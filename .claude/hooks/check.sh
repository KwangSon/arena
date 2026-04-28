#!/bin/bash
#
# Claude Code Stop hook — runs after Claude finishes a conversation turn.
#
# Steps:
#   1. gdlint   — full-project lint sweep
#   2. gdformat — auto-format (mutates .gd files in place)
#   3. GUT      — unit tests
#
# Output protocol (Claude Code Stop hook):
#   - Success: prints `{}` (no-op, Claude is allowed to stop)
#   - Failure: prints `{"decision":"block","reason":"<errors>"}` so Claude Code
#     feeds the failures back to the model on the next turn.

# Activate Python venv for gdlint/gdformat
if [ -f ".venv/bin/activate" ]; then
  # shellcheck source=/dev/null
  source .venv/bin/activate
fi

# Discard Stop event JSON on stdin (we don't need it)
cat >/dev/null

errors=""

# Project .gd files only — exclude addons/, .godot/ cache, and Nakama's test_suite/
find_project_gd() {
  find . -name "*.gd" \
    -not -path "./addons/*" \
    -not -path "./.godot/*" \
    -not -path "./test_suite/*" \
    -print0
}

# 1. gdlint
echo "[check] gdlint" >&2
lint_out=$(find_project_gd | xargs -0 gdlint 2>&1)
if [ $? -ne 0 ]; then
  errors+="=== GDLINT FAILED ==="$'\n'"$lint_out"$'\n\n'
fi

# 2. gdformat (mutates files in place)
echo "[check] gdformat" >&2
fmt_out=$(find_project_gd | xargs -0 gdformat 2>&1)
if [ $? -ne 0 ]; then
  errors+="=== GDFORMAT FAILED ==="$'\n'"$fmt_out"$'\n\n'
fi

# 3. GUT unit tests
# Resolve Godot binary: prefer per-user ./godot symlink (see docs/setup.md),
# fall back to PATH. Aliases don't work here — hooks run in non-interactive shells.
echo "[check] GUT" >&2
godot_bin=""
if [ -x "./godot" ]; then
  godot_bin="./godot"
elif command -v godot &>/dev/null; then
  godot_bin="godot"
fi

if [ -n "$godot_bin" ]; then
  gut_out=$("$godot_bin" -d -s --path "$PWD" addons/gut/gut_cmdln.gd 2>&1)
  if [ $? -ne 0 ]; then
    errors+="=== GUT TESTS FAILED ==="$'\n'"$gut_out"$'\n\n'
  fi
else
  echo "[check] godot binary not found (expected ./godot symlink — see docs/setup.md), skipping GUT" >&2
fi

# Emit Claude Code Stop decision JSON
if [ -z "$errors" ]; then
  echo '{}'
else
  jq -nc --arg reason "$errors" '{decision: "block", reason: $reason}'
fi
