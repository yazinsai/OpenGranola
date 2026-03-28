# Design: Migrate omniASR to `LLM_Unlimited_*_v2` family

**Date:** 2026-03-28
**Status:** Approved

## Background

The codebase currently exposes six omniASR model options — three CTC variants and three unversioned LLM variants. Meta's omnilingual-asr library has since published the `omniASR_LLM_Unlimited_*_v2` family, which supports unlimited-length audio transcription and supersedes the older models. The goal is to restrict the codebase to only this new family.

## Scope

Three locations require changes:

| File | What changes |
|---|---|
| `crates/opencassava-core/src/settings.rs` | Default model value + migration map |
| `opencassava/src/components/SettingsView.tsx` | UI model options array |

No changes needed to the Python worker, requirements, or Rust transcription engine — they accept the model name as a string and pass it to fairseq2, so the card name change is transparent to them.

## New Default

`omniASR_LLM_Unlimited_1B_v2` — balanced speed and accuracy, replaces `omniASR_CTC_300M`.

## Migration Map

All old saved values are silently upgraded on load in `AppSettings::load_from`. Any value already in the v2 Unlimited family passes through unchanged via the `other => other` arm.

| Old value(s) | → New value |
|---|---|
| `facebook/omnilingual-asr-300m`, `omnilingual-asr-300m`, `omniASR_CTC_300M` | `omniASR_LLM_Unlimited_300M_v2` |
| `facebook/omnilingual-asr-1b`, `omnilingual-asr-1b`, `omniASR_CTC_1B`, `omniASR_LLM_300M` | `omniASR_LLM_Unlimited_1B_v2` |
| `facebook/omnilingual-asr-3b`, `omnilingual-asr-3b`, `omniASR_CTC_3B`, `omniASR_LLM_1B` | `omniASR_LLM_Unlimited_3B_v2` |
| `facebook/omnilingual-asr-7b`, `omnilingual-asr-7b`, `omniASR_LLM_7B` | `omniASR_LLM_Unlimited_7B_v2` |

Note: `omniASR_LLM_3B` was not in the old UI options list, so it has no migration entry.

## UI Model Options

Replace `omniAsrModelOptions` in `SettingsView.tsx` with:

```typescript
const omniAsrModelOptions = [
  { value: "omniASR_LLM_Unlimited_300M_v2", label: "omniASR LLM Unlimited 300M v2 (Fast)",  description: "Fastest unlimited-length model." },
  { value: "omniASR_LLM_Unlimited_1B_v2",   label: "omniASR LLM Unlimited 1B v2",           description: "Balanced speed and accuracy." },
  { value: "omniASR_LLM_Unlimited_3B_v2",   label: "omniASR LLM Unlimited 3B v2",           description: "High accuracy." },
  { value: "omniASR_LLM_Unlimited_7B_v2",   label: "omniASR LLM Unlimited 7B v2 (Best)",   description: "Highest accuracy, requires more VRAM." },
];
```

## Tests

Add `omni_asr_model_migrates_to_v2` in `settings.rs` that writes a JSON settings file containing each old model name and asserts it loads back as the correct v2 Unlimited name. Covers: both HuggingFace-style names, bare CTC names, and unversioned LLM names.

## Out of Scope

- CTC v2 models (`omniASR_CTC_*_v2`) are not included — the request is specifically for the `LLM_Unlimited` family.
- Zero-shot model (`omniASR_LLM_7B_ZS`) is not included.
- No changes to Python worker, fairseq2 requirements, or Rust transcription engine.
