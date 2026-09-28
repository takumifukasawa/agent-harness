#!/usr/bin/env bash
# tests/eta.sh — harness eta のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/eta.sh [<シナリオ名の部分一致>]
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。フィルタに 1 件も一致しなければ 1。
#
# 対象仕様: docs/spec/task-timing.md（T02: B1/B1b/B2/B3/B4/B6, C2, D1/D2。T03: A3/B6 の追補）
#          + docs/spec/timing-anywhere.md（T02: B1〜B4。tasks が空でも timings の実績で所要時間・
#            実行中の経過時間を出す。T03: no_tasks 経路の 3 防御の回帰と --json の JSON 妥当性
#            検証の追補）。
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
NOW_EPOCH=0   # ago_iso の基準時刻。scenario() が setup の直前に 1 回だけ date +%s で取り直す（tech-debt #19）。

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
# ago_iso は "date +%s" を毎回叩かず、$NOW_EPOCH（scenario() が setup の直前に 1 回だけ取る。
# 下記参照）を基準にする（tech-debt #19）。
#
# 直していた理由: 1 つの setup 関数が ago_iso を複数回呼び、その差分（例: ago_iso 1800 と
# ago_iso 1440 の差が 6 分になる）を期待値と比べるシナリオが 19 呼び出し中に複数ある
# （ETA6/7/11/24/25/25b 等）。呼ぶたびに date +%s を叩くと、2 回の呼び出しの間で実時刻の
# 秒が 1 つ進むことがあり、期待した 360 秒が実際には 361 秒になって --json の
# "min_seconds": 360 のような厳密一致が落ちる（実測: ETA25 が pre-commit 中で 1 回落ちた）。
# 基準を 1 回だけ取って共有すれば、同じシナリオ内の ago_iso 同士の差は境界をまたいでも
# 常に厳密に一致し、期待値に許容（±1 秒等）を持たせる必要が無い。
ago_iso() { # N秒前 -> ISO8601 UTC（$NOW_EPOCH 基準）
  epoch_to_iso $((NOW_EPOCH - $1))
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
  NOW_EPOCH="$(date +%s)"   # このシナリオの ago_iso 基準時刻（tech-debt #19）。setup の直前に 1 回だけ取る。
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

# ETA4c: レビュー指摘（T04 #3）— tasks が 0 件（phase: no_tasks）のとき、eta_tasks_only /
# eta_with_review が known: true（epoch = 今）を捏造してはいけない（B3）。テキスト出力は
# 正しく「不明」と言うのに --json だけ矛盾していた（remaining_count が偶然 0 になるのを
# 「残り 0 件で確定」と区別できていなかった）。
expect_empty_tasks_json_not_fabricated() {
  run_eta --json
  expect_code 0
  expect_out '"eta_tasks_only": \{"known": false'
  expect_out '"eta_with_review": \{"known": false'
}
scenario "ETA4c: tasks が空のとき eta_tasks_only/eta_with_review の known を捏造しない（レビューT04#3）" \
  new_proj_empty_tasks expect_empty_tasks_json_not_fabricated

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

# node があるときだけ、直近の run_eta --json の $OUT を実際に JSON.parse に通す。
#
# レビュー指摘（T03 #3）: --json の全体的な妥当性検証はこれまで ETA14（tasks/timings とも
# 中身があるフィクスチャ）だけが行っており、no_tasks 経路（records/running_records）は
# regex 一致（expect_out）だけで、構造的に壊れた JSON（例: 末尾要素にも常にカンマを打つ）を
# 検出できなかった（実際に 1 行だけ書き換えて再現・確認済み。report 参照）。ここを 1 箇所に
# 切り出し、no_tasks 系の *_json expect 関数からも呼べるようにする。
assert_valid_json_if_node() {
  command -v node >/dev/null 2>&1 || return 0
  printf '%s' "$OUT" | node -e 'JSON.parse(require("fs").readFileSync(0,"utf8"))' \
    || errors+=("--json の出力が妥当な JSON ではない")
}
# ETA14: --json が JSON として妥当であること（node があるときだけ厳密に検証）。
expect_json_is_valid() {
  run_eta --json
  expect_code 0
  assert_valid_json_if_node
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

# ETA17: レビュー指摘（T04 #2）— review の started_at が非空だが日付として解釈できない値
# （"not-a-real-timestamp" 等）で、done_at だけは妥当なとき、phase 判定が非空チェックだけで
# 「有効な記録」と誤認し、黙って all_done と言ってしまう（no-silent-failures 再発）。
# review_known の計算と同じ iso_to_epoch 検証を phase 判定にも使い、解釈できない場合は
# 警告（timings_parse_warnings）へ回すことを確かめる。
new_proj_review_started_unparseable() {
  new_proj_with '{
  "timings": [
    {"id": "TA", "started_at": "2026-09-27T05:00:00Z", "done_at": "2026-09-27T05:10:00Z"},
    {"id": "review", "started_at": "not-a-real-timestamp", "done_at": "2026-09-27T06:00:00Z"}
  ],
  "_doc": "d",
  "tasks": [
    {
      "id": "TA",
      "status": "done"
    }
  ]
}'
}
expect_review_started_unparseable() {
  run_eta
  expect_code 0
  expect_out 'review の started_at .*を解釈できない'
  # done_at 自体は妥当な値だが、started_at が壊れている以上 review_known（両方揃って初めて
  # 実績とみなす）は成立しないので、黙って「完了」と言い切ってはいけない（B3・自己矛盾の解消）。
  expect_not_out '完了（タスク・レビューとも done）'
}
scenario "ETA17: review の started_at が解釈できない値でも黙って完了と言わず警告する（レビューT04#2）" \
  new_proj_review_started_unparseable expect_review_started_unparseable

expect_review_started_unparseable_json() {
  run_eta --json
  expect_code 0
  expect_out '"timings_parse_warnings": \['
  expect_out 'review の started_at .*を解釈できない'
  # review_duration.known: false と phase が矛盾なく揃っていること（started_at 不明のまま
  # phase: all_done を名乗らない。以前は phase: "all_done" なのに review_duration.known: false
  # という自己矛盾を出していた）。
  expect_out '"review_duration": \{"known": false'
  expect_not_out '"phase": "all_done"'
}
scenario "ETA17b: 同じ状況の --json も timings_parse_warnings に理由を出し、phase を all_done と矛盾させない（レビューT04#2）" \
  new_proj_review_started_unparseable expect_review_started_unparseable_json

# ETA18: レビュー指摘（T04 #2 の対称ケース）— started_at は妥当だが done_at が解釈できない値。
# done_at を信頼できない以上「完了」とは言えないので review_in_progress 側に倒れる。
# ただし黙らせず、done_at が読めなかったことを警告することを確かめる。
new_proj_review_done_unparseable() {
  local revs
  revs="$(ago_iso 600)"
  new_proj_with "{
  \"timings\": [
    {\"id\": \"TA\", \"started_at\": \"2026-09-27T05:00:00Z\", \"done_at\": \"2026-09-27T05:10:00Z\"},
    {\"id\": \"review\", \"started_at\": \"${revs}\", \"done_at\": \"not-a-real-timestamp\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"TA\",
      \"status\": \"done\"
    }
  ]
}"
}
expect_review_done_unparseable() {
  run_eta
  expect_code 0
  expect_out 'review の done_at .*を解釈できない'
  expect_out '実行中: レビュー'
  expect_not_out '完了（タスク・レビューとも done）'
}
scenario "ETA18: review の done_at が解釈できない値でも警告し、完了と誤認しない（レビューT04#2 対称ケース）" \
  new_proj_review_done_unparseable expect_review_done_unparseable

expect_review_done_unparseable_json() {
  run_eta --json
  expect_code 0
  expect_out '"timings_parse_warnings": \['
  expect_out 'review の done_at .*を解釈できない'
  expect_out '"phase": "review_in_progress"'
}
scenario "ETA18b: 同じ状況の --json は phase: review_in_progress のまま timings_parse_warnings に理由を出す（レビューT04#2）" \
  new_proj_review_done_unparseable expect_review_done_unparseable_json

# ETA19: レビュー指摘（review-effectiveness #2）— phase: pending を検証するシナリオが 0 件だった。
# ETA5 と全く同じ入力（実行中のタスクも done も review も無い）が phase: pending を実際に
# 通っているのに、ETA5 はテキストの「経過 不明」等しか見ておらず phase 自体を確認していなかった
# （判定を丸ごと無効化しても検出できなかった）。同じ setup を再利用し、pending 固有の出力を見る。
expect_no_timings_phase_pending_text() {
  run_eta
  expect_code 0
  expect_out '実行中のタスクなし（次のタスク未着手）'
}
scenario "ETA19: 実行中・done・review のいずれも無いとき phase: pending 固有のテキストを出す（レビュー指摘: phase 未検証#1）" \
  new_proj_no_timings expect_no_timings_phase_pending_text

expect_no_timings_phase_pending_json() {
  run_eta --json
  expect_code 0
  expect_out '"phase": "pending"'
  expect_out '"current": \{"kind": "pending"\}'
}
scenario "ETA19b: 同じ状況の --json は phase: pending / current.kind: pending を出す" \
  new_proj_no_timings expect_no_timings_phase_pending_json

# ETA20: レビュー指摘（review-effectiveness #2）— phase: review_in_progress を検証するシナリオが
# 0 件だった。しかも「このリポジトリが今まさにその状態を通った」（review の started_at はあるが
# done_at はまだ無い、書式は正常）という最も基本的な形。ETA17/18 は started_at/done_at の
# 「解釈できない」異常系のついでにこの分岐へ落ちていただけで、正常系だけの単独シナリオは無かった。
new_proj_review_in_progress_clean() {
  local t1s t1d revs
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # T01 は完了済み（6分）
  revs="$(ago_iso 300)"                           # review は 5分前に開始、done_at はまだ null
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"review\", \"started_at\": \"${revs}\", \"done_at\": null}
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
expect_review_in_progress_clean_text() {
  run_eta
  expect_code 0
  expect_out '1/1 done'
  expect_out '実行中: レビュー'
  expect_out '5 分経過'
  expect_not_out 'を解釈できない'
  expect_not_out '記録が欠けている'
}
scenario "ETA20: review が started_at のみ（done_at は null）の正常系で phase: review_in_progress を検証する（レビュー指摘: phase 未検証#1）" \
  new_proj_review_in_progress_clean expect_review_in_progress_clean_text

expect_review_in_progress_clean_json() {
  run_eta --json
  expect_code 0
  expect_out '"phase": "review_in_progress"'
  expect_out '"current": \{"kind": "review", "id": "review", "elapsed_seconds": [0-9]+\}'
  expect_out '"timings_parse_warnings": \[\]'
}
scenario "ETA20b: 同じ状況の --json は phase: review_in_progress を警告なしで出す" \
  new_proj_review_in_progress_clean expect_review_in_progress_clean_json

# ETA21〜24: レビュー指摘（review-effectiveness #3）— B6 の異常系検出 6 分岐のうち
# missing_started_at / unparseable_started_at / unparseable_done_at / done_before_start の
# 4 つは「見逃し方向」（判定を無効化しても検出できない）のシナリオが無かった（no_record と
# missing_done_at の 2 つにしかテストが無かった）。4 分岐それぞれを単独で再現し、(a) 専用の
# reason コードで区別されること、(b) 実績サンプル（sample_min/max）を汚染しないことの両方を見る。

# ETA21: timings のエントリ自体はあるが started_at が null（no_record とは別扱いになること）。
new_proj_missing_started_at() {
  new_proj_with '{
  "timings": [
    {"id": "T01", "started_at": null, "done_at": null}
  ],
  "_doc": "d",
  "tasks": [
    {
      "id": "T01",
      "status": "in_progress"
    }
  ]
}'
}
expect_missing_started_at_text() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（in_progress）: started_at が記録されていない'
  expect_not_out 'T01（in_progress）: 記録が無い'
}
scenario "ETA21: timings は有るが started_at が無いのを missing_started_at として no_record と区別する（レビュー指摘#2・見逃し方向）" \
  new_proj_missing_started_at expect_missing_started_at_text

expect_missing_started_at_json() {
  run_eta --json
  expect_code 0
  expect_out '"id": "T01", "status": "in_progress", "reason": "missing_started_at"'
}
scenario "ETA21b: 同じ状況の --json は reason: missing_started_at を出す" \
  new_proj_missing_started_at expect_missing_started_at_json

# ETA22: started_at が非空だが日付として解釈できない（review 以外＝タスク本体で確認するのは初）。
new_proj_unparseable_started_at() {
  new_proj_with '{
  "timings": [
    {"id": "T01", "started_at": "not-a-real-timestamp", "done_at": "2026-09-27T06:00:00Z"}
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
expect_unparseable_started_at_text() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（done）: started_at .*を解釈できない'
  expect_out 'タスクの所要時間の推定: 不明（完了実績が 0 件）'
}
scenario "ETA22: task の started_at が解釈できない値を unparseable_started_at として区別し、実績サンプルに混ぜない（レビュー指摘#2・見逃し方向）" \
  new_proj_unparseable_started_at expect_unparseable_started_at_text

expect_unparseable_started_at_json() {
  run_eta --json
  expect_code 0
  expect_out '"id": "T01", "status": "done", "reason": "unparseable_started_at"'
  expect_out '"task_duration": \{"known": false, "sample_count": 0'
}
scenario "ETA22b: 同じ状況の --json は reason: unparseable_started_at を出し、sample_count に混ぜない" \
  new_proj_unparseable_started_at expect_unparseable_started_at_json

# ETA23: done_at が非空だが日付として解釈できない（started_at は妥当）。
new_proj_unparseable_done_at() {
  new_proj_with '{
  "timings": [
    {"id": "T01", "started_at": "2026-09-27T05:00:00Z", "done_at": "not-a-real-timestamp"}
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
expect_unparseable_done_at_text() {
  run_eta
  expect_code 0
  expect_out '記録が欠けている'
  expect_out 'T01（done）: done_at .*を解釈できない'
  expect_out 'タスクの所要時間の推定: 不明（完了実績が 0 件）'
}
scenario "ETA23: task の done_at が解釈できない値を unparseable_done_at として区別し、実績サンプルに混ぜない（レビュー指摘#2・見逃し方向）" \
  new_proj_unparseable_done_at expect_unparseable_done_at_text

expect_unparseable_done_at_json() {
  run_eta --json
  expect_code 0
  expect_out '"id": "T01", "status": "done", "reason": "unparseable_done_at"'
  expect_out '"task_duration": \{"known": false, "sample_count": 0'
}
scenario "ETA23b: 同じ状況の --json は reason: unparseable_done_at を出す" \
  new_proj_unparseable_done_at expect_unparseable_done_at_json

# ETA24: done_at が started_at より前（負の所要時間）。T04 のコメントにある通り、この分岐を
# 「反転」すると通常系破壊で拾われてしまうが「無効化」だと無傷になる非対称があるため、あえて
# 正常なサンプル（T01, 6分）と混在させ、サンプル統計（sample_count/min/max）が壊れた T02 の
# 負の所要時間で汚染されないことを直接見る（remaining_count が 0 だと該当の出力行自体が
# スキップされるため、todo の T03 を足して残数を 1 件のまま残す）。
new_proj_done_before_start() {
  local t1s t1d
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 妥当な実績: 6分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"T02\", \"started_at\": \"2026-09-27T06:00:00Z\", \"done_at\": \"2026-09-27T05:00:00Z\"}
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
      \"status\": \"todo\"
    }
  ]
}"
}
expect_done_before_start_text() {
  run_eta
  expect_code 0
  expect_out '2/3 done'
  expect_out '記録が欠けている'
  expect_out 'T02（done）: done_at が started_at より前になっている'
  expect_out '残りタスク: 1 件'
  expect_out '6〜6 分/件'
  expect_out '完了実績 1 件'
  expect_out '残り計 6〜6 分'
}
scenario "ETA24: done_at が started_at より前の記録を done_before_start として除外し、実績サンプルを汚染しない（レビュー指摘#2・見逃し方向）" \
  new_proj_done_before_start expect_done_before_start_text

expect_done_before_start_json() {
  run_eta --json
  expect_code 0
  expect_out '"id": "T02", "status": "done", "reason": "done_before_start"'
  expect_out '"task_duration": \{"known": true, "sample_count": 1, "min_seconds": 360, "max_seconds": 360\}'
}
scenario "ETA24b: 同じ状況の --json は reason: done_before_start を出し、負の所要時間を混ぜない" \
  new_proj_done_before_start expect_done_before_start_json

# ETA25/25b: レビュー指摘（review-effectiveness #4）— strip_strings（JSON 文字列中の不釣り合いな
# 中括弧を無害化する防御。timings_extract/tasks_extract 双方にある）を検証するフィクスチャが
# 無かった。無効化すると tasks_extract が status を取り違え、後続タスクを丸ごと取りこぼす
# （レビュアーが実証）。開き "{" 単独・閉じ "}" 単独の両方向を title に入れて確認する。
#
# 単に total_tasks/done_tasks の件数だけを見ると、strip_strings を無効化したときに depth が
# ずれて「T01 が unknown に化け、空 id の幽霊エントリが T02 の代わりに 1 件出る」という壊れ方を
# しても件数（2 件）がたまたま一致してしまい検出できない（実際に確認済み。閉じ "}" 方向で再現）。
# T01 に実測の timings（task_duration の値まで検証できる）を持たせ、T02 は in_progress かつ
# timings 記録が無い状態にして missing_records に T02 の完全な行が出ることまで確認することで、
# 件数の偶然一致に頼らない。
new_proj_brace_in_title_open() {
  local t1s t1d
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 6分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"title\": \"設定 { 形式のサンプル（閉じ括弧なし）\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T02\",
      \"status\": \"in_progress\"
    }
  ]
}"
}
expect_brace_in_title_open() {
  run_eta --json
  expect_code 0
  expect_out '"total_tasks": 2'
  expect_out '"done_tasks": 1'
  expect_out '"task_duration": \{"known": true, "sample_count": 1, "min_seconds": 360, "max_seconds": 360\}'
  expect_out '"id": "T02", "status": "in_progress", "reason": "no_record"'
}
scenario "ETA25: title に対にならない開き { が入っていても後続タスクを取りこぼさない（strip_strings 防御。レビュー指摘#4）" \
  new_proj_brace_in_title_open expect_brace_in_title_open

new_proj_brace_in_title_close() {
  local t1s t1d
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 6分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"T01\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": [
    {
      \"id\": \"T01\",
      \"title\": \"閉じ括弧のみ } のサンプル\",
      \"status\": \"done\"
    },
    {
      \"id\": \"T02\",
      \"status\": \"in_progress\"
    }
  ]
}"
}
expect_brace_in_title_close() {
  run_eta --json
  expect_code 0
  expect_out '"total_tasks": 2'
  expect_out '"done_tasks": 1'
  expect_out '"task_duration": \{"known": true, "sample_count": 1, "min_seconds": 360, "max_seconds": 360\}'
  expect_out '"id": "T02", "status": "in_progress", "reason": "no_record"'
}
scenario "ETA25b: title に対にならない閉じ } が入っていても後続タスクを取りこぼさない（strip_strings 防御。レビュー指摘#4・反対方向）" \
  new_proj_brace_in_title_close expect_brace_in_title_close

# ETA26: レビュー指摘（review-effectiveness #5）— all_done 時の eta_with_review の JSON 値
# そのものを確認するテストが無かった（ETA12 はテキストの「残り行が出ない」ことしか見ていない）。
# eta_with_review は eta_tasks_only と同じ min_epoch/max_epoch になるはず（review 込みでも
# レビューは既に done なので追加時間 0）。この一致を実測値どうしの比較で確認する（epoch は
# 実行時刻に依存するため固定値をハードコードしない）。
expect_all_done_eta_with_review_matches() {
  run_eta --json
  expect_code 0
  expect_out '"eta_tasks_only": \{"known": true'
  expect_out '"eta_with_review": \{"known": true'
  local tasks_part review_part t_min t_max r_min r_max
  tasks_part="$(printf '%s' "$OUT" | grep -o '"eta_tasks_only": {"known": true, "min_epoch": [0-9]*, "max_epoch": [0-9]*}')"
  review_part="$(printf '%s' "$OUT" | grep -o '"eta_with_review": {"known": true, "min_epoch": [0-9]*, "max_epoch": [0-9]*}')"
  t_min="$(printf '%s' "$tasks_part" | sed -n 's/.*"min_epoch": \([0-9]*\).*/\1/p')"
  t_max="$(printf '%s' "$tasks_part" | sed -n 's/.*"max_epoch": \([0-9]*\).*/\1/p')"
  r_min="$(printf '%s' "$review_part" | sed -n 's/.*"min_epoch": \([0-9]*\).*/\1/p')"
  r_max="$(printf '%s' "$review_part" | sed -n 's/.*"max_epoch": \([0-9]*\).*/\1/p')"
  [ -n "$t_min" ] || errors+=("eta_tasks_only.min_epoch を取得できなかった")
  [ "$t_min" = "$r_min" ] || errors+=("eta_with_review.min_epoch(${r_min}) が eta_tasks_only.min_epoch(${t_min}) と一致しない")
  [ "$t_max" = "$r_max" ] || errors+=("eta_with_review.max_epoch(${r_max}) が eta_tasks_only.max_epoch(${t_max}) と一致しない")
}
scenario "ETA26: all_done 時、eta_with_review の JSON 値が eta_tasks_only と一致することを検証する（レビュー指摘#5）" \
  new_proj_all_done expect_all_done_eta_with_review_matches

# ETA27/27b: レビュー指摘（review-spec #7）— tasks が「1 タスク 1 行」の圧縮形式だと
# tasks_extract が無警告で該当タスクを無視していた（T03 の CHANGELOG は「圧縮 1 行・展開の
# 両方を読める」と書いていたが実態と食い違っていた）。T05 で tasks_extract を timings_extract と
# 同じ非固定位置マッチ（depth==1 のガードを外す）に揃え、圧縮形式でも読めるようにした
# （判断: 「読めるようにする」を選んだ。理由は report 参照）。
new_proj_compressed_tasks() {
  new_proj_with '{
  "_doc": "d",
  "tasks": [
    {"id": "T01", "status": "done"},
    {"id": "T02", "status": "todo"}
  ]
}'
}
expect_compressed_tasks_text() {
  run_eta
  expect_code 0
  expect_out '1/2 done'
}
scenario "ETA27: tasks が圧縮1行形式（1 タスク 1 行）でも取りこぼさず読める（tasks_extract。レビュー指摘#7）" \
  new_proj_compressed_tasks expect_compressed_tasks_text

expect_compressed_tasks_json() {
  run_eta --json
  expect_code 0
  expect_out '"total_tasks": 2'
  expect_out '"done_tasks": 1'
}
scenario "ETA27b: 同じ状況の --json も total_tasks/done_tasks を圧縮形式のまま正しく数える" \
  new_proj_compressed_tasks expect_compressed_tasks_json

# ---------------------------------------------------------------- T02（docs/spec/timing-anywhere.md B1〜B4）
# tasks が空（phase: no_tasks）でも timings の実績が乗っていれば黙って「不明」だけで終わらず、
# 「何分かかったか」（B1）・「実行中のものの経過時間」（B3）を出す。進捗（N/M）は分母が無いので
# 出せないと正直に言う（B2。数字を捏造しない）。

# ETA4d: tasks も timings も空のとき、records / running_records は「実績が無い」ことを
# 捏造せずに表す（known: false, [] のまま）。ETA4/4b/4c と同じフィクスチャで --json だけ追加確認。
expect_empty_tasks_json_records_empty() {
  run_eta --json
  expect_code 0
  expect_out '"records": \{"known": false, "count": 0, "min_seconds": null, "max_seconds": null, "avg_seconds": null\}'
  expect_out '"running_records": \[\]'
}
scenario "ETA4d: tasks/timings とも空のとき records は known:false、running_records は空配列（B1/B3 の捏造防止）" \
  new_proj_empty_tasks expect_empty_tasks_json_records_empty

# ETA28: tasks が空でも、完了した実績が 2 件あれば「件数・最小〜最大・平均」を出す（B1）。
# 進捗（N/M）は依然として出せない・捏造しないことも合わせて確認する（B2）。
new_proj_no_tasks_with_records() {
  local t1s t1d t2s t2d
  t1s="$(ago_iso 3600)"; t1d="$(ago_iso 3240)"   # 360秒 = 6分
  t2s="$(ago_iso 2400)"; t2d="$(ago_iso 660)"     # 1740秒 = 29分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-19\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"debt-20\", \"started_at\": \"${t2s}\", \"done_at\": \"${t2d}\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_with_records_text() {
  run_eta
  expect_code 0
  expect_out '不明'
  expect_not_out '[0-9]+/[0-9]+ done'
  expect_out '記録 2 件（6〜29 分、平均 18 分）'
  expect_out '実行中の記録: 無い'
}
scenario "ETA28: tasks が空でも timings の実績（完了 2 件）から所要時間を出す（B1・B2）" \
  new_proj_no_tasks_with_records expect_no_tasks_with_records_text

expect_no_tasks_with_records_json() {
  run_eta --json
  expect_code 0
  expect_out '"phase": "no_tasks"'
  expect_out '"records": \{"known": true, "count": 2, "min_seconds": 360, "max_seconds": 1740, "avg_seconds": 1050\}'
  expect_out '"running_records": \[\]'
  assert_valid_json_if_node
}
scenario "ETA28b: 同じ状況の --json も records に件数・最小/最大/平均秒を出す（B4）" \
  new_proj_no_tasks_with_records expect_no_tasks_with_records_json

# ETA29: tasks が空で、完了した実績は無いが実行中（done_at が null）の記録が 1 件あれば
# その経過時間を出す（B3）。「完了記録が無い」と「実行中が無い」を混同しない。
new_proj_no_tasks_running_only() {
  local rs
  rs="$(ago_iso 300)"   # 5分経過
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-21\", \"started_at\": \"${rs}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_running_only_text() {
  run_eta
  expect_code 0
  expect_out '完了した記録: まだ無い'
  expect_out '実行中: debt-21（.*開始、5 分経過）'
}
scenario "ETA29: tasks が空でも実行中（done_at が null）の経過時間を出す（B3）" \
  new_proj_no_tasks_running_only expect_no_tasks_running_only_text

expect_no_tasks_running_only_json() {
  run_eta --json
  expect_code 0
  expect_out '"records": \{"known": false, "count": 0, "min_seconds": null, "max_seconds": null, "avg_seconds": null\}'
  expect_out '"running_records": \['
  # elapsed_seconds は「今」との差なので、既存の current.elapsed_seconds（ETA20b）と同じく
  # 厳密な秒数ではなく [0-9]+ で見る（実行時刻のわずかなずれで 300 ちょうどにならないことがある。
  # 完了した記録の所要時間（record_min/max/avg）は ago_iso 同士の差なのでずれず厳密一致で見てよいが、
  # ここだけは cmd_eta 実行時の実際の date +%s に依存するため区別する）。
  expect_out '"id": "debt-21", "elapsed_seconds": [0-9]+'
  assert_valid_json_if_node
}
scenario "ETA29b: 同じ状況の --json は running_records に id と経過秒を出す（B4）" \
  new_proj_no_tasks_running_only expect_no_tasks_running_only_json

# ETA30: 完了 1 件 + 実行中 1 件が同時にある混在ケース。両方とも出す。
new_proj_no_tasks_mixed() {
  local t1s t1d rs
  t1s="$(ago_iso 3600)"; t1d="$(ago_iso 3240)"   # 6分
  rs="$(ago_iso 120)"                              # 実行中 2分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-19\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"debt-22\", \"started_at\": \"${rs}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_mixed_text() {
  run_eta
  expect_code 0
  expect_out '記録 1 件（6〜6 分、平均 6 分）'
  expect_out '実行中: debt-22（.*開始、2 分経過）'
}
scenario "ETA30: tasks が空で完了実績と実行中が同時にあれば両方出す（B1・B3）" \
  new_proj_no_tasks_mixed expect_no_tasks_mixed_text

expect_no_tasks_mixed_json() {
  run_eta --json
  expect_code 0
  expect_out '"records": \{"known": true, "count": 1, "min_seconds": 360, "max_seconds": 360, "avg_seconds": 360\}'
  expect_out '"running_records": \['
  expect_out '"id": "debt-22", "elapsed_seconds": [0-9]+'   # 理由は ETA29b のコメント参照
  assert_valid_json_if_node
}
scenario "ETA30b: 同じ状況の --json も records と running_records の両方を出す" \
  new_proj_no_tasks_mixed expect_no_tasks_mixed_json

# ETA31: tasks が空でも、done_at が「null ではなく解釈できない値」なのを「実行中（null）」と
# 混同しない。記録が欠けている／書式が読めないのとも区別して timings_parse_warnings に出す
# （B6 と同じ原則を no_tasks 経路でも保つ）。
new_proj_no_tasks_unparseable_done_at() {
  local s
  s="$(ago_iso 600)"
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-99\", \"started_at\": \"${s}\", \"done_at\": \"garbage\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_unparseable_done_at_text() {
  run_eta
  expect_code 0
  expect_out '完了した記録: まだ無い'
  expect_out 'debt-99.*解釈できない'
  expect_not_out '実行中: debt-99'
}
scenario "ETA31: tasks が空で done_at が解釈できない値のとき、実行中(null)とも完了実績とも混同せず警告する" \
  new_proj_no_tasks_unparseable_done_at expect_no_tasks_unparseable_done_at_text

expect_no_tasks_unparseable_done_at_json() {
  run_eta --json
  expect_code 0
  expect_out '"records": \{"known": false, "count": 0, "min_seconds": null, "max_seconds": null, "avg_seconds": null\}'
  expect_out '"running_records": \[\]'
  expect_out '"timings_parse_warnings": \['
  expect_out '"debt-99: done_at .garbage. を解釈できない"'
  assert_valid_json_if_node
}
scenario "ETA31b: 同じ状況の --json は records/running_records を汚染せず timings_parse_warnings に出す" \
  new_proj_no_tasks_unparseable_done_at expect_no_tasks_unparseable_done_at_json

# ---------------------------------------------------------------- T03（レビュー指摘#1）
# no_tasks 経路の 3 防御（started_at 欠落／解釈不能／done_before_start）は、tasks 版
# （ETA21/ETA22/ETA24）と同じ穴を no_tasks 版でも塞ぐ。以前は「警告を出さず continue のみ」
# に書き換えても tests/eta.sh 52/52 が green のままだった（.harness/state/reports/
# review-effectiveness.md 指摘#1）。特に done_before_start は、防御を無効化すると負の所要時間が
# そのまま record_min/max/avg に混入する（ETA25b と同型の被害）。

# ETA32: tasks が空で started_at が記録されていない（null）記録を、no_record 版
# （ETA21/21b の tasks 版）と同じ理由で警告し、records/running_records を汚染しない。
new_proj_no_tasks_started_at_missing() {
  new_proj_with '{
  "timings": [
    {"id": "debt-40", "started_at": null, "done_at": null}
  ],
  "_doc": "d",
  "tasks": []
}'
}
expect_no_tasks_started_at_missing_text() {
  run_eta
  expect_code 0
  expect_out 'debt-40: started_at が記録されていない'
  expect_out '完了した記録: まだ無い'
  expect_out '実行中の記録: 無い'
}
scenario "ETA32: tasks が空で started_at が無い記録を警告し、records/running_records を汚染しない（レビュー指摘#1・no_tasks 版）" \
  new_proj_no_tasks_started_at_missing expect_no_tasks_started_at_missing_text

expect_no_tasks_started_at_missing_json() {
  run_eta --json
  expect_code 0
  expect_out '"debt-40: started_at が記録されていない'
  expect_out '"records": \{"known": false, "count": 0, "min_seconds": null, "max_seconds": null, "avg_seconds": null\}'
  expect_out '"running_records": \[\]'
  assert_valid_json_if_node
}
scenario "ETA32b: 同じ状況の --json も records/running_records を空のまま保ち timings_parse_warnings に出す" \
  new_proj_no_tasks_started_at_missing expect_no_tasks_started_at_missing_json

# ETA33: tasks が空で started_at が解釈できない値（ETA22/22b の tasks 版と同型）を no_tasks
# 経路でも区別し、running_records（実行中）にも records（完了）にも混ぜない。
new_proj_no_tasks_unparseable_started_at() {
  new_proj_with '{
  "timings": [
    {"id": "debt-41", "started_at": "garbage", "done_at": null}
  ],
  "_doc": "d",
  "tasks": []
}'
}
expect_no_tasks_unparseable_started_at_text() {
  run_eta
  expect_code 0
  expect_out "debt-41: started_at .garbage. を解釈できない"
  expect_out '完了した記録: まだ無い'
  expect_out '実行中の記録: 無い'
}
scenario "ETA33: tasks が空で started_at が解釈できない記録を区別し、records/running_records に混ぜない（レビュー指摘#1・no_tasks 版）" \
  new_proj_no_tasks_unparseable_started_at expect_no_tasks_unparseable_started_at_text

expect_no_tasks_unparseable_started_at_json() {
  run_eta --json
  expect_code 0
  expect_out '"debt-41: started_at .garbage. を解釈できない"'
  expect_out '"records": \{"known": false, "count": 0, "min_seconds": null, "max_seconds": null, "avg_seconds": null\}'
  expect_out '"running_records": \[\]'
  assert_valid_json_if_node
}
scenario "ETA33b: 同じ状況の --json も records/running_records を空のまま保ち timings_parse_warnings に出す" \
  new_proj_no_tasks_unparseable_started_at expect_no_tasks_unparseable_started_at_json

# ETA34: tasks が空で done_at が started_at より前（負の所要時間）の記録が、有効な完了記録
# 1 件と混在するケース（ETA24/24b の tasks 版と同型）。防御が無効化されると record_count が
# 2 に増え、record_min が負の値で汚染される（ETA25b と同型の被害。レビュー指摘#1 の核心）。
new_proj_no_tasks_done_before_start() {
  local t1s t1d
  t1s="$(ago_iso 1800)"; t1d="$(ago_iso 1440)"   # 妥当な実績: 360秒 = 6分
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-42\", \"started_at\": \"${t1s}\", \"done_at\": \"${t1d}\"},
    {\"id\": \"debt-43\", \"started_at\": \"2026-09-27T06:00:00Z\", \"done_at\": \"2026-09-27T05:00:00Z\"}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_done_before_start_text() {
  run_eta
  expect_code 0
  expect_out 'debt-43: done_at が started_at より前になっている'
  expect_out '記録 1 件（6〜6 分、平均 6 分）'
  expect_out '実行中の記録: 無い'
}
scenario "ETA34: tasks が空で done_before_start の記録を除外し、record_min/max/avg を負の所要時間で汚染しない（レビュー指摘#1・ETA25b と同型・no_tasks 版）" \
  new_proj_no_tasks_done_before_start expect_no_tasks_done_before_start_text

expect_no_tasks_done_before_start_json() {
  run_eta --json
  expect_code 0
  expect_out 'debt-43: done_at が started_at より前になっている'
  expect_out '"records": \{"known": true, "count": 1, "min_seconds": 360, "max_seconds": 360, "avg_seconds": 360\}'
  expect_out '"running_records": \[\]'
  assert_valid_json_if_node
}
scenario "ETA34b: 同じ状況の --json も records を汚染せず timings_parse_warnings に出す" \
  new_proj_no_tasks_done_before_start expect_no_tasks_done_before_start_json

# ---------------------------------------------------------------- T03（レビュー指摘#2）
# ETA29b/30b はいずれも running_records の要素数が 1 件だけで、複数要素の場合の要素間カンマ
# （先頭〜中間は "," が要り、末尾だけ要らない）を一度も検証していなかった。running_records を
# 2 件にしたフィクスチャを追加し、--json の妥当性を node で確認する。
new_proj_no_tasks_two_running() {
  local rs1 rs2
  rs1="$(ago_iso 600)"   # 10分経過
  rs2="$(ago_iso 120)"   # 2分経過
  new_proj_with "{
  \"timings\": [
    {\"id\": \"debt-50\", \"started_at\": \"${rs1}\", \"done_at\": null},
    {\"id\": \"debt-51\", \"started_at\": \"${rs2}\", \"done_at\": null}
  ],
  \"_doc\": \"d\",
  \"tasks\": []
}"
}
expect_no_tasks_two_running_text() {
  run_eta
  expect_code 0
  expect_out '実行中: debt-50（.*開始、10 分経過）'
  expect_out '実行中: debt-51（.*開始、2 分経過）'
}
scenario "ETA35: tasks が空で実行中の記録が複数件あれば全件出す（レビュー指摘#2）" \
  new_proj_no_tasks_two_running expect_no_tasks_two_running_text

expect_no_tasks_two_running_json() {
  run_eta --json
  expect_code 0
  expect_out '\{"id": "debt-50", "elapsed_seconds": [0-9]+\},'
  expect_out '\{"id": "debt-51", "elapsed_seconds": [0-9]+\}$'
  assert_valid_json_if_node
}
scenario "ETA35b: tasks が空で実行中が複数件のとき running_records の要素間カンマが正しく、--json 全体も妥当な JSON のまま（レビュー指摘#2）" \
  new_proj_no_tasks_two_running expect_no_tasks_two_running_json

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
