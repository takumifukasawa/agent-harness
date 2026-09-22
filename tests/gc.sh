#!/usr/bin/env bash
# tests/gc.sh — harness gc のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/gc.sh [<シナリオ名の部分一致>]
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。フィルタに 1 件も一致しなければ 1。
#
# なぜ要るか（tech-debt #8）: gc.sh は harness check の経路にも tests/ にも無く、**壊れていても
# 誰も気づかない**状態だった。実際 2026-09-20 に macOS で、日付に依存する判定（handoff の鮮度、
# active な計画の放置日数）が `date -d`（GNU 専用）の失敗で**無言でスキップ**され、gc が
# 「問題なし」と報告していた。エラーも警告も出ないので、仕事の半分をしていないことに気づけない。
# ここが gc の実行経路そのものなので、日付判定が生きていることを毎回機械で確かめる。
#
# 枠: scenario "<名前>" <setup関数> <expect関数>
#   setup 関数 : ${WORK} に docs ツリーを作り、$PROJ を設定する
#   expect 関数: run_gc を呼び、expect_* で表明する
# gc は docs/ と git があれば動くので、harness init（1 回 ≒ 11 秒）は通さない。ペイロード側の
# harness/scripts/gc.sh を直接叩く（正本を検査する。導入コピーは harness update が同期する）。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GC="$REPO/harness/scripts/gc.sh"
FILTER="${1:-}"

passed=0; failed=0
failed_names=()
WORK=""; PROJ=""; OUT=""; CODE=0
errors=()

trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM

# ---------------------------------------------------------------- 表明
expect_code() { # 期待する終了コード
  [ "$CODE" = "$1" ] || errors+=("終了コード: 期待 $1 / 実際 ${CODE}")
}
expect_out() { # 出力にこの正規表現があること
  printf '%s\n' "$OUT" | grep -qE "$1" || errors+=("出力に /$1/ が無い")
}
expect_not_out() { # 出力にこの正規表現が無いこと
  if printf '%s\n' "$OUT" | grep -qE "$1"; then errors+=("出力に /$1/ があってはいけない"); fi
}

run_gc() { # [args...]
  OUT="$(cd "$PROJ" && bash "$GC" "$@" 2>&1)"; CODE=$?
}

# ---------------------------------------------------------------- setup 部品
days_ago() { # N -> YYYY-MM-DD（GNU / BSD 双方で動く。テスト側も date の方言に依存しない）
  date -d "-$1 days" '+%Y-%m-%d' 2>/dev/null && return 0
  date -v"-$1"d '+%Y-%m-%d' 2>/dev/null && return 0
  echo "1970-01-01"
}

new_proj() { # 最小の docs ツリー（索引 + handoff）を持つ git リポジトリ
  PROJ="$WORK/p"; mkdir -p "$PROJ/docs" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
  printf '# index\n\n- [handoff](handoff.md)\n' >"$PROJ/docs/README.md"
  printf '# handoff\n\n最終更新: %s\n' "$(days_ago 1)" >"$PROJ/docs/handoff.md"
}

set_handoff_date() { # <日付文字列>
  printf '# handoff\n\n最終更新: %s\n' "$1" >"$PROJ/docs/handoff.md"
}

new_proj_committed() { # new_proj に加え、handoff/README を 1 回コミットする（commit ベースの鮮度判定の起点を作る）
  new_proj || return 1
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1 ||
    { errors+=("setup: 初回コミットに失敗した"); return 1; }
}

commit_non_docs() { # <n> -> docs/ の外だけを触るコミットを n 回作る（同じコミットで日付は今日のまま）
  local n="$1" i
  mkdir -p "$PROJ/src" || return 1
  for i in $(seq 1 "$n"); do
    printf 'x%s\n' "$i" >"$PROJ/src/f$i.txt"
    ( cd "$PROJ" && git add -A &&
      git -c user.email=t@t -c user.name=t commit -q -m "work $i" ) >/dev/null 2>&1 || return 1
  done
}

commit_docs_only() { # <n> -> docs/ の中（README.md への追記）だけを触るコミットを n 回作る（handoff には触らない）
  local n="$1" i
  for i in $(seq 1 "$n"); do
    printf '<!-- note %s -->\n' "$i" >>"$PROJ/docs/README.md"
    ( cd "$PROJ" && git add -A &&
      git -c user.email=t@t -c user.name=t commit -q -m "docs note $i" ) >/dev/null 2>&1 || return 1
  done
}

# ---------------------------------------------------------------- 枠
scenario() { # <名前> <setup関数> <expect関数>
  local name="$1" setup="$2" expect="$3"
  if [ -n "$FILTER" ]; then
    case "$name" in
      *"$FILTER"*) ;;
      *) return 0;;
    esac
  fi
  errors=(); PROJ=""; OUT=""; CODE=0
  WORK="$(mktemp -d)" || { echo "tests/gc.sh: mktemp -d に失敗した"; exit 2; }
  local setup_rc=0
  "$setup" || setup_rc=$?
  if [ "$setup_rc" -eq 0 ]; then
    "$expect"
  else
    errors+=("setup が失敗した（戻り値 ${setup_rc}）。expect は実行していない")
  fi
  rm -rf "$WORK"
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

# ================================================================ シナリオ

# G1. 日付判定が生きていること。これが落ちるなら gc は日付に依存する判定を**全部**していない。
# （macOS の date に -d が無いため 2026-09-20 まで実際に無言でスキップしていた。tech-debt #8）
setup_stale_handoff() { new_proj && set_handoff_date "$(days_ago 100)"; }
expect_stale_handoff() {
  run_gc
  expect_out '最終更新が 1[0-9][0-9] 日前'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G1: handoff の最終更新が閾値より古ければ日数つきで報告する（日付判定が生きている）" \
  setup_stale_handoff expect_stale_handoff

# G2. 閾値内の handoff は報告しない（G1 が「常に報告する」実装で通ってしまわないようにする）
setup_fresh_handoff() { new_proj && set_handoff_date "$(days_ago 1)"; }
expect_fresh_handoff() {
  run_gc
  expect_not_out '最終更新が'
  expect_out '問題なし'
  expect_code 0
}
scenario "G2: handoff が閾値内なら鮮度を報告しない" setup_fresh_handoff expect_fresh_handoff

# G3. --days で閾値を動かせる（G1/G2 の境界が固定値でないこと）
setup_days_option() { new_proj && set_handoff_date "$(days_ago 20)"; }
expect_days_option() {
  run_gc --days 30
  expect_not_out '最終更新が'
  run_gc --days 10
  expect_out '最終更新が 20 日前'
}
scenario "G3: --days で鮮度の閾値が変わる" setup_days_option expect_days_option

# G4. 日付が読めないときは黙って飛ばさない。tech-debt #8 の本体はここで、
# 「日付判定に失敗しても gc が緑を返す」ことが最大の害だった（誰も気づけない）。
setup_unparsable_date() { new_proj && set_handoff_date "2026/09/01"; }
expect_unparsable_date() {
  run_gc
  expect_out '日付'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G4: 解釈できない日付は無言でスキップせず報告する" setup_unparsable_date expect_unparsable_date

# G7. 日付の後ろに一言添える書き方（「最終更新: 2026-09-20（題材 …）」）は実際にある
# （このリポジトリの docs/handoff.md がそれ）。行の残り全部を日付として扱うと、正しく書かれた
# handoff に対して G4 の「読めない日付」警告が出る＝偽陽性で診断の信用が落ちる。行頭の
# YYYY-MM-DD だけを取る。
setup_dated_with_note() {
  new_proj || return 1
  printf '# handoff\n\n最終更新: %s（題材 cross-env のフェーズ 1）\n' "$(days_ago 100)" >"$PROJ/docs/handoff.md"
}
expect_dated_with_note() {
  run_gc
  expect_out '最終更新が 1[0-9][0-9] 日前'
  expect_not_out '読めなかった'
}
scenario "G7: 日付の後ろに補足が続いても日付として読む（偽陽性を出さない）" \
  setup_dated_with_note expect_dated_with_note

# G5. 放置された計画（git の最終コミット日で判定）。handoff とは別経路の日付判定。
setup_stale_plan() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active"
  printf '# plan\n' >"$PROJ/docs/plans/active/old.md"
  ( cd "$PROJ" && git add -A &&
    GIT_AUTHOR_DATE='2020-01-02T00:00:00 +0000' GIT_COMMITTER_DATE='2020-01-02T00:00:00 +0000' \
      git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: 日付を遡らせたコミットに失敗した"); return 1; }
}
expect_stale_plan() {
  run_gc
  expect_out 'docs/plans/active/old\.md が [0-9]+ 日更新されていない'
}
scenario "G5: active な計画の放置日数を git の最終コミット日から出す" setup_stale_plan expect_stale_plan

# G6. --strict は 1 件でも見つかれば exit 1（CI 用）。既定は exit 0。
setup_strict() { new_proj && set_handoff_date "$(days_ago 100)"; }
expect_strict() {
  run_gc --strict
  expect_code 1
  run_gc
  expect_code 0
}
scenario "G6: --strict は検出があれば exit 1、既定は exit 0" setup_strict expect_strict

# G8. C1a（spec no-silent-failures C）: active な計画のタスク表がすべて done なのに、
# 状態欄が「完了」になっていない＝書き戻し漏れを検出する。表記揺れ（**done** / done）両方を拾う。
setup_plan_table_done_state_not_complete() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  {
    printf '# foo\n\n'
    printf -- '- 開始: 2026-09-01\n'
    printf -- '- 状態: 進行中\n\n'
    printf '## タスク分解（依存順）\n\n'
    printf '| # | タスク | 状態 | 備考 |\n'
    printf '|---|---|---|---|\n'
    printf '| T01 | do thing | **done** | ... |\n'
    printf '| T02 | do other | done | ... |\n'
  } >"$PROJ/docs/plans/active/foo.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_table_done_state_not_complete() {
  run_gc
  expect_out '計画 docs/plans/active/foo\.md のタスク表は行が全部 done なのに状態欄が「完了」になっていない'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G8: 計画のタスク表が全行 done なのに状態欄が完了でなければ報告する（書き戻し漏れ）" \
  setup_plan_table_done_state_not_complete expect_plan_table_done_state_not_complete

# G9. C1b（spec no-silent-failures C）: 状態欄が「完了」なのに active/ に置かれたまま＝畳み忘れを検出する。
setup_plan_state_complete_in_active() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  printf '# bar\n\n- 開始: 2026-09-01\n- 状態: **完了（2026-09-21）**\n' >"$PROJ/docs/plans/active/bar.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_state_complete_in_active() {
  run_gc
  expect_out '計画 docs/plans/active/bar\.md の状態欄が「完了」なのに active/ に置かれたまま'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G9: 計画の状態欄が完了なのに active/ に置かれたままなら報告する（畳み忘れ）" \
  setup_plan_state_complete_in_active expect_plan_state_complete_in_active

# G10. C3（表記揺れでは警告しない）: docs/plans/active/no-silent-failures.md の実物と同じ形
# （タスク表に 進行中 / 未着手 が混在し、状態欄は 進行中）では、G8/G9 のどちらも報告しない。
setup_plan_mixed_states_no_false_positive() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  {
    printf '# baz\n\n'
    printf -- '- 開始: 2026-09-01\n'
    printf -- '- 状態: 進行中\n\n'
    printf '## タスク分解（依存順）\n\n'
    printf '| # | タスク | 状態 | 備考 |\n'
    printf '|---|---|---|---|\n'
    printf '| T01 | task a | 進行中 | ... |\n'
    printf '| T02 | task b | 未着手 | ... |\n'
  } >"$PROJ/docs/plans/active/baz.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_mixed_states_no_false_positive() {
  run_gc
  expect_not_out 'タスク表は行が全部 done なのに状態欄が'
  expect_not_out '状態欄が「完了」なのに active/ に置かれたまま'
  expect_code 0
}
scenario "G10: タスク表に進行中/未着手が混在し状態欄が進行中なら誤検知しない（実物と同じ形）" \
  setup_plan_mixed_states_no_false_positive expect_plan_mixed_states_no_false_positive

# G11. S4（最終レビュー指摘）: C1b の「完了」判定が部分文字列一致だと、状態欄が「未完了」のような
# 実際には未完了の文章でも「畳み忘れ」と誤案内する。状態欄が「完了」で始まる場合だけ拾う。
setup_plan_state_mikanryou_no_false_positive() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  printf '# qux\n\n- 開始: 2026-09-01\n- 状態: 未完了\n' >"$PROJ/docs/plans/active/qux.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_state_mikanryou_no_false_positive() {
  run_gc
  expect_not_out '状態欄が「完了」なのに active/ に置かれたまま'
  expect_code 0
}
scenario "G11: 状態欄が「未完了」なら完了扱いしない（部分文字列一致による誤検知を防ぐ）" \
  setup_plan_state_mikanryou_no_false_positive expect_plan_state_mikanryou_no_false_positive

# G12. S4（最終レビュー指摘）: 状態欄が「進行中（T01完了、T02未着手）」のように、括弧の中に
# 「完了」という語を含むだけの文章でも C1b が誤案内しないこと。タスク表も全 done ではないので
# C1a も出さない（未着手が残っている）。
setup_plan_state_parenthetical_kanryou_no_false_positive() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  {
    printf '# quux\n\n'
    printf -- '- 開始: 2026-09-01\n'
    printf -- '- 状態: 進行中（T01完了、T02未着手）\n\n'
    printf '## タスク分解（依存順）\n\n'
    printf '| # | タスク | 状態 | 備考 |\n'
    printf '|---|---|---|---|\n'
    printf '| T01 | do thing | done | ... |\n'
    printf '| T02 | do other | 未着手 | ... |\n'
  } >"$PROJ/docs/plans/active/quux.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_state_parenthetical_kanryou_no_false_positive() {
  run_gc
  expect_not_out '状態欄が「完了」なのに active/ に置かれたまま'
  expect_not_out 'タスク表は行が全部 done なのに状態欄が'
  expect_code 0
}
scenario "G12: 状態欄が「進行中（…完了…）」でも完了扱いしない（括弧内の部分文字列一致を防ぐ）" \
  setup_plan_state_parenthetical_kanryou_no_false_positive expect_plan_state_parenthetical_kanryou_no_false_positive

# G13. G1（最終レビュー指摘）: タスク表が全 done でも、状態欄が「レビュー中」など作業継続中を
# 表す語（末尾が「中」）なら C1a を出さない。実物（docs/plans/active/no-silent-failures.md）と
# 同じ「**最終レビュー中**（T01〜T03 は全 done。指摘の処理が残っている）」という書き方を再現する。
setup_plan_review_in_progress_no_false_positive() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/plans/active" || return 1
  {
    printf '# corge\n\n'
    printf -- '- 開始: 2026-09-01\n'
    printf -- '- 状態: **最終レビュー中**（T01〜T03 は全 done。指摘の処理が残っている）\n\n'
    printf '## タスク分解（依存順）\n\n'
    printf '| # | タスク | 状態 | 備考 |\n'
    printf '|---|---|---|---|\n'
    printf '| T01 | do thing | done | ... |\n'
    printf '| T02 | do other | **done** | ... |\n'
  } >"$PROJ/docs/plans/active/corge.md"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}
expect_plan_review_in_progress_no_false_positive() {
  run_gc
  expect_not_out 'タスク表は行が全部 done なのに状態欄が'
  expect_not_out '状態欄が「完了」なのに active/ に置かれたまま'
  expect_code 0
}
scenario "G13: タスク表が全 done でも状態欄がレビュー中（末尾が「中」）なら誤検知しない（最終レビュー中の実物）" \
  setup_plan_review_in_progress_no_false_positive expect_plan_review_in_progress_no_false_positive

# G14. A1/A2（spec writeback-sensors A）: docs/handoff.md を最後に触ったコミットより後、
# docs 以外を触ったコミットが既定閾値（10）ちょうどあれば、日付とは無関係に報告する
# （同じ日に何コミットしても「古く」ならない、という日数ベースの穴を埋める）。
setup_commit_freshness_default() {
  new_proj_committed || return 1
  commit_non_docs 10
}
expect_commit_freshness_default() {
  run_gc
  expect_out '最終更新から docs 以外を触ったコミットが 10 件進んでいる'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G14: 既定閾値(10件)ちょうどの非 docs コミットで commit ベースの鮮度を報告する" \
  setup_commit_freshness_default expect_commit_freshness_default

# G15. G14 の境界: 閾値未満（9 件）なら報告しない（「常に報告する」実装で通ってしまわないようにする）
setup_commit_freshness_below_default() {
  new_proj_committed || return 1
  commit_non_docs 9
}
expect_commit_freshness_below_default() {
  run_gc
  expect_not_out '最終更新から docs 以外を触ったコミットが'
  expect_out '問題なし'
  expect_code 0
}
scenario "G15: 既定閾値未満(9件)の非 docs コミットでは commit ベースの鮮度を報告しない" \
  setup_commit_freshness_below_default expect_commit_freshness_below_default

# G16. A2: --commits で閾値を調整できる（--days と同じ流儀）
setup_commit_freshness_option() {
  new_proj_committed || return 1
  commit_non_docs 5
}
expect_commit_freshness_option() {
  run_gc --commits 3
  expect_out '最終更新から docs 以外を触ったコミットが 5 件進んでいる（閾値 3）'
  run_gc --commits 10
  expect_not_out '最終更新から docs 以外を触ったコミットが'
}
scenario "G16: --commits でコミット数ベースの鮮度の閾値が変わる" \
  setup_commit_freshness_option expect_commit_freshness_option

# G17. A3: docs/ だけを触ったコミットは数えない（handoff を直すたびに次の警告が積まれるのを防ぐ）
setup_commit_freshness_docs_only_not_counted() {
  new_proj_committed || return 1
  commit_docs_only 15
}
expect_commit_freshness_docs_only_not_counted() {
  run_gc
  expect_not_out '最終更新から docs 以外を触ったコミットが'
  expect_out '問題なし'
  expect_code 0
}
scenario "G17: docs だけを触ったコミットは commit ベースの鮮度に数えない（A3）" \
  setup_commit_freshness_docs_only_not_counted expect_commit_freshness_docs_only_not_counted

# G18. A4: 日数ベースとコミット数ベースは別々に報告される（どちらの理由で古いのかが読み手に分かる）。
# handoff の内容は初回コミット時点で古い日付にしておき（以後は触らない）、その後 docs 以外の
# コミットを積む。日数は現在のファイル内容から、コミット数は git 履歴から、それぞれ独立に出る。
setup_both_stale() {
  new_proj || return 1
  set_handoff_date "$(days_ago 100)"
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1 ||
    { errors+=("setup: 初回コミットに失敗した"); return 1; }
  commit_non_docs 10
}
expect_both_stale() {
  run_gc
  expect_out '最終更新が 1[0-9][0-9] 日前'
  expect_out '最終更新から docs 以外を触ったコミットが 10 件進んでいる'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G18: 日数ベースとコミット数ベースは別々に報告される（A4）" setup_both_stale expect_both_stale

# G19. handoff がまだ一度もコミットされていない場合は、commit ベースの判定を（クラッシュせず）
# 黙ってスキップする（git log がアンカーを取れないので「〜以降」を数えようがない）。
setup_handoff_never_committed() {
  new_proj  # あえて commit しない
}
expect_handoff_never_committed() {
  run_gc
  expect_not_out '最終更新から docs 以外を触ったコミットが'
  expect_code 0
}
scenario "G19: handoff が未コミットなら commit ベースの鮮度判定をスキップする（クラッシュしない）" \
  setup_handoff_never_committed expect_handoff_never_committed

# ---------------------------------------------------------------- C: spec の状態欄と計画の食い違い
commit_all() { # setup の最後で使う。plans/active/ を放置扱い（未コミット警告）にしないため必ず呼ぶ
  ( cd "$PROJ" && git add -A &&
    git -c user.email=t@t -c user.name=t commit -q -m plan ) >/dev/null 2>&1 ||
    { errors+=("setup: コミットに失敗した"); return 1; }
}

# G20. C1（spec writeback-sensors C）: spec の状態欄が「完了」でないのに、対応する計画
# （`- 関連:` の相対リンクで対応が取れる）が docs/plans/completed/ にある＝書き戻し漏れを検出する。
# 実物: docs/spec/cross-env-support.md（状態「合意済み」）と docs/plans/completed/cross-env.md。
setup_spec_plan_mismatch_completed() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/spec" "$PROJ/docs/plans/completed" || return 1
  printf '# foo\n\n状態: **合意済み**（準備フェーズ完了）\n' >"$PROJ/docs/spec/foo.md"
  printf '# foo\n\n- 状態: **完了（2026-09-21）**\n- 関連: [spec](../../spec/foo.md)\n' \
    >"$PROJ/docs/plans/completed/foo.md"
  commit_all
}
expect_spec_plan_mismatch_completed() {
  run_gc
  expect_out 'docs/spec/foo\.md の状態欄が対応する計画 docs/plans/completed/foo\.md と食い違っている'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G20: spec が未完了なのに対応する計画が completed/ にあれば食い違いを報告する" \
  setup_spec_plan_mismatch_completed expect_spec_plan_mismatch_completed

# G21. spec も計画（completed/ 配置）も「完了」で揃っていれば報告しない（誤検知しない）。
setup_spec_plan_match_completed() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/spec" "$PROJ/docs/plans/completed" || return 1
  printf '# foo\n\n状態: **完了（2026-09-21）**\n' >"$PROJ/docs/spec/foo.md"
  printf '# foo\n\n- 状態: **完了（2026-09-21）**\n- 関連: [spec](../../spec/foo.md)\n' \
    >"$PROJ/docs/plans/completed/foo.md"
  commit_all
}
expect_spec_plan_match_completed() {
  run_gc
  expect_not_out 'の状態欄が対応する計画'
  expect_out '問題なし'
  expect_code 0
}
scenario "G21: spec と計画（completed/）がどちらも完了なら報告しない" \
  setup_spec_plan_match_completed expect_spec_plan_match_completed

# G22. C3: 対応する計画が無い spec（どの計画からも参照されていない）は警告しない。
# 実物: docs/spec/check-speed.md（完了扱いだが専用の計画ファイルを持たない）。
setup_spec_no_matching_plan() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/spec" || return 1
  printf '# foo\n\n状態: **合意済み**\n' >"$PROJ/docs/spec/foo.md"
  commit_all
}
expect_spec_no_matching_plan() {
  run_gc
  expect_not_out 'の状態欄が対応する計画'
  expect_out '問題なし'
  expect_code 0
}
scenario "G22: 対応する計画が無い spec は食い違いを警告しない（C3）" \
  setup_spec_no_matching_plan expect_spec_no_matching_plan

# G23. spec も計画（active/ 配置）もどちらも未完了で揃っていれば報告しない。
setup_spec_plan_match_active() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/spec" "$PROJ/docs/plans/active" || return 1
  printf '# foo\n\n状態: **反復フェーズ**\n' >"$PROJ/docs/spec/foo.md"
  printf '# foo\n\n- 状態: 進行中\n- 関連: [spec](../../spec/foo.md)\n' \
    >"$PROJ/docs/plans/active/foo.md"
  commit_all
}
expect_spec_plan_match_active() {
  run_gc
  expect_not_out 'の状態欄が対応する計画'
  expect_out '問題なし'
  expect_code 0
}
scenario "G23: spec と計画（active/）がどちらも未完了なら報告しない" \
  setup_spec_plan_match_active expect_spec_plan_match_active

# G24. 計画自身の「- 状態:」の文言が古いまま（例: 「進行中」）でも、completed/ という置き場所を
# 実態として判定に使う。文言どうしを比べるだけの実装だと、この実物と同じケース
# （docs/plans/completed/harness-doctor.md の「- 状態: 進行中（T01 から）」）を見逃す。
setup_spec_plan_mismatch_stale_plan_text() {
  new_proj || return 1
  mkdir -p "$PROJ/docs/spec" "$PROJ/docs/plans/completed" || return 1
  printf '# foo\n\n状態: 合意済（詳細は略）\n' >"$PROJ/docs/spec/foo.md"
  printf '# foo\n\n- 状態: 進行中（T01 から）\n- 関連: `docs/spec/foo.md`（合意済 spec）\n' \
    >"$PROJ/docs/plans/completed/foo.md"
  commit_all
}
expect_spec_plan_mismatch_stale_plan_text() {
  run_gc
  expect_out 'docs/spec/foo\.md の状態欄が対応する計画 docs/plans/completed/foo\.md と食い違っている'
  expect_not_out '問題なし'
  expect_code 0
}
scenario "G24: 計画の状態欄の文言が古くても completed/ の置き場所を実態として食い違いを検出する" \
  setup_spec_plan_mismatch_stale_plan_text expect_spec_plan_mismatch_stale_plan_text

# ================================================================ 集計
echo
echo "tests/gc.sh: pass=$passed fail=$failed"
if [ -n "$FILTER" ] && [ $((passed + failed)) -eq 0 ]; then
  echo "  フィルタ「${FILTER}」に一致するシナリオが無かった。"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  gc の出力（上の「直近の出力」）と harness/scripts/gc.sh を突き合わせて直す。"
  echo "  導入コピー（.harness/scripts/gc.sh）ではなく harness/scripts/gc.sh を直し、bash bin/harness update で同期する。"
  exit 1
fi
