#!/bin/bash
# Local mirror of .github/workflows/tests.yml's harness loop.
# Usage: tools/run_suite.sh [harness ...]   (no args = the full CI list)
set -u
GODOT=~/godot-bin/godot
cd "$(dirname "$0")/.."
mkdir -p /tmp/ci-logs
failed=0
run() {
  local name="$1"; shift
  "$GODOT" --headless --path . -s "tools/${name}.gd" "$@" \
    > "/tmp/ci-logs/${name}.log" 2>&1 || true
  if grep -q "RESULT: PASS" "/tmp/ci-logs/${name}.log"; then
    echo "ok    ${name}"
  else
    echo "FAIL  ${name}"
    tail -n 30 "/tmp/ci-logs/${name}.log"
    failed=1
  fi
}
if [ $# -gt 0 ]; then
  for h in "$@"; do
    if [ "$h" = "check_level" ]; then run check_level -- --all; else run "$h"; fi
  done
else
  run test_rules; run test_roll; run test_career; run test_gear; run test_morale; run test_overwatch; run test_undo; run test_aiplan; run test_projection; run test_pressure; run test_wounds
  run test_menu; run test_save_load; run test_progression; run test_hero_gameover
  run test_returners; run test_bounty; run test_ratline; run test_occlusion
  run check_level -- --all; run check_briefing_fit; run check_cover_rules
  run check_tile_catalog; run check_floor_sheets; run check_unit_art; run check_prop_tables
fi
exit $failed
