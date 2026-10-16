#!/usr/bin/env bash
# tests/source-cache.sh — URL の source を手元に持つキャッシュ（~/.cache/agent-harness/）が、
# source の最新に追従することの単体テスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/source-cache.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 発端（2026-10-16）: source のリポジトリを 1 コミットに作り直したら、キャッシュの
# `git pull --ff-only` が「つながらない履歴」で失敗し、`|| true` が握りつぶして古い版を黙って配った。
# キャッシュはハーネスの持ち物なので、ローカルの状態より origin を正とする。
#
# bin/harness は source するとコマンド分岐を走らせない（HARNESS_SOURCED）ので、resolve_source を直接呼ぶ。
# HOME を使い捨てに差し替え、実際の PC のキャッシュには触らない。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)" || { echo "tests/source-cache.sh: mktemp -d に失敗した"; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0; failed=0
failed_names=()

g() { git -c user.email=t@t -c user.name=t "$@"; }

# 使い捨ての origin を作り、1 つ目の版をコミットする
make_origin() { # <dir> <内容>
  mkdir -p "$1" && g -C "$1" init -q -b main . && printf '%s\n' "$2" >"$1/payload.txt" &&
    g -C "$1" add payload.txt && g -C "$1" commit -q -m v1
}

# resolve_source を使い捨ての HOME で呼び、解決したディレクトリの payload.txt を出す
resolve() { # <source> [<ref>]
  (
    export HOME="$WORK/home"
    # shellcheck disable=SC1090
    source "$REPO/bin/harness"
    dir="$(resolve_source "$1" "${2:-}")" || exit 1
    cat "$dir/payload.txt"
  ) 2>"$WORK/stderr"
}

report() { # <名前> <OK なら 0>
  if [ "$2" = 0 ]; then passed=$((passed + 1)); echo "PASS  $1"
  else failed=$((failed + 1)); failed_names+=("$1"); echo "FAIL  $1"; sed 's/^/      /' "$WORK/stderr"; fi
}

# ---------------------------------------------------------------- シナリオ
# SC1: 普通に進んだ（fast-forward できる）source には追従する（今までの動き）
O="$WORK/o1"; rm -rf "$WORK/home"
make_origin "$O" v1
resolve "file://$O" >/dev/null
printf 'v2\n' >"$O/payload.txt" && g -C "$O" commit -q -am v2
got="$(resolve "file://$O")"
[ "$got" = v2 ]; report "SC1: fast-forward できる source の更新に追従する" $?

# SC2: source の履歴が作り直された（つながらない）ときも、黙って古い版を返さず新しい版に追従する
O="$WORK/o2"; rm -rf "$WORK/home"
make_origin "$O" old-with-leak
resolve "file://$O" >/dev/null
g -C "$O" checkout -q --orphan fresh && printf 'new-clean\n' >"$O/payload.txt" &&
  g -C "$O" add payload.txt && g -C "$O" commit -q -m fresh &&
  g -C "$O" branch -q -D main && g -C "$O" branch -q -m main
got="$(resolve "file://$O")"
[ "$got" = new-clean ]; report "SC2: 履歴を作り直した source でも古い版を黙って使わず、新しい版に追従する" $?

# SC3: ref にブランチを指定したときも、作り直された履歴に追従する
O="$WORK/o3"; rm -rf "$WORK/home"
make_origin "$O" v1
g -C "$O" branch -q stable
resolve "file://$O" stable >/dev/null
g -C "$O" checkout -q --orphan fresh && printf 'stable-new\n' >"$O/payload.txt" &&
  g -C "$O" add payload.txt && g -C "$O" commit -q -m fresh &&
  g -C "$O" branch -q -D stable && g -C "$O" branch -q -m stable
got="$(resolve "file://$O" stable)"
[ "$got" = stable-new ]; report "SC3: ref のブランチも作り直された履歴に追従する" $?

# SC4: ref にタグを指定したときは、そのタグの版を返す（ブランチの最新ではない）
O="$WORK/o4"; rm -rf "$WORK/home"
make_origin "$O" tagged
g -C "$O" tag v1
printf 'later\n' >"$O/payload.txt" && g -C "$O" commit -q -am later
got="$(resolve "file://$O" v1)"
[ "$got" = tagged ]; report "SC4: ref のタグはその版を返す" $?

# SC5: 存在しない ref は黙らず失敗する
O="$WORK/o5"; rm -rf "$WORK/home"
make_origin "$O" v1
if resolve "file://$O" no-such-ref >/dev/null; then r=1; else grep -q 'ref が見つからない' "$WORK/stderr"; r=$?; fi
report "SC5: 存在しない ref は失敗し、理由を言う" $r

echo
echo "tests/source-cache.sh: pass=$passed fail=$failed"
[ "$failed" = 0 ] || { printf '  failed: %s\n' "${failed_names[@]}"; exit 1; }
