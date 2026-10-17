#!/bin/sh
# leak-audit git hook shim. Copy it into a repo (e.g. .githooks/leak-audit.sh); it holds no machine paths, so the
# same file works on every machine, Git for Windows' sh included. It finds leak-audit's scripts/hook.py on this
# machine and runs it:
#
#   sh leak-audit-hook.sh pre-push "$@"       from .githooks/pre-push   (stdin passes through)
#   sh leak-audit-hook.sh commit-msg "$1"     from .githooks/commit-msg
#   sh leak-audit-hook.sh pre-commit          from .githooks/pre-commit, or a pre-commit check runner
#
# Where it looks, in order: $LEAK_AUDIT_DIR; <config dir>/skills/leak-audit for $CLAUDE_CONFIG_DIR and every
# ~/.claude* directory (a symlinked or copied skill); the newest leak-audit in those directories' plugin caches.
# If leak-audit or Python 3.8+ is missing it says so and lets the commit / push through (the check did NOT run);
# LEAK_AUDIT_STRICT=1 makes that a failure instead.

mode="$1"
[ $# -gt 0 ] && shift

find_dir() {
  if [ -n "$LEAK_AUDIT_DIR" ] && [ -f "$LEAK_AUDIT_DIR/scripts/hook.py" ]; then
    echo "$LEAK_AUDIT_DIR"; return
  fi
  for base in "$CLAUDE_CONFIG_DIR" "$HOME"/.claude*; do
    if [ -n "$base" ] && [ -f "$base/skills/leak-audit/scripts/hook.py" ]; then
      echo "$base/skills/leak-audit"; return
    fi
  done
  # plugin caches keep old versions next to the current one: take the most recently written
  ls -dt "$HOME"/.claude*/plugins/cache/*/*/*/leak-audit 2>/dev/null | while IFS= read -r d; do
    if [ -f "$d/scripts/hook.py" ]; then echo "$d"; break; fi
  done
}

not_checked() {
  echo "[leak-audit] WARNING: $1 -- this $mode was NOT checked for leaks." >&2
  echo "[leak-audit] Install the leak-audit skill (or set LEAK_AUDIT_DIR to its folder) to enable the check." >&2
  [ "$LEAK_AUDIT_STRICT" = "1" ] && exit 1
  exit 0
}

dir=$(find_dir)
[ -n "$dir" ] || not_checked "leak-audit not found on this machine"

PY=""
for py in python3 python "py -3"; do
  # shellcheck disable=SC2086  # "py -3" must split into command + argument
  if $py -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1; then PY="$py"; break; fi
done
[ -n "$PY" ] || not_checked "Python 3.8+ not found"

# shellcheck disable=SC2086
exec $PY "$dir/scripts/hook.py" "$mode" "$@"
