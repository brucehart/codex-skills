#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/amend_latest_commit_message.sh [--yes] [--no-push] [--max-files N]

Options:
  --yes         Skip confirmation prompt and amend immediately.
  --no-push     Do not push, even if old HEAD was already on upstream.
  --max-files   Maximum files to list per change category (default: 10).
  -h, --help    Show this help text.
EOF
}

is_positive_int() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

print_group() {
  local label="$1"
  local max_files="$2"
  local -n entries="$3"

  if (( ${#entries[@]} == 0 )); then
    return
  fi

  echo "- ${label} (${#entries[@]}):"
  local limit="${#entries[@]}"
  if (( limit > max_files )); then
    limit="$max_files"
  fi

  local i
  for (( i = 0; i < limit; i++ )); do
    echo "  - ${entries[$i]}"
  done

  if (( ${#entries[@]} > max_files )); then
    echo "  - ...and $(( ${#entries[@]} - max_files )) more"
  fi
}

auto_yes=0
no_push=0
max_files=10

while (( $# > 0 )); do
  case "$1" in
    --yes)
      auto_yes=1
      ;;
    --no-push)
      no_push=1
      ;;
    --max-files)
      if (( $# < 2 )); then
        echo "Missing value for --max-files" >&2
        exit 1
      fi
      max_files="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if ! is_positive_int "$max_files"; then
  echo "--max-files must be a positive integer." >&2
  exit 1
fi

if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "Not inside a git repository." >&2
  exit 1
fi

cd "$git_root"

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Repository has no commits yet." >&2
  exit 1
fi

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [[ -z "$branch" ]]; then
  echo "Detached HEAD is not supported. Checkout a branch and try again." >&2
  exit 1
fi

old_sha=$(git rev-parse HEAD)
old_sha_short=$(git rev-parse --short HEAD)
original_subject=$(git show -s --format=%s HEAD)
if [[ -z "$original_subject" ]]; then
  original_subject="(empty subject)"
fi

upstream_ref=""
remote=""
upstream_branch=""
was_pushed=0

if upstream_ref=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null); then
  remote="${upstream_ref%%/*}"
  upstream_branch="${upstream_ref#*/}"
  git fetch --quiet "$remote" >/dev/null 2>&1 || true
  if upstream_sha=$(git rev-parse "$upstream_ref" 2>/dev/null); then
    if git merge-base --is-ancestor "$old_sha" "$upstream_sha"; then
      was_pushed=1
    fi
  fi
fi

declare -a added=()
declare -a modified=()
declare -a deleted=()
declare -a renamed=()
declare -a all_paths=()

while IFS=$'\t' read -r status path1 path2; do
  if [[ -z "${status:-}" ]]; then
    continue
  fi

  code="${status:0:1}"
  case "$code" in
    A)
      added+=("$path1")
      all_paths+=("$path1")
      ;;
    M)
      modified+=("$path1")
      all_paths+=("$path1")
      ;;
    D)
      deleted+=("$path1")
      all_paths+=("$path1")
      ;;
    R)
      renamed+=("$path1 -> $path2")
      all_paths+=("$path2")
      ;;
    *)
      modified+=("$path1")
      all_paths+=("$path1")
      ;;
  esac
done < <(git diff-tree --no-commit-id --name-status -r -M --root HEAD)

file_count=$(( ${#added[@]} + ${#modified[@]} + ${#deleted[@]} + ${#renamed[@]} ))

action="Update"
if (( ${#added[@]} > 0 && ${#modified[@]} == 0 && ${#deleted[@]} == 0 && ${#renamed[@]} == 0 )); then
  action="Add"
elif (( ${#deleted[@]} > 0 && ${#added[@]} == 0 && ${#modified[@]} == 0 && ${#renamed[@]} == 0 )); then
  action="Remove"
elif (( ${#renamed[@]} > 0 && ${#added[@]} == 0 && ${#modified[@]} == 0 && ${#deleted[@]} == 0 )); then
  action="Rename"
fi

scope="project files"
if (( ${#all_paths[@]} > 0 )); then
  common_prefix="${all_paths[0]}"
  for path in "${all_paths[@]}"; do
    while [[ -n "$common_prefix" && "$path" != "$common_prefix" && "$path" != "$common_prefix/"* ]]; do
      common_prefix=$(dirname "$common_prefix")
      if [[ "$common_prefix" == "." || "$common_prefix" == "/" ]]; then
        common_prefix=""
        break
      fi
    done
  done

  if [[ -n "$common_prefix" ]]; then
    if (( file_count == 1 )); then
      scope="${all_paths[0]}"
    else
      scope="$common_prefix"
    fi
  fi
fi

title="${action} ${scope}"
if (( file_count > 1 )); then
  title="${title} (${file_count} files)"
fi
if (( ${#title} > 72 )); then
  title="${title:0:69}..."
fi

shortstat=$(git show --format= --shortstat HEAD | sed '/^[[:space:]]*$/d' | tail -n 1)
if [[ -z "$shortstat" ]]; then
  shortstat="No file-change stats available for HEAD."
fi

msg_file=$(mktemp)
trap 'rm -f "$msg_file"' EXIT

{
  echo "$title"
  echo
  echo "Summary:"
  echo "- Original subject: $original_subject"
  echo "- Commit analyzed: $old_sha_short"
  echo "- Change mix: ${#added[@]} added, ${#modified[@]} modified, ${#deleted[@]} deleted, ${#renamed[@]} renamed"
  echo "- Total files: $file_count"
  echo
  echo "Files Changed:"
  if (( file_count == 0 )); then
    echo "- No file entries detected for HEAD."
  else
    print_group "Added" "$max_files" added
    print_group "Modified" "$max_files" modified
    print_group "Deleted" "$max_files" deleted
    print_group "Renamed" "$max_files" renamed
  fi
  echo
  echo "Stats:"
  echo "- $shortstat"
  echo
  echo "Notes:"
  echo "- Message generated from latest commit metadata (diff stat and file status)."
} > "$msg_file"

echo "Generated commit message preview:"
echo "--------------------------------"
cat "$msg_file"
echo "--------------------------------"

if (( auto_yes == 0 )); then
  read -r -p "Amend HEAD with this message? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted. Commit was not amended."
      exit 0
      ;;
  esac
fi

git commit --amend -F "$msg_file" >/dev/null
new_sha_short=$(git rev-parse --short HEAD)
echo "Amended commit: ${old_sha_short} -> ${new_sha_short}"

if (( was_pushed == 1 )); then
  if (( no_push == 1 )); then
    echo "Old commit is on ${upstream_ref}. Skipped push because --no-push was set."
  else
    git push --force-with-lease "$remote" "HEAD:${upstream_branch}"
    echo "Force-pushed amended commit to ${upstream_ref} with --force-with-lease."
  fi
else
  echo "Old commit was not detected on upstream. No push needed."
fi
