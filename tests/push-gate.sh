#!/usr/bin/env bash
# tests/push-gate.sh — harness/adapters/claude/push-gate.sh（push 前のレビューの関門）の
# シナリオテスト（このリポジトリ専用。ペイロードではない。決定 0014）
#
# 使い方:  bash tests/push-gate.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 使い捨ての bare リポジトリと clone を作り、hook に Claude Code と同じ形の JSON を渡す。
# 印は `push-gate.sh --stamp` で付ける。jq が無い経路も見る。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO/harness/adapters/claude/push-gate.sh"
WORK="$(mktemp -d)" || { echo "tests/push-gate.sh: mktemp -d に失敗した"; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0; failed=0
failed_names=()

g() { git -c user.email=t@t -c user.name=t "$@"; }
jstr() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; printf '"%s"' "$s"; }

run_gate() { # <コマンド> [nojq]  → 出力を OUT に（cwd は ${W}）
  local payload; payload="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(jstr "$1")}}"
  if [ "${2:-}" = nojq ]; then
    OUT="$(printf '%s' "$payload" | (cd "$W" && PATH="$NOJQ_BIN" bash "$GATE") 2>&1)"
  else
    OUT="$(printf '%s' "$payload" | (cd "$W" && bash "$GATE") 2>&1)"
  fi
}
expect() { # <名前> <deny|allow> [出力に含む正規表現]
  local got=allow
  printf '%s' "$OUT" | grep -q '"permissionDecision":"deny"' && got=deny
  if [ "$got" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$OUT" | grep -qE "$3"; }; then
    passed=$((passed + 1)); echo "PASS  $1"
  else
    failed=$((failed + 1)); failed_names+=("$1"); echo "FAIL  $1（期待 $2 / 実際 ${got}）"; printf '%s\n' "$OUT" | sed 's/^/      | /'
  fi
}
stamp() { (cd "$W" && bash "$GATE" --stamp) >/dev/null 2>&1; }

# jq を外した PATH（jq のあるディレクトリには git なども居るので、jq 以外をリンクした置き場を作る）
NOJQ_BIN="$WORK/nojq-bin"; mkdir -p "$NOJQ_BIN"
for c in bash git sed awk tr cat date mkdir printf grep cut env sort wc pwd; do
  p="$(command -v "$c" 2>/dev/null)" && [ -n "$p" ] && [ -x "$p" ] && ln -sf "$p" "$NOJQ_BIN/$c"
done

# 使い捨ての origin と clone（push 済みのコミットが 1 つある状態）
g init -q -b main --bare "$WORK/o.git" && g clone -q "$WORK/o.git" "$WORK/w" 2>/dev/null
W="$WORK/w"
printf 'a\n' >"$W/a.sh" && g -C "$W" add a.sh && g -C "$W" commit -q -m base && g -C "$W" push -q origin main
mkdir -p "$WORK/other"   # git でないディレクトリ

# ---------------------------------------------------------------- シナリオ
run_gate "git status";                     expect "P1: push でないコマンドは通す" allow
run_gate "git push";                       expect "P2: push していないコミットが無ければ通す" allow

printf 'b\n' >>"$W/a.sh" && g -C "$W" commit -q -am src
run_gate "git push"
expect "P3: 印の無い先端があれば止め、レビューと印の付け方を言う" deny 'まだレビューされていない.*--stamp'

stamp
run_gate "git push origin main";           expect "P4: 印を付けたら通す" allow

printf 'c\n' >>"$W/a.sh" && g -C "$W" commit -q -am more
run_gate "git push"
expect "P5: 印の後にコミットを足すと、印は効かなくなる" deny 'まだレビューされていない'
stamp

g -C "$W" commit -q --amend -m more-amended
run_gate "git push"
expect "P6: push していないコミットを書き換えると、印は効かなくなる" deny 'まだレビューされていない'
stamp

g -C "$W" branch -q side && g -C "$W" checkout -q side && printf 'd\n' >>"$W/a.sh" && g -C "$W" commit -q -am side &&
  g -C "$W" checkout -q main
run_gate "git push origin side"
expect "P7: HEAD 以外のブランチにある印の無いコミットも見る" deny 'まだレビューされていない'
stamp

run_gate "git push --dry-run; git push"
expect "P8: dry-run と本物の push が混ざれば、本物として関門を通す（印があるので通る）" allow
printf 'e\n' >>"$W/a.sh" && g -C "$W" commit -q -am e
run_gate "git push --dry-run; git push";   expect "P9: dry-run と本物の push が混ざり、印が無ければ止める" deny 'まだレビューされていない'
run_gate "git push --dry-run";             expect "P10: すべて dry-run なら通す" allow

run_gate "git commit -m z && git push"
expect "P11: commit と push が同じコマンドなら止める（hook は実行前に走る）" deny '同じコマンド'
run_gate "git pull && git push";           expect "P12: pull と push が同じコマンドでも止める" deny '同じコマンド'

run_gate "git -C . push";                  expect "P13: git -C を追って push 先を決める" deny 'まだレビューされていない'
run_gate "cd $WORK/other && git -C $W push"
expect "P14: cd の後の git -C（絶対パス）も追う" deny 'まだレビューされていない'
run_gate "cd $WORK/other; git push"
expect "P15: cd で git でない場所へ移ってからの push は、このリポジトリの関門にかけない" allow

run_gate 'git push $(echo origin) main';   expect "P16: 展開を含む push は止める" deny '展開'
run_gate "echo origin | xargs git push";   expect "P17: xargs を通した push は止める" deny 'xargs'
run_gate "git --git-dir=$W/.git push";     expect "P18: --git-dir を付けた push は止める" deny 'git-dir'
g -C "$W" config alias.p push
run_gate "git p origin main";              expect "P19: git の alias（p = push）は展開して見る" deny 'まだレビューされていない'

run_gate "cat > notes.md <<'EOF'
git push origin main
EOF"
expect "P20: ヒアドキュメントの中の git push はコマンドとして見ない" allow
run_gate "bash .harness/scripts/push-gate.sh --stamp"
expect "P21: 印を付けるコマンド自体は通す（push の語を含むが push ではない）" allow

run_gate "git push" nojq;                  expect "P22: jq が無くても同じに判定する" deny 'まだレビューされていない'
run_gate 'echo "未 push の件数: $(git -C . rev-list --count HEAD)"'
expect "P32: push ではないコマンドは、git と push の文字と展開を含んでも止めない" allow
run_gate 'git $(echo push) origin';        expect "P33: git のサブコマンドが展開なら止める" deny '展開'

# ---- 2026-10-16 のレビューの指摘（素通りする形）----
run_gate "bc <<<foo
git push origin HEAD"
expect "P23: ヒアストリング（<<<）の後ろの push も見る" deny 'まだレビューされていない'
run_gate 'echo "a <<EOF"
git push origin HEAD'
expect "P24: 閉じの行が無い <<EOF（引用符の中など）の後ろの push も見る" deny 'まだレビューされていない'
run_gate "git push origin HEAD # -n";      expect "P25: コメントの -n を dry-run と見ない" deny 'まだレビューされていない'
run_gate "git -C
git push"
expect "P26: git -C の後ろに語が無くても止まる（無限ループで timeout になり素通りしない）" deny 'git -C'
run_gate "git subtree push --prefix=x origin main"; expect "P27: git subtree push も push として見る" deny 'まだレビューされていない'
run_gate "git -c alias.q=push q origin";   expect "P28: git -c alias.* は止める" deny 'alias'
run_gate "export GIT_DIR=$W/.git; git push"; expect "P29: export GIT_DIR の後の push は止める" deny 'GIT_DIR'
stamp
g -C "$W" checkout -q --detach && printf 'f\n' >>"$W/a.sh" && g -C "$W" commit -q -am detached
run_gate "git push origin HEAD:main";      expect "P30: detached HEAD のコミットも見る" deny 'まだレビューされていない'
g -C "$W" checkout -q main
printf 'g\n' >>"$W/a.sh" && g -C "$W" commit -q -am g
OUT="$(printf '{"tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"%s"}' "$W" | (cd "$WORK/other" && bash "$GATE") 2>&1)"
expect "P31: hook の pwd が別の場所でも、payload の cwd のリポジトリを見る" deny 'まだレビューされていない'

# ---- 1.5.0: claude.ai のリンク（セッション・artifact）を push させない ----
# このファイル自体にリンクの文字列を書かない（このリポジトリの push で止まるので、組み立てる）
HOST="claude.ai"
stamp_out() { STAMP_OUT="$( (cd "$W" && bash "$GATE" --stamp) 2>&1)"; STAMP_RC=$?; }
g -C "$W" checkout -q -B main origin/main 2>/dev/null; g -C "$W" reset -q --hard origin/main
for b in $(g -C "$W" for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$'); do g -C "$W" branch -q -D "$b"; done
printf 'h\n' >>"$W/a.sh" && g -C "$W" commit -q -am "feat: x

Claude-Session: https://$HOST/code/session_01AbCdEfGh"
stamp_out
[ "$STAMP_RC" -ne 0 ] && printf '%s' "$STAMP_OUT" | grep -q 'session_01AbCdEfGh' \
  && { passed=$((passed + 1)); echo "PASS  P34: メッセージにセッションの URL があれば --stamp は印を付けない"; } \
  || { failed=$((failed + 1)); failed_names+=("P34"); echo "FAIL  P34"; printf '%s\n' "$STAMP_OUT" | sed 's/^/      | /'; }
run_gate "git push";                       expect "P35: 印が無ければ従来どおり止める" deny 'まだレビューされていない'
printf '%s\t%s\n' "$(g -C "$W" rev-parse HEAD)" now >>"$W/.git/harness-push-reviewed"   # 古い版の印・手で書いた印
run_gate "git push";                       expect "P36: 印があってもメッセージのリンクで止め、外し方を言う" deny 'claude.ai のリンク.*amend'
g -C "$W" commit -q --amend -m "feat: x

Co-Authored-By: someone <noreply@example.com>"
printf 'See https://%s/code/artifact/0a1b2c3d-4e5f\n' "$HOST" >"$W/note.md" && g -C "$W" add note.md && g -C "$W" commit -q -m note
stamp_out
[ "$STAMP_RC" -ne 0 ] && printf '%s' "$STAMP_OUT" | grep -q '追加行: .*artifact/0a1b2c3d' \
  && { passed=$((passed + 1)); echo "PASS  P37: 差分の追加行に artifact の URL があれば --stamp は印を付けない"; } \
  || { failed=$((failed + 1)); failed_names+=("P37"); echo "FAIL  P37"; printf '%s\n' "$STAMP_OUT" | sed 's/^/      | /'; }
printf 'Artifact: https://%s/code/artifact/{uuid}\n' "$HOST" >"$W/note.md" && g -C "$W" commit -q --amend -am note
stamp_out
[ "$STAMP_RC" -eq 0 ] && { passed=$((passed + 1)); echo "PASS  P38: {uuid} のような置き場の書き方と Co-Authored-By は通す"; } \
  || { failed=$((failed + 1)); failed_names+=("P38"); echo "FAIL  P38"; printf '%s\n' "$STAMP_OUT" | sed 's/^/      | /'; }
run_gate "git push";                       expect "P39: リンクを外して印を付ければ通す" allow
run_gate "git push" nojq;                  expect "P40: jq が無くても通す" allow

# ---- 1.8.0: ハーネスを入れたリポジトリでは、push する先端でフルの検査が通った記録を求める ----
mkdir -p "$W/.harness" && printf '%s\n' 'check "all" "true"' >"$W/.harness/checks.sh"   # 追跡しない（検査の登録として置くだけ）
run_gate "git push";                       expect "P45: checks.sh に on を書いた検査が無ければ、フルの検査を求めない（1.9.0）" allow
printf '%s\n' 'check "all" "true"' 'check fast on "src/" "src" "true"' >"$W/.harness/checks.sh"
run_gate "git push";                       expect "P41: on を書いた検査があれば、印があってもフルの検査の記録が無ければ止め、--full を言う" deny 'フルの検査が通っていない.*check --full'
printf '%s\t%s\n' "$(g -C "$W" rev-parse 'HEAD^{tree}')" now >>"$W/.git/harness-check-passed"
run_gate "git push";                       expect "P42: 先端の中身（ツリー）にフルの検査の記録があれば通す" allow
g -C "$W" commit -q --amend -m "i: メッセージだけ直す" && stamp
run_gate "git push";                       expect "P42b: メッセージだけ直したコミットは、中身が同じなので記録が効く" allow
printf 'i\n' >>"$W/a.sh" && g -C "$W" commit -q -am i && stamp
run_gate "git push";                       expect "P43: 記録の後に中身を変えたコミットを足すと、記録は効かなくなる" deny 'フルの検査が通っていない'
g -C "$W" config harness.pushRequiresCheck false
run_gate "git push";                       expect "P44: git config harness.pushRequiresCheck false なら求めない" allow
g -C "$W" config --unset harness.pushRequiresCheck

echo
echo "tests/push-gate.sh: pass=$passed fail=$failed"
[ "$failed" = 0 ] || { printf '  failed: %s\n' "${failed_names[@]}"; exit 1; }
