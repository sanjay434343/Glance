#!/usr/bin/env python3
"""
chat_stream.py - terminal chatbot that does NOT keep the model in RAM.

For every message you send:
    1. the model is streamed in from the SSD (mmap, nothing is pinned)
    2. the reply is streamed to your screen token by token
    3. the model is released, so RAM drops back to almost nothing

Your conversation history is just text, so it survives the unloading.

Install:
    pip install psutil
    pip install llama-cpp-python --prefer-binary --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu

Run:
    python chat_stream.py --model "D:\\Glance\\glance\\Falcon3-1B-Instruct-Q6_K_L.gguf"

Useful options:
    --keep-alive 30    keep the model loaded for 30s after a reply (faster follow-ups),
                       then unload it automatically. Default 0 = unload after every reply.
    --n-ctx 2048       context window (also the biggest RAM cost after the weights)
    --max-tokens 256   max length of each reply

In chat:  /reset  clear history   /ram  show memory   /system <text>  set persona   /exit  quit
"""
import argparse
import gc
import os
import sys
import threading
import time


def rss_mb():
    try:
        import psutil
        return psutil.Process().memory_info().rss / 1e6
    except ImportError:
        import resource
        v = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        return v / 1e6 if sys.platform == "darwin" else v / 1e3


# ------------------------------------------------------------ fake model (self-test)


class FakeLlama:
    """Stand-in model used by --selftest so the load/unload logic can be tested
    without a real GGUF file. It allocates real memory, then frees it on close()."""

    def __init__(self, **kw):
        self.blob = bytearray(300 * 1024 * 1024)
        for i in range(0, len(self.blob), 4096):
            self.blob[i] = 1                      # touch pages so they count as RSS

    def tokenize(self, b, add_bos=False):
        return b.split()

    def create_chat_completion(self, messages, max_tokens, temperature, stream):
        for w in ("This ", "is ", "a ", "fake ", "streamed ", "reply. "):
            time.sleep(0.05)
            yield {"choices": [{"delta": {"content": w}}]}

    def close(self):
        self.blob = None


# ----------------------------------------------------------------------- model host


class ModelHost:
    """Loads the model on demand and unloads it again. Thread-safe."""

    def __init__(self, args):
        self.args = args
        self.llm = None
        self.lock = threading.RLock()
        self.last_used = time.time()

    def load(self):
        """Returns seconds spent loading (0 if it was already loaded)."""
        with self.lock:
            if self.llm is not None:
                return 0.0
            t0 = time.time()
            if self.args.selftest:
                self.llm = FakeLlama()
            else:
                try:
                    from llama_cpp import Llama
                except ImportError:
                    sys.exit("Missing package. Run:  pip install llama-cpp-python")
                self.llm = Llama(
                    model_path=self.args.model,
                    n_ctx=self.args.n_ctx,
                    n_threads=self.args.threads,
                    n_gpu_layers=0,
                    use_mmap=True,       # weights are paged in from SSD on demand
                    use_mlock=False,     # never pinned, the OS can evict at will
                    verbose=False,
                )
            return time.time() - t0

    def unload(self):
        with self.lock:
            if self.llm is None:
                return False
            try:
                self.llm.close()
            except Exception:
                pass
            self.llm = None
            gc.collect()
            return True


# ------------------------------------------------------------------------ chat logic


def count_tokens(llm, text):
    try:
        return len(llm.tokenize(text.encode("utf-8"), add_bos=False))
    except Exception:
        return len(text) // 3


def trim_history(llm, system, history, n_ctx, max_tokens):
    """Drop the oldest messages until the prompt fits in the context window."""
    budget = n_ctx - max_tokens - 64
    def total():
        return count_tokens(llm, system) + sum(count_tokens(llm, m["content"]) + 8 for m in history)
    dropped = 0
    while len(history) > 1 and total() > budget:
        history.pop(0)
        dropped += 1
    return dropped


def stream_reply(llm, messages, args):
    """Yield text pieces of the reply."""
    try:
        for chunk in llm.create_chat_completion(
                messages=messages, max_tokens=args.max_tokens,
                temperature=args.temperature, stream=True):
            piece = chunk["choices"][0]["delta"].get("content", "")
            if piece:
                yield piece
    except Exception:
        # model without a chat template: plain prompt fallback
        prompt = "\n".join(f"{m['role'].capitalize()}: {m['content']}" for m in messages)
        prompt += "\nAssistant:"
        for chunk in llm(prompt, max_tokens=args.max_tokens, stream=True,
                         temperature=args.temperature, stop=["\nUser:"]):
            yield chunk["choices"][0]["text"]


def idle_watcher(host, keep_alive, stop_evt):
    """Unload the model after `keep_alive` seconds without use."""
    while not stop_evt.is_set():
        time.sleep(0.5)
        if keep_alive <= 0 or host.llm is None:
            continue
        if time.time() - host.last_used < keep_alive:
            continue
        if host.lock.acquire(blocking=False):      # never interrupt a running reply
            try:
                if host.llm is not None and host.unload():
                    sys.stdout.write(f"\n[idle {keep_alive:.0f}s: model unloaded, RAM {rss_mb():.0f} MB]\nYou: ")
                    sys.stdout.flush()
            finally:
                host.lock.release()


def chat_turn(host, system, history, user_text, args):
    ram_before = rss_mb()
    with host.lock:
        load_s = host.load()
        ram_loaded = rss_mb()
        history.append({"role": "user", "content": user_text})
        dropped = trim_history(host.llm, system, history, args.n_ctx, args.max_tokens)
        messages = [{"role": "system", "content": system}] + history

        sys.stdout.write("Bot: ")
        sys.stdout.flush()
        t0, n, reply, peak = time.time(), 0, [], ram_loaded
        for piece in stream_reply(host.llm, messages, args):
            sys.stdout.write(piece)
            sys.stdout.flush()
            reply.append(piece)
            n += 1
            peak = max(peak, rss_mb())
        gen_s = time.time() - t0
        history.append({"role": "assistant", "content": "".join(reply).strip()})
        host.last_used = time.time()

        unloaded = False
        if args.keep_alive <= 0:
            unloaded = host.unload()
    ram_after = rss_mb()

    print(f"\n  [load {load_s:.1f}s | {n / max(gen_s, 1e-9):.1f} tok/s | "
          f"RAM: before {ram_before:.0f} -> peak {peak:.0f} -> after {ram_after:.0f} MB"
          f"{' | model unloaded' if unloaded else ' | model kept loaded'}"
          f"{f' | trimmed {dropped} old msgs' if dropped else ''}]")


def main():
    ap = argparse.ArgumentParser(description="Chatbot that streams the model from SSD per message")
    ap.add_argument("--model", help="path to a .gguf file")
    ap.add_argument("--n-ctx", type=int, default=2048)
    ap.add_argument("--max-tokens", type=int, default=256)
    ap.add_argument("--temperature", type=float, default=0.7)
    ap.add_argument("--threads", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--keep-alive", type=float, default=0,
                    help="seconds to keep the model loaded after a reply (0 = unload every time)")
    ap.add_argument("--system", default="You are a helpful, concise assistant.")
    ap.add_argument("--selftest", action="store_true", help="test the load/unload logic with a fake model")
    args = ap.parse_args()

    if not args.selftest:
        if not args.model:
            sys.exit("Give a model:  --model path\\to\\model.gguf")
        if not os.path.exists(args.model):
            sys.exit(f"File not found: {args.model}")

    host = ModelHost(args)
    system, history = args.system, []
    stop_evt = threading.Event()
    threading.Thread(target=idle_watcher, args=(host, args.keep_alive, stop_evt), daemon=True).start()

    print(f"Chat ready. Model is NOT loaded yet (RAM {rss_mb():.0f} MB). "
          f"Mode: {'unload after every reply' if args.keep_alive <= 0 else f'keep {args.keep_alive:.0f}s'}")
    print("Commands: /reset  /ram  /system <text>  /exit\n")

    scripted = ["hello", "tell me more", "/exit"] if args.selftest else None
    while True:
        try:
            user = scripted.pop(0) if scripted else input("You: ").strip()
            if scripted is not None:
                print(f"You: {user}")
        except (EOFError, KeyboardInterrupt):
            break
        if not user:
            continue
        if user == "/exit":
            break
        if user == "/reset":
            history.clear()
            print("[history cleared]")
            continue
        if user == "/ram":
            print(f"[RAM {rss_mb():.0f} MB | model {'loaded' if host.llm else 'not loaded'}]")
            continue
        if user.startswith("/system "):
            system = user[8:].strip()
            history.clear()
            print("[system prompt set, history cleared]")
            continue
        chat_turn(host, system, history, user, args)

    stop_evt.set()
    host.unload()
    print("Bye.")


if __name__ == "__main__":
    main()