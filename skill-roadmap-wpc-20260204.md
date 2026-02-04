# Skill Roadmap (WPC 2026-02-04)

## Skill Usage Summary (From Local Logs)
From `~/.codex/sessions` on this machine:
- `gh-issue-fix-pr`: 10 uses (2026-02-02 to 2026-02-03)
- `format-euler-code`: 8 uses (2026-01-20 to 2026-01-29)
- `generate-story`: 7 uses (2026-01-09 to 2026-01-30)
- `gh-pr-feedback`: 7 uses (2026-02-02 only)
- `draft-article`: 2 uses (2026-01-27 only)
- `skill-creator`: 2 uses (2026-01-29 to 2026-02-02)
- `skill-installer`: 1 use (2026-01-23 only)

## What Went Wrong (With Dates)
- `generate-story`
  - 2026-01-21: workflow assumed `python` but only `python3` existed (`python: command not found`).
  - 2026-01-21: Replicate image download failed; `/tmp/story-image.jpg` missing.
  - 2026-01-21: Replicate polling returned empty output, causing JSON decode errors.
- `draft-article`
  - 2026-01-27: `jq` failed due to shell quoting, then curl failed writing output.
  - 2026-01-27: `python` not found in helper steps.
- `gh-pr-feedback`
  - 2026-02-02: shell quoting caused `unexpected EOF` while running a command.
  - 2026-02-02: compile failed with Rust error `E0277` in `src/commands/pii.rs`.
  - 2026-02-02: `gh pr create` failed because there were no commits between branches.
  - 2026-02-02: `gh pr view --json` used unsupported fields (`repository`, `reviewThreads`).
- `gh-issue-fix-pr`
  - 2026-02-02: compile failed with `cannot find value tls_details in this scope`.
- `skill-creator`
  - 2026-01-29: packaging failed due to invalid YAML frontmatter.
  - 2026-01-29: cleanup failed because deletion was blocked by policy.
  - 2026-02-02: expected `/home/bhart/.codex/skills/scripts` but it didn’t exist.
- `skill-installer`
  - 2026-01-23: skill assumed `prompts/` directory; `ls` and `rg` failed.
- `format-euler-code`
  - No clear runtime errors in logs; issues appear minimal.

## Recommendations To Improve Existing Skills
- `generate-story`
  - Use `python3` everywhere; preflight `python3` and `curl`.
  - Add retry + empty-response guard for Replicate polling.
  - Confirm file download exists before upload.
- `draft-article`
  - Avoid shell-quoting traps; use temp files for `jq` or `python3 -c` for JSON parsing.
  - Preflight `jq` and `python3` and fail fast with a one-line fix.
- `gh-pr-feedback`
  - Use `--body-file`/heredoc for comments to avoid quoting issues.
  - Restrict `gh pr view --json` to supported fields; add fallback.
  - Guard against “no commits between branches” before creating PR.
  - Run build/test early and stop on compile errors.
- `gh-issue-fix-pr`
  - Add a compile/test checkpoint right after core edits.
  - If build fails, summarize the exact error and pause for user decision.
- `skill-creator`
  - Validate YAML frontmatter before packaging.
  - Don’t assume `scripts/` exists; check and branch.
  - If deletion is blocked, move to a quarantine folder instead of failing cleanup.
- `skill-installer`
  - Check for `prompts/` before `rg`; fall back to `AGENTS.md`/`README.md` when missing.
- `format-euler-code`
  - Optional: add a diff-only mode to minimize unintended logic changes.

## Frequent Tasks That Could Become New Skills
- `agents-md-generator`
  - Standardize creation/updating of `AGENTS.md` across repos.
- `wrangler-deploy`
  - Wrap `wrangler deploy`, summarize changes, and check env/secret diffs.
- `test-fix-loop`
  - Run tests, capture failures, apply minimal fixes, re-run.
- `readme-updater`
  - Update README sections consistently with a structured template.
- `rename-batch`
  - Rename files to strict formats with a preview step.
- `yt-transcript-troubleshoot`
  - Standardized debugging for YouTube transcript API issues.
- `obituary-update`
  - Apply Wikipedia-style edits and fact checks to obituary drafts.
