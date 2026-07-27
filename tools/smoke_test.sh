#!/usr/bin/env bash
# Launch REAPER with the automated smoke harness and assert success.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${REAPROFESSOR_TEST_DIR:-/tmp/reaprofessor-test}"
RESULT="$OUT_DIR/smoke-result.txt"
LOG="$OUT_DIR/reaper-stdout.log"
mkdir -p "$OUT_DIR"
rm -f "$RESULT"

export DISPLAY="${DISPLAY:-:1}"

if [[ -x "$REPO_ROOT/tools/start_jack.sh" ]]; then
  "$REPO_ROOT/tools/start_jack.sh" || true
fi
"$REPO_ROOT/tools/link_to_reaper.sh"

# Ensure REAPER can require() repo libs even before Actions registration.
export REAPROFESSOR_ROOT="$REPO_ROOT"

# A leftover GUI instance will steal argv and open .lua as media — always start clean.
killall -9 reaper 2>/dev/null || true
sleep 0.5

timeout "${SMOKE_TIMEOUT:-60}" reaper -newinst -nosplash -new -ignoreerrors \
  "$REPO_ROOT/tests/smoke.lua" >"$LOG" 2>&1 || true

# Wait briefly if REAPER is still flushing the result file
for _ in $(seq 1 20); do
  [[ -f "$RESULT" ]] && break
  sleep 0.25
done

if [[ ! -f "$RESULT" ]]; then
  echo "Smoke test failed: no result file" >&2
  tail -50 "$LOG" >&2 || true
  exit 1
fi

echo "---- smoke-result ----"
cat "$RESULT"
echo "----------------------"

if ! grep -q '^OK$' "$RESULT"; then
  echo "Smoke test reported failure" >&2
  exit 1
fi

# Required keys
for key in version sws reapack modules cue_go channels_same channels_double snap_bypass snap_params snap_full maps_empty_default midi_match midi_no_default osc_match osc_unmapped_ignored; do
  grep -q "^${key}=" "$RESULT" || { echo "Missing key: $key" >&2; exit 1; }
done

grep -q '^cue_go=true$' "$RESULT" || { echo "cue_go did not succeed" >&2; exit 1; }
grep -q '^channels_same=true$' "$RESULT" || { echo "channel create failed" >&2; exit 1; }
grep -q '^snap_full=true$' "$RESULT" || { echo "full snapshot reload failed" >&2; exit 1; }
grep -q '^maps_empty_default=true$' "$RESULT" || { echo "maps should start empty" >&2; exit 1; }
grep -q '^midi_match=true$' "$RESULT" || { echo "midi map match failed" >&2; exit 1; }
grep -q '^midi_no_default=true$' "$RESULT" || { echo "unexpected default midi binding" >&2; exit 1; }
grep -q '^osc_unmapped_ignored=true$' "$RESULT" || { echo "unmapped OSC should be ignored" >&2; exit 1; }

echo "Smoke test passed."
