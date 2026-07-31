#!/usr/bin/env bash
# Symlink ReaProfessor scripts/theme/extension into the REAPER resource path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCE="${REAPER_RESOURCE:-$HOME/.config/REAPER}"

mkdir -p "$RESOURCE/Scripts" "$RESOURCE/ColorThemes" "$RESOURCE/OSC" "$RESOURCE/UserPlugins"

link_path() {
  local src="$1" dst="$2"
  if [[ -L "$dst" || -e "$dst" ]]; then
    rm -rf "$dst"
  fi
  ln -sfn "$src" "$dst"
  echo "linked $dst -> $src"
}

link_path "$REPO_ROOT/scripts/ReaProfessor" "$RESOURCE/Scripts/ReaProfessor"
link_path "$REPO_ROOT/theme/ReaProfessor.ReaperTheme" "$RESOURCE/ColorThemes/ReaProfessor.ReaperTheme"
link_path "$REPO_ROOT/theme/ReaProfessor" "$RESOURCE/ColorThemes/ReaProfessor"
link_path "$REPO_ROOT/resources/osc/ReaProfessor.ReaperOSC" "$RESOURCE/OSC/ReaProfessor.ReaperOSC"

# Native Extensions menu extension (hookcustommenu — does not touch reaper-menu.ini)
install_native() {
  local src="" dst=""
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64|Linux-amd64)
      src="$REPO_ROOT/dist/linux64/reaper_reaprofessor-x86_64.so"
      dst="$RESOURCE/UserPlugins/reaper_reaprofessor-x86_64.so"
      if [[ ! -f "$src" ]]; then
        make -C "$REPO_ROOT/native" OS=Linux || true
      fi
      ;;
    Darwin-arm64)
      src="$REPO_ROOT/dist/darwin-arm64/reaper_reaprofessor.dylib"
      dst="$RESOURCE/UserPlugins/reaper_reaprofessor.dylib"
      if [[ ! -f "$src" ]]; then
        make -C "$REPO_ROOT/native" OS=Darwin || true
      fi
      ;;
    Darwin-x86_64)
      src="$REPO_ROOT/dist/darwin64/reaper_reaprofessor.dylib"
      dst="$RESOURCE/UserPlugins/reaper_reaprofessor.dylib"
      if [[ ! -f "$src" ]]; then
        make -C "$REPO_ROOT/native" OS=Darwin || true
      fi
      ;;
    *)
      echo "No prebuilt native extension for $(uname -s)-$(uname -m); build with native/Makefile"
      return 0
      ;;
  esac
  if [[ -f "$src" ]]; then
    cp -f "$src" "$dst"
    echo "installed native extension -> $dst"
  else
    echo "WARNING: native extension missing at $src (Extensions menu entry needs it)"
  fi
}
install_native

# Drop any legacy [Main extensions] hijack from older ReaProfessor versions.
if [[ -f "$RESOURCE/reaper-menu.ini" ]] && grep -q 'ReaProfessor\|reaprofessor_layout\|_REAPACK_BROWSE' "$RESOURCE/reaper-menu.ini" 2>/dev/null; then
  echo "Note: $RESOURCE/reaper-menu.ini still has an old ReaProfessor Extensions customization."
  echo "      Open the hub once (or run install_extensions_menu.lua) to remove it, then quit/reopen."
fi

echo "REAPER resource: $RESOURCE"
echo
echo "Next steps in REAPER:"
echo "  1) File → Quit and reopen so UserPlugins picks up reaper_reaprofessor"
echo "  2) Extensions → ReaProfessor (sibling of ReaPack / SWS / your other extensions)"
echo "  3) Use ← Back inside panels to return to the hub"
echo "Optional: Preferences → Control/OSC/web → pattern config ReaProfessor."
echo "If an older build nested Extensions: open hub once to clear reaper-menu.ini, then quit/reopen."
