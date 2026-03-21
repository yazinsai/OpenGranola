# Repo Policy Bot — Design Spec

## Problem

Maintaining an open-source repo is tedious. Issue triage, PR review, duplicate detection, release management — it's all repetitive work that follows rules. OpenOats built an autonomous maintainer powered by Claude Code that handles this via a policy document. This works, but it's tightly coupled to OpenOats and requires manual Claude Code sessions.

Other repo maintainers want the same thing. They need a way to define their repo's maintenance policy and have an AI agent execute it autonomously on GitHub.

## Solution

An npm package (`repo-policy-bot`) that scaffolds an autonomous repo maintainer onto any GitHub repository. Users run one command, customize a policy file, and get AI-powered triage, code review, implementation, and release management — all running as GitHub Actions on top of `anthropics/claude-code-action@v1`.

## Non-Goals

- Multi-provider support (Codex, Gemini) — v1 is Claude-only, though the policy format is provider-agnostic
- Custom label taxonomies — the label system is opinionated and fixed
- Web dashboard or hosted service
- GitHub App packaging — workflows are simpler
- Replacing CI — this orchestrates around existing CI, doesn't replace it

## Architecture

### Four-Workflow Execution Model

```
┌──────────────────────────────────────────────────────────┐
│                    GitHub Events                          │
│    (issues, PRs, comments, labels, CI, reopens)           │
└────┬──────────┬──────────────┬──────────────┬────────────┘
     │          │              │              │
     ▼          ▼              ▼              ▼
┌─────────┐ ┌──────────┐ ┌───────────┐ ┌─────────────┐
│ Triage  │ │Implement │ │Gate Runner│ │Release Runner│
│ Agent   │ │ Agent    │ │(pure logic)│ │(pure logic) │
│(AI, low │ │(AI, write│ │           │ │             │
│privilege)│ │privilege)│ │ Merge if  │ │ Bump version│
│         │ │          │ │ gates pass│ │ Tag release │
└─────────┘ └──────────┘ └───────────┘ └─────────────┘
```

The AI layer is split into two workflows for security: a low-privilege **Triage Agent** that handles untrusted input (issues, comments, PR reviews) and a higher-privilege **Implementation Agent** that only runs on trusted triggers (labels applied by the Triage Agent or maintainers).

#### 1. Triage Agent (low privilege)

**Trigger:**
- `issues` (opened, reopened, labeled, unlabeled, closed) — new issues, state changes, label repairs
- `pull_request` (opened, synchronize, labeled, unlabeled, reopened, closed) — new/updated PRs and state changes
- `issue_comment` (created) — two modes:
  - Items in `state:needs-info`, `state:needs-repro`, or `state:awaiting-human`: trigger on ALL comments (human replies resume the workflow)
  - All other items: trigger only when comment contains `@claude` (filtered in workflow YAML)

**Guards:**
- Skip if trigger is `labeled`/`unlabeled` and the label was applied by the bot itself (prevent loops)
- Concurrency: `concurrency: { group: triage-${{ github.event.issue.number || github.event.pull_request.number }} }` — one run per item. GitHub allows one running + one pending; handlers are idempotent so dropped intermediate triggers are safe.

**How it works:**
- Calls `anthropics/claude-code-action@v1` in automation mode
- The prompt is assembled as: `system-prompt.md` content + contents of `.github/repo-policy.md` + GitHub event context
- Passed via the `prompt` input of `claude-code-action`
- Tool overrides via `claude_args`: `--allowedTools Read Grep Glob Bash(gh:*) --max-turns 15`
- **No file editing, no git write access** — triage is read-only + GitHub API via `gh`
- Pinned to `anthropics/claude-code-action@v1` (explicit version)

**Permissions:** `issues: write`, `pull-requests: write`, `contents: read`, `actions: read`

**What it does:**
- Triages new issues (classify kind, assess risk, check for duplicates via `gh` and `git log`)
- Reviews PRs (code review, risk assessment, label normalization)
- Normalizes labels: if multiple labels exist in a namespace, keeps the highest-severity one and removes others
- Applies labels as the state machine progresses
- Comments with reasoning and status updates
- Runs adversarial input checks on submissions
- Escalates `risk:high` items by labeling `state:awaiting-human`
- On `synchronize` (new commits pushed to PR): re-reviews only the new changes, does not re-triage from scratch
- On `reopened`: re-evaluates state, removes terminal `resolution:*` label, sets `state:new`
- On `unlabeled`: checks label invariant (one per namespace), repairs if violated
- On `closed` (by human, not by Gate Runner): applies `state:done` and appropriate `resolution:*`
- **Fork PRs:** Review-only. The Triage Agent reviews and labels fork PRs but never attempts to push code to fork branches. If the fork PR is accepted, the system prompt instructs the agent to note this and optionally re-implement on a base-repo branch.
- Resumes work when human replies to `needs-info`/`needs-repro`/`awaiting-human` items (comment trigger fires on all comments for these states)

#### 2. Implementation Agent (write privilege)

**Trigger:**
- `issues` (labeled) — only when `state:planned` or `state:in-progress` is applied
- `pull_request` (labeled) — only when `state:in-progress` is applied

**Guards:**
- Skip unless the label that triggered the event is `state:planned` or `state:in-progress`
- Skip if the label was applied by the Implementation Agent itself (prevent loops)
- Skip if item has `risk:high` (requires human implementation)
- Concurrency: `concurrency: { group: implement-${{ github.event.issue.number || github.event.pull_request.number }} }` — one run per item, idempotent handlers

**How it works:**
- Calls `anthropics/claude-code-action@v1` in automation mode
- Tool overrides via `claude_args`: `--allowedTools Edit Read Write Grep Glob Bash(gh:*) Bash(git:*) --max-turns 40`
- **Full write access** — can edit files, create branches, push commits
- After claude-code-action completes, a post-step creates the PR via `gh pr create` if the action pushed commits but didn't open a PR (claude-code-action prepares branches but may not auto-open PRs)

**Permissions:** `contents: write`, `issues: write`, `pull-requests: write`, `actions: read`

**What it does:**
- Implements `risk:low` and `risk:medium` fixes
- Creates a branch named `bot/{issue-number}-{slug}`
- Edits files, pushes commits
- Post-step: opens PR via `gh pr create --body "Fixes #{issue}" ...`
- Links the PR to the issue via `Fixes #N` in the PR body
- Applies initial labels to the PR (`kind:*` from issue, `risk:*` from issue, `state:in-progress`, `resolution:none`, `release:*` based on scope)

**Issue/PR linkage:**
- The **issue** is the parent; the **PR** is the child
- When the Implementation Agent creates a PR for issue `#123`, it includes `Fixes #123` in the PR body
- The issue keeps its labels. The PR gets its own independent label set.
- When the PR merges, GitHub auto-closes the issue via `Fixes #123`
- If no `Fixes` keyword was used, the Gate Runner closes linked issues via `gh issue close`
- The Gate Runner applies `state:done` and `resolution:merged` to both the PR and any linked issues

#### 3. Gate Runner

**Trigger:**
- `pull_request` (labeled) — when `state:ready-to-merge` is applied
- `check_suite` (completed) — re-evaluate when CI finishes (a PR may have been labeled `ready-to-merge` before CI completed)
- `pull_request_review` (submitted) — re-evaluate when a human review is submitted

**How it works:** Pure shell/JS logic, no AI. No AI API calls — cost is zero. Triggers when conditions might have changed.

**Merge conditions (all must be true):**
- PR has `state:ready-to-merge` label
- PR does NOT have `risk:high` label
- No merge conflicts
- All required status checks pass (checked via GitHub API, not by name — works with any CI)
- No unresolved human reviews requesting changes (agent reviews are tracked via labels, not GitHub review API since claude-code-action cannot submit formal reviews)
- PR body is non-empty (contains user-facing summary)
- `resolution` label is `resolution:none` (the literal label, meaning active/unresolved). If resolution is anything else, the item is already terminal — skip silently.

**Merge strategy:** Read from `.github/repo-policy.yml` (machine-readable config, see below). Defaults to squash merge. Supports `merge` and `rebase`.

**Action:** Merge the PR via GitHub API using configured strategy. Apply `resolution:merged` and `state:done` labels to PR. Close linked issues and apply `state:done` + `resolution:merged` to them. Record the PR number and labels as a JSON annotation on the merge commit (for Release Runner consumption).

**Failure:** If any gate fails, post a comment explaining which gate blocked, remove `state:ready-to-merge`, apply `state:in-progress`.

**Concurrency:** `concurrency: { group: gate-${{ github.event.pull_request.number }} }` — idempotent, safe to re-run.

#### 4. Release Runner

**Trigger:**
- `workflow_run` (completed) — triggers when the repo's CI workflow completes on the default branch (not on `push`, since CI may not be green yet at push time)

**How it works:** Pure shell/JS logic, no AI. No AI API calls — cost is zero.

**Finding merged PRs:** Uses GitHub's "List pull requests associated with a commit" API (`GET /repos/{owner}/{repo}/commits/{sha}/pulls`) for each commit between the latest semver tag and HEAD. This handles squash merges, cherry-picks, and regular merges correctly. Falls back to Gate Runner annotations if the API returns no results.

**Release conditions:**
- At least one merged PR has `release:patch` or `release:minor` label
- No merged PR in the batch has `release:major` (requires human approval)
- No merged PR in the batch has `risk:high`
- CI workflow that triggered this run completed successfully

**Version bump rule:**
- Any `release:minor` in batch → bump minor
- Otherwise any `release:patch` → bump patch
- `release:none` PRs don't trigger releases
- `release:major` blocks automatic release, comments asking for human approval

**Version source:** Git tags. The Release Runner finds the latest semver tag (e.g., `v1.2.3`), applies the bump rule, and creates the new tag + GitHub Release with auto-generated notes. If no semver tag exists, starts at `v0.1.0`. The release tag triggers whatever release pipeline the repo already has (e.g., a `release-dmg.yml` workflow).

**Error handling:** If tag creation fails (already exists), skip and log. If CI status is not available or not green, skip release and comment on the most recent merged PR explaining why.

### Label Taxonomy (Built-In, Fixed)

Users do not configure these. They ship with the tool.

| Namespace | Labels | Purpose |
|-----------|--------|---------|
| `kind:` | `bug`, `feature`, `ux`, `docs`, `housekeeping` | Classify work type |
| `state:` | `new`, `needs-info`, `needs-repro`, `planned`, `in-progress`, `awaiting-human`, `ready-to-merge`, `done` | Track workflow stage |
| `risk:` | `low`, `medium`, `high` | Determine autonomy level |
| `resolution:` | `none`, `merged`, `duplicate`, `already-fixed`, `declined`, `out-of-scope` | Terminal state |
| `release:` | `none`, `patch`, `minor`, `major` | Version impact |

Every open issue/PR gets exactly one label from each namespace.

### State Machine Transitions

Issues and PRs share the same label taxonomy but have slightly different valid transitions.

#### Issue Transitions

```
new → needs-info          (missing details)
new → needs-repro         (bug without reproduction steps)
new → planned             (accepted, queued for work)
new → awaiting-human      (risk:high or ambiguous, needs human)
new → done                (duplicate, already-fixed, declined, out-of-scope)

needs-info → planned      (info provided)
needs-info → done         (no response, or info reveals duplicate/invalid)
needs-info → awaiting-human

needs-repro → planned     (repro provided)
needs-repro → done        (no response, or can't reproduce)
needs-repro → awaiting-human

planned → in-progress     (Implementation Agent picks up work)
planned → awaiting-human  (new info changes risk assessment)
planned → done            (superseded or no longer needed)

in-progress → awaiting-human  (hit a decision point)
in-progress → planned         (blocked, returning to queue)
in-progress → done            (resolved without PR, e.g. config change)

awaiting-human → planned      (human approves/decides)
awaiting-human → in-progress  (human approves and work resumes)
awaiting-human → done         (human declines)
```

#### PR Transitions

```
new → in-progress         (PR accepted, review in progress)
new → awaiting-human      (risk:high or needs human review)
new → done                (duplicate, already-fixed, declined, out-of-scope)

in-progress → ready-to-merge  (passes review)
in-progress → awaiting-human  (hit a decision point)
in-progress → done            (closed without merge)

awaiting-human → in-progress  (human approves and review resumes)
awaiting-human → done         (human declines)

ready-to-merge → done         (merged by Gate Runner)
ready-to-merge → in-progress  (gate failed, needs more work)
```

Note: PRs skip `planned` (they're already concrete work) and can go directly from `new → in-progress`.

The Triage/Implementation Agents enforce these transitions. If an invalid state is encountered (e.g., a human manually set a bad label), the agent normalizes using the following repair rules:
- If no `state:` label exists → set `state:new`
- If no `kind:` label exists → infer from content or set `kind:bug` as default
- If no `risk:` label exists → set `risk:medium` as default
- If no `resolution:` label exists → set `resolution:none`
- If no `release:` label exists → set `release:none`

### Config Files

Two config files serve different audiences:

#### `.github/repo-policy.md` — For the AI agent

Free-form markdown. The AI reads this to make judgment calls. Contains:

```markdown
# Product Guardrails
<!-- What this project values. The agent uses these to make judgment calls. -->
- Example: Privacy by default
- Example: Simplicity over features

# Risk Classification
<!-- Override or extend the default risk rules. -->
## Always High Risk
- Changes to authentication or authorization
- Modifications to the release pipeline
- Database migration changes

## Always Low Risk
- Documentation-only changes
- Test-only changes

# Decision Rules
## Bugs
- Fix if reproducible or obvious from code inspection
- Close as duplicate if an existing issue covers it

## Features
- Accept if it benefits most users
- Decline if it adds disproportionate complexity
- Escalate to human if ambiguous

## External PRs
- The idea matters, the exact code doesn't
- OK to reimplement rather than iterate on the PR

# Repo-Specific Rules
<!-- Anything unique to this project. -->
- Example: Treat changes to the billing module as risk:high
```

Sections are optional. Omitted sections use sensible defaults.

#### `.github/repo-policy.yml` — For the Gate Runner and Release Runner

Machine-readable YAML. Consumed by deterministic workflows, not AI:

```yaml
# Merge strategy: squash (default), merge, or rebase
merge_strategy: squash

# CI workflow name to watch for release gating (must match a workflow filename)
ci_workflow: ci.yml

# Branch to release from (default: repo's default branch)
# release_branch: main
```

This file is small and stable. The `init` CLI creates it with defaults.

## npm Package: `repo-policy-bot`

### CLI Commands

```bash
# Full setup — scaffolds everything
npx repo-policy-bot init

# Recreate/sync labels on the repo
npx repo-policy-bot labels
```

### `init` Flow

1. Detect repo root (find `.git/`)
2. Check for `gh` CLI availability
3. Create `.github/workflows/triage-agent.yml` — **skip if exists**, print warning
4. Create `.github/workflows/implement-agent.yml` — **skip if exists**, print warning
5. Create `.github/workflows/gate-runner.yml` — **skip if exists**, print warning
6. Create `.github/workflows/release-runner.yml` — **skip if exists**, print warning
7. Create `.github/repo-policy.md` (starter template) — **skip if exists**, print warning
8. Create `.github/repo-policy.yml` (machine config) — **skip if exists**, print warning
9. Create labels via `gh label create` (skip existing, update descriptions on existing)
10. Check for `ANTHROPIC_API_KEY` repo secret — prompt user to add if missing
11. Print summary of what was created vs. skipped

### `labels` Flow

1. Read expected label taxonomy from `labels.ts`
2. List existing repo labels via `gh label list`
3. Create missing labels with correct name, color, and description
4. Update description/color on existing labels if they differ
5. Never delete labels — only additive

### Package Structure

```
repo-policy-bot/
├── package.json
├── bin/cli.js                    # CLI entry point
├── src/
│   ├── commands/
│   │   ├── init.ts               # Scaffold workflows + policy + labels
│   │   └── labels.ts             # Sync labels
│   ├── templates/
│   │   ├── triage-agent.yml      # Workflow template (low privilege)
│   │   ├── implement-agent.yml   # Workflow template (write privilege)
│   │   ├── gate-runner.yml       # Workflow template
│   │   ├── release-runner.yml    # Workflow template
│   │   ├── repo-policy.md        # Starter policy (for AI)
│   │   ├── repo-policy.yml       # Starter config (for runners)
│   │   └── system-prompt.md      # Built-in agent instructions
│   └── labels.ts                 # Label taxonomy definition
└── README.md
```

## System Prompt (Built-In)

The system prompt is the core IP. It's what turns `claude-code-action` into a repo maintainer. It encodes:

- The label state machine and transitions (separate issue/PR rules)
- Default risk classification rules
- Gate definitions (for the agent to know when to label `ready-to-merge`)
- Adversarial input defense (deception checks)
- How to read and apply the user's policy file
- Decision-making framework for bugs, features, PRs
- When to act autonomously vs. escalate to human
- Fork PR handling (review-only, never push to fork branches)
- Issue/PR linkage rules (`Fixes #N` convention)

Two variants ship in the package:
- `system-prompt-triage.md` — read-only instructions, no implementation guidance
- `system-prompt-implement.md` — full implementation instructions, branching conventions, PR creation

Both are **generic** — they reference only the label taxonomy, state machine, and decision framework. They contain no repo-specific CI check names, languages, or tools. All repo-specific behavior comes from the user's policy file.

## Cost and Rate Limiting

- **Concurrency:** Each workflow uses `concurrency` groups keyed by issue/PR number. GitHub allows one running + one pending run per group. Handlers are idempotent — if an intermediate trigger is dropped, the next run picks up the correct state from labels.
- **Trigger filtering:** The Triage Agent skips bot-applied labels. The Implementation Agent only fires on specific state labels. Comment triggers are filtered by state (broad for follow-up states, `@claude`-only otherwise).
- **Model selection:** Workflow templates default to `claude-sonnet-4-6` via `claude_args: --model claude-sonnet-4-6`. Users can override in the workflow file.
- **Max turns:** Triage Agent: `--max-turns 15`. Implementation Agent: `--max-turns 40`. Set via `claude_args`.
- **Documentation:** README includes expected per-invocation cost estimates and guidance for high-traffic repos (e.g., limit triggers to `labeled` events only, disable Implementation Agent for cost control).

## Security Considerations

- **Privilege separation:** Triage Agent has read-only repo access + label/comment write. Implementation Agent has full write access but only triggers on trusted label events (applied by Triage Agent or maintainers), never on raw untrusted input.
- **API key management:** Stored as GitHub repo secret, never in code
- **Permission scoping:** Each workflow requests minimum needed permissions. Triage gets `contents: read`, Implementation gets `contents: write`.
- **Adversarial input defense:** System prompt includes deception detection instructions. Triage Agent processes untrusted content but cannot write to the repo. Implementation Agent only sees label triggers, not raw issue/PR content (it reads the content itself, but the trigger is trusted).
- **Merge restrictions:** Agent cannot merge directly — Gate Runner is a separate, auditable workflow
- **Risk escalation:** `risk:high` always requires human approval, enforced at both the Implementation Agent level (skips `risk:high`) and Gate Runner level (blocks merge)
- **Fork PRs:** Review-only, no write access to fork branches
- **No Bash on untrusted events:** Triage Agent's `Bash` access is limited to `gh` (GitHub CLI for label/comment operations). No `git` write access. Implementation Agent has broader `Bash` but only fires on trusted triggers.
- **No secrets in policy:** Policy file is committed to repo, should contain no secrets
- **Declared permissions:** Workflows explicitly declare `actions: read` for CI inspection

## User Journey

1. User discovers `repo-policy-bot` (README, blog post, word of mouth)
2. Runs `npx repo-policy-bot init` in their repo
3. Adds `ANTHROPIC_API_KEY` as repo secret
4. Edits `.github/repo-policy.md` to describe their project's values and risk boundaries
5. Optionally edits `.github/repo-policy.yml` for merge strategy and CI config
6. Commits and pushes the workflow files
7. Next issue or PR triggers the Triage Agent
8. Triage Agent labels, reviews, and escalates as appropriate
9. For `risk:low`/`risk:medium` issues labeled `state:planned`, Implementation Agent picks up work
10. Implementation Agent creates branch, implements fix, opens PR
11. Triage Agent reviews the PR, labels `state:ready-to-merge` if it passes
12. Gate Runner auto-merges when all gates pass
13. Release Runner cuts releases when CI completes on the default branch
14. User intervenes only for `risk:high` or `release:major` items
