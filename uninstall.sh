#!/usr/bin/env bash
# uninstall.sh — remove ONLY the skills that ship with Agent Craft.
#
# Removes ${INSTALL_DIR:-$HOME/.agent-skills}/skills/<name>/ for every <name>
# present in this pack's skills/ directory. It never touches unrelated skills.
#
# Usage:
#   ./uninstall.sh
#
# Environment:
#   INSTALL_DIR   Install root used with install.sh. Default: ~/.agent-skills
#
# Safety rules:
#   - Only the exact pack skill directories (by name) are removed.
#   - A directory is only removed if it contains a SKILL.md; anything that
#     merely shares a name but is not a skill directory is reported, not deleted.
#   - Empty parent directories are cleaned up with rmdir (never rm -rf).
#
# Exit codes:
#   0  finished (removed everything found; missing entries are reported quietly)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
INSTALL_ROOT="${INSTALL_DIR:-$HOME/.agent-skills}"
TARGET_SKILLS="$INSTALL_ROOT/skills"

if [[ ! -d "$SKILLS_SRC" ]]; then
  echo "error: skills source directory not found: $SKILLS_SRC" >&2
  exit 2
fi

removed=0
missing=0
refused=0

for skill_dir in "$SKILLS_SRC"/*/; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="$(basename "$skill_dir")"
  target_dir="$TARGET_SKILLS/$skill_name"

  if [[ ! -e "$target_dir" ]]; then
    missing=$((missing + 1))
    continue
  fi

  if [[ ! -d "$target_dir" ]]; then
    refused=$((refused + 1))
    echo "  NOT removed (not a directory): $target_dir" >&2
    continue
  fi

  if [[ ! -f "$target_dir/SKILL.md" ]]; then
    refused=$((refused + 1))
    echo "  NOT removed (no SKILL.md inside; does not look like an Agent Craft skill dir): $target_dir" >&2
    continue
  fi

  rm -rf "$target_dir"
  removed=$((removed + 1))
  echo "  removed: ${target_dir#"$INSTALL_ROOT"/}"
done

# Clean up now-empty parent directories. rmdir only succeeds on empty dirs,
# so an install root shared with other content is left untouched.
rmdir "$TARGET_SKILLS" 2>/dev/null || true
rmdir "$INSTALL_ROOT" 2>/dev/null || true

echo
echo "Skills removed: $removed"
echo "Not installed : $missing (nothing to do)"
if [[ "$refused" -gt 0 ]]; then
  echo "Refused       : $refused (see above; review manually)" >&2
fi
echo "Done."
