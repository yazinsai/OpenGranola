# Repo Policy Bot — Design Spec

## Problem

Maintaining an open-source repo is tedious. Issue triage, PR review, duplicate detection, release management — it's all repetitive work that follows rules. OpenOats built an autonomous maintainer powered by Claude Code that handles this via a policy document. This works, but it's tightly coupled to OpenOats and requires manual Claude Code sessions.

Other repo maintainers want the same thing. They need a way to define their repo's maintenance policy and have an AI agent execute it autonomously on GitHub.

## Solution

An npm package (`repo-policy-bot`) that scaffolds an autonomous repo maintainer onto any GitHub repository. Users run one command, customize a policy file, and get AI-powered triage, code review, implementation, and release management — all running as GitHub Actions on top of `anthropics/claude-code-action`.

## Non-Goals

- Multi-provider support (Codex, Gemini) — v1 is Claude-only, though the policy format is provider-agnostic
- Custom label taxonomies — the label system is opinionated and fixed
- Web dashboard or hosted service
- Replacing CI — this orchestrates around existing CI, doesn't replace it

## Prerequisites

**GitHub App required.** The workflow chaining model (Triage labels → Implementation triggers, Triage labels → Gate Runner triggers) requires that label/PR events created by one workflow can trigger another. GitHub suppresses workflow triggers for events created by `GITHUB_TOKEN`. To solve this, the `init` CLI guides users through creating a dedicated GitHub App (or using a PAT) and storing its credentials as repo secrets. All workflows authenticate with this App token instead of `GITHUB_TOKEN` when performing actions that must trigger downstream workflows (labeling, PR creation).

This is a one-time setup cost. The `init` CLI automates as much as possible (generates the App manifest, provides installation instructions).

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

### Workflow Chaining and Loop Prevention

**Chaining mechanism:** All workflows that need to trigger downstream workflows use a single GitHub App token (generated at the start of each workflow run via `actions/create-github-app-token`). Events created with this token (unlike `GITHUB_TOKEN`) do trigger other workflows. The `init` CLI guides users through creating one GitHub App and installing it on the repo.

**Loop prevention:** Since all workflows share the same App identity (`repo-policy-bot[bot]`), sender-based loop prevention is not sufficient. Instead, each workflow uses a **label-event fingerprint** approach:
- Before applying a label, the workflow writes a workflow run ID to a hidden comment on the issue/PR: `<!-- rpb-last-action: {workflow-name}:{run-id} -->`
- When a `labeled` event fires, the triggered workflow reads this marker. If the marker shows the same workflow name as the current workflow, it skips (self-triggered). If it shows a different workflow name, it proceeds (cross-workflow trigger, expected).
- This is deterministic, does not depend on actor identity, and works with a single shared App.

#### 1. Triage Agent (low privilege)

**Trigger:**
- `issues` (opened, reopened, labeled, unlabeled, closed) — new issues, state changes, label repairs
- `pull_request_target` (opened, synchronize, labeled, unlabeled, reopened, closed) — new/updated PRs and state changes. Uses `pull_request_target` instead of `pull_request` so that fork PRs get write tokens for labeling/commenting. The workflow does NOT check out PR code — the Triage Agent reads code via GitHub API (`gh api` / `gh pr diff`), never via local checkout. This prevents untrusted code execution entirely.
- `issue_comment` (created) — two modes:
  - Items in `state:needs-info`, `state:needs-repro`, or `state:awaiting-human`: trigger on comments from the issue author OR repo collaborators (filtered via `if: github.event.comment.author_association in ['OWNER', 'MEMBER', 'COLLABORATOR'] || github.event.comment.user.login == <issue-author>`). This allows the original reporter to respond to info requests while still preventing abuse from random users.
  - All other items: trigger only when comment contains `@claude` AND commenter is a collaborator
- `pull_request_review` (submitted, dismissed) — re-evaluate when human reviews are submitted or dismissed
- `pull_request_review_comment` (created) — capture inline diff comments from reviewers

**Guards:**
- Skip if trigger is `labeled`/`unlabeled` and the `<!-- rpb-last-action: ... -->` marker on the issue/PR shows `triage` as the workflow name (self-triggered).
- Concurrency: `concurrency: { group: triage-${{ github.event.issue.number || github.event.pull_request.number }} }` — one run per item. GitHub allows one running + one pending; handlers are idempotent so dropped intermediate triggers are safe.

**How it works:**
- Calls `anthropics/claude-code-action@<pinned-sha>` in automation mode. The workflow template pins to a specific commit SHA of the action (not `@v1`) for supply-chain security. The `init` CLI resolves the latest SHA at scaffold time.
- The prompt is assembled as: `system-prompt-triage.md` content + contents of `.github/repo-policy.md` + GitHub event context
- Passed via the `prompt` input of `claude-code-action`
- Tool overrides via `claude_args`: `--allowedTools Grep Glob --max-turns 15`
- **Minimal tool access.** The Triage Agent uses `Grep` and `Glob` for searching the checked-out codebase (the workflow checks out the default branch, NOT the PR branch — this is safe because `pull_request_target` runs on the base repo). All GitHub interactions (labeling, commenting, searching issues, reading PR diffs) are performed by the `claude-code-action` built-in GitHub MCP tools, not via Bash. This eliminates the `gh` extension/alias attack vector entirely.
- **Code reading model:** The workflow checks out the repo's default branch (base code). For PR review, the agent reads the PR diff via the built-in GitHub MCP tools (`gh pr diff` equivalent). It never checks out the PR head branch. For issue triage, it reads the base codebase via `Grep`/`Glob` on the checked-out default branch.
- For `synchronize` events (new commits pushed to PR): the agent stores the last-reviewed commit SHA in a hidden HTML comment in its PR comment (e.g., `<!-- last-reviewed: abc123 -->`). On subsequent runs, it reads this marker and reviews only commits since that SHA, preventing missed or duplicate reviews when GitHub drops intermediate concurrency events.

**Permissions:** `issues: write`, `pull-requests: write`, `contents: read`, `actions: read`

**What it does:**
- Triages new issues (classify kind, assess risk, check for duplicates via GitHub search API)
- Reviews PRs (code review via `gh pr diff`, risk assessment, label normalization)
- Normalizes labels: if multiple labels exist in a namespace, keeps the highest-severity one and removes others
- Applies labels as the state machine progresses (using App token so downstream workflows trigger)
- Comments with reasoning and status updates
- Runs adversarial input checks on submissions
- Escalates `risk:high` items by labeling `state:awaiting-human`
- On `synchronize` (new commits pushed to PR): incremental review from last-reviewed SHA
- On `reopened`: re-evaluates state, removes terminal `resolution:*` label, sets `state:new`
- On `unlabeled`: checks label invariant (one per namespace), repairs if violated
- On `closed` (by human, not by Gate Runner): applies `state:done` and appropriate `resolution:*`
- On `pull_request_review` (dismissed): re-evaluates whether `state:ready-to-merge` should be re-applied if the dismissed review was the only blocker
- **Fork PRs:** Review-only. The Triage Agent reviews and labels fork PRs but never attempts to push code to fork branches. Reads PR diff via API, not local checkout. If the fork PR is accepted, the system prompt instructs the agent to note this and optionally re-implement on a base-repo branch.
- Resumes work when the original reporter or collaborators reply to `needs-info`/`needs-repro`/`awaiting-human` items

#### 2. Implementation Agent (write privilege)

**Trigger:**
- `issues` (labeled) — only when `state:planned` is applied

The Implementation Agent triggers **only on issues**, never on PRs. This prevents the agent from running write-capable code in response to external PR content.

**Handling PR revisions:** When a bot-authored PR receives review feedback or fails CI, the Triage Agent sets `state:in-progress` on the PR and adds a comment summarizing what needs to change. It then removes `state:in-progress` from the **parent issue** and applies `state:planned`, which re-triggers the Implementation Agent. (The issue must first be moved away from `state:planned` — e.g., to `state:in-progress` when the Implementation Agent starts work — so that re-applying `state:planned` emits a new `labeled` event.) The Implementation Agent checks for an existing open PR on the `bot/{issue-number}-*` branch, and if found, pushes additional commits to that branch rather than creating a new PR.

**Issue state during implementation:** When the Implementation Agent starts work, it moves the issue from `state:planned` to `state:in-progress` as its first action. This ensures the issue can later be re-labeled `state:planned` to trigger a revision cycle.

**Guards:**
- Skip unless the label that triggered the event is `state:planned`
- Skip if the `<!-- rpb-last-action: ... -->` marker shows `implement` as the workflow name (self-triggered)
- Skip if item has `risk:high` (requires human implementation)
- Concurrency: `concurrency: { group: implement-${{ github.event.issue.number }} }` — one run per item, idempotent handlers

**How it works:**
- Calls `anthropics/claude-code-action@<pinned-sha>` in automation mode
- Tool overrides via `claude_args`: `--allowedTools Edit Read Write Grep Glob Bash(git:*) --max-turns 40`
- **Full write access** — can edit files, create branches, push commits
- GitHub interactions (creating PRs, applying labels) are done via a post-step using the App token and `gh` CLI, not by the agent itself. This keeps the agent's Bash access limited to `git` only.
- After claude-code-action completes, a post-step creates the PR via `gh pr create` (using App token) if the action pushed commits but didn't open a PR

**Permissions:** `contents: write`, `issues: write`, `pull-requests: write`, `actions: read`

**Prompt injection mitigation:** The Implementation Agent reads issue content, which is untrusted. This is an inherent risk of any AI code agent. Mitigations:
- The system prompt includes explicit adversarial input defense instructions
- The agent's Bash access is limited to `git` commands only — no `gh`, no arbitrary shell
- The agent runs in a sandboxed GitHub Actions runner (no access to secrets beyond `ANTHROPIC_API_KEY` and the App token)
- `risk:high` items are excluded (the most security-sensitive work requires human implementation)
- All generated code goes through a PR → Triage Agent review → Gate Runner pipeline before merging
- The Triage Agent re-reviews the implementation as a second AI pass on the generated code

**What it does:**
- Implements `risk:low` and `risk:medium` fixes
- Creates a branch named `bot/{issue-number}-{slug}` (or pushes to existing branch if revising)
- Edits files, pushes commits
- Post-step (using App token): opens PR via `gh pr create --body "Fixes #{issue}" ...` or updates existing PR
- Links the PR to the issue via `Fixes #N` in the PR body
- Post-step applies initial labels to the PR (`kind:*` from issue, `risk:*` from issue, `state:in-progress`, `resolution:none`, `release:*` based on scope)

**Issue/PR linkage:**
- The **issue** is the parent; the **PR** is the child
- When the Implementation Agent creates a PR for issue `#123`, it includes `Fixes #123` in the PR body
- The issue keeps its labels. The PR gets its own independent label set.
- When the PR merges, GitHub auto-closes the issue via `Fixes #123`
- If no `Fixes` keyword was used, the Gate Runner closes linked issues via `gh issue close`
- The Gate Runner applies `state:done` and `resolution:merged` to both the PR and any linked issues

#### 3. Gate Runner

**Trigger:**
- `pull_request_target` (labeled) — when `state:ready-to-merge` is applied. Uses `pull_request_target` for consistent permissions on fork PRs.
- `check_run` (completed) — re-evaluate when a GitHub Actions check run finishes. This is the modern event for Actions-based CI (not the legacy `status` event).
- `status` — re-evaluate when a legacy commit status is posted (for repos using external CI that posts statuses rather than check runs).
- `pull_request_review` (submitted, dismissed) — re-evaluate when a human review is submitted or dismissed

**How it works:** Pure shell/JS logic, no AI. No AI API calls — cost is zero. Triggers when conditions might have changed.

**PR discovery on `check_run`/`status` events:** These events do not carry a top-level PR number. Instead, the Gate Runner queries all open PRs with the `state:ready-to-merge` label (`gh pr list --label "state:ready-to-merge" --state open`) and evaluates merge conditions for each. This is cheap (usually 0-2 PRs) and handles the case where CI finishes after labeling.

**Merge conditions (all must be true):**
- PR has `state:ready-to-merge` label
- PR does NOT have `risk:high` label
- PR is mergeable (checked via `GET /repos/{owner}/{repo}/pulls/{number}` — the `mergeable` field accounts for conflicts, and the `mergeable_state` field reflects branch protection rules including required approvals, CODEOWNERS, conversation resolution, required deployments, and the required-check allowlist). This delegates merge policy to GitHub's own branch protection evaluation rather than re-implementing it.
- No unresolved human reviews requesting changes (checked via `GET /repos/{owner}/{repo}/pulls/{number}/reviews` — only considers reviews with `state: CHANGES_REQUESTED` that have not been dismissed)
- PR body contains a meaningful summary (not just `Fixes #N` — the Implementation Agent's system prompt instructs it to generate a description of what changed and why, alongside the `Fixes #N` link)
- `resolution` label is `resolution:none` (the literal label, meaning active/unresolved). If resolution is anything else, the item is already terminal — skip silently.

**Handling "CI not ready yet":** If the PR's `mergeable_state` is `blocked` or `behind` (pending checks or out-of-date branch), the Gate Runner does NOT remove `state:ready-to-merge` or set `state:in-progress`. It simply exits without merging. The next `check_run` or `status` event will re-trigger evaluation. This prevents the deadlock where removing the label means CI completion can never trigger a re-check.

**Merge strategy:** Read from `.github/repo-policy.yml` (machine-readable config, see below). Defaults to squash merge. Supports `merge` and `rebase`.

**Action:** Merge the PR via GitHub API (using App token) using configured strategy. Apply `resolution:merged` and `state:done` labels to PR. Close linked issues and apply `state:done` + `resolution:merged` to them.

**Failure:** If a gate fails for a non-transient reason (conflicts, failing checks, blocking review), post a comment explaining which gate blocked, remove `state:ready-to-merge`, apply `state:in-progress`.

**Concurrency:** `concurrency: { group: gate-${{ github.event.pull_request.number || 'status-check' }} }` — idempotent, safe to re-run. Status events use a shared group since they evaluate all ready PRs.

#### 4. Release Runner

**Trigger:**
- `workflow_run` (completed) — triggers when the CI workflow (identified by its workflow `name:` field, configured in `.github/repo-policy.yml`) completes on the default branch

**How it works:** Pure shell/JS logic, no AI. No AI API calls — cost is zero.

**Commit range:** The Release Runner scans from the latest semver tag to the **`workflow_run` event's `head_sha`** (the commit that the CI run actually validated), NOT `HEAD`. This prevents releasing commits that landed after the CI run started but were not part of the validated build.

**Finding merged PRs:** Uses GitHub's "List pull requests associated with a commit" API (`GET /repos/{owner}/{repo}/commits/{sha}/pulls`) for each commit in the range. This handles squash merges, cherry-picks, and regular merges correctly.

**Release conditions:**
- At least one merged PR has `release:patch` or `release:minor` label
- No merged PR in the batch has `release:major` (requires human approval)
- No merged PR in the batch has `risk:high`
- The `workflow_run` that triggered this run completed with `conclusion: success`

**Version bump rule:**
- Any `release:minor` in batch → bump minor
- Otherwise any `release:patch` → bump patch
- `release:none` PRs don't trigger releases
- `release:major` blocks automatic release, comments asking for human approval

**Version source:** Git tags. The Release Runner finds the latest semver tag (e.g., `v1.2.3`), applies the bump rule, and creates the new tag + GitHub Release with auto-generated notes. If no semver tag exists, starts at `v0.1.0`. The release tag triggers whatever release pipeline the repo already has (e.g., a `release-dmg.yml` workflow).

**Serialization:** `concurrency: { group: release-runner }` — only one release evaluation at a time. Before creating a tag, the runner verifies that `head_sha` is an ancestor of the current default branch tip (via `git merge-base --is-ancestor`). If a newer commit has landed, the runner skips this run — a subsequent `workflow_run` for the newer commit will handle the release.

**Error handling:** If tag creation fails (already exists), skip and log. If the `workflow_run` conclusion is not `success`, skip release entirely.

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
in-progress → planned         (blocked, returning to queue; also used to re-trigger implementation after PR revision)
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
ready-to-merge → in-progress  (gate failed for non-transient reason)
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

# CI workflow name to watch for release gating
# This must match the `name:` field in your CI workflow YAML, not the filename.
# The init CLI auto-detects this from your repo's existing workflows.
ci_workflow_name: "CI"

# Branch to release from (default: repo's default branch)
# release_branch: main
```

This file is small and stable. The `init` CLI creates it with defaults, auto-detecting the CI workflow name from existing workflow files.

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
3. Guide user through GitHub App creation (or PAT setup) for workflow chaining
4. Resolve latest commit SHA of `anthropics/claude-code-action` for pinning
5. Auto-detect CI workflow name from existing `.github/workflows/*.yml` files
6. Create `.github/workflows/triage-agent.yml` — **skip if exists**, print warning
7. Create `.github/workflows/implement-agent.yml` — **skip if exists**, print warning
8. Create `.github/workflows/gate-runner.yml` — **skip if exists**, print warning
9. Create `.github/workflows/release-runner.yml` — **skip if exists**, print warning
10. Create `.github/repo-policy.md` (starter template) — **skip if exists**, print warning
11. Create `.github/repo-policy.yml` (machine config with detected CI name) — **skip if exists**, print warning
12. Create labels via `gh label create` (skip existing, update descriptions on existing)
13. Check for `ANTHROPIC_API_KEY` repo secret — prompt user to add if missing
14. Check for App credentials repo secrets — prompt user to add if missing
15. Print summary of what was created vs. skipped

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
│   │   ├── init.ts               # Scaffold workflows + policy + labels + App setup
│   │   └── labels.ts             # Sync labels
│   ├── templates/
│   │   ├── triage-agent.yml      # Workflow template (low privilege)
│   │   ├── implement-agent.yml   # Workflow template (write privilege)
│   │   ├── gate-runner.yml       # Workflow template
│   │   ├── release-runner.yml    # Workflow template
│   │   ├── repo-policy.md        # Starter policy (for AI)
│   │   ├── repo-policy.yml       # Starter config (for runners)
│   │   ├── system-prompt-triage.md    # Triage agent instructions
│   │   └── system-prompt-implement.md # Implementation agent instructions
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
- PR revision loop (how to update existing PRs after feedback)

Two variants ship in the package:
- `system-prompt-triage.md` — read-only instructions, duplicate detection via GitHub search API (not `git log`), no implementation guidance
- `system-prompt-implement.md` — full implementation instructions, branching conventions, PR creation/update

Both are **generic** — they reference only the label taxonomy, state machine, and decision framework. They contain no repo-specific CI check names, languages, or tools. All repo-specific behavior comes from the user's policy file.

## Cost and Rate Limiting

- **Concurrency:** Each workflow uses `concurrency` groups keyed by issue/PR number. GitHub allows one running + one pending run per group. Handlers are idempotent — if an intermediate trigger is dropped, the next run picks up the correct state from labels.
- **Trigger filtering:** The Triage Agent skips its own bot's labels. The Implementation Agent only fires on `state:planned` labels on issues. Comment triggers are filtered to issue author + collaborators for follow-up states, collaborators-only for `@claude` mentions.
- **Model selection:** Workflow templates default to `claude-sonnet-4-6` via `claude_args: --model claude-sonnet-4-6`. Users can override in the workflow file.
- **Max turns:** Triage Agent: `--max-turns 15`. Implementation Agent: `--max-turns 40`. Set via `claude_args`.
- **Documentation:** README includes expected per-invocation cost estimates and guidance for high-traffic repos (e.g., limit triggers to `labeled` events only, disable Implementation Agent for cost control).

## Security Considerations

- **Privilege separation:** Triage Agent has read-only repo access + label/comment write. Implementation Agent has full write access but only triggers on `state:planned` labels on issues — never on PR events, never on raw comments.
- **No Bash for Triage:** Triage Agent uses only `Read`, `Grep`, `Glob` tools. No `Bash` access at all. GitHub interactions use `claude-code-action`'s built-in GitHub MCP tools. This eliminates `gh` extension/alias attack vectors.
- **Limited Bash for Implementation:** Implementation Agent's Bash access is `Bash(git:*)` only — no `gh`, no arbitrary shell. PR creation and labeling are done in post-steps using the App token.
- **Action pinning:** Workflow templates pin `anthropics/claude-code-action` to a specific release tag's commit SHA (not `HEAD` or an arbitrary commit). The `init` CLI resolves the SHA of the latest GitHub Release at scaffold time.
- **Loop prevention:** Uses label-event fingerprinting (hidden comment markers) rather than sender identity. Each workflow writes its name and run ID before applying labels; triggered workflows check the marker to detect self-triggers.
- **API key management:** Stored as GitHub repo secret, never in code
- **Permission scoping:** Each workflow requests minimum needed permissions. Triage gets `contents: read`, Implementation gets `contents: write`.
- **Fork PR handling:** Uses `pull_request_target` with checkout of default branch only (not PR head). Triage Agent reads PR diffs via GitHub MCP tools (API). This gives write permissions for labels/comments without executing untrusted code. Note: the Triage Agent still processes attacker-controlled text (issue/PR body, diff content) as prompt input — this is an inherent LLM risk mitigated by the system prompt's adversarial defense instructions, the agent's inability to modify repo files, and rate limiting via collaborator-only comment filtering.
- **Adversarial input defense:** System prompt includes deception detection instructions. Triage Agent processes untrusted content but cannot write to the repo. Implementation Agent reads issue content (inherent prompt injection surface — see mitigations in Implementation Agent section), but all generated code goes through review before merge.
- **Merge restrictions:** Agent cannot merge directly — Gate Runner is a separate, auditable workflow
- **Risk escalation:** `risk:high` always requires human approval, enforced at both the Implementation Agent level (skips `risk:high`) and Gate Runner level (blocks merge)
- **Comment filtering:** Follow-up state triggers include the issue author (so reporters can respond to info requests) plus collaborators. `@claude` triggers are collaborator-only.
- **No secrets in policy:** Policy file is committed to repo, should contain no secrets
- **Declared permissions:** Workflows explicitly declare `actions: read` for CI inspection

## User Journey

1. User discovers `repo-policy-bot` (README, blog post, word of mouth)
2. Runs `npx repo-policy-bot init` in their repo
3. Creates a GitHub App (guided by `init`) and adds credentials as repo secrets
4. Adds `ANTHROPIC_API_KEY` as repo secret
5. Edits `.github/repo-policy.md` to describe their project's values and risk boundaries
6. Optionally edits `.github/repo-policy.yml` for merge strategy and CI config
7. Commits and pushes the workflow files
8. Next issue or PR triggers the Triage Agent
9. Triage Agent labels, reviews, and escalates as appropriate
10. For `risk:low`/`risk:medium` issues labeled `state:planned`, Implementation Agent picks up work
11. Implementation Agent creates branch, implements fix, opens PR
12. Triage Agent reviews the PR, labels `state:ready-to-merge` if it passes
13. If review feedback: Triage Agent re-labels parent issue as `state:planned`, Implementation Agent revises
14. Gate Runner auto-merges when all gates pass (waits for pending CI without removing the label)
15. Release Runner cuts releases when CI completes on the default branch
16. User intervenes only for `risk:high` or `release:major` items
