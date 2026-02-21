#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_INPUT="$SCRIPT_DIR"
REPO_PATH_DEFAULT=""
SELECTED_INDEX=-1
RESOLVED_DESTINATION_ROOT=""

cleanup_terminal() {
  tput cnorm >/dev/null 2>&1 || true
}

trap cleanup_terminal EXIT INT TERM

print_usage() {
  cat <<'EOF'
Usage: ./skill-installer.sh [--root <path>] [--repo-path <repo-path>]

Options:
  --root <path>       Root directory to scan for skills (default: script directory)
  --repo-path <path>  Default repo root when choosing "install to repo/.codex/skills"
  -h, --help          Show this help message

Examples:
  ./skill-installer.sh
  ./skill-installer.sh --repo-path ~/work/my-repo
  ./skill-installer.sh --root /path/to/skills
EOF
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

expand_path() {
  local raw_path="$1"

  if [[ "$raw_path" == "~" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  if [[ "$raw_path" == ~/* ]]; then
    printf '%s\n' "$HOME/${raw_path#~/}"
    return 0
  fi

  printf '%s\n' "$raw_path"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --root)
        if (($# < 2)); then
          echo "Missing value for --root"
          exit 1
        fi
        ROOT_INPUT="$2"
        shift 2
        ;;
      --repo-path)
        if (($# < 2)); then
          echo "Missing value for --repo-path"
          exit 1
        fi
        REPO_PATH_DEFAULT="$2"
        shift 2
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        ROOT_INPUT="$1"
        shift
        ;;
    esac
  done
}

toml_get_value() {
  local file="$1"
  local key_pattern="$2"
  local value=""

  value="$(sed -nE "s/^[[:space:]]*(${key_pattern})[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\2/p" "$file" | head -n1)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(sed -nE "s/^[[:space:]]*(${key_pattern})[[:space:]]*=[[:space:]]*'([^']*)'.*/\2/p" "$file" | head -n1)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(sed -nE "s/^[[:space:]]*(${key_pattern})[[:space:]]*=[[:space:]]*([^#]+).*/\2/p" "$file" | head -n1)"
  value="$(trim_whitespace "$value")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  fi
}

find_config_toml() {
  local dir="$1"
  local candidate=""
  local match=""

  for candidate in \
    "$dir/skill.toml" \
    "$dir/config.toml" \
    "$dir/skill-config.toml" \
    "$dir/metadata.toml"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  match="$(find "$dir" -maxdepth 1 -type f \( -iname "*skill*.toml" -o -iname "*config*.toml" \) | head -n1 || true)"
  if [[ -n "$match" ]]; then
    printf '%s\n' "$match"
  fi
}

discover_skills() {
  local root="$1"
  local -n out_paths_ref="$2"
  local -n out_labels_ref="$3"
  local -n out_names_ref="$4"

  local -a dirs=()
  mapfile -t dirs < <(find "$root" -mindepth 1 -type d -not -path "*/.*" | sort)

  local dir=""
  local rel_path=""
  local folder_name=""
  local config_toml=""
  local name=""
  local description=""
  local label=""
  local has_skill_md=0
  local parsed_name=""
  local parsed_description=""

  for dir in "${dirs[@]}"; do
    has_skill_md=0
    if [[ -f "$dir/SKILL.md" ]]; then
      has_skill_md=1
    fi

    config_toml="$(find_config_toml "$dir" || true)"
    if (( ! has_skill_md )) && [[ -z "$config_toml" ]]; then
      continue
    fi

    folder_name="$(basename "$dir")"
    rel_path="${dir#"$root"/}"
    name="$folder_name"
    description=""

    if [[ -n "$config_toml" ]]; then
      parsed_name="$(toml_get_value "$config_toml" "name|skill_name|title|id" || true)"
      parsed_description="$(toml_get_value "$config_toml" "description|summary" || true)"

      if [[ -n "$parsed_name" ]]; then
        name="$parsed_name"
      fi
      if [[ -n "$parsed_description" ]]; then
        description="$parsed_description"
      fi
    fi

    label="$name"
    if [[ "$name" != "$folder_name" ]]; then
      label="$label [$folder_name]"
    fi
    if [[ -n "$description" ]]; then
      label="$label - $description"
    fi
    label="$label ($rel_path)"

    out_paths_ref+=("$dir")
    out_labels_ref+=("$label")
    out_names_ref+=("$name")
  done
}

read_key() {
  local key=""
  local next=""
  local final=""

  if ! IFS= read -rsn1 key; then
    printf 'quit\n'
    return 0
  fi

  case "$key" in
    $'\x1b')
      IFS= read -rsn1 -t 0.01 next || true
      if [[ "$next" == "[" ]]; then
        IFS= read -rsn1 -t 0.01 final || true
        case "$final" in
          A) printf 'up\n' ;;
          B) printf 'down\n' ;;
          C) printf 'right\n' ;;
          D) printf 'left\n' ;;
          5)
            IFS= read -rsn1 -t 0.01 _ || true
            printf 'pgup\n'
            ;;
          6)
            IFS= read -rsn1 -t 0.01 _ || true
            printf 'pgdn\n'
            ;;
          *)
            printf 'other\n'
            ;;
        esac
      else
        printf 'other\n'
      fi
      ;;
    $'\n'|$'\r'|"")
      printf 'enter\n'
      ;;
    $'\x7f')
      printf 'backspace\n'
      ;;
    [0-9])
      printf 'digit:%s\n' "$key"
      ;;
    n|N)
      printf 'nextpage\n'
      ;;
    p|P)
      printf 'prevpage\n'
      ;;
    q|Q)
      printf 'quit\n'
      ;;
    *)
      printf 'other\n'
      ;;
  esac
}

render_menu() {
  local title="$1"
  local menu_name="$2"
  local selected="$3"
  local page_size="$4"
  local number_buffer="$5"
  local -n menu_ref="$menu_name"

  local total="${#menu_ref[@]}"
  local total_pages=$(( (total + page_size - 1) / page_size ))
  local current_page=$(( selected / page_size ))
  local start=$(( current_page * page_size ))
  local end=$(( start + page_size - 1 ))
  local i=0

  if (( end >= total )); then
    end=$((total - 1))
  fi

  clear
  printf '%s\n' "$title"
  printf 'Use Up/Down to move, Enter to select, digits + Enter for direct choice, q to cancel.\n'
  if (( total_pages > 1 )); then
    printf 'Use Left/Right, PgUp/PgDn, or n/p for pagination.\n'
  fi
  printf 'Page %d/%d  Total: %d\n\n' "$((current_page + 1))" "$total_pages" "$total"

  for ((i = start; i <= end; i++)); do
    if (( i == selected )); then
      printf '> %3d) %s\n' "$((i + 1))" "${menu_ref[i]}"
    else
      printf '  %3d) %s\n' "$((i + 1))" "${menu_ref[i]}"
    fi
  done

  if [[ -n "$number_buffer" ]]; then
    printf '\nTyped number: %s\n' "$number_buffer"
  fi
}

select_from_menu() {
  local title="$1"
  local menu_name="$2"
  local page_size="$3"
  local -n menu_ref="$menu_name"

  local total="${#menu_ref[@]}"
  local selected=0
  local number_buffer=""
  local action=""
  local digit=""
  local typed=0

  if (( total == 0 )); then
    return 1
  fi

  tput civis >/dev/null 2>&1 || true

  while true; do
    render_menu "$title" "$menu_name" "$selected" "$page_size" "$number_buffer"
    action="$(read_key)"

    case "$action" in
      up)
        ((selected = (selected - 1 + total) % total))
        number_buffer=""
        ;;
      down)
        ((selected = (selected + 1) % total))
        number_buffer=""
        ;;
      left|pgup|prevpage)
        ((selected -= page_size))
        if (( selected < 0 )); then
          selected=0
        fi
        number_buffer=""
        ;;
      right|pgdn|nextpage)
        ((selected += page_size))
        if (( selected >= total )); then
          selected=$((total - 1))
        fi
        number_buffer=""
        ;;
      digit:*)
        digit="${action#digit:}"
        number_buffer+="$digit"
        typed=$((10#$number_buffer))
        if (( typed >= 1 && typed <= total )); then
          selected=$((typed - 1))
        fi
        ;;
      backspace)
        if [[ -n "$number_buffer" ]]; then
          number_buffer="${number_buffer%?}"
          if [[ -n "$number_buffer" ]]; then
            typed=$((10#$number_buffer))
            if (( typed >= 1 && typed <= total )); then
              selected=$((typed - 1))
            fi
          fi
        fi
        ;;
      enter)
        if [[ -n "$number_buffer" ]]; then
          typed=$((10#$number_buffer))
          if (( typed >= 1 && typed <= total )); then
            selected=$((typed - 1))
          else
            number_buffer=""
            continue
          fi
        fi
        SELECTED_INDEX="$selected"
        tput cnorm >/dev/null 2>&1 || true
        return 0
        ;;
      quit)
        tput cnorm >/dev/null 2>&1 || true
        return 130
        ;;
      *)
        ;;
    esac
  done
}

resolve_destination_root() {
  local default_repo_path="$1"
  local destination_page_size="$2"
  local -a destination_options=()
  local repo_path_input="$default_repo_path"
  local repo_path_resolved=""

  if [[ -n "$default_repo_path" ]]; then
    destination_options=(
      "Install to $HOME/.codex/skills"
      "Install to repo .codex/skills (default repo: $default_repo_path)"
    )
  else
    destination_options=(
      "Install to $HOME/.codex/skills"
      "Install to repo .codex/skills"
    )
  fi

  if ! select_from_menu "Choose install destination" destination_options "$destination_page_size"; then
    return 130
  fi

  case "$SELECTED_INDEX" in
    0)
      RESOLVED_DESTINATION_ROOT="$HOME/.codex/skills"
      return 0
      ;;
    1)
      tput cnorm >/dev/null 2>&1 || true
      clear
      if [[ -n "$default_repo_path" ]]; then
        read -r -p "Enter repository root path [$default_repo_path]: " repo_path_input
        repo_path_input="${repo_path_input:-$default_repo_path}"
      else
        read -r -p "Enter repository root path: " repo_path_input
      fi

      if [[ -z "$repo_path_input" ]]; then
        echo "No repository path entered." >&2
        return 1
      fi

      repo_path_resolved="$(expand_path "$repo_path_input")"
      if [[ ! -d "$repo_path_resolved" ]]; then
        echo "Directory not found: $repo_path_resolved" >&2
        return 1
      fi

      repo_path_resolved="$(cd "$repo_path_resolved" && pwd)"
      RESOLVED_DESTINATION_ROOT="$repo_path_resolved/.codex/skills"
      return 0
      ;;
    *)
      echo "Unknown destination option." >&2
      return 1
      ;;
  esac
}

install_skill() {
  local source_dir="$1"
  local destination_root="$2"
  local skill_dir_name=""
  local destination_dir=""
  local overwrite=""

  skill_dir_name="$(basename "$source_dir")"
  destination_dir="$destination_root/$skill_dir_name"
  mkdir -p "$destination_root"

  if [[ -e "$destination_dir" ]]; then
    read -r -p "Skill already exists at $destination_dir. Overwrite? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      echo "Skipped: $skill_dir_name"
      return 1
    fi
    rm -rf "$destination_dir"
  fi

  cp -a "$source_dir" "$destination_dir"
  return 0
}

main() {
  local root_dir=""
  local repo_path_default_resolved=""
  local terminal_lines=24
  local page_size=10
  local destination_root=""
  local install_more=""
  local installed_skill_name=""
  local selected_skill_path=""
  local selected_skill_name=""
  local selected_skill_index=0
  local -a skill_paths=()
  local -a skill_labels=()
  local -a skill_names=()

  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "This script requires an interactive terminal."
    exit 1
  fi

  parse_args "$@"

  root_dir="$(expand_path "$ROOT_INPUT")"
  if [[ ! -d "$root_dir" ]]; then
    echo "Root directory not found: $root_dir"
    exit 1
  fi
  root_dir="$(cd "$root_dir" && pwd)"

  if [[ -n "$REPO_PATH_DEFAULT" ]]; then
    repo_path_default_resolved="$(expand_path "$REPO_PATH_DEFAULT")"
    if [[ ! -d "$repo_path_default_resolved" ]]; then
      echo "Default repo path not found: $repo_path_default_resolved"
      exit 1
    fi
    repo_path_default_resolved="$(cd "$repo_path_default_resolved" && pwd)"
  fi

  discover_skills "$root_dir" skill_paths skill_labels skill_names
  if (( ${#skill_paths[@]} == 0 )); then
    echo "No skills found under $root_dir"
    exit 1
  fi

  terminal_lines="$(tput lines 2>/dev/null || echo 24)"
  page_size=$((terminal_lines - 8))
  if (( page_size < 5 )); then
    page_size=5
  fi

  if ! resolve_destination_root "$repo_path_default_resolved" 6; then
    clear
    echo "Cancelled."
    exit 1
  fi
  destination_root="$RESOLVED_DESTINATION_ROOT"

  while true; do
    if ! select_from_menu "Select a skill to install (Destination: $destination_root)" skill_labels "$page_size"; then
      clear
      echo "Cancelled."
      exit 1
    fi

    selected_skill_index="$SELECTED_INDEX"
    selected_skill_path="${skill_paths[$selected_skill_index]}"
    selected_skill_name="${skill_names[$selected_skill_index]}"

    clear
    if install_skill "$selected_skill_path" "$destination_root"; then
      installed_skill_name="$(basename "$selected_skill_path")"
      echo "Installed '$selected_skill_name' to $destination_root/$installed_skill_name"
    fi

    read -r -p "Install another skill to the same destination? [y/N]: " install_more
    if [[ ! "$install_more" =~ ^[Yy]$ ]]; then
      break
    fi
  done
}

main "$@"
