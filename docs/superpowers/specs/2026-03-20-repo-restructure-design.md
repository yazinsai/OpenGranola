---
name: Repo Restructure — Break from Fork
description: Flatten OpenCassava/ subdirectory to repo root, clean up fork artifacts, dead worktrees, and empty directories
type: project
---

# Repo Restructure: Break from Fork

**Date:** 2026-03-20

## Context

OpenCassava was forked from `yazinsai/OpenOats`. Now that we're going our own direction, we no longer need fork compatibility. This cleanup flattens the repo structure, removes fork artifacts, and removes dead git state.

## Target Structure

```
repo-root/
├── opencassava/          (was: OpenCassava/OpenCassavaTauri/)
│   ├── src/              React/TypeScript UI
│   ├── src-tauri/        Tauri + Rust bridge
│   ├── package.json
│   └── ...
├── crates/
│   └── opencassava-core/
├── Cargo.toml            (was: OpenCassava/Cargo.toml)
├── Cargo.lock            (was: OpenCassava/Cargo.lock)
├── package.json          (was: OpenCassava/package.json)
├── README.md
├── LICENSE
├── assets/
└── docs/
```

## Changes

### Git moves (history-preserving)
- `OpenCassava/OpenCassavaTauri/` → `opencassava/`
- `OpenCassava/crates/` → `crates/`
- `OpenCassava/Cargo.toml` → `Cargo.toml`
- `OpenCassava/Cargo.lock` → `Cargo.lock`
- `OpenCassava/package.json` → `package.json`
- `OpenCassava/package-lock.json` → `package-lock.json`

### Deletions
- `OpenCassava/` — wrapper directory, now empty after moves
- `output/` — empty directory
- `scripts/` — empty directory
- `OpenCassava/OpenCassavaTauri/src-tauri/err.txt` — build artifact
- `.claude/worktrees/` — dead worktree (full repo snapshot, not needed in git)

### Git remotes
- Remove `upstream` remote (`yazinsai/OpenOats.git`)
- Update `origin` to `romeroej2/OpenCassava.git` (after GitHub repo rename)

### Path reference updates
- `Cargo.toml` workspace members: `crates/opencassava-core` and `opencassava/src-tauri`
- `.github/workflows/windows-release.yml`: update any `OpenCassavaTauri/` path references
- `.gitignore`: update `OpenCassava/`-prefixed entries to new paths; add `.claude/worktrees/`
- `README.md`: update architecture diagram and build instructions to reflect new paths

## Approach

Use `git mv` for all file moves to preserve history. Fix path references. Commit as a single "repo restructure" commit. No force-push required.

## Out of Scope

- No code changes
- No dependency updates
- No feature work
