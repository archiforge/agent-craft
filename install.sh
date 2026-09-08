#!/usr/bin/env bash
# install.sh — install Agent Craft skills into a target directory.
#
# Copies every skills/<name>/ directory shipped with this pack into
# ${INSTALL_DIR:-$HOME/.agent-skills}/skills/.
#
# Usage:
#   ./install.sh [--force]
#
# Environment:
#   INSTALL_DIR   Target root directory. Default: ~/.agent-skills
#                 Skills land in: $INSTALL_DIR/skills/<name>/
#
# Behavior:
#   - Creates target directories as needed.
#   - New files are copied as-is.
#   - Existing identical files are skipped (idempotent re-runs).
#   - Existing DIFFERING files are refused by default.
#       With --force, the existing file is first backed up to
#       <file>.bak.TIMESTAMP and then replaced.
#
# Exit codes:
#   0  success (possibly with skips)
#   1  one or more collisions were refused (re-run with --force)
#   2  usage or environment error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
INSTALL_ROOT="${INSTALL_DIR:-$HOME/.agent-skills}"
FORCE=0
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force]

Installs Agent Craft skills into ${INSTALL_DIR:-$HOME/.agent-skills}/skills/.

Options:
  --force     Back up (.bak.TIMESTAMP) and overwrite files that differ.
  -h, --help  Show this help.

Environment:
  INSTALL_DIR  Override the install root (default: ~/.agent-skills).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "error: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "error: skills source directory not found: $SKILLS_SRC" >&2
  exit 2
fi

if ! command -v find >/dev/null 2>&1 || ! command -v cmp >/dev/null 2>&1; then
  echo "error: this script requires 'find' and 'cmp' (standard Unix tools)." >&2
  exit 2
fi

TARGET_SKILLS="$INSTALL_ROOT/skills"
mkdir -p "$TARGET_SKILLS"

copied=0
skipped=0
backed_up=0
conflicts=0

for skill_dir in "$SKILLS_SRC"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  target_dir="$TARGET_SKILLS/$skill_name"
  mkdir -p "$target_dir"

  while IFS= read -r -d '' src_file; do
    rel="${src_file#"$skill_dir"}"
    dest="$target_dir/$rel"
    dest_parent="$(dirname "$dest")"
    [[ -d "$dest_parent" ]] || mkdir -p "$dest_parent"

    if [[ -e "$dest" ]]; then
      if cmp -s "$src_file" "$dest"; then
        skipped=$((skipped + 1))
        echo "  skip (identical): ${dest#"$INSTALL_ROOT"/}"
        continue
      fi
      if [[ "$FORCE" -eq 1 ]]; then
        backup="${dest}.bak.$TIMESTAMP"
        cp -p "$dest" "$backup"
        cp "$src_file" "$dest"
        backed_up=$((backed_up + 1))
        copied=$((copied + 1))
        echo "  replaced:          ${dest#"$INSTALL_ROOT"/}"
        echo "    backup:          ${backup#"$INSTALL_ROOT"/}"
      else
        conflicts=$((conflicts + 1))
        echo "  CONFLICT (kept):   ${dest#"$INSTALL_ROOT"/}" >&2
        echo "    differs from pack version; re-run with --force to back it up and replace." >&2
      fi
    else
      cp "$src_file" "$dest"
      copied=$((copied + 1))
      echo "  installed:         ${dest#"$INSTALL_ROOT"/}"
    fi
  done < <(find "$skill_dir" -type f -print0)
done

echo
echo "Install root : $INSTALL_ROOT"
echo "Skills found : $(find "$SKILLS_SRC" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
echo "Files copied : $copied"
echo "Files skipped: $skipped (already identical)"
if [[ "$backed_up" -gt 0 ]]; then
  echo "Backups made : $backed_up (.bak.$TIMESTAMP)"
fi

if [[ "$conflicts" -gt 0 ]]; then
  echo
  echo "REFUSED: $conflicts file(s) differ from the pack version and were NOT overwritten." >&2
  echo "Re-run with --force to back them up (.bak.$TIMESTAMP) and replace them." >&2
  exit 1
fi

echo "Done."
