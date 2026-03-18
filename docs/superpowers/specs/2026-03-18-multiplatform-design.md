# OpenOats Multiplatform Design Spec
**Date:** 2026-03-18
**Status:** Approved

## Overview

Migrate OpenOats from a split Mac-only Swift app + minimal Windows Tauri stub into a fully unified, feature-complete cross-platform app. The target architecture is a shared Rust core library (`openoats-core`) powering a single Tauri app with a shared React/TypeScript UI on both Windows and macOS.

The migration follows an incremental strategy: keep the Mac Swift app shipping while building Windows to full feature parity, then replace the Mac Swift app with the Tauri app.

---

## Architecture

### Repository Structure

```
OpenOats (monorepo)
├── crates/
│   └── openoats-core/           # Rust library — all business logic, no Tauri dependency
│       └── src/
│           ├── lib.rs
│           ├── models.rs         # Utterance, Speaker, Session, Suggestion, ConversationState, etc.
│           ├── settings.rs       # AppSettings (cross-platform JSON persistence via dirs crate)
│           ├── keychain.rs       # Secret storage (keyring crate) — openRouterApiKey, voyageApiKey, openAIEmbedApiKey
│           ├── audio/
│           │   ├── mod.rs        # AudioCaptureService + MicCaptureService traits (futures::Stream<Item=Vec<f32>>)
│           │   └── cpal_mic.rs   # Cross-platform mic capture (CPAL) with cpal device enumeration
│           ├── transcription/
│           │   ├── mod.rs
│           │   ├── vad.rs        # Energy-based VAD — unified: RMS threshold 0.005, chunk 1600 samples, 5 silence chunks
│           │   ├── whisper.rs    # WhisperManager (whisper-rs wrapper, language from settings)
│           │   ├── streaming_transcriber.rs  # VAD + whisper pipeline
│           │   └── engine.rs     # TranscriptionEngine (mic + system audio orchestration)
│           ├── storage/
│           │   ├── mod.rs
│           │   ├── session_store.rs    # JSONL + sidecar (.meta.json) session persistence
│           │   ├── template_store.rs   # Template CRUD (JSON)
│           │   └── transcript_logger.rs  # Plain-text .txt archive to ~/Documents/OpenOats/
│           └── intelligence/
│               ├── mod.rs
│               ├── llm_client.rs       # OpenRouter + Ollama HTTP clients (reqwest + tokio)
│               ├── embedding_client.rs # Voyage AI + Ollama + OpenAI-compatible
│               ├── knowledge_base.rs   # KB loading, chunking, cosine similarity, JSON cache
│               ├── suggestion_engine.rs  # Configurable delay (default 5s)
│               └── notes_engine.rs
│
├── OpenOatsTauri/
│   ├── src-tauri/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── main.rs
│   │       ├── lib.rs            # Tauri commands — thin bridge to openoats-core
│   │       ├── audio_windows.rs  # WASAPI loopback (system audio, "them") — Phase 2
│   │       └── audio_mac.rs      # CoreAudio process tap via raw FFI or Swift shim — Phase 3
│   └── src/                      # React/TypeScript UI (shared across platforms)
│       ├── components/
│       │   ├── ControlBar.tsx        # Start/stop, mic selector, status
│       │   ├── TranscriptView.tsx    # Main window utterance list
│       │   ├── OverlayView.tsx       # Compact transcript + suggestion for overlay window
│       │   ├── SuggestionsView.tsx
│       │   ├── NotesView.tsx
│       │   ├── SettingsView.tsx
│       │   ├── SessionHistoryView.tsx
│       │   ├── OnboardingView.tsx
│       │   └── ConsentModal.tsx
│       ├── App.tsx
│       └── main.tsx
│
├── Sources/OpenOatsMac/          # Kept shipping through Phase 2
├── Sources/OpenOatsCore/         # Deprecated after Phase 3
├── Sources/OpenOatsWindows/      # Deprecated after Phase 3
└── Package.swift                 # Simplified or removed in Phase 4
```

### Principles

- `openoats-core` owns all business logic. It has no Tauri dependency.
- `src-tauri` is a thin command adapter — it wires Tauri commands/events to core functions.
- Platform-specific audio implementations (WASAPI loopback, CoreAudio tap) live in `src-tauri` and are injected into core at app startup via trait objects.
- The React UI is fully shared between Windows and Mac — no platform-specific UI code.
- All secrets (API keys) are stored via the `keyring` crate only — never in plain JSON settings files.

---

## Migration Phases

### Phase 1 — Rust Core Foundation
**Goal:** Establish `openoats-core` crate and migrate existing Tauri inline code into it. Windows app gains session persistence and settings.

Tasks:
- Create `crates/openoats-core` with workspace `Cargo.toml`
- Define `AudioCaptureService` + `MicCaptureService` traits using `futures::Stream<Item = Vec<f32>>` (Rust equivalent of Swift's `AsyncStream<[Float]>`)
- Move existing `audio.rs`, `transcriber.rs` from `src-tauri/src` into `openoats-core`
- Port `models.rs` (Utterance, Speaker, Session, Suggestion, ConversationState, etc.) from Swift to Rust
- Implement `AppSettings` in Rust using `dirs` + `serde_json` (JSON file in app data dir). **Note:** Existing Mac user settings stored in Apple UserDefaults will not be migrated automatically — this is a fresh start for Windows users.
- Implement `keychain.rs` using `keyring` crate for all three secrets: `openRouterApiKey`, `voyageApiKey`, `openAIEmbedApiKey`
- Implement `SessionStore` in Rust (JSONL + `.meta.json` sidecar, same file format as current Swift implementation)
- Implement `TranscriptLogger` in Rust (plain-text `.txt` archive to `~/Documents/OpenOats/` — preserves existing user export behavior)
- Replace `ureq` in `engine.rs` model download with `reqwest` + `tokio::spawn_blocking` and move download logic into `openoats-core`. All HTTP in the project now goes through `reqwest`.
- Implement cpal-based mic device enumeration in `cpal_mic.rs` (enumerate by name, not raw `AudioDeviceID` integer)
- Wire updated Tauri commands to core

**Deliverable:** Windows app with audio, transcription, session persistence, settings storage, and plain-text transcript export.

### Phase 2 — Windows Feature Parity
**Goal:** Windows Tauri app reaches full feature parity with the Mac Swift app.

Tasks:
- System audio capture via WASAPI loopback (`audio_windows.rs`) — enables "them" speaker
- `LLMClient`: OpenRouter + Ollama HTTP clients (`reqwest` + `tokio`)
- `EmbeddingClient`: Voyage AI + Ollama + OpenAI-compatible
- `KnowledgeBase`: file loading, chunking, cosine similarity search, JSON embedding cache
- `SuggestionEngine`: trigger detection, KB retrieval, LLM surfacing gate (configurable delay, default 5s)
- `NotesEngine`: template-based notes generation
- `TemplateStore` in Rust
- Overlay window: second `WebviewWindow` with `always_on_top: true` + `decorations: false`. State shared with main window via `app.emit_all()` so both windows receive the same transcript/suggestion events. `OverlayView.tsx` renders compact transcript + current suggestion.
- React UI components: SettingsView (all tabs: transcription, LLM, embeddings, KB, privacy), SuggestionsView, NotesView + template picker, SessionHistoryView, OnboardingView, ConsentModal, ControlBar with mic selector
- Recording consent gate (ConsentModal must be acknowledged before first session starts)
- Screen-share content protection (`content_protection` Tauri capability)

**Deliverable:** Windows Tauri app feature-complete, ready for user testing.

### Phase 3 — Mac Tauri Migration
**Goal:** Replace OpenOatsMac Swift app with the Tauri app running on macOS.

Tasks:
- macOS system audio capture (`audio_mac.rs`): `AudioHardwareCreateProcessTap` + `AudioHardwareCreateAggregateDevice` + `AudioDeviceCreateIOProcIDWithBlock` (macOS 14.2+ APIs). These have no Rust bindings in `coreaudio-rs` — implement via raw `extern "C"` FFI bindings (`core-foundation` + `core-audio-types` crates) or wrap in a thin Swift shim compiled alongside the Tauri app and called via C ABI. Decision to be made at Phase 3 start based on FFI complexity assessment.
- macOS permissions flow: microphone + screen recording via Tauri capabilities
- Overlay window validation on macOS
- Screen-share hiding (`content_protection`) validation on macOS
- Auto-updater: integrate `tauri-plugin-updater`, configure appcast URL, handle macOS App Management permission errors (equivalent to current Sparkle `OpenOatsUserDriver` behavior). **This is a shipping requirement for Mac — not optional.**
- End-to-end Mac validation
- Deprecate `OpenOatsMac` Swift executable

**Deliverable:** Single Tauri app shipping on both Windows and Mac.

### Phase 4 — Swift Cleanup
**Goal:** Remove all Swift code and simplify the repository.

Tasks:
- Remove `Sources/OpenOatsCore`
- Remove `Sources/OpenOatsMac`
- Remove `Sources/OpenOatsWindows`
- Simplify or remove `Package.swift`
- Update CI/build scripts

**Deliverable:** Clean Rust + React monorepo with no Swift dependency.

---

## Key Technical Decisions

| Concern | Solution | Rationale |
|---|---|---|
| Mic capture | `cpal` (existing) with device enumeration by name | Already working; raw device ID integers replaced with named lookup |
| System audio Windows | WASAPI loopback via `windows-rs` | Native, no extra deps, captures all output audio |
| System audio Mac | Raw FFI or Swift shim (assessed at Phase 3 start) | `AudioHardwareCreateProcessTap` has no `coreaudio-rs` bindings; approach TBD |
| Secret storage | `keyring` crate for all three API keys | Abstracts Windows Credential Manager + macOS Keychain; never stored in plain JSON |
| Settings persistence | JSON file via `dirs` + `serde_json` | Portable; no migration from Apple UserDefaults (fresh start) |
| HTTP / API clients | `reqwest` + `tokio` throughout (replaces `ureq`) | Single async HTTP stack across model download + intelligence layer |
| Vector search / KB | Cosine similarity in Rust, JSON cache | No external DB needed at this scale |
| Frontend ↔ Backend | Tauri invoke (commands) + `app.emit_all()` (events) | `emit_all` broadcasts to both main and overlay windows |
| Logging | `log` crate + Tauri log plugin | Replaces `/tmp/openoats.log` hack |
| Overlay window | Second `WebviewWindow` (`always_on_top`, `decorations: false`) | Both windows share state via `emit_all`; `OverlayView.tsx` renders compact view |
| Screen-share hiding | Tauri `content_protection` capability | Maps to `SetWindowDisplayAffinity` on Windows, `setSharingType` on Mac |
| Auto-updater | `tauri-plugin-updater` (Phase 3) | Replaces Sparkle; required for Mac shipping |
| UI framework | React + TypeScript (existing) | Already in repo, shared across platforms |
| Audio traits | `futures::Stream<Item = Vec<f32>>` | Rust equivalent of Swift `AsyncStream<[Float]>` |

---

## UI Component Map

| SwiftUI (Mac) | React Component | Description |
|---|---|---|
| `ContentView` | `App.tsx` | Top-level layout shell |
| `ControlBar` | `ControlBar.tsx` | Start/stop, mic selector (by device name), status indicator |
| `TranscriptView` | `TranscriptView.tsx` | Utterance list, auto-scroll, you/them labels |
| `OverlayContent` / `OverlayPanel` | `OverlayView.tsx` + second WebviewWindow | Compact transcript + suggestion; separate window via `emit_all` |
| `SuggestionsView` | `SuggestionsView.tsx` | AI suggestion cards, helpful/not helpful feedback |
| `NotesView` | `NotesView.tsx` | Generated notes markdown display, template picker |
| `SettingsView` | `SettingsView.tsx` | Tabbed: transcription, LLM, embeddings, KB, privacy |
| `OnboardingView` | `OnboardingView.tsx` | First-run wizard |
| `RecordingConsentView` | `ConsentModal.tsx` | Must-acknowledge modal before first session |
| `CheckForUpdatesView` | `tauri-plugin-updater` | Phase 3 — shipping requirement for Mac |
| `AppCoordinator` | `lib.rs` AppState + Tauri lifecycle | Session start/stop, transcript drain on finalize |

**State management:** React context + hooks. No external state library. Tauri events (via `listen()`) feed into React state in both windows.

---

## Gaps & Optimizations

The following issues were identified in the current codebase and are addressed during migration:

### Bugs / Gaps
1. `WindowsExports.swift` — all C-binding stubs are empty, never connected to Tauri. Removed in Phase 4.
2. `resolvedMicDeviceID()` passes `AudioDeviceID` integers through without validation or existence check. In Rust, mic selection uses cpal device enumeration by name — no raw integer IDs.
3. `WhisperManager.transcribe()` hardcodes `language = "en"`, ignoring `AppSettings.transcriptionLocale`. Fixed in Rust `whisper.rs` — language read from settings.
4. `diagLog()` writes to `/tmp/openoats.log` — invalid path on Windows. Replaced with `log` crate + Tauri log plugin.
5. `KeychainHelper` Windows fallback stores all three API keys (`openRouterApiKey`, `voyageApiKey`, `openAIEmbedApiKey`) in plain `UserDefaults`. Fixed with `keyring` crate in Phase 1.
6. System audio ("them" speaker) completely absent on Windows. Addressed in Phase 2.
7. Tauri transcript events only emit `speaker: "you"` — "them" path never fires. Fixed when system audio is added in Phase 2.
8. `TranscriptLogger` plain-text `.txt` export exists in Swift but was not ported to Tauri. Ported in Phase 1 to preserve user export behavior.
9. Existing Mac user settings in Apple UserDefaults will not migrate to the new Rust JSON settings format — intentional clean break for the Rust app.

### Optimizations
1. VAD parameters unified in `openoats-core/vad.rs`: RMS threshold `0.005`, chunk size `1600` samples (100 ms at 16 kHz), silence end at 5 consecutive silent chunks. (Swift had different threshold and 4096-sample chunks.)
2. Rust `sync_channel(500)` buffer size made configurable via settings.
3. `build_mic_stream` extended to handle `U16` sample format in addition to `F32` and `I16`.
4. Model path made configurable via settings — no longer hardcoded to `ggml-base.en.bin`.
5. `SuggestionEngine` delayed write made configurable (default 5 seconds).
6. `ureq` replaced with `reqwest` throughout — single async HTTP stack.

---

## Progress Tracking

- [ ] **Phase 1 — Rust Core Foundation**
  - [ ] Create `crates/openoats-core` with workspace Cargo.toml
  - [ ] Define `AudioCaptureService` / `MicCaptureService` traits (`futures::Stream`)
  - [ ] Move audio + transcription into core crate
  - [ ] Port data models to Rust
  - [ ] Implement AppSettings (JSON persistence via dirs)
  - [ ] Implement keychain (keyring crate, all 3 keys)
  - [ ] Implement SessionStore (JSONL + sidecar)
  - [ ] Implement TranscriptLogger (plain-text .txt export)
  - [ ] Replace ureq with reqwest for model download; move download into core
  - [ ] Implement cpal mic device enumeration by name
  - [ ] Wire Tauri commands to core

- [ ] **Phase 2 — Windows Feature Parity**
  - [ ] WASAPI loopback system audio capture
  - [ ] LLM client (OpenRouter + Ollama)
  - [ ] Embedding client (Voyage + Ollama + OpenAI-compatible)
  - [ ] KnowledgeBase (load, chunk, embed, search)
  - [ ] SuggestionEngine (configurable delay)
  - [ ] NotesEngine + TemplateStore
  - [ ] Overlay window (second WebviewWindow + emit_all)
  - [ ] React: OverlayView.tsx (compact transcript + suggestion)
  - [ ] React: ControlBar with named mic selector
  - [ ] React: SuggestionsView
  - [ ] React: NotesView + template picker
  - [ ] React: SettingsView (all tabs)
  - [ ] React: SessionHistoryView
  - [ ] React: OnboardingView
  - [ ] React: ConsentModal
  - [ ] Screen-share content protection

- [ ] **Phase 3 — Mac Tauri Migration**
  - [ ] Assess CoreAudio process tap FFI approach (raw bindings vs Swift shim)
  - [ ] Implement macOS system audio capture (audio_mac.rs)
  - [ ] macOS permissions flow (mic + screen recording)
  - [ ] Overlay window validation on macOS
  - [ ] tauri-plugin-updater integration + appcast + App Management permission handling
  - [ ] End-to-end Mac validation
  - [ ] Deprecate OpenOatsMac Swift app

- [ ] **Phase 4 — Swift Cleanup**
  - [ ] Remove Sources/OpenOatsCore
  - [ ] Remove Sources/OpenOatsMac
  - [ ] Remove Sources/OpenOatsWindows
  - [ ] Simplify/remove Package.swift
  - [ ] Update CI/build scripts
