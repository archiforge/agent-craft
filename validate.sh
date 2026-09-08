#!/usr/bin/env bash
# validate.sh — CI-style structural validator for Agent Craft skills.
#
# Verifies that every skills/<name>/SKILL.md under a skills root:
#   1. has a valid YAML frontmatter block (opening and closing '---' fences,
#      containing 'name:' and 'description:' keys),
#   2. 'name' is kebab-case AND matches its parent directory name,
#   3. 'description' is a single line of at most 200 characters,
#   4. contains an H1 title and the required sections:
#      "When to use", "Protocol", "Checklist", "Anti-patterns".
#
# Usage:
#   ./validate.sh [skills-root]
#
#   skills-root defaults to the 'skills/' directory next to this script
#   (the free pack). Pass a path to validate another tree, e.g.:
#
#       ./validate.sh ../pro/skills
#
#   Relative paths are resolved against the current working directory.
#
# Exit codes:
#   0  all skills valid (PASS summary printed)
#   1  one or more skills failed (per-file report printed)
#   2  environment error (missing/empty skills root)
#
# Dependencies: bash, grep, awk, sed, find — standard Unix tools only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${1:-$SCRIPT_DIR/skills}"

# Resolve relative paths against the caller's working directory.
case "$SKILLS_ROOT" in
  /*) : ;;
  *)  SKILLS_ROOT="$PWD/$SKILLS_ROOT" ;;
esac

if [[ ! -d "$SKILLS_ROOT" ]]; then
  echo "error: skills root not found: $SKILLS_ROOT" >&2
  exit 2
fi

MAX_DESCRIPTION=200
REQUIRED_SECTIONS="When to use|Protocol|Checklist|Anti-patterns"

total=0
failed=0

report_fail() {
  # report_fail <file> <message>  — print in the per-file report later
  FAILURES="${FAILURES:-}FAIL: $1
  - $2
"
}

for skill_dir in "$SKILLS_ROOT"/*/; do
  [[ -d "$skill_dir" ]] || continue
  total=$((total + 1))
  skill_name="$(basename "$skill_dir")"
  file="$skill_dir/SKILL.md"
  FAILURES=""

  if [[ ! -f "$file" ]]; then
    report_fail "$skill_name/SKILL.md" "missing: SKILL.md not found in skill directory"
    echo "$FAILURES"
    failed=$((failed + 1))
    continue
  fi

  # ---- 1. Frontmatter block -------------------------------------------------
  first_line="$(sed -n '1p' "$file")"
  if [[ "$first_line" != "---" ]]; then
    report_fail "$skill_name/SKILL.md" "frontmatter: file must start with a '---' line (got: '$first_line')"
  fi

  closing_line="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")"
  if [[ -z "$closing_line" ]]; then
    report_fail "$skill_name/SKILL.md" "frontmatter: no closing '---' fence found"
  elif [[ "$closing_line" -gt 30 ]]; then
    report_fail "$skill_name/SKILL.md" "frontmatter: closing '---' fence at line $closing_line (expected within the first 30 lines)"
  fi

  # Extract the frontmatter block (between the fences) when it is well-formed.
  fm=""
  if [[ "$first_line" == "---" && -n "$closing_line" && "$closing_line" -le 30 ]]; then
    fm="$(sed -n "2,$((closing_line - 1))p" "$file")"
  fi
  if [[ -n "$first_line" && "$first_line" == "---" && -n "$closing_line" && "$closing_line" -le 30 && -z "$fm" ]]; then
    report_fail "$skill_name/SKILL.md" "frontmatter: block is empty (no YAML keys between the fences)"
  fi

  # ---- 2. name key -----------------------------------------------------------
  name_val=""
  if [[ -n "$fm" ]]; then
    name_line="$(printf '%s\n' "$fm" | grep -E '^name:[[:space:]]*[^[:space:]]' | sed -n '1p' || true)"
    if [[ -z "$name_line" ]]; then
      report_fail "$skill_name/SKILL.md" "frontmatter: required key 'name:' is missing or has no value"
    else
      name_val="$(printf '%s' "$name_line" | sed -E 's/^name:[[:space:]]*//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' | sed -E 's/[[:space:]]+$//')"
      if [[ "$name_val" != "$skill_name" ]]; then
        report_fail "$skill_name/SKILL.md" "name mismatch: frontmatter name '$name_val' does not match directory '$skill_name'"
      fi
      if ! printf '%s' "$name_val" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
        report_fail "$skill_name/SKILL.md" "name format: '$name_val' is not kebab-case (lowercase alphanumerics joined by single hyphens)"
      fi
    fi
  fi

  # ---- 3. description key ----------------------------------------------------
  if [[ -n "$fm" ]]; then
    desc_line="$(printf '%s\n' "$fm" | grep -E '^description:[[:space:]]*\S' | sed -n '1p' || true)"
    if [[ -z "$desc_line" ]]; then
      report_fail "$skill_name/SKILL.md" "frontmatter: required key 'description:' is missing or empty (a one-line 'when to use this' sentence is required)"
    else
      desc_val="$(printf '%s' "$desc_line" | sed -E 's/^description:[[:space:]]*//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
      desc_len=${#desc_val}
      if [[ "$desc_len" -gt "$MAX_DESCRIPTION" ]]; then
        report_fail "$skill_name/SKILL.md" "description too long: $desc_len characters (max $MAX_DESCRIPTION)"
      fi
      if printf '%s' "$fm" | grep -Eq '^description:.*(\||>)'; then
        report_fail "$skill_name/SKILL.md" "description must be a single line (no folded '|' or block '>' scalars)"
      fi
    fi
  fi

  # ---- 4. H1 title -------------------------------------------------------------
  if ! grep -Eq '^# [^[:space:]].*' "$file"; then
    report_fail "$skill_name/SKILL.md" "structure: missing H1 title ('# ...' line)"
  fi

  # ---- 5. Required sections -----------------------------------------------------
  section="$REQUIRED_SECTIONS"
  oldIFS="$IFS"
  IFS='|'
  for required in $section; do
    if ! grep -Eiq "^#{2,6}[[:space:]]+.*${required}" "$file"; then
      report_fail "$skill_name/SKILL.md" "structure: missing required section '${required}'"
    fi
  done
  IFS="$oldIFS"

  if [[ -n "$FAILURES" ]]; then
    echo "$FAILURES"
    failed=$((failed + 1))
  fi
done

if [[ "$total" -eq 0 ]]; then
  echo "error: no skill directories found under: $SKILLS_ROOT" >&2
  exit 2
fi

echo "-------------------------------------------------------------------------------"
if [[ "$failed" -gt 0 ]]; then
  echo "FAIL: $failed of $total skill(s) invalid in $SKILLS_ROOT"
  exit 1
fi
echo "PASS: $total skill(s) valid in $SKILLS_ROOT"
echo "       frontmatter OK, name matches directory, description <= $MAX_DESCRIPTION chars,"
echo "       H1 title present, all required sections present."
exit 0
