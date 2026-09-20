#!/usr/bin/env bash
# tests/seed.sh — seed（harness init が配る雛形）がそのままで通ることを確かめる
#
# 使い方:  bash tests/seed.sh
# 終了コード: 通れば 0、落ちれば 1。
#
# 何を守るか: `harness/checks.seed.sh` が配る検査は、init 直後のプロジェクトで
# 必ず pass しなければならない（決定 0005）。ここが落ちると、以後すべての
# 新規導入が「入れた瞬間に赤い」状態で始まる。
#
# なぜスクリプトなのか: この検証は使い捨てプロジェクトで `harness check` を
# 回す。同じことを `.harness/checks.sh` の 1 行に inline で書くと、`$(...)` の
# エスケープを 1 つ落としただけで checks.sh の読み込み時に展開され、
# harness check が自分自身を再帰的に起動する（2026-09-18 に実際に踏んだ。
# docs/learnings.md を参照）。ファイルに逃がせばエスケープの問題が消える。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

WORK="$(mktemp -d)" || { echo "tests/seed.sh: mktemp -d に失敗した"; exit 2; }
PROJ="$WORK/p"
mkdir -p "$PROJ" || exit 2

(
  cd "$PROJ" &&
  git init -q . &&
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
) >/dev/null 2>&1 || { echo "tests/seed.sh: 使い捨てプロジェクトの作成に失敗した"; exit 2; }

if ! (cd "$PROJ" && bash "$REPO/bin/harness" init --source "$REPO") >/dev/null 2>&1; then
  echo "tests/seed.sh: harness init に失敗した（bash $REPO/bin/harness init --source ${REPO}）"
  exit 1
fi

n="$(grep -c '^check' "$PROJ/.harness/checks.sh" 2>/dev/null || echo 0)"
if [ "$n" -lt 2 ]; then
  echo "tests/seed.sh: seed が配る検査が $n 件しかない。harness/checks.seed.sh に検査が入っているか確認する（決定 0005）。"
  exit 1
fi

out="$(cd "$PROJ" && bash .harness/bin/harness check 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "$out"
  echo
  echo "tests/seed.sh: init 直後のプロジェクトで harness check が落ちた（exit ${rc}）。"
  echo "  harness/checks.seed.sh が配る検査が init 直後に通っていない（決定 0005）。"
  echo "  seed の検査を直すか、上の出力が指す診断（doctor の FAIL 行の「→」）に従って実装を直す。"
  exit 1
fi

echo "tests/seed.sh: pass（seed の検査 $n 件が init 直後のプロジェクトで通る）"
