#!/usr/bin/env bash
# tests/update.sh — harness update の所有権規則のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/update.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 枠:  scenario "<名前>" <setup関数> <expect関数>
#   setup 関数 : $PROJ（導入済みプロジェクトの使い捨てコピー）を壊す
#   expect 関数: run_update などを呼び、expect_* で表明する
# シナリオを足すときは、先に落ちるシナリオを書いてから bin/harness を直す（TDD）。
#
# harness init は 10 秒近くかかるので、テンプレートを 1 回だけ作り、各シナリオはそれを複製する。
#
# ここが守る不変条件（docs/decisions/0002-update-repairs-managed-files.md）:
#   - managed / generated は harness が正本。ローカルの変更は update が元に戻す（変更前は .harness/backup/ へ）
#   - seed はプロジェクトの資産。update は触らない
#   - CLAUDE.md は import スタブ。@AGENTS.md の行だけを保証し、プロジェクトが書いた内容は残す
#   - AGENTS.md は managed ブロックだけを直す。ブロック外は残す
#   - manifest に無いのに存在するファイルは harness の持ち物ではない。上書きせず .harness/conflicts/ に新版を置く
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HVER="$(tr -d '\r\n' <"$REPO/VERSION")"

passed=0; failed=0
failed_names=()
TEMPLATE=""; WORK=""; PROJ=""; OUT=""; CODE=0
errors=()

cleanup() { [ -n "$TEMPLATE" ] && rm -rf "$TEMPLATE"; [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

# ---------------------------------------------------------------- 表明
expect_code() { # 期待する終了コード
  [ "$CODE" = "$1" ] || errors+=("終了コード: 期待 $1 / 実際 $CODE")
}
expect_out() { # 出力にこの正規表現があること
  printf '%s\n' "$OUT" | grep -qE "$1" || errors+=("出力に /$1/ が無い")
}
expect_not_out() { # 出力にこの正規表現が無いこと
  if printf '%s\n' "$OUT" | grep -qE "$1"; then errors+=("出力に /$1/ があってはいけない"); fi
  return 0
}
expect_file_has() { # <PROJ 相対パス> <正規表現>
  grep -qE "$2" "$PROJ/$1" 2>/dev/null || errors+=("$1 に /$2/ が無い")
}
expect_file_lacks() { # <PROJ 相対パス> <正規表現>
  if grep -qE "$2" "$PROJ/$1" 2>/dev/null; then errors+=("$1 に /$2/ が残っている"); fi
  return 0
}
expect_file_eq_payload() { # <PROJ 相対パス> <REPO 相対パス>
  cmp -s "$PROJ/$1" "$REPO/$2" || errors+=("$1 が正本 $2 と一致しない（update が直していない）")
}
expect_file_eq() { # <PROJ 相対パス a> <PROJ 相対パス b>
  cmp -s "$PROJ/$1" "$PROJ/$2" || errors+=("$1 と $2 の内容がずれている")
}
# Git Bash の grep はテキストモードで CR を落とすので、CRLF の検出に grep は使えない（常に「CR 無し」に見える）。
# CR を消したコピーと cmp で突き合わせる。
expect_no_cr() { # <PROJ 相対パス>  改行が LF であること（CRLF 化が直っていること）
  local f="$PROJ/$1" t
  [ -f "$f" ] || { errors+=("$1 が無い"); return 0; }
  t="$(mktemp)"; tr -d '\r' <"$f" >"$t"
  cmp -s "$f" "$t" || errors+=("$1 に CR が残っている（CRLF のまま）")
  rm -f "$t"
  return 0
}
expect_exists() { # <PROJ 相対パス>
  [ -e "$PROJ/$1" ] || errors+=("$1 が無い")
}
expect_no_conflict() { # <PROJ 相対パス>  conflicts への退避で済ませていないこと
  if [ -e "$PROJ/.harness/conflicts/$1.new" ]; then
    errors+=(".harness/conflicts/$1.new がある（managed は退避ではなく復元するはず）")
  fi
  return 0
}
expect_backup_has() { # <PROJ 相対パス> <正規表現>  変更前の内容が backup に残っていること
  local f found=0
  for f in "$PROJ"/.harness/backup/*/"$1"; do
    [ -f "$f" ] && grep -qE "$2" "$f" && found=1
  done
  [ "$found" = 1 ] || errors+=(".harness/backup/<ts>/$1 に変更前の内容が無い（ローカルの変更を黙って捨てている）")
}
expect_no_backup() { # backup ディレクトリを作っていないこと（変更が無いときの update）
  local d
  for d in "$PROJ"/.harness/backup/*/; do
    [ -d "$d" ] && errors+=("変更が無いのに .harness/backup/ を作っている: ${d#"$PROJ"/}")
  done
  return 0
}
# grep -c は 0 件のとき exit 1 を返す。`|| echo 0` を足すと "0\n0" になって整数比較が壊れる（T06 の学び）。
count_lines_with() { # <固定文字列> <PROJ 相対パス> → 整数
  local n; n="$(grep -cF "$1" "$PROJ/$2" 2>/dev/null || true)"; n="${n%%[!0-9]*}"; printf '%s' "${n:-0}"
}
expect_markers_once() { # AGENTS.md の managed マーカーが 1 対だけであること
  local b e
  b="$(count_lines_with '<!-- harness:begin' AGENTS.md)"
  e="$(count_lines_with '<!-- harness:end -->' AGENTS.md)"
  [ "$b" = 1 ] || errors+=("AGENTS.md の begin マーカーが $b 個（1 個であるべき）")
  [ "$e" = 1 ] || errors+=("AGENTS.md の end マーカーが $e 個（1 個であるべき）")
}

# ---------------------------------------------------------------- 実行
run_update() { # 導入コピーの CLI で update する（プロジェクトでの通常の直し方）
  OUT="$(cd "$PROJ" && bash .harness/bin/harness update 2>&1)"; CODE=$?
}
run_update_from_repo() { # 正本側の CLI で update する（同梱コピーが壊れているときの直し方）
  OUT="$(cd "$PROJ" && bash "$REPO/bin/harness" update 2>&1)"; CODE=$?
}
run_status() {
  OUT="$(cd "$PROJ" && bash .harness/bin/harness status 2>&1)"; CODE=$?
}

# ---------------------------------------------------------------- 枠
build_template() { # 使い捨てプロジェクトを 1 つ作って harness init する（各シナリオはこれを複製する）
  TEMPLATE="$(mktemp -d)" || { echo "tests/update.sh: mktemp -d に失敗した"; exit 2; }
  (
    mkdir -p "$TEMPLATE/p" && cd "$TEMPLATE/p" &&
    git init -q . &&
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    printf '# プロジェクト固有のルール\n\nこの行はプロジェクトが書いた。update で消えてはいけない。\n' >AGENTS.md &&
    bash "$REPO/bin/harness" init --source "$REPO"
  ) >/dev/null 2>&1 || { echo "tests/update.sh: テンプレートの harness init に失敗した"; exit 2; }
}

scenario() { # <名前> <setup関数> <expect関数>
  local name="$1" setup="$2" expect="$3"
  errors=(); OUT=""; CODE=0
  WORK="$(mktemp -d)" || { echo "tests/update.sh: mktemp -d に失敗した"; exit 2; }
  PROJ="$WORK/p"
  if ! cp -r "$TEMPLATE/p" "$PROJ" 2>/dev/null; then
    errors+=("setup: テンプレートの複製に失敗した")
  elif "$setup"; then
    "$expect"
  else
    errors+=("setup 関数が失敗した（シナリオを実行できていない）")
  fi
  rm -rf "$WORK"; WORK=""
  if [ "${#errors[@]}" -eq 0 ]; then
    printf 'PASS  %s\n' "$name"; passed=$((passed + 1))
  else
    printf 'FAIL  %s\n' "$name"
    printf '        - %s\n' "${errors[@]}"
    printf '      直近の出力:\n'
    printf '%s\n' "$OUT" | sed 's/^/        | /'
    failed=$((failed + 1)); failed_names+=("$name")
  fi
}

build_template

# ================================================================ シナリオ

# U1. managed をローカルで書き換えた（DESIGN.md の所有権。harness が正本）
break_managed_edit() { echo '# ローカルで足した行' >>"$PROJ/.harness/scripts/check.sh"; }
expect_managed_restored() {
  run_update
  expect_code 0
  expect_out 'restore .*check\.sh'
  expect_file_lacks ".harness/scripts/check.sh" '^# ローカルで足した行$'
  expect_file_eq_payload ".harness/scripts/check.sh" "harness/scripts/check.sh"
  expect_backup_has ".harness/scripts/check.sh" '^# ローカルで足した行$'
  expect_no_conflict ".harness/scripts/check.sh"
}
scenario "U1: 書き換えた managed は正本に戻り、変更前は backup に残る" break_managed_edit expect_managed_restored

# U2. B5: CRLF 化した managed（フィルタ付き git hash-object では「未変更」に見えていた）
break_crlf() { sed -i 's/$/\r/' "$PROJ/.harness/scripts/check.sh"; }
expect_crlf_fixed() {
  run_status
  expect_out 'MODIFIED.*\.harness/scripts/check\.sh'
  run_update
  expect_no_cr ".harness/scripts/check.sh"
  expect_file_eq_payload ".harness/scripts/check.sh" "harness/scripts/check.sh"
}
scenario "U2(B5): CRLF 化した managed を status が MODIFIED と言い、update が LF に戻す" break_crlf expect_crlf_fixed

# U3. B7: AGENTS.md のマーカーの版ずれ
break_marker_version() { sed -i 's/<!-- harness:begin v=[^ ]* -->/<!-- harness:begin v=0.0.1 -->/' "$PROJ/AGENTS.md"; }
expect_marker_version_fixed() {
  run_update
  expect_code 0
  expect_file_has "AGENTS.md" "harness:begin v=$HVER"
  expect_file_lacks "AGENTS.md" 'harness:begin v=0\.0\.1'
  expect_file_has "AGENTS.md" 'この行はプロジェクトが書いた'
  expect_markers_once
}
scenario "U3(B7): AGENTS.md のマーカーの版ずれを update が直す（ブロック外は残す）" break_marker_version expect_marker_version_fixed

# U4. B7: managed ブロックの重複（block_hash が先頭しか見ないので検出すらしていなかった）
break_marker_duplicate() {
  awk 'index($0,"<!-- harness:begin")==1{p=1} p{print} p&&index($0,"<!-- harness:end -->")==1{exit}' \
    "$PROJ/AGENTS.md" >"$WORK/block" || return 1
  { cat "$WORK/block"; echo; cat "$PROJ/AGENTS.md"; } >"$WORK/agents" && mv "$WORK/agents" "$PROJ/AGENTS.md"
}
expect_marker_duplicate_fixed() {
  run_status
  expect_out 'MODIFIED.*AGENTS\.md'
  run_update
  expect_code 0
  expect_markers_once
  expect_file_has "AGENTS.md" 'この行はプロジェクトが書いた'
}
scenario "U4(B7): AGENTS.md の managed ブロック重複を status が検出し、update が 1 つに畳む" break_marker_duplicate expect_marker_duplicate_fixed

# U5. B8: CLAUDE.md の @AGENTS.md import 欠落（CLAUDE.md は import スタブ。中身は捨てない）
break_claude_import() { printf '# プロジェクトのメモ\n\nこの行は残る。\n' >"$PROJ/CLAUDE.md"; }
expect_claude_import_restored() {
  run_update
  expect_code 0
  expect_file_has "CLAUDE.md" '^@AGENTS\.md$'
  expect_file_has "CLAUDE.md" 'この行は残る'
  run_status
  expect_not_out 'MODIFIED.*CLAUDE\.md'
}
scenario "U5(B8): CLAUDE.md の @AGENTS.md 欠落を update が足し、プロジェクトの記述は残す" break_claude_import expect_claude_import_restored

# U6. B8: .claude/skills の drift（.agents/skills が正本）
break_claude_skill_drift() { echo '手で足した行' >>"$PROJ/.claude/skills/harness/SKILL.md"; }
expect_claude_skill_synced() {
  run_update
  expect_code 0
  expect_file_lacks ".claude/skills/harness/SKILL.md" '^手で足した行$'
  expect_file_eq ".claude/skills/harness/SKILL.md" ".agents/skills/harness/SKILL.md"
}
scenario "U6(B8): .claude/skills の drift を update が同期する" break_claude_skill_drift expect_claude_skill_synced

# U7. 回帰: manifest に無いのに存在するファイルは harness の持ち物ではない。上書きしない
break_not_from_harness() {
  local p=".agents/skills/harness/SKILL.md"
  grep -v "\"path\":\"$p\"" "$PROJ/.harness/manifest.json" >"$WORK/m" && mv "$WORK/m" "$PROJ/.harness/manifest.json" || return 1
  printf 'プロジェクトが自分で書いたファイル\n' >"$PROJ/$p"
}
expect_not_from_harness_kept() {
  run_update
  expect_code 0
  expect_out 'CONFLICT'
  expect_file_has ".agents/skills/harness/SKILL.md" 'プロジェクトが自分で書いたファイル'
  expect_exists ".harness/conflicts/.agents/skills/harness/SKILL.md.new"
}
scenario "U7: manifest に無い既存ファイルは上書きせず conflicts に新版を置く" break_not_from_harness expect_not_from_harness_kept

# U8. 回帰: end マーカーだけ消えた AGENTS.md で、ブロック外のプロジェクトの記述を巻き込んで消さない
break_marker_end_missing() {
  grep -v '^<!-- harness:end -->$' "$PROJ/AGENTS.md" >"$WORK/a" && mv "$WORK/a" "$PROJ/AGENTS.md"
}
expect_project_text_kept() {
  run_update
  expect_code 0
  expect_file_has "AGENTS.md" 'この行はプロジェクトが書いた'
  expect_markers_once
  expect_backup_has "AGENTS.md" 'この行はプロジェクトが書いた'
}
scenario "U8: end マーカーが消えた AGENTS.md でもプロジェクトの記述を消さない" break_marker_end_missing expect_project_text_kept

# U9. 変更が無ければ update は何も書き換えない（.harness/bin/harness.cmd の毎回上書きの回帰も兼ねる）
break_nothing() { return 0; }
expect_idempotent() {
  run_update
  expect_code 0
  expect_out 'updated=0 restored=0 unchanged=[0-9]+ seeded=0 conflicts=0'
  expect_not_out 'restore '
  expect_not_out 'CONFLICT'
  expect_no_backup
}
scenario "U9: 変更が無いときの update は上書きも backup もしない" break_nothing expect_idempotent

# U10. generated（.claude/agents/*.md）の drift は再生成で戻る
break_generated_drift() { echo '手で足した行' >>"$PROJ/.claude/agents/implementer.md"; }
expect_generated_regenerated() {
  run_update
  expect_code 0
  expect_file_lacks ".claude/agents/implementer.md" '^手で足した行$'
  expect_file_has ".claude/agents/implementer.md" 'generated by agent-harness'
}
scenario "U10: generated の drift は update の再生成で戻る" break_generated_drift expect_generated_regenerated

# U11. 同梱 CLI が CRLF 化しても、正本側の bin/harness からの update で直せる（壊れた方へ委譲しない）
break_vendored_cli_crlf() { sed -i 's/$/\r/' "$PROJ/.harness/bin/harness"; }
expect_vendored_cli_restored() {
  run_update_from_repo
  expect_code 0
  expect_no_cr ".harness/bin/harness"
  expect_file_eq_payload ".harness/bin/harness" "bin/harness"
}
scenario "U11: CRLF 化した同梱 CLI を正本側の bin/harness からの update で直せる" break_vendored_cli_crlf expect_vendored_cli_restored

# U12. 回帰: seed はプロジェクトの資産。update は触らない
break_seed_edit() { echo 'check fast "project own check" "true"' >>"$PROJ/.harness/checks.sh"; }
expect_seed_kept() {
  run_update
  expect_code 0
  expect_file_has ".harness/checks.sh" 'project own check'
  expect_not_out 'restore .*checks\.sh'
}
scenario "U12: seed（.harness/checks.sh）の編集は update で保持される" break_seed_edit expect_seed_kept

# ================================================================ 集計
echo
echo "tests/update.sh: pass=$passed fail=$failed"
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  update の出力（上の「直近の出力」）と bin/harness の apply_plan を突き合わせて直す。"
  echo "  導入コピー（.harness/bin/harness）ではなく bin/harness を直し、bash bin/harness update で同期する。"
  exit 1
fi
