#!/usr/bin/env bash
# tests/lint-bash-compat.sh — bash 3.2 互換を機械で強制する（決定 0006: bash 3.2 を切らない）。
#
# macOS 既定の bash は 3.2.57 のままで、今後もアップデートされない見込み。以下の 2 つを
# 踏むと macOS の既定 bash で壊れるので、bin/harness・harness/scripts/*.sh・tests/*.sh から
# 締め出す（実測: docs/decisions/0006-support-bash-3-2.md）。
#
#   1. bash 4+ 専用構文（declare -A / local -A / declare -n / local -n / mapfile / readarray）
#      -> 連想配列が無い。`bin/harness:355` の declare -A で harness init が即死した実績がある。
#   2. 変数展開の直後に非 ASCII が来る形（例: "$var" のすぐ後ろに日本語が続く）
#      -> bash 3.2 + UTF-8 ロケールでは変数名にマルチバイト文字の先頭バイトが食い込み、
#         set -u 環境で "unbound variable" になる。${var} と波括弧で括れば起きない。
#
# コメント行（行頭が # だけの行）は対象外にする。実装コードだけを見る。
#
# 使い方: bash tests/lint-bash-compat.sh [forbidden-syntax|nonascii-var]
#   引数無しなら両方実行する。harness check からは 2 検査として別々に呼ぶ。
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2

mode="${1:-all}"
case "$mode" in forbidden-syntax|nonascii-var|all) ;; *) echo "usage: $0 [forbidden-syntax|nonascii-var]" >&2; exit 2;; esac

files=()
[ -f bin/harness ] && files+=("bin/harness")
for f in harness/scripts/*.sh; do [ -f "$f" ] && files+=("$f"); done
for f in tests/*.sh; do
  # この検査スクリプト自身は除く。禁止パターンを「メッセージ文字列として」持たざるを得ない
  # （直し方の説明に実例を出す）ので、対象に含めると自分自身で必ず引っかかる。
  [ -f "$f" ] && [ "$f" != "tests/lint-bash-compat.sh" ] && files+=("$f")
done

status=0

# コメント行（行頭が # の行）を除いた「<行番号>:<内容>」だけを検査対象にする
code_hits() { # file pattern
  grep -nE "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#'
}

check_forbidden_syntax() {
  echo "-- bash 4+ 専用構文の禁止（declare -A / local -A / declare -n / local -n / mapfile / readarray）"
  local forbidden_re='(declare|local)[[:space:]]+-A|(declare|local)[[:space:]]+-n|\<mapfile\>|\<readarray\>'
  local hit=0 f out
  for f in "${files[@]}"; do
    out="$(code_hits "$f" "$forbidden_re")"
    if [ -n "$out" ]; then
      hit=1
      while IFS= read -r line; do echo "  $f:$line"; done <<<"$out"
    fi
  done
  if [ "$hit" = 1 ]; then
    echo "  直し方: 連想配列は使わず、区切り文字つきの単一変数・一時ファイル・関数での引き当てに置き換える。"
    echo "         mapfile / readarray は while IFS= read -r line; do ...; done <file に置き換える。"
    echo "         bash 3.2 を切らない方針は docs/decisions/0006-support-bash-3-2.md。"
    return 1
  fi
  echo "  OK"
  return 0
}

check_nonascii_var() {
  echo "-- 変数展開直後の非 ASCII の禁止（\"\$var<非ASCII>\" は bash 3.2 + UTF-8 で unbound variable になる）"
  # LC_ALL=C で生バイト比較にする（実行環境のロケールに判定結果を左右させない）。
  # [ -~] は ASCII の空白〜チルダ（印字可能な半角）。その外側（多バイト文字の先頭バイトや制御文字）を拾う。
  local nonascii_re='\$[A-Za-z_][A-Za-z0-9_]*[^ -~]'
  local hit=0 f out
  for f in "${files[@]}"; do
    out="$(LC_ALL=C code_hits "$f" "$nonascii_re")"
    if [ -n "$out" ]; then
      hit=1
      while IFS= read -r line; do echo "  $f:$line"; done <<<"$out"
    fi
  done
  if [ "$hit" = 1 ]; then
    echo '  直し方: 変数展開を ${var} と波括弧で括る（例: "$v。" -> "${v}。"）。'
    echo "         再発しやすい罠は docs/decisions/0006-support-bash-3-2.md と docs/learnings.md を見る。"
    return 1
  fi
  echo "  OK"
  return 0
}

case "$mode" in
  forbidden-syntax) check_forbidden_syntax || status=1 ;;
  nonascii-var)      check_nonascii_var || status=1 ;;
  all)
    check_forbidden_syntax || status=1
    check_nonascii_var || status=1
    ;;
esac

exit "$status"
