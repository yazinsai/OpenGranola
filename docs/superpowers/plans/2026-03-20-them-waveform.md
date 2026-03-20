# Them Waveform Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second waveform visualizer for the "them" (speaker/system audio) channel, stacked below the existing mic waveform in the control bar.

**Architecture:** The backend already emits `{ you, them }` audio levels via the `audio-level` Tauri event; the frontend only uses `you`. We thread `them` through the React state and props chain, add a `color`/`colorLight` prop to `WaveformVisualizer` so it can render in amber instead of teal, add a `themLight` tint to the theme, and render two stacked canvases in `ControlBar`. Tasks 3 and 4 (App.tsx and ControlBar.tsx) are committed together in a single commit because App.tsx passes a prop that ControlBar does not yet accept mid-way — committing them together keeps the tree always compilable.

**Tech Stack:** React 19, TypeScript, Tauri 2, Canvas 2D API, inline CSS-in-JS, custom theme object (`src/theme.ts`)

---

## File Map

| Action | File | Change |
|--------|------|--------|
| Modify | `opencassava/src/theme.ts:37` | Add `themLight: "#dba86e"` next to `them` |
| Modify | `opencassava/src/components/WaveformVisualizer.tsx:4-7,13,67-69,122,132` | Add `color`/`colorLight` props; reduce height to 18; parameterize gradient, fill, and effect deps |
| Modify | `opencassava/src/App.tsx:129,247-249,460` | Add `audioLevelThem` state; set from `e.payload.them`; pass to ControlBar |
| Modify | `opencassava/src/components/ControlBar.tsx:6-17,51-52,283` | Add `audioLevelThem` prop; render stacked waveforms |

---

### Task 1: Add `themLight` to theme

**Files:**
- Modify: `opencassava/src/theme.ts:37`

- [ ] **Step 1: Add `themLight` color**

In `opencassava/src/theme.ts`, add `themLight` on the line immediately after `them` (line 37):

```ts
// Before (line 37):
    them: "#c98b4f",            // Warm amber (was #d2994d)

// After:
    them: "#c98b4f",            // Warm amber (was #d2994d)
    themLight: "#dba86e",       // Lighter amber tint
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd opencassava && npx tsc -b ./tsconfig.app.json --noEmit
```
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add opencassava/src/theme.ts
git commit -m "feat: add themLight color to theme"
```

---

### Task 2: Add color props to WaveformVisualizer and reduce height

**Files:**
- Modify: `opencassava/src/components/WaveformVisualizer.tsx`

- [ ] **Step 1: Update Props interface and function signature**

Replace the Props interface (lines 4-7) and the opening of the component function (lines 9-13). The "Before" block shows the full extent of what changes — note lines after `height = 32` are unchanged:

```tsx
// Before (lines 4-13):
interface Props {
  level: number; // 0-1
  isActive: boolean;
}

export function WaveformVisualizer({ level, isActive }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [dataArray, setDataArray] = useState<Float32Array>(new Float32Array(64));
  const width = 140;
  const height = 32;
  // ... lines continue unchanged

// After:
interface Props {
  level: number; // 0-1
  isActive: boolean;
  color?: string;
  colorLight?: string;
}

export function WaveformVisualizer({
  level,
  isActive,
  color = colors.accent,
  colorLight = colors.accentLight,
}: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [dataArray, setDataArray] = useState<Float32Array>(new Float32Array(64));
  const width = 140;
  const height = 18;
  // ... lines continue unchanged
```

- [ ] **Step 2: Parameterize gradient stops**

Replace the hardcoded gradient color stops in the draw function (around line 67-69):

```tsx
// Before:
      const gradient = ctx.createLinearGradient(0, 0, width, 0);
      gradient.addColorStop(0, colors.accent);
      gradient.addColorStop(0.5, colors.accentLight);
      gradient.addColorStop(1, colors.accent);

// After:
      const gradient = ctx.createLinearGradient(0, 0, width, 0);
      gradient.addColorStop(0, color);
      gradient.addColorStop(0.5, colorLight);
      gradient.addColorStop(1, color);
```

- [ ] **Step 3: Parameterize fill color**

Replace the hardcoded fill (around line 122):

```tsx
// Before:
      ctx.fillStyle = `${colors.accent}20`;

// After:
      ctx.fillStyle = `${color}20`;
```

- [ ] **Step 4: Add `color` and `colorLight` to the draw `useEffect` dependency array**

The `draw` function closes over `color` and `colorLight`. They must be in the dependency array so the canvas re-draws if colors ever change. Find the dependency array of the second `useEffect` (the one containing the `draw` function, around line 132):

```tsx
// Before:
  }, [dataArray, isActive, normalizedLevel, visualLevel]);

// After:
  }, [dataArray, isActive, normalizedLevel, visualLevel, color, colorLight]);
```

- [ ] **Step 5: Verify TypeScript compiles**

```bash
cd opencassava && npx tsc -b ./tsconfig.app.json --noEmit
```
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add opencassava/src/components/WaveformVisualizer.tsx
git commit -m "feat: add color/colorLight props to WaveformVisualizer, reduce height to 18"
```

---

### Task 3: Wire `audioLevelThem` through App and ControlBar

**Note:** App.tsx and ControlBar.tsx are edited and committed together in this task. Committing App.tsx alone would pass a prop that ControlBar doesn't yet accept, causing a TypeScript error. Editing both files before committing keeps the tree always compilable.

**Files:**
- Modify: `opencassava/src/App.tsx:129,247-249,460`
- Modify: `opencassava/src/components/ControlBar.tsx:6-17,51-52,283`

**— App.tsx changes —**

- [ ] **Step 1: Add `audioLevelThem` state in App.tsx**

On the line immediately after `const [audioLevel, setAudioLevel] = useState(0);` (line 129), add:

```tsx
const [audioLevelThem, setAudioLevelThem] = useState(0);
```

- [ ] **Step 2: Set `audioLevelThem` from the event in App.tsx**

In the `audio-level` listener (lines 247-249), update to also set the new state:

```tsx
// Before:
      listen<{ you: number; them: number }>("audio-level", (e) => {
        setAudioLevel(e.payload.you);
      }),

// After:
      listen<{ you: number; them: number }>("audio-level", (e) => {
        setAudioLevel(e.payload.you);
        setAudioLevelThem(e.payload.them);
      }),
```

- [ ] **Step 3: Pass `audioLevelThem` to ControlBar in App.tsx**

Find the `<ControlBar>` usage (around line 460) and add the new prop on the line after `audioLevel`:

```tsx
// Before:
        audioLevel={audioLevel}
      />

// After:
        audioLevel={audioLevel}
        audioLevelThem={audioLevelThem}
      />
```

**— ControlBar.tsx changes —**

- [ ] **Step 4: Add `audioLevelThem` to Props in ControlBar.tsx**

In the `Props` interface (lines 6-17), add after `audioLevel`:

```tsx
// Before:
  audioLevel?: number;
}

// After:
  audioLevel?: number;
  audioLevelThem?: number;
}
```

- [ ] **Step 5: Add default value in destructuring in ControlBar.tsx**

In the function parameter destructuring (around line 51-52), add after `audioLevel = 0`:

```tsx
// Before:
  audioLevel = 0,
}: Props) {

// After:
  audioLevel = 0,
  audioLevelThem = 0,
}: Props) {
```

- [ ] **Step 6: Replace single waveform with stacked pair in ControlBar.tsx**

Find the single `<WaveformVisualizer>` render (line 283):

```tsx
// Before:
          <WaveformVisualizer level={audioLevel} isActive={isRunning} />

// After:
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            <WaveformVisualizer level={audioLevel} isActive={isRunning} />
            <WaveformVisualizer
              level={audioLevelThem}
              isActive={isRunning}
              color={colors.them}
              colorLight={colors.themLight}
            />
          </div>
```

- [ ] **Step 7: Verify TypeScript compiles cleanly**

```bash
cd opencassava && npx tsc -b ./tsconfig.app.json --noEmit
```
Expected: No errors.

- [ ] **Step 8: Commit both files together**

```bash
git add opencassava/src/App.tsx opencassava/src/components/ControlBar.tsx
git commit -m "feat: add stacked them waveform to control bar"
```

---

### Task 4: Visual verification

- [ ] **Step 1: Start the app in dev mode**

```bash
cd opencassava && npm run dev
```

- [ ] **Step 2: Start a recording session and verify**

Click Record. Check:
- Two waveforms appear stacked in the control bar
- Top waveform (you/mic) is teal/accent-colored
- Bottom waveform (them/speaker) is amber-colored
- Both animate independently based on their audio channels
- Silent channels (level < 0.02) show a flat gray (`colors.border`) line — same neutral color for both waveforms
- Timer and LIVE badge remain vertically centered next to the waveform pair
- Total height of the stacked pair (~40px) is visually similar to the original single 32px canvas

- [ ] **Step 3: Final commit if any cosmetic tweaks were needed**

```bash
git add -p
git commit -m "fix: cosmetic tweaks to stacked waveform layout"
```
