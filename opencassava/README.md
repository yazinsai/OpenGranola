# OpenCassava Frontend (React + TypeScript)

This package contains the desktop UI layer for OpenCassava.

- **Runtime:** Tauri + React 18 + TypeScript + Vite
- **Entry point:** `src/main.tsx`
- **Main shell:** `src/App.tsx`
- **Desktop host integration:** `src-tauri/`

## UI Areas

- `src/components/ControlBar.tsx` - session lifecycle controls and quick actions.
- `src/components/SuggestionsView.tsx` - live AI suggestions during calls.
- `src/components/TranscriptView.tsx` - real-time transcript stream.
- `src/components/NotesView.tsx` - structured notes and template output.
- `src/components/SessionSidebar.tsx` - history and session selection.
- `src/components/SettingsView.tsx` - model providers, prompts, and app behavior.

## Design Goals

The frontend emphasizes:

1. **At-a-glance readability** in high-focus conversations.
2. **Low-friction control** (keyboard shortcuts + minimal click depth).
3. **Stable information hierarchy** (suggestions, transcript, and notes each have clear zones).
4. **Dark, contrast-forward styling** to reduce distraction while screen-sharing.

## Development

```bash
cd opencassava
npm install
npm run dev
```

## Build

```bash
npm run build
npm run tauri -- build
```
