---
name: gh-commit-and-push
description: Pull latest changes from origin, stage new and modified files, inspect diffs, generate a detailed commit message, commit to the current or specified branch, and push to origin. Use when the user asks to quickly commit and push local changes (optionally to a specified branch), or needs a repeatable git workflow for pull + add + inspect + commit + push.
---

# Gh Commit And Push

## Overview

Sync with origin, stage changes, understand the staged patch, write a semantic commit message, commit, and push.

## Workflow

1. Choose the target branch.
- If a branch name is provided, switch to it (create locally from origin if needed) and use it for commit and push.
- Otherwise, use the current branch.

2. Pull from origin with fast-forward only.
- Fetch from origin.
- Pull `origin/<branch>` with `--ff-only` to avoid accidental merges.

3. Stage and understand the changes.
- Stage new and modified files with `git add -A`.
- Show `git status --short` and `git diff --cached --stat` to confirm scope.
- Read the full `git diff --cached` before writing the message. Use targeted diff reads when a generated or exceptionally large file would obscure the substantive changes.
- Review recent titles with `git log -5 --format=%s` to preserve any clear project convention.
- Identify the primary user-visible or architectural outcome. Do not infer intent from filenames alone.

4. Write a semantic commit message.
- Use a Conventional Commit type when it fits: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `ci`, `build`, or `chore`.
- Write the title as `<type>: <specific outcome> (<file count> files)` and keep it at 72 characters or fewer when practical.
- Prefer an imperative, concrete outcome such as `feat: track Awetomaton careers`; never use generic titles such as `Update project files` or `Update repo`.
- Under `Summary:`, write two to five bullets describing behavior, architecture, integration, migration, and test coverage as relevant.
- Summarize what changed and why it matters. Do not use added/modified filename lists as the body.
- Under `Stats:`, report aggregate file, insertion, and deletion counts from `git diff --cached --shortstat`.
- Omit empty insertion or deletion counts rather than inventing zero-value detail.

Use this structure:

```text
feat: add OpenAI polling fallback (8 files)

Summary:
- Track accepted background response IDs and candidate paths.
- Poll unresolved responses before each cron run.
- Add integration coverage for polling recovery and late webhooks.

Stats:
- 8 files changed
- 492 insertions
- 64 deletions
```

5. Commit the reviewed staged changes.
- Show the proposed message before committing and ensure it matches the staged diff.
- If no changes remain after `git add -A`, exit without committing.
- Commit without opening an interactive editor.

6. Push to origin.
- Push the target branch to origin.
- Verify that the local branch and `origin/<branch>` point to the new commit and that the working tree is clean.

## Bundled Script

Do not use `scripts/gh_commit_and_push.sh` by default. Its one-shot message generator only analyzes file statuses and common paths, so it cannot produce a semantic summary of the staged patch.

Use the script only when the user explicitly prefers a generic filename-based commit message over semantic message quality. Otherwise, perform the workflow above directly so the commit message is based on the full diff.
