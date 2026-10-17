#!/usr/bin/env bash
# agent-harness managed: Claude Code の PreToolUse hook。git push の前に、まだ push していない範囲が
# セキュリティの観点でレビュー済みであることを確かめる（1.2.0。docs/decisions/0014）。
#
# 流れ（レビューは push 1 回につき 1 回。commit ごとにはしない）:
#   1. push を頼まれたら、push していない範囲（git log --branches --not --remotes）をまとめてレビューする
#   2. 問題なしなら印を付ける:  bash .harness/scripts/push-gate.sh --stamp
#      （印は .git/harness-push-reviewed。git の中なのでコミットされない。push していないブランチの先端を記録する）
#   3. 問題があれば直し、push していないコミットを書き換えてから（git commit --amend、
#      git reset --soft <push 済みの基点> で作り直す など）1 に戻る。上流に乗ったものは書き換えない
# この hook は、push していないコミットを持つブランチ・タグの先端がすべて印に載っているときだけ通す。
# 先端が 1 つでも変われば（コミットを足した、書き換えた）印は効かなくなり、もう一度レビューが要る。
#
# 止めるもの（判定できない形は止める側に倒す。止めても人は `! git push` で通せる）:
#   - 印の無い先端がある push
#   - コミットを作る・取り込む操作（commit / merge / rebase / pull など）と push が同じコマンド
#     （hook は実行前に走るので、そのコマンドで作られるコミットは印と照らせない）
#   - 展開（$( ) ` ` ${ }）・eval・xargs・sh -c・--git-dir・GIT_DIR= を通した push、シェルを通す git の alias
# 通すもの: push していないコミットが無い push、すべてが --dry-run の push。
# push 先のリポジトリは cd / pushd / git -C を追って決める。ヒアドキュメントの中身はコマンドとして見ない。
#
# 印はエージェントでも書ける。これは「レビュー前にうっかり push する」ことを止める関門で、
# 悪意のあるエージェントを止める境界ではない（Claude Code の docs も deny / ask を境界ではないと書く）。
# permissions.ask の Bash(git push *) は、2026-10-16 の実機（auto モード）で確認が出なかったので使わない。
set -u

STAMP_NAME="harness-push-reviewed"

# 未 push のコミットを持つ、ローカルのブランチ・タグ・HEAD の先端（重複なし）。HEAD を含めるのは、
# detached HEAD や rebase 中に `git push origin HEAD:main` するときのため。rev-list は 1 回だけ起動する
# （ref ごとに起動すると、タグの多いリポジトリで hook の timeout を超え、超えると素通りになる）。
unpushed_tips() { # <リポジトリ>
  local unpushed
  unpushed="$(git -C "$1" rev-list --branches --tags HEAD --not --remotes 2>/dev/null)" || return 0
  [ -n "$unpushed" ] || return 0
  { printf '%s\n' "$unpushed"; echo "--"
    git -C "$1" for-each-ref --format='%(objectname)' refs/heads refs/tags 2>/dev/null
    git -C "$1" rev-parse -q --verify HEAD 2>/dev/null
  } | awk '$0=="--"{r=1;next} !r{u[$0];next} ($0 in u) && !s[$0]++'
}

# ---- 印を付ける（レビューで問題なしと判断した後に、エージェントか人が実行する） ----
if [ "${1:-}" = "--stamp" ]; then
  gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || { echo "push-gate --stamp: git のリポジトリの中で実行する" >&2; exit 1; }
  tips="$(unpushed_tips .)"
  if [ -z "$tips" ]; then echo "push-gate --stamp: push していないコミットは無い（印は要らない）"; exit 0; fi
  now="$(date +%Y-%m-%dT%H:%M:%S%z)"
  printf '%s\n' "$tips" | while read -r t; do printf '%s\t%s\n' "$t" "$now"; done >>"$gd/$STAMP_NAME"
  echo "push-gate --stamp: レビュー済みの印を付けた（$(printf '%s\n' "$tips" | wc -l | tr -d ' ') 件の先端）:"
  printf '%s\n' "$tips" | while read -r t; do echo "  $(git log -1 --format='%h %s' "$t")"; done
  exit 0
fi

payload="$(cat)"

deny() { # 理由
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# --- コマンドの取り出し（harness/adapters/codex/deny.sh と同じやり方。jq があれば使う） ---
unescape_u_lines() { # 退避文字（\ の代わり）
  local first=0 line hex
  while IFS= read -r line; do
    if [ "$first" -eq 0 ]; then printf '%s' "$line"; first=1; continue; fi
    hex="${line:0:4}"; line="${line:4}"
    case "$hex" in
      005[cC]) printf '%s' "$1" ;;
      00[0-7][0-9a-fA-F]) printf "\\x${hex:2:2}" ;;
      *) printf '?' ;;
    esac
    printf '%s' "$line"
  done
}
json_unescape() {
  local s="$1" BS=$'\001'
  s="${s//\\\\/$BS}"
  case "$s" in
    *'\u'*)
      s="$(printf '%s\n' "$s" | sed 's/\\u/\
/g' | unescape_u_lines "$BS"; printf x)"
      s="${s%x}" ;;
  esac
  s="${s//\\\"/\"}"; s="${s//\\\//\/}"
  s="${s//\\n/$'\n'}"; s="${s//\\t/$'\t'}"; s="${s//\\r/$'\r'}"
  s="${s//\\b/ }"; s="${s//\\f/ }"
  printf '%s' "${s//$BS/\\}"
}
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command | if type == "string" then . else empty end' 2>/dev/null || true)"
fi
if [ -z "$cmd" ]; then
  cmd="$(printf '%s' "$payload" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(\([^"\\]*\(\\.\)*\)*\)".*/\1/p')"
  cmd="$(json_unescape "$cmd")"
fi
[ -n "$cmd" ] || exit 0
# hook に渡される作業ディレクトリ（Claude Code の Bash は cd をコール間で持ち越す）。無ければ hook の pwd
pcwd=""
if command -v jq >/dev/null 2>&1; then
  pcwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$pcwd" ] || pcwd="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p')"
# push の語が無く、push に展開される git の alias も無ければ見るまでもない（ほとんどのコマンドはここで抜ける）
push_aliases="$(git config --get-regexp '^alias\.' 2>/dev/null | awk '$0 ~ /push/ {sub(/^alias\./,"",$1); print $1}')"
has_push_word() { # <文字列>
  case "$1" in *push*) return 0 ;; esac
  local a
  for a in $push_aliases; do case "$1" in *"$a"*) return 0 ;; esac; done
  return 1
}
has_push_word "$cmd" || exit 0

# ヒアドキュメントの中身（ファイルに書く文章など）はコマンドではないので外す。
# 区切りの語（<<EOF / <<'EOF' / <<-"EOF"）を覚え、その語だけの行までを捨てる。
# ヒアストリング（<<<）は対象外。閉じの行が見つからなければ捨てずに戻す（止める側に倒す。
# 引用符の中の "<<EOF" のような、ヒアドキュメントでないものを取り違えたときもこれで救われる）。
cmd="$(printf '%s\n' "$cmd" | awk '
  skip { t=$0; sub(/^\t+/,"",t); buf=buf $0 "\n"; if (t==delim) { skip=0; buf="" } ; next }
  {
    print
    line=$0; gsub(/<<</,"   ",line)
    if (match(line, /<<-?[ \t]*["'\'']?[A-Za-z_][A-Za-z0-9_]*["'\'']?/)) {
      d=substr(line, RSTART, RLENGTH); sub(/^<<-?[ \t]*/,"",d); gsub(/["'\'']/,"",d); delim=d; skip=1; buf=""
    }
  }
  END { if (skip) printf "%s", buf }')"
has_push_word "$cmd" || exit 0

# 展開（$( ) ` ` ${ }）は、push が実際に見つかったコマンドでだけ止める（下の n_push の後）。
# 「git」と「push」の文字が離れて出てくるだけの、push ではないコマンドまで止めないため。

case "$cmd" in
  *GIT_DIR=*|*GIT_WORK_TREE=*) deny "agent-harness: push-gate: GIT_DIR / GIT_WORK_TREE を設定するコマンドの push は、どのリポジトリに効くかを判定できないので止めた。" ;;
esac

# --- git push を探す（区切りでコマンドに分け、語に分けてから見る。deny.sh と同じ正規化） ---
norm="${cmd//\\$'\n'/ }"
norm="$(printf '%s\n' "$norm" | sed -e 's/^#.*$//' -e 's/[[:space:]]#.*$//' | tr -d "\"'\\\\" | tr ';&|(){}' '\n\n\n\n\n\n\n' | tr '\t\r<>' '    ')"
takes_value() {
  case "$1" in -c|-C|--git-dir|--work-tree|--namespace|--config-env|--super-prefix|--exec-path) return 0;; esac
  return 1
}
abs_dir() { # <基準> <パス>  → 絶対パス（辿れなければ空）
  local d="$2"
  case "$d" in "~") d="$HOME" ;; "~/"*) d="$HOME/${d#\~/}" ;; esac
  case "$d" in /*) ;; *) d="$1/$d" ;; esac
  (cd "$d" 2>/dev/null && pwd) || true
}
creates_commit() {
  case "$1" in commit|merge|rebase|cherry-pick|revert|am|pull|commit-tree|update-ref|reset|stash) return 0;; esac
  return 1
}
cwd="$(pwd)"
[ -n "$pcwd" ] && [ -d "$pcwd" ] && cwd="$pcwd"
n_push=0; n_dry=0; has_commit=1
targets=""
scan_git() { # $@ = git の後ろの語
  local gdir="$cwd" t sub alias
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; break ;;
      -C) [ $# -ge 2 ] || deny "agent-harness: push-gate: git -C の後ろにディレクトリが無い。判定できないので止めた。"
          gdir="$(abs_dir "$gdir" "$2")"
          [ -n "$gdir" ] || deny "agent-harness: push-gate: git -C の先が辿れない。push 先を判定できないので止めた。"
          shift 2 ;;
      -c) case "${2:-}" in alias.*) deny "agent-harness: push-gate: git -c alias.* を付けた git は、何が実行されるかを判定できないので止めた。" ;; esac
          [ $# -ge 2 ] && shift 2 || shift ;;
      --git-dir|--git-dir=*|--work-tree|--work-tree=*)
        deny "agent-harness: push-gate: --git-dir / --work-tree を付けた git は、どのリポジトリに効くかを判定できないので止めた。cd してから素の git push を使う。" ;;
      -*) if takes_value "$1" && [ $# -ge 2 ]; then shift; fi; shift ;;
      *) break ;;
    esac
  done
  sub="${1:-}"; [ -n "$sub" ] || return 0; shift
  case "$sub" in *'$'*) deny "agent-harness: push-gate: git のサブコマンドが展開（${sub}）になっていて、push かどうか判定できない。展開を使わずに書く。" ;; esac
  # git の alias（git p = push など）は展開して見る。シェルを通す alias（!...）が push / commit を含めば止める
  if [ "$sub" != push ] && alias="$(git -C "$gdir" config --get "alias.${sub}" 2>/dev/null)" && [ -n "$alias" ]; then
    case "$alias" in
      '!'*) case "$alias" in *push*|*commit*) deny "agent-harness: push-gate: git の alias（${sub}）がシェルを通して push / commit を含む。判定できないので止めた。素の git push を使う。" ;; esac
            return 0 ;;
    esac
    set -f; set -- $alias "$@"; set +f
    sub="$1"; shift
  fi
  if creates_commit "$sub"; then has_commit=0; return 0; fi
  # git subtree push も push として見る
  if [ "$sub" = subtree ] && [ "${1:-}" = push ]; then sub=push; shift; fi
  [ "$sub" = push ] || return 0
  n_push=$((n_push + 1))
  for t in "$@"; do
    case "$t" in --dry-run|-n) n_dry=$((n_dry + 1)); break ;; --*) ;; -*n*) n_dry=$((n_dry + 1)); break ;; esac
  done
  targets="$targets
$gdir"
}
while IFS= read -r line; do
  set -f; set -- $line; set +f
  while [ $# -gt 0 ]; do
    case "$1" in
      cd|pushd)
        shift
        if [ $# -gt 0 ]; then cwd="$(abs_dir "$cwd" "$1")"; shift; else cwd="$HOME"; fi
        [ -n "$cwd" ] || cwd="/nonexistent-push-gate" ;;     # 辿れない cd の後の push は下で止まる
      GIT_DIR=*|GIT_WORK_TREE=*)
        case "$line" in *push*) deny "agent-harness: push-gate: GIT_DIR / GIT_WORK_TREE を付けた push は、どのリポジトリに効くかを判定できないので止めた。" ;; esac
        shift ;;
      eval|xargs|sh|bash|zsh)
        # 語としての push（git push を渡している）があれば止める。push-gate.sh のようなファイル名は除く
        case " $line " in *" push "*) deny "agent-harness: push-gate: ${1} を通した push は、実行前に何が push されるか判定できない。素の git push を使う。" ;; esac
        shift ;;
      git|*/git) shift; scan_git "$@"; break ;;
      *) shift ;;
    esac
  done
done <<EOF
$norm
EOF
[ "$n_push" -gt 0 ] || exit 0
case "$cmd" in
  *'$('*|*'`'*|*'${'*) deny "agent-harness: push-gate: 展開を含むコマンドの push は、実行前に何が push されるか判定できない。展開を使わない git push に書き直す。" ;;
esac
[ "$n_dry" -eq "$n_push" ] && exit 0                    # すべての push が dry-run のときだけ素通り
if [ "$has_commit" -eq 0 ]; then
  deny "agent-harness: push-gate: コミットを作る・取り込む操作（commit / merge / rebase / pull など）と push が同じコマンドに入っている。分けて実行する（先にコミットし、レビューして印を付けてから push する）。"
fi

# --- 関門（push 先のリポジトリごと） ---
gate_repo() { # <リポジトリのディレクトリ>
  local dir="$1" gd tips t missing="" stamp
  [ -d "$dir" ] || deny "agent-harness: push-gate: push 先のディレクトリ（${dir}）が辿れない。判定できないので止めた。"
  gd="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || return 0   # git の外での push は git 自身が失敗する
  tips="$(unpushed_tips "$dir")"
  [ -n "$tips" ] || return 0
  stamp="$gd/$STAMP_NAME"
  for t in $tips; do
    awk -F'\t' -v t="$t" '$1==t{f=1} END{exit f?0:1}' "$stamp" 2>/dev/null || missing="$missing ${t:0:7}"
  done
  [ -z "$missing" ] && return 0
  deny "agent-harness: push-gate: push していない範囲がまだレビューされていない（印の無い先端:${missing}）。git log --branches --not --remotes の範囲をセキュリティの観点でレビューし、問題なければ bash .harness/scripts/push-gate.sh --stamp で印を付けてから push する。問題があれば直し、push していないコミットを書き換えてから（上流に乗ったものは書き換えない）レビューし直す。人が中身を確かめたうえなら ! git push で通せる。"
}
seen=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$seen" in *"|$t|"*) continue ;; esac
  seen="$seen|$t|"
  gate_repo "$t"
done <<EOF3
$targets
EOF3
exit 0
