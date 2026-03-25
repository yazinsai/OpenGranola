# Frequency-Domain Acoustic Echo Cancellation

## Problem

The current NLMS-based echo canceller fails to suppress acoustic echoes in a setup with external speakers and a separate microphone. The time-domain NLMS filter converges too slowly (~625ms), cannot model room impulse responses beyond its 64ms filter length, and produces consistently poor results throughout calls. Echoes leak through to the transcriber, producing garbled "You" utterances that mirror what the remote speaker said.

The text-level echo suppression (Jaccard similarity + n-gram matching) catches some survivors but cannot handle heavily garbled echoes where ASR produces entirely different words.

## Solution

Replace the time-domain NLMS adaptive filter with a Partitioned Block Frequency-Domain Adaptive Filter (PBFDAF). This is the standard approach used by WebRTC, Speex, and all professional AEC systems.

## Design

### Core Algorithm: PBFDAF

The mic and reference signals are processed in fixed-size blocks. Each block is transformed to the frequency domain via FFT, where per-bin adaptive filtering estimates and subtracts the echo.

**Parameters:**
- Block size: 256 samples (16ms at 16kHz)
- Number of partitions: 16 (covers 256ms total impulse response)
- FFT size: 512 points (256 real samples + 256 zero-padding for overlap-save)
- Step size (mu): 0.5
- Regularization: per-bin power estimate with exponential smoothing (alpha = 0.9)

**Per-block processing:**
1. FFT the new mic block and reference block (512-point with zero-padding)
2. For each partition, multiply reference spectrum history by that partition's filter coefficients; sum across all partitions to form the echo estimate spectrum
3. Subtract echo estimate from mic spectrum to get error spectrum
4. IFFT the error spectrum; extract the valid 256-sample block (overlap-save)
5. Update filter coefficients: for each partition, correlate error spectrum with that partition's reference spectrum, normalize by per-bin power estimate

**Why this works better than NLMS:**
- Each frequency bin converges independently (~50-100ms vs 625ms)
- 16 partitions implicitly cover 0-256ms delay without explicit delay search
- Computational cost: ~130K complex ops per 16ms block vs ~1M real ops for equivalent time-domain filter
- Natural spectral selectivity enables per-bin double-talk decisions

### Double-Talk Detection

Per-bin energy comparison between mic and reference, evaluated each block:
- mic energy >> reference energy in a bin: freeze adaptation for that bin (user speaking)
- reference energy >> mic energy: adapt aggressively (pure echo)
- energies similar: reduce mu to 0.1 for that bin (possible double-talk)

This is a **per-bin decision**, so adaptation continues at frequencies dominated by echo while freezing at frequencies dominated by the user's voice. No global double-talk state needed.

### Residual Echo Suppression (Post-Filter)

After adaptive filtering, a spectral post-filter suppresses remaining echo residual:

For each frequency bin:
- Estimate residual echo power: `echo_power = leakage * |reference_spectrum|^2`
- Compute gain: `gain = max(1.0 - alpha * echo_power / mic_power, floor)`
- alpha = 2.0 (slight oversubtraction to catch residual)
- floor = 0.1 (prevents musical noise artifacts by never fully zeroing a bin)
- Apply gain to the cleaned spectrum before final IFFT

### Integration

**Public API unchanged:**
- `EchoReferenceBuffer::push_render_chunk(&self, samples: &[f32])` — unchanged signature
- `MicEchoProcessor::process_chunk(&mut self, mic: &[f32]) -> Vec<f32>` — unchanged signature
- `MicEchoProcessor::set_enabled(&mut self, enabled: bool)` — unchanged

**Internal changes to `echo_cancel.rs`:**
- `NlmsEchoCanceller` replaced by `FreqDomainAec`
- `EchoReferenceBuffer` internals switch from sample-by-sample VecDeque to block-oriented ring buffer storing 256-sample blocks
- `best_match()` and correlation-based alignment removed (partitions handle delay implicitly)
- Post-NLMS heuristic suppression (the `correlation > 0.55` block) replaced by spectral post-filter

**Removed:**
- `AlignedRender` struct
- `normalized_correlation()` function
- `CORRELATION_STRIDE`, `MIN_CORRELATION`, `DEFAULT_MAX_DELAY_MS` constants

**Kept unchanged:**
- `rms()` helper function
- `MIN_RENDER_RMS` constant (used to skip processing when reference is silent)
- All text-level echo suppression in `engine.rs`
- All wiring in `engine.rs`

**Block accumulation:**
Mic chunks arrive in variable sizes (300-450 samples). The processor accumulates samples in an internal buffer and processes 256-sample blocks as they fill. Remainder carries to the next call. Output length always equals input length.

**New dependency:**
- `realfft` crate (pure Rust FFT, wraps `rustfft`, no native dependencies)

### Testing

1. **Pure echo cancellation** — identical signal as reference and mic with delay. Assert cleaned energy < 10% of original.
2. **Double-talk preservation** — reference + independent mic signal simultaneously. Assert mic signal preserved above 70%.
3. **Convergence speed** — measure blocks until 20dB suppression. Assert < 20 blocks (320ms).
4. **Variable chunk sizes** — chunks of 100, 256, 500, 1000 samples. Assert output length matches input exactly.
5. **Delayed echo** — reference signal, then 150ms later as mic. Assert cancellation works across partitions.
6. **Silence preservation** — silent reference, mic signal passes through unmodified.

### Constraints

- User setup: external speakers + separate microphone
- Balance: suppress echoes aggressively but preserve user's speech during double-talk
- Echo is consistently bad throughout calls (not a convergence-only problem)
- Sample rate: 16kHz throughout the pipeline (no resampling needed at AEC boundary)
- Must not increase CPU usage significantly (current pipeline optimized from 84% to 17%)
