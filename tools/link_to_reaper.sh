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
echo "  1) Open hub → Install / repair Extensions menu → File → Quit → reopen"
echo "  2) Extensions → ReaProfessor (ReaPack / SWS/S&M are sibling submenus)"
echo "  3) Use ← Back inside panels to return to the hub"
echo "Optional: Preferences → Control/OSC/web → pattern config ReaProfessor."
echo "If a leftover 'Default menu' remains: Customize menus/toolbars → uncheck Include default menu as submenu."
echo "To restore stock Extensions only: hub → Remove Extensions customization → Quit/reopen."

