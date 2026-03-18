# OpenOats Multiplatform Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate OpenOats from a split Swift/Tauri codebase to a unified `openoats-core` Rust library powering a single Tauri/React app on Windows and macOS.

**Architecture:** All business logic lives in a `crates/openoats-core` Rust library with no Tauri dependency. The Tauri `src-tauri` layer is a thin command adapter. The React frontend is shared across platforms. Platform-specific audio (WASAPI loopback on Windows, CoreAudio tap on Mac) is injected into core at startup via trait objects.

**Tech Stack:** Rust (openoats-core), Tauri 2, React/TypeScript, whisper-rs, cpal, reqwest/tokio, serde/serde_json, dirs, keyring, futures

**Spec:** `docs/superpowers/specs/2026-03-18-multiplatform-design.md`

---

## Phase 1 — Rust Core Foundation (Detailed)

This phase establishes the `openoats-core` crate, moves all business logic into it, and wires the existing Tauri app to use it. The Windows app will have audio, transcription, session persistence, and settings at the end of this phase.

**The existing Tauri code to migrate:**
- `OpenOatsTauri/src-tauri/src/audio.rs` — cpal mic capture with resampling → moves to core
- `OpenOatsTauri/src-tauri/src/transcriber.rs` — VAD + whisper pipeline → moves to core
- `OpenOatsTauri/src-tauri/src/engine.rs` — Tauri commands → becomes thin wrapper over core

---

### Task 1: Rust Workspace Setup

**Files:**
- Create: `OpenOats/Cargo.toml`
- Modify: `OpenOats/OpenOatsTauri/src-tauri/Cargo.toml`
- Create: `OpenOats/crates/openoats-core/Cargo.toml`
- Create: `OpenOats/crates/openoats-core/src/lib.rs`

- [ ] **Step 1: Create the workspace `Cargo.toml` at `OpenOats/Cargo.toml`**

```toml
[workspace]
members = [
    "crates/openoats-core",
    "OpenOatsTauri/src-tauri",
]
resolver = "2"
```

- [ ] **Step 2: Create `OpenOats/crates/openoats-core/Cargo.toml`**

```toml
[package]
name = "openoats-core"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
dirs = "5"
keyring = "3"
futures = "0.3"
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.12", features = ["json", "stream"] }
whisper-rs = "0.14"
cpal = "0.15"
rubato = "0.15"
log = "0.4"
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }
async-trait = "0.1"
tokio-stream = "0.1"

[dev-dependencies]
tempfile = "3"
tokio = { version = "1", features = ["full"] }
```

- [ ] **Step 3: Create `OpenOats/crates/openoats-core/src/lib.rs`**

Note: `intelligence` is NOT declared here in Phase 1 — it will be added in Phase 2.

```rust
pub mod audio;
pub mod download;
pub mod keychain;
pub mod models;
pub mod settings;
pub mod storage;
pub mod transcription;
```

- [ ] **Step 3b: Create placeholder dirs and files so `cargo check` succeeds**

Create these files now (each with just a comment) so all declared modules resolve:
- `OpenOats/crates/openoats-core/src/audio/mod.rs` → `// see Task 8`
- `OpenOats/crates/openoats-core/src/audio/cpal_mic.rs` → `// see Task 12`
- `OpenOats/crates/openoats-core/src/transcription/mod.rs` → `// see Task 9`
- `OpenOats/crates/openoats-core/src/transcription/vad.rs` → `// see Task 9`
- `OpenOats/crates/openoats-core/src/transcription/whisper.rs` → `// see Task 10`
- `OpenOats/crates/openoats-core/src/transcription/streaming_transcriber.rs` → `// see Task 11`
- `OpenOats/crates/openoats-core/src/transcription/engine.rs` → `// see Task 13`
- `OpenOats/crates/openoats-core/src/storage/mod.rs` → `// see Task 5`
- `OpenOats/crates/openoats-core/src/storage/session_store.rs` → `// see Task 5`
- `OpenOats/crates/openoats-core/src/storage/template_store.rs` → `// see Task 7`
- `OpenOats/crates/openoats-core/src/storage/transcript_logger.rs` → `// see Task 6`
- `OpenOats/crates/openoats-core/src/download.rs` → `// see Task 13`
- `OpenOats/crates/openoats-core/src/keychain.rs` → `// see Task 4`
- `OpenOats/crates/openoats-core/src/models.rs` → `// see Task 2`
- `OpenOats/crates/openoats-core/src/settings.rs` → `// see Task 3`

- [ ] **Step 4: Update `OpenOats/OpenOatsTauri/src-tauri/Cargo.toml` to use workspace and add openoats-core**

Replace the entire file with:

```toml
[package]
name = "app"
version = "0.1.0"
description = "OpenOats"
authors = []
edition = "2021"
rust-version = "1.77.2"

[lib]
name = "app_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2.5.6", features = [] }

[dependencies]
openoats-core = { path = "../../crates/openoats-core" }
serde_json = "1.0"
serde = { version = "1.0", features = ["derive"] }
log = "0.4"
tauri = { version = "2.10.3", features = [] }
tauri-plugin-log = "2"
```

Note: `cpal`, `rubato`, `whisper-rs`, and `ureq` are removed from the Tauri crate — they now live in openoats-core.

- [ ] **Step 5: Verify the workspace resolves**

Run from `OpenOats/`:
```bash
cargo check --workspace
```
Expected: errors about missing modules in openoats-core (lib.rs references them), but the workspace itself resolves. We'll fill modules in subsequent tasks.

- [ ] **Step 6: Commit**

```bash
git add OpenOats/Cargo.toml OpenOats/crates/ OpenOats/OpenOatsTauri/src-tauri/Cargo.toml
git commit -m "feat: create openoats-core workspace skeleton"
```

---

### Task 2: Port Data Models

Port all Swift data models to Rust with full serde support.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/models.rs`

- [ ] **Step 1: Write the failing test**

Add to the bottom of `OpenOats/crates/openoats-core/src/models.rs` (create the file first with just the test):

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utterance_roundtrips_json() {
        let u = Utterance::new("hello world".into(), Speaker::You);
        let json = serde_json::to_string(&u).unwrap();
        let back: Utterance = serde_json::from_str(&json).unwrap();
        assert_eq!(back.text, "hello world");
        assert_eq!(back.speaker, Speaker::You);
    }

    #[test]
    fn session_record_roundtrips_json() {
        let r = SessionRecord {
            speaker: Speaker::Them,
            text: "test".into(),
            timestamp: chrono::Utc::now(),
            suggestions: None,
            kb_hits: None,
            suggestion_decision: None,
            surfaced_suggestion_text: None,
            conversation_state_summary: None,
        };
        let json = serde_json::to_string(&r).unwrap();
        let back: SessionRecord = serde_json::from_str(&json).unwrap();
        assert_eq!(back.text, "test");
        assert_eq!(back.speaker, Speaker::Them);
    }

    #[test]
    fn meeting_template_built_ins_have_stable_ids() {
        let templates = MeetingTemplate::built_ins();
        assert_eq!(templates.len(), 6);
        assert_eq!(
            templates[0].id.to_string(),
            "00000000-0000-0000-0000-000000000000"
        );
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core models 2>&1 | head -20
```
Expected: compile error — `Utterance`, `Speaker`, etc. not defined yet.

- [ ] **Step 3: Implement `models.rs`**

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ── Speaker ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Speaker {
    You,
    Them,
}

impl Speaker {
    pub fn label(&self) -> &'static str {
        match self {
            Speaker::You => "you",
            Speaker::Them => "them",
        }
    }
}

// ── Utterance ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Utterance {
    pub id: Uuid,
    pub text: String,
    pub speaker: Speaker,
    pub timestamp: DateTime<Utc>,
}

impl Utterance {
    pub fn new(text: String, speaker: Speaker) -> Self {
        Self { id: Uuid::new_v4(), text, speaker, timestamp: Utc::now() }
    }
}

// ── ConversationState ─────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ConversationState {
    pub current_topic: String,
    pub short_summary: String,
    pub open_questions: Vec<String>,
    pub active_tensions: Vec<String>,
    pub recent_decisions: Vec<String>,
    pub them_goals: Vec<String>,
    pub suggested_angles_recently_shown: Vec<String>,
    pub last_updated_at: DateTime<Utc>,
}

impl ConversationState {
    pub fn empty() -> Self {
        Self { last_updated_at: DateTime::<Utc>::from_timestamp(0, 0).unwrap(), ..Default::default() }
    }
}

// ── SuggestionDecision ────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestionDecision {
    pub should_surface: bool,
    pub confidence: f64,
    pub relevance_score: f64,
    pub helpfulness_score: f64,
    pub timing_score: f64,
    pub novelty_score: f64,
    pub reason: String,
}

// ── KBResult ──────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KBResult {
    pub id: Uuid,
    pub text: String,
    pub source_file: String,
    pub header_context: String,
    pub score: f64,
}

impl KBResult {
    pub fn new(text: String, source_file: String, header_context: String, score: f64) -> Self {
        Self { id: Uuid::new_v4(), text, source_file, header_context, score }
    }
}

// ── Suggestion ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Suggestion {
    pub id: Uuid,
    pub text: String,
    pub timestamp: DateTime<Utc>,
    pub kb_hits: Vec<KBResult>,
    pub decision: Option<SuggestionDecision>,
    pub summary_snapshot: Option<String>,
}

impl Suggestion {
    pub fn new(text: String, kb_hits: Vec<KBResult>, decision: Option<SuggestionDecision>) -> Self {
        Self { id: Uuid::new_v4(), text, timestamp: Utc::now(), kb_hits, decision, summary_snapshot: None }
    }
}

// ── SessionRecord (JSONL line) ────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRecord {
    pub speaker: Speaker,
    pub text: String,
    pub timestamp: DateTime<Utc>,
    pub suggestions: Option<Vec<String>>,
    pub kb_hits: Option<Vec<String>>,
    pub suggestion_decision: Option<SuggestionDecision>,
    pub surfaced_suggestion_text: Option<String>,
    pub conversation_state_summary: Option<String>,
}

// ── MeetingTemplate ───────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeetingTemplate {
    pub id: Uuid,
    pub name: String,
    pub icon: String,
    pub system_prompt: String,
    pub is_built_in: bool,
}

impl MeetingTemplate {
    pub fn built_ins() -> Vec<Self> {
        vec![
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000000").unwrap(), name: "Generic".into(), icon: "doc.text".into(), system_prompt: GENERIC_PROMPT.into(), is_built_in: true },
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap(), name: "1:1".into(), icon: "person.2".into(), system_prompt: ONE_ON_ONE_PROMPT.into(), is_built_in: true },
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap(), name: "Customer Discovery".into(), icon: "magnifyingglass".into(), system_prompt: DISCOVERY_PROMPT.into(), is_built_in: true },
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000003").unwrap(), name: "Hiring".into(), icon: "person.badge.plus".into(), system_prompt: HIRING_PROMPT.into(), is_built_in: true },
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000004").unwrap(), name: "Stand-Up".into(), icon: "arrow.up.circle".into(), system_prompt: STANDUP_PROMPT.into(), is_built_in: true },
            Self { id: Uuid::parse_str("00000000-0000-0000-0000-000000000005").unwrap(), name: "Weekly Meeting".into(), icon: "calendar".into(), system_prompt: WEEKLY_PROMPT.into(), is_built_in: true },
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateSnapshot {
    pub id: Uuid,
    pub name: String,
    pub icon: String,
    pub system_prompt: String,
}

impl From<&MeetingTemplate> for TemplateSnapshot {
    fn from(t: &MeetingTemplate) -> Self {
        Self { id: t.id, name: t.name.clone(), icon: t.icon.clone(), system_prompt: t.system_prompt.clone() }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnhancedNotes {
    pub template: TemplateSnapshot,
    pub generated_at: DateTime<Utc>,
    pub markdown: String,
}

// ── SessionIndex / Sidecar ────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionIndex {
    pub id: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub template_snapshot: Option<TemplateSnapshot>,
    pub title: Option<String>,
    pub utterance_count: usize,
    pub has_notes: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSidecar {
    pub index: SessionIndex,
    pub notes: Option<EnhancedNotes>,
}

// ── Built-in template prompts ─────────────────────────────────────────────────

const GENERIC_PROMPT: &str = "You are a meeting notes assistant. Given a transcript of a meeting, produce structured notes in markdown.\n\nInclude these sections:\n## Summary\nA 2-3 sentence overview of what was discussed.\n\n## Key Points\nBullet points of the most important topics and insights.\n\n## Action Items\nBullet points of concrete next steps, with owners if mentioned.\n\n## Decisions Made\nAny decisions that were reached during the meeting.\n\n## Open Questions\nUnresolved questions or topics that need follow-up.";
const ONE_ON_ONE_PROMPT: &str = "You are a meeting notes assistant for a 1:1 meeting. Given a transcript, produce structured notes in markdown.\n\nInclude these sections:\n## Discussion Points\nKey topics that were covered.\n\n## Action Items\nConcrete next steps with owners.\n\n## Follow-ups\nItems that need follow-up in future 1:1s.\n\n## Key Decisions\nDecisions that were made during the meeting.";
const DISCOVERY_PROMPT: &str = "You are a meeting notes assistant for a customer discovery call. Given a transcript, produce structured notes in markdown.\n\nInclude these sections:\n## Customer Profile\nWho the customer is, their role, and context.\n\n## Problems Identified\nPain points and challenges the customer described.\n\n## Current Solutions\nHow they currently solve these problems.\n\n## Key Insights\nSurprising or important learnings from the conversation.\n\n## Next Steps\nFollow-up actions and commitments made.";
const HIRING_PROMPT: &str = "You are a meeting notes assistant for a hiring interview. Given a transcript, produce structured notes in markdown.\n\nInclude these sections:\n## Candidate Summary\nBrief overview of the candidate and role discussed.\n\n## Strengths\nAreas where the candidate demonstrated strong capability.\n\n## Concerns\nPotential red flags or areas needing further evaluation.\n\n## Culture Fit\nObservations about alignment with team/company values.\n\n## Recommendation\nOverall assessment and suggested next steps.";
const STANDUP_PROMPT: &str = "You are a meeting notes assistant for a stand-up meeting. Given a transcript, produce structured notes in markdown.\n\nInclude these sections:\n## Yesterday\nWhat was completed since the last stand-up.\n\n## Today\nWhat each person plans to work on.\n\n## Blockers\nAny obstacles or dependencies that need resolution.";
const WEEKLY_PROMPT: &str = "You are a meeting notes assistant for a weekly team meeting. Given a transcript, produce structured notes in markdown.\n\nInclude these sections:\n## Updates\nStatus updates from team members.\n\n## Decisions Made\nAny decisions that were reached.\n\n## Open Items\nTopics that need further discussion or action.\n\n## Action Items\nConcrete next steps with owners and deadlines if mentioned.";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utterance_roundtrips_json() {
        let u = Utterance::new("hello world".into(), Speaker::You);
        let json = serde_json::to_string(&u).unwrap();
        let back: Utterance = serde_json::from_str(&json).unwrap();
        assert_eq!(back.text, "hello world");
        assert_eq!(back.speaker, Speaker::You);
    }

    #[test]
    fn session_record_roundtrips_json() {
        let r = SessionRecord {
            speaker: Speaker::Them,
            text: "test".into(),
            timestamp: Utc::now(),
            suggestions: None,
            kb_hits: None,
            suggestion_decision: None,
            surfaced_suggestion_text: None,
            conversation_state_summary: None,
        };
        let json = serde_json::to_string(&r).unwrap();
        let back: SessionRecord = serde_json::from_str(&json).unwrap();
        assert_eq!(back.text, "test");
        assert_eq!(back.speaker, Speaker::Them);
    }

    #[test]
    fn meeting_template_built_ins_have_stable_ids() {
        let templates = MeetingTemplate::built_ins();
        assert_eq!(templates.len(), 6);
        assert_eq!(
            templates[0].id.to_string(),
            "00000000-0000-0000-0000-000000000000"
        );
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd OpenOats && cargo test -p openoats-core models -- --nocapture
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/models.rs
git commit -m "feat(core): port data models to Rust with serde"
```

---

### Task 3: AppSettings

Settings persisted as JSON in the platform app data directory.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/settings.rs`

- [ ] **Step 1: Write the failing test**

```rust
// At bottom of settings.rs (create file first):
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn settings_persist_and_reload() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("settings.json");

        let mut s = AppSettings::load_from(path.clone());
        s.selected_model = "anthropic/claude-3-haiku".into();
        s.save_to(path.clone());

        let s2 = AppSettings::load_from(path);
        assert_eq!(s2.selected_model, "anthropic/claude-3-haiku");
    }

    #[test]
    fn settings_defaults_when_no_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("nonexistent.json");
        let s = AppSettings::load_from(path);
        assert_eq!(s.transcription_locale, "en-US");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core settings 2>&1 | head -20
```
Expected: compile error.

- [ ] **Step 3: Implement `settings.rs`**

```rust
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    #[serde(default = "default_model")]
    pub selected_model: String,

    #[serde(default = "default_locale")]
    pub transcription_locale: String,

    #[serde(default = "default_transcription_model")]
    pub transcription_model: String,

    #[serde(default)]
    pub input_device_name: Option<String>,

    #[serde(default = "default_llm_provider")]
    pub llm_provider: String,

    #[serde(default = "default_embedding_provider")]
    pub embedding_provider: String,

    #[serde(default = "default_ollama_url")]
    pub ollama_base_url: String,

    #[serde(default = "default_ollama_llm_model")]
    pub ollama_llm_model: String,

    #[serde(default = "default_ollama_embed_model")]
    pub ollama_embed_model: String,

    #[serde(default = "default_openai_embed_url")]
    pub open_ai_embed_base_url: String,

    #[serde(default = "default_openai_embed_model")]
    pub open_ai_embed_model: String,

    #[serde(default)]
    pub kb_folder_path: Option<String>,

    #[serde(default = "default_notes_folder")]
    pub notes_folder_path: String,

    #[serde(default)]
    pub has_acknowledged_recording_consent: bool,

    #[serde(default = "default_true")]
    pub hide_from_screen_share: bool,

    #[serde(default)]
    pub has_completed_onboarding: bool,
}

impl AppSettings {
    /// Load settings from the platform default location.
    pub fn load() -> Self {
        Self::load_from(Self::default_path())
    }

    /// Save to the platform default location.
    pub fn save(&self) {
        self.save_to(Self::default_path());
    }

    /// Returns the default settings file path for the current platform.
    pub fn default_path() -> PathBuf {
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("OpenOats")
            .join("settings.json")
    }

    pub fn load_from(path: PathBuf) -> Self {
        if let Ok(data) = std::fs::read_to_string(&path) {
            serde_json::from_str(&data).unwrap_or_default()
        } else {
            Self::default()
        }
    }

    pub fn save_to(&self, path: PathBuf) {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(self) {
            let _ = std::fs::write(path, json);
        }
    }

    pub fn notes_folder_url(&self) -> PathBuf {
        PathBuf::from(&self.notes_folder_path)
    }
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            selected_model: default_model(),
            transcription_locale: default_locale(),
            transcription_model: default_transcription_model(),
            input_device_name: None,
            llm_provider: default_llm_provider(),
            embedding_provider: default_embedding_provider(),
            ollama_base_url: default_ollama_url(),
            ollama_llm_model: default_ollama_llm_model(),
            ollama_embed_model: default_ollama_embed_model(),
            open_ai_embed_base_url: default_openai_embed_url(),
            open_ai_embed_model: default_openai_embed_model(),
            kb_folder_path: None,
            notes_folder_path: default_notes_folder(),
            has_acknowledged_recording_consent: false,
            hide_from_screen_share: true,
            has_completed_onboarding: false,
        }
    }
}

fn default_model() -> String { "google/gemini-3-flash-preview".into() }
fn default_locale() -> String { "en-US".into() }
fn default_transcription_model() -> String { "whisper-base".into() }
fn default_llm_provider() -> String { "openrouter".into() }
fn default_embedding_provider() -> String { "voyage".into() }
fn default_ollama_url() -> String { "http://localhost:11434".into() }
fn default_ollama_llm_model() -> String { "qwen3:8b".into() }
fn default_ollama_embed_model() -> String { "nomic-embed-text".into() }
fn default_openai_embed_url() -> String { "http://localhost:8080".into() }
fn default_openai_embed_model() -> String { "text-embedding-3-small".into() }
fn default_true() -> bool { true }
fn default_notes_folder() -> String {
    dirs::document_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("OpenOats")
        .to_string_lossy()
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn settings_persist_and_reload() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("settings.json");
        let mut s = AppSettings::load_from(path.clone());
        s.selected_model = "anthropic/claude-3-haiku".into();
        s.save_to(path.clone());
        let s2 = AppSettings::load_from(path);
        assert_eq!(s2.selected_model, "anthropic/claude-3-haiku");
    }

    #[test]
    fn settings_defaults_when_no_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("nonexistent.json");
        let s = AppSettings::load_from(path);
        assert_eq!(s.transcription_locale, "en-US");
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core settings -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/settings.rs
git commit -m "feat(core): implement AppSettings with JSON persistence"
```

---

### Task 4: Keychain

Secure storage for API keys using the OS keychain.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/keychain.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    // Note: keychain tests interact with the OS keychain.
    // Use a test-specific service name to avoid polluting user data.
    #[test]
    fn save_and_load_roundtrip() {
        let entry = KeyEntry::new_with_service("openoats-test", "test_api_key");
        entry.save("sk-test-value-123").unwrap();
        let loaded = entry.load().unwrap();
        assert_eq!(loaded, "sk-test-value-123");
        entry.delete().ok();
    }

    #[test]
    fn load_missing_key_returns_none() {
        let entry = KeyEntry::new_with_service("openoats-test", "definitely_does_not_exist_xyz");
        let result = entry.load();
        assert!(result.is_none());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core keychain 2>&1 | head -20
```
Expected: compile error.

- [ ] **Step 3: Implement `keychain.rs`**

```rust
use keyring::Entry;

const SERVICE: &str = "com.openoats.app";

/// Named API key entries stored in the OS keychain.
pub struct KeyEntry {
    entry: Entry,
}

impl KeyEntry {
    fn new(key: &str) -> Self {
        Self { entry: Entry::new(SERVICE, key).expect("keyring entry creation failed") }
    }

    /// For tests only — uses a custom service to avoid polluting user keychains.
    pub fn new_with_service(service: &str, key: &str) -> Self {
        Self { entry: Entry::new(service, key).expect("keyring entry creation failed") }
    }

    pub fn open_router_api_key() -> Self { Self::new("openRouterApiKey") }
    pub fn voyage_api_key() -> Self { Self::new("voyageApiKey") }
    pub fn open_ai_embed_api_key() -> Self { Self::new("openAIEmbedApiKey") }

    pub fn save(&self, value: &str) -> Result<(), keyring::Error> {
        self.entry.set_password(value)
    }

    pub fn load(&self) -> Option<String> {
        self.entry.get_password().ok()
    }

    pub fn delete(&self) -> Result<(), keyring::Error> {
        self.entry.delete_password()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn save_and_load_roundtrip() {
        let entry = KeyEntry::new_with_service("openoats-test", "test_api_key");
        entry.save("sk-test-value-123").unwrap();
        let loaded = entry.load().unwrap();
        assert_eq!(loaded, "sk-test-value-123");
        entry.delete().ok();
    }

    #[test]
    fn load_missing_key_returns_none() {
        let entry = KeyEntry::new_with_service("openoats-test", "definitely_does_not_exist_xyz");
        let result = entry.load();
        assert!(result.is_none());
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core keychain -- --nocapture
```
Expected: 2 tests pass. (On CI without a keychain, `save_and_load_roundtrip` may be skipped — acceptable.)

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/keychain.rs
git commit -m "feat(core): implement keychain storage via keyring crate"
```

---

### Task 5: SessionStore

JSONL session persistence with `.meta.json` sidecar — same file format as the Swift implementation.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/storage/mod.rs`
- Create: `OpenOats/crates/openoats-core/src/storage/session_store.rs`

- [ ] **Step 1: Create `storage/mod.rs`**

```rust
pub mod session_store;
pub mod template_store;
pub mod transcript_logger;
```

Note: `template_store` and `transcript_logger` will be created in later tasks. Add them now so the mod compiles.

- [ ] **Step 2: Create placeholder files**

Create `template_store.rs` and `transcript_logger.rs` with just a comment:
```rust
// TODO: implemented in Task 6 / Task 7
```

- [ ] **Step 3: Write the failing test at the bottom of `session_store.rs`**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use crate::models::{SessionRecord, Speaker};
    use chrono::Utc;

    #[test]
    fn start_writes_jsonl_file() {
        let dir = tempdir().unwrap();
        let mut store = SessionStore::new(dir.path().to_path_buf());
        store.start_session();
        assert!(store.current_session_id().is_some());
        let id = store.current_session_id().unwrap().to_string();
        let jsonl = dir.path().join(format!("{}.jsonl", id));
        assert!(jsonl.exists());
    }

    #[test]
    fn append_and_load_roundtrip() {
        let dir = tempdir().unwrap();
        let mut store = SessionStore::new(dir.path().to_path_buf());
        store.start_session();
        let record = SessionRecord {
            speaker: Speaker::You,
            text: "hello".into(),
            timestamp: Utc::now(),
            suggestions: None,
            kb_hits: None,
            suggestion_decision: None,
            surfaced_suggestion_text: None,
            conversation_state_summary: None,
        };
        store.append_record(&record).unwrap();
        store.end_session();

        let sessions = store.load_session_index();
        assert_eq!(sessions.len(), 1);
        let records = store.load_transcript(&sessions[0].id);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].text, "hello");
    }
}
```

- [ ] **Step 4: Run test to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core session_store 2>&1 | head -20
```

- [ ] **Step 5: Implement `session_store.rs`**

```rust
use crate::models::{EnhancedNotes, SessionIndex, SessionRecord, SessionSidecar, TemplateSnapshot};
use chrono::{DateTime, Utc};
use serde_json;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;

pub struct SessionStore {
    sessions_dir: PathBuf,
    current_id: Option<String>,
    current_file: Option<File>,
}

impl SessionStore {
    pub fn new(sessions_dir: PathBuf) -> Self {
        let _ = fs::create_dir_all(&sessions_dir);
        Self { sessions_dir, current_id: None, current_file: None }
    }

    /// Default location: <app_data>/OpenOats/sessions/
    pub fn with_default_path() -> Self {
        let dir = dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("OpenOats")
            .join("sessions");
        Self::new(dir)
    }

    pub fn start_session(&mut self) {
        let now: DateTime<Utc> = Utc::now();
        let id = format!("session_{}", now.format("%Y-%m-%d_%H-%M-%S"));
        let path = self.sessions_dir.join(format!("{}.jsonl", id));
        match File::create(&path) {
            Ok(f) => {
                self.current_id = Some(id);
                self.current_file = Some(f);
            }
            Err(e) => log::error!("SessionStore: failed to create session file: {e}"),
        }
    }

    pub fn current_session_id(&self) -> Option<&str> {
        self.current_id.as_deref()
    }

    pub fn append_record(&mut self, record: &SessionRecord) -> Result<(), String> {
        let file = self.current_file.as_mut().ok_or("no active session")?;
        let mut json = serde_json::to_string(record).map_err(|e| e.to_string())?;
        json.push('\n');
        file.write_all(json.as_bytes()).map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn end_session(&mut self) {
        self.current_file = None;
        self.current_id = None;
    }

    // ── Sidecar ───────────────────────────────────────────────────────────────

    pub fn write_sidecar(&self, sidecar: &SessionSidecar) {
        let path = self.sessions_dir.join(format!("{}.meta.json", sidecar.index.id));
        match serde_json::to_string_pretty(sidecar) {
            Ok(json) => { let _ = fs::write(path, json); }
            Err(e) => log::error!("SessionStore: sidecar write failed: {e}"),
        }
    }

    pub fn save_notes(&self, session_id: &str, notes: EnhancedNotes) {
        let meta_path = self.sessions_dir.join(format!("{}.meta.json", session_id));
        let mut sidecar = self.read_sidecar_or_stub(session_id);
        sidecar.notes = Some(notes);
        sidecar.index.has_notes = true;
        self.write_sidecar(&sidecar);
    }

    fn read_sidecar_or_stub(&self, session_id: &str) -> SessionSidecar {
        let path = self.sessions_dir.join(format!("{}.meta.json", session_id));
        if let Ok(data) = fs::read_to_string(&path) {
            if let Ok(s) = serde_json::from_str::<SessionSidecar>(&data) {
                return s;
            }
        }
        // Build stub from JSONL filename
        let started_at = Self::parse_date_from_id(session_id);
        let utterance_count = self.load_transcript(session_id).len();
        SessionSidecar {
            index: SessionIndex {
                id: session_id.to_string(),
                started_at,
                ended_at: None,
                template_snapshot: None,
                title: None,
                utterance_count,
                has_notes: false,
            },
            notes: None,
        }
    }

    // ── History ───────────────────────────────────────────────────────────────

    pub fn load_session_index(&self) -> Vec<SessionIndex> {
        let Ok(entries) = fs::read_dir(&self.sessions_dir) else { return vec![] };
        let mut map: std::collections::HashMap<String, SessionIndex> = std::collections::HashMap::new();

        for entry in entries.flatten() {
            let path = entry.path();
            let name = path.file_name().unwrap_or_default().to_string_lossy().to_string();

            if name.ends_with(".meta.json") {
                let stem = name.trim_end_matches(".meta.json").to_string();
                if let Ok(data) = fs::read_to_string(&path) {
                    if let Ok(sidecar) = serde_json::from_str::<SessionSidecar>(&data) {
                        map.insert(stem, sidecar.index);
                    }
                }
            }
        }

        // Handle orphaned JSONL files with no sidecar
        for entry in fs::read_dir(&self.sessions_dir).into_iter().flatten().flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) == Some("jsonl") {
                let stem = path.file_stem().unwrap_or_default().to_string_lossy().to_string();
                if !map.contains_key(&stem) {
                    let records = self.load_transcript(&stem);
                    map.insert(stem.clone(), SessionIndex {
                        id: stem.clone(),
                        started_at: Self::parse_date_from_id(&stem),
                        ended_at: None,
                        template_snapshot: None,
                        title: None,
                        utterance_count: records.len(),
                        has_notes: false,
                    });
                }
            }
        }

        let mut sessions: Vec<SessionIndex> = map.into_values().collect();
        sessions.sort_by(|a, b| b.started_at.cmp(&a.started_at));
        sessions
    }

    pub fn load_transcript(&self, session_id: &str) -> Vec<SessionRecord> {
        let path = self.sessions_dir.join(format!("{}.jsonl", session_id));
        let Ok(file) = File::open(&path) else { return vec![] };
        BufReader::new(file)
            .lines()
            .flatten()
            .filter(|l| !l.is_empty())
            .filter_map(|line| serde_json::from_str::<SessionRecord>(&line).ok())
            .collect()
    }

    fn parse_date_from_id(id: &str) -> DateTime<Utc> {
        let date_part = id.trim_start_matches("session_");
        chrono::NaiveDateTime::parse_from_str(date_part, "%Y-%m-%d_%H-%M-%S")
            .map(|dt| dt.and_utc())
            .unwrap_or_else(|_| Utc::now())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Speaker;
    use tempfile::tempdir;

    #[test]
    fn start_writes_jsonl_file() {
        let dir = tempdir().unwrap();
        let mut store = SessionStore::new(dir.path().to_path_buf());
        store.start_session();
        assert!(store.current_session_id().is_some());
        let id = store.current_session_id().unwrap().to_string();
        let jsonl = dir.path().join(format!("{}.jsonl", id));
        assert!(jsonl.exists());
    }

    #[test]
    fn append_and_load_roundtrip() {
        let dir = tempdir().unwrap();
        let mut store = SessionStore::new(dir.path().to_path_buf());
        store.start_session();
        let record = SessionRecord {
            speaker: Speaker::You,
            text: "hello".into(),
            timestamp: Utc::now(),
            suggestions: None,
            kb_hits: None,
            suggestion_decision: None,
            surfaced_suggestion_text: None,
            conversation_state_summary: None,
        };
        store.append_record(&record).unwrap();
        store.end_session();

        let sessions = store.load_session_index();
        assert_eq!(sessions.len(), 1);
        let records = store.load_transcript(&sessions[0].id);
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].text, "hello");
    }
}
```

- [ ] **Step 6: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core session_store -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add OpenOats/crates/openoats-core/src/storage/
git commit -m "feat(core): implement SessionStore with JSONL + sidecar persistence"
```

---

### Task 6: TranscriptLogger

Plain-text `.txt` export to `~/Documents/OpenOats/`.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/storage/transcript_logger.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn creates_txt_file_on_start() {
        let dir = tempdir().unwrap();
        let mut logger = TranscriptLogger::new(dir.path().to_path_buf());
        logger.start_session();
        let files: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert_eq!(files.len(), 1);
        let name = files[0].as_ref().unwrap().file_name();
        assert!(name.to_string_lossy().ends_with(".txt"));
    }

    #[test]
    fn appended_lines_appear_in_file() {
        let dir = tempdir().unwrap();
        let mut logger = TranscriptLogger::new(dir.path().to_path_buf());
        logger.start_session();
        logger.append("You", "hello there", chrono::Utc::now());
        logger.end_session();

        let files: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        let content = std::fs::read_to_string(files[0].as_ref().unwrap().path()).unwrap();
        assert!(content.contains("You: hello there"));
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core transcript_logger 2>&1 | head -20
```

- [ ] **Step 3: Implement `transcript_logger.rs`**

```rust
use chrono::{DateTime, Utc};
use std::fs::{self, File};
use std::io::Write;
use std::path::PathBuf;

pub struct TranscriptLogger {
    directory: PathBuf,
    current_file: Option<File>,
}

impl TranscriptLogger {
    pub fn new(directory: PathBuf) -> Self {
        let _ = fs::create_dir_all(&directory);
        Self { directory, current_file: None }
    }

    pub fn with_default_path() -> Self {
        let dir = dirs::document_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("OpenOats");
        Self::new(dir)
    }

    pub fn start_session(&mut self) {
        let now: DateTime<Utc> = Utc::now();
        let filename = format!("{}.txt", now.format("%Y-%m-%d_%H-%M"));
        let path = self.directory.join(filename);
        match File::create(&path) {
            Ok(mut f) => {
                let header = format!("OpenOats - {}\n\n", now.format("%B %d, %Y %H:%M"));
                let _ = f.write_all(header.as_bytes());
                self.current_file = Some(f);
            }
            Err(e) => log::error!("TranscriptLogger: failed to create file: {e}"),
        }
    }

    pub fn append(&mut self, speaker: &str, text: &str, timestamp: DateTime<Utc>) {
        let Some(ref mut file) = self.current_file else { return };
        let line = format!("[{}] {}: {}\n", timestamp.format("%H:%M:%S"), speaker, text);
        let _ = file.write_all(line.as_bytes());
    }

    pub fn end_session(&mut self) {
        self.current_file = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn creates_txt_file_on_start() {
        let dir = tempdir().unwrap();
        let mut logger = TranscriptLogger::new(dir.path().to_path_buf());
        logger.start_session();
        let files: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        assert_eq!(files.len(), 1);
        let name = files[0].as_ref().unwrap().file_name();
        assert!(name.to_string_lossy().ends_with(".txt"));
    }

    #[test]
    fn appended_lines_appear_in_file() {
        let dir = tempdir().unwrap();
        let mut logger = TranscriptLogger::new(dir.path().to_path_buf());
        logger.start_session();
        logger.append("You", "hello there", Utc::now());
        logger.end_session();
        let files: Vec<_> = std::fs::read_dir(dir.path()).unwrap().collect();
        let content = std::fs::read_to_string(files[0].as_ref().unwrap().path()).unwrap();
        assert!(content.contains("You: hello there"));
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core transcript_logger -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/storage/transcript_logger.rs
git commit -m "feat(core): implement TranscriptLogger plain-text export"
```

---

### Task 7: TemplateStore

Template CRUD with JSON persistence and deterministic built-in IDs.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/storage/template_store.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn loads_built_ins_when_no_file() {
        let dir = tempdir().unwrap();
        let store = TemplateStore::load_from(dir.path().join("templates.json"));
        assert_eq!(store.templates().len(), 6);
    }

    #[test]
    fn custom_template_persists() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("templates.json");
        let mut store = TemplateStore::load_from(path.clone());
        let t = crate::models::MeetingTemplate {
            id: uuid::Uuid::new_v4(),
            name: "My Template".into(),
            icon: "star".into(),
            system_prompt: "Be helpful.".into(),
            is_built_in: false,
        };
        store.add(t.clone());
        // Reload from disk
        let store2 = TemplateStore::load_from(path);
        assert!(store2.templates().iter().any(|x| x.name == "My Template"));
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd OpenOats && cargo test -p openoats-core template_store 2>&1 | head -20
```

- [ ] **Step 3: Implement `template_store.rs`**

```rust
use crate::models::MeetingTemplate;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Serialize, Deserialize)]
struct StorageFormat {
    version: u32,
    templates: Vec<MeetingTemplate>,
}

pub struct TemplateStore {
    path: PathBuf,
    templates: Vec<MeetingTemplate>,
}

impl TemplateStore {
    pub fn load() -> Self {
        Self::load_from(Self::default_path())
    }

    pub fn default_path() -> PathBuf {
        dirs::data_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("OpenOats")
            .join("templates.json")
    }

    pub fn load_from(path: PathBuf) -> Self {
        let templates = if let Ok(data) = std::fs::read_to_string(&path) {
            if let Ok(stored) = serde_json::from_str::<StorageFormat>(&data) {
                let mut ts = stored.templates;
                // Ensure all built-ins exist (handles version upgrades)
                for built_in in MeetingTemplate::built_ins() {
                    if !ts.iter().any(|t| t.id == built_in.id) {
                        ts.push(built_in);
                    }
                }
                ts
            } else {
                MeetingTemplate::built_ins()
            }
        } else {
            MeetingTemplate::built_ins()
        };

        let mut store = Self { path, templates };
        store.save();
        store
    }

    pub fn templates(&self) -> &[MeetingTemplate] {
        &self.templates
    }

    pub fn get(&self, id: uuid::Uuid) -> Option<&MeetingTemplate> {
        self.templates.iter().find(|t| t.id == id)
    }

    pub fn add(&mut self, template: MeetingTemplate) {
        self.templates.push(template);
        self.save();
    }

    pub fn update(&mut self, template: MeetingTemplate) {
        if let Some(t) = self.templates.iter_mut().find(|t| t.id == template.id) {
            *t = template;
            self.save();
        }
    }

    pub fn delete(&mut self, id: uuid::Uuid) {
        if let Some(idx) = self.templates.iter().position(|t| t.id == id && !t.is_built_in) {
            self.templates.remove(idx);
            self.save();
        }
    }

    fn save(&self) {
        if let Some(parent) = self.path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let stored = StorageFormat { version: 1, templates: self.templates.clone() };
        if let Ok(json) = serde_json::to_string_pretty(&stored) {
            let _ = std::fs::write(&self.path, json);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn loads_built_ins_when_no_file() {
        let dir = tempdir().unwrap();
        let store = TemplateStore::load_from(dir.path().join("templates.json"));
        assert_eq!(store.templates().len(), 6);
    }

    #[test]
    fn custom_template_persists() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("templates.json");
        let mut store = TemplateStore::load_from(path.clone());
        let t = crate::models::MeetingTemplate {
            id: uuid::Uuid::new_v4(),
            name: "My Template".into(),
            icon: "star".into(),
            system_prompt: "Be helpful.".into(),
            is_built_in: false,
        };
        store.add(t);
        let store2 = TemplateStore::load_from(path);
        assert!(store2.templates().iter().any(|x| x.name == "My Template"));
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core template_store -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/storage/template_store.rs
git commit -m "feat(core): implement TemplateStore with built-in templates"
```

---

### Task 8: Audio Capture Traits

Define the `AudioCaptureService` and `MicCaptureService` traits that both platform implementations and the engine depend on.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/audio/mod.rs`

- [ ] **Step 1: Create `audio/mod.rs`**

```rust
pub mod cpal_mic;

use async_trait::async_trait;
use futures::stream::BoxStream;
use std::error::Error;

pub type AudioStream = BoxStream<'static, Vec<f32>>;

/// Cross-platform interface for system audio capture (the "them" speaker).
/// Implementations: WASAPI loopback (Windows), CoreAudio tap (Mac).
#[async_trait]
pub trait AudioCaptureService: Send + Sync {
    fn audio_level(&self) -> f32;
    async fn buffer_stream(&self) -> Result<AudioStream, Box<dyn Error + Send + Sync>>;
    fn finish_stream(&self);
    async fn stop(&self);
}

/// Microphone capture service — extends AudioCaptureService with device selection.
#[async_trait]
pub trait MicCaptureService: Send + Sync {
    fn audio_level(&self) -> f32;

    /// Returns a stream for the named device, or the system default if `device_name` is None.
    fn buffer_stream_for_device(&self, device_name: Option<&str>) -> AudioStream;

    async fn is_authorized(&self) -> bool;
    fn finish_stream(&self);
    async fn stop(&self);
}
```

- [ ] **Step 2: Create placeholder `cpal_mic.rs`**

```rust
// Implemented in Task 9
```

- [ ] **Step 3: Verify it compiles**

```bash
cd OpenOats && cargo check -p openoats-core 2>&1 | grep "audio"
```
Expected: no errors for the audio module.

- [ ] **Step 4: Commit**

```bash
git add OpenOats/crates/openoats-core/src/audio/
git commit -m "feat(core): define AudioCaptureService and MicCaptureService traits"
```

---

### Task 9: VAD

Port the voice activity detector with unified parameters.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/transcription/mod.rs`
- Create: `OpenOats/crates/openoats-core/src/transcription/vad.rs`

- [ ] **Step 1: Create `transcription/mod.rs`**

```rust
pub mod engine;
pub mod streaming_transcriber;
pub mod vad;
pub mod whisper;
```

- [ ] **Step 2: Create placeholder files for engine, streaming_transcriber, whisper**

Each with just:
```rust
// TODO: see Tasks 10, 11, 12
```

- [ ] **Step 3: Write failing test in `vad.rs`**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_is_not_speech() {
        let mut vad = Vad::new();
        let silence = vec![0.0f32; 1600];
        assert!(!vad.process_chunk(&silence));
    }

    #[test]
    fn loud_signal_is_speech() {
        let mut vad = Vad::new();
        let loud: Vec<f32> = (0..1600).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
        assert!(vad.process_chunk(&loud));
    }

    #[test]
    fn rms_below_threshold_is_silence() {
        let mut vad = Vad::new();
        let quiet: Vec<f32> = vec![0.001; 1600]; // RMS = 0.001, below 0.005
        assert!(!vad.process_chunk(&quiet));
    }
}
```

- [ ] **Step 4: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core vad 2>&1 | head -20
```

- [ ] **Step 5: Implement `vad.rs`**

```rust
/// Energy-based Voice Activity Detector.
/// Parameters (unified from Swift/Rust divergence):
///   RMS threshold: 0.005
///   Chunk size:    1600 samples (100 ms at 16 kHz)
///   Silence end:   5 consecutive silent chunks (500 ms)
pub struct Vad {
    pub rms_threshold: f32,
}

impl Vad {
    pub const CHUNK_SIZE: usize = 1_600;
    pub const SILENCE_END_CHUNKS: usize = 5;
    pub const MIN_SPEECH_SAMPLES: usize = 8_000;
    pub const FLUSH_SAMPLES: usize = 48_000;

    pub fn new() -> Self {
        Self { rms_threshold: 0.005 }
    }

    /// Returns true if the chunk contains speech above the RMS threshold.
    pub fn process_chunk(&mut self, chunk: &[f32]) -> bool {
        let rms = (chunk.iter().map(|s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
        rms > self.rms_threshold
    }
}

impl Default for Vad {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_is_not_speech() {
        let mut vad = Vad::new();
        let silence = vec![0.0f32; 1600];
        assert!(!vad.process_chunk(&silence));
    }

    #[test]
    fn loud_signal_is_speech() {
        let mut vad = Vad::new();
        let loud: Vec<f32> = (0..1600).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
        assert!(vad.process_chunk(&loud));
    }

    #[test]
    fn rms_below_threshold_is_silence() {
        let mut vad = Vad::new();
        let quiet: Vec<f32> = vec![0.001; 1600];
        assert!(!vad.process_chunk(&quiet));
    }
}
```

- [ ] **Step 6: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core vad -- --nocapture
```
Expected: 3 tests pass.

- [ ] **Step 7: Commit**

```bash
git add OpenOats/crates/openoats-core/src/transcription/
git commit -m "feat(core): implement unified VAD (RMS 0.005, 1600-sample chunks)"
```

---

### Task 10: WhisperManager

Wrap `whisper-rs` with language-from-settings support.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/transcription/whisper.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whisper_manager_requires_valid_path() {
        let result = WhisperManager::new("/nonexistent/path/model.bin", "en");
        assert!(result.is_err());
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core whisper 2>&1 | head -20
```

- [ ] **Step 3: Implement `whisper.rs`**

```rust
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters, WhisperState};

pub struct WhisperManager {
    ctx: WhisperContext,
    language: String,
}

impl WhisperManager {
    pub fn new(model_path: &str, language: &str) -> Result<Self, String> {
        let ctx = WhisperContext::new_with_params(model_path, WhisperContextParameters::default())
            .map_err(|e| format!("Failed to load whisper model: {e}"))?;
        Ok(Self { ctx, language: language.to_string() })
    }

    pub fn create_state(&self) -> Result<WhisperState, String> {
        self.ctx.create_state().map_err(|e| e.to_string())
    }

    pub fn transcribe(state: &mut WhisperState, samples: &[f32], language: &str) -> String {
        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 0 });
        params.set_n_threads(4);
        params.set_language(Some(language));
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);
        params.set_single_segment(false);
        params.set_no_context(true);
        params.set_suppress_blank(true);

        if state.full(params, samples).is_err() {
            return String::new();
        }

        let n = state.full_n_segments().unwrap_or(0);
        let mut text = String::new();
        for i in 0..n {
            if let Ok(seg) = state.full_get_segment_text(i) {
                text.push_str(&seg);
            }
        }
        text.trim().to_string()
    }

    pub fn language(&self) -> &str {
        &self.language
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn whisper_manager_requires_valid_path() {
        let result = WhisperManager::new("/nonexistent/path/model.bin", "en");
        assert!(result.is_err());
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core whisper -- --nocapture
```
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/transcription/whisper.rs
git commit -m "feat(core): implement WhisperManager with language-from-settings"
```

---

### Task 11: StreamingTranscriber

VAD + whisper pipeline that consumes a `futures::Stream<Item = Vec<f32>>`.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/transcription/streaming_transcriber.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream;

    #[tokio::test]
    async fn silence_produces_no_transcription() {
        let (tx, rx) = std::sync::mpsc::channel();
        let on_final = move |text: String| { tx.send(text).ok(); };

        let transcriber = StreamingTranscriber::new_passthrough(
            Box::new(on_final),
        );

        // 3 seconds of silence
        let silence: Vec<Vec<f32>> = (0..30).map(|_| vec![0.0f32; 1600]).collect();
        let s = stream::iter(silence);
        transcriber.run(s).await;

        assert!(rx.try_recv().is_err(), "silence should produce no transcription");
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core streaming_transcriber 2>&1 | head -20
```

- [ ] **Step 3: Implement `streaming_transcriber.rs`**

The transcriber does not hold a WhisperState directly (whisper-rs state is `!Send`) — it sends segments to a dedicated transcription thread and gets results back via a channel.

```rust
use crate::transcription::vad::Vad;
use futures::Stream;
use std::sync::mpsc;
use std::thread;

pub type OnFinal = Box<dyn Fn(String) + Send + 'static>;

pub struct StreamingTranscriber {
    on_final: OnFinal,
    /// Optional: path to whisper model. If None, transcriber runs in passthrough mode (VAD only).
    model_path: Option<String>,
    language: String,
}

impl StreamingTranscriber {
    pub fn new(model_path: String, language: String, on_final: OnFinal) -> Self {
        Self { on_final, model_path: Some(model_path), language }
    }

    /// Test-only: passthrough mode that skips actual transcription.
    pub fn new_passthrough(on_final: OnFinal) -> Self {
        Self { on_final, model_path: None, language: "en".into() }
    }

    pub async fn run<S>(self, stream: S)
    where
        S: Stream<Item = Vec<f32>> + Send + 'static,
    {
        use futures::StreamExt;

        // Spin up transcription thread if we have a model
        let (seg_tx, seg_rx) = mpsc::sync_channel::<Vec<f32>>(10);
        let on_final = self.on_final;
        let language = self.language.clone();
        let model_path = self.model_path.clone();

        let transcribe_thread = thread::spawn(move || {
            if let Some(path) = model_path {
                match crate::transcription::whisper::WhisperManager::new(&path, &language) {
                    Ok(manager) => {
                        let mut state = match manager.create_state() {
                            Ok(s) => s,
                            Err(e) => { log::error!("whisper state: {e}"); return; }
                        };
                        for samples in seg_rx.iter() {
                            let text = crate::transcription::whisper::WhisperManager::transcribe(
                                &mut state, &samples, &language,
                            );
                            if !text.is_empty() {
                                log::info!("[transcriber] {}", &text[..text.len().min(80)]);
                                on_final(text);
                            }
                        }
                    }
                    Err(e) => log::error!("Failed to load whisper model: {e}"),
                }
            }
            // passthrough mode: drain and discard
            for _ in seg_rx.iter() {}
        });

        let mut vad = Vad::new();
        let mut vad_buf: Vec<f32> = Vec::new();
        let mut speech_buf: Vec<f32> = Vec::new();
        let mut speaking = false;
        let mut silence_count = 0usize;

        let mut stream = Box::pin(stream);
        while let Some(samples) = stream.next().await {
            vad_buf.extend_from_slice(&samples);

            while vad_buf.len() >= Vad::CHUNK_SIZE {
                let chunk: Vec<f32> = vad_buf.drain(..Vad::CHUNK_SIZE).collect();
                let active = vad.process_chunk(&chunk);

                if active {
                    silence_count = 0;
                    speaking = true;
                    speech_buf.extend_from_slice(&chunk);
                } else if speaking {
                    silence_count += 1;
                    speech_buf.extend_from_slice(&chunk);

                    if silence_count >= Vad::SILENCE_END_CHUNKS {
                        speaking = false;
                        silence_count = 0;
                        if speech_buf.len() > Vad::MIN_SPEECH_SAMPLES {
                            let _ = seg_tx.send(std::mem::take(&mut speech_buf));
                        } else {
                            speech_buf.clear();
                        }
                    }
                }

                if speaking && speech_buf.len() >= Vad::FLUSH_SAMPLES {
                    let _ = seg_tx.send(std::mem::take(&mut speech_buf));
                }
            }
        }

        // Flush remainder
        if speech_buf.len() > Vad::MIN_SPEECH_SAMPLES {
            let _ = seg_tx.send(speech_buf);
        }

        drop(seg_tx);
        let _ = transcribe_thread.join();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::stream;

    #[tokio::test]
    async fn silence_produces_no_transcription() {
        let (tx, rx) = std::sync::mpsc::channel();
        let on_final = move |text: String| { tx.send(text).ok(); };
        let transcriber = StreamingTranscriber::new_passthrough(Box::new(on_final));
        let silence: Vec<Vec<f32>> = (0..30).map(|_| vec![0.0f32; 1600]).collect();
        transcriber.run(stream::iter(silence)).await;
        assert!(rx.try_recv().is_err());
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core streaming_transcriber -- --nocapture
```
Expected: 1 test passes.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/transcription/streaming_transcriber.rs
git commit -m "feat(core): implement StreamingTranscriber (VAD + whisper pipeline)"
```

---

### Task 12: CPAL Mic Capture

Cross-platform mic capture with device enumeration by name.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/audio/cpal_mic.rs`

This is ported from the existing `OpenOatsTauri/src-tauri/src/audio.rs` with two key changes:
1. Device selection by name (not integer ID)
2. Implements the `MicCaptureService` trait

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_available_devices() {
        let devices = CpalMicCapture::available_device_names();
        // On any machine with audio hardware, at least one device should be present.
        // On CI with no audio, this may be empty — that is acceptable.
        println!("Available mic devices: {:?}", devices);
        // No panic = pass
    }

    #[test]
    fn default_device_name_is_some_or_none() {
        let name = CpalMicCapture::default_device_name();
        println!("Default device: {:?}", name);
        // No panic = pass
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core cpal_mic 2>&1 | head -20
```

- [ ] **Step 3: Implement `cpal_mic.rs`**

Move and adapt the logic from `OpenOatsTauri/src-tauri/src/audio.rs`. Key changes: takes `Option<&str>` device name instead of `UInt32`.

```rust
use crate::audio::{AudioStream, MicCaptureService};
use async_trait::async_trait;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, Stream};
use futures::stream;
use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, Mutex,
};
use tokio::sync::mpsc;

const TARGET_RATE: u32 = 16_000;
const CHUNK_SIZE: usize = 480;

pub struct CpalMicCapture {
    finished: Arc<AtomicBool>,
    audio_level: Arc<Mutex<f32>>,
    _stream: Option<Arc<Mutex<Stream>>>,
}

unsafe impl Send for CpalMicCapture {}
unsafe impl Sync for CpalMicCapture {}

impl CpalMicCapture {
    pub fn new() -> Self {
        Self {
            finished: Arc::new(AtomicBool::new(false)),
            audio_level: Arc::new(Mutex::new(0.0)),
            _stream: None,
        }
    }

    /// Returns names of all available input devices.
    pub fn available_device_names() -> Vec<String> {
        let host = cpal::default_host();
        host.input_devices()
            .map(|devs| devs.filter_map(|d| d.name().ok()).collect())
            .unwrap_or_default()
    }

    /// Returns the name of the default input device, if any.
    pub fn default_device_name() -> Option<String> {
        cpal::default_host().default_input_device()?.name().ok()
    }
}

#[async_trait]
impl MicCaptureService for CpalMicCapture {
    fn audio_level(&self) -> f32 {
        *self.audio_level.lock().unwrap()
    }

    fn buffer_stream_for_device(&self, device_name: Option<&str>) -> AudioStream {
        let host = cpal::default_host();

        let device = if let Some(name) = device_name {
            host.input_devices()
                .ok()
                .and_then(|mut devs| devs.find(|d| d.name().ok().as_deref() == Some(name)))
                .or_else(|| host.default_input_device())
        } else {
            host.default_input_device()
        };

        let Some(device) = device else {
            log::error!("No input device available");
            return Box::pin(stream::empty());
        };

        let (tx, mut rx) = mpsc::channel::<Vec<f32>>(500);
        let finished = self.finished.clone();
        let level_arc = self.audio_level.clone();

        let Ok(config) = device.default_input_config() else {
            return Box::pin(stream::empty());
        };

        let sample_rate = config.sample_rate().0;
        let channels = config.channels() as usize;
        let needs_resample = sample_rate != TARGET_RATE;

        let mut resampler = if needs_resample {
            let sinc_params = SincInterpolationParameters {
                sinc_len: 64,
                f_cutoff: 0.95,
                interpolation: SincInterpolationType::Linear,
                oversampling_factor: 64,
                window: WindowFunction::BlackmanHarris2,
            };
            SincFixedIn::<f32>::new(
                TARGET_RATE as f64 / sample_rate as f64,
                1.0,
                sinc_params,
                CHUNK_SIZE,
                1,
            ).ok()
        } else {
            None
        };

        let mut ring: Vec<f32> = Vec::new();
        let err_fn = |err| log::error!("Audio stream error: {}", err);
        let tx_clone = tx.clone();

        let process = move |mono: Vec<f32>| {
            // Update audio level (RMS)
            let rms = (mono.iter().map(|s| s * s).sum::<f32>() / mono.len() as f32).sqrt();
            *level_arc.lock().unwrap() = rms;

            if finished.load(Ordering::Relaxed) { return; }

            if let Some(ref mut resampler) = resampler {
                ring.extend_from_slice(&mono);
                while ring.len() >= CHUNK_SIZE {
                    let chunk: Vec<f32> = ring.drain(..CHUNK_SIZE).collect();
                    if let Ok(out) = resampler.process(&[chunk], None) {
                        if let Some(ch) = out.into_iter().next() {
                            if !ch.is_empty() { tx_clone.try_send(ch).ok(); }
                        }
                    }
                }
            } else {
                tx_clone.try_send(mono).ok();
            }
        };

        let stream = match config.sample_format() {
            SampleFormat::F32 => device.build_input_stream(
                &config.into(),
                move |data: &[f32], _: &_| {
                    let mono: Vec<f32> = data.chunks(channels)
                        .map(|c| c.iter().sum::<f32>() / c.len() as f32)
                        .collect();
                    process(mono);
                },
                err_fn, None,
            ),
            SampleFormat::I16 => {
                let process2 = process;
                device.build_input_stream(
                    &config.into(),
                    move |data: &[i16], _: &_| {
                        let mono: Vec<f32> = data.chunks(channels)
                            .map(|c| c.iter().map(|&s| s as f32 / 32768.0).sum::<f32>() / c.len() as f32)
                            .collect();
                        process2(mono);
                    },
                    err_fn, None,
                )
            },
            SampleFormat::U16 => {
                let process3 = process;
                device.build_input_stream(
                    &config.into(),
                    move |data: &[u16], _: &_| {
                        let mono: Vec<f32> = data.chunks(channels)
                            .map(|c| c.iter().map(|&s| (s as f32 - 32768.0) / 32768.0).sum::<f32>() / c.len() as f32)
                            .collect();
                        process3(mono);
                    },
                    err_fn, None,
                )
            },
            fmt => {
                log::error!("Unsupported sample format: {:?}", fmt);
                return Box::pin(stream::empty());
            }
        };

        match stream {
            Ok(s) => {
                if let Err(e) = s.play() {
                    log::error!("Failed to start mic stream: {e}");
                    return Box::pin(stream::empty());
                }
                // Keep stream alive via background task
                tokio::spawn(async move {
                    let _s = s; // keep alive
                    while rx.recv().await.is_some() {}
                });
            }
            Err(e) => {
                log::error!("Failed to build mic stream: {e}");
                return Box::pin(stream::empty());
            }
        }

        Box::pin(tokio_stream::wrappers::ReceiverStream::new(rx))
    }

    async fn is_authorized(&self) -> bool {
        // On Windows, mic access is controlled via system settings.
        // cpal will fail to open the device if access is denied — no pre-check needed.
        true
    }

    fn finish_stream(&self) {
        self.finished.store(true, Ordering::Relaxed);
    }

    async fn stop(&self) {
        self.finish_stream();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_available_devices() {
        let devices = CpalMicCapture::available_device_names();
        println!("Available mic devices: {:?}", devices);
    }

    #[test]
    fn default_device_name_is_some_or_none() {
        let name = CpalMicCapture::default_device_name();
        println!("Default device: {:?}", name);
    }
}
```

Add `tokio-stream` to `openoats-core/Cargo.toml` dependencies:
```toml
tokio-stream = "0.1"
```

**Note on Tokio runtime:** `buffer_stream_for_device` is a sync fn that calls `tokio::spawn` internally. This requires an active Tokio runtime at the call site. It will always be called from within `tokio::spawn` in `start_transcription`, so this is safe at runtime. Do not call it outside a Tokio context (e.g. bare `#[test]` — use `#[tokio::test]` if needed).

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core cpal_mic -- --nocapture
```
Expected: 2 tests pass (no panic).

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/audio/cpal_mic.rs OpenOats/crates/openoats-core/Cargo.toml
git commit -m "feat(core): implement CpalMicCapture with named device selection"
```

---

### Task 13: TranscriptionEngine

Orchestrates mic and system audio captures into dual `StreamingTranscriber` instances — the spec-required `transcription/engine.rs` module.

**Files:**
- Modify: `OpenOats/crates/openoats-core/src/transcription/engine.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_starts_not_running() {
        let engine = TranscriptionEngine::new();
        assert!(!engine.is_running());
    }

    #[test]
    fn engine_reports_error_with_missing_model() {
        let engine = TranscriptionEngine::new();
        let result = engine.validate_model("/nonexistent/path.bin");
        assert!(result.is_err());
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core engine 2>&1 | head -20
```

- [ ] **Step 3: Implement `transcription/engine.rs`**

```rust
use std::sync::{Arc, Mutex};

/// Orchestrates mic and system audio transcription.
/// Holds runtime state: whether transcription is active and any last error.
/// Platform audio implementations are injected at `start()` time via closures.
pub struct TranscriptionEngine {
    is_running: Arc<Mutex<bool>>,
    last_error: Arc<Mutex<Option<String>>>,
}

impl TranscriptionEngine {
    pub fn new() -> Self {
        Self {
            is_running: Arc::new(Mutex::new(false)),
            last_error: Arc::new(Mutex::new(None)),
        }
    }

    pub fn is_running(&self) -> bool {
        *self.is_running.lock().unwrap()
    }

    pub fn last_error(&self) -> Option<String> {
        self.last_error.lock().unwrap().clone()
    }

    pub fn validate_model(&self, model_path: &str) -> Result<(), String> {
        if std::path::Path::new(model_path).exists() {
            Ok(())
        } else {
            Err(format!("Model not found: {}", model_path))
        }
    }

    pub fn set_running(&self, running: bool) {
        *self.is_running.lock().unwrap() = running;
    }

    pub fn set_error(&self, error: Option<String>) {
        *self.last_error.lock().unwrap() = error;
    }
}

impl Default for TranscriptionEngine {
    fn default() -> Self { Self::new() }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_starts_not_running() {
        let engine = TranscriptionEngine::new();
        assert!(!engine.is_running());
    }

    #[test]
    fn engine_reports_error_with_missing_model() {
        let engine = TranscriptionEngine::new();
        let result = engine.validate_model("/nonexistent/path.bin");
        assert!(result.is_err());
    }
}
```

- [ ] **Step 4: Update `transcription/mod.rs` to declare the engine module**

```rust
pub mod engine;
pub mod streaming_transcriber;
pub mod vad;
pub mod whisper;
```

- [ ] **Step 5: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core engine -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 6: Commit**

```bash
git add OpenOats/crates/openoats-core/src/transcription/engine.rs OpenOats/crates/openoats-core/src/transcription/mod.rs
git commit -m "feat(core): add TranscriptionEngine state orchestrator"
```

---

### Task 14: Model Download

Move model download from `ureq` (blocking) to `reqwest` (async) inside `openoats-core`.

**Files:**
- Create: `OpenOats/crates/openoats-core/src/download.rs`

- [ ] **Step 1: Write the failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn model_exists_check_returns_false_for_missing() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ggml-base.en.bin");
        assert!(!model_exists(&path));
    }

    #[test]
    fn model_exists_check_returns_true_when_present() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ggml-base.en.bin");
        std::fs::write(&path, b"fake model").unwrap();
        assert!(model_exists(&path));
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd OpenOats && cargo test -p openoats-core download 2>&1 | head -20
```

- [ ] **Step 3: Implement `download.rs`**

```rust
use std::path::{Path, PathBuf};

const MODEL_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";

pub fn model_exists(path: &Path) -> bool {
    path.exists()
}

/// Download the Whisper model to `dest`, emitting progress via `on_progress(pct: u32)`.
/// Uses a `.tmp` file then renames atomically on completion.
pub async fn download_model<F>(dest: PathBuf, on_progress: F) -> Result<(), String>
where
    F: Fn(u32) + Send + 'static,
{
    use reqwest::Client;
    use tokio::io::AsyncWriteExt;

    if dest.exists() {
        return Ok(());
    }

    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }

    let client = Client::new();
    let resp = client.get(MODEL_URL).send().await.map_err(|e| e.to_string())?;

    if !resp.status().is_success() {
        return Err(format!("HTTP {}", resp.status()));
    }

    let total = resp.content_length().unwrap_or(0);
    let mut stream = resp.bytes_stream();
    let tmp = dest.with_extension("tmp");
    let mut file = tokio::fs::File::create(&tmp).await.map_err(|e| e.to_string())?;

    let mut downloaded: u64 = 0;
    use futures::StreamExt;
    while let Some(chunk) = stream.next().await {
        let bytes = chunk.map_err(|e| e.to_string())?;
        file.write_all(&bytes).await.map_err(|e| e.to_string())?;
        downloaded += bytes.len() as u64;
        if total > 0 {
            on_progress((downloaded * 100 / total) as u32);
        }
    }

    file.flush().await.map_err(|e| e.to_string())?;
    drop(file);
    std::fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;
    log::info!("Model downloaded to {}", dest.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn model_exists_check_returns_false_for_missing() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ggml-base.en.bin");
        assert!(!model_exists(&path));
    }

    #[test]
    fn model_exists_check_returns_true_when_present() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("ggml-base.en.bin");
        std::fs::write(&path, b"fake model").unwrap();
        assert!(model_exists(&path));
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd OpenOats && cargo test -p openoats-core download -- --nocapture
```
Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenOats/crates/openoats-core/src/download.rs
git commit -m "feat(core): implement async model download via reqwest"
```

---

### Task 14: Wire Tauri Commands to Core

Replace the existing Tauri `engine.rs`, `audio.rs`, `transcriber.rs` with thin wrappers over `openoats-core`.

**Files:**
- Modify: `OpenOats/OpenOatsTauri/src-tauri/src/engine.rs`
- Modify: `OpenOats/OpenOatsTauri/src-tauri/src/lib.rs`
- Delete: `OpenOats/OpenOatsTauri/src-tauri/src/audio.rs`
- Delete: `OpenOats/OpenOatsTauri/src-tauri/src/transcriber.rs`

- [ ] **Step 1: Rewrite `engine.rs`**

```rust
use openoats_core::{
    audio::cpal_mic::CpalMicCapture,
    download,
    settings::AppSettings,
    storage::{session_store::SessionStore, transcript_logger::TranscriptLogger},
    transcription::streaming_transcriber::StreamingTranscriber,
};
use serde::Serialize;
use std::sync::{Arc, Mutex};
use std::path::PathBuf;
use tauri::{AppHandle, Emitter, Manager};

#[derive(Clone, Serialize)]
pub struct TranscriptPayload {
    pub text: String,
    pub speaker: String,
}

pub struct AppState {
    pub settings: Mutex<AppSettings>,
    pub session_store: Mutex<SessionStore>,
    pub transcript_logger: Mutex<TranscriptLogger>,
    pub audio_task: Mutex<Option<tokio::task::JoinHandle<()>>>,
    pub is_running: Mutex<bool>,
}

impl AppState {
    pub fn new() -> Self {
        let settings = AppSettings::load();
        let session_store = SessionStore::with_default_path();
        let transcript_logger = TranscriptLogger::with_default_path();
        Self {
            settings: Mutex::new(settings),
            session_store: Mutex::new(session_store),
            transcript_logger: Mutex::new(transcript_logger),
            audio_task: Mutex::new(None),
            is_running: Mutex::new(false),
        }
    }

    pub fn model_path(app: &AppHandle) -> Result<PathBuf, String> {
        app.path()
            .app_data_dir()
            .map(|p| p.join("ggml-base.en.bin"))
            .map_err(|e| e.to_string())
    }
}

// ── Tauri commands ─────────────────────────────────────────────────────────────

#[tauri::command]
pub fn check_model(app: AppHandle) -> Result<bool, String> {
    let path = AppState::model_path(&app)?;
    Ok(download::model_exists(&path))
}

#[tauri::command]
pub fn get_model_path(app: AppHandle) -> Result<String, String> {
    AppState::model_path(&app).map(|p| p.to_string_lossy().into_owned())
}

#[tauri::command]
pub fn get_settings(state: tauri::State<'_, Arc<AppState>>) -> AppSettings {
    state.settings.lock().unwrap().clone()
}

#[tauri::command]
pub fn save_settings(
    new_settings: AppSettings,
    state: tauri::State<'_, Arc<AppState>>,
) {
    let mut s = state.settings.lock().unwrap();
    *s = new_settings;
    s.save();
}

#[tauri::command]
pub fn list_mic_devices() -> Vec<String> {
    CpalMicCapture::available_device_names()
}

#[tauri::command]
pub fn start_transcription(
    app: AppHandle,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<(), String> {
    let model_path = AppState::model_path(&app)?;
    if !download::model_exists(&model_path) {
        return Err("Whisper model not found. Download it first.".into());
    }

    let mut running = state.is_running.lock().unwrap();
    if *running { return Ok(()); }
    *running = true;
    drop(running);

    // Start session
    state.session_store.lock().unwrap().start_session();
    state.transcript_logger.lock().unwrap().start_session();

    let model_str = model_path.to_string_lossy().into_owned();
    let app_clone = app.clone();
    let state_clone = Arc::clone(&state);

    let settings = state.settings.lock().unwrap().clone();
    let device_name = settings.input_device_name.clone();
    let language = settings.transcription_locale
        .split('-').next().unwrap_or("en").to_string();

    let handle = tokio::spawn(async move {
        let mic = CpalMicCapture::new();
        let stream = mic.buffer_stream_for_device(device_name.as_deref());

        let app_for_final = app_clone.clone();
        let state_for_final = Arc::clone(&state_clone);

        let on_final = move |text: String| {
            let payload = TranscriptPayload { text: text.clone(), speaker: "you".into() };
            app_for_final.emit("transcript", &payload).ok();

            // Persist to session store
            let record = openoats_core::models::SessionRecord {
                speaker: openoats_core::models::Speaker::You,
                text: text.clone(),
                timestamp: chrono::Utc::now(),
                suggestions: None,
                kb_hits: None,
                suggestion_decision: None,
                surfaced_suggestion_text: None,
                conversation_state_summary: None,
            };
            state_for_final.session_store.lock().unwrap().append_record(&record).ok();
            state_for_final.transcript_logger.lock().unwrap()
                .append("You", &text, chrono::Utc::now());
        };

        app_clone.emit("whisper-ready", ()).ok();

        let transcriber = StreamingTranscriber::new(model_str, language, Box::new(on_final));
        transcriber.run(stream).await;
    });

    *state.audio_task.lock().unwrap() = Some(handle);
    Ok(())
}

#[tauri::command]
pub fn stop_transcription(state: tauri::State<'_, Arc<AppState>>) -> Result<(), String> {
    if let Some(handle) = state.audio_task.lock().unwrap().take() {
        handle.abort();
    }
    state.session_store.lock().unwrap().end_session();
    state.transcript_logger.lock().unwrap().end_session();
    *state.is_running.lock().unwrap() = false;
    Ok(())
}

#[tauri::command]
pub async fn download_model(app: AppHandle) -> Result<(), String> {
    use tauri::Emitter;
    let model_path = AppState::model_path(&app)?;
    let app_clone = app.clone();
    download::download_model(model_path, move |pct| {
        app_clone.emit("model-download-progress", pct).ok();
    }).await?;
    app.emit("model-download-done", ()).ok();
    Ok(())
}
```

- [ ] **Step 2: Rewrite `lib.rs`**

```rust
mod engine;

use std::sync::Arc;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let state = Arc::new(engine::AppState::new());

    tauri::Builder::default()
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            engine::check_model,
            engine::get_model_path,
            engine::get_settings,
            engine::save_settings,
            engine::list_mic_devices,
            engine::start_transcription,
            engine::stop_transcription,
            engine::download_model,
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 3: Delete the old inline files**

```bash
rm OpenOats/OpenOatsTauri/src-tauri/src/audio.rs
rm OpenOats/OpenOatsTauri/src-tauri/src/transcriber.rs
```

- [ ] **Step 4: Add a compile-time test to `engine.rs` verifying the AppState initializes**

Add to the bottom of the rewritten `engine.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_state_initializes_without_panic() {
        let state = AppState::new();
        assert!(!*state.is_running.lock().unwrap());
    }
}
```

- [ ] **Step 5: Run the test**

```bash
cd OpenOats && cargo test -p app app_state 2>&1 | tail -10
```
Expected: 1 test passes.

- [ ] **Step 6: Build the Tauri app to verify**

```bash
cd OpenOats/OpenOatsTauri && cargo tauri build --debug 2>&1 | tail -20
```
Expected: builds successfully (may take a few minutes first time).

- [ ] **Step 7: Smoke test — run the app**

```bash
cd OpenOats/OpenOatsTauri && cargo tauri dev
```
Expected: app launches, "Download Model" or "Start Session" button visible, no crashes.

- [ ] **Step 8: Commit**

```bash
git add OpenOats/OpenOatsTauri/src-tauri/src/
git commit -m "feat: wire Tauri commands to openoats-core, remove inline audio/transcriber"
```

---

### Task 15: Update spec progress checklist

Mark Phase 1 as complete in the spec.

- [ ] **Step 1: Update `docs/superpowers/specs/2026-03-18-multiplatform-design.md`**

In the `## Progress Tracking` section, check off all Phase 1 items.

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-03-18-multiplatform-design.md
git commit -m "docs: mark Phase 1 complete in multiplatform spec"
```

---

## Phase 2 — Windows Feature Parity (Outline)

Each item below becomes its own detailed task when Phase 1 is complete.

### 2.1 WASAPI Loopback System Audio
- Add `audio_windows.rs` to `src-tauri/src/` implementing `AudioCaptureService` via WASAPI loopback
- Add `windows` crate to Tauri Cargo.toml (Windows only, `cfg`)
- Wire "them" speaker events: emit `transcript` with `speaker: "them"`

### 2.2 Intelligence Layer (openoats-core)
- `intelligence/llm_client.rs` — `reqwest` streaming SSE client for OpenRouter + non-streaming for Ollama
- `intelligence/embedding_client.rs` — Voyage AI, Ollama, OpenAI-compatible embedding endpoints
- `intelligence/knowledge_base.rs` — load markdown files, chunk, embed, cosine similarity search, JSON cache
- `intelligence/suggestion_engine.rs` — trigger detection from "them" utterances, KB retrieval, LLM gate, configurable delay
- `intelligence/notes_engine.rs` — format transcript + template prompt → LLM → markdown notes

### 2.3 Tauri Commands for Intelligence
- `get_suggestions`, `generate_notes`, `search_kb`, `update_kb_folder` commands
- Frontend events: `suggestion`, `notes-ready`, `kb-indexed`

### 2.4 Overlay Window
- Add second `WebviewWindow` config in `tauri.conf.json`
- All transcript/suggestion events emitted via `app.emit_all()` reach both windows
- `OverlayView.tsx` — compact transcript feed + current suggestion card

### 2.5 React UI Components
- `ControlBar.tsx` — mic device picker (calls `list_mic_devices`), start/stop, status
- `TranscriptView.tsx` — utterance list, you/them styling, auto-scroll (extend existing)
- `SuggestionsView.tsx` — suggestion cards, helpful/not-helpful buttons
- `NotesView.tsx` — markdown display, template picker dropdown, "Generate Notes" button
- `SettingsView.tsx` — tabbed: Transcription, LLM, Embeddings, KB folder, Privacy
- `SessionHistoryView.tsx` — session list, load transcript, view notes
- `OnboardingView.tsx` — first-run wizard (check `has_completed_onboarding`)
- `ConsentModal.tsx` — recording consent gate, blocks session start until acknowledged

### 2.6 Screen-Share Protection
- Enable `content_protection` in `src-tauri/capabilities/default.json`
- Call `window.set_content_protected(true)` on both main and overlay windows at startup

---

## Phase 3 — Mac Tauri Migration (Outline)

### 3.1 CoreAudio System Audio (Mac)
- Investigate FFI approach: `core-audio-types` crate + `extern "C"` for `AudioHardwareCreateProcessTap`
- If FFI surface is too complex: write thin Swift shim compiled with `cc` crate, exposed via C ABI
- `audio_mac.rs` implements `AudioCaptureService`, wired in on `#[cfg(target_os = "macos")]`

### 3.2 macOS Permissions
- Add `NSMicrophoneUsageDescription` and `NSScreenCaptureUsageDescription` to `Info.plist`
- Add Tauri `microphone` and `screen-capture` capabilities
- Permission request flow in `start_transcription` command on Mac

### 3.3 Auto-Updater
- Add `tauri-plugin-updater` dependency
- Configure `tauri.conf.json` with appcast URL
- Handle App Management permission error (macOS 15+): show user guidance dialog on update failure

### 3.4 Mac Validation
- Manual QA checklist: mic capture, system audio capture, suggestions, notes, overlay, screen-share hiding, updater check
- Deprecate `OpenOatsMac` once all items pass

---

## Phase 4 — Swift Cleanup (Outline)

### 4.1 Remove Swift Sources
```bash
rm -rf OpenOats/Sources/OpenOatsCore
rm -rf OpenOats/Sources/OpenOatsMac
rm -rf OpenOats/Sources/OpenOatsWindows
```

### 4.2 Simplify Package.swift
Remove or replace with a minimal stub (or delete entirely if no Swift remains).

### 4.3 CI / Build Scripts
Update any CI workflows that reference `swift build` or `xcodebuild` to only run `cargo build` and `cargo tauri build`.

---

## Appendix: Running Tests

```bash
# All openoats-core tests
cd OpenOats && cargo test -p openoats-core -- --nocapture

# Specific module
cd OpenOats && cargo test -p openoats-core session_store -- --nocapture

# Full workspace check
cd OpenOats && cargo check --workspace

# Tauri dev build
cd OpenOats/OpenOatsTauri && cargo tauri dev
```
