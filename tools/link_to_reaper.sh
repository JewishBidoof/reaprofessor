#!/usr/bin/env bash
# Symlink ReaProfessor scripts/theme into the REAPER resource path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCE="${REAPER_RESOURCE:-$HOME/.config/REAPER}"

mkdir -p "$RESOURCE/Scripts" "$RESOURCE/ColorThemes" "$RESOURCE/OSC"

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

echo "REAPER resource: $RESOURCE"
echo
echo "Next steps in REAPER:"
echo "  1) Actions → Show action list → Load → Scripts/ReaProfessor/ReaProfessor.lua"
echo "  2) Run 'ReaProfessor' (or 'Install Extensions menu')"
echo "  3) Restart REAPER once → Extensions → ReaProfessor"
echo "Optional: Preferences → Control/OSC/web → pattern config ReaProfessor."

