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
days_since() { # YYYY-MM-DD -> days (or empty if unparsable)
  local e; e=$(date -d "$1" +%s 2>/dev/null) || return 1
  echo $(( (today_epoch - e) / 86400 ))
}

# 1. handoff の鮮度
if [ -f "$DOCS/handoff.md" ]; then
  upd=$(sed -n 's/^最終更新: *//p' "$DOCS/handoff.md" | head -1 | tr -d '\r')
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

echo
if [ "$n" = 0 ]; then
  echo "harness gc: 問題なし（閾値 ${DAYS} 日）"
else
  echo "harness gc: ${n} 件（閾値 ${DAYS} 日）。判断と修正は harness-maintain スキルの D か人間が行う。"
  [ "$STRICT" = 1 ] && exit 1
fi
exit 0
