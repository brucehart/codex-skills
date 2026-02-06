---
name: "organize-gdrive-inbox"
description: "Triage and organize files in /mnt/g/My Drive/Inbox: classify, rename, dedupe, and move into a predictable folder structure while producing a change log."
---

# Organize GDrive Inbox

Use this skill when the user asks to clean up or organize their Google Drive `Inbox` folder (e.g., rename files, sort into folders, remove duplicates, or produce an inventory).

## Workflow

1. Inventory
   - Enumerate files/folders under `/mnt/g/My Drive/Inbox` and capture: path, size, modified time, extension.
   - If the user cares about media, also capture basic metadata (dimensions/duration) when feasible.
   - If there is an obvious staging folder (commonly `To File/`), inventory that folder separately and treat it as the primary set of items to move, unless the user says otherwise.

2. Propose a structure
   - Suggest a folder taxonomy (by project/person/year-month/type) based on what is actually present.
   - Confirm any naming rules (dates, prefixes, casing) before moving/renaming.
   - If the Inbox contains statements (PDFs that look like financial statements):
     - Inspect the existing canonical structure under `/mnt/g/My Drive/Personal/Finance/Statements` and mirror it instead of inventing a new taxonomy.
     - Default convention observed in that tree (verify locally and follow it):
       - Destination: `/mnt/g/My Drive/Personal/Finance/Statements/<YYYY>/<Vendor>/...`
       - Filenames commonly start with `YYYY-MM-DD_<Vendor>...` (underscore-separated, no spaces).
   - If the Inbox contains receipts (PDFs/emails/scans) and the user has not specified a destination, default to:
     - HSA-eligible receipts: `/mnt/g/My Drive/Personal/Health/<YYYY>/`
     - House maintenance (Sable Ridge): `/mnt/g/My Drive/Personal/Finance/House/Sable Ridge/Maintenance/<YYYY>/`
     - Other miscellaneous receipts: `/mnt/g/My Drive/Personal/Finance/Receipts/<YYYY>/`
     - Other (non-receipt/non-statement) items: `/mnt/g/My Drive/Personal/Finance/Other/<YYYY>/`

3. Classify and normalize (statements)
   - Use `pdftotext` (prefer first page) to classify issuer/vendor and (when present) the statement date and statement amount.
   - Prefer content-derived classification over PDF metadata.
   - Amount extraction (for filenames):
     - Prefer "New Balance" / "New balance as of" on the first page.
     - Normalize to `<dollars>_<cents>` (remove `$` and commas, replace `.` with `_`), e.g. `$3,812.73` -> `3812_73`.
   - Naming:
     - Target pattern for statements should match the existing tree, typically:
       - `YYYY-MM-DD_<Vendor>_<dollars>_<cents>.pdf`
     - If the vendor tree uses a slightly different pattern (e.g. occasional missing amount), follow the dominant local convention and only introduce new patterns with user confirmation.

4. Dry-run plan (required)
   - Always show an explicit dry-run plan as a list of move/rename operations with full before/after paths.
   - Run a collision check: verify each destination path does not already exist; if it does, propose an alternate (e.g. add suffix) and ask for confirmation.
   - Respect user-scoped constraints. Examples:
     - If the user says "only move `To File/`" then do not touch other Inbox items.
     - If the user says "leave images alone" then do not rename or move images.
   - Ask for confirmation before doing any filesystem modifications.

5. Apply changes safely
   - Execute the approved moves/renames.
   - Keep operations idempotent when possible (avoid overwriting; prefer `mv -n` semantics).
   - Do not delete anything unless explicitly requested.

6. Deliver a log
   - Provide a change log: moved/renamed/deleted (if any), with before/after paths.
   - Call out any ambiguities and items left in Inbox intentionally.
   - Include where the change log is saved (e.g., a timestamped file in `/tmp/`).

## Receipt Naming Rules (Default)

When organizing receipts (including HSA receipts and house maintenance items), use a consistent filename format:

- `YYYY-MM-DD_<Vendor>_<AmountOrDescriptor>.<ext>`
- `Vendor`: 1-4 words max, title-cased or as it appears on the receipt; normalize whitespace to underscores.
- `AmountOrDescriptor`:
  - If an amount is available: use `<dollars>_<cents>` (same normalization as statements).
  - If no amount is available: use a short descriptor (1-2 words), e.g. `Quote`, `Notice`, `Invoice`, `Receipt`, `Estimate`, `Statement`.

Classification defaults (unless the user overrides):

- If the receipt appears HSA-eligible (medical/dental/vision/pharmacy, etc.): move to `/mnt/g/My Drive/Personal/Health/<YYYY>/`.
- If it appears to be a house maintenance item (repairs, contractors, home services) for Sable Ridge: move to `/mnt/g/My Drive/Personal/Finance/House/Sable Ridge/Maintenance/<YYYY>/`.
- Otherwise: move to `/mnt/g/My Drive/Personal/Finance/Receipts/<YYYY>/`.
  - If it's not a receipt/statement but still belongs in Finance: move to `/mnt/g/My Drive/Personal/Finance/Other/<YYYY>/`.

Implementation notes:

- Determine `YYYY-MM-DD` from the document content when possible (prefer over filesystem timestamps).
- If only month/year is present, ask the user how to date it (or use the last day of the month only with explicit confirmation).
