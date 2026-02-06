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

2. Propose a structure
   - Suggest a folder taxonomy (by project/person/year-month/type) based on what is actually present.
   - Confirm any naming rules (dates, prefixes, casing) before moving/renaming.

3. Apply changes safely
   - Prefer a dry-run preview first (list planned moves/renames).
   - Then execute moves/renames, keeping operations idempotent when possible.

4. Deliver a log
   - Provide a change log: moved/renamed/deleted (if any), with before/after paths.
   - Call out any ambiguities and items left in Inbox intentionally.

