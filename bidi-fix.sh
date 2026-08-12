#!/usr/bin/env bash
# opencode-desktop-bidi-fix
#
# Fixes Arabic/English text direction (bidi) in the OpenCode desktop app:
#   - chat messages (user + assistant/markdown) render RTL when starting with Arabic
#   - the composer starts typing from the right for Arabic input
#
# Idempotent and reversible. Works on Linux, macOS, and Windows.
#
# Usage:
#   ./bidi-fix.sh                 # apply the fix
#   ./bidi-fix.sh --check         # check whether the fix is applied
#   ./bidi-fix.sh --uninstall     # restore the original app.asar
#   ./bidi-fix.sh --force         # re-apply even if already applied
#
set -euo pipefail

MARKER='bidi fix: Arabic+English mixed text renders correctly'
CSS_RULES='[data-component="markdown"] p,[data-component="markdown"] li,[data-component="markdown"] h1,[data-component="markdown"] h2,[data-component="markdown"] h3,[data-component="markdown"] h4,[data-component="markdown"] h5,[data-component="markdown"] h6,[data-component="markdown"] blockquote,[data-component="markdown"] td,[data-component="markdown"] th{unicode-bidi:plaintext;text-align:start}
[data-component="user-message"] [data-slot="user-message-text"]{unicode-bidi:plaintext;text-align:start}
[data-component="prompt-input"] [contenteditable]{unicode-bidi:plaintext;text-align:start}'

# ---------------------------------------------------------------- paths
find_asar() {
  # returns path to app.asar, or empty
  local c
  for c in \
    "/opt/OpenCode/resources/app.asar" \
    "/Applications/OpenCode.app/Contents/Resources/app.asar" \
    "${LOCALAPPDATA:-}/Programs/opencode/resources/app.asar" \
    "${LOCALAPPDATA:-}/Programs/OpenCode/resources/app.asar" \
    "/usr/lib/opencode/resources/app.asar" \
    "/usr/local/lib/opencode/resources/app.asar"; do
    if [ -f "$c" ]; then echo "$c"; return 0; fi
  done
  # also try `which opencode`-adjacent resources
  local bin
  bin=$(command -v ai.opencode.desktop 2>/dev/null || command -v opencode 2>/dev/null || true)
  if [ -n "$bin" ]; then
    local dir
    dir=$(dirname "$(readlink -f "$bin" 2>/dev/null || echo "$bin")")
    for c in \
      "$dir/resources/app.asar" \
      "$(dirname "$dir")/resources/app.asar" \
      "$(dirname "$(dirname "$dir")")/resources/app.asar"; do
      if [ -f "$c" ]; then echo "$c"; return 0; fi
    done
  fi
  return 1
}

backup_path() {
  local asar="$1"
  echo "$HOME/.cache/opencode-desktop-bidi-fix/$(echo "$asar" | md5sum | cut -d' ' -f1).asar"
}

# ---------------------------------------------------------------- helpers
die() { echo "ERROR: $*" >&2; exit 1; }

need_tool() {
  command -v npx >/dev/null 2>&1 || die "npx not found. Install Node.js (https://nodejs.org) or run from a machine that has it."
}

asar_cmd() {
  npx --yes @electron/asar "$@" 2>/dev/null
}

need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  else
    command -v sudo >/dev/null 2>&1 || die "sudo not found and not running as root."
    echo "sudo"
  fi
}

run_as_root() {
  local sudo_bin=$1; shift
  if [ -n "$sudo_bin" ]; then "$sudo_bin" "$@"; else "$@"; fi
}

# ---------------------------------------------------------------- core
apply_fix() {
  need_tool
  local asar css_dir css_file patched tmp backup sudo_bin force=0
  force="${1:-0}"

  asar=$(find_asar) || die "OpenCode desktop app.asar not found. Install OpenCode desktop first."
  sudo_bin=$(need_sudo)

  backup=$(backup_path "$asar")
  mkdir -p "$(dirname "$backup")"

  tmp=$(mktemp -d)
  trap 'rm -rf "${tmp:-}"' EXIT

  echo "Extracting $asar ..."
  asar_cmd extract "$asar" "$tmp/app" || die "failed to extract app.asar"

  css_dir="$tmp/app/out/renderer/assets"
  [ -d "$css_dir" ] || die "renderer assets not found in app.asar (structure changed?)"

  css_file=""
  # prefer the big main stylesheet; fall back to any css that mentions markdown
  local f
  for f in "$css_dir"/main-*.css "$css_dir"/index-*.css; do
    [ -f "$f" ] || continue
    if grep -q "data-component=\"markdown\"\|--markdown-heading" "$f" 2>/dev/null; then
      css_file="$f"; break
    fi
  done
  if [ -z "$css_file" ]; then
    css_file=$(ls -S "$css_dir"/*.css 2>/dev/null | head -1 || true)
  fi
  [ -n "$css_file" ] || die "no stylesheet found in app.asar (structure changed?)"

  if grep -qF "$MARKER" "$css_file"; then
    if [ "$force" -eq 0 ]; then
      echo "bidi fix: already applied → $(basename "$css_file")"
      rm -rf "$tmp"
      trap - EXIT
      return 0
    fi
    echo "bidi fix: removing old rules, re-applying (--force)"
    # strip previously appended blocks so a re-run never duplicates rules.
    # matches one or more consecutive blocks (marker comment + rule lines) and
    # any stray broken rule tails left by older manual patches.
    python3 - "$css_file" <<'EOF'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
block = re.compile(
    r'\n?/\* bidi fix: Arabic\+English mixed text renders correctly[^\n]*\*/\n'
    r'(?:\[data-component[^\n]*\n)*'
)
s = block.sub('', s)
s = re.sub(r'\n?\[data-component="[^"\n]*"[^\n]*\n', '', s)
open(p, 'w', encoding='utf-8').write(s)
EOF
  fi

  # backup the pristine asar only once
  if [ ! -f "$backup" ]; then
    cp "$asar" "$backup"
    echo "Backup saved: $backup"
  fi

  echo "Patching $(basename "$css_file") ..."
  {
    printf '\n/* %s */\n' "$MARKER"
    printf '%s\n' "$CSS_RULES"
  } >> "$css_file"

  patched="$tmp/app.asar"
  echo "Repacking app.asar ..."
  asar_cmd pack "$tmp/app" "$patched" || die "failed to repack app.asar"

  echo "Installing (this may ask for your password) ..."
  run_as_root "$sudo_bin" cp "$patched" "$asar"
  echo "Done. Restart the OpenCode desktop app."
}

check_fix() {
  local asar tmp css
  asar=$(find_asar) || die "OpenCode desktop app.asar not found."
  tmp=$(mktemp -d)
  trap 'rm -rf "${tmp:-}"' EXIT
  asar_cmd extract "$asar" "$tmp/app" 2>/dev/null || die "extract failed"
  css=$(ls -S "$tmp/app/out/renderer/assets"/*.css 2>/dev/null | head -1)
  if grep -qF "$MARKER" "$css" 2>/dev/null; then
    echo "✓ bidi fix is APPLIED"
  else
    echo "✗ bidi fix is NOT applied"
  fi
}

uninstall_fix() {
  need_tool
  local asar backup sudo_bin
  asar=$(find_asar) || die "OpenCode desktop app.asar not found."
  backup=$(backup_path "$asar")
  if [ ! -f "$backup" ]; then
    echo "No backup found — cannot uninstall (fix may never have been applied here)."
    return 1
  fi
  sudo_bin=$(need_sudo)
  echo "Restoring original app.asar ..."
  run_as_root "$sudo_bin" cp "$backup" "$asar"
  echo "Done. Original app.asar restored."
}

# ---------------------------------------------------------------- main
case "${1:-apply}" in
  --check|-c)   need_tool; check_fix ;;
  --uninstall|-u) uninstall_fix ;;
  --force|-f)   apply_fix 1 ;;
  --help|-h|help) sed -n '2,14p' "$0" ;;
  apply|"")     apply_fix 0 ;;
  *)            echo "Unknown option: $1"; sed -n '2,14p' "$0"; exit 1 ;;
esac
