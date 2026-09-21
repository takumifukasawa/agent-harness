#!/usr/bin/env bash
# tests/seed-case.sh — seed-case.sh（harness/scripts/seed-case.sh）の単体テスト
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
# を fs_case_insensitive()（実 FS 依存。ここでは戻り値そのものはテストしない）から切り離し、
# 引数 ci として受け取る形にしてある。ここでは ci を固定して、実ホストの FS が何であっても
# 以下の系統を再現する。
#   1. 衝突あり  （ci=1、dest と大文字小文字だけ違う既存ファイル/ディレクトリがある）
#   2. 衝突なし  （ci=1、dest がそのまま存在する / 何も無い の 2 パターン）
#   3. case を区別する環境（ci=0。衝突しうる既存ファイルがあっても検出しない。B3）
#
# 最終レビュー指摘（2026-09-21）の回帰テストもここに足す。
#   X1: fs_case_insensitive() が $ROOT ではなく OS 既定の一時ディレクトリの FS を見ていた
#       （$ROOT と別ボリュームだと判定を取り違える。偽陽性は git mv 誤案内 = データ損失リスク）。
#       戻り値そのものはホスト依存で当てにできないので、「渡した引数の配下でプローブしている
#       こと」を mktemp をラップして呼び出し引数を記録することで確かめる（fs_case_insensitive
#       自体の判定結果には依存しない）。
#   C1: seed_case_collision() が、ディレクトリ名だけ case 違いでファイル名は完全一致する
#       ネストケース（例: 既存 docs/Plans/README.md、seed 配布先 docs/plans/README.md）を
#       検出しなかった。ファイル名の完全一致だけを見て「衝突ではなく配布済み」と誤判定していた。
#   X2: `find ... -iname | head -1` は、case 違いのファイルが 3 つ以上あるとき、どれを報告するかが
#       find 実装（BSD/GNU/MSYS）依存で非決定的だった。find をラップして「実装が返す順序」を
#       意図的に非ソート順にしても、報告が常にソート済み先頭（決定的な値）になることを確かめる。
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

# --- C1. 衝突あり（ネスト）: ディレクトリ名だけ case 違い、ファイル名は完全一致 ---
# 実機再現（2026-09-21）: docs/Plans/README.md を先に置いて harness init すると、
# seed の docs/plans/README.md が配られず、衝突として検出もされなかった。
mkdir -p "$WORK/nested-collision/docs/Plans"
: >"$WORK/nested-collision/docs/Plans/README.md"
assert_collision "$WORK/nested-collision" "docs/plans/README.md" 1 "docs/Plans/README.md"

# --- C1 回帰の反例: ディレクトリもファイル名も完全一致するネストは衝突ではない ---
mkdir -p "$WORK/nested-no-collision/docs/plans"
: >"$WORK/nested-no-collision/docs/plans/README.md"
assert_collision "$WORK/nested-no-collision" "docs/plans/README.md" 1 ""

# --- X2. 大文字小文字違いが 3 つ以上あるとき、報告が find の返す順序に依存しない ---
# find をラップし、実装が -iname で探した結果を意図的にソート済みでない順で返す。
# 実装が明示的にソートしていれば、find がどんな順で返しても報告は常にソート済み先頭になる。
mkdir -p "$WORK/x2-multi/docs"
: >"$WORK/x2-multi/docs/FOO.txt"
: >"$WORK/x2-multi/docs/foo.TXT"
: >"$WORK/x2-multi/docs/Foo.txt"
FAKEBIN_FIND="$WORK/fakebin-find"
mkdir -p "$FAKEBIN_FIND"
REAL_FIND="$(command -v find)"
{
  echo '#!/usr/bin/env bash'
  echo 'for a in "$@"; do'
  echo '  if [ "$a" = "-iname" ]; then'
  printf '    printf %%s\\\\n %s %s %s\n' \
    "'$WORK/x2-multi/docs/Foo.txt'" "'$WORK/x2-multi/docs/foo.TXT'" "'$WORK/x2-multi/docs/FOO.txt'"
  echo '    exit 0'
  echo '  fi'
  echo 'done'
  printf 'exec "%s" "$@"\n' "$REAL_FIND"
} >"$FAKEBIN_FIND/find"
chmod +x "$FAKEBIN_FIND/find"
got_x2="$(PATH="$FAKEBIN_FIND:$PATH" seed_case_collision "$WORK/x2-multi" "docs/foo.txt" 1)"
want_x2="docs/FOO.txt"
if [ "$got_x2" != "$want_x2" ]; then
  errors+=("seed_case_collision: 大文字小文字違いが複数あるとき find の返す順に依存している（期待 [$want_x2] / 実際 [$got_x2]）")
fi

# --- X1. fs_case_insensitive() が引数で渡したディレクトリの配下でプローブすること ---
# 実際の判定結果（case を区別するか）はホスト依存で当てにできない。ここで確かめるのは
# 「どこでプローブしたか」だけ: mktemp をラップして呼び出し引数を記録し、渡した root が
# 含まれていること（= 一時ディレクトリの既定 FS ではなく $ROOT を見ていること）を確かめる。
FAKEBIN_MKTEMP="$WORK/fakebin-mktemp"
mkdir -p "$FAKEBIN_MKTEMP"
REAL_MKTEMP="$(command -v mktemp)"
MKTEMP_LOG="$WORK/mktemp.log"
: >"$MKTEMP_LOG"
{
  echo '#!/usr/bin/env bash'
  printf 'echo "$@" >>"%s"\n' "$MKTEMP_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_MKTEMP"
} >"$FAKEBIN_MKTEMP/mktemp"
chmod +x "$FAKEBIN_MKTEMP/mktemp"

mkdir -p "$WORK/probe-root"
if PATH="$FAKEBIN_MKTEMP:$PATH" fs_case_insensitive "$WORK/probe-root" >/dev/null 2>&1; then :; fi
if ! grep -qF "$WORK/probe-root" "$MKTEMP_LOG"; then
  errors+=("fs_case_insensitive: 渡した引数（$WORK/probe-root）の配下で mktemp を呼んでいない（一時ディレクトリの既定 FS を見ている可能性。X1）")
fi

# 渡したディレクトリが存在しなければ、実ホストの判定に関わらず「区別する」側（1）へ倒す
if fs_case_insensitive "$WORK/does-not-exist-XYZ" >/dev/null 2>&1; then
  errors+=("fs_case_insensitive: 存在しないディレクトリを渡しても case を区別しない (0) を返した")
fi

# プローブ用に作った一時ディレクトリを後始末していること（$ROOT 配下を汚さない）
if find "$WORK/probe-root" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .; then
  errors+=("fs_case_insensitive: プローブ用の一時ディレクトリを $WORK/probe-root の配下に残したままにしている")
fi

if [ "${#errors[@]}" -gt 0 ]; then
  echo "tests/seed-case.sh: fail"
  for e in "${errors[@]}"; do echo "  - $e"; done
  exit 1
fi
echo "tests/seed-case.sh: pass（seed_case_collision: 衝突あり 2 / 衝突なし 4 / case を区別する環境 1 / find の順序非依存 1、fs_case_insensitive: プローブ先 3 の計 11 シナリオ）"
