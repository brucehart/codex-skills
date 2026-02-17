#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF2'
Usage:
  generate_header_image.sh --slug <post-slug> [options]
  generate_header_image.sh --post-id <post-id> [options]

Options:
  --prompt <text>                 Prompt text for the image model
  --prompt-file <file>            Read prompt text from a file
  --logo-url <url>                URL for a logo to include (also passed as an input image when supported)
  --alt <text>                    Alt text (if omitted, a basic one is generated)
  --model <name>                  Replicate model slug (default: google/nano-banana-pro)
  --aspect-ratio <ratio>          Aspect ratio (default: 16:9)
  --resolution <val>              Model resolution (default: 2K)
  --gen-timeout <seconds>         Timeout for image generation (default: 180)
  --gen-retries <count>           Retry count for image generation (default: 2)
  --upload-mode <mode>            Upload mode: direct|import|skip (default: direct)
  --upload-endpoint <url>         Temp upload endpoint for media import (required for --upload-mode import)
  --key-prefix <prefix>           R2 key prefix for media import (default: headers)
  --api-base <url>                Bhart Codex API base (default: https://bhart-org.bruce-hart.workers.dev/api/codex/v1)
  --python-bin <path>             Python binary override (default: ~/scripts/.venv/bin/python or python3)

Env:
  CODEX_BHART_API_TOKEN
  REPLICATE_API_TOKEN

Examples:
  bash generate_header_image.sh --slug web-tools-my-tiny-tool-factory-on-cloudflare-workers \
    --prompt-file prompt.txt \
    --logo-url https://bhart.org/media/webtools.png
EOF2
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required binary: $1" >&2; exit 1; }
}

need_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: $name" >&2
    exit 1
  fi
}

post_id=""
post_slug=""
prompt=""
prompt_file=""
logo_url=""
alt_text=""
image_model="google/nano-banana-pro"
key_prefix="headers"
api_base="https://bhart-org.bruce-hart.workers.dev/api/codex/v1"
aspect_ratio="16:9"
resolution="2K"
upload_mode="direct"
upload_endpoint=""
gen_timeout="180"
gen_retries="2"
python_bin=""

while [ $# -gt 0 ]; do
  case "$1" in
    --post-id) post_id="${2:-}"; shift 2 ;;
    --slug) post_slug="${2:-}"; shift 2 ;;
    --prompt) prompt="${2:-}"; shift 2 ;;
    --prompt-file) prompt_file="${2:-}"; shift 2 ;;
    --logo-url) logo_url="${2:-}"; shift 2 ;;
    --alt) alt_text="${2:-}"; shift 2 ;;
    --model) image_model="${2:-}"; shift 2 ;;
    --aspect-ratio) aspect_ratio="${2:-}"; shift 2 ;;
    --resolution) resolution="${2:-}"; shift 2 ;;
    --gen-timeout) gen_timeout="${2:-}"; shift 2 ;;
    --gen-retries) gen_retries="${2:-}"; shift 2 ;;
    --upload-mode) upload_mode="${2:-}"; shift 2 ;;
    --upload-endpoint) upload_endpoint="${2:-}"; shift 2 ;;
    --key-prefix) key_prefix="${2:-}"; shift 2 ;;
    --api-base) api_base="${2:-}"; shift 2 ;;
    --python-bin) python_bin="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

need_bin curl
need_bin jq
need_env CODEX_BHART_API_TOKEN
need_env REPLICATE_API_TOKEN

if [ -n "$prompt_file" ]; then
  if [ ! -f "$prompt_file" ]; then
    echo "Prompt file not found: $prompt_file" >&2
    exit 1
  fi
  prompt="$(cat "$prompt_file")"
fi

if [ -z "$prompt" ]; then
  echo "Missing --prompt or --prompt-file" >&2
  usage
  exit 1
fi

if [ -z "$post_id" ] && [ -z "$post_slug" ]; then
  echo "Missing --post-id or --slug" >&2
  usage
  exit 1
fi

if [ "$upload_mode" != "direct" ] && [ "$upload_mode" != "import" ] && [ "$upload_mode" != "skip" ]; then
  echo "Invalid --upload-mode: $upload_mode (expected direct|import|skip)" >&2
  exit 1
fi

if [ "$upload_mode" = "import" ] && [ -z "$upload_endpoint" ]; then
  echo "Missing --upload-endpoint for --upload-mode import" >&2
  exit 1
fi

auth_header=( -H "Authorization: Bearer $CODEX_BHART_API_TOKEN" )

if [ -n "$post_slug" ]; then
  encoded_slug="$(jq -rn --arg s "$post_slug" '$s|@uri')"
  post_json="$(curl -sS "${auth_header[@]}" "$api_base/posts/by-slug/$encoded_slug")"
else
  post_json="$(curl -sS "${auth_header[@]}" "$api_base/posts/$post_id")"
fi

post_id="$(jq -r '.post.id' <<<"$post_json")"
expected_updated_at="$(jq -r '.post.updated_at' <<<"$post_json")"
post_title="$(jq -r '.post.title' <<<"$post_json")"
author_name="$(jq -r '.post.author_name' <<<"$post_json")"
author_email="$(jq -r '.post.author_email' <<<"$post_json")"

if [ -z "$alt_text" ]; then
  if [ -n "$logo_url" ]; then
    alt_text="Header graphic for \"$post_title\" featuring the project logo and abstract tool tiles on a dark gradient background."
  else
    alt_text="Header graphic for \"$post_title\" with abstract tool tiles on a dark gradient background."
  fi
fi

if [ -z "$python_bin" ]; then
  if [ -x "$HOME/scripts/.venv/bin/python" ]; then
    python_bin="$HOME/scripts/.venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    python_bin="$(command -v python3)"
  elif command -v python >/dev/null 2>&1; then
    python_bin="$(command -v python)"
  else
    echo "Missing python binary. Set --python-bin or install python3." >&2
    exit 1
  fi
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python_args=(
  --prompt "$prompt"
  --model "$image_model"
  --aspect-ratio "$aspect_ratio"
  --resolution "$resolution"
)
if [ -n "$logo_url" ]; then
  python_args+=(--reference-url "$logo_url")
fi

image_path=""
attempt=0
max_attempts="$((gen_retries + 1))"
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt="$((attempt + 1))"
  echo "Generating image (attempt $attempt/$max_attempts)..." >&2
  if command -v timeout >/dev/null 2>&1; then
    image_path="$(timeout "${gen_timeout}s" "$python_bin" "$script_dir/generate_header_image.py" "${python_args[@]}")" || true
  else
    image_path="$("$python_bin" "$script_dir/generate_header_image.py" "${python_args[@]}")" || true
  fi

  if [ -n "$image_path" ] && [ -f "$image_path" ]; then
    break
  fi
  if [ "$attempt" -lt "$max_attempts" ]; then
    echo "Image generation failed or timed out. Retrying..." >&2
    sleep 2
  fi
done

if [ -z "$image_path" ] || [ ! -f "$image_path" ]; then
  echo "Failed to generate image file." >&2
  echo "Tip: verify REPLICATE_API_TOKEN and model access on Replicate." >&2
  exit 1
fi

media_url=""
if [ "$upload_mode" = "skip" ]; then
  echo "Upload skipped. Generated image at: $image_path" >&2
  echo "Next: upload to R2 and PATCH the post hero_image_url + hero_image_alt." >&2
  exit 0
fi

upload_attempt=0
upload_max_attempts=3
while [ "$upload_attempt" -lt "$upload_max_attempts" ]; do
  upload_attempt="$((upload_attempt + 1))"
  if [ "$upload_mode" = "direct" ]; then
    echo "Uploading generated image directly to R2 via Codex API (attempt $upload_attempt/$upload_max_attempts)..." >&2
    media_json="$(curl -sS "${auth_header[@]}" \
      -F "image=@${image_path}" \
      -F "alt_text=${alt_text}" \
      -F "author_name=${author_name}" \
      -F "author_email=${author_email}" \
      -F "key_prefix=${key_prefix}" \
      -F "internal_description=Generated via Replicate (${image_model})" \
      -F "tags=[\"header\",\"generated\",\"replicate\"]" \
      "$api_base/media/upload")"
  else
    echo "Uploading generated image to temp host (attempt $upload_attempt/$upload_max_attempts)..." >&2
    output_url="$(curl -sS -F "file=@${image_path}" "$upload_endpoint" | head -n 1 | tr -d '\r')"
    if [ -z "$output_url" ]; then
      echo "Temporary upload failed; no URL returned." >&2
      media_json=""
    else
      echo "Importing generated image into R2 via Bhart Codex API..." >&2
      media_payload="$(jq -n \
        --arg source_url "$output_url" \
        --arg alt_text "$alt_text" \
        --arg author_name "$author_name" \
        --arg author_email "$author_email" \
        --arg key_prefix "$key_prefix" \
        --arg internal_description "Generated via Replicate ($image_model)" \
        '{
          source_url: $source_url,
          alt_text: $alt_text,
          author_name: $author_name,
          author_email: $author_email,
          key_prefix: $key_prefix,
          internal_description: $internal_description,
          tags: ["header", "generated", "replicate"]
        }')"
      media_json="$(curl -sS "${auth_header[@]}" \
        -H "Content-Type: application/json" \
        -d "$media_payload" \
        "$api_base/media/import")"
    fi
  fi

  if [ -n "$media_json" ]; then
    media_url="$(jq -r '.media.url // empty' <<<"$media_json")"
  fi
  if [ -n "$media_url" ]; then
    break
  fi
  if [ "$upload_attempt" -lt "$upload_max_attempts" ]; then
    echo "Upload/import failed. Retrying..." >&2
    sleep 2
  fi
done

if [ -z "$media_url" ]; then
  echo "Media upload failed. Response:" >&2
  echo "$media_json" | jq . >&2 || true
  exit 1
fi

echo "Updating post hero image fields..." >&2
patch_attempt=0
patch_max_attempts=3
patched=""
while [ "$patch_attempt" -lt "$patch_max_attempts" ]; do
  patch_attempt="$((patch_attempt + 1))"
  patch_payload="$(jq -n \
    --arg hero_image_url "$media_url" \
    --arg hero_image_alt "$alt_text" \
    --arg expected_updated_at "$expected_updated_at" \
    '{hero_image_url: $hero_image_url, hero_image_alt: $hero_image_alt, expected_updated_at: $expected_updated_at}')"

  patched="$(curl -sS "${auth_header[@]}" \
    -H "Content-Type: application/json" \
    -X PATCH \
    -d "$patch_payload" \
    "$api_base/posts/$post_id")"

  patched_post_id="$(jq -r '.post.id // empty' <<<"$patched")"
  if [ -n "$patched_post_id" ]; then
    break
  fi
  if [ "$patch_attempt" -lt "$patch_max_attempts" ]; then
    echo "Post update failed. Retrying..." >&2
    sleep 2
  fi
done

patched_post_id="$(jq -r '.post.id // empty' <<<"$patched")"
if [ -z "$patched_post_id" ]; then
  echo "Post update failed. Response:" >&2
  echo "$patched" | jq . >&2 || true
  exit 1
fi

echo "$patched" | jq -r '"OK\npost_id=\(.post.id)\nslug=\(.post.slug)\nhero_image_url=\(.post.hero_image_url)\nhero_image_alt=\(.post.hero_image_alt)\n"' >&2
