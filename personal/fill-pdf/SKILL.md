---
name: fill-pdf
description: Fill interactive PDF forms with pdftk using structured context values. Use when the user provides a fillable PDF plus field data (or natural-language context) and wants a completed output PDF, flattened final copy, or help mapping context keys to PDF form field names.
---

# Fill PDF

Fill AcroForm PDFs by mapping context keys to form fields and running `pdftk` with an FDF payload.

## Workflow

1. Validate prerequisites.
- Confirm `pdftk` is installed before doing form operations.
- Treat this skill as AcroForm-focused; if the PDF has no fillable fields, report that and stop.

2. Inspect field names.
- Run:
```bash
pdftk <input.pdf> dump_data_fields_utf8
```
- Capture exact `FieldName` values and use them as target keys.

3. Build context map.
- Normalize provided context into a flat JSON object where each key is an exact field name.
- Convert values to strings when needed.
- Leave missing fields out unless the user asks for explicit blanks.

4. Fill the PDF with pdftk.
- Preferred helper:
```bash
scripts/fill_pdf.sh --input <input.pdf> --context <context.json> --output <output.pdf> [--flatten]
```
- The helper converts JSON context to FDF and calls:
```bash
pdftk <input.pdf> fill_form <tmp.fdf> output <output.pdf>
```

5. Verify result.
- Confirm output file exists and is non-empty.
- If the user asks for non-editable output, use `--flatten`.

## Quick Commands

List field names:

```bash
scripts/fill_pdf.sh --list-fields --input <input.pdf>
```

Fill from context JSON:

```bash
scripts/fill_pdf.sh --input <input.pdf> --context <context.json> --output <output.pdf>
```

Fill and flatten:

```bash
scripts/fill_pdf.sh --input <input.pdf> --context <context.json> --output <output.pdf> --flatten
```

## Notes

- Keep context keys aligned to exact PDF field names; guessing names causes silent misses.
- Prefer `dump_data_fields_utf8` output over visual assumptions from labels.
- If a field does not populate, re-check case and punctuation in the key.

## Resources

### scripts/

- `fill_pdf.sh`: Lists form fields and fills PDFs from a JSON context file via `pdftk`.
