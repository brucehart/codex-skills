---
name: gh-commit-and-create-pr
description: Commit current local changes to a new feature branch, push it to origin, and use the gh CLI to open a pull request back into the current branch or a user-specified base branch. Use when the user wants a gh-commit-and-push style workflow that avoids committing directly to the base branch and creates a PR instead.
---

# Gh Commit And Create Pr

## Overview

Use this workflow when the task is based on the current working tree rather than a GitHub issue. The goal is to safely move local changes onto a new feature branch, commit them there, push the branch, and open a PR back into the current branch unless the user names a different base branch.

## Workflow

1. Verify repo state and prerequisites.
- Confirm the repository is on a normal branch, not detached `HEAD`.
- Confirm `gh` is installed and authenticated before doing the PR step.
- Run `git status --short`; if there are no changes, stop without creating a branch, commit, or PR.

2. Choose the PR base branch.
- If the user provides a base branch, use it for the PR base.
- Otherwise, use the branch that was current when the workflow started.
- Do not use the remote default branch unless it is also the current or user-specified base.
- Use the same base branch for branch creation and `gh pr create --base`.

3. Synchronize the base branch.
- Fetch from origin.
- If the base branch has an upstream branch, update it with `git pull --ff-only`.
- If the local base branch has unpushed commits after pulling, stop and ask the user to push or choose a different base so the PR does not include unexpected base-branch history.
- If local changes are present before switching or pulling, preserve them with a temporary stash and restore them after creating the feature branch.
- If the stash restore conflicts, stop on the feature branch and report the conflict clearly.

4. Create or switch to the feature branch.
- Derive a branch slug from the requested change or the generated commit summary.
- Default to a feature-style branch name such as `feature/<slug>`.
- Always commit on a feature branch, never directly on the base branch.
- Create the feature branch from the synchronized base branch.
- If a feature branch name was provided explicitly by the user, prefer it over the generated name.
- If the feature branch already exists, choose a unique suffix or stop and ask before reusing it.

5. Stage and inspect the actual change set.
- Run `git add -A`.
- Review `git status --short` and `git diff --cached --stat`.
- Base both the commit message and PR description on the staged diff, not only on the original prompt.

6. Create the commit.
- Write a concise subject line that reflects the staged change.
- Keep the commit message focused on what changed, not a generic workflow note.
- If there is nothing staged after `git add -A`, stop without committing.

7. Push the branch.
- Push with upstream tracking:

```bash
git push -u origin <branch>
```

8. Create the PR with a GitHub-compatible Markdown body.
- Use `gh pr create --base <base> --head <branch>`.
- Build a structured Markdown body with these sections when applicable:
  - `## Summary`
  - `## Changes`
  - `## Testing`
  - `## Notes`
- Keep bullets flat so the formatting renders predictably on GitHub.
- Avoid nested lists unless the user explicitly asked for them.
- If shell escaping is awkward, write the body to a temporary file and use `--body-file`.

## PR Body Format

Use a body shaped like this:

```markdown
## Summary
- Short explanation of the purpose of the change.

## Changes
- Key implementation detail or behavior change.
- Additional relevant file or subsystem change.

## Testing
- Tests run, if any.
- If tests were not run, say so directly.

## Notes
- Risks, follow-ups, or review guidance when needed.
```

Rules:
- Use Markdown headings and flat bullet lists.
- Keep statements concrete and tied to the actual diff.
- Do not include HTML, nested bullets, or dense prose when a short bullet is clearer.
- Omit empty sections instead of leaving placeholders.

## Suggested Commands

```bash
git status --short
git symbolic-ref --short HEAD

# base defaults to the current branch unless the user specified another one
git fetch origin --prune
git checkout <base-branch>
git pull --ff-only origin <base-branch>
git checkout -b feature/<slug>

git add -A
git diff --cached --stat
git commit -m "<concise summary>"
git push -u origin feature/<slug>

gh pr create --base <base-branch> --head feature/<slug> \
  --title "<concise summary>" \
  --body-file /tmp/pr-body.md
```

## Quick Command

Use the script for a one-shot workflow:

```bash
scripts/gh_commit_and_create_pr.sh [base-branch] [feature-branch]
```

- If `[base-branch]` is omitted, the script targets the branch that was current when it started.
- If `[feature-branch]` is omitted, the script derives a unique `feature/<slug>` branch from the staged change summary.
- The script stages all changes, creates a commit, pushes the feature branch, and creates the PR with `gh pr create`.
- The script requires the base branch to exist on `origin`, because GitHub cannot create a PR into a local-only base branch.

## Notes

- Prefer `gh pr create --body-file` for multi-section PR descriptions to avoid quoting mistakes.
- If the repository uses a PR template, follow it while keeping the same Markdown-safe structure.
- If `origin` or `gh` authentication is unavailable, stop and report the concrete setup problem instead of continuing partially.
- If the user asks to target a branch other than the current branch, treat that branch as the PR base, not as the branch that receives the commit.
