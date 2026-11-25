#!/usr/bin/env bash
# tests/check-runner.sh — harness/scripts/check.sh（検査の実行役）自身のシナリオテスト
#
# 使い方:  bash tests/check-runner.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 使い捨てのリポジトリに .harness/checks.sh を書き、check.sh を直接回す（init は通さない。速さのため）。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO/harness/scripts/check.sh"
WORK="$(mktemp -d)" || { echo "tests/check-runner.sh: mktemp -d に失敗した"; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0; failed=0
failed_names=()
ok()   { passed=$((passed + 1)); echo "PASS  $1"; }
ng()   { failed=$((failed + 1)); failed_names+=("$1"); echo "FAIL  $1"; printf '%s\n' "$OUT" | sed 's/^/      | /'; }

P="$WORK/p"; mkdir -p "$P/.harness" && git init -q "$P"
checks() { printf '%s\n' "$@" >"$P/.harness/checks.sh"; }
run() { OUT="$(cd "$P" && HARNESS_FAST_WARN_SEC="${WARN:-5}" bash "$RUNNER" "$@" 2>&1)"; RC=$?; }

# ---- C1〜C3: --fast で重い fast の検査を言う（決定 0015）----
checks 'check fast "quick" "true"' 'check fast "slow" "sleep 2"' 'check "full only" "sleep 2"'
WARN=1 run --fast
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'NOTE: fast の検査が 1 秒を超えた' \
  && printf '%s' "$OUT" | sed -n '/NOTE: fast/,$p' | grep -qE '^ +[0-9]+s  slow$' \
  && ! printf '%s' "$OUT" | sed -n '/NOTE: fast/,$p' | grep -qE '^ +[0-9]+s  quick$'; } \
  && ok "C1: --fast で閾値を超えた fast の検査だけを挙げ、落とさない" || ng "C1"
WARN=1 run
printf '%s' "$OUT" | grep -q 'NOTE: fast の検査' && ng "C2" || ok "C2: フルの検査では言わない"
WARN=5 run --fast
printf '%s' "$OUT" | grep -q 'NOTE: fast の検査' && ng "C3" || ok "C3: 閾値（既定 5 秒）以内なら言わない"

# ---- C4〜C7: --only で表示名に合う検査だけ回す（決定 0015）----
checks 'check fast "lint a" "true"' 'check "unit b" "true"' 'check "unit c" "false"'
run --only 'unit b'
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=0 skipped=2'; } && ok "C4: --only に合う検査だけ回す" || ng "C4"
run --only 'lint|unit c'
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=1 skipped=1'; } && ok "C5: --only は拡張正規表現。落ちれば終了コードも落ちる" || ng "C5"
run --fast --only 'unit'
printf '%s' "$OUT" | grep -q 'pass=0 fail=0 skipped=3' && ok "C6: --fast と --only の両方に合うものだけ" || ng "C6"
run --only
{ [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q -- '--only の後ろに'; } && ok "C7: --only の値が無ければ使い方を言って止まる" || ng "C7"

echo
echo "tests/check-runner.sh: pass=$passed fail=$failed"
[ "$failed" = 0 ] || { printf '  failed: %s\n' "${failed_names[@]}"; exit 1; }
