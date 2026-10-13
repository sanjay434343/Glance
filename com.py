
from pathlib import Path
from PIL import Image
import os

# Input and output folders
SOURCE_DIR = Path(r"D:\Glance\glance\assets\icons")
OUTPUT_DIR = SOURCE_DIR / "compressed_512"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

IMAGES = [
    "all.png",
    "ap_activity.png",
    "copied_text.png",
    "documens.png",
    "images.png",
    "location.png",
    "notification.png",
    "screenshot.png",
    "website.png",
]

MAX_SIZE = (512, 512)

# Lower value = stronger JPEG/WebP compression.
# PNG uses palette quantization instead of a JPEG quality setting.
PNG_COLORS = 32


def compress_image(filename):
    source = SOURCE_DIR / filename
    destination = OUTPUT_DIR / filename

    if not source.exists():
        print(f"[MISSING] {filename}")
        return

    try:
        with Image.open(source) as img:
            img.load()
            original_size = source.stat().st_size

            # Preserve aspect ratio; never stretch the image.
            img.thumbnail(MAX_SIZE, Image.Resampling.LANCZOS)

            # Preserve transparency while reducing the color palette.
            rgba = img.convert("RGBA")
            alpha = rgba.getchannel("A")

            # Quantize RGB colors; restore original alpha channel.
            rgb = rgba.convert("RGB").quantize(
                colors=PNG_COLORS,
                method=Image.Quantize.MEDIANCUT,
                dither=Image.Dither.NONE,
            )

            rgb = rgb.convert("RGBA")
            rgb.putalpha(alpha)

            # Save optimized PNG to a separate folder.
            rgb.save(
                destination,
                format="PNG",
                optimize=True,
                compress_level=9,
            )

            new_size = destination.stat().st_size
            saved = (
                (original_size - new_size) / original_size * 100
                if original_size else 0
            )

            print(
                f"[OK] {filename}\n"
                f"     Dimensions: {img.width}x{img.height}\n"
                f"     Size: {original_size / 1024:.1f} KB"
                f" -> {new_size / 1024:.1f} KB\n"
                f"     Change: {saved:.1f}%\n"
            )

    except Exception as exc:
        print(f"[ERROR] {filename}: {exc}")


if __name__ == "__main__":
    for name in IMAGES:
        compress_image(name)

    print(f"\nCompleted. Output folder:\n{OUTPUT_DIR}")
