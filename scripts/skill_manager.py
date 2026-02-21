#!/usr/bin/env python3
"""
Interactive skill manager for this repository.

Primary use cases:
1) Install one or more skills from this repo into either:
   - User Codex home (~/.codex/skills or $CODEX_HOME/skills)
   - A repo's local .codex/skills directory
2) Import (copy/update) an external skill folder back into this repo, so changes
   can be versioned and shared.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional


REPO_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_IGNORE_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "node_modules",
}
DEFAULT_IGNORE_FILES = {
    ".DS_Store",
}


@dataclass(frozen=True)
class Skill:
    name: str
    root: Path  # directory containing SKILL.md
    rel_root: Path  # root relative to repo root
    title: str  # extracted from SKILL.md (best-effort)


def _die(msg: str, code: int = 2) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(code)


def _repo_root_from_git(cwd: Optional[Path] = None) -> Optional[Path]:
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(cwd or REPO_ROOT),
            check=True,
            capture_output=True,
            text=True,
        )
        p = Path(r.stdout.strip())
        return p if p.exists() else None
    except Exception:
        return None


def _codex_home() -> Path:
    # Mirrors common Codex conventions: $CODEX_HOME if set, else ~/.codex
    ch = os.environ.get("CODEX_HOME")
    if ch:
        return Path(ch).expanduser().resolve()
    return Path.home().joinpath(".codex").resolve()


def _read_skill_title(skill_md: Path) -> str:
    try:
        txt = skill_md.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""
    lines = txt.splitlines()

    # Skip YAML front matter if present (common in skills).
    i = 0
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and lines[i].strip() == "---":
        i += 1
        while i < len(lines) and lines[i].strip() != "---":
            i += 1
        if i < len(lines) and lines[i].strip() == "---":
            i += 1

    for line in lines[i:]:
        s = line.strip()
        if not s:
            continue
        if s.startswith("#"):
            return s.lstrip("#").strip()
        return s[:80]
    return ""


def discover_skills(repo_root: Path = REPO_ROOT) -> list[Skill]:
    skills: list[Skill] = []
    for skill_md in repo_root.rglob("SKILL.md"):
        # Skip vendored installs (repo-local .codex) and VCS dirs
        parts = set(skill_md.parts)
        if ".codex" in parts or ".git" in parts:
            continue
        skill_root = skill_md.parent
        name = skill_root.name
        title = _read_skill_title(skill_md)
        rel_root = skill_root.relative_to(repo_root)
        skills.append(Skill(name=name, root=skill_root, rel_root=rel_root, title=title))

    # Deterministic ordering: by name then path
    skills.sort(key=lambda s: (s.name.lower(), str(s.rel_root).lower()))
    return skills


def _format_skill_row(i: int, s: Skill) -> str:
    desc = f" - {s.title}" if s.title else ""
    return f"{i:>2}. {s.name} ({s.rel_root.as_posix()}){desc}"


def _parse_selection(spec: str, n_items: int) -> list[int]:
    """
    Parse "1,2,5-7" into 0-based indexes.
    """
    spec = spec.strip()
    if not spec:
        return []
    out: set[int] = set()
    for part in re.split(r"[,\s]+", spec):
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            a_i = int(a)
            b_i = int(b)
            if a_i > b_i:
                a_i, b_i = b_i, a_i
            for x in range(a_i, b_i + 1):
                out.add(x - 1)
        else:
            out.add(int(part) - 1)
    bad = [x for x in out if x < 0 or x >= n_items]
    if bad:
        _die(f"selection out of range: {', '.join(str(x+1) for x in sorted(bad))}")
    return sorted(out)


def _prompt(msg: str, default: Optional[str] = None) -> str:
    if default is None:
        p = f"{msg}: "
    else:
        p = f"{msg} [{default}]: "
    try:
        s = input(p).strip()
    except EOFError:
        return default or ""
    return s if s else (default or "")


def _prompt_choice(msg: str, choices: list[tuple[str, str]], default_key: str) -> str:
    """
    choices: list of (key, label)
    """
    print(msg)
    for k, label in choices:
        star = " *" if k == default_key else ""
        print(f"  {k}) {label}{star}")
    while True:
        ans = _prompt("Choose", default_key).lower()
        if any(ans == k for k, _ in choices):
            return ans
        print("Invalid choice.")


def _should_ignore(rel: Path) -> bool:
    if rel.name in DEFAULT_IGNORE_FILES:
        return True
    for p in rel.parts:
        if p in DEFAULT_IGNORE_DIRS:
            return True
    return False


def _copy_tree(src: Path, dst: Path, mode: str) -> None:
    """
    mode:
      - copy: fail if dst exists
      - overwrite: delete dst then copy
      - update: copy files/dirs, overwriting, but do not delete extras in dst
      - sync: mirror src into dst, deleting extras in dst (destructive)
    """
    src = src.resolve()
    dst = dst.resolve()

    if not src.exists() or not src.is_dir():
        _die(f"source is not a directory: {src}")

    if mode not in {"copy", "overwrite", "update", "sync"}:
        _die(f"unknown mode: {mode}")

    if dst.exists() and mode == "copy":
        _die(f"destination already exists: {dst}")

    if dst.exists() and mode == "overwrite":
        shutil.rmtree(dst)

    if not dst.exists():
        shutil.copytree(
            src,
            dst,
            symlinks=True,
            ignore=lambda d, names: [n for n in names if _should_ignore(Path(d).joinpath(n).relative_to(src))],
        )
        return

    # dst exists: update or sync
    # 1) ensure all src content is present/updated in dst
    for p in src.rglob("*"):
        rel = p.relative_to(src)
        if _should_ignore(rel):
            continue
        target = dst / rel
        if p.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                try:
                    if target.is_symlink() or p.is_symlink():
                        target.unlink()
                        try:
                            target.symlink_to(os.readlink(p))
                        except Exception:
                            # If symlinks aren't supported, fall back to copying bytes.
                            shutil.copy2(p, target)
                    else:
                        shutil.copy2(p, target)
                except Exception:
                    # Windows/WSL symlink edge cases: fall back to copying bytes
                    shutil.copy2(p, target)
            else:
                if p.is_symlink():
                    try:
                        target.symlink_to(os.readlink(p))
                    except Exception:
                        shutil.copy2(p, target)
                else:
                    shutil.copy2(p, target)

    if mode != "sync":
        return

    # 2) delete extras in dst not present in src
    # Walk bottom-up so we can remove empty dirs.
    for p in sorted(dst.rglob("*"), key=lambda x: len(x.parts), reverse=True):
        rel = p.relative_to(dst)
        if _should_ignore(rel):
            continue
        if not (src / rel).exists():
            if p.is_dir():
                try:
                    p.rmdir()
                except OSError:
                    pass
            else:
                p.unlink(missing_ok=True)


def _pick_repo_categories(repo_root: Path) -> list[str]:
    out: list[str] = []
    for p in repo_root.iterdir():
        if not p.is_dir():
            continue
        if p.name.startswith("."):
            continue
        if p.name in {"scripts"}:
            continue
        out.append(p.name)
    out.sort()
    return out


def _normalize_skill_src(path: Path) -> Path:
    # Accept either a skill directory or a direct SKILL.md path.
    p = path.expanduser().resolve()
    if p.is_file() and p.name == "SKILL.md":
        return p.parent
    return p


def cmd_list(args: argparse.Namespace) -> int:
    skills = discover_skills(REPO_ROOT)
    if not skills:
        print("No skills found (no SKILL.md files discovered).")
        return 0
    for i, s in enumerate(skills, 1):
        print(_format_skill_row(i, s))
    return 0


def _select_skills_interactive(skills: list[Skill]) -> list[Skill]:
    if not skills:
        _die("no skills found in this repo (no SKILL.md files discovered)")

    print("Available skills:")
    for i, s in enumerate(skills, 1):
        print(_format_skill_row(i, s))

    while True:
        sel = _prompt("Select skill(s) by number (e.g. 1,3-5)")
        try:
            idxs = _parse_selection(sel, len(skills))
        except ValueError:
            print("Invalid selection; try again.")
            continue
        if not idxs:
            print("No skills selected; try again.")
            continue
        return [skills[i] for i in idxs]


def cmd_install(args: argparse.Namespace) -> int:
    skills = discover_skills(REPO_ROOT)

    if args.interactive:
        selected = _select_skills_interactive(skills)
    else:
        # Non-interactive: select by name or rel path
        want = set(args.skills or [])
        if not want:
            _die("no skills specified; pass skill names/paths or use --interactive")
        selected = []
        for s in skills:
            if s.name in want or s.rel_root.as_posix() in want:
                selected.append(s)
        missing = [w for w in want if w not in {s.name for s in selected} and w not in {s.rel_root.as_posix() for s in selected}]
        if missing:
            _die(f"unknown skill(s): {', '.join(missing)}")

    if args.dest == "user":
        base = _codex_home() / "skills"
    elif args.dest == "repo":
        rr = _repo_root_from_git(REPO_ROOT) or REPO_ROOT
        base = rr / ".codex" / "skills"
    else:
        base = Path(args.dest).expanduser().resolve()

    base.mkdir(parents=True, exist_ok=True)

    mode = args.mode
    for s in selected:
        target = base / s.name
        print(f"- {s.name}: {s.rel_root.as_posix()} -> {target}")
        _copy_tree(s.root, target, mode=mode)

    print(f"Installed {len(selected)} skill(s) into {base}")
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    src_root = _normalize_skill_src(Path(args.source))
    if not src_root.exists() or not src_root.is_dir():
        _die(f"source skill directory not found: {src_root}")
    if not src_root.joinpath("SKILL.md").exists():
        _die(f"source does not look like a skill folder (missing SKILL.md): {src_root}")

    skill_name = args.name or src_root.name

    if args.category:
        category = args.category
    elif not args.interactive:
        # Non-interactive convenience: if the skill already exists in this repo
        # uniquely by name, update it in-place (keeps existing category path).
        matches = [s for s in discover_skills(REPO_ROOT) if s.name == skill_name]
        if len(matches) == 1:
            category = matches[0].rel_root.parts[0] if matches[0].rel_root.parts else ""
        else:
            _die("missing --category (or use --interactive)")
    else:
        cats = _pick_repo_categories(REPO_ROOT)
        print("Target category (top-level folder in this repo):")
        for i, c in enumerate(cats, 1):
            print(f"{i:>2}. {c}")
        print(f"{len(cats)+1:>2}. (new) create a new category folder")
        while True:
            raw = _prompt("Choose category number", "1")
            try:
                n = int(raw)
            except ValueError:
                print("Invalid number.")
                continue
            if 1 <= n <= len(cats):
                category = cats[n - 1]
                break
            if n == len(cats) + 1:
                category = _prompt("New category folder name")
                if category:
                    break
                print("Category cannot be empty.")
                continue
            print("Out of range.")
    if not category:
        _die("could not determine category")

    dest_root = REPO_ROOT / category / skill_name
    dest_root.parent.mkdir(parents=True, exist_ok=True)

    mode = args.mode
    print(f"- import {skill_name}: {src_root} -> {dest_root} (mode={mode})")
    _copy_tree(src_root, dest_root, mode=mode)
    print(f"Imported skill into {dest_root.relative_to(REPO_ROOT).as_posix()}")
    return 0


def run_interactive() -> int:
    top = _prompt_choice(
        "What do you want to do?",
        choices=[
            ("1", "Install skill(s) from this repo into a Codex skills directory"),
            ("2", "Import/update a skill folder into this repo"),
            ("3", "List skills discovered in this repo"),
            ("q", "Quit"),
        ],
        default_key="1",
    )

    if top == "q":
        return 0

    if top == "3":
        return cmd_list(argparse.Namespace())

    if top == "1":
        mode = _prompt_choice(
            "Install mode (what to do if destination already exists)?",
            choices=[
                ("update", "Update: overwrite matching files; keep extra destination files"),
                ("copy", "Copy: fail if destination exists"),
                ("overwrite", "Overwrite: delete destination then copy"),
                ("sync", "Sync: mirror source into destination; delete extras (destructive)"),
            ],
            default_key="update",
        )
        dest = _prompt_choice(
            "Install destination",
            choices=[
                ("user", f"User: {_codex_home() / 'skills'}"),
                ("repo", "Repo: <git-root>/.codex/skills"),
                ("custom", "Custom: provide a path"),
            ],
            default_key="user",
        )
        if dest == "custom":
            dest_path = _prompt("Custom destination path")
        else:
            dest_path = dest
        args = argparse.Namespace(interactive=True, skills=None, dest=dest_path, mode=mode)
        return cmd_install(args)

    # top == "2"
    mode = _prompt_choice(
        "Import mode (what to do if destination already exists)?",
        choices=[
            ("update", "Update: overwrite matching files; keep extra destination files"),
            ("copy", "Copy: fail if destination exists"),
            ("overwrite", "Overwrite: delete destination then copy"),
            ("sync", "Sync: mirror source into destination; delete extras (destructive)"),
        ],
        default_key="update",
    )
    source = _prompt("Path to skill folder (or SKILL.md)")
    name = _prompt("Skill name override (optional)", "")
    args = argparse.Namespace(
        interactive=True,
        source=source,
        name=(name or None),
        category=None,
        mode=mode,
    )
    return cmd_import(args)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="skill_manager.py",
        description="Manage Codex skills: install from this repo, or import skills back into this repo.",
    )
    p.add_argument(
        "--interactive",
        action="store_true",
        help="Run in interactive mode (menu + prompts). If no subcommand is given, interactive is implied.",
    )

    sub = p.add_subparsers(dest="cmd")

    sp_list = sub.add_parser("list", help="List skills discovered in this repo.")
    sp_list.set_defaults(func=cmd_list)

    sp_install = sub.add_parser("install", help="Install skill(s) from this repo into a destination skills directory.")
    sp_install.add_argument("skills", nargs="*", help="Skill name(s) or relative skill path(s) like github/gh-commit-and-push")
    sp_install.add_argument(
        "--dest",
        default="user",
        help="Destination: 'user' (~/.codex/skills or $CODEX_HOME/skills), 'repo' (<git-root>/.codex/skills), or an explicit path",
    )
    sp_install.add_argument(
        "--mode",
        default="update",
        choices=["copy", "overwrite", "update", "sync"],
        help="How to handle existing destination folders (default: update).",
    )
    sp_install.set_defaults(func=cmd_install)

    sp_import = sub.add_parser("import", help="Import/update an external skill folder into this repo.")
    sp_import.add_argument("source", help="Path to a skill folder (must contain SKILL.md) or to SKILL.md itself.")
    sp_import.add_argument("--name", help="Override skill folder name in this repo (default: source folder name).")
    sp_import.add_argument("--category", help="Target top-level category folder in this repo (e.g. github, personal).")
    sp_import.add_argument(
        "--mode",
        default="update",
        choices=["copy", "overwrite", "update", "sync"],
        help="How to handle existing destination folders (default: update).",
    )
    sp_import.set_defaults(func=cmd_import)

    return p


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.cmd is None:
        return run_interactive()

    if getattr(args, "interactive", False):
        # For subcommands, --interactive means selection prompts where applicable.
        if args.cmd == "install":
            args.interactive = True
        if args.cmd == "import":
            args.interactive = True

    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
