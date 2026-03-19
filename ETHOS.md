# OpenOats Autonomous Repo Policy

This document defines how autonomous agents triage issues, review pull requests, merge changes, and cut releases for OpenOats. It is meant to be machine-operable.

## Product Guardrails

OpenOats is a local-first, macOS-native meeting copilot. Autonomous decisions should preserve these defaults:

- Privacy by default
- Simplicity over features
- macOS-native product direction
- Broad usefulness over niche workflow customization

If a proposed change conflicts with these guardrails, decline it or escalate it.

## System Of Record

- GitHub labels are the only workflow state.
- Do not use JSON files, SQLite, or sidecar state.
- Do not use git tags as workflow state. Tags are release artifacts only.
- Labels are authoritative. Comments explain decisions, but comments do not replace labels.
- For every open issue or PR, maintain exactly one label from each required namespace:
  - `kind:*`
  - `state:*`
  - `risk:*`
  - `resolution:*`
  - `release:*`
- `resolution:none` means the item is still active.
- Any `resolution:*` other than `resolution:none` means the item is terminal, must be `state:done`, and should be closed.
- If labels are missing or conflicting, normalize labels before taking any other action.
- Human label changes override agent judgment.

## Label Set

### `kind:*`

- `kind:bug` broken behavior, regressions, crashes, incorrect output
- `kind:feature` new user-facing capability or changed default behavior
- `kind:ux` copy, layout, interaction, polish, or small quality-of-life changes
- `kind:docs` README, guides, comments, templates, and docs-only work
- `kind:housekeeping` refactors, cleanup, dependencies, scripts, or repo maintenance with no intended product change

### `state:*`

- `state:new` not yet triaged
- `state:needs-info` missing key details from the reporter or author
- `state:needs-repro` enough detail exists, but the bug has not been confirmed on current code
- `state:planned` accepted and ready for implementation
- `state:in-progress` work is actively underway
- `state:awaiting-human` blocked on maintainer input
- `state:ready-to-merge` PR is policy-compliant and waiting only on merge
- `state:done` terminal state

### `risk:*`

- `risk:low` small, isolated, low-blast-radius change
- `risk:medium` contained but meaningful change inside existing product boundaries
- `risk:high` product-shape, trust-boundary, release, or architecture change that needs maintainer approval

### `resolution:*`

- `resolution:none` active item
- `resolution:merged` completed by a merged PR
- `resolution:duplicate` duplicate of another issue or PR
- `resolution:already-fixed` already solved on the default branch or in a shipped release
- `resolution:declined` valid request, not accepted
- `resolution:out-of-scope` does not fit this repo or product direction

### `release:*`

- `release:none` no user-visible release needed
- `release:patch` user-visible fix or polish, safe for a patch release
- `release:minor` new capability, new opt-in setting, or meaningful UX addition
- `release:major` breaking change, product-shape change, or maintainer-approved release only

## Risk Classification

Assign `risk:high` if any of the following are true:

- The change alters the product promise or default behavior in a meaningfully new way
- The change affects recording consent flow, privacy guarantees, what leaves the machine by default, storage defaults, permissions, or entitlements
- The change affects updater behavior, signing, notarization, release workflow, Sparkle/appcast, Homebrew packaging, or distribution
- The change is cross-platform work or a major rewrite
- The change introduces a new core abstraction or persistence model across multiple subsystems
- The change touches 9 or more files across more than one core subsystem: `Audio`, `Transcription`, `Intelligence`, `Storage`, `Settings`, `App`, `Views`

Assign `risk:low` only if all of the following are true:

- It touches docs, scripts, or a small isolated code path
- It touches 3 or fewer files in one subsystem
- It adds no new dependency, no new setting, no new permission, and no new default-on behavior
- It does not change off-device data flow, release or distribution logic, or persistence format

Anything in between is `risk:medium`.

## Default Decision Rules

### Bugs

- Fix bugs if they can be reproduced or the fix is obvious from code inspection
- Before implementing, check whether the issue is already fixed or duplicated
- If reproduction steps are missing, use `state:needs-info`
- If steps exist but the bug cannot be confirmed on current code, use `state:needs-repro`

### UX, Docs, And Housekeeping

- Accept low-risk UX polish, docs, and housekeeping by default
- Prefer the smallest change that solves the problem
- Do not add settings unless the benefit is broad or the feature is meaningfully optional

### Features

A feature may be accepted autonomously only if all of the following are true:

- It benefits more than a niche workflow
- It fits a macOS-native, local-first meeting copilot
- The complexity is proportional to the value
- Any unavoidable complexity can be hidden behind an opt-in setting
- It is not `risk:high`

Otherwise, decline it or escalate it.

## Human Escalation Boundary

Use `state:awaiting-human` and stop autonomous implementation, merge, and release when any of the following are true:

- The item is `risk:high`
- The desired behavior is materially ambiguous after one pass at clarification
- There are two plausible product directions with different tradeoffs
- A contributor PR has a good idea but needs a non-trivial redesign beyond the submitted scope
- The correct release label is `release:major`

Maintainer approval is represented by label changes in GitHub. Approval means replacing `state:awaiting-human` with the next state and, if needed, adjusting `risk:*` or `release:*`. Do not infer approval from vague positive comments alone.

## Issue Workflow

### New Issue

1. Assign `kind:*`, `risk:*`, `resolution:none`, `release:none`, and `state:new`.
2. Search for duplicates, already-fixed work, and existing support in the codebase.
3. Transition according to the first matching rule:
   - Duplicate: `state:done` + `resolution:duplicate`, then close
   - Already fixed: `state:done` + `resolution:already-fixed`, then close
   - Missing key information: `state:needs-info`
   - Needs confirmation on current code: `state:needs-repro`
   - High risk: `state:awaiting-human`
   - Accepted and actionable: `state:planned`

### Planned Issue

- Move to `state:in-progress` when implementation starts
- Open or update a linked PR
- If scope expands into `risk:high`, move to `state:awaiting-human`

### Completed Issue

- When the linked PR merges, set `state:done` + `resolution:merged`, then close

## PR Workflow

### New PR

1. Normalize labels:
   - `kind:*`
   - `risk:*`
   - `resolution:none`
   - `release:*`
   - `state:in-progress`
2. Review for duplicate work, code quality, blast radius, settings bloat, and fit with product guardrails.
3. Transition according to the first matching rule:
   - Out of scope: `state:done` + `resolution:out-of-scope`, then close
   - Declined: `state:done` + `resolution:declined`, then close
   - Needs maintainer call: `state:awaiting-human`
   - Policy-compliant and waiting on checks: `state:ready-to-merge`

### External PRs

- The idea is valuable. The exact implementation is not sacred.
- It is acceptable to push fixups, cherry-pick only the good parts, or reimplement the change in a smaller PR.
- Do not merge large external PRs wholesale if a narrower implementation is cleaner.

### Merged PR

- After merge, set `state:done` + `resolution:merged`
- Keep the assigned `release:*` label so the PR remains queryable for release batching

## Autonomous Actions

### Allowed Without Human Approval

- Label and triage issues and PRs
- Request missing reproduction details
- Close duplicates and already-fixed items
- Implement `risk:low` work
- Implement `risk:medium` work when the expected behavior is clear
- Merge `risk:low` and `risk:medium` PRs if all merge gates pass
- Cut `release:patch` and `release:minor` releases if all release gates pass

### Not Allowed Without Human Approval

- Merge or release `risk:high` work
- Create `release:major`
- Change labels only to bypass policy after a required check fails
- Ship changes that cross the human escalation boundary above

## Merge Gates

A PR may be auto-merged only if all of the following are true:

- `resolution:none`
- `state:ready-to-merge`
- Risk is not `risk:high`
- The PR is mergeable with no unresolved conflicts
- Required GitHub checks are green
- The required `validate-swift` check is green
- There is no unresolved review requesting changes
- The PR body or top comment contains a concise user-facing summary
- The `release:*` label matches the scope of the change

Use squash merge unless there is a clear reason not to.

### Required Repo Configuration

The `validate-swift` workflow must be configured as a required branch protection check for the default branch. If it is not required in GitHub settings, agent-driven auto-merge of app code is disabled.

`validate-swift` is a compile-only check. It is intentionally safe for unattended PR validation because it does not sign, package, notarize, or install into `/Applications`.

## Release Gates

A release may be created autonomously only if all of the following are true:

- There is at least one merged PR since the last GitHub release with `release:patch` or `release:minor`
- No merged PR since the last release is labeled `release:major`
- No merged PR in the release batch is `risk:high`
- The current default branch tip has a green `validate-swift` run
- The current default branch tip has a green `package-smoke` run
- Required GitHub checks and the release workflow are green
- Signing and notarization secrets required by the release workflow are available
- Release notes are generated from the merged PRs in the batch

### Required Repo Prerequisite

The `package-smoke` workflow must exist and remain non-destructive. It validates app bundling without signing, notarization, DMG creation, or installation. The release workflow alone is not a sufficient safety gate.

### Version Bump Rule

- If any unreleased merged PR is `release:minor`, bump minor
- Else if any unreleased merged PR is `release:patch`, bump patch
- `release:none` does not trigger a release
- `release:major` always requires maintainer approval

## Polling Loop

Run roughly every 30 minutes:

1. List open issues and PRs without normalized labels
2. Normalize labels and apply the workflow above
3. Comment only when the state changes or new information is required
4. For `state:planned` items, implement according to the autonomy rules
5. For `state:ready-to-merge` PRs, merge if merge gates pass
6. For merged PRs awaiting shipment, cut a release if release gates pass
7. Never revisit closed items unless they are reopened or a new linked item appears

## Repo-Specific High-Risk Rules

For OpenOats, treat the following as `risk:high` by default:

- Changes to recording consent and legal acknowledgment
- Changes to privacy defaults or what is sent to cloud providers by default
- Changes to entitlements, capture permissions, or onboarding around recording
- Changes to Sparkle, appcast generation, signing, notarization, DMG packaging, or Homebrew distribution
- Cross-platform support or non-macOS product direction

## Examples

- Tooltip, copy tweak, icon alignment, or README fix: `risk:low`
- Contained bug fix in `KnowledgeBase` or `SuggestionEngine` with no new setting: `risk:medium`
- New opt-in transcript cleanup setting: `risk:medium` + `release:minor`
- Default provider behavior change, consent flow change, or release automation change: `risk:high`
