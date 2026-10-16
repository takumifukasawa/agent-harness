#!/usr/bin/env bash
# tests/hash-server-stderr.sh — hash_server_start / hash_server_stop の後も stderr が生きて
# いるかを機械で確かめる（tech-debt #15 の回帰検査。このリポジトリ専用。ペイロードではない）。
#
# 使い方:  bash tests/hash-server-stderr.sh
# 終了コード: 通れば 0、落ちれば 1（環境が対応していなければ SKIP して 0）。
#
# なぜ要るか: hash_server_start の中の `exec 3<>"$d/in" 4<>"$d/out" 2>/dev/null` はコマンドを
# 伴わない bare exec なので、`2>/dev/null` がその 1 行だけでなくシェル全体へ永続適用され、
# 以後のすべての stderr が /dev/null に消える（bash のよくある落とし穴）。この状態で下流の
# 処理（seed の mkdir -p 等）が失敗すると、init / update がエラーメッセージ無しに無言終了する
# （実害は 2026-09-21 に実機で再現。docs/tech-debt.md #15）。hash_server_stop の
# `exec 3>&- 4>&- 2>/dev/null` にも同じ形があるので、両方を見る。
#
# bin/harness は CLI を経由せず source して hash_server_start / hash_server_stop を直接呼ぶ
# （bin/harness 末尾の main 分岐は「source されたときは走らせない」よう HARNESS_SOURCED で
# ガードしてある）。stderr が壊れているかどうかは、壊れた fd 2 は同一プロセス内では検出でき
# ない（2>&1 で束ねても、その時点で fd 2 はすでに /dev/null を指している）ため、外側の
# プロセスが用意した 2 つの独立したファイルへ子プロセスの stdout / stderr を分けて捕まえ、
# 子プロセス終了後にファイルの中身を見る。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTF="$(mktemp)"; ERRF="$(mktemp)"
trap 'rm -f "$OUTF" "$ERRF"' EXIT INT TERM

bash -c '
  REPO="$1"
  . "$REPO/bin/harness"
  [ "${HARNESS_SOURCED:-0}" = 1 ] || { echo "bin/harness の source に失敗した（HARNESS_SOURCED != 1）" >&2; exit 2; }
  hash_server_start
  if [ -z "${HASH_SRV_DIR:-}" ]; then
    echo "この環境では常駐サーバが起動しない（mkfifo か git hash-object --stdin-paths --no-filters が無い）"
    exit 3
  fi
  echo "stdout after hash_server_start"
  echo "PROBE-A: stderr after hash_server_start" >&2
  hash_server_stop
  echo "PROBE-B: stderr after hash_server_stop" >&2
  exit 0
' -- "$REPO" >"$OUTF" 2>"$ERRF"
code=$?

if [ "$code" = 3 ]; then
  echo "tests/hash-server-stderr.sh: SKIP（この環境では常駐サーバが起動しないため、常駐時の stderr は判定できない）"
  cat "$OUTF"
  exit 0
fi

fail=0
if [ "$code" != 0 ]; then
  echo "tests/hash-server-stderr.sh: 子プロセスが想定外の終了コード $code"
  echo "--- stdout ---"; cat "$OUTF"
  echo "--- stderr ---"; cat "$ERRF"
  fail=1
fi

if ! grep -q '^PROBE-A: stderr after hash_server_start$' "$ERRF"; then
  echo "tests/hash-server-stderr.sh: hash_server_start の後で stderr が消えている（tech-debt #15 の回帰）。"
  echo "  bin/harness の hash_server_start にある bare 'exec ... 2>/dev/null' がシェル全体へ永続適用されていないか確認する。"
  echo "  直し方: { exec 3<>... 4<>...; } 2>/dev/null のようにグループへ包み、fd 2 のリダイレクトをそのブロックの実行中だけに限定する。"
  fail=1
fi

if ! grep -q '^PROBE-B: stderr after hash_server_stop$' "$ERRF"; then
  echo "tests/hash-server-stderr.sh: hash_server_stop の後で stderr が消えている（同じ形の bare exec が原因）。"
  echo "  直し方: hash_server_stop の exec も { exec 3>&- 4>&-; } 2>/dev/null に包む。"
  fail=1
fi

[ "$fail" = 0 ] || exit 1
echo "tests/hash-server-stderr.sh: pass（hash_server_start / hash_server_stop の後も stderr が生きている）"
