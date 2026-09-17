#!/usr/bin/env bash
# harness check — プロジェクトが .harness/checks.sh に登録した検査を順に実行する。
# エージェントはこの結果を「実装完了の客観条件」として使う。LLM は使わない。
#
# 使い方:  bash .harness/scripts/check.sh [--fast]
#   --fast : pre-commit 用。checks.sh で `fast` と印を付けた検査だけ実行する。
#
# .harness/checks.sh の書き方（seed ファイル。プロジェクトが編集する）:
#   check fast "lint"        "npm run lint"
#   check      "unit tests"  "npm test"
#   check      "structure"   "bash scripts/structural-test.sh"
#
# 検査コマンドのエラー出力は「何が違反か」だけでなく「どう直すか / どの doc を読むか」を含めること。
# エージェントはエラー出力をそのまま文脈に取り込むので、そこが最も安い指示経路になる。
set -u

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHECKS="$ROOT/.harness/checks.sh"

if [ ! -f "$CHECKS" ]; then
  echo "harness check: $CHECKS が無い。harness init で seed されるはずのファイル。" >&2
  echo "  直し方: agent-harness の harness/checks.seed.sh を .harness/checks.sh にコピーし、検査を登録する。" >&2
  exit 2
fi

pass=0; fail=0; skipped=0
failed_names=()

check() {
  local speed="" name cmd
  if [ "${1:-}" = "fast" ]; then speed="fast"; shift; fi
  name="${1:-}"; cmd="${2:-}"
  if [ -z "$name" ] || [ -z "$cmd" ]; then
    echo "harness check: checks.sh の書式エラー。check [fast] \"<表示名>\" \"<コマンド>\" の形で書く（name='$name')" >&2
    fail=$((fail + 1)); failed_names+=("(malformed check)"); return
  fi
  if [ "$FAST" = 1 ] && [ "$speed" != "fast" ]; then
    skipped=$((skipped + 1)); return
  fi
  printf '── %s\n' "$name"
  if (cd "$ROOT" && bash -c "$cmd"); then
    echo "   PASS"; pass=$((pass + 1))
  else
    echo "   FAIL ($cmd)"; fail=$((fail + 1)); failed_names+=("$name")
  fi
}

# shellcheck disable=SC1090
source "$CHECKS"

echo
echo "harness check: pass=$pass fail=$fail skipped=$skipped"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failed_names[@]}"
  echo "  失敗した検査の出力を読み、修復手順があればそれに従う。無ければ直した後に検査側へ手順を足す。"
  exit 1
fi
