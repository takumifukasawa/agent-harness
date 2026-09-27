#!/usr/bin/env bash
# tests/eta.sh — harness eta のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/eta.sh [<シナリオ名の部分一致>]
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。フィルタに 1 件も一致しなければ 1。
#
# 対象仕様: docs/spec/task-timing.md（T02: B1/B1b/B2/B3/B4/B6, C2, D1/D2。T03: A3/B6 の追補）。
#   - B1/B1b: 完了数/全体数・経過時間・残りの推定・推定完了時刻（幅、ローカルタイム表示）
#   - B2    : 残りの推定は完了タスクの実測「最小〜最大」を残タスク数に掛ける（単純平均はしない）
#   - B3    : 実績が無い／進行中の題材が無いときは「不明」と言う（数字を捏造しない）
#   - B4    : --json で機械可読な出力も出す
#   - B6    : 記録が欠けているタスク（done/in_progress なのに timings が無い・不完全）を指摘する。
#             T03 で追加: 記録が欠けている（無い）のと、timings の書式を解釈できない（あるが
#             読めない）のは別物として区別する（ETA16/16b）
#   - C2    : レビューは「残数 × 幅」ではなく固定枠（review の 1 件の実測をそのまま使う）
#   - A3    : T03 で追加: timings が「展開形式」（1 フィールド 1 行。python json.dump(indent=2)
#             相当）でも壊れずに読める（ETA15/15b）
#
# 枠は tests/task-timing.sh と同じ: scenario "<名前>" <setup関数> <expect関数>
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

run_eta() { # [args...]
  OUT="$(cd "$PROJ" && bash "$HARNESS" eta "$@" 2>&1)"; CODE=$?
}

# ---------------------------------------------------------------- 時刻の組み立て（GNU/BSD 両対応）
# stages.json の timings は harness task が書く実際の形（1 エントリ 1 行）に合わせる。
epoch_to_iso() { # epoch -> ISO8601 UTC
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  return 1
}
ago_iso() { # N秒前 -> ISO8601 UTC
  local now; now="$(date +%s)"
  epoch_to_iso $((now - $1))
}

# ---------------------------------------------------------------- setup 部品
new_proj_no_state() { # .harness/state/ 自体が無い
  PROJ="$WORK/p"; mkdir -p "$PROJ" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
}

new_proj_state_no_stages() { # .harness/state/ はあるが stages.json が無い
  PROJ="$WORK/p"; mkdir -p "$PROJ/.harness/state" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
}

# stages_body を渡してプロジェクトを作る共通部品。tasks/timings は各シナリオが用意する。
new_proj_with() { # stages_json_text
  PROJ="$WORK/p"; mkdir -p "$PROJ/.harness/state" || return 1
  ( cd "$PROJ" && git init -q . ) >/dev/null 2>&1 || { errors+=("setup: git init に失敗した"); return 1; }
  printf '%s\n' "$1" >"$PROJ/.harness/state/stages.json"
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
  WORK="$(mktemp -d)" || { echo "tests/eta.sh: mktemp -d に失敗した"; exit 2; }
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

# ETA1/ETA2: 案内は harness task と同じ文言を共有する（require_stages_file）。
expect_no_state_dir() {
  run_eta
  expect_code 1
  expect_out '\.harness/state が無い'
  expect_out 'task-orchestrate'
}
scenario "ETA1: .harness/state/ が無ければ黙って失敗せず案内して exit 1" \
  new_proj_no_state expect_no_state_dir

expect_no_stages_file() {
  run_eta
  expect_code 1
  expect_out 'stages\.json が無い'
}
scenario "ETA2: stages.json が無ければ黙って失敗せず案内して exit 1" \
  new_proj_state_no_stages expect_no_stages_file

# ETA3: 未知のオプションは拒否する。
expect_unknown_option() {
  run_eta --bogus
  expect_code 1
  expect_out 'unknown option'
}
scenario "ETA3: 未知のオプションは拒否して exit 1" \
  new_proj_state_no_stages expect_unknown_option
# ↑ state/stages.json 自体が無くても、オプション検証は require_stages_file より前に走る
#   （die は即 exit するので、"stages.json が無い" ではなく "unknown option" が先に出ることを見る）。

# ETA4: tasks が空（1 行の空配列）なら「不明」と言い、捏造しない（B3）。exit 0（異常系ではない）。
new_proj_empty_tasks() {
  new_proj_with '{
  "_doc": "d",
  "tasks": []
}'
}
expect_empty_tasks() {
  run_eta
  expect_code 0
  expect_out '不明'
}
scenario "ETA4: tasks が空なら不明と言う（B3）" new_proj_empty_tasks expect_empty_tasks

expect_empty_tasks_json() {
  run_eta --json
  expect_code 0
  expect_out '"phase": "no_tasks"'
  expect_out '"total_tasks": 0'
}
scenario "ETA4b: tasks が空のとき --json は phase: no_tasks を出す" \
  new_proj_empty_tasks expect_empty_tasks_json

# ETA5: 実績が 1 件も無い（timings 自体が無い）→ 経過・タスク推定とも不明。
new_proj_no_timings() {
  new_proj_with '{
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "todo"
    },
    {
      "id": "T02",
      "status": "todo"
    }
  ]
}'
}
expect_no_timings() {
  run_eta
  expect_code 0
  expect_out '0/2 done'
  expect_out '経過 不明'
  expect_out 'タスクの所要時間の推定: 不明'
  expect_out 'レビューの所要時間の推定: 不明'
  expect_not_out '記録が欠けている'   # todo はまだ着手していないだけなので指摘しない
}
scenario "ETA5: 実績も進行中のタスクも無ければ不明と言う（B3）。todo は記録欠けの指摘対象外" \
  new_proj_no_timings expect_no_timings

# ETA6: 完了 1 件（6 分）+ 実行中 1 件（12 分経過）。残り 1 件の推定は 6〜6 分（サンプル 1 件）。
new_proj_one_sample_in_progress() {
  local t1s t1d t2s
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 30分前 -> 24分前 = 6分
  t2s="$(ago_iso 720)"                            # 12分前から実行中
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"T02\", \"started_at\": \"${t2s}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T02\",
      \"status\": \"in_progress\"
    }
  ]
}"
}
expect_one_sample_in_progress() {
  run_eta
  expect_code 0
  expect_out '1/2 done'
  expect_out '実行中: T02'
  expect_out '12 分経過'
  expect_out '残りタスク: 1 件'
  expect_out '6〜6 分/件'
  expect_out '完了見込み（タスクのみ）'
  expect_out 'レビューの所要時間の推定: 不明'
  expect_out '完了見込み（レビュー込み）: 不明'
}
scenario "ETA6: 完了実績 1 件から残り 1 件の推定を出し、レビューは実績が無いので不明のまま" \
  new_proj_one_sample_in_progress expect_one_sample_in_progress

expect_one_sample_json() {
  run_eta --json
  expect_code 0
  expect_out '"phase": "task_in_progress"'
  expect_out '"done_tasks": 1'
  expect_out '"total_tasks": 2'
  expect_out '"sample_count": 1'
  expect_out '"min_seconds": 360'
  expect_out '"max_seconds": 360'
  expect_out '"review_duration": \{"known": false'
  expect_out '"eta_with_review": \{"known": false'
}
scenario "ETA6b: 同じ状況の --json は known/秒の値が拾える" \
  new_proj_one_sample_in_progress expect_one_sample_json

# ETA7: レビューの実績（1 件）があれば、レビュー込みの完了見込みも出す（C2: 固定枠）。
new_proj_with_review() {
  local t1s t1d t2s revs revd
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 6分
  t2s="$(ago_iso 720)"                            # 12分経過
  revs="$(ago_iso 3600)"; revd="$(ago_iso 2400)"  # 過去のレビュー実測 20分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"T02\", \"started_at\": \"${t2s}\", \"done_at\": null},
    {\"id\": \"review\", \"started_at\": \"${revs}\", \"done_at\": \"${revd}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T02\",
      \"status\": \"in_progress\"
    }
  ]
}"
}
expect_with_review() {
  run_eta
  expect_code 0
  expect_out 'レビューの所要時間の推定: 20〜20 分'
  expect_out '固定枠'
  expect_out '完了見込み（レビュー込み）: [0-9][0-9]:[0-9][0-9]〜[0-9][0-9]:[0-9][0-9]'
}
scenario "ETA7: review の実績 1 件があれば固定枠として完了見込みに足す（C2）" \
  new_proj_with_review expect_with_review

# ETA8: done なのに timings が無い（このリポジトリの T01 相当）→ 記録が欠けていると指摘する（B6）。
new_proj_done_without_record() {
  new_proj_with '{
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "done"
    },
    {
      "id": "T02",
      "status": "todo"
    }
  ]
}'
}
expect_done_without_record() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（done）: 記録が無い'
}
scenario "ETA8: done なのに timings が無いタスクを指摘する（B6）" \
  new_proj_done_without_record expect_done_without_record

expect_done_without_record_json() {
  run_eta --json
  expect_code 0
  expect_out '"id": "T01", "status": "done", "reason": "no_record"'
}
scenario "ETA8b: 同じ状況の --json も missing_records に理由コードを出す" \
  new_proj_done_without_record expect_done_without_record_json

# ETA9: done で timings はあるが done_at が無い（start しただけで done を呼んでいない）。
new_proj_done_missing_done_at() {
  local t1s
  t1s="$(ago_iso 600)"
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    }
  ]
}"
}
expect_done_missing_done_at() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（done）: done_at が記録されていない'
}
scenario "ETA9: done なのに done_at が無いタスクを指摘する（B6）" \
  new_proj_done_missing_done_at expect_done_missing_done_at

# ETA10: in_progress なのに timings が無い。
new_proj_in_progress_without_record() {
  new_proj_with '{
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "in_progress"
    }
  ]
}'
}
expect_in_progress_without_record() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（in_progress）: 記録が無い'
  expect_out '実行中: T01（開始時刻は記録されていない）'
}
scenario "ETA10: in_progress なのに timings が無いタスクを指摘する（B6）" \
  new_proj_in_progress_without_record expect_in_progress_without_record

# ETA11: 完了実績が min/max 異なる 2 件 → 単純平均ではなく幅で出す（B2）。
new_proj_two_samples() {
  local t1s t1d t2s t2d t3s
  t1s="$(ago_iso 3600)"; t1d="$(ago_iso 3240)"   # 6分
  t2s="$(ago_iso 3000)"; t2d="$(ago_iso 1560)"   # 24分
  t3s="$(ago_iso 300)"                            # 実行中 5分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"T02\", \"started_at\": \"${t2s}\", \"done_at\": \"${t2d}\"},
    {\"id\": \"T03\", \"started_at\": \"${t3s}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T02\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T03\",
      \"status\": \"in_progress\"
    },
    {
      \"id\": \"T04\",
      \"status\": \"todo\"
    }
  ]
}"
}
expect_two_samples() {
  run_eta
  expect_code 0
  expect_out '2/4 done'
  expect_out '残りタスク: 2 件'
  # 単純平均（15分）ではなく実測の最小〜最大（6〜24分）をそのまま残数（2 件）に掛ける
  expect_out '6〜24 分/件'
  expect_out '完了実績 2 件'
  expect_out '残り計 12〜48 分'
  expect_not_out '15 分'
}
scenario "ETA11: 実測のばらつきをならさず最小〜最大の幅をそのまま残数に掛ける（B2）" \
  new_proj_two_samples expect_two_samples

# ETA12: 全タスク・レビューとも done → 完了。残り/推定の行は出さない。
new_proj_all_done() {
  local t1s t1d revs revd
  t1s="$(ago_iso 1200)"; t1d="$(ago_iso 840)"
  revs="$(ago_iso 600)"; revd="$(ago_iso 120)"
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"review\", \"started_at\": \"${revs}\", \"done_at\": \"${revd}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    }
  ]
}"
}
expect_all_done() {
  run_eta
  expect_code 0
  expect_out '1/1 done'
  expect_out '完了（タスク・レビューとも done）'
  expect_not_out '残りタスク'
  expect_not_out 'レビューの所要時間の推定'
}
scenario "ETA12: タスク・レビューとも done なら完了と言い、推定行は出さない" \
  new_proj_all_done expect_all_done

# ETA13: 全タスク done だがレビュー未着手 → レビュー待ちと言う。
new_proj_awaiting_review() {
  local t1s t1d
  t1s="$(ago_iso 1200)"; t1d="$(ago_iso 840)"
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"status\": \"done\"
    }
  ]
}"
}
expect_awaiting_review() {
  run_eta
  expect_code 0
  expect_out 'レビュー未着手'
  expect_out 'harness task start review'
  expect_out 'レビューの所要時間の推定: 不明'
}
scenario "ETA13: 全タスク done でレビュー未着手ならそう言い、レビュー推定は不明のまま" \
  new_proj_awaiting_review expect_awaiting_review

# ETA14: --json が JSON として妥当であること（node があるときだけ厳密に検証）。
expect_json_is_valid() {
  run_eta --json
  expect_code 0
  command -v node >/dev/null 2>&1 || return 0
  printf '%s' "$OUT" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' \
    || errors+=("--json の出力が妥当な JSON ではない")
}
scenario "ETA14: --json は妥当な JSON を出す（B4）" \
  new_proj_two_samples expect_json_is_valid

# ETA15: timings が「展開形式」（1 フィールド 1 行。統括が実際に stages.json を
# `python -c "json.dump(..., indent=2)"` で書き換えた後に踏んだ形そのもの）でも読めること。
# 既存のフィクスチャは ETA1〜14 まで全て「1 エントリ 1 行」なので、この穴は原理的に検出できな
# かった（T03 の受け入れ条件 3）。started_at/done_at は固定の実時刻にして、経過時間の分
# （09:55:49 - 09:27:07 = 1722 秒 = 29 分）を「今」に依存させず再現できるようにする。
new_proj_expanded_format() {
  new_proj_with '{
  "timings": [
    {
      "id": "T01",
      "started_at": "2026-09-25T09:27:07Z",
      "done_at": "2026-09-25T09:55:49Z"
    }
  ],
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "done"
    },
    {
      "id": "T02",
      "status": "todo"
    }
  ]
}'
}
expect_expanded_format() {
  run_eta
  expect_code 0
  expect_out '1/2 done'
  expect_not_out '記録が欠けている'
  expect_out '残りタスク: 1 件'
  expect_out '29〜29 分/件'
  expect_out '完了実績 1 件'
  expect_out '残り計 29〜29 分'
}
scenario "ETA15: timings が展開形式（1 フィールド 1 行。python json.dump 相当）でも読める" \
  new_proj_expanded_format expect_expanded_format

expect_expanded_format_json() {
  run_eta --json
  expect_code 0
  expect_out '"sample_count": 1'
  expect_out '"min_seconds": 1722'
  expect_out '"max_seconds": 1722'
  expect_out '"missing_records": \[\]'
  expect_out '"timings_parse_warnings": \[\]'
}
scenario "ETA15b: 同じ展開形式の --json も正しい秒数を拾い、missing_records/timings_parse_warnings とも空" \
  new_proj_expanded_format expect_expanded_format_json

# ETA16: timings のエントリに "id" を読み取れない（キー名が想定と違う）場合は、黙って
# 「記録が無い」と言わず「書式が想定と違う」と言う（T03 の受け入れ条件 4。no-silent-failures）。
# 「記録が無い」と区別がつくことが要求なので、両方の文言を実際に出しつつ書き分ける。
new_proj_unparseable_entry() {
  new_proj_with '{
  "timings": [
    {
      "task_id": "T01",
      "started_at": "2026-09-25T09:27:07Z",
      "done_at": "2026-09-25T09:55:49Z"
    }
  ],
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "done"
    }
  ]
}'
}
expect_unparseable_entry() {
  run_eta
  expect_code 0
  expect_out 'ではなく書式が想定と違う可能性がある'
  expect_out 'id を読み取れないエントリ'
  expect_out 'T01（done）: 記録が無い'
}
scenario "ETA16: id を読み取れない timings エントリは「記録が無い」と区別して警告する（B6）" \
  new_proj_unparseable_entry expect_unparseable_entry

expect_unparseable_entry_json() {
  run_eta --json
  expect_code 0
  expect_out '"timings_parse_warnings": \['
  expect_out 'id を読み取れないエントリ'
}
scenario "ETA16b: 同じ状況の --json は timings_parse_warnings に理由を出す" \
  new_proj_unparseable_entry expect_unparseable_entry_json

# ================================================================ 集計
echo
echo "tests/eta.sh: pass=$passed fail=$failed"
if [ -n "$FILTER" ] && [ $((passed + failed)) -eq 0 ]; then
  echo "  フィルタ「${FILTER}」に一致するシナリオが無かった。"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  上の「直近の出力」と bin/harness の cmd_eta / tasks_extract を突き合わせて直す。"
  echo "  導入コピー（.harness/bin/harness）ではなく bin/harness を直し、bash bin/harness update で同期する。"
  exit 1
fi
