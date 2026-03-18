# Blog Automation API for News

Base path: `/api/codex/v1`

Auth: `Authorization: Bearer $CODEX_BHART_API_TOKEN`

Local dev: `npm run dev`, then call `https://bhart.org/api/codex/v1/...`

## News endpoints

- `GET /news`
  - Query params: `status=draft|published`, `q=<text>`, `limit`, `cursor`
  - Returns: `{ news_items: [{ id, title, category, status, updated_at, published_at }], next_cursor }`

- `GET /news/:id`
  - Returns the full news item including `body_markdown`

- `POST /news`
  - Required: `category`, `title`, `body_markdown`
  - Optional: `status` (`draft` default), `published_at` (required if `status=published`)

- `PATCH /news/:id`
  - Partial updates: `category`, `title`, `body_markdown`, `status`, `published_at`
  - Concurrency: `expected_updated_at` (ISO timestamp)

## Related article endpoints

- `GET /posts`
  - Use this to locate the related article when the user does not give an ID

- `GET /posts/:id`
  - Use this to load the current article body and `updated_at`

- `PATCH /posts/:id`
  - Use this for a minimal article addendum patch
  - Relevant fields for this workflow: `body_markdown`, `hero_image_url`, `hero_image_alt`
  - Concurrency: `expected_updated_at` (ISO timestamp)
  - Recompute: `recompute: { readingTime: true }` is appropriate when appending an addendum

## Recommended workflow

1. Draft the news item body from the user's notes.
2. `POST /news`.
3. If the item should be public immediately, include `status: "published"` and `published_at`.
4. If the user also wants a related article update:
   - Load the article with `GET /posts/:id` or find it with `GET /posts`.
   - Append a dated addendum.
   - `PATCH /posts/:id` with `expected_updated_at`.

## Public link shapes in this repo

- News items: `/news#news-<id>`
- Articles: `/articles/<slug>`

## Example

```bash
curl -sS \
  -H "Authorization: Bearer $CODEX_BHART_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"category":"Update","title":"Example","body_markdown":"Short update here."}' \
  "https://bhart.org/api/codex/v1/news"
```
