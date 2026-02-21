#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  fill_pdf.sh --list-fields --input <input.pdf>
  fill_pdf.sh --input <input.pdf> --context <context.json> --output <output.pdf> [--flatten]

Options:
  --input <path>      Path to input PDF form
  --context <path>    JSON object of field name -> value pairs
  --output <path>     Path to output PDF
  --list-fields       Print available field names from the PDF
  --flatten           Flatten output so fields are no longer editable
  -h, --help          Show this help
USAGE
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

write_fdf_from_json() {
  local json_path="$1"
  local fdf_path="$2"

  python3 - "$json_path" "$fdf_path" <<'PY'
import json
import sys

json_path, fdf_path = sys.argv[1], sys.argv[2]

with open(json_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

if not isinstance(data, dict):
    raise SystemExit("Context JSON must be an object: {\"FieldName\": \"value\"}")


def as_text(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


def esc(value):
    value = value.replace("\\", "\\\\")
    value = value.replace("(", "\\(")
    value = value.replace(")", "\\)")
    value = value.replace("\r", "")
    value = value.replace("\n", "\\r")
    return value

lines = ["%FDF-1.2", "1 0 obj", "<<", "/FDF <<", "/Fields ["]
for key, raw_value in data.items():
    key_str = esc(str(key))
    value_str = esc(as_text(raw_value))
    lines.append(f"<< /T ({key_str}) /V ({value_str}) >>")
lines += ["]", ">>", ">>", "endobj", "trailer", "<< /Root 1 0 R >>", "%%EOF", ""]

with open(fdf_path, "w", encoding="latin-1", errors="ignore") as fh:
    fh.write("\n".join(lines))
PY
}

INPUT=""
CONTEXT=""
OUTPUT=""
FLATTEN=0
LIST_FIELDS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
      shift 2
      ;;
    --context)
      CONTEXT="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --flatten)
      FLATTEN=1
      shift
      ;;
    --list-fields)
      LIST_FIELDS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd pdftk
require_cmd python3

if [[ -z "$INPUT" ]]; then
  echo "Error: --input is required" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Error: input PDF not found: $INPUT" >&2
  exit 1
fi

if [[ "$LIST_FIELDS" -eq 1 ]]; then
  pdftk "$INPUT" dump_data_fields_utf8 \
    | awk -F': ' '/^FieldName:/{print $2}'
  exit 0
fi

if [[ -z "$CONTEXT" || -z "$OUTPUT" ]]; then
  echo "Error: --context and --output are required unless --list-fields is used" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$CONTEXT" ]]; then
  echo "Error: context JSON not found: $CONTEXT" >&2
  exit 1
fi

tmp_fdf="$(mktemp "${TMPDIR:-/tmp}/fill-pdf-XXXXXX.fdf")"
cleanup() {
  rm -f "$tmp_fdf"
}
trap cleanup EXIT

write_fdf_from_json "$CONTEXT" "$tmp_fdf"

if [[ "$FLATTEN" -eq 1 ]]; then
  pdftk "$INPUT" fill_form "$tmp_fdf" output "$OUTPUT" flatten
else
  pdftk "$INPUT" fill_form "$tmp_fdf" output "$OUTPUT"
fi

echo "Wrote filled PDF: $OUTPUT"
