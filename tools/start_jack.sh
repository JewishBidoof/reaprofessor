#!/usr/bin/env bash
# Start (or restart) JACK with the dummy driver for cloud / no-interface use.
set -euo pipefail

RATE="${JACK_RATE:-48000}"
PERIOD="${JACK_PERIOD:-256}"
INS="${JACK_INS:-8}"
OUTS="${JACK_OUTS:-8}"
LOG="${JACK_LOG:-/tmp/reaprofessor-jackd.log}"

if command -v jack_lsp >/dev/null 2>&1 && jack_lsp >/dev/null 2>&1; then
  echo "JACK already running:"
  jack_lsp | head -5
  exit 0
fi

killall jackd 2>/dev/null || true
sleep 0.3

# Realtime privileges are often unavailable in cloud VMs — still usable.
jackd -d dummy -r "$RATE" -p "$PERIOD" -C "$INS" -P "$OUTS" >"$LOG" 2>&1 &
disown || true

for i in $(seq 1 20); do
  if jack_lsp >/dev/null 2>&1; then
    echo "JACK dummy ready (r=$RATE p=$PERIOD ${INS}in/${OUTS}out)"
    jack_lsp | head -8
    exit 0
  fi
  sleep 0.25
done

echo "JACK failed to start; see $LOG" >&2
tail -30 "$LOG" >&2 || true
exit 1
