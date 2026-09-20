#!/usr/bin/env bash
# tests/stdin.sh — bin/harness を「標準入力から」実行する経路を守る（このリポジトリ専用）
#
# 使い方:  bash tests/stdin.sh
# 終了コード: 通れば 0、落ちれば 1。
#
# 何を守るか: README が案内する導入方法のひとつが `curl -fsSL <公開 URL>/bin/harness | bash -s -- init`
# で、この経路ではスクリプトがファイルではなく標準入力から来る。そのとき ${BASH_SOURCE[0]} は
# **設定されない**ので、set -u のもとで素に参照すると "BASH_SOURCE[0]: unbound variable" になる。
# 2026-09-20 に macOS（bash 3.2.57）の実機で確認した。self_repo() の中では command substitution
# の subshell が死ぬだけなので init は進んでしまい、**エラーを出しながら成功する**という
# 一番たちの悪い出方をする。cmd_self_install に至っては「標準入力からは self-install できない」と
# 案内する die に**到達する前に**落ちるので、案内が一度も読まれない。
#
# ここでは公開 URL の代わりにこのリポジトリを source にして同じ経路（stdin 実行）を通す。
# ネットワークに依存させない（検査はオフラインでも通らなければならない）。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM

fail=0
note() { echo "  - $1"; fail=1; }

WORK="$(mktemp -d)" || { echo "tests/stdin.sh: mktemp -d に失敗した"; exit 2; }

# S1. 標準入力からの version が unbound variable を出さない（どのサブコマンドでも通る入口の回帰）
out="$(cat "$REPO/bin/harness" | "$BASH_BIN" -s -- version 2>&1)"
case "$out" in
  *"unbound variable"*) note "標準入力からの version が unbound variable を出す: ${out}";;
esac

# S2. 標準入力からの self-install は「できない理由」を案内して終わる（unbound variable で落ちない）
out="$(cd "$WORK" && cat "$REPO/bin/harness" | "$BASH_BIN" -s -- self-install --dir "$WORK/bin" 2>&1)"
case "$out" in
  *"unbound variable"*) note "標準入力からの self-install が案内の前に unbound variable で落ちる: ${out}";;
  *"標準入力から実行中は self-install できない"*) ;;
  *) note "標準入力からの self-install が想定外の出力になった: ${out}";;
esac

# S3. 標準入力からの init（= curl | bash 経路）が、エラーを出さずに導入まで終わる
PROJ="$WORK/p"; mkdir -p "$PROJ"
(
  cd "$PROJ" &&
  git init -q . &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
) >/dev/null 2>&1 || { echo "tests/stdin.sh: 使い捨てプロジェクトの作成に失敗した"; exit 2; }

out="$(cd "$PROJ" && cat "$REPO/bin/harness" | "$BASH_BIN" -s -- init --source "$REPO" 2>&1)"; rc=$?
case "$out" in
  *"unbound variable"*) note "標準入力からの init が unbound variable を出す（成功していても出してはいけない）";;
esac
[ "$rc" = 0 ] || note "標準入力からの init が exit ${rc} で終わった"
# @self（同梱 CLI）は SELF_PATH が無いときペイロード側の bin/harness から書かれる。その経路の回帰。
[ -f "$PROJ/.harness/bin/harness" ] || note "標準入力からの init で .harness/bin/harness が置かれていない"
[ -x "$PROJ/.githooks/pre-commit" ] || note "標準入力からの init で .githooks/pre-commit が実行可能になっていない"
if [ -f "$PROJ/.harness/bin/harness" ]; then
  cmp -s "$PROJ/.harness/bin/harness" "$REPO/bin/harness" ||
    note "同梱された CLI がペイポードの bin/harness と一致しない（@self のフォールバックが壊れている）"
fi

if [ "$fail" != 0 ]; then
  echo "tests/stdin.sh: fail"
  echo "  直し方: bin/harness の \${BASH_SOURCE[0]} 参照を \${BASH_SOURCE[0]:-} にする（標準入力から"
  echo "          実行すると BASH_SOURCE は設定されない。set -u と組み合わさると落ちる）。"
  exit 1
fi
echo "tests/stdin.sh: pass（version / self-install / init を標準入力から実行しても unbound variable が出ない）"
