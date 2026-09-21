#!/usr/bin/env bash
# tests/seed-case.sh — seed_case_collision()（harness/scripts/seed-case.sh）の単体テスト
# （このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/seed-case.sh
# 終了コード: 通れば 0、落ちれば 1。
#
# なぜ単体テストか（tech-debt #13）: 「このファイルシステムが case を区別するか」は実 FS の
# 挙動そのもので、テストから切り替えられない。実際に harness init / update / doctor を動かして
# 確かめようとすると、テストを走らせるホストの FS が case を区別するかどうかで結果が変わって
# しまい、CI やコントリビュータの環境ごとに再現性が無くなる。
#
# そこで harness/scripts/seed-case.sh の seed_case_collision() は「この環境は case を区別しないか」
# を fs_case_insensitive()（実 FS 依存。ここではテストしない）から切り離し、引数 ci として受け取る
# 形にしてある。ここでは ci を固定して、実ホストの FS が何であっても以下の 3 系統を再現する。
#   1. 衝突あり  （ci=1、dest と大文字小文字だけ違う既存ファイルがある）
#   2. 衝突なし  （ci=1、dest がそのまま存在する / 何も無い の 2 パターン）
#   3. case を区別する環境（ci=0。衝突しうる既存ファイルがあっても検出しない。B3）
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO/harness/scripts/seed-case.sh"

if [ ! -f "$LIB" ]; then
  echo "tests/seed-case.sh: ${LIB} が無い。harness/scripts/seed-case.sh を作る（tech-debt #13）。"
  exit 2
fi
# shellcheck source=../harness/scripts/seed-case.sh
. "$LIB"

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

WORK="$(mktemp -d)" || { echo "tests/seed-case.sh: mktemp -d に失敗した"; exit 2; }

errors=()

# root dest_rel ci expected_existing_rel（衝突なしなら空文字）
assert_collision() {
  local root="$1" dest="$2" ci="$3" want="$4" got rc
  got="$(seed_case_collision "$root" "$dest" "$ci")"; rc=$?
  if [ -n "$want" ]; then
    if [ "$rc" -ne 0 ]; then
      errors+=("dest=$dest ci=$ci: 衝突を検出すべきだが検出しなかった（rc=${rc}）")
    elif [ "$got" != "$want" ]; then
      errors+=("dest=$dest ci=$ci: 衝突先の期待 [$want] / 実際 [$got]")
    fi
  else
    if [ "$rc" -eq 0 ]; then
      errors+=("dest=$dest ci=$ci: 衝突を検出してはいけないのに [$got] を検出した")
    fi
  fi
}

# --- 1. 衝突あり: docs/HANDOFF.md だけが存在し、dest は docs/handoff.md、ci=1 ---
mkdir -p "$WORK/collision/docs"
: >"$WORK/collision/docs/HANDOFF.md"
assert_collision "$WORK/collision" "docs/handoff.md" 1 "docs/HANDOFF.md"

# --- 2a. 衝突なし: docs/handoff.md がそのまま既に存在する（seed 配布済み。同じ名前は衝突ではない） ---
mkdir -p "$WORK/no-collision-exact/docs"
: >"$WORK/no-collision-exact/docs/handoff.md"
assert_collision "$WORK/no-collision-exact" "docs/handoff.md" 1 ""

# --- 2b. 衝突なし: 大文字小文字違いのファイルも何も無い ---
mkdir -p "$WORK/no-collision-empty/docs"
assert_collision "$WORK/no-collision-empty" "docs/handoff.md" 1 ""

# --- 3. case を区別する環境: 大文字小文字違いのファイルがあっても ci=0 なら検出しない（B3） ---
mkdir -p "$WORK/case-sensitive-env/docs"
: >"$WORK/case-sensitive-env/docs/HANDOFF.md"
assert_collision "$WORK/case-sensitive-env" "docs/handoff.md" 0 ""

if [ "${#errors[@]}" -gt 0 ]; then
  echo "tests/seed-case.sh: fail"
  for e in "${errors[@]}"; do echo "  - $e"; done
  exit 1
fi
echo "tests/seed-case.sh: pass（衝突あり 1 / 衝突なし 2 / case を区別する環境 1 の計 4 シナリオ）"
