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
   - For each file, extract (best-effort) metadata needed for renaming:
     - Statement/document date (preferred: date on the document; fallback: filename; last resort: filesystem mtime).
     - Vendor name (preferred: on-document; fallback: filename).
     - Amount (preferred: on-document; fallback: filename; optional if not applicable).
     - Classification hints: HSA-eligible, house maintenance, or general bill/statement/receipt.
   - Use best-effort text extraction when useful:
     - PDFs: `pdftotext` (or similar) to find date/vendor/amount.
     - Images/scans: OCR if available; otherwise rely on filename + mtime and flag as ambiguous in the log.

2. Determine the destination folder (must start with `/mnt/g/My Drive/`)
   - Choose the best applicable rule below; if multiple match, prefer in this order: HSA eligible, house maintenance, then general statements.
   - HSA eligible receipts/statements:
     - Destination: `/mnt/g/My Drive/Personal/Health/[statement year]`
   - House maintenance items:
     - Destination: `/mnt/g/My Drive/Personal/Finance/House/Sable Ridge/Maintenance/[statement year]`
   - Bills/statements/receipts (everything else):
     - Destination: `/mnt/g/My Drive/Personal/Finance/Statements/[statement year]/[best-fit vendor or Misc]`
     - `[best-fit vendor]` should be the same vendor token used in the filename (ASCII + underscores). Use `Misc` if no clear vendor.
   - `[statement year]` is derived from the statement/document date used in the filename.

3. Rename the file (strict format)
   - Rename to: `YYYY-MM-DD_Vendor_Name_Dollars_Cents.[ext]`
     - `YYYY-MM-DD`: the statement/document date.
     - `Vendor_Name`: vendor name using only ASCII characters; use underscores for spaces; remove other punctuation.
     - `Dollars_Cents`: amount when applicable, formatted like `123_45` (for $123.45). If no amount applies, use a short descriptor instead of the amount, e.g. `Estimate`, `Notice`, `Warranty`.
   - Keep the original extension (case-insensitive), and do not change file content.
   - Collision handling:
     - If the target filename already exists in the destination folder, disambiguate by appending `_2`, `_3`, etc.

4. Move the file
   - Create destination folders as needed.
   - Move each file into the selected destination folder using the new filename.

5. Output required reports
   - First, output a list (one line per file) containing:
     - Original filename
     - New filename
     - Destination folder moved to
   - After that list, output a list of HSA-eligible receipts in this exact tab-delimited format (where `\t` is a literal tab character):
     - `M/D/YY\tM/D/YY\tM/D/YY\t\tVendor\t[1-2 word description]\tAmount`
   - If one of the three dates is not available, still emit the row and leave that date field blank (but keep the tabs aligned).
