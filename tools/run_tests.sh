#!/usr/bin/env bash
# Run ReaProfessor automated test suite (smoke + extended harnesses).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${REAPROFESSOR_TEST_DIR:-/tmp/reaprofessor-test}"
mkdir -p "$OUT_DIR"

export DISPLAY="${DISPLAY:-:1}"
export REAPROFESSOR_ROOT="$REPO_ROOT"
export REAPROFESSOR_TEST_DIR="$OUT_DIR"

if [[ -x "$REPO_ROOT/tools/start_jack.sh" ]]; then
  "$REPO_ROOT/tools/start_jack.sh" || true
fi
"$REPO_ROOT/tools/link_to_reaper.sh"

run_harness() {
  local name="$1"
  local script="$2"
  local result_name="$3"
  local result="$OUT_DIR/$result_name"
  local log="$OUT_DIR/${name}-stdout.log"
  rm -f "$result"

  echo ""
  echo "======== $name ========"
  killall -9 reaper 2>/dev/null || true
  sleep 0.4

  timeout "${TEST_TIMEOUT:-90}" reaper -newinst -nosplash -new -ignoreerrors \
    "$script" >"$log" 2>&1 || true

  for _ in $(seq 1 40); do
    [[ -f "$result" ]] && break
    sleep 0.25
  done

  if [[ ! -f "$result" ]]; then
    echo "FAIL: $name — no result file" >&2
    tail -80 "$log" >&2 || true
    return 1
  fi

  echo "---- $result_name ----"
  cat "$result"
  echo "----------------------"

  if ! grep -q '^OK$' "$result"; then
    echo "FAIL: $name reported failure" >&2
    return 1
  fi

  # Fail on any key=false (except informational / legacy keys)
  local falses
  falses=$(grep -E '^[a-z0-9_]+=false$' "$result" | grep -vE '^(legacy_has_actions|legacy_snap_name|playhead_natural)=' || true)
  if [[ -n "$falses" ]]; then
    echo "FAIL: $name has false assertions:" >&2
    echo "$falses" >&2
    return 1
  fi

  echo "PASS: $name"
  return 0
}

require_keys() {
  local result="$1"; shift
  for key in "$@"; do
    grep -q "^${key}=" "$result" || { echo "Missing key: $key in $result" >&2; return 1; }
  done
}

FAILED=0

# 1) Core smoke
if ! "$REPO_ROOT/tools/smoke_test.sh"; then
  FAILED=1
else
  require_keys "$OUT_DIR/smoke-result.txt" \
    tc_format tc_parse tc_chase tc_once tc_rewind \
    cue_go osc_queue snap_full || FAILED=1
  grep -q '^tc_chase=true$' "$OUT_DIR/smoke-result.txt" || { echo "tc_chase failed" >&2; FAILED=1; }
  grep -q '^tc_rewind=true$' "$OUT_DIR/smoke-result.txt" || { echo "tc_rewind failed" >&2; FAILED=1; }
fi

# 2) Extensive timecode suite
if ! run_harness "timecode" "$REPO_ROOT/tests/timecode.lua" "timecode-result.txt"; then
  FAILED=1
else
  require_keys "$OUT_DIR/timecode-result.txt" \
    roundtrip parse_blank cross_c1 cross_c2 cross_c3 multi_cross scrub_ignored \
    rewind_rearms sync_create sync_upsert no_inbound_feedback outbound_queued \
    dummy_fire_ok snap_chase_fire live_chase_fire transport_running \
    || FAILED=1
fi

# 3) FX recall suite
if [[ -f "$REPO_ROOT/tests/fx_recall.lua" ]]; then
  if ! run_harness "fx_recall" "$REPO_ROOT/tests/fx_recall.lua" "fx-recall-result.txt"; then
    FAILED=1
  fi
fi

# 4) UI path recall (show-path / cue full)
if [[ -f "$REPO_ROOT/tests/ui_path_recall.lua" ]]; then
  if ! run_harness "ui_path_recall" "$REPO_ROOT/tests/ui_path_recall.lua" "ui-path-result.txt"; then
    FAILED=1
  fi
fi

# 5) Menu / nav registration
if [[ -f "$REPO_ROOT/tests/menu_nav.lua" ]]; then
  if ! run_harness "menu_nav" "$REPO_ROOT/tests/menu_nav.lua" "menu-nav-result.txt"; then
    FAILED=1
  fi
fi

echo ""
if [[ "$FAILED" -ne 0 ]]; then
  echo "======== SUITE FAILED ========" >&2
  exit 1
fi
echo "======== ALL TESTS PASSED ========"
exit 0
