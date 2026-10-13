<div align="center">

<img src="assets/images/logo.png" alt="Glance Logo" width="130" height="130"/>

# Glance

### Your Life. Fully Searchable. Completely Private.

**An open-source on-device AI memory engine for Android that continuously captures, indexes, and understands your digital life — powered by Google Gemma 2B & MediaPipe, with zero cloud dependency.**

<br/>

[![Latest Release](https://img.shields.io/github/v/release/sanjay434343/Glance?color=3478F6&label=Release&style=for-the-badge&logo=github)](https://github.com/sanjay434343/Glance/releases)
[![Stars](https://img.shields.io/github/stars/sanjay434343/Glance?color=F59E0B&style=for-the-badge&logo=apachespark)](https://github.com/sanjay434343/Glance/stargazers)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-8.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://android.com)
[![Gemma AI](https://img.shields.io/badge/AI-Gemma_2B_On--Device-4285F4?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev/gemma)
[![Privacy](https://img.shields.io/badge/Privacy-100%25_Offline-00C896?style=for-the-badge&logo=shield)](https://github.com/sanjay434343/Glance)
[![License](https://img.shields.io/badge/License-MIT-7c3aed?style=for-the-badge)](LICENSE)

<br/>

### 📲 [Download Latest APK (v1.0.0)](https://github.com/sanjay434343/Glance/releases/latest)

[![Download arm64-v8a](https://img.shields.io/badge/Download-arm64--v8a_(Recommended)-3478F6?style=for-the-badge&logo=android&logoColor=white)](https://github.com/sanjay434343/Glance/releases/latest)
[![Download armeabi-v7a](https://img.shields.io/badge/Download-armeabi--v7a_(32--bit)-6B7280?style=for-the-badge&logo=android&logoColor=white)](https://github.com/sanjay434343/Glance/releases/latest)
[![Download x86_64](https://img.shields.io/badge/Download-x86__64_(Emulator)-6B7280?style=for-the-badge&logo=android&logoColor=white)](https://github.com/sanjay434343/Glance/releases/latest)

<br/>

[**⚡ The 10-Second Pitch**](#-why-glance) &nbsp;•&nbsp; [**📸 Screenshots**](#-screenshots) &nbsp;•&nbsp; [**✨ Features**](#-features) &nbsp;•&nbsp; [**🏗️ Architecture**](#️-architecture) &nbsp;•&nbsp; [**🚀 Quick Start**](#-quick-start) &nbsp;•&nbsp; [**🔒 Privacy**](#-privacy--security)

</div>

---

## ⚡ Why Glance? (The 10-Second Pitch)

Ever remember reading a crucial note, seeing an address in a screenshot, or copying a verification code yesterday — only to spend 15 minutes fruitlessly searching through 10 different apps?

**Glance solves this silently in the background.** It creates a local, chronological memory graph of your digital life. Ask it anything in natural language, and your local AI finds it in milliseconds.

### 🥊 How Glance Compares

| Feature | 🛡️ **Glance** | 🪟 Microsoft Recall | ☁️ Cloud AI / Rewind |
| :--- | :---: | :---: | :---: |
| **Privacy & Telemetry** | **100% On-Device, Zero Tracking** | Questionable / Windows Cloud Sync | Cloud Server Uploads |
| **Local AI Engine** | **Google Gemma 2B (MediaPipe)** | Proprietary NPU Copilot | Remote Cloud APIs |
| **Offline Operation** | **100% Fully Offline** | Hybrid Cloud | Requires Active Internet |
| **Source Code** | **Open Source (MIT)** | Closed Source | Proprietary |
| **Performance** | **20-Item Batch Lazy Loading (60 FPS)** | Heavy Resource Spikes | Battery & Data Heavy |
| **Platform** | **Android 8.0+** | Windows 11 Copilot+ PCs only | macOS / iOS |

---

## 📸 Screenshots

<div align="center">
<table>
<tr>
<td align="center"><b>🏠 Home</b></td>
<td align="center"><b>⏱️ Timeline</b></td>
<td align="center"><b>🗂️ Collection</b></td>
</tr>
<tr>
<td><img src="assets/images/home.png" width="230" style="border-radius:18px"/></td>
<td><img src="assets/images/timeline.png" width="230" style="border-radius:18px"/></td>
<td><img src="assets/images/collection.png" width="230" style="border-radius:18px"/></td>
</tr>
<tr>
<td align="center"><b>⚙️ Settings</b></td>
<td align="center"><b>➕ Capture</b></td>
<td align="center"><b>🔍 Search & AI Model</b></td>
</tr>
<tr>
<td><img src="assets/images/settings.png" width="230" style="border-radius:18px"/></td>
<td><img src="assets/images/capture.png" width="230" style="border-radius:18px"/></td>
<td><img src="assets/images/search.png" width="230" style="border-radius:18px"/></td>
</tr>
</table>
</div>

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🧠 On-Device Gemma 2B Intelligence
- **Google Gemma 3N E2B Int4** powered by MediaPipe
- Native GPU hardware acceleration (Vulkan / OpenCL)
- Automatic CPU XNNPACK fallback
- Token-by-token streaming inference with **0 cloud dependency**

</td>
<td width="50%">

### 🔎 Hybrid RAG Retrieval Engine
- **SQLite FTS5** lexical indexing with BM25 ranking
- Vector & semantic search combined
- Recency decay & temporal windowing
- Intent classification with smart query expansion

</td>
</tr>
<tr>
<td width="50%">

### ⚡ 20-Item Batch Lazy Loading
- Rock-solid 60 FPS scrolling even with thousands of memories
- Paginated in 20-item lazy-loaded batches
- Guarded isolate extraction prevents memory spikes
- Capped OCR & document analysis prevents ANR lockups

</td>
<td width="50%">

### 📱 360° Device Data Capture
- **App Usage & Screen Time** via Android `UsageStats`
- **Screenshots & Photos** with Google ML Kit OCR
- **Clipboard History** with entity parsing (OTPs, URLs, emails)
- **Notifications & Calls** captured and indexed locally

</td>
</tr>
<tr>
<td width="50%">

### 🗂️ Smart & Custom Collections
- Auto-organized categories: Screenshots, Photos, Clipboard, Documents, App Usage, Notifications
- Custom user-defined tags and folders
- Chronological timeline views (Days / Weeks / Months)

</td>
<td width="50%">

### 🔒 Air-Gapped by Design
- No accounts, no subscriptions, no tracking
- Cryptographic SHA-256 fingerprint deduplication
- All SQLite databases isolated in Android app sandbox
- Does not contain a single analytics SDK

</td>
</tr>
</table>

---

## 🏗️ Architecture

```mermaid
graph TD
    subgraph Ingestion["📱 Native Android Ingestion"]
        A["MediaStore (Screenshots & Photos)"]
        B["AppMonitor (Native UsageStats)"]
        C["Clipboard Listener"]
        D["GlanceNotification Service"]
        E["Documents & PDFs"]
    end

    subgraph Pipeline["⚙️ Processing Pipeline (100% Local)"]
        F["ContentPipeline Coordinator"]
        G["Google ML Kit OCR Engine"]
        H["SHA-256 Deduplication"]
        I["250-Token Chunking"]
        J["Smart Entity Extractor"]
    end

    subgraph Storage["💾 Sandbox Storage"]
        K[("SQLite DB + FTS5 BM25 Index")]
    end

    subgraph AI["🧠 Local AI Core"]
        L["MediaPipe LLM Bridge (GPU / Vulkan)"]
        M["Gemma 2B Int4 Model"]
    end

    subgraph Presentation["🖥️ User Experience"]
        N["HybridRetriever (BM25 + Semantic)"]
        O["Ask AI Dialog & Search Screen"]
        P["20-Batch Lazy-Loaded Timeline & Grid"]
    end

    A & B & C & D & E --> F
    F --> G --> H --> I --> J --> K
    K --> N
    N --> L --> M --> O
    K --> P
```

---

## 🚀 Quick Start

### 1. Download Prebuilt APK (Easiest)
Download the `.apk` directly from [GitHub Releases](https://github.com/sanjay434343/Glance/releases/latest):
- **`app-arm64-v8a-release.apk`**: Most modern Android smartphones (recommended).
- **`app-armeabi-v7a-release.apk`**: Older 32-bit Android phones.
- **`app-x86_64-release.apk`**: Emulators and ChromeOS devices.

### 2. Build From Source

#### Prerequisites:
- **Flutter SDK**: `^3.12`
- **Dart SDK**: `^3.12`
- **Android SDK**: API 26+ (Android 8.0+, recommended API 30+)
- **JDK**: 17

```bash
# 1. Clone the repository
git clone https://github.com/sanjay434343/Glance.git
cd Glance

# 2. Install Flutter packages
flutter pub get

# 3. Build optimized release APKs
flutter build apk --split-per-abi

# 4. Or run directly on your connected device
flutter run --release
```

---

## 🔒 Privacy & Permissions

Glance requests the following permissions purely to index your local activity. **No data ever leaves your device:**

| Permission | Purpose |
| :--- | :--- |
| `PACKAGE_USAGE_STATS` | Measure active app foreground duration and screen time |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | Privately index notification text and message titles |
| `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` | Discover local screenshots, images, and documents |
| `FOREGROUND_SERVICE` | Keep background OCR and memory indexing responsive |

---

## 🗺️ Roadmap

- [x] On-device Gemma 2B via MediaPipe GPU inference
- [x] SQLite FTS5 BM25 Hybrid RAG
- [x] 20-item batch lazy loading & lag-free document extraction
- [x] App usage, notification, and screenshot ingestion
- [ ] Biometric lock & encrypted database option
- [ ] Support for lightweight Llama 3.2 / Qwen 2.5 models
- [ ] F-Droid & IzzyOnDroid release packages
- [ ] Export memory graph as Markdown / JSON

---

## 🤝 Contributing

Contributions make open-source amazing!
1. **Fork** the repo
2. **Create** your feature branch: `git checkout -b feat/amazing-feature`
3. **Commit** your changes: `git commit -m 'feat: Add amazing feature'`
4. **Push** to the branch: `git push origin feat/amazing-feature`
5. **Open a Pull Request**

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for more information.

---

<div align="center">

<img src="assets/images/logo.png" alt="Glance" width="44"/>

### **Built with ❤️ using Flutter & Google Gemma**

**If you love privacy and on-device AI, please give Glance a ⭐ — it helps the project grow!**

</div>
