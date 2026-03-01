---
name: git-commit-msg
description: Analyze the latest Git commit and amend it with a detailed structured message based on file status and diff stats. Use when the user asks to rewrite, improve, or standardize the most recent commit message, including after the commit is already created.
---

# Git Commit Msg

## Overview

Generate a detailed commit message for `HEAD` without loading broad repository context, preview it, and amend the latest commit. Detect whether the original `HEAD` is already on upstream and force-push with `--force-with-lease` when required.

## Workflow

1. Ensure the repository is on a normal branch (not detached `HEAD`).
2. Run:

```bash
scripts/amend_latest_commit_message.sh
```

3. Review the message preview shown by the script.
4. Confirm the amend prompt to update `HEAD`.

## Message Format

Generate a structured message with:

- A concise title line.
- `Summary` section.
- `Files Changed` section grouped by Added, Modified, Deleted, and Renamed.
- `Stats` section using git shortstat output.
- `Notes` section documenting that the message was derived from latest commit metadata.

## Options

Use optional flags when needed:

- `--yes`: skip interactive confirmation.
- `--no-push`: never push, even when old `HEAD` was on upstream.
- `--max-files N`: cap file entries shown per section (default `10`).

## Safety and Token Efficiency

Keep analysis strictly to latest-commit metadata:

- `git diff-tree --name-status` for file status classification.
- `git show --shortstat` for compact statistics.

Do not scan the full repo or load large code context to generate the message.

## Resources

- `scripts/amend_latest_commit_message.sh`: Build preview message, amend `HEAD`, and force-push with `--force-with-lease` when needed.
