#!/usr/bin/env bash
# install.sh — install Agent Craft skills into a target directory.
#
# Copies every skills/<name>/ directory shipped with this pack into
# $INSTALL_DIR/skills/.
#
# Usage:
#   ./install.sh [--force]
#   curl -fsSL https://raw.githubusercontent.com/mohamed-bashir-dev/agent-craft/main/install.sh | bash
#
# Environment:
#   INSTALL_DIR   Target root directory. When unset, the target is
#                 auto-detected: the first existing of ~/.claude,
#                 ~/.agents, ~/.codex wins; if none exist, ~/.agent-skills
#                 is used. Skills land in: $INSTALL_DIR/skills/<name>/
#
# Behavior:
#   - Piped invocation (curl ... | bash) cannot resolve a local skills/
#     tree, so the script downloads the repo tarball from github.com over
#     HTTPS, extracts it to a temporary directory, and re-runs the
#     installer from the extracted copy with the same arguments and
#     environment. The temporary directory is removed on exit.
#   - Creates target directories as needed.
#   - New files are copied as-is.
#   - Existing identical files are skipped (idempotent re-runs).
#   - Existing DIFFERING files are refused by default.
#       With --force, the existing file is first backed up to
#       <file>.bak.TIMESTAMP and then replaced.
#   - When INSTALL_DIR is unset, logs the auto-detected target and how to
#     override it.
#
# Exit codes:
#   0  success (possibly with skips)
#   1  one or more collisions were refused (re-run with --force)
#   2  usage or environment error (including a failed piped-mode download)

set -euo pipefail

# Fixed public snapshot URL for piped installs. Never built from user input.
REPO_TARBALL_URL="https://github.com/mohamed-bashir-dev/agent-craft/archive/refs/heads/main.tar.gz"

# --- Piped invocation (curl ... | bash) -------------------------------------
# When the script text arrives on stdin, BASH_SOURCE[0] is unset; when it
# arrives through process substitution, it names a pipe descriptor instead of
# a regular file. Either way there is no local checkout to install from, so
# fetch the repo snapshot and re-run from it.
piped=0
if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
  piped=1
elif [[ ! -f "${BASH_SOURCE[0]}" && ! -t 0 ]]; then
  piped=1
fi

if [[ "$piped" -eq 1 ]]; then
  # Sanity-check the constant before fetching: HTTPS scheme, host exactly
  # github.com. Guards against the URL above ever being edited into
  # something untrusted.
  url_host="${REPO_TARBALL_URL#https://}"
  url_host="${url_host%%/*}"
  if [[ "$REPO_TARBALL_URL" != https://* || "$url_host" != "github.com" ]]; then
    echo "error: refusing to fetch snapshot from a non-github.com URL: $REPO_TARBALL_URL" >&2
    exit 2
  fi
  if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    echo "error: piped install requires 'curl' and 'tar'; clone the repo and run ./install.sh instead." >&2
    exit 2
  fi

  echo "Piped install: fetching repo snapshot from $url_host ..."
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  if ! curl -fsSL "$REPO_TARBALL_URL" -o "$TMP_DIR/repo.tar.gz"; then
    echo "error: download failed: $REPO_TARBALL_URL" >&2
    echo "       clone the repo and run ./install.sh instead." >&2
    exit 2
  fi
  if ! tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"; then
    echo "error: failed to extract repo tarball." >&2
    exit 2
  fi

  # The GitHub tarball unpacks to a single top-level directory
  # (agent-craft-main/); take the first directory found.
  SRC_DIR=""
  for entry in "$TMP_DIR"/*/; do
    [[ -d "$entry" ]] || continue
    SRC_DIR="${entry%/}"
    break
  done
  if [[ -z "$SRC_DIR" || ! -f "$SRC_DIR/install.sh" ]]; then
    echo "error: repo snapshot does not contain the installer." >&2
    exit 2
  fi

  # Run the real installer from the extracted copy with the same arguments
  # and environment; propagate its exit code (the EXIT trap removes TMP_DIR).
  rc=0
  "${BASH:-bash}" "$SRC_DIR/install.sh" "$@" || rc=$?
  exit "$rc"
fi

# --- Normal invocation (from a clone or checkout) ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/skills"
FORCE=0
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# detect_install_root — echo the default target root: first existing of
# ~/.claude, ~/.agents, ~/.codex wins; otherwise echo ~/.agent-skills and
# return 1 so callers can word their log line accordingly.
# Duplicated verbatim in uninstall.sh (each script stays self-contained).
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

usage() {
  cat <<'EOF'
Usage: ./install.sh [--force]
       curl -fsSL https://raw.githubusercontent.com/mohamed-bashir-dev/agent-craft/main/install.sh | bash

Installs Agent Craft skills into $INSTALL_DIR/skills/.

Options:
  --force     Back up (.bak.TIMESTAMP) and overwrite files that differ.
  -h, --help  Show this help.

Environment:
  INSTALL_DIR  Override the install root. When unset, the first existing
               of these wins: ~/.claude, ~/.agents, ~/.codex; if none of
               them exist, the default ~/.agent-skills is used.
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

# Install root: an explicit INSTALL_DIR wins; otherwise auto-detect the
# first known agent home that exists, falling back to ~/.agent-skills.
if [[ -n "${INSTALL_DIR:-}" ]]; then
  INSTALL_ROOT="$INSTALL_DIR"
elif INSTALL_ROOT="$(detect_install_root)"; then
  echo "Install target: $INSTALL_ROOT (auto-detected; set INSTALL_DIR=/path to override)"
else
  echo "Install target: $INSTALL_ROOT (default; no ~/.claude, ~/.agents or ~/.codex found — set INSTALL_DIR=/path to override)"
fi

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
