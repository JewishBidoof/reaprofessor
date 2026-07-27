#!/usr/bin/env bash
# Unpack Default 7.0 theme images next to ReaProfessor color overlay.
set -euo pipefail

RESOURCE="${REAPER_RESOURCE:-$HOME/.config/REAPER}"
DEST="$RESOURCE/ColorThemes"
mkdir -p "$DEST"

THEME_ZIP=""
for candidate in \
  /opt/REAPER/InstallData/ColorThemes/Default_7.0.ReaperThemeZip \
  /usr/local/share/REAPER/InstallData/ColorThemes/Default_7.0.ReaperThemeZip
do
  if [[ -f "$candidate" ]]; then
    THEME_ZIP="$candidate"
    break
  fi
done

if [[ -z "$THEME_ZIP" ]]; then
  echo "Default_7.0.ReaperThemeZip not found (is REAPER installed?)" >&2
  exit 1
fi

if [[ -d "$DEST/Default_7.0_unpacked" && -f "$DEST/Default_7.0_unpacked.ReaperTheme" ]]; then
  echo "Default 7.0 already unpacked in $DEST"
  exit 0
fi

TMP=$(mktemp -d)
cp "$THEME_ZIP" "$TMP/theme.zip"
unzip -q -o "$TMP/theme.zip" -d "$TMP/out"
cp -a "$TMP/out/." "$DEST/"
rm -rf "$TMP"
echo "Unpacked Default 7.0 into $DEST"
