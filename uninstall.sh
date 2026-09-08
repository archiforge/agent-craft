#!/usr/bin/env bash
# uninstall.sh — remove ONLY the skills that ship with Agent Craft.
#
# Removes $INSTALL_DIR/skills/<name>/ for every <name> present in this
# pack's skills/ directory. It never touches unrelated skills.
#
# Usage:
#   ./uninstall.sh
#
# Environment:
#   INSTALL_DIR   Install root used with install.sh. When unset, the
#                 target is auto-detected exactly like install.sh does:
#                 first existing of ~/.claude, ~/.agents, ~/.codex wins;
#                 if none exist, ~/.agent-skills is used.
#
# Behavior:
#   - When INSTALL_DIR is unset, logs the auto-detected target and how to
#     override it (same detection order as install.sh).
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

# detect_install_root — echo the default target root: first existing of
# ~/.claude, ~/.agents, ~/.codex wins; otherwise echo ~/.agent-skills and
# return 1 so callers can word their log line accordingly.
# Duplicated verbatim in install.sh (each script stays self-contained).
detect_install_root() {
  local candidate
  for candidate in "$HOME/.claude" "$HOME/.agents" "$HOME/.codex"; do
    if [[ -d "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  echo "$HOME/.agent-skills"
  return 1
}

# Uninstall root: an explicit INSTALL_DIR wins; otherwise auto-detect the
# same target install.sh would choose, falling back to ~/.agent-skills.
if [[ -n "${INSTALL_DIR:-}" ]]; then
  INSTALL_ROOT="$INSTALL_DIR"
elif INSTALL_ROOT="$(detect_install_root)"; then
  echo "Uninstall target: $INSTALL_ROOT (auto-detected; set INSTALL_DIR=/path to override)"
else
  echo "Uninstall target: $INSTALL_ROOT (default; no ~/.claude, ~/.agents or ~/.codex found — set INSTALL_DIR=/path to override)"
fi

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
