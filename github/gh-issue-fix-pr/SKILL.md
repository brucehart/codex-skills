---
name: gh-issue-fix-pr
description: "Implement enhancements or fixes from one or more GitHub issues using the gh CLI. Use when a task requires: reading issues by number, creating a new branch, implementing changes, committing, opening a PR against main, and linking the issue(s) to the PR."
---

# Gh Issue Fix Pr

## Overview
Use this workflow to implement issue-driven changes with gh, keep work isolated in a new branch, and open a PR that references the issue numbers.

## Workflow

1) Confirm issue numbers
- If issue numbers are missing or ambiguous, ask the user to provide them.
- If multiple issues are provided, treat them as a single change set unless the user asks to split work.

2) Fetch issue context with gh
- Use `gh issue view <id> --web` only when needed; prefer `gh issue view <id>` for CLI details.
- Capture required acceptance criteria, labels, and any linked PRs.

3) Synchronize with origin
- Ensure local `main` is up to date before branching to avoid merge conflicts.
- Suggested sequence:
  - `git fetch origin`
  - `git checkout main`
  - `git pull --ff-only origin main`

4) Create a branch
- Base on `main` unless the repo uses a different default.
- Suggested naming: `issue-<id>-<short-slug>` or `issues-<id1>-<id2>-<slug>`.

5) Implement changes
- Follow repo instructions and existing patterns.
- Keep scope tight to the issue(s).
- Add or update tests when reasonable.

6) Validate
- Run the smallest test or build commands that establish confidence.
- If tests are not run, state why in the PR description.

7) Commit
- Use a clear commit message, e.g. `Fix #123: <short summary>` or `Implement #123/#124: <summary>`.

8) Create PR and link issues
- Use `gh pr create --base main --head <branch>`.
- Include `Fixes #<id>` or `Closes #<id>` in the PR body to auto-link.
- For multiple issues, list each on its own line.

9) Share outcome
- Provide the PR URL, branch name, and a brief summary.
- Call out any follow-ups or risks.

## Suggested gh commands (examples)

```bash
gh issue view 123

git checkout -b issue-123-short-slug

# implement changes

git status

git add -A

git commit -m "Fix #123: short summary"

gh pr create --base main --head issue-123-short-slug \
  --title "Fix #123: short summary" \
  --body $'Fixes #123\n\nSummary:\n- ...\n\nTesting:\n- ...'
```

## Notes
- If the repo requires a different base branch, use it consistently for both branch creation and PR base.
- If CI or policy requires specific PR templates, follow them.
