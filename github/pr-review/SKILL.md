---
name: pr-review
description: "Conduct a full review of a pending GitHub PR by reading all PR comments, inline review threads, and attached/subordinate PRs; validate expected behavior from code and PR text; and post severity-tagged security/functionality/code-smell issues as comments on the PR."
---

# PR Review

## Overview

Review pending PRs end-to-end before merge. The process must inspect the PR diff, top-level and inline review comments, and any linked/subordinate PRs, then post concise severity-tagged findings directly in the PR comments.

## Workflow

### 1) Collect PR metadata and checkout context

- Resolve PR reference from user (`<owner>/<repo>#<id>`, full URL, or PR number in current repo).
- Fetch PR context:
  - `gh pr view <PR#> --json number,title,body,author,baseRefName,headRefName,headRepository,headRepositoryOwner,url,reviews,changedFiles,maintainerCanModify,labels,assignees`.
- Fetch changed files and line-level patch details:
  - `gh pr view <PR#> --json files,commits,additions,deletions,mergeStateStatus`
  - `gh pr diff <PR#>`
- Fetch full conversation:
  - `gh pr view <PR#> --comments`
  - `gh api repos/<owner>/<repo>/pulls/<PR#>/comments --paginate`
  - `gh api repos/<owner>/<repo>/pulls/<PR#>/reviews --paginate`

### 2) Detect attached / sub-PRs

Before judging functional expectations, include all related code in scope by finding linked PRs.

- Parse PR body and existing comments for links/mentions like `#123`, `pull/123`, or URLs to `pulls/<id>`.
- Query timeline for cross-reference events:
  - `gh api repos/<owner>/<repo>/issues/<PR#>/timeline --paginate`
- Resolve each linked PR and repeat Step 1 for them.
- Consolidate a single review plan for the entire change set (parent + attached PRs).

### 3) Capture expected behavior from PR text

- Read PR body and linked discussion for acceptance criteria, edge cases, and non-functional constraints.
- Note explicit assumptions (API compatibility, auth model, rollout conditions, migration steps).
- Treat unverified assumptions as a risk point and test them during code inspection.

### 4) Review for issue classes

For each changed file/line, check:

- Security issues:
  - auth/authz bypasses
  - injection opportunities (SQL/OS/command/template)
  - secrets/logging sensitive data
  - path traversal / insecure redirects / SSRF / unsafe deserialization
- Functionality issues:
  - behavior mismatches with PR description, tests, existing API contracts, schema changes, and feature flags
  - broken error paths, off-by-one and boundary regressions, wrong defaults
  - missing null checks, race conditions, concurrency risks
- Code smells / maintainability risks:
  - duplicated logic, hidden side effects, inconsistent naming, weak validation, confusing ownership of constants
- Expected-functionality gaps:
  - missing docs/tests/telemetry/rollback steps when explicitly required
  - config/feature gate handling ignored in code
  - missing automated test coverage for changed behavior when tests exist in the project:
    - identify untested critical paths, scenarios, and edge cases introduced or modified by the PR
    - explicitly call out any gaps in the final review summary (e.g., "No tests for X behavior", "Existing tests do not validate Y").

When reviewing, cross-reference all findings with:
- explicit reviewer comments (high priority)
- top-level PR comments
- review-thread context from inline comments
- attached PR diffs

### 5) Produce prioritized findings

- Deduplicate duplicates across parent and sub-PR comments.
- Keep each finding to one location (`file:line` when available).
- Assign severity from this scale:
  - `high`: security compromise, data loss, downtime, privilege escalation
  - `medium`: incorrect behavior that affects users/reliability, important performance regressions
  - `low`: maintainability, minor edge-case behavior, style-level risk
- Include exact evidence with snippets/commands and why it is incorrect.
- Mark confidence:
  - `high` if demonstrable in code
  - `medium` if behavior depends on assumptions
  - `low` if requires additional context

### 6) Post review in PR comments section

- Post one structured summary and separate findings with this format in the PR comment:
  - `#### [SEVERITY] path:line — title`
  - `Expected behavior`, `Observed behavior`, `Why this matters`, `Suggested fix`
- Use clear, specific remediation steps.
- Include a final section:
  - `### Blockers` (high severity)
  - `### Must-fix` (medium)
  - `### Nice-to-have` (low)
- If uncertain, avoid overclaiming; state what extra check is needed.

### 7) Do not overreach

- Do not claim the PR is wrong without reproducible reason tied to code or explicit PR requirements.
- If PR is under active discussion with unresolved contradictory guidance, request clarification instead of forcing a hard verdict.

## Suggested command sequence

```bash
# Identify repo context and baseline PR metadata
gh pr view <PR#> --json number,title,body,author,baseRefName,headRefName,headRepositoryOwner,headRepository,url

# Read all feedback and inline reviews
gh pr view <PR#> --comments
gh api repos/<owner>/<repo>/pulls/<PR#>/comments --paginate
gh api repos/<owner>/<repo>/pulls/<PR#>/reviews --paginate

gh api repos/<owner>/<repo>/issues/<PR#>/timeline --paginate

gh pr diff <PR#>

gh pr comment <PR#> --body "...severity-tagged findings..."
```
