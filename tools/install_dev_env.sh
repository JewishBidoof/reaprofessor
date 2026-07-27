#!/usr/bin/env bash
# Idempotent install of REAPER + extensions + audio tooling for ReaProfessor dev.
set -euo pipefail

REAPER_VER="${REAPER_VER:-778}"
REAPER_URL="${REAPER_URL:-https://www.reaper.fm/files/7.x/reaper${REAPER_VER}_linux_x86_64.tar.xz}"
SWS_URL="${SWS_URL:-https://github.com/reaper-oss/sws/releases/download/v2.14.0.7/reaper_sws-x86_64.so}"
SWS_PY_URL="${SWS_PY_URL:-https://github.com/reaper-oss/sws/releases/download/v2.14.0.7/sws_python64.py}"
REAPACK_URL="${REAPACK_URL:-https://github.com/cfillion/reapack/releases/latest/download/reaper_reapack-x86_64.so}"

RESOURCE="${REAPER_RESOURCE:-$HOME/.config/REAPER}"
TMP="${TMPDIR:-/tmp}/reaprofessor-install"
mkdir -p "$TMP" "$RESOURCE/UserPlugins" "$RESOURCE/Scripts" "$RESOURCE/ColorThemes"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "==> System packages"
if need_cmd apt-get; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    wget curl xz-utils unzip alsa-utils jackd2 libjack-jackd2-0 lua5.4 \
    >/dev/null
fi

if ! need_cmd reaper; then
  echo "==> Installing REAPER ${REAPER_VER}"
  wget -q -O "$TMP/reaper.tar.xz" "$REAPER_URL"
  tar -xf "$TMP/reaper.tar.xz" -C "$TMP"
  if [[ -x "$TMP/reaper_linux_x86_64/install-reaper.sh" ]]; then
    sudo "$TMP/reaper_linux_x86_64/install-reaper.sh" \
      --install /opt --quiet --integrate-desktop --usr-local-bin-symlink
  else
    sudo mkdir -p /opt/REAPER
    sudo cp -a "$TMP/reaper_linux_x86_64/REAPER/." /opt/REAPER/
    sudo ln -sfn /opt/REAPER/reaper /usr/local/bin/reaper
  fi
else
  echo "==> REAPER already present: $(command -v reaper)"
fi

echo "==> SWS + ReaPack plugins"
wget -q -O "$RESOURCE/UserPlugins/reaper_sws-x86_64.so" "$SWS_URL"
wget -q -O "$RESOURCE/UserPlugins/sws_python64.py" "$SWS_PY_URL" || true
wget -q -O "$RESOURCE/UserPlugins/reaper_reapack-x86_64.so" "$REAPACK_URL"

# Seed JACK-friendly reaper.ini if missing
if [[ ! -f "$RESOURCE/reaper.ini" ]]; then
  echo "==> Writing initial reaper.ini (JACK)"
  cat > "$RESOURCE/reaper.ini" << 'EOF'
[REAPER]
ver=7.78
hasbeenrun=1
splash=0
checkforupdates=0
script_allow=1
jack=1
jack_auto_activate=1
jack_nch_in=8
jack_nch_out=8
audiodevicein=JACK
audiodeviceout=JACK
alsa=0
pulse=0
EOF
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -x "$REPO_ROOT/tools/unpack_default_theme.sh" ]]; then
  "$REPO_ROOT/tools/unpack_default_theme.sh" || true
fi
if [[ -x "$REPO_ROOT/tools/link_to_reaper.sh" ]]; then
  "$REPO_ROOT/tools/link_to_reaper.sh"
fi

echo "==> Done. Run: tools/start_jack.sh && tools/smoke_test.sh"
reaper -h 2>&1 | head -3 || true
