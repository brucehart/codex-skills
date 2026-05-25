#!/usr/bin/env bash
set -euo pipefail

base_arg="${1:-}"
feature_arg="${2:-}"
msg_file=""
body_file=""
stash_ref=""
stash_created=0

die() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  local code=$?

  if [ -n "$msg_file" ]; then
    rm -f "$msg_file"
  fi
  if [ -n "$body_file" ]; then
    rm -f "$body_file"
  fi

  if [ "$code" -ne 0 ] && [ "$stash_created" -eq 1 ] && [ -n "$stash_ref" ]; then
    echo "Restoring stashed changes after failure..." >&2
    git checkout "$current_branch" >/dev/null 2>&1 || true
    if ! git stash pop "$stash_ref" >/dev/null 2>&1; then
      echo "Could not automatically restore the temporary stash. It remains at $stash_ref." >&2
    fi
  fi

  trap - EXIT
  exit "$code"
}

trap cleanup EXIT

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' |
    cut -c1-48
}

remote_branch_exists() {
  git ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1
}

local_branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

unique_branch() {
  local base_name="$1"
  local candidate="$base_name"
  local n=2

  while local_branch_exists "$candidate" || remote_branch_exists "$candidate"; do
    candidate="${base_name}-${n}"
    n=$((n + 1))
  done

  printf '%s\n' "$candidate"
}

ensure_base_branch() {
  local base="$1"

  if local_branch_exists "$base"; then
    git checkout "$base"
  elif remote_branch_exists "$base"; then
    git checkout -b "$base" "origin/$base"
  else
    die "base branch '$base' does not exist locally"
  fi

  git pull --ff-only origin "$base"

  local ahead_count
  ahead_count=$(git rev-list --count "origin/$base..$base")
  if [ "$ahead_count" -gt 0 ]; then
    die "base branch '$base' has $ahead_count unpushed commit(s); push it or choose a different base before creating a PR"
  fi
}

build_change_metadata() {
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
}

build_title() {
  local file_count="$1"
  local action="Update"
  local scope="repo"

  if [ "${#added[@]}" -gt 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#deleted[@]}" -eq 0 ] && [ "${#renamed[@]}" -eq 0 ]; then
    action="Add"
  elif [ "${#deleted[@]}" -gt 0 ] && [ "${#added[@]}" -eq 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#renamed[@]}" -eq 0 ]; then
    action="Remove"
  elif [ "${#renamed[@]}" -gt 0 ] && [ "${#added[@]}" -eq 0 ] && [ "${#modified[@]}" -eq 0 ] && [ "${#deleted[@]}" -eq 0 ]; then
    action="Rename"
  fi

  if [ "${#all_paths[@]}" -gt 0 ]; then
    local common_prefix="${all_paths[0]}"
    local path

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

  if [ "$scope" = "repo" ]; then
    printf '%s project files' "$action"
  else
    printf '%s %s' "$action" "$scope"
  fi
}

write_commit_message() {
  local title="$1"
  local msg_file="$2"

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
}

write_pr_body() {
  local base_branch="$1"
  local feature_branch="$2"
  local body_file="$3"

  {
    echo "## Summary"
    echo "- Commits the staged local changes on \`$feature_branch\` for review into \`$base_branch\`."
    echo
    echo "## Changes"
    if [ "${#added[@]}" -gt 0 ]; then
      echo "- Added ${#added[@]} file(s)."
    fi
    if [ "${#modified[@]}" -gt 0 ]; then
      echo "- Updated ${#modified[@]} file(s)."
    fi
    if [ "${#deleted[@]}" -gt 0 ]; then
      echo "- Removed ${#deleted[@]} file(s)."
    fi
    if [ "${#renamed[@]}" -gt 0 ]; then
      echo "- Renamed ${#renamed[@]} file(s)."
    fi
    echo
    echo "## Testing"
    echo "- Not run by this commit-and-PR script."
  } > "$body_file"
}

if ! git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  die "not inside a git repository"
fi

cd "$git_root"

if ! command -v gh >/dev/null 2>&1; then
  die "gh CLI is not installed or not on PATH"
fi

if ! gh auth status >/dev/null 2>&1; then
  die "gh CLI is not authenticated"
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  die "git remote 'origin' is not configured"
fi

current_branch=$(git symbolic-ref --quiet --short HEAD) || die "detached HEAD is not supported"
base_branch="${base_arg:-$current_branch}"

if [ -n "$feature_arg" ] && [ "$feature_arg" = "$base_branch" ]; then
  die "feature branch must be different from base branch '$base_branch'"
fi

git fetch origin --prune

if ! remote_branch_exists "$base_branch"; then
  die "base branch '$base_branch' does not exist on origin"
fi

if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "No local changes. Nothing to commit or PR."
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git stash push -u -m "gh-commit-and-create-pr temporary stash" >/dev/null
  stash_ref="stash@{0}"
  stash_created=1
fi

ensure_base_branch "$base_branch"

initial_feature_branch="${feature_arg:-feature/local-changes-$(date +%Y%m%d-%H%M%S)}"
if local_branch_exists "$initial_feature_branch" || remote_branch_exists "$initial_feature_branch"; then
  if [ -n "$feature_arg" ]; then
    die "feature branch '$feature_arg' already exists locally or on origin"
  fi
  initial_feature_branch=$(unique_branch "$initial_feature_branch")
fi

git checkout -b "$initial_feature_branch"

if [ -n "$stash_ref" ]; then
  if ! git stash pop "$stash_ref"; then
    stash_created=0
    echo "Temporary stash could not be applied cleanly. Resolve conflicts on '$initial_feature_branch' before committing." >&2
    exit 1
  fi
  stash_created=0
fi

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

build_change_metadata

title=$(build_title "$file_count")
if [ "$file_count" -gt 1 ]; then
  title="$title ($file_count files)"
fi

if [ ${#title} -gt 72 ]; then
  title=$(echo "$title" | cut -c1-69 | sed 's/[[:space:]]*$//')"..."
fi

feature_branch="$initial_feature_branch"
if [ -z "$feature_arg" ]; then
  slug=$(slugify "$title")
  if [ -z "$slug" ]; then
    slug="local-changes"
  fi
  desired_branch=$(unique_branch "feature/$slug")
  if [ "$desired_branch" != "$feature_branch" ]; then
    git branch -m "$desired_branch"
    feature_branch="$desired_branch"
  fi
fi

msg_file=$(mktemp)
body_file=$(mktemp)

write_commit_message "$title" "$msg_file"
write_pr_body "$base_branch" "$feature_branch" "$body_file"

git commit -F "$msg_file"
git push -u origin "$feature_branch"

pr_url=$(gh pr create \
  --base "$base_branch" \
  --head "$feature_branch" \
  --title "$title" \
  --body-file "$body_file")

echo
echo "Created PR:"
echo "$pr_url"
