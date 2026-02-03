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

title="Update $file_count file"
if [ "$file_count" != "1" ]; then
  title="Update $file_count files"
fi

short_files=$(echo "$files" | head -n 2 | paste -sd ", " -)
if [ -n "$short_files" ]; then
  candidate="$title: $short_files"
  if [ ${#candidate} -le 72 ]; then
    title="$candidate"
  fi
fi

msg_file=$(mktemp)
{
  echo "$title"
  echo
  echo "Summary:"
  echo "$files" | sed '/^$/d' | sed 's/^/- /'
  echo
  echo "Stats:"
  git diff --cached --stat
} > "$msg_file"

git commit -F "$msg_file"
rm -f "$msg_file"

git push origin "$branch"
