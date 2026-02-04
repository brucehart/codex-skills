# Skill Roadmap (2026-02-03)

## Summary
From `~/.codex/sessions`, the most-used skills (by explicit `<skill>` tags) were:
- `generate-story` (28)
- `draft-article` (10)
- `format-euler-code` (6)
- `gh-issue-fix-pr` (6)
- `generate-header-image` (5)
- `skill-creator` (4)
- `gh-commit-and-push` (2)
- `gh-pr-feedback` (1)

## What Went Wrong (With Dates)
- `generate-story` on January 15, 2026: blocked because a `SESSION_COOKIE` was required to find the next open date. You later replaced this with an API-token calendar endpoint.
- `generate-story` on February 2, 2026: `next-open-date.py` got a `403 Forbidden` (Cloudflare) until a browser-like `User-Agent` and `Accept: application/json` were added.
- `generate-story` on January 14, 2026: PixVerse videos played on Android but not iPhone because of H.265/codec profile mismatch; you added an `ffmpeg` re-encode step to H.264/AAC.
- `draft-article` on January 6, 2026: missing required fields (`title`, `summary`, `tags`, `author_name`, `author_email`) forced an extra loop before posting.
- `draft-article` on January 10, 2026: `REPLICATE_API_TOKEN` not visible in the running shell caused a stall.
- `gh-pr-feedback` on February 3, 2026: a PR comment was posted with backticks interpreted by the shell; a corrected comment had to be re-posted.

## Recommendations To Improve Existing Skills
- `generate-story`:
  - Add a preflight that checks for `STORY_API_TOKEN` and fails fast with a short “how to set in current shell” snippet.
  - In `.codex/skills/generate-story/scripts/next-open-date.py`, keep the Cloudflare-safe headers and add explicit retries with a short backoff. Also print the HTTP body on non-2xx for diagnostics.
  - Make video handling codec-aware: run `ffprobe` and only re-encode when needed. If `ffmpeg` is missing, the skill should give a single-line install hint and continue with “image-only” output.
- `draft-article`:
  - Add “auto-fill metadata” mode: if any required field is missing, infer title/summary/tags from prompt and load `author_name`/`author_email` from the most recent post automatically. Only ask if still missing.
  - Add a token preflight for `CODEX_BHART_API_TOKEN` and `REPLICATE_API_TOKEN` with a single short failure message.
- `generate-header-image`:
  - Make `--aspect-ratio` and `--resolution` explicit defaults in the skill instructions and script, and confirm the accepted schema before calling Replicate.
  - Always generate `hero_image_alt` and show it before the final API PATCH so you can approve or tweak.
- `gh-pr-feedback`:
  - Stop using inline strings for comments. Use `--body-file` (or a heredoc piped to `gh pr comment --body-file -`) to avoid shell interpretation of backticks/markdown.
- `gh-commit-and-push`:
  - Add a guardrail to summarize unexpected modified/untracked files and require an explicit “include all” confirmation before staging everything.

## Frequent Tasks That Could Become New Skills
- `edit-article` skill:
  - Workflow: `GET /posts?status=draft&q=...` → `GET /posts/:id` → apply edits → `PATCH /posts/:id` with `expected_updated_at`.
  - You do this routinely in the January 6 and January 9, 2026 sessions after drafts are created.
- `publish-article` skill:
  - Sets `status=published`, `published_at`, and optional SEO fields in one go, with a confirmation step.
- `add-news-item` skill:
  - You created a news item on January 6, 2026; this could be a single skill that handles category defaults and publishes or saves as draft.
- `deploy-bedtimestories` skill:
  - Run `wrangler deploy` with a brief preflight and a “dry-run” summary of what changed.
- `euler-verify` skill:
  - Compile and run a specified Euler solution file with standard flags and a short output check; you already format them consistently with `format-euler-code`.
