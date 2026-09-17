#!/usr/bin/env bash
# harness doctor — 導入先の環境とハーネス導入状態を機械的に診断して一覧にする。
# 報告のみ（自動修復はしない）。gc が docs の健康診断なら、doctor は環境の健康診断。LLM は使わない。
#
# 使い方:  bash .harness/scripts/doctor.sh
#
# 各行:  OK|WARN|FAIL  項目  →  直し方     （OK 行に直し方は付かない）
# 最後に集計行（OK / WARN / FAIL の件数）。
#
# 終了コード:
#   0  問題なし、または WARN のみ
#   1  FAIL あり
#   2  診断自体ができない環境不備（未導入ディレクトリなど）
#
# 診断は bash と git だけで動く。node / jq が無くても全項目が実行できる（あれば使う、で留める）。
set -u

# git が無い環境でも診断できるよう、ROOT の決定は git に依存しすぎない
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Git for Windows は C:/... を返す。MSYS の /c/... に揃える（bin/harness の project_root と同じ扱い）
if command -v cygpath >/dev/null 2>&1; then ROOT="$(cygpath -u "$ROOT" 2>/dev/null || echo "$ROOT")"; fi
cd "$ROOT" 2>/dev/null || { echo "harness doctor: $ROOT に入れない" >&2; exit 2; }

if [ ! -f "$ROOT/.harness/manifest.json" ]; then
  echo "harness doctor: 導入コピーが無い（$ROOT/.harness/manifest.json が見つからない）" >&2
  echo "  直し方: このディレクトリで harness init を実行する" >&2
  echo "          例: bash <agent-harness を clone した場所>/bin/harness init --source <同じ場所>" >&2
  exit 2
fi

n_ok=0; n_warn=0; n_fail=0; n_info=0
report() { # severity 項目 [直し方]
  case "$1" in
    OK)   n_ok=$((n_ok + 1));;
    WARN) n_warn=$((n_warn + 1));;
    FAIL) n_fail=$((n_fail + 1));;
    INFO) n_info=$((n_info + 1));;
  esac
  if [ -n "${3:-}" ]; then
    printf '%-4s  %s  →  %s\n' "$1" "$2" "$3"
  else
    printf '%-4s  %s\n' "$1" "$2"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# 2 つのファイルの内容が同一か（パスではなく中身で見る。Windows では C:/ と /c/ と /tmp が混在する）。
# 素の git hash-object は使わない。理由が 2 つある:
#   1. .gitattributes の text eol=lf フィルタを通すので、CRLF 化しただけのファイルを「一致」と誤診する
#   2. git が無い環境では両辺が空文字になり、常に「一致」になる（誤った OK を出す）
# そこで生バイトで比べる。cmp → git hash-object --no-filters → bash 内蔵だけ、の順に落ちる。
content_eq() { # a b
  [ -f "$1" ] && [ -f "$2" ] || return 1
  if have cmp; then
    cmp -s "$1" "$2"
  elif have git; then
    local h1 h2
    h1="$(git hash-object --no-filters "$1" 2>/dev/null)"
    h2="$(git hash-object --no-filters "$2" 2>/dev/null)"
    [ -n "$h1" ] && [ "$h1" = "$h2" ]
  else
    # 外部コマンドが一切無くても判定する最後の手段（bash 内蔵の mapfile だけを使う）
    local -a lines_a=() lines_b=()
    mapfile lines_a <"$1" 2>/dev/null || return 1
    mapfile lines_b <"$2" 2>/dev/null || return 1
    [ "${#lines_a[@]}" = "${#lines_b[@]}" ] && [ "${lines_a[*]}" = "${lines_b[*]}" ]
  fi
}

# grep -c は 0 件のとき "0" を出して exit 1 を返す。`|| echo 0` を足すと出力が "0\n0" になり、
# 続く整数比較が「integer expression expected」で失敗して条件が常に偽になる（偽の全快の元）。
# 数を数えるときは必ずこの 2 つを通し、整数以外が来ても 0 に落とす。
as_int() { # 文字列 → 先頭の整数（空や非整数は 0）
  local n="${1%%[!0-9]*}"
  printf '%s' "${n:-0}"
}
count_matches() { # 正規表現 ファイル → マッチした行数（整数）
  as_int "$(grep -c "$1" "$2" 2>/dev/null || true)"
}

os_name="$(uname -s 2>/dev/null || echo unknown)"
is_windows=0
case "$os_name" in MINGW*|MSYS*|CYGWIN*) is_windows=1;; esac

# ---------------------------------------------------------------- B1. 必須ツール
# bash の版は BASH_VERSINFO[0] で見る（BASH_VERSINFO は readonly なのでテストから上書きできない。
# 「bash < 4」のシナリオは自動テストでは再現せず、実機が bash 3 の環境でこの行を見る）
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
  report OK "bash ${BASH_VERSION:-?}（4 以上）"
else
  report FAIL "bash の版が ${BASH_VERSION:-不明}（4 未満。連想配列などが使えない）" \
    "bash 4 以上で実行する（macOS: brew install bash して /opt/homebrew/bin/bash から回す。Windows: Git for Windows 同梱の bash）"
fi

if have git; then
  report OK "git（$(git --version 2>/dev/null | head -1)）"
else
  report FAIL "git が見つからない（ハーネスは git と bash だけに依存する）" \
    "git を入れて PATH に通す（Windows: Git for Windows、macOS: xcode-select --install、Linux: apt install git など）"
fi

# ---------------------------------------------------------------- B2. 任意ツール
if have node; then
  report OK "node（任意。$(node --version 2>/dev/null)）"
else
  report WARN "node が無い（任意）" \
    ".claude/settings.json の自動マージが手動になる。無くてもハーネスは動く。必要なら node を入れる"
fi

if have jq; then
  report OK "jq（任意。$(jq --version 2>/dev/null)）"
else
  report WARN "jq が無い（任意）" \
    "task-orchestrate の stages.json 抽出が grep 頼りになる。無くてもハーネスは動く。必要なら jq を入れる"
fi

if [ "$is_windows" = 1 ]; then
  if have cygpath; then
    report OK "cygpath（Windows）"
  else
    report WARN "cygpath が無い（$os_name）" \
      "パス形式（C:/ と /c/）の正規化ができない。Git for Windows 同梱の bash から実行する"
  fi
fi

# ---------------------------------------------------------------- B3. manifest
# bin/harness の manifest_get / manifest_entries と同じ「1 エントリ 1 行」書式を前提にする。
MANIFEST="$ROOT/.harness/manifest.json"
manifest_get() { # key
  sed -n "s/^  \"$1\": *\"\(.*\)\",\{0,1\}$/\1/p" "$MANIFEST" | head -1
}

mf_version="$(manifest_get harness_version)"
mf_source="$(manifest_get source)"
mf_agents="$(manifest_get agents)"

# path<TAB>src<TAB>ownership<TAB>sha256<TAB>source_sha256
mf_entries="$(grep '^    {"path"' "$MANIFEST" 2>/dev/null | sed -E \
  's/.*"path":"([^"]*)".*"src":"([^"]*)".*"ownership":"([^"]*)".*"sha256":"([^"]*)".*"source_sha256":"([^"]*)".*/\1\t\2\t\3\t\4\t\5/')"
mf_entry_lines="$(count_matches '^    {"path"' "$MANIFEST")"

# 1 行に複数エントリ / 別のインデント で書かれた manifest を「エントリ 0 件」と取り違えないための照合。
# ファイル全体の "path" キーの数とエントリ行の数が食い違えば、1 エントリ 1 行になっていない。
mf_path_keys="$mf_entry_lines"   # awk が無ければ照合しない（無い側に倒して誤検知を避ける）
if have awk; then
  mf_path_keys="$(as_int "$(awk '{ c += gsub(/"path":"/, "&") } END { print c + 0 }' "$MANIFEST" 2>/dev/null)")"
fi

mf_bad_lines=0
if [ "$mf_entry_lines" -gt 0 ] && have awk; then
  mf_bad_lines="$(as_int "$(printf '%s\n' "$mf_entries" | awk -F'\t' 'NF!=5{c++} END{print c+0}')")"
fi

mf_broken=""
[ -z "$mf_version" ] && mf_broken="$mf_broken harness_version が読めない;"
[ -z "$mf_source" ] && mf_broken="$mf_broken source が読めない;"
[ -z "$mf_agents" ] && mf_broken="$mf_broken agents が読めない;"
[ "$mf_entry_lines" -eq 0 ] && mf_broken="$mf_broken files のエントリ行が 0 件;"
[ "$mf_bad_lines" -gt 0 ] && mf_broken="$mf_broken 項目が欠けたエントリ行が ${mf_bad_lines} 件;"
[ "$mf_path_keys" -ne "$mf_entry_lines" ] && \
  mf_broken="$mf_broken 1 エントリ 1 行ではない（\"path\" が ${mf_path_keys} 個に対しエントリ行は ${mf_entry_lines} 行）;"

manifest_ok=1
[ -n "$mf_broken" ] && manifest_ok=0

if [ "$manifest_ok" = 1 ]; then
  report OK "manifest（version=$mf_version, agents=$mf_agents, ${mf_entry_lines} 件）"
else
  report FAIL "manifest（.harness/manifest.json）が壊れている:${mf_broken%;}" \
    ".harness/backup/ があれば復元するか、harness init をやり直す（bin/harness も同じ「1 エントリ 1 行」で読む）"
  # 黙ってスキップしない。何を確認できていないかを出力に残す。
  report WARN "manifest が読めないため B4（ファイルの存在）/ B5（改行）/ B8・B9（アダプタ側の照合）/ B10（新版）の診断をスキップした" \
    "先に上の FAIL（manifest）を直してから、もう一度 harness doctor を回す"
fi

# ---------------------------------------------------------------- B4. ファイルの存在（manifest 記載分）
# seed の欠落は WARN（導入後にプロジェクトが編集・削除しうる）。managed / generated / merge の欠落は FAIL。
if [ "$manifest_ok" = 1 ]; then
  mf_missing=0
  while IFS=$'\t' read -r f_path f_src f_own f_sha f_srcsha; do
    [ -z "$f_path" ] && continue
    [ -e "$ROOT/$f_path" ] && continue
    mf_missing=$((mf_missing + 1))
    if [ "$f_own" = "seed" ]; then
      report WARN "seed ファイルが無い: $f_path" \
        "seed は導入後にプロジェクトが編集する前提のファイル。必要なら harness の docs-template/ から取り直すか手で作る"
    else
      report FAIL "$f_own ファイルが無い: $f_path" \
        "harness update で復元する（直接編集していた場合は上書きされる点に注意）。復元できなければ harness init をやり直す"
    fi
  done <<<"$mf_entries"
  [ "$mf_missing" -eq 0 ] && report OK "manifest 記載ファイル（${mf_entry_lines} 件）はすべて存在する"
fi

# ---------------------------------------------------------------- B5. 改行
# managed / generated のファイルに CR（\r）が含まれていないか。Windows の core.autocrlf=true で
# チェックアウトすると LF 管理のはずのファイルが CRLF になり、ハッシュ比較や shebang 実行が壊れる。
if [ "$manifest_ok" = 1 ]; then
  cr_found=0
  while IFS=$'\t' read -r f_path f_src f_own f_sha f_srcsha; do
    [ -z "$f_path" ] && continue
    case "$f_own" in managed|generated) ;; *) continue;; esac
    case "$f_path" in *.cmd) continue;; esac  # *.cmd は CRLF が規約（.gitattributes）
    [ -f "$ROOT/$f_path" ] || continue  # 欠落は B4 で報告済み
    # grep の \r マッチは環境によって信用できない（MSYS の一部 grep が誤検知しない）ので、
    # tr -d '\r' の前後でバイト数を比べる（CR があれば減る）。
    if [ "$(tr -d '\r' < "$ROOT/$f_path" | wc -c)" != "$(wc -c < "$ROOT/$f_path")" ]; then
      cr_found=$((cr_found + 1))
      report FAIL "改行: $f_path に CR（\\r）が含まれる（CRLF 化されている）" \
        "autocrlf を疑う（git config core.autocrlf false のうえで harness update、または git checkout -- $f_path で復元）"
    fi
  done <<<"$mf_entries"
  [ "$cr_found" -eq 0 ] && report OK "改行: managed / generated ファイルに CR は無い"

  if [ -f "$ROOT/.gitattributes" ] && grep -qxF ".harness/** text eol=lf" "$ROOT/.gitattributes"; then
    report OK ".gitattributes に .harness/** text eol=lf がある"
  else
    report WARN ".gitattributes に .harness/** text eol=lf が無い" \
      ".gitattributes に \".harness/** text eol=lf\" を足す（本来 harness init/update が足す行。手で消していないか確認する）"
  fi
fi

# ---------------------------------------------------------------- B6. git hooks
hooks_path="$(git -C "$ROOT" config --get core.hooksPath 2>/dev/null || true)"
if [ "$hooks_path" = ".githooks" ] && [ -f "$ROOT/.githooks/pre-commit" ]; then
  report OK "git hooks（core.hooksPath=.githooks, .githooks/pre-commit あり）"
else
  report WARN "git hooks（core.hooksPath が .githooks になっていない、または .githooks/pre-commit が無い。現在値: ${hooks_path:-未設定}）" \
    "git config core.hooksPath .githooks"
fi

# ---------------------------------------------------------------- B7. AGENTS.md のマーカーと版
AGENTS_FILE="$ROOT/AGENTS.md"
if [ ! -f "$AGENTS_FILE" ]; then
  report FAIL "AGENTS.md が無い" \
    "harness update をやり直すか、.harness/backup/ から復元する"
else
  begin_count="$(count_matches '<!-- harness:begin' "$AGENTS_FILE")"
  end_count="$(count_matches '<!-- harness:end -->' "$AGENTS_FILE")"
  if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    report FAIL "AGENTS.md に harness の管理ブロックのマーカーが無い（<!-- harness:begin v=X --> / <!-- harness:end -->）" \
      "harness update をやり直すか、.harness/backup/ から復元する"
  elif [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
    report FAIL "AGENTS.md のマーカーがちょうど 1 組ではない（begin=${begin_count}, end=${end_count}）" \
      "重複または欠落したマーカーを手で 1 組に整理するか、.harness/backup/ から復元する"
  else
    agents_ver="$(sed -n 's/.*<!-- harness:begin v=\([^ ]*\) -->.*/\1/p' "$AGENTS_FILE" | head -1)"
    if [ "$manifest_ok" != 1 ]; then
      report WARN "AGENTS.md のマーカー（v=${agents_ver:-不明}）と manifest の harness_version の一致は、manifest が壊れているため確認できない" \
        "先に manifest（B3）を直してから、もう一度 harness doctor を回す"
    elif [ -n "$agents_ver" ] && [ "$agents_ver" = "$mf_version" ]; then
      report OK "AGENTS.md のマーカー（v=$agents_ver, manifest と一致）"
    else
      report WARN "AGENTS.md のマーカーの版（v=${agents_ver:-不明}）が manifest の harness_version（${mf_version:-不明}）と食い違う" \
        "harness update を実行して同期する"
    fi
  fi
fi

# ---------------------------------------------------------------- B8. Claude アダプタ
# manifest の agents に claude を含むときだけ実行する。含まないときは CLAUDE.md 等がそもそも
# 導入されていないので、何も報告しない（誤検知を避ける）。
case ",$mf_agents," in
  *,claude,*)
    if [ -f "$ROOT/CLAUDE.md" ] && grep -q '^@AGENTS\.md' "$ROOT/CLAUDE.md"; then
      report OK "CLAUDE.md に @AGENTS.md の import がある"
    else
      report FAIL "CLAUDE.md に @AGENTS.md の import が無い" \
        "harness update をやり直すか、CLAUDE.md の先頭付近に @AGENTS.md を足す"
    fi

    if [ "$manifest_ok" = 1 ]; then
      skill_mismatch=0
      while IFS=$'\t' read -r f_path f_src f_own f_sha f_srcsha; do
        [ -z "$f_path" ] && continue
        case "$f_path" in .claude/skills/*) ;; *) continue;; esac
        rel="${f_path#.claude/skills/}"
        agents_side="$ROOT/.agents/skills/$rel"
        claude_side="$ROOT/$f_path"
        [ -f "$agents_side" ] || continue  # 欠落は B4 で報告済み
        [ -f "$claude_side" ] || continue  # 同上
        if ! content_eq "$agents_side" "$claude_side"; then
          skill_mismatch=$((skill_mismatch + 1))
          report WARN ".claude/skills/$rel が .agents/skills/$rel と内容がずれている" \
            "harness update で同期する（.claude 側を直接編集していないか確認する）"
        fi
      done <<<"$mf_entries"
      [ "$skill_mismatch" -eq 0 ] && report OK ".claude/skills/* は .agents/skills/* と内容が一致する"

      # .claude/agents/*.md の欠落は B4 が個別に報告する。ここでは集計だけ添える。
      claude_agents_missing=0
      while IFS=$'\t' read -r f_path f_src f_own f_sha f_srcsha; do
        [ -z "$f_path" ] && continue
        case "$f_path" in .claude/agents/*.md) ;; *) continue;; esac
        [ -f "$ROOT/$f_path" ] || claude_agents_missing=$((claude_agents_missing + 1))
      done <<<"$mf_entries"
      [ "$claude_agents_missing" -eq 0 ] && report OK ".claude/agents/*.md は manifest どおりに揃っている"
    fi
  ;;
esac

# ---------------------------------------------------------------- B9. Codex アダプタ
# manifest の agents に codex を含むときだけ実行する。
case ",$mf_agents," in
  *,codex,*)
    if [ "$manifest_ok" = 1 ]; then
      codex_missing=0
      for f in .agents/skills/role-implementer/SKILL.md .agents/skills/role-reviewer/SKILL.md; do
        [ -f "$ROOT/$f" ] || codex_missing=$((codex_missing + 1))
      done
      if [ "$codex_missing" -eq 0 ]; then
        report OK "Codex アダプタ（role-implementer / role-reviewer）が揃っている"
      else
        report FAIL "Codex アダプタの役割スキルが足りない（role-implementer / role-reviewer）" \
          "harness update で復元する（復元できなければ harness init をやり直す）"
      fi
    fi
  ;;
esac

# ---------------------------------------------------------------- B10. 版（source の新版）
# source がローカルディレクトリのときだけ VERSION を比べる。URL のときはネットワークに触らない。
if [ "$manifest_ok" = 1 ]; then
  if [ -n "$mf_source" ] && [ -d "$mf_source" ] && [ -f "$mf_source/VERSION" ]; then
    src_version="$(tr -d '\r\n' < "$mf_source/VERSION")"
    if [ -n "$src_version" ] && [ "$src_version" != "$mf_version" ]; then
      report INFO "source（$mf_source）に新版 $src_version がある（導入済みは $mf_version）" \
        "bash bin/harness update で追従する（別 ref を使うときは --ref を付ける）"
    else
      report OK "source の版は導入済みと同じ（$mf_version）"
    fi
  else
    report OK "source はローカルディレクトリではない、または VERSION が無い（新版チェックはネットワークに触らないため省略）"
  fi
fi

# ---------------------------------------------------------------- B11. gitignore
GITIGNORE="$ROOT/.gitignore"
gi_missing=""
for entry in ".harness/state/" ".harness/backup/" ".harness/conflicts/"; do
  if [ -f "$GITIGNORE" ] && grep -qxF "$entry" "$GITIGNORE"; then
    :
  else
    gi_missing="$gi_missing $entry"
  fi
done
gi_missing="${gi_missing# }"
if [ -z "$gi_missing" ]; then
  report OK ".gitignore に .harness/state|backup|conflicts/ がある"
else
  report WARN ".gitignore に無いエントリ: $gi_missing" \
    ".gitignore に「$gi_missing」を追記する"
fi

# ---------------------------------------------------------------- 集計
echo
echo "harness doctor: OK=$n_ok WARN=$n_warn FAIL=$n_fail"
if [ "$n_fail" -gt 0 ]; then
  echo "  FAIL の行の「→」に従って直す。直せたらもう一度 harness doctor を回す。"
  exit 1
fi
exit 0
