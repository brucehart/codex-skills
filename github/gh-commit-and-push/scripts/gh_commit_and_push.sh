#!/usr/bin/env bash
set -euo pipefail

branch_arg="${1:-}"

if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "Not inside a git repository." >&2
  exit 1
fi

cd "$git_root"

current_branch=$(git rev-parse --abbrev-ref HEAD)
branch="$current_branch"

if [ -n "$branch_arg" ] && [ "$branch_arg" != "$current_branch" ]; then
  if git show-ref --verify --quiet "refs/heads/$branch_arg"; then
    git checkout "$branch_arg"
  elif git ls-remote --exit-code --heads origin "$branch_arg" >/dev/null 2>&1; then
    git checkout -b "$branch_arg" "origin/$branch_arg"
  else
    git checkout -b "$branch_arg"
  fi
  branch="$branch_arg"
fi

git fetch origin

git pull --ff-only origin "$branch"

git add -A

if git diff --cached --quiet; then
  echo "No staged changes after 'git add -A'. Nothing to commit."
  exit 0
fi

echo "Staged changes:"
git status --short

echo

git diff --cached --stat

echo

files=$(git diff --cached --name-only)
file_count=$(echo "$files" | sed '/^$/d' | wc -l | tr -d ' ')

added=()
modified=()
deleted=()
renamed=()
all_paths=()

while IFS= read -r -d '' status; do
  IFS= read -r -d '' path1 || break
  if [[ "$status" == R* ]]; then
    IFS= read -r -d '' path2 || break
    renamed+=("$path1 -> $path2")
    all_paths+=("$path2")
  else
    case "$status" in
      A) added+=("$path1") ;;
      M) modified+=("$path1") ;;
      D) deleted+=("$path1") ;;
      *) modified+=("$path1") ;;
    esac
    all_paths+=("$path1")
  fi
done < <(git diff --cached --name-status -z)

action="Update"
if [ "${#added[@]}" -gt 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#deleted[@]}" -eq 0 ] && [ "${#renamed[@]}" -eq 0 ]; then
  action="Add"
elif [ "${#deleted[@]}" -gt 0 ] && [ "${#added[@]}" -eq 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#renamed[@]}" -eq 0 ]; then
  action="Remove"
elif [ "${#renamed[@]}" -gt 0 ] && [ "${#added[@]}" -eq 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#deleted[@]}" -eq 0 ]; then
  action="Rename"
fi

scope="repo"
if [ "${#all_paths[@]}" -gt 0 ]; then
  common_prefix="${all_paths[0]}"
  for path in "${all_paths[@]}"; do
    while [ -n "$common_prefix" ] && [[ "$path" != "$common_prefix" && "$path" != "$common_prefix/"* ]]; do
      common_prefix=$(dirname "$common_prefix")
      if [ "$common_prefix" = "." ] || [ "$common_prefix" = "/" ]; then
        common_prefix=""
        break
      fi
    done
  done

  if [ -n "$common_prefix" ]; then
    if [ "$file_count" -eq 1 ]; then
      scope="${all_paths[0]}"
    else
      scope="$common_prefix"
    fi
  fi
fi

title="$action $scope"
if [ "$scope" = "repo" ]; then
  title="$action project files"
fi

if [ "$file_count" -gt 1 ]; then
  title="$title ($file_count files)"
fi

if [ ${#title} -gt 72 ]; then
  title=$(echo "$title" | cut -c1-69 | sed 's/[[:space:]]*$//')"..."
fi

msg_file=$(mktemp)
{
  echo "$title"
  echo
  echo "Summary:"
  if [ "${#added[@]}" -gt 0 ]; then
    echo "- Added (${#added[@]}):"
    printf '%s\n' "${added[@]}" | head -n 5 | sed 's/^/  - /'
    if [ "${#added[@]}" -gt 5 ]; then
      echo "  - ...and $(( ${#added[@]} - 5 )) more"
    fi
  fi
  if [ "${#modified[@]}" -gt 0 ]; then
    echo "- Updated (${#modified[@]}):"
    printf '%s\n' "${modified[@]}" | head -n 5 | sed 's/^/  - /'
    if [ "${#modified[@]}" -gt 5 ]; then
      echo "  - ...and $(( ${#modified[@]} - 5 )) more"
    fi
  fi
  if [ "${#deleted[@]}" -gt 0 ]; then
    echo "- Removed (${#deleted[@]}):"
    printf '%s\n' "${deleted[@]}" | head -n 5 | sed 's/^/  - /'
    if [ "${#deleted[@]}" -gt 5 ]; then
      echo "  - ...and $(( ${#deleted[@]} - 5 )) more"
    fi
  fi
  if [ "${#renamed[@]}" -gt 0 ]; then
    echo "- Renamed (${#renamed[@]}):"
    printf '%s\n' "${renamed[@]}" | head -n 5 | sed 's/^/  - /'
    if [ "${#renamed[@]}" -gt 5 ]; then
      echo "  - ...and $(( ${#renamed[@]} - 5 )) more"
    fi
  fi
  echo
  echo "Stats:"
  git diff --cached --stat
} > "$msg_file"

git commit -F "$msg_file"
rm -f "$msg_file"

git push origin "$branch"
