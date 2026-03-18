---
name: create-news-item
description: Create or publish a Bhart news item via the Blog Automation API, and optionally patch a related article with a dated addendum that links to the news item. Use for short site updates, launch notes, project progress blurbs, and other news-specific content in this repo.
---

# Create News Item

## Overview

Create a short Bhart news item from a user-provided update. Use this for news posts, launch blurbs, and "quick update" style content, not full blog articles.

Load `references/agents.md` before drafting or submitting anything.

## Workflow

### 1) Gather the minimum inputs

- Generate a `title`, `category`, and `body_markdown` if the user only gives rough notes.
- If the user does not specify publish state, default to `draft`.
- If the user clearly wants the update live now, use `status: "published"` and set `published_at`.
- If the user also wants an article updated, identify the target article before writing the addendum.

### 2) Draft the news item

- Keep it shorter and simpler than a full article.
- Prefer 2-5 short paragraphs over a long essay.
- Lead with what changed or what launched.
- Include why it matters in practical terms, not just a changelog.
- If the user provided an image URL, include it inline with sensible alt text.
- If there is an obvious next step, mention it briefly.
- Keep the tone informal, specific, and human. Avoid hype.
- Keep all content ASCII unless the source material already requires Unicode.

### 3) Submit the news item

- Call `POST /news` with `category`, `title`, and `body_markdown`.
- If publishing, include `status: "published"` and `published_at`.
- Return the created news item ID and status.

### 4) Optionally patch a related article

- Only do this when the user explicitly asks for an article update.
- Load the article source of truth first with `GET /posts/:id` or locate it via `GET /posts`.
- Append a dated addendum instead of rewriting unrelated article content.
- Keep the patch minimal and use `expected_updated_at`.
- If the news item was published, link to it using `/news#news-<id>`.
- If the user wants the updated image reflected on the article, patch `hero_image_url` and `hero_image_alt` in the same request.

## Output format

- Provide the drafted `category`, `title`, `body_markdown`, and intended `status` for review.
- If requested, submit immediately and return the created news item ID.
- If an article was patched too, return the article ID or slug and summarize the addendum you appended.

## API usage

Use `references/agents.md`. Prefer `curl` for visibility and reproducibility.

## Notes

- News items are not blog posts. Do not invent post-only metadata such as tags, summary, or SEO fields.
- For this repo's current public routes, article links use `/articles/<slug>` and news links use `/news#news-<id>`.
