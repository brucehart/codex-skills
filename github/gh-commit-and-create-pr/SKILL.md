---
name: gh-commit-and-create-pr
description: Commit the current local changes on a feature branch, push the branch to origin, and use the gh CLI to open a pull request with a detailed GitHub-compatible Markdown description. Use when the user wants to turn an in-progress working tree into a PR without starting from a GitHub issue.
---

# Gh Commit And Create Pr

## Overview

Use this workflow when the task is based on the current working tree rather than a GitHub issue. The goal is to safely move the local changes onto a feature branch, create a commit, push it, and open a PR with a clear Markdown body that renders cleanly on GitHub.

## Workflow

1. Verify repo state and prerequisites.
- Confirm the repository is on a normal branch, not detached `HEAD`.
- Confirm `gh` is installed and authenticated before doing the PR step.
- Run `git status --short`; if there are no changes, stop without creating a branch, commit, or PR.

2. Detect the base branch.
- Prefer the remote default branch from `refs/remotes/origin/HEAD`.
- Fall back to `main` if the remote default cannot be resolved.
- Use the same base branch for both branch reasoning and `gh pr create --base`.

3. Check whether it is safe to branch from the current `HEAD`.
- If the current branch is the detected base branch, continue.
- If the current branch is already a feature branch but the local changes are clearly meant for it, continue and reuse that branch.
- If the current branch appears to contain unrelated commits ahead of the base branch, stop and ask before opening a PR. Do not guess and risk a PR with unexpected history.

4. Create or switch to the feature branch.
- Derive a branch slug from the requested change or the generated commit summary.
- Default to a feature-style branch name such as `feature/<slug>`.
- If the branch does not exist yet, create it from the current `HEAD` so the uncommitted changes move with it.
- If a branch name was provided explicitly by the user, prefer it over the generated name.

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
git symbolic-ref refs/remotes/origin/HEAD

# create or switch to the feature branch
git checkout -b feature/<slug>

git add -A
git diff --cached --stat
git commit -m "<concise summary>"
git push -u origin feature/<slug>

gh pr create --base <base-branch> --head feature/<slug> \
  --title "<concise summary>" \
  --body-file /tmp/pr-body.md
```

## Notes

- Prefer `gh pr create --body-file` for multi-section PR descriptions to avoid quoting mistakes.
- If the repository uses a PR template, follow it while keeping the same Markdown-safe structure.
- If `origin` or `gh` authentication is unavailable, stop and report the concrete setup problem instead of continuing partially.
