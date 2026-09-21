#!/usr/bin/env bash
# harness gc — docs の腐敗を機械的に検知して一覧にする（判断と修正はしない。LLM も使わない）。
#
# 使い方:  bash .harness/scripts/gc.sh [--days N] [--strict]
#   --days N   鮮度の閾値（既定 14 日）
#   --strict   1 件でも見つかれば exit 1（CI 用）。既定は常に exit 0
#
# 見るもの:
#   1. docs/handoff.md の「最終更新:」が無い / 雛形のまま / N 日より古い
#   2. docs/README.md（索引）にリンクされた doc が存在しない
#   3. docs/ 直下の .md が索引に無い
#   4. docs/**/*.md の相対リンク切れ
#   5. docs/plans/active/ の計画が N 日更新されていない（git の最終コミット日で判定）
#   6. docs/tech-debt.md に「未着手」が残っている
#   7. .harness/state/progress.json の updated_at が N 日より古い（放置された state）
#   8. harness status の MODIFIED（管理ファイルの drift）
#   9. docs/references/ の取得日が N*6 日（約 3 か月）より古い
#  10. docs/plans/active/ の計画で、タスク表と状態欄が矛盾している
#      （a) タスク表の行がすべて done なのに状態欄が「完了」でも作業継続中（〜中）でもない
#       (b) 状態欄が「完了」で始まる（部分文字列一致ではない）のに active/ のまま）
set -u

DAYS=14; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --days) DAYS="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2
DOCS="docs"
[ -d "$DOCS" ] || { echo "gc: docs/ が無い。harness init で seed される。"; exit 2; }

n=0
report() { # severity message hint
  n=$((n + 1))
  printf '%-5s %s\n      → %s\n' "$1" "$2" "$3"
}

today_epoch=$(date +%s)

# YYYY-MM-DD を epoch 秒（その日の 0 時）にする。date の方言は 2 系統あり、どちらか一方しか通らない:
#   GNU coreutils … date -d "2026-09-01" +%s
#   BSD / macOS   … date -j -f '%Y-%m-%d %H:%M:%S' "2026-09-01 00:00:00" +%s
# 以前は GNU 形式だけを試し、失敗を `|| return 1` で握り潰していた。その結果 macOS では
# **日付に依存する判定（handoff の鮮度・計画の放置日数・state・references）が全部無言で飛び**、
# gc が「問題なし」と報告していた（2026-09-20 に実測。tech-debt #8）。両方言に対応したうえで、
# それでも読めなかった日付は下の集計で必ず報告する（黙って飛ばすのが最大の害だった）。
date_to_epoch() { # YYYY-MM-DD -> epoch 秒
  date -d "$1" +%s 2>/dev/null && return 0
  date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" +%s 2>/dev/null && return 0
  return 1
}

# 読めなかった日付の控えはファイルに貯める。days_since は `d=$(days_since ...)` と
# コマンド置換（= 別プロセス）で呼ばれるので、変数に貯めても呼び出し元には残らない。
UNPARSED_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/harness-gc-unparsed.$$")"
: >"$UNPARSED_FILE"
trap 'rm -f "$UNPARSED_FILE"' EXIT INT TERM

days_since() { # YYYY-MM-DD -> days（読めなければ非ゼロで返し、読めなかった日付を控える）
  local e
  e=$(date_to_epoch "$1") || { printf '%s\n' "$1" >>"$UNPARSED_FILE"; return 1; }
  echo $(( (today_epoch - e) / 86400 ))
}

# 1. handoff の鮮度
if [ -f "$DOCS/handoff.md" ]; then
  upd_raw=$(sed -n 's/^最終更新: *//p' "$DOCS/handoff.md" | head -1 | tr -d '\r')
  # 「最終更新: 2026-09-20（題材 …）」のように日付の後ろへ一言添える書き方が実際にある。
  # 行の残り全部を日付として扱うと、正しく書かれた handoff に「読めない日付」の警告が出る。
  upd=$(printf '%s' "$upd_raw" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -z "$upd" ] && upd="$upd_raw"
  if [ -z "$upd" ]; then
    report WARN "docs/handoff.md に「最終更新:」の行が無い" "session-handoff の手順で日付を書く"
  elif [ "$upd" = "YYYY-MM-DD" ]; then
    report WARN "docs/handoff.md が雛形のまま（最終更新: YYYY-MM-DD）" "session-handoff で現在地を書く"
  else
    d=$(days_since "$upd") && [ "$d" -gt "$DAYS" ] && report WARN "docs/handoff.md の最終更新が ${d} 日前（${upd}）" "現在地が古い。session-handoff で更新するか、休止中なら明記する"
  fi
else
  report ERR "docs/handoff.md が無い" "docs-template/handoff.md から作る"
fi

# 2. 索引のリンク先が存在するか
if [ -f "$DOCS/README.md" ]; then
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in http*|\#*) continue;; esac
    target="$DOCS/${link%%#*}"
    [ -e "$target" ] || report ERR "索引 docs/README.md のリンク先が無い: $link" "doc を作るか、索引の行を消す"
  done < <(grep -oE '\]\(([^)]+)\)' "$DOCS/README.md" | sed -E 's/^\]\((.*)\)$/\1/')
  # 3. 索引に無い doc（docs 直下の .md と、サブディレクトリの README 以外の .md）
  while IFS= read -r f; do
    rel="${f#"$DOCS"/}"
    [ "$rel" = "README.md" ] && continue
    case "$rel" in plans/active/*|plans/completed/*|decisions/*|references/*|roles/*|spec/*|rules/*) continue;; esac  # 各ディレクトリの索引が持つ
    grep -qF "($rel" "$DOCS/README.md" || report WARN "docs/$rel が索引に無い" "docs/README.md に行を足す（索引に無い doc は存在しないものとして扱われる）"
  done < <(find "$DOCS" -maxdepth 1 -name '*.md' | sort)
else
  report ERR "docs/README.md（索引）が無い" "docs-template/README.md から作る"
fi

# 4. docs 内の相対リンク切れ
while IFS= read -r f; do
  dir="$(dirname "$f")"
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in http*|mailto:*|\#*) continue;; esac
    t="${link%%#*}"; [ -z "$t" ] && continue
    [ -e "$dir/$t" ] || report WARN "リンク切れ: $f → $link" "リンク先を直すか、移動先を書く"
  done < <(grep -oE '\]\(([^) ]+)\)' "$f" | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find "$DOCS" -name '*.md' | sort)

# 5. 放置された計画
if [ -d "$DOCS/plans/active" ]; then
  while IFS= read -r f; do
    last=$(git log -1 --format=%cs -- "$f" 2>/dev/null)
    [ -z "$last" ] && { report WARN "計画 $f が未コミット" "コミットする（git から辿れて初めて次のセッションの事実になる）"; continue; }
    d=$(days_since "$last") && [ "$d" -gt "$DAYS" ] && report WARN "計画 $f が ${d} 日更新されていない（最終コミット ${last}）" "進めるか、completed/ へ移すか、handoff に休止と書く"
  done < <(find "$DOCS/plans/active" -name '*.md' | sort)
fi

# 6. 負債の放置
if [ -f "$DOCS/tech-debt.md" ]; then
  c=$(grep -c '未着手' "$DOCS/tech-debt.md" || true)
  # 雛形の例示行（"例:" を含む）は数えない
  ex=$(grep '未着手' "$DOCS/tech-debt.md" | grep -c '例:' || true)
  c=$((c - ex))
  [ "$c" -gt 0 ] && report INFO "docs/tech-debt.md に未着手の負債が ${c} 件" "小さく継続的に返す。放置するなら理由を書く"
fi

# 7. 放置された state
if [ -f ".harness/state/progress.json" ]; then
  upd=$(sed -n 's/.*"updated_at": *"\([^"]*\)".*/\1/p' .harness/state/progress.json | head -1)
  if [ -n "$upd" ] && [ "$upd" != "YYYY-MM-DD" ]; then
    d=$(days_since "$upd") && [ "$d" -gt "$DAYS" ] && report WARN ".harness/state/progress.json が ${d} 日更新されていない" "進めるか、確定事項を docs に書き戻して state を捨てる"
  fi
fi

# 8. 管理ファイルの drift
if [ -f ".harness/bin/harness" ]; then
  mod=$(bash .harness/bin/harness status 2>/dev/null | grep -cE '^  (managed|merge|generated) +MODIFIED' || true)
  [ "$mod" -gt 0 ] && report WARN "ハーネス管理ファイルの手変更が ${mod} 件（harness status）" "harness diff で見て、汎用なら upstream、固有なら AGENTS.md のプロジェクト領域へ"
fi

# 9. 古い外部知識
if [ -f "$DOCS/references/README.md" ]; then
  while IFS= read -r dt; do
    d=$(days_since "$dt") && [ "$d" -gt $((DAYS * 6)) ] && report INFO "docs/references/ に取得から ${d} 日経った知識がある（${dt}）" "元を見直すか、腐っていないか確認する"
  done < <(grep -oE '\| *[0-9]{4}-[0-9]{2}-[0-9]{2} *\|' "$DOCS/references/README.md" | tr -d '| ')
fi

# 10. 計画のタスク表と状態欄の矛盾（統括自身の書き戻し漏れを機械で見る。spec no-silent-failures C）
#     見るのは合意済みの 2 つだけ（C3: 表記揺れでは警告しない。広げない）:
#       (a) タスク表の行がすべて `done` なのに、状態欄が「完了」になっていない（＝書き戻し忘れ）
#       (b) 状態欄が「完了」なのに active/ に置かれたまま（＝畳み忘れ）
plan_state_value() { # <file> -> 「- 状態:」行の値（1 行。無ければ空）
  sed -n 's/^- *状態: *//p' "$1" | head -1
}

plan_state_core() { # <state> -> 装飾（**強調**）と括弧の注記を落とした中核語だけ
  # 先に括弧の注記を落としてから前後の空白・強調記号を剥がす。逆順だと「**レビュー中**（…）」の
  # ように強調の閉じ ** が括弧の手前に来る書き方で、末尾の ** が剥がれずに残ってしまう。
  printf '%s' "$1" |
    sed -E 's/[（(].*//' |
    sed -E 's/^\*+//; s/\*+$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

plan_state_is_complete() { # <state> -> 真: 状態欄が「完了」を表す（中核語が「完了」で始まる）
  # 部分文字列一致にすると「未完了」「進行中（T01完了、T02未着手）」のように実際には
  # 未完了の文章まで拾ってしまう（レビュー指摘 S4）。中核語の先頭が「完了」の場合だけ拾う。
  case "$(plan_state_core "$1")" in 完了*) return 0;; esac
  return 1
}

plan_state_is_ongoing() { # <state> -> 真: 「〜レビュー中」等、最終レビューが正常に進行中を表す語
  # C1a はタスク表が全 done なのに状態欄が「完了」でないケースを拾う。task-orchestrate の手順
  # （docs/roles/、.agents/skills/task-orchestrate/SKILL.md）では実装が全部終わってから最終
  # レビューを 1 回回すので、「タスク表は全 done・状態欄はレビュー中」は正常な途中状態であり、
  # ここで警告すると C3（誤検知で既存の指摘を埋もれさせない）に反する（レビュー指摘 G1。実物:
  # docs/plans/active/no-silent-failures.md の「**最終レビュー中**（…）」）。
  # 一方 docs/plans/README.md の雛形にある他の状態（計画中/進行中/ブロック中）は、タスク表が
  # 全 done なら矛盾したままなので除外しない（「〜中」全般を継続中扱いすると、素の書き戻し忘れ
  # ＝「進行中」のまま放置、を見逃してしまう。tests/gc.sh の G8 が回帰を止める）。よって
  # 「レビュー中」に限定して継続中とみなす。
  case "$(plan_state_core "$1")" in *レビュー中) return 0;; esac
  return 1
}

plan_state_col() { # <file> -> タスク表で「状態」列の配列添字（0-indexed。列が無ければ空）
  local header cells cell idx col
  header=$(grep -m1 -E '^\|.*状態.*\|' "$1") || return 0
  idx=0; col=""
  IFS='|' read -ra cells <<<"$header"
  for cell in "${cells[@]}"; do
    cell=$(printf '%s' "$cell" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    if [ "$cell" = "状態" ]; then col=$idx; break; fi
    idx=$((idx + 1))
  done
  echo "$col"
}

plan_all_tasks_done() { # <file> <col> -> 真: タスク行（先頭列が T+数字）が 1 件以上あり全部 done
  local f="$1" col="$2" any=0 line cells first status
  [ -n "$col" ] || return 1
  while IFS= read -r line; do
    IFS='|' read -ra cells <<<"$line"
    first=$(printf '%s' "${cells[1]:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    case "$first" in T[0-9]*) ;; *) continue;; esac
    any=1
    status=$(printf '%s' "${cells[$col]:-}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^\*+//; s/\*+$//')
    case "$status" in [Dd][Oo][Nn][Ee]*) ;; *) return 1;; esac
  done < <(grep -E '^\|' "$f")
  [ "$any" = 1 ]
}

if [ -d "$DOCS/plans/active" ]; then
  while IFS= read -r f; do
    state=$(plan_state_value "$f")
    if plan_state_is_complete "$state"; then
      report WARN "計画 $f の状態欄が「完了」なのに active/ に置かれたまま" "docs/plans/completed/ へ移す（畳み忘れ）"
    else
      col=$(plan_state_col "$f")
      if [ -n "$col" ] && plan_all_tasks_done "$f" "$col" && ! plan_state_is_ongoing "$state"; then
        report WARN "計画 $f のタスク表は行が全部 done なのに状態欄が「完了」になっていない" "状態欄を完了に書き戻すか、まだなら理由を書く"
      fi
    fi
  done < <(find "$DOCS/plans/active" -name '*.md' | sort)
fi

# 読めなかった日付は必ず出す。日付判定が効いていないまま「問題なし」と言うのが一番害が大きい
# （gc が仕事の半分をしていないことに誰も気づけない。tech-debt #8 の本体）。
if [ -s "$UNPARSED_FILE" ]; then
  bad="$(sort -u "$UNPARSED_FILE" | tr '\n' ' ')"
  report WARN "日付として読めなかった記述がある: ${bad}" \
    "YYYY-MM-DD 形式で書く（この日付に依存する鮮度の判定は今回スキップしている）"
fi

echo
if [ "$n" = 0 ]; then
  echo "harness gc: 問題なし（閾値 ${DAYS} 日）"
else
  echo "harness gc: ${n} 件（閾値 ${DAYS} 日）。判断と修正は harness-maintain スキルの D か人間が行う。"
  [ "$STRICT" = 1 ] && exit 1
fi
exit 0
