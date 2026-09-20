#!/usr/bin/env bash
# tests/githooks.sh — このリポジトリ自身の .githooks/pre-commit が「実際に走る形」で
# コミットされていることを機械で確かめる（このリポジトリ専用。ペイロードではない）。
#
# 使い方:  bash tests/githooks.sh
# 終了コード: 通れば 0、落ちれば 1。
#
# なぜ要るか: git は**実行ビットの無いフックを黙って無視する**。commit は成功し、
#   hint: The '.githooks/pre-commit' hook was ignored because it's not set as executable.
# が 1 行出るだけなので、「pre-commit で速い検査が回っている」つもりのまま一度も回っていない、
# という状態が長く続く（2026-09-20 に macOS 実機で発覚。index も作業ツリーも 100644 だった）。
# ハーネスは「harness check が完了の客観条件」を根幹に置いているので、その入口が黙って
# 無効化される状態を許さない。
#
# 見るのは git index の mode（= clone した先に配られる値）を主、作業ツリーの -x を従とする。
# Windows の Git は core.filemode=false が既定で作業ツリーの実行ビットに意味が無いため、
# そこでは -x を見ない（見ると全員に偽の失敗が出る）。index の mode は OS を問わず記録される。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 2

HOOK=".githooks/pre-commit"
fail=0

if [ ! -f "$HOOK" ]; then
  echo "tests/githooks.sh: ${HOOK} が無い。bash bin/harness update で入る。"
  exit 1
fi

mode="$(git ls-files -s -- "$HOOK" 2>/dev/null | awk '{print $1; exit}')"
if [ -z "$mode" ]; then
  echo "tests/githooks.sh: ${HOOK} が git に追跡されていない。"
  echo "  直し方: git add --chmod=+x ${HOOK}"
  fail=1
elif [ "$mode" != "100755" ]; then
  echo "tests/githooks.sh: git index 上の ${HOOK} の mode が ${mode}（実行ビット無し）。"
  echo "  この状態で clone すると実行ビットの無いフックが配られ、git がフックを黙って無視する。"
  echo "  直し方: chmod +x ${HOOK} && git update-index --chmod=+x ${HOOK}"
  fail=1
fi

filemode="$(git config --get core.filemode 2>/dev/null || true)"
if [ "$filemode" != "false" ] && [ ! -x "$HOOK" ]; then
  echo "tests/githooks.sh: 作業ツリーの ${HOOK} に実行ビットが無い（この PC ではフックが走らない）。"
  echo "  直し方: chmod +x ${HOOK}"
  echo "  harness update の直後なら、update は実行ビットを立て直すので、その後に落ちたなら bin/harness を疑う。"
  fail=1
fi

# フックが「速い検査を回す」中身であること。実行ビットだけ立っていて中身が空では意味が無い。
if ! grep -q 'check\.sh' "$HOOK"; then
  echo "tests/githooks.sh: ${HOOK} が check.sh を呼んでいない。bash bin/harness update で正本の内容に戻す。"
  fail=1
fi

[ "$fail" = 0 ] || exit 1
echo "tests/githooks.sh: pass（index mode=${mode}, 中身は check.sh --fast を呼ぶ）"
