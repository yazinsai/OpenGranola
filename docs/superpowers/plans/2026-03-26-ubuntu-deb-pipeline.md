# Ubuntu .deb Build Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable OpenCassava to build as a `.deb` package on Ubuntu 22.04 LTS and publish it to GitHub Releases automatically on every version tag.

**Architecture:** Fix one cross-platform incompatibility in `tauri.conf.json` (`npm.cmd` → `npm`), then add a new `ubuntu-release.yml` GitHub Actions workflow mirroring the existing `windows-release.yml` pattern — same triggers, same Rust cache setup, with Linux-specific system dep installation and `pwsh` to run the existing `prepare-whisper.ps1`.

**Tech Stack:** Tauri 2, Rust, Node.js 20, GitHub Actions, PowerShell Core (pwsh), apt

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `opencassava/src-tauri/tauri.conf.json` | Fix `npm.cmd` → `npm` so Tauri's before-build/dev hooks run on Linux |
| Create | `.github/workflows/ubuntu-release.yml` | Full Linux CI pipeline: deps → whisper → build → publish |

---

### Task 1: Fix npm.cmd in tauri.conf.json

**Files:**
- Modify: `opencassava/src-tauri/tauri.conf.json` (lines 9–10)

`npm.cmd` is a Windows batch file wrapper. On Linux it doesn't exist; `npm` works on all platforms including Windows.

- [ ] **Step 1: Apply the fix**

In `opencassava/src-tauri/tauri.conf.json`, change lines 9–10 from:

```json
    "beforeDevCommand": "npm.cmd run dev",
    "beforeBuildCommand": "npm.cmd run build",
```

to:

```json
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build",
```

- [ ] **Step 2: Verify the Windows workflow still references npm correctly**

The Windows workflow (`windows-release.yml`) calls `npm.cmd ci` and `npm.cmd run tauri` directly in its own `run:` steps — those are fine as-is (Windows runner, Windows shell). The `tauri.conf.json` change only affects Tauri's internal invocation of the before-build hook. No change needed to the Windows workflow.

- [ ] **Step 3: Commit**

```bash
git add opencassava/src-tauri/tauri.conf.json
git commit -m "fix: use npm instead of npm.cmd in tauri.conf.json for Linux compatibility"
```

---

### Task 2: Create ubuntu-release.yml

**Files:**
- Create: `.github/workflows/ubuntu-release.yml`

Mirrors `windows-release.yml` structure. Key differences: `ubuntu-22.04` runner, bash shell, apt deps, pwsh for `prepare-whisper.ps1`, `--bundles deb`.

- [ ] **Step 1: Create the workflow file**

Create `.github/workflows/ubuntu-release.yml` with this exact content:

```yaml
name: Build Ubuntu App

on:
  workflow_dispatch:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  build-ubuntu:
    runs-on: ubuntu-22.04
    defaults:
      run:
        working-directory: opencassava

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: opencassava/package-lock.json

      - name: Set up Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Restore Rust cache
        uses: Swatinem/rust-cache@v2
        with:
          workspaces: |
            . -> target
            opencassava/src-tauri -> target

      - name: Install Linux system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            libwebkit2gtk-4.1-dev \
            libgtk-3-dev \
            librsvg2-dev \
            libayatana-appindicator3-dev \
            libssl-dev \
            pkg-config \
            libdbus-1-dev \
            cmake \
            clang \
            libclang-dev
        working-directory: .

      - name: Prepare whisper-rs
        run: pwsh opencassava/scripts/prepare-whisper.ps1
        working-directory: .

      - name: Install frontend dependencies
        run: npm ci

      - name: Build .deb package
        run: npm run tauri -- build --bundles deb

      - name: Upload .deb artifact
        uses: actions/upload-artifact@v4
        with:
          name: opencassava-ubuntu-deb
          path: target/release/bundle/deb/*.deb
          if-no-files-found: error

      - name: Publish GitHub release assets
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: target/release/bundle/deb/*.deb
```

> **Notes on working-directory overrides:**
> - The `apt-get` and `pwsh` steps use `working-directory: .` (repo root) to override the job-level `opencassava/` default — these commands need to run from the root.
> - All other `run:` steps inherit the job default and run from `opencassava/`.
> - `upload-artifact` and `action-gh-release` `path:` values are always relative to the repo root regardless of `working-directory`.

- [ ] **Step 2: Validate YAML syntax locally**

```bash
# From repo root — requires Python (available on most dev machines)
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ubuntu-release.yml'))" && echo "YAML valid"
```

Expected output: `YAML valid`

If Python isn't available, open the file in VS Code — it highlights YAML errors inline.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ubuntu-release.yml
git commit -m "feat: add Ubuntu 22.04 .deb build and release pipeline"
```

---

### Task 3: Smoke-test the pipeline

This task is done in GitHub — no local steps except pushing.

- [ ] **Step 1: Push to trigger workflow_dispatch**

```bash
git push origin main
```

Then go to the repo on GitHub → **Actions** → **Build Ubuntu App** → **Run workflow** (manual trigger on `main`).

- [ ] **Step 2: Watch for failures and expected fix-ups**

Common first-run failures and their fixes:

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `libwebkit2gtk-4.1-dev: Unable to locate package` | Package not available on 22.04 | Change to `libwebkit2gtk-4.0-dev` and check Tauri 2 docs for the correct package name on Jammy |
| `pwsh: command not found` | pwsh not pre-installed | Add a step before the pwsh step: `- name: Install PowerShell` / `run: sudo apt-get install -y powershell` with `working-directory: .` |
| `cmake: command not found` | apt-get step failed silently | Check the apt-get step logs; ensure `sudo apt-get update` ran first |
| `No files were found with the provided path: target/release/bundle/deb/*.deb` | Build succeeded but bundle path is wrong | Check the build logs for the actual output path; adjust the glob in the upload step |
| `error: linker cc not found` | build-essential not installed | Add `build-essential` to the apt install list |

- [ ] **Step 3: If pwsh is missing, add the install step**

If the `pwsh: command not found` error appears, edit `.github/workflows/ubuntu-release.yml` to add this step immediately before "Prepare whisper-rs":

```yaml
      - name: Install PowerShell
        run: |
          sudo apt-get install -y powershell
        working-directory: .
```

Then commit:

```bash
git add .github/workflows/ubuntu-release.yml
git commit -m "fix: install pwsh on ubuntu runner before prepare-whisper step"
```

- [ ] **Step 4: Tag and verify full release flow once build is green**

```bash
# Only after the manual workflow_dispatch run succeeds
git tag v0.1.5-linux-test
git push origin v0.1.5-linux-test
```

Check GitHub → Releases — the `.deb` file should appear as a release asset.

Delete the test tag after confirming:

```bash
git push origin --delete v0.1.5-linux-test
git tag -d v0.1.5-linux-test
```
