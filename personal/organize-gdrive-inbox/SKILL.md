---
name: "organize-gdrive-inbox"
description: "Organize /mnt/g/My Drive/Inbox/To File by classifying, renaming, moving to Personal/* destinations, and producing required logs (including an HSA table)."
---

# Organize GDrive Inbox

Use this skill when the user asks to file documents from `/mnt/g/My Drive/Inbox/To File` into the correct `/mnt/g/My Drive/Personal/...` folders with a strict naming convention and required reporting.

## Workflow

1. Inspect every file in `To File`
   - Enumerate *every file* under `/mnt/g/My Drive/Inbox/To File` (recursively).
   - Ignore folders for filing purposes, but do not skip files nested under subfolders.
   - Detect when multiple PDFs belong to the same item/invoice and treat them as a single filing unit.
   - For each file, extract (best-effort) metadata needed for renaming:
     - Statement/document date (preferred: date on the document; fallback: filename; last resort: filesystem mtime).
     - Vendor name (preferred: on-document; fallback: filename).
     - Amount (preferred: on-document; fallback: filename; optional if not applicable).
     - Classification hints: HSA-eligible, house maintenance, or general bill/statement/receipt.
   - Use best-effort text extraction when useful:
     - PDFs: `pdftotext` (or similar) to find date/vendor/amount.
     - Images/scans: OCR if available; otherwise rely on filename + mtime and flag as ambiguous in the log.

2. Determine the destination folder (must start with `/mnt/g/My Drive/`)
   - Choose the best applicable rule below; if multiple match, prefer in this order: HSA eligible, house maintenance, general statements, then other receipts/finance items.
   - HSA eligible receipts/statements:
     - Destination: `/mnt/g/My Drive/Personal/Health/[statement year]`
   - House maintenance items:
     - Destination: `/mnt/g/My Drive/Personal/Finance/House/Sable Ridge/Maintenance/[statement year]`
   - Bills and statements:
     - Destination: `/mnt/g/My Drive/Personal/Finance/Statements/[statement year]/[best-fit vendor or Misc]`
     - `[best-fit vendor]` should be the same vendor token used in the filename (ASCII + underscores). Use `Misc` if no clear vendor.
   - Other receipts:
     - Destination: `/mnt/g/My Drive/Personal/Finance/Receipts/[statement year]`
   - Other finance items that are neither receipts nor statements:
     - Destination: `/mnt/g/My Drive/Personal/Finance/Other/[statement year]`
   - `[statement year]` is derived from the statement/document date used in the filename.

3. Rename the file (strict format)
   - Rename to: `YYYY-MM-DD_Vendor_Name_Dollars_Cents.[ext]`
     - `YYYY-MM-DD`: the statement/document date.
     - `Vendor_Name`: vendor name using only ASCII characters; use underscores for spaces; remove other punctuation.
     - `Dollars_Cents`: amount when applicable, formatted like `123_45` (for $123.45). If no amount applies, use a short descriptor instead of the amount, e.g. `Estimate`, `Notice`, `Warranty`.
   - Keep the original extension (case-insensitive), and do not change file content.
   - Collision handling:
     - If the target filename already exists in the destination folder, disambiguate by appending `_2`, `_3`, etc.

4. Prepare the file for moving
   - If multiple PDFs belong to the same item/invoice, combine them into a single PDF with `pdftk` before moving them, and do not move the individual PDFs separately.
   - The combined PDF should use the final destination filename and remain a `.pdf`.
   - Create destination folders as needed.
   - Prepare each file, or each combined PDF, for moving into the selected destination folder using the new filename.

5. Apply changes safely
   - Execute the approved moves/renames.
   - Keep operations idempotent when possible (avoid overwriting; prefer `mv -n` semantics).
   - Do not delete anything unless explicitly requested.

6. Deliver a log
   - First, output a list (one line per file) containing:
     - Original filename
     - New filename
     - Destination folder moved to
   - Provide a change log: moved/renamed/combined (and deleted, if any), with before/after paths.
   - Call out any ambiguities and items left in Inbox intentionally.
   - Include where the change log is saved (for example, a timestamped file in `/tmp/`).
   - After the change log, output HSA-eligible receipts using the required TSV format below.

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

## HSA Output Format (Required)

When reporting HSA-eligible receipts, output rows in a tab-separated format that can be copied directly into Google Sheets.

- Header must be exactly:
  - `Date Start	Date End	Paid Date	Patient	Provider	For	Amount	Receipt`
- Emit the HSA output as a single fenced `tsv` code block containing only the header row plus data rows.
  - Do not use markdown tables, bullets, numbering, inline code, alignment spaces, or prose inside that block.
- Use literal tab characters between all columns (TSV), not commas and not the two-character sequence `\t`.
- Every line in the TSV block must have exactly 8 cells / 7 tab separators so it pastes cleanly into the 8 Google Sheet columns above.
- Do not pad cells with leading or trailing spaces to make columns look visually aligned in the response.
- Format date values as `M/D/YY` (example: `2/19/26`).
- Use plain numeric values in `Amount` with no `$` and no thousands separators (example: `12.95`).
- The `Receipt` column value must be the green checkbox emoji: `✅`.
- `Patient` must be one of: `BJ`, `Stef`, `Grace`, `James`.
  - If unclear which family member the expense is for, default `Patient` to `Stef`.
- `For` should describe the expense purpose (examples: `Office Visit`, `Dental`, `Rx`, `OTC Supplies/Medication`).
  - If unknown, default `For` to `OTC Supplies/Medication`.
- If a date is unknown, leave the cell blank rather than inventing a value.
- Save the same TSV content verbatim to a timestamped file in `/tmp/` (for example `/tmp/organize_gdrive_inbox_hsa_<timestamp>.tsv`) and report that path in the final response.

Example:

```tsv
Date Start	Date End	Paid Date	Patient	Provider	For	Amount	Receipt
2/20/26	2/20/26		BJ	The Little Clinic	Office Visit	12.95	✅
```
