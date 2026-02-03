---
name: gh-commit-and-push
description: Pull latest changes from origin, stage new and modified files, inspect diffs, generate a detailed commit message, commit to the current or specified branch, and push to origin. Use when the user asks to quickly commit and push local changes (optionally to a specified branch), or needs a repeatable git workflow for pull + add + inspect + commit + push.
---

# Gh Commit And Push

## Overview

Automate a safe, repeatable git workflow that syncs with origin, stages changes, summarizes diffs, generates a detailed commit message, commits, and pushes.

## Workflow

1. Choose the target branch.
- If a branch name is provided, switch to it (create locally from origin if needed) and use it for commit and push.
- Otherwise, use the current branch.

2. Pull from origin with fast-forward only.
- Fetch from origin.
- Pull `origin/<branch>` with `--ff-only` to avoid accidental merges.

3. Stage and inspect changes.
- Stage new and modified files with `git add -A`.
- Inspect `git status --short` and `git diff --cached --stat`.

4. Generate a detailed commit message and commit.
- Title: concise summary (include file count or key files).
- Body: bullet list of changed files plus diff stats.
- Commit with the generated message.

5. Push to origin.
- Push the target branch to origin.

## Quick Command

Use the script for a one-shot workflow:

```bash
scripts/gh_commit_and_push.sh [branch]
```

- If `[branch]` is provided, the script will checkout or create it, pull from origin, commit there, and push to `origin/<branch>`.
- If omitted, it uses the current branch.

## Notes

- If there are no staged changes after `git add -A`, exit without committing.
- Always show `git status --short` and `git diff --cached --stat` before committing to ensure the commit message matches the actual changes.

## Resources

### scripts/

- `gh_commit_and_push.sh`: Pulls from origin, stages changes, inspects diffs, builds a detailed commit message, commits, and pushes.
