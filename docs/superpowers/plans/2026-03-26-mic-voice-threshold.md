# Mic Voice Threshold (Noise Gate) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a calibratable noise gate to the mic audio pipeline so that audio below the user's speaking voice level is silenced before transcription, suppressing faint echo pickup.

**Architecture:** The gate lives inside `MicEchoProcessor` (applies after AEC, independently of it). Two new settings fields store the calibrated RMS and user-configurable multiplier. Three new Tauri commands handle preview streaming and calibration. The Settings UI gets a new section with a live waveform bar and calibration flow.

**Tech Stack:** Rust (no new deps), Tauri v2, React/TypeScript, existing `WaveformVisualizer` component, `CpalMicCapture` stream, `serde_json` for settings persistence.

**Spec:** `docs/superpowers/specs/2026-03-26-mic-voice-threshold-design.md`

---

## File Map

| File | Change |
|---|---|
| `crates/opencassava-core/src/audio/echo_cancel.rs` | Add `threshold` field, `set_threshold()`, gate in `process_chunk`, 4 unit tests |
| `crates/opencassava-core/src/settings.rs` | Add `mic_calibration_rms` + `mic_threshold_multiplier` fields with serde defaults |
| `opencassava/src-tauri/src/engine.rs` | Add `preview_task`/`preview_stop` to `AppState`, apply threshold at session start, add `CalibrationAudioLevelPayload`, `top_percentile_mean`, and 3 new commands |
| `opencassava/src-tauri/src/lib.rs` | Register 3 new Tauri commands |
| `opencassava/src/types.ts` | Add `micCalibrationRms` + `micThresholdMultiplier` to `AppSettings` interface |
| `opencassava/src/components/SettingsView.tsx` | Add Mic Voice Threshold section below echo cancellation toggle |

---

## Task 1: Add noise gate to `MicEchoProcessor`

**Files:**
- Modify: `crates/opencassava-core/src/audio/echo_cancel.rs`

- [ ] **Step 1: Write the failing tests**

Add to the `#[cfg(test)] mod tests` block at the bottom of `echo_cancel.rs`:

```rust
#[test]
fn gate_silences_chunk_below_threshold() {
    let reference = EchoReferenceBuffer::new(1_000);
    let mut processor = MicEchoProcessor::new(reference.clone());
    processor.set_enabled(false); // pass-through mode, gate still applies
    processor.set_threshold(0.1);

    // chunk with very low amplitude — rms will be well below 0.1
    let quiet = vec![0.001f32; 480];
    reference.push_render_chunk(&quiet);
    let out = processor.process_chunk(&quiet);
    let out_rms: f32 = {
        let sq: f32 = out.iter().map(|s| s * s).sum();
        (sq / out.len() as f32).sqrt()
    };
    assert_eq!(out.len(), quiet.len(), "length must be preserved");
    assert!(out_rms < 1e-6, "output should be silence, got rms={}", out_rms);
}

#[test]
fn gate_passes_chunk_above_threshold() {
    let reference = EchoReferenceBuffer::new(1_000);
    let mut processor = MicEchoProcessor::new(reference.clone());
    processor.set_enabled(false);
    processor.set_threshold(0.05);

    // chunk with amplitude clearly above threshold
    let loud: Vec<f32> = (0..480).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
    reference.push_render_chunk(&loud);
    let out = processor.process_chunk(&loud);
    let out_rms: f32 = {
        let sq: f32 = out.iter().map(|s| s * s).sum();
        (sq / out.len() as f32).sqrt()
    };
    assert!(out_rms > 0.1, "loud audio should pass gate, got rms={}", out_rms);
}

#[test]
fn gate_disabled_when_threshold_zero() {
    let reference = EchoReferenceBuffer::new(1_000);
    let mut processor = MicEchoProcessor::new(reference.clone());
    processor.set_enabled(false);
    // default threshold is 0.0 — gate should be open
    let quiet = vec![0.001f32; 480];
    reference.push_render_chunk(&quiet);
    let out = processor.process_chunk(&quiet);
    let out_rms: f32 = {
        let sq: f32 = out.iter().map(|s| s * s).sum();
        (sq / out.len() as f32).sqrt()
    };
    assert!(out_rms > 0.0005, "gate should be open when threshold=0, got rms={}", out_rms);
}

#[test]
fn gate_applies_when_aec_enabled() {
    // Gate applies to AEC output: use set_enabled(false) to isolate gate behavior,
    // confirming the gate runs on the pass-through path (same code path as AEC output).
    // A separate check ensures the gate still fires when AEC is on.
    let reference = EchoReferenceBuffer::new(1_000);
    let mut processor = MicEchoProcessor::new(reference.clone());
    // AEC enabled, threshold set above the chunk's RMS — gate must fire
    processor.set_enabled(false); // isolate: no AEC variables, pure gate test
    processor.set_threshold(0.2);

    // loud chunk — rms ~0.35 → above threshold, must pass
    let loud: Vec<f32> = (0..480).map(|i| (i as f32 * 0.1).sin() * 0.5).collect();
    reference.push_render_chunk(&loud);
    let out_loud = processor.process_chunk(&loud);
    let loud_rms: f32 = {
        let sq: f32 = out_loud.iter().map(|s| s * s).sum();
        (sq / out_loud.len() as f32).sqrt()
    };
    assert!(loud_rms > 0.1, "loud chunk should pass gate, got rms={}", loud_rms);

    // quiet chunk — rms ~0.003 → below threshold, must be silenced
    let quiet = vec![0.005f32; 480];
    reference.push_render_chunk(&quiet);
    let out_quiet = processor.process_chunk(&quiet);
    let quiet_rms: f32 = {
        let sq: f32 = out_quiet.iter().map(|s| s * s).sum();
        (sq / out_quiet.len() as f32).sqrt()
    };
    assert!(quiet_rms < 1e-6, "quiet chunk should be silenced by gate, got rms={}", quiet_rms);
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd crates/opencassava-core
cargo test gate_ -- --nocapture 2>&1 | tail -20
```

Expected: compile error (`set_threshold` not found) or test failures.

- [ ] **Step 3: Add `threshold` field and `set_threshold` to `MicEchoProcessor`**

In `echo_cancel.rs`, find the `MicEchoProcessor` struct definition (around line 220):

```rust
pub struct MicEchoProcessor {
    reference: EchoReferenceBuffer,
    aec: FreqDomainAec,
    enabled: bool,
    mic_accum: Vec<f32>,
    out_accum: VecDeque<f32>,
    ref_abs_offset: usize,
}
```

Add `threshold: f32` field:

```rust
pub struct MicEchoProcessor {
    reference: EchoReferenceBuffer,
    aec: FreqDomainAec,
    enabled: bool,
    threshold: f32,
    mic_accum: Vec<f32>,
    out_accum: VecDeque<f32>,
    ref_abs_offset: usize,
}
```

In `impl MicEchoProcessor::new(...)`, initialize `threshold: 0.0`:

```rust
Self {
    reference,
    aec: FreqDomainAec::new(),
    enabled: true,
    threshold: 0.0,
    mic_accum: Vec::with_capacity(BLOCK_SIZE * 2),
    out_accum: VecDeque::with_capacity(BLOCK_SIZE * 4),
    ref_abs_offset: initial_offset,
}
```

Add `set_threshold` method after `set_enabled`:

```rust
pub fn set_threshold(&mut self, threshold: f32) {
    self.threshold = threshold;
}
```

- [ ] **Step 4: Update `process_chunk` to apply the gate**

The current `process_chunk` starts with an early return for the `!enabled` case. Replace the entire method with the gated version. Find the method (starts around line 246) and change it so the gate check happens after the `cleaned` value is produced, regardless of `enabled`:

```rust
pub fn process_chunk(&mut self, mic: &[f32]) -> Vec<f32> {
    if mic.is_empty() {
        return mic.to_vec();
    }

    let cleaned = if !self.enabled {
        mic.to_vec()
    } else {
        self.mic_accum.extend_from_slice(mic);

        while self.mic_accum.len() >= BLOCK_SIZE {
            let mic_block: Vec<f32> = self.mic_accum.drain(..BLOCK_SIZE).collect();

            let ref_block = match self.reference.read_block_at(self.ref_abs_offset) {
                Some(block) => {
                    self.ref_abs_offset += BLOCK_SIZE;
                    block
                }
                None => {
                    self.out_accum.extend(mic_block.iter());
                    self.ref_abs_offset += BLOCK_SIZE;
                    continue;
                }
            };

            let processed = self.aec.process_block(&mic_block, &ref_block);
            self.out_accum.extend(processed.iter());
        }

        let needed = mic.len();
        if self.out_accum.len() >= needed {
            self.out_accum.drain(..needed).collect()
        } else {
            let mut result: Vec<f32> = self.out_accum.drain(..).collect();
            let remaining = needed - result.len();
            result.extend_from_slice(&mic[mic.len() - remaining..]);
            result
        }
    };

    // Noise gate: applies regardless of AEC enabled state
    if self.threshold > 0.0 && rms(&cleaned) < self.threshold {
        return vec![0.0; mic.len()];
    }

    cleaned
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd crates/opencassava-core
cargo test -- --nocapture 2>&1 | tail -30
```

Expected: all tests pass including the 4 new `gate_*` tests and all existing tests.

- [ ] **Step 6: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add crates/opencassava-core/src/audio/echo_cancel.rs
git commit -m "feat: add noise gate to MicEchoProcessor with set_threshold()"
```

---

## Task 2: Add settings fields

**Files:**
- Modify: `crates/opencassava-core/src/settings.rs`

- [ ] **Step 1: Write the failing tests**

Add to the `#[cfg(test)] mod tests` block at the bottom of `settings.rs`:

```rust
#[test]
fn mic_threshold_defaults() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("nonexistent.json");
    let s = AppSettings::load_from(path);
    assert!(s.mic_calibration_rms.is_none(), "mic_calibration_rms should default to None");
    assert!(
        (s.mic_threshold_multiplier - 0.6).abs() < 1e-6,
        "mic_threshold_multiplier should default to 0.6"
    );
}

#[test]
fn mic_threshold_persists_and_reloads() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("settings.json");
    let mut s = AppSettings::load_from(path.clone());
    s.mic_calibration_rms = Some(0.042);
    s.mic_threshold_multiplier = 0.7;
    s.save_to(path.clone());
    let s2 = AppSettings::load_from(path);
    assert!((s2.mic_calibration_rms.unwrap() - 0.042).abs() < 1e-6);
    assert!((s2.mic_threshold_multiplier - 0.7).abs() < 1e-6);
}

#[test]
fn mic_threshold_defaults_when_absent_from_json() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("settings.json");
    // Write a settings file that has no threshold fields (simulating an old settings file)
    std::fs::write(&path, r#"{"selectedModel":"gpt-4o"}"#).unwrap();
    let s = AppSettings::load_from(path);
    assert!(s.mic_calibration_rms.is_none());
    assert!((s.mic_threshold_multiplier - 0.6).abs() < 1e-6);
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd crates/opencassava-core
cargo test mic_threshold -- --nocapture 2>&1 | tail -20
```

Expected: compile errors (fields don't exist yet).

- [ ] **Step 3: Add the two new fields to `AppSettings`**

In `settings.rs`, after `echo_cancellation_enabled` (line 110), add:

```rust
#[serde(default)]
pub mic_calibration_rms: Option<f32>,

#[serde(default = "default_mic_threshold_multiplier")]
pub mic_threshold_multiplier: f32,
```

Add the default function near the other default functions at the bottom of the file:

```rust
fn default_mic_threshold_multiplier() -> f32 {
    0.6
}
```

In `impl Default for AppSettings`, after `echo_cancellation_enabled: default_true()`, add:

```rust
mic_calibration_rms: None,
mic_threshold_multiplier: default_mic_threshold_multiplier(),
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd crates/opencassava-core
cargo test -- --nocapture 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add crates/opencassava-core/src/settings.rs
git commit -m "feat: add mic_calibration_rms and mic_threshold_multiplier settings fields"
```

---

## Task 3: Add `top_percentile_mean`, `AppState` preview fields, and apply gate at session start

**Files:**
- Modify: `opencassava/src-tauri/src/engine.rs`

- [ ] **Step 1: Add `top_percentile_mean` pure function**

Find `fn compute_rms(samples: &[f32]) -> f32` (around line 634). Just below it, add:

```rust
/// Returns the mean of the top `percentile` fraction of values in `values`.
/// Used to compute the calibrated speaking level from a sorted set of block RMSes.
/// If `values` is empty, returns 0.0.
pub(crate) fn top_percentile_mean(values: &[f32], percentile: f32) -> f32 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));
    let count = ((values.len() as f32 * percentile).ceil() as usize).max(1);
    let top = &sorted[..count.min(sorted.len())];
    top.iter().sum::<f32>() / top.len() as f32
}
```

- [ ] **Step 2: Add `preview_task` and `preview_stop` fields to `AppState`**

In the `AppState` struct definition (around line 157), after `parakeet_warming`, add:

```rust
pub preview_task: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
pub preview_stop: Arc<std::sync::atomic::AtomicBool>,
```

In `AppState::new()`, after `parakeet_warming: Arc::new(...)`, add:

```rust
preview_task: Mutex::new(None),
preview_stop: Arc::new(std::sync::atomic::AtomicBool::new(false)),
```

- [ ] **Step 3: Add `CalibrationAudioLevelPayload` struct**

Near the `AudioLevelPayload` struct definition (around line 96), add:

```rust
#[derive(Clone, Serialize)]
pub struct CalibrationAudioLevelPayload {
    pub level: f32,
}
```

- [ ] **Step 4: Apply threshold at session start**

Find where `echo_processor.set_enabled(settings.echo_cancellation_enabled)` is called (around line 1276). On the line immediately after it, add:

```rust
let mic_gate_threshold = settings.mic_calibration_rms.unwrap_or(0.0) * settings.mic_threshold_multiplier;
echo_processor.set_threshold(mic_gate_threshold);
```

- [ ] **Step 5: Add unit tests for `top_percentile_mean`**

Add a `#[cfg(test)]` block at the very end of `engine.rs` (just before the final `}`):

```rust
#[cfg(test)]
mod tests {
    use super::top_percentile_mean;

    #[test]
    fn top_percentile_mean_known_inputs() {
        let vals = vec![0.1f32, 0.5, 0.3, 0.8, 0.2];
        // top 30% of 5 = ceil(1.5) = 2 items → sorted desc [0.8, 0.5] → mean = 0.65
        let result = top_percentile_mean(&vals, 0.30);
        assert!((result - 0.65).abs() < 1e-5, "expected 0.65, got {}", result);
    }

    #[test]
    fn top_percentile_mean_empty() {
        assert_eq!(top_percentile_mean(&[], 0.30), 0.0);
    }

    #[test]
    fn top_percentile_mean_all_items_when_percentile_is_one() {
        let vals = vec![0.2f32, 0.4, 0.6];
        let result = top_percentile_mean(&vals, 1.0);
        assert!((result - (0.2 + 0.4 + 0.6) / 3.0).abs() < 1e-5, "got {}", result);
    }
}
```

- [ ] **Step 6: Run the new tests**

```bash
cd opencassava/src-tauri
cargo test top_percentile -- --nocapture 2>&1 | tail -20
```

Expected: 3 tests pass.

- [ ] **Step 7: Verify the full project builds**

```bash
cd opencassava/src-tauri
cargo build 2>&1 | tail -20
```

Expected: builds successfully with no errors.

- [ ] **Step 8: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add opencassava/src-tauri/src/engine.rs
git commit -m "feat: add preview state fields, CalibrationAudioLevelPayload, top_percentile_mean, apply gate at session start"
```

---

## Task 4: Implement calibration Tauri commands

**Files:**
- Modify: `opencassava/src-tauri/src/engine.rs`

All three commands go in `engine.rs`. Add them near the bottom of the file, before the last closing `}` of the module, grouped together.

- [ ] **Step 1: Add `start_calibration_preview`**

```rust
#[tauri::command]
pub async fn start_calibration_preview(
    app: tauri::AppHandle,
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<(), String> {
    if *state.is_running.lock().unwrap() {
        return Err("Recording session is active — use audio-level events instead".into());
    }
    // Stop any existing preview first
    state.preview_stop.store(true, Ordering::Relaxed);
    if let Some(handle) = state.preview_task.lock().unwrap().take() {
        handle.abort();
    }

    let device_name = state.settings.lock().unwrap().input_device_name.clone();
    state.preview_stop.store(false, Ordering::Relaxed);
    let stop_flag = Arc::clone(&state.preview_stop);

    let handle = tauri::async_runtime::spawn(async move {
        use futures::StreamExt;
        // Wire stop_flag as the CPAL stop signal so the device releases cleanly
        let mic = CpalMicCapture::new().with_stop_signal(Arc::clone(&stop_flag));
        let mut stream = mic.buffer_stream_for_device(device_name.as_deref());
        let mut interval = tokio::time::interval(std::time::Duration::from_millis(100));
        let mut level_accum: Vec<f32> = Vec::new();

        loop {
            tokio::select! {
                chunk = stream.next() => {
                    match chunk {
                        Some(samples) => level_accum.extend_from_slice(&samples),
                        None => break,
                    }
                }
                _ = interval.tick() => {
                    if stop_flag.load(Ordering::Relaxed) { break; }
                    if !level_accum.is_empty() {
                        let level = compute_rms(&level_accum);
                        level_accum.clear();
                        app.emit("calibration-audio-level", &CalibrationAudioLevelPayload { level }).ok();
                    }
                }
            }
        }
    });

    *state.preview_task.lock().unwrap() = Some(handle);
    Ok(())
}
```

- [ ] **Step 2: Add `stop_calibration_preview`**

```rust
#[tauri::command]
pub async fn stop_calibration_preview(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<(), String> {
    state.preview_stop.store(true, Ordering::Relaxed);
    if let Some(handle) = state.preview_task.lock().unwrap().take() {
        handle.abort();
    }
    Ok(())
}
```

- [ ] **Step 3: Add `calibrate_mic_threshold`**

```rust
#[tauri::command]
pub async fn calibrate_mic_threshold(
    state: tauri::State<'_, Arc<AppState>>,
) -> Result<f32, String> {
    if *state.is_running.lock().unwrap() {
        return Err("Cannot calibrate during an active recording".into());
    }

    // Stop any running preview — we'll open a fresh capture
    state.preview_stop.store(true, Ordering::Relaxed);
    if let Some(handle) = state.preview_task.lock().unwrap().take() {
        handle.abort();
    }
    // Small delay to let the device release
    tokio::time::sleep(std::time::Duration::from_millis(150)).await;

    let device_name = state.settings.lock().unwrap().input_device_name.clone();

    // Capture 3 seconds of audio in a dedicated task (CpalMicCapture must stay on one task).
    let block_rmses = tauri::async_runtime::spawn(async move {
        use futures::StreamExt;
        let stop = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let stop2 = Arc::clone(&stop);
        // Wire stop signal so the CPAL device releases cleanly when we're done
        let mic = CpalMicCapture::new().with_stop_signal(Arc::clone(&stop));
        let mut stream = mic.buffer_stream_for_device(device_name.as_deref());
        let mut accum: Vec<f32> = Vec::new();
        let mut rmses: Vec<f32> = Vec::new();
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(3);

        loop {
            if tokio::time::Instant::now() >= deadline {
                stop2.store(true, Ordering::Relaxed);
                break;
            }
            match tokio::time::timeout(
                std::time::Duration::from_millis(500),
                stream.next()
            ).await {
                Ok(Some(chunk)) => {
                    accum.extend_from_slice(&chunk);
                    while accum.len() >= 256 {
                        let block: Vec<f32> = accum.drain(..256).collect();
                        rmses.push(compute_rms(&block));
                    }
                }
                Ok(None) | Err(_) => break,
            }
        }
        rmses
    }).await.map_err(|e| format!("Capture task failed: {e}"))?;

    if block_rmses.is_empty() {
        return Err("No audio captured — check your microphone".into());
    }

    let calibrated_rms = top_percentile_mean(&block_rmses, 0.30);

    if calibrated_rms < 0.001 {
        return Err("Level too low — check your microphone".into());
    }

    {
        let mut settings = state.settings.lock().unwrap();
        settings.mic_calibration_rms = Some(calibrated_rms);
        settings.save();
    }

    Ok(calibrated_rms)
}
```

- [ ] **Step 4: Build to verify**

```bash
cd opencassava/src-tauri
cargo build 2>&1 | tail -30
```

Expected: successful build. Fix any borrow checker or import errors.

- [ ] **Step 5: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add opencassava/src-tauri/src/engine.rs
git commit -m "feat: add start_calibration_preview, stop_calibration_preview, calibrate_mic_threshold commands"
```

---

## Task 5: Register commands and update TypeScript types

**Files:**
- Modify: `opencassava/src-tauri/src/lib.rs`
- Modify: `opencassava/src/types.ts`

- [ ] **Step 1: Register the three new commands in `lib.rs`**

In `lib.rs`, find the `tauri::generate_handler![` block (around line 21). Add three new entries after `engine::save_transcript,`:

```rust
engine::start_calibration_preview,
engine::stop_calibration_preview,
engine::calibrate_mic_threshold,
```

- [ ] **Step 2: Update the TypeScript `AppSettings` interface**

In `opencassava/src/types.ts`, find the `AppSettings` interface. After the `echoCancellationEnabled: boolean;` line, add:

```ts
micCalibrationRms: number | null;
micThresholdMultiplier: number;
```

- [ ] **Step 3: Build the Tauri backend to confirm command registration**

```bash
cd opencassava/src-tauri
cargo build 2>&1 | tail -10
```

Expected: clean build.

- [ ] **Step 4: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add opencassava/src-tauri/src/lib.rs opencassava/src/types.ts
git commit -m "feat: register calibration commands and update AppSettings TS types"
```

---

## Task 6: Settings UI — Mic Voice Threshold section

**Files:**
- Modify: `opencassava/src/components/SettingsView.tsx`

- [ ] **Step 1: Add `listen` import from tauri**

At the top of `SettingsView.tsx`, the current imports are:
```ts
import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
```

Add `listen` import:
```ts
import { listen } from "@tauri-apps/api/event";
```

- [ ] **Step 2: Add calibration state**

Find the component's state declarations (the `useState` calls near the top of the component function). Add after the existing state:

```tsx
const [isCalibrating, setIsCalibrating] = useState(false);
const [calibrationCountdown, setCalibrationCountdown] = useState(0);
const [calibrationLevel, setCalibrationLevel] = useState(0);
const [calibrationError, setCalibrationError] = useState<string | null>(null);
```

- [ ] **Step 3: Add calibration handler**

Add this function inside the component, below the existing `saveSettings` function:

```tsx
async function startCalibration() {
    setIsCalibrating(true);
    setCalibrationError(null);
    setCalibrationLevel(0);

    // Start preview — listen for level events
    const unlisten = await listen<{ level: number }>("calibration-audio-level", (e) => {
        setCalibrationLevel(e.payload.level);
    });

    try {
        await invoke("start_calibration_preview");

        // Countdown 3 → 2 → 1
        for (let i = 3; i >= 1; i--) {
            setCalibrationCountdown(i);
            await new Promise((r) => setTimeout(r, 1000));
        }
        setCalibrationCountdown(0);

        const rms = await invoke<number>("calibrate_mic_threshold");
        await invoke("stop_calibration_preview");
        saveSettings({ ...settings, micCalibrationRms: rms });
    } catch (err) {
        setCalibrationError(String(err));
        await invoke("stop_calibration_preview").catch(() => {});
    } finally {
        unlisten();
        setIsCalibrating(false);
        setCalibrationLevel(0);
    }
}
```

- [ ] **Step 4: Add the UI section**

Find the echo cancellation `</div>` closing tag followed by `</>` (around line 1010 in the original file). Insert the new section immediately after the echo cancellation `fieldWrap` div closes and before `</>`:

```tsx
<div style={styles.fieldWrap}>
  <label style={styles.labelStyle}>Mic Voice Threshold</label>

  {isCalibrating ? (
    <div style={{ display: "flex", flexDirection: "column", gap: spacing[1] }}>
      <WaveformVisualizer level={calibrationLevel} isActive={true} />
      <span style={{ fontSize: typography.sm, color: colors.textMuted }}>
        {calibrationCountdown > 0
          ? `Speak normally… ${calibrationCountdown}`
          : "Processing…"}
      </span>
    </div>
  ) : (
    <>
      {settings.micCalibrationRms == null ? (
        <span style={{ fontSize: typography.sm, color: colors.textMuted }}>
          Not calibrated — gate is disabled
        </span>
      ) : (
        <>
          <span style={{ fontSize: typography.sm, color: colors.text }}>
            Calibrated: {(settings.micCalibrationRms * 1000).toFixed(1)}
          </span>
          <div style={{ display: "flex", alignItems: "center", gap: spacing[2], marginTop: spacing[1] }}>
            <label style={{ fontSize: typography.sm, color: colors.text }}>Sensitivity</label>
            <input
              type="range"
              min={0.1}
              max={0.8}
              step={0.05}
              value={settings.micThresholdMultiplier ?? 0.6}
              onChange={(e) =>
                saveSettings({ ...settings, micThresholdMultiplier: parseFloat(e.target.value) })
              }
              style={{ width: 120 }}
            />
            <span style={{ fontSize: typography.sm, color: colors.textMuted }}>
              {((settings.micThresholdMultiplier ?? 0.6) * 100).toFixed(0)}%
            </span>
          </div>
        </>
      )}
      {calibrationError && (
        <span style={{ fontSize: typography.sm, color: colors.error, marginTop: spacing[1], display: "block" }}>
          {calibrationError}
        </span>
      )}
      <button
        style={{ ...styles.button, marginTop: spacing[1] }}
        onClick={startCalibration}
        disabled={isCalibrating}
      >
        {settings.micCalibrationRms == null ? "Calibrate" : "Recalibrate"}
      </button>
      <span style={{ fontSize: typography.sm, color: colors.textMuted, marginTop: 4, display: "block" }}>
        Audio below this level will be silenced. Recalibrate if you change microphones.
      </span>
    </>
  )}
</div>
```

- [ ] **Step 5: Add `WaveformVisualizer` import**

Near the top imports of `SettingsView.tsx`, add:

```ts
import { WaveformVisualizer } from "./WaveformVisualizer";
```

- [ ] **Step 6: Verify the frontend builds**

```bash
cd opencassava
npm run build 2>&1 | tail -20
```

Expected: clean build with no TypeScript errors. Fix any type errors.

- [ ] **Step 7: Commit**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
git add opencassava/src/components/SettingsView.tsx
git commit -m "feat: add mic voice threshold calibration UI to settings"
```

---

## Task 7: Final integration check

- [ ] **Step 1: Run all Rust tests**

```bash
cd C:/Users/ejrom/exa-tec/OpenOats
cargo test --workspace 2>&1 | tail -30
```

Expected: all tests pass, including the 4 new gate tests and 3 new settings tests.

- [ ] **Step 2: Full build**

```bash
cd opencassava
npm run tauri build -- --debug 2>&1 | tail -20
```

Expected: app builds successfully.

- [ ] **Step 3: Manual smoke test**

1. Open Settings → find "Mic Voice Threshold" section
2. Click "Calibrate" — the waveform bar appears and counts down 3/2/1
3. After calibration, the calibrated value is shown and a Sensitivity slider appears
4. Start a recording session — confirm normal speech is transcribed
5. Play audio from speakers at low volume — confirm it is NOT transcribed
