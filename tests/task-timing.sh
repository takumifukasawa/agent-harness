#!/usr/bin/env bash
# tests/task-timing.sh — harness task start/done のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/task-timing.sh [<シナリオ名の部分一致>]
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。フィルタに 1 件も一致しなければ 1。
#
# 対象仕様: docs/spec/task-timing.md（T01: A1〜A4, C1, D1/D2）。
#   - A2: 記録は CLI（harness task start/done）で行う
#   - A4/実装ノート: 時刻は ISO 8601 / UTC。`date -d`（GNU 専用）は使わない（tech-debt #8）
#   - A3: 時刻フィールドが無い既存の stages.json でも壊れない
#   - C1: id はタスク（T01 等）でもレビュー（review 等）でもよい。レビューを特別扱いしない
#     （実装は "tasks" 配列を一切見ないので、tasks に無い任意の id でも同じように動くはず）
#   - no-silent-failures: .harness/state/ が無い / stages.json が無い / start と done が
#     対応しない、を黙って通さない
#
# 枠は tests/gc.sh と同じ: scenario "<名前>" <setup関数> <expect関数>
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS="$REPO/bin/harness"
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

run_task() { # [args...]
  OUT="$(cd "$PROJ" && bash "$HARNESS" task "$@" 2>&1)"; CODE=$?
}

# ---------------------------------------------------------------- stages.json から timings を読む部品
stages_file() { printf '%s/.harness/state/stages.json' "$PROJ"; }

# id の timings 行（1 行）を取り出す。無ければ空文字。
# timings のエントリは常に "{\"id\": \"...\"" で始まる 1 行 JSON（timings_render_block が書く形）
# なので、行頭アンカーで絞る。アンカー無しの "\"id\": \"...\"" だけだと、"tasks" 配列側の展開形式
# （1 フィールド 1 行）の id 行にも誤ってマッチし得る（timings が tasks より後ろに元々ある
# stages.json、例えば配布テンプレートそのままの並びで踏む。TT16 で再現・回帰済み）。
timing_line() { # id
  grep -E "^[[:space:]]*\{\"id\": \"$1\"" "$(stages_file)" 2>/dev/null | head -1
}

# id の指定フィールドの値。null なら文字列 "null"、値があれば生の値、id 自体が無ければ "__NOTFOUND__"。
timing_value() { # id field
  local line tok
  line="$(timing_line "$1")"
  if [ -z "$line" ]; then printf '%s' "__NOTFOUND__"; return 0; fi
  tok="$(printf '%s\n' "$line" | sed -E "s/.*\"$2\": (null|\"[^\"]*\").*/\1/")"
  if [ "$tok" = "null" ]; then
    printf 'null'
  else
    tok="${tok#\"}"; tok="${tok%\"}"
    printf '%s' "$tok"
  fi
}

ISO8601_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

expect_timing_iso8601() { # id field
  local v; v="$(timing_value "$1" "$2")"
  printf '%s' "$v" | grep -qE "$ISO8601_RE" || errors+=("${1} の ${2} が ISO8601/UTC ではない: '${v}'")
}
expect_timing_value() { # id field expected
  local v; v="$(timing_value "$1" "$2")"
  [ "$v" = "$3" ] || errors+=("${1} の ${2}: 期待 '$3' / 実際 '${v}'")
}
expect_json_valid_if_node() {
  command -v node >/dev/null 2>&1 || return 0
  node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$(stages_file)" \
    || errors+=("stages.json が壊れた JSON になっている（node で JSON.parse に失敗）")
}

# ---------------------------------------------------------------- setup 部品
# 実物（.harness/state/stages.json）に近い形（tasks に acceptance/spec_refs 等のネストした
# 配列を含む）を fixture にする。timings 抽出が "tasks" 側の "id" を巻き込まないことを兼ねて見る。
STAGES_FIXTURE='{
  "_doc": "タスク一覧。orchestrator は current_task のタスクだけを取り出して読み、終わったぶんは開かない。",
  "tasks": [
    {
      "id": "T01",
      "title": "サンプルタスク（括弧つき）",
      "status": "in_progress",
      "acceptance": ["受け入れ条件 1", "受け入れ条件 2（日本語）"],
      "spec_refs": ["docs/spec/task-timing.md"],
      "result": {
        "commit": null,
        "questions": [],
        "report_path": null,
        "note_for_next": ""
      }
    },
    {
      "id": "T02",
      "title": "2 つめのタスク",
      "status": "todo",
      "acceptance": [],
      "spec_refs": [],
      "depends_on": ["T01"]
    }
  ]
}'

new_proj() { # .harness/state/stages.json ありの git リポジトリ
  PROJ="$WORK/p"; mkdir -p "$PROJ/.harness/state" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
  printf '%s\n' "$STAGES_FIXTURE" >"$PROJ/.harness/state/stages.json"
}

new_proj_no_state() { # .harness/state/ 自体が無い git リポジトリ
  PROJ="$WORK/p"; mkdir -p "$PROJ" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
}

new_proj_state_no_stages() { # .harness/state/ はあるが stages.json が無い
  PROJ="$WORK/p"; mkdir -p "$PROJ/.harness/state" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
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
  WORK="$(mktemp -d)" || { echo "tests/task-timing.sh: mktemp -d に失敗した"; exit 2; }
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

# TT1. A1/A2: start / done が stages.json に ISO8601/UTC の時刻を書く。
expect_start_done_basic() {
  run_task start T01
  expect_code 0
  expect_out 'task start T01:'
  expect_timing_iso8601 T01 started_at
  expect_timing_value T01 done_at null

  run_task done T01
  expect_code 0
  expect_out 'task done T01:'
  expect_timing_iso8601 T01 started_at
  expect_timing_iso8601 T01 done_at
  expect_json_valid_if_node
}
scenario "TT1: start してから done すると started_at/done_at が ISO8601/UTC で記録される" \
  new_proj expect_start_done_basic

# TT2. C1: id は tasks 配列に無い自由な文字列でもよい（review を含めレビューを特別扱いしない）。
expect_review_and_arbitrary_id() {
  run_task start review
  expect_code 0
  expect_timing_iso8601 review started_at

  run_task done review
  expect_code 0
  expect_timing_iso8601 review done_at

  # review だけを特別扱いしていないことを、tasks 配列にも無い別の id でも確かめる
  run_task start adhoc-check
  expect_code 0
  expect_timing_iso8601 adhoc-check started_at
}
scenario "TT2: id はレビュー（review）でも tasks に無い任意の id でもよい（C1・特別扱いしない）" \
  new_proj expect_review_and_arbitrary_id

# TT3. A3 の核心: 既存の "tasks" 配列（ネストした配列・result オブジェクト・日本語・括弧を含む）を
# 一切壊さずに "timings" だけを足し書きする。
expect_preserves_existing_tasks_array() {
  run_task start T01
  expect_code 0
  run_task done T01
  expect_code 0

  grep -qF '"title": "サンプルタスク（括弧つき）"' "$(stages_file)" \
    || errors+=("既存の tasks[0].title が消えた/壊れた")
  grep -qF '"acceptance": ["受け入れ条件 1", "受け入れ条件 2（日本語）"]' "$(stages_file)" \
    || errors+=("既存の tasks[0].acceptance が消えた/壊れた")
  grep -qF '"depends_on": ["T01"]' "$(stages_file)" \
    || errors+=("既存の tasks[1].depends_on が消えた/壊れた")
  grep -qF '"_doc": "タスク一覧。orchestrator は current_task のタスクだけを取り出して読み、終わったぶんは開かない。"' "$(stages_file)" \
    || errors+=("_doc が消えた/壊れた")
  expect_json_valid_if_node
}
scenario "TT3: timings を足しても既存の tasks 配列・_doc は一切変わらない（A3）" \
  new_proj expect_preserves_existing_tasks_array

# TT4: .harness/state/ が無い場合は黙って失敗せず、はっきり案内して exit 1。
expect_no_state_dir() {
  run_task start T01
  expect_code 1
  expect_out '\.harness/state が無い'
  expect_out 'task-orchestrate'
}
scenario "TT4: .harness/state/ が無ければ黙って失敗せず案内して exit 1" \
  new_proj_no_state expect_no_state_dir

# TT5: .harness/state/ はあるが stages.json が無い場合も同様。
expect_no_stages_file() {
  run_task start T01
  expect_code 1
  expect_out 'stages\.json が無い'
}
scenario "TT5: stages.json が無ければ黙って失敗せず案内して exit 1" \
  new_proj_state_no_stages expect_no_stages_file

# TT6: done を start より先に呼んでも黙って通さない（started_at 不明のまま done_at だけ記録し、
# その旨を出力する）。no-silent-failures の「id が見つからない」に対応。
expect_done_without_start() {
  run_task done T03
  expect_code 0
  expect_out 'start 記録が無い'
  expect_timing_value T03 started_at null
  expect_timing_iso8601 T03 done_at
}
scenario "TT6: start していない id に done しても失敗はしないが記録が無いことを言う" \
  new_proj expect_done_without_start

# TT7: start を 2 回呼ぶと上書きされ、上書きしたことを言う（黙って上書きしない）。
# 時刻は秒単位なので、同じ秒内に 2 回呼ぶと started_at の値そのものは変わらないことがある。
# そこは表明しない（仕様は秒単位より細かい精度を求めていない）。ここで確かめるのは
# 「上書きした」という note が出ることと、エントリが 2 行に増えず 1 行のまま保たれること。
expect_double_start() {
  run_task start T01
  run_task start T01
  expect_code 0
  expect_out 'すでに.*start 済み'
  expect_timing_iso8601 T01 started_at
  local n; n="$(grep -c '"id": "T01".*started_at' "$(stages_file)")"
  [ "$n" = "1" ] || errors+=("T01 の timings エントリが ${n} 行ある（1 行のはず。二重 start で行が増えた）")
}
scenario "TT7: 同じ id に 2 回 start すると上書きし、上書きしたことを言う" \
  new_proj expect_double_start

# TT8: done を 2 回呼ぶと上書きされ、上書きしたことを言う。TT7 と同じ理由で時刻の変化は表明しない。
expect_double_done() {
  run_task start T01
  run_task done T01
  run_task done T01
  expect_code 0
  expect_out 'すでに.*done 済み'
  expect_timing_iso8601 T01 done_at
  local n; n="$(grep -c '"id": "T01".*started_at' "$(stages_file)")"
  [ "$n" = "1" ] || errors+=("T01 の timings エントリが ${n} 行ある（1 行のはず。二重 done で行が増えた）")
}
scenario "TT8: 同じ id に 2 回 done すると上書きし、上書きしたことを言う" \
  new_proj expect_double_done

# TT9: id に空白を含む文字列は拒否する（生成する JSON 行への混入を防ぐ）。
expect_invalid_id_space() {
  run_task start "foo bar"
  expect_code 1
  expect_out '使える文字'
  grep -q '"timings"' "$(stages_file)" && errors+=("拒否したはずの id で timings ブロックが作られてしまった")
}
scenario "TT9: id に空白を含む場合は拒否し、stages.json を変更しない" \
  new_proj expect_invalid_id_space

# TT10: id に二重引用符を含む文字列も拒否する（手組み JSON への注入を防ぐ）。
expect_invalid_id_quote() {
  run_task start 'foo"bar'
  expect_code 1
  expect_out '使える文字'
  grep -q '"timings"' "$(stages_file)" && errors+=("拒否したはずの id で timings ブロックが作られてしまった")
}
scenario "TT10: id に二重引用符を含む場合は拒否する（JSON 注入防止）" \
  new_proj expect_invalid_id_quote

# TT11: id を渡さない場合は usage を出して exit 1。
expect_missing_id() {
  run_task start
  expect_code 1
  expect_out 'usage: harness task'
}
scenario "TT11: id を渡さないと usage を出して exit 1" \
  new_proj expect_missing_id

# TT12: start/done 以外のサブコマンドは拒否する。
expect_unknown_subcommand() {
  run_task foo T01
  expect_code 1
  expect_out 'unknown task subcommand'
  expect_out '<start[|]done>'
}
scenario "TT12: start/done 以外のサブコマンドは拒否する" \
  new_proj expect_unknown_subcommand

# TT13: サブコマンド自体を渡さない場合も usage を出して exit 1（黙って何もしない、をしない）。
expect_no_subcommand() {
  run_task
  expect_code 1
  expect_out 'usage: harness task'
}
scenario "TT13: サブコマンドを渡さないと usage を出して exit 1" \
  new_proj expect_no_subcommand

# TT14: 複数の id を独立に記録する（互いに上書き・混線しない）。
expect_multiple_ids_independent() {
  run_task start T01
  run_task start T02
  run_task done T01
  expect_code 0

  expect_timing_iso8601 T01 started_at
  expect_timing_iso8601 T01 done_at
  expect_timing_iso8601 T02 started_at
  expect_timing_value T02 done_at null
}
scenario "TT14: 複数 id の記録は互いに独立している（混線しない）" \
  new_proj expect_multiple_ids_independent

# TT15: 1 回目の start がその場で "timings": [] を先頭に挿入し、既存の内容の前に置く
# （A3: 時刻フィールドが無い既存の stages.json でも壊れずに追加できる）。
expect_first_call_inserts_timings_block() {
  grep -q '"timings"' "$(stages_file)" && errors+=("setup の時点で timings が既にある（fixture が想定と違う）")
  run_task start T01
  expect_code 0
  grep -q '"timings"' "$(stages_file)" || errors+=("start 後に timings ブロックが無い")
  # timings は _doc より前（先頭直後）に挿入される
  local timings_ln doc_ln
  timings_ln="$(grep -n '"timings"' "$(stages_file)" | head -1 | cut -d: -f1)"
  doc_ln="$(grep -n '"_doc"' "$(stages_file)" | head -1 | cut -d: -f1)"
  [ -n "$timings_ln" ] && [ -n "$doc_ln" ] && [ "$timings_ln" -lt "$doc_ln" ] \
    || errors+=("timings が _doc より後ろに挿入された（想定は先頭直後）")
  expect_json_valid_if_node
}
scenario "TT15: 初回の start が既存の stages.json を壊さずに timings ブロックを先頭直後へ挿入する（A3）" \
  new_proj expect_first_call_inserts_timings_block

# TT16: レビュー指摘（T04）— 配布テンプレート（harness/state-template/stages.json）は
# "timings": [] を 1 行で閉じた空配列として持つ。この状態で初めて start すると、
# timings_splice が「開き [ と閉じ ] が同じ行」を考慮せず inblock に居座り続け、
# それ以降の行（_timings_doc、末尾の閉じ }）を丸ごと消してしまう（実機で再現済み）。
new_proj_from_seed_template() {
  PROJ="$WORK/p"; mkdir -p "$PROJ/.harness/state" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
  cp "$REPO/harness/state-template/stages.json" "$PROJ/.harness/state/stages.json" \
    || { errors+=("setup: state-template/stages.json のコピーに失敗した"); return 1; }
  grep -qE '^[[:space:]]*"timings"[[:space:]]*:[[:space:]]*\[\][,]?[[:space:]]*$' "$PROJ/.harness/state/stages.json" \
    || { errors+=("setup: state-template/stages.json の想定（1 行で閉じた空 timings 配列）と違う"); return 1; }
}
expect_seed_template_start_does_not_break_json() {
  run_task start T01
  expect_code 0
  expect_json_valid_if_node
  grep -q '"_timings_doc"' "$(stages_file)" \
    || errors+=("_timings_doc が消えた（timings_splice が閉じ } まで巻き込んで消した疑い）")
  # 末尾がちゃんと閉じていること（node が無い環境でも壊れを検出できるようにする）
  tail -1 "$(stages_file)" | grep -qE '^\}[[:space:]]*$' \
    || errors+=("stages.json の末尾が '}' で終わっていない（JSON が壊れている疑い）")
  expect_timing_iso8601 T01 started_at
}
scenario "TT16: 配布テンプレートの1行空timings配列に初めてstartしてもJSONが壊れない（レビューT04#1）" \
  new_proj_from_seed_template expect_seed_template_start_does_not_break_json

# ================================================================ 集計
echo
echo "tests/task-timing.sh: pass=$passed fail=$failed"
if [ -n "$FILTER" ] && [ $((passed + failed)) -eq 0 ]; then
  echo "  フィルタ「${FILTER}」に一致するシナリオが無かった。"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  上の「直近の出力」と bin/harness の cmd_task / timings_* を突き合わせて直す。"
  echo "  導入コピー（.harness/bin/harness）ではなく bin/harness を直し、bash bin/harness update で同期する。"
  exit 1
fi
