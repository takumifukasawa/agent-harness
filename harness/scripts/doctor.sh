#!/usr/bin/env bash
# harness doctor — 導入先の環境とハーネス導入状態を機械的に診断して一覧にする。
# 報告のみ（自動修復はしない）。gc が docs の健康診断なら、doctor は環境の健康診断。LLM は使わない。
#
# 使い方:  bash .harness/scripts/doctor.sh
#
# 各行:  OK|WARN|FAIL  項目  →  直し方     （OK 行に直し方は付かない）
# 最後に集計行（OK / WARN / FAIL の件数）。
#
# 終了コード:
#   0  問題なし、または WARN のみ
#   1  FAIL あり
#   2  診断自体ができない環境不備（未導入ディレクトリなど）
#
# 診断は bash と git だけで動く。node / jq が無くても全項目が実行できる（あれば使う、で留める）。
set -u

# git が無い環境でも診断できるよう、ROOT の決定は git に依存しすぎない
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Git for Windows は C:/... を返す。MSYS の /c/... に揃える（bin/harness の project_root と同じ扱い）
if command -v cygpath >/dev/null 2>&1; then ROOT="$(cygpath -u "$ROOT" 2>/dev/null || echo "$ROOT")"; fi
cd "$ROOT" 2>/dev/null || { echo "harness doctor: $ROOT に入れない" >&2; exit 2; }

if [ ! -f "$ROOT/.harness/manifest.json" ]; then
  echo "harness doctor: 導入コピーが無い（$ROOT/.harness/manifest.json が見つからない）" >&2
  echo "  直し方: このディレクトリで harness init を実行する" >&2
  echo "          例: bash <agent-harness を clone した場所>/bin/harness init --source <同じ場所>" >&2
  exit 2
fi

n_ok=0; n_warn=0; n_fail=0
report() { # severity 項目 [直し方]
  case "$1" in
    OK)   n_ok=$((n_ok + 1));;
    WARN) n_warn=$((n_warn + 1));;
    FAIL) n_fail=$((n_fail + 1));;
  esac
  if [ -n "${3:-}" ]; then
    printf '%-4s  %s  →  %s\n' "$1" "$2" "$3"
  else
    printf '%-4s  %s\n' "$1" "$2"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

os_name="$(uname -s 2>/dev/null || echo unknown)"
is_windows=0
case "$os_name" in MINGW*|MSYS*|CYGWIN*) is_windows=1;; esac

# ---------------------------------------------------------------- B1. 必須ツール
# bash の版は BASH_VERSINFO[0] で見る（BASH_VERSINFO は readonly なのでテストから上書きできない。
# 「bash < 4」のシナリオは自動テストでは再現せず、実機が bash 3 の環境でこの行を見る）
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  report OK "bash ${BASH_VERSION:-?}（4 以上）"
else
  report FAIL "bash の版が ${BASH_VERSION:-不明}（4 未満。連想配列などが使えない）" \
    "bash 4 以上で実行する（macOS: brew install bash して /opt/homebrew/bin/bash から回す。Windows: Git for Windows 同梱の bash）"
fi

if have git; then
  report OK "git（$(git --version 2>/dev/null | head -1)）"
else
  report FAIL "git が見つからない（ハーネスは git と bash だけに依存する）" \
    "git を入れて PATH に通す（Windows: Git for Windows、macOS: xcode-select --install、Linux: apt install git など）"
fi

# ---------------------------------------------------------------- B2. 任意ツール
if have node; then
  report OK "node（任意。$(node --version 2>/dev/null)）"
else
  report WARN "node が無い（任意）" \
    ".claude/settings.json の自動マージが手動になる。無くてもハーネスは動く。必要なら node を入れる"
fi

if have jq; then
  report OK "jq（任意。$(jq --version 2>/dev/null)）"
else
  report WARN "jq が無い（任意）" \
    "task-orchestrate の stages.json 抽出が grep 頼りになる。無くてもハーネスは動く。必要なら jq を入れる"
fi

if [ "$is_windows" = 1 ]; then
  if have cygpath; then
    report OK "cygpath（Windows）"
  else
    report WARN "cygpath が無い（$os_name）" \
      "パス形式（C:/ と /c/）の正規化ができない。Git for Windows 同梱の bash から実行する"
  fi
fi

# ---------------------------------------------------------------- 集計
echo
echo "harness doctor: OK=$n_ok WARN=$n_warn FAIL=$n_fail"
if [ "$n_fail" -gt 0 ]; then
  echo "  FAIL の行の「→」に従って直す。直せたらもう一度 harness doctor を回す。"
  exit 1
fi
exit 0
