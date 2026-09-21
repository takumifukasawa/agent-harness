#!/usr/bin/env bash
# harness/scripts/seed-case.sh — 判定: seed の配布先と大文字小文字違いの既存ファイルの衝突（tech-debt #13）
#
# source して使う（実行はしない。関数を定義するだけで副作用は無い）。
#   . harness/scripts/seed-case.sh          # 正本（bin/harness の apply_plan から、$PAYLOAD 経由で読む）
#   . "$(dirname "$0")/seed-case.sh"        # 導入コピー（plan() が .harness/scripts/ へ自動配布するので
#                                             #   doctor.sh の隣に必ず置かれる）
#
# 背景: case を区別しないファイルシステム（macOS / Windows）では、既存の docs/HANDOFF.md が
# あると seed の docs/handoff.md の配布が `[ -f docs/handoff.md ]` で「既にある」と判定されて
# スキップされる。にもかかわらず manifest には docs/handoff.md として記録される。case を区別する
# Linux に持っていくと、その名前のファイルが本当に無いと判定されて harness update が雛形を新たに
# 配り、HANDOFF.md と handoff.md が併存する（docs/tech-debt.md #13。2026-09-21、実プロジェクト
# aesthetic-comparison への導入で発見。その場は git mv で寄せて解消した）。
#
# bin/harness（apply_plan。init / update の出力）と harness/scripts/doctor.sh の両方がこの判定を
# 使う。どちらも元々は独立した bash スクリプトで共通処理を source する形は無かったが、この判定は
# テストから単体で呼べる必要があり（下記）、2 か所に複製すると実装がずれたときに気付けない。
# plan() は harness/scripts/*.sh をそのまま .harness/scripts/*.sh として配るので、この選択で
# 導入先にも自動的に同梱される（plan() 自体の変更は不要）。
#
# テスト容易性: 「このファイルシステムが case を区別するか」は実 FS の挙動そのものなので、
# テストから切り替えられない。そこで判定を 2 段に分ける。
#   1. fs_case_insensitive() … 実 FS を一時ディレクトリで確かめる（呼び出し側が使う）。
#      戻り値はホスト環境に依存するので、テストはこの関数の戻り値そのものは当てにしない。
#   2. seed_case_collision() … 衝突の有無を決める純粋ロジック。「case を区別しないか」は
#      呼び出し側が 1. の結果を引数 ci で渡す。テストは ci を固定するので、実ホストの FS が
#      どちらであっても「衝突あり / 衝突なし / case を区別する環境」の 3 系統を再現できる。
#      ファイル名の一致は `find -name` / `-iname`（readdir が返す生のファイル名どうしの文字列比較。
#      パス解決時に OS が行う case フォールディングは経由しない）で見るので、この判定自体は
#      ホストの実 FS が case を区別するかどうかに左右されない
#      （実機確認 2026-09-21, macOS 15 / APFS 既定ボリューム: `FOO.txt` のみが存在する状態で
#       `[ -e foo.txt ]` は真になるが、`find . -name foo.txt` は `FOO.txt` を拾わない）。

# このファイルシステムは case を区別しないか。
# 一時ディレクトリに小文字のファイルを作り、大文字名で -e を見る。判定できなければ
# 「区別する」側へ倒す（誤検出を避ける。区別する環境では何も報告しない）。
# 戻り値: 0 = 区別しない（衝突の可能性がある） / 1 = 区別する、または判定不能
fs_case_insensitive() {
  local d insensitive=1
  d="$(mktemp -d 2>/dev/null)" || return 1
  : >"$d/harness-case-probe" 2>/dev/null || { rm -rf "$d" 2>/dev/null; return 1; }
  [ -e "$d/HARNESS-CASE-PROBE" ] && insensitive=0
  rm -rf "$d" 2>/dev/null
  return "$insensitive"
}

# root: プロジェクトルート（絶対パス）
# dest_rel: seed の配布先（root からの相対パス。例: docs/handoff.md）
# ci: 呼び出し側が渡す「この環境は case を区別しないか」（1 = 区別しない / それ以外 = 区別する）
#
# dest_rel と大文字小文字だけが違う既存ファイルが同じディレクトリにあれば、その既存ファイルの
# パス（root からの相対）を 1 行標準出力して 0 を返す。無い、または ci が 1 でなければ
# 何も出力せず 1 を返す。dest_rel がそのままの大文字小文字で既に存在する場合も 1 を返す
# （それは衝突ではなく、単に seed が既に配布済みというだけ）。
seed_case_collision() {
  local root="$1" dest_rel="$2" ci="$3" dir base exact found
  [ "$ci" = "1" ] || return 1
  dir="$(dirname "$dest_rel")"; base="$(basename "$dest_rel")"
  [ -d "$root/$dir" ] || return 1
  exact="$(find "$root/$dir" -maxdepth 1 -name "$base" 2>/dev/null | head -1)"
  [ -n "$exact" ] && return 1
  found="$(find "$root/$dir" -maxdepth 1 -iname "$base" 2>/dev/null | head -1)"
  [ -n "$found" ] || return 1
  printf '%s\n' "${found#"$root"/}"
  return 0
}

# 衝突の説明文・直し方（bin/harness と doctor.sh で文言を揃えるための共通ヘルパー）
seed_case_collision_reason() { # dest_rel existing_rel
  printf 'この環境は大文字小文字を区別しないため、seed の配布先 %s は既存の %s と同じファイル扱いになっている。雛形は配っていないが manifest には %s として記録される。case を区別する環境（Linux 等）に持っていくと、%s と %s が別ファイルとして併存する（tech-debt #13）' \
    "$1" "$2" "$1" "$2" "$1"
}
seed_case_collision_fix() { # dest_rel existing_rel
  printf 'git mv %s %s で寄せる（内容を確認してから。自動では変更しない）' "$2" "$1"
}
