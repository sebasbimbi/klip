<div align="center">

# 📋 Klip

**The clipboard manager for vibe coders — native to Mac.**
Everything you copy while building with AI — code, errors, screenshots, prompts and keys — one shortcut away.

Text & image history · **native capture + annotation** · **fast OCR capture** · **voice & video → text** · **meeting notes (mic + system audio, no bot)** (on-device, or OpenAI/Gemini) · **copy as code block / for WhatsApp / for email** · **always-paste-clean** · **encrypted credential manager**. Lives in the menu bar: light, fast and private.

🆓 Free & open source (MIT) · 🔒 No telemetry · 🍎 Native Swift (no Electron)

<br/>

<img src="docs/klip-preview.gif" alt="Klip in action: snip an area of the screen, have it appear in Klip and pull its text with OCR; and record a voice note that transcribes itself" width="500"/>

<sub>Snip an area → it lands in Klip → pull the text (OCR) · and record a voice note that transcribes itself.</sub>

</div>

> ### 🖥️ For now, Mac only
> Klip is a **native macOS** app and requires **macOS 14 (Sonoma) or later** (Apple Silicon or Intel).
> A **Windows 🪟 version is planned**. Your data stays on your machine.

---

## 🤔 Why Klip if you code with AI?

"Vibe coding" is a constant back-and-forth of copy-paste between your editor and tools like Claude, ChatGPT or Cursor: code snippets, error messages, UI screenshots, terminal output, dictated prompts and API keys. Klip is built for that flow:

- **Never lose a snippet** — everything you copy lands in a searchable history.
- **Snip an error and annotate it** (arrows, text, highlighter) without leaving the keyboard, and it lands in Klip ready to paste into the AI.
- **Pull the text out of a screenshot** (OCR) to paste a log that was stuck in an image.
- **Copy as a code block** (` ``` `) to paste cleanly into a chat.
- **Dictate a prompt** and Klip transcribes it to text.
- **Bundle several clips** (screenshots + text) into a **PDF or ZIP** to upload as context in one shot.
- **Keep your API keys** detected, **encrypted at rest**, named and searchable.

## ✨ Features

### 📋 Clipboard
- **Automatic history** of **text and images/screenshots**.
- **Instant search** with **match highlighting** + **keyboard navigation** (↑/↓, Enter, `⌘↩` copy-as-code, `Esc`).
- **Type filters** (text · **links** · images · voice · credentials · favorites); a type chip only shows up once you actually have items of that type.
- **Auto-paste** into the active app · **Favorite** ⭐ · **Delete** 🗑️ (with confirmation on clear-all).
- **Readable date** on every item: *"Tue, Jul 04 · 10:43"*, *"Today"*, *"Yesterday"*.

### 📸 Native capture + annotation (Klip Snap)
- Global shortcut **`⌥⇧D`** → snip a region of the screen (drag a selection over a dimmed *freeze-frame*, with a live dimension badge and correct Retina scale). Uses **ScreenCaptureKit** (not the deprecated API).
- Built-in **annotation editor**: **select & move any annotation**, pencil, line, **arrow**, rectangle, ellipse, highlighter, **editable/movable/resizable text**, **blur/pixelate**, **spotlight**, **numbered counter badges**, color, stroke width, **undo/redo** and **pinch zoom** with a live percentage readout.
- When you're done, the annotated capture lands in **history** (ready for **OCR** and search) and on the clipboard.
- Also from the 📷 button in the panel or the menu-bar menu.
- **Fast text capture** (`⌥⇧F`): snip a region and its **text is OCR'd straight to the clipboard** (and history) — skips the editor when you just need the text.
- **Upload audio/video** (`⌥⇧O`): drop or pick files; each one's transcription appears right in the window as it finishes, with a per-upload language override.

### 🖼️ Images
- Large preview (cached thumbnails for smooth scrolling), **open large** and **save to file**.
- **OCR** (extract text from an image) with Apple's **Vision** engine — free and on-device. Perfect for pulling the text out of a log or error you copied as a screenshot.

### 🎙️ Voice & video → text
- **Record** (`⌥⇧R`) or **upload files** (`⌥⇧O`): audio (m4a, mp3, wav, **WhatsApp .opus**, ogg, flac…) **and video** (mp4, mov, mkv, webm…) — Klip **extracts the video's audio track** and transcribes it.
- Transcribes **in the background** — you can record another one right away.
- **The original audio is kept** with **duration** and a **progress bar**: play it (▶) or reveal it in Finder, and **retry (↻)** if a transcription fails. (Videos aren't stored — only their text.)
- **Pick the language per upload**, and clear per-file errors: DRM-protected video, no audio track, too large for cloud.

### 🎧 Meeting notes — no bot, no cloud
- Press **`⌥⇧M`** when you join a virtual meeting (Zoom, Meet, Teams, FaceTime — any app): Klip records **your microphone AND the system audio** (the other participants). **No bot joins the call**; nobody sees a recorder.
- When you stop (**`⌥⇧M`** again, or automatically after **15 minutes of silence**), both tracks are **mixed locally** and transcribed. With the **on-device engine**, each track is transcribed separately and interleaved chronologically as a **"Me:" / "Them:"** labeled transcript.
- The note lands in history named **"Meeting — Jul 9, 2:03 PM"** (renamable), with the **mixed audio kept and playable** (▶) and retry (↻) if transcription fails.
- **Everything stays on your Mac** — unlike cloud meeting tools, the audio is never uploaded anywhere. Uses the Screen Recording permission Klip already has for captures.

### 🤖 AI: you pick the engine
- **On-device (default)** — transcribe **fully offline with Whisper** ([WhisperKit](https://github.com/argmaxinc/WhisperKit) on Core ML): **no API key, no audio ever leaves your Mac.** Pick the model (Tiny / Base / Small / Large v3 Turbo); it downloads once on first use, then runs offline.
- **OpenAI** or **Google Gemini** — optional cloud engines if you'd rather use them; bring your own key. For **Gemini** you can pick the model (`gemini-flash-latest`, `-flash-lite-latest`, `-pro-latest`, `2.5-flash`, `2.5-pro`); for **OpenAI**, `gpt-4o-mini-transcribe` or `whisper-1`.
- **Dictation language** is selectable (and auto-detect), so transcription is natural in your language.
- **Context words** — list names, brands or jargon (e.g. `GitHub, React, Supabase, API, webhook`) so the transcriber spells your proper nouns correctly. Works for the on-device engine too.

### 🧰 Built for pasting into AI
- **Copy as code block** — wraps the text in ` ``` ` (with a detected language tag) to paste cleanly into a chat (`⌘↩` on the selected item).
- **Copy for WhatsApp / for email** — reformats a clip so it pastes cleanly: WhatsApp markup (`*bold*`, `_italic_`, • bullets) or rich email text (renders bold/italic, keeps the paragraph spacing).
- **Always paste clean** (on by default) — a copy from a rich source (e.g. an AI chat on a dark theme) is stored as clean text that keeps **bold/italic + emojis** but drops the dark background, colours and fonts.
- **Copy as Markdown** for a single item, or export the **whole history** to Markdown.
- **Save text as a file** (`.txt`/`.md`) to drag into a tool when the chat won't let you paste it.
- **Batch multi-select** (☑️ icon in the header): mark several clips and…
  - **Combine them into a PDF** (one page per screenshot/text) to upload a full context at once.
  - **Export them as a ZIP** (the chosen subset, separate from the backup ZIP).
  - **Assign them to a collection**.

### 🏷️ Organization
- **Collections** — group related clips (e.g. the context of one task) and filter them with a chip.
- **Name any item** and find it by that name (great for your credentials).
- **Type-aware actions**: **open links** 🔗 and a **color swatch** for hex values (`#1E90FF`).
- **Mini credential manager** 🔑: detects tokens and API keys when you copy them and **encrypts them at rest** (AES-256-GCM, key in the macOS Keychain — so `items.json` and backups never hold the secret in the clear). Shown **masked** (👁 to reveal/copy), with their own filter, and **never auto-pasted** (copied so you paste them by hand).

### 💾 Backup
- **Export / import** the whole history (images and audio included) as a `.zip`. **Never** includes your API keys.

### 🌍 Languages
- Interface available in **English, Spanish, French, German, Italian, Portuguese, Chinese (Simplified) and Japanese**, switchable in Preferences.

### 🔒 Privacy & system
- All **local** with `0600` permissions · **no telemetry** · ignores passwords and lets you **exclude apps**.
- **Stable signing**: macOS asks for permissions (microphone, screen recording…) **once** and remembers them across updates.
- **Launch at login** optional.

## ⌨️ Shortcuts

Global shortcuts use **⌥⇧ (Option+Shift)** + a letter, grouped by function on the left of the keyboard — comfortable to hold and rarely claimed by other apps (so the global hotkey actually fires; `⌘⇧`+letter clashes with VS Code / browsers):

| Shortcut | Action |
|---|---|
| `⌥⇧E` | Open the history panel (**E**dit history) |
| `⌥⇧R` | **R**ecord / stop a voice note |
| `⌥⇧D` | Capture a region and annotate it (**D**raw — Klip Snap) |
| `⌥⇧F` | **F**ast text capture: snip a region → OCR straight to the clipboard, no editor |
| `⌥⇧O` | **O**pen the "upload audio/video to transcribe" window |
| `⌥⇧M` | Record a **m**eeting (mic + system audio) — press again to stop |
| `↑` / `↓` · `Enter` | Navigate and pick an item |
| `⌘↩` | Copy the selected item as a code block (``` ```) |
| `Esc` | Close the panel |
| `⌘⇧⌃4` | *(macOS)* screenshot to clipboard → also lands in Klip |

> All six global shortcuts are **configurable** in Preferences › Shortcuts.

## 🧰 Requirements

- **macOS 14 (Sonoma) or later** — tested on macOS 26, Apple Silicon.
- **Xcode Command Line Tools** (no full Xcode needed):
  ```bash
  xcode-select --install
  ```
- *(Optional)* An **OpenAI or Google Gemini API key** for voice notes. It's stored in a **local file**, never in the code or the repository.

## ⚡ Quick install

```bash
git clone https://github.com/tamibot/klip.git klip
cd klip
./install.sh
```

That builds Klip, signs it, copies it to `/Applications`, launches it and registers launch-at-login.
You'll see the 📋 icon in the menu bar. Press **`⌥⇧E`** to open the history.

> On first run, `install.sh` creates a **local signing certificate** (`Klip Code Signing`) in your Keychain so the signature is stable. That way macOS asks for permissions (microphone, accessibility, screen recording) **once** and remembers them across updates, instead of re-prompting on every reinstall. It's local and reversible (you can delete it from *Keychain Access*).
>
> macOS may ask you to approve the "login item" in *Settings › General*. For **auto-paste**, grant Accessibility when prompted (Klip menu → *Enable auto-paste…*). The first capture with `⌥⇧D` will ask for **Screen Recording**.

### Build without installing

```bash
./build.sh        # produces Klip.app in the project folder
open Klip.app
```

### Development

```bash
swift build       # debug build
swift run Klip    # run directly
```

## 🚀 Usage (a vibe coder's typical flow)

1. **Copy anything** while you code (code, terminal output, an error message). It all lands in Klip.
2. **`⌥⇧E`** → open the panel. Type to **search**; use **↑/↓ + Enter** or **click** to pick an item (it auto-pastes if you enabled auto-paste).
3. To paste code into an AI chat, hover the row and hit **`</>`** (*copy as code block*).
4. **`⌥⇧D`** → snip the error/UI, annotate it (arrow + text) and it lands in Klip. Or **`⌥⇧F`** to snip a region and get its **text via OCR straight to the clipboard** (no editor).
5. 🎙️ **`⌥⇧R`** to dictate a prompt; on stop, it transcribes and lands in the history.
6. ☑️ Turn on **multi-select** in the header, mark several screenshots/texts and hit **PDF** or **ZIP** to upload them as context to the AI in one go.
7. `Esc` or a click outside closes the panel.

## ⚙️ Configuration

Open **Preferences** (`⌘,` from the Klip menu):

- **Shortcuts** — record the combinations you prefer (history, voice, annotate, fast-OCR, upload, meeting). Defaults are `⌥⇧E / R / D / F / O / M`.
- **Voice transcription** — pick the **provider** (on-device, OpenAI or Google Gemini), **model**, language and **context words**.
- **OpenAI / Google Gemini** — paste the API key for the provider you chose (only that section shows). Stored in a local `0600` file.
- **History** — maximum number of items.
- **Privacy** — ignore passwords/sensitive content, exclude apps, **always-paste-clean** toggle.
- **Language** — interface language.

## 🔐 Privacy

- **Local-first**: your history lives in `~/Library/Application Support/Klip/` (`items.json` + `images/` + `audio/`). Nothing leaves your Mac except the audio **you** send to the AI provider you choose (OpenAI or Gemini) to transcribe.
- **No secrets in the repo**: API keys are stored in **local files** (`openai.key`, `gemini.key`, `0600` permissions), never in the code or the repository.
- The **history** (`items.json`), **images** and voice-note **audio** are stored only on your Mac with `0600` permissions (`0700` folders). Credentials are additionally **encrypted at rest** (AES-256-GCM; the key lives in the macOS Keychain), so the secret is never written to `items.json` or backups in the clear.
- **No telemetry**.
- Klip **ignores** content marked as concealed by password managers, and you can **exclude** specific apps.
- **Tokens/API keys** you copy are detected, **encrypted at rest**, and shown **masked** (🔑 filter).

## 🏗️ Architecture

| File | Responsibility |
|---|---|
| `main.swift` / `AppDelegate.swift` | Startup, menu bar, Edit menu, global shortcuts. |
| `ClipboardManager.swift` | Clipboard monitoring, history, source, privacy, collections. |
| `ClipboardItem.swift` / `Storage.swift` | Model and persistence (JSON + images + audio + PDF/ZIP). |
| `PanelController.swift` / `HistoryView.swift` | HUD panel and the UI (SwiftUI), multi-select and export. |
| `SnapController.swift` / `ScreenCapturer.swift` | Native capture flow (ScreenCaptureKit). |
| `CaptureOverlayController.swift` | Region-selection overlay (freeze-frame + badge). |
| `SnapEditorController.swift` / `AnnotationCanvasView.swift` / `AnnotationModel.swift` | Annotation editor and annotation model. |
| `HotKey.swift` / `Settings.swift` | Shortcuts (Carbon) and preferences (UserDefaults). |
| `OCR.swift` | Text extraction with Vision (on-device). |
| `SnapController.swift` | Capture flow incl. **fast OCR-to-clipboard** mode (`⌥⇧F`). |
| `CredentialCrypto.swift` / `CredentialDetector.swift` | Credential detection + **AES-256-GCM encryption at rest** (Keychain key). |
| `RichText.swift` | Rich clipboard text → clean Markdown (keeps bold/italic + emojis) for *always-paste-clean*. |
| `UploadView.swift` | "Upload audio/video to transcribe" window with live per-file results. |
| `Recorder.swift` / `AudioPlayer.swift` | Recording, background transcription and voice-note playback. |
| `MediaAudioExtractor.swift` | Extracts a **video's** audio track (AVAssetReader→Writer, 16 kHz mono AAC) for transcription. |
| `MeetingRecorder.swift` | **Meeting notes**: mic + system audio (ScreenCaptureKit), local mix, Me/Them dual-track transcription. |
| `OpenAIClient.swift` / `GeminiClient.swift` / `LocalTranscriber.swift` | Transcription via OpenAI, Google Gemini or on-device WhisperKit. |
| `L10n.swift` | Lightweight localization (8 languages). |
| `SecretStore.swift` | API keys in local `0600` files (`openai.key`, `gemini.key`). |
| `Paster.swift` / `LoginItem.swift` | Auto-paste and launch-at-login. |
| `Markdownify.swift` | Markdown conversion and export (local). |

## 🗺️ Roadmap

**Klip is Mac-only for now.** Next up:

- [ ] **Windows version** 🪟 — the big next step.
- [ ] More type-aware quick actions (emails, numbers).
- [ ] Translate / summarize / clean up text with AI.
- [ ] Favorites sync · optional sync between Macs.
- [ ] Developer ID signing + notarization for warning-free distribution.

**Already available:** text+image history · native capture + annotation (Klip Snap) · **fast OCR capture** (`⌥⇧F`) · OCR · **on-device** voice notes (WhisperKit) plus OpenAI/Gemini, **upload audio & video** with per-file language · **meeting notes** (mic+system, Me/Them, on-device), saved audio and retry · copy as code block / **for WhatsApp / for email** · **always-paste-clean** · **encrypted credentials (AES-256-GCM)** · **links filter** · multi-select + combine into PDF/ZIP · collections · name and search · color swatch · Markdown · export/import · stable signing · 8 UI languages.

## 🤝 Contributing

Contributions are welcome! Open an *issue* or a *pull request*. The project builds with just the Command Line Tools (no Xcode), so it's easy to get started. Code and comments are in English to keep the project approachable for everyone.

## 👤 Author

Created and maintained by **Martin Velasco O.** — [@tamibot](https://github.com/tamibot).

## 📄 License

[MIT](LICENSE) © 2026 Martin Velasco O. — use it, modify it and share it freely.
