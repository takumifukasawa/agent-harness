#!/usr/bin/env bash
# tests/lockfile.sh — lockfile 方式（1.0.0。決定 0013）のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/lockfile.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 守る不変条件:
#   - 導入先がコミットするのは manifest・seed・AGENTS.md・CLAUDE.md・.claude/settings.json・.gitignore だけ。
#     それ以外の配布物は .gitignore の管理ブロックに載る
#   - manifest は source_commit（配った source のコミット）を持つ
#   - install は source_commit の版をそのまま入れ、manifest を変えない（source が先に進んでいても）
#   - source_commit が source に無ければ、install は何も書かずに止まり update を案内する
#   - update は版を上げ、source_commit を書き換える
#   - 既にコミットされた配布物は、update が index から外す手順を案内する（勝手には外さない）
#
# source は使い捨てのリポジトリ（このリポジトリの作業ツリーの今の内容を 1 コミットにしたもの）を使う。
# install は source のコミットを git archive で取り出すので、このリポジトリの未コミットの変更を試すには
# 作業ツリーの内容をコミットした source が要る。HOME も使い捨てにし、実際の PC のキャッシュに触らない。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)" || { echo "tests/lockfile.sh: mktemp -d に失敗した"; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM
export HOME="$WORK/home"; mkdir -p "$HOME"

passed=0; failed=0
failed_names=()
errors=()
OUT=""; CODE=0

g() { git -c user.email=t@t -c user.name=t "$@"; }

ok_or_fail() { # <名前>
  if [ "${#errors[@]}" -eq 0 ]; then passed=$((passed + 1)); echo "PASS  $1"
  else
    failed=$((failed + 1)); failed_names+=("$1"); echo "FAIL  $1"
    printf '      %s\n' "${errors[@]}"
    printf '%s\n' "$OUT" | tail -15 | sed 's/^/      | /'
  fi
  errors=()
}

# ---------------------------------------------------------------- フィクスチャ
# 使い捨ての source（v1）を作る
SRC="$WORK/src"
mkdir -p "$SRC" && cp -R "$REPO/harness" "$REPO/bin" "$REPO/VERSION" "$REPO/CHANGELOG.md" "$SRC/" &&
  g -C "$SRC" init -q -b main . && g -C "$SRC" add -A && g -C "$SRC" commit -q -m v1 ||
  { echo "tests/lockfile.sh: source の準備に失敗した"; exit 2; }
V1="$(git -C "$SRC" rev-parse HEAD)"

# 導入済みでコミット済みのプロジェクト（init 1 回。各シナリオは複製して使う）
BASE="$WORK/base"
mkdir -p "$BASE" && g -C "$BASE" init -q -b main . && g -C "$BASE" commit -q --allow-empty -m init &&
  (cd "$BASE" && bash "$SRC/bin/harness" init --source "$SRC") >"$WORK/init.out" 2>&1 &&
  g -C "$BASE" add -A && g -C "$BASE" commit -q --no-verify -m harness ||
  { echo "tests/lockfile.sh: init に失敗した"; cat "$WORK/init.out"; exit 2; }

clone_base() { # <dir>  BASE を clone する（コミットされた物だけが来る = 別の PC の clone と同じ）
  git clone -q "$BASE" "$1"
}

# ---------------------------------------------------------------- L1: コミットされる物
L1() {
  local tracked bad
  tracked="$(git -C "$BASE" ls-files)"
  bad="$(printf '%s\n' "$tracked" | grep -vE '^(\.harness/manifest\.json|\.harness/checks\.sh|AGENTS\.md|CLAUDE\.md|\.claude/settings\.json|\.gitignore|\.gitattributes|docs/.*)$' || true)"
  [ -z "$bad" ] || errors+=("コミットされてはいけない物が入った: $(printf '%s ' $bad)")
  for p in .harness/bin/harness .harness/scripts/check.sh .agents/skills/harness/SKILL.md .claude/agents/implementer.md .githooks/pre-commit .codex/hooks.json; do
    [ -f "$BASE/$p" ] || { errors+=("init が $p を配っていない"); continue; }
    git -C "$BASE" check-ignore -q "$p" || errors+=("$p が .gitignore に入っていない")
  done
  git -C "$BASE" check-ignore -q CLAUDE.md && errors+=("CLAUDE.md が ignore されている（プロジェクトの内容が消える）")
  grep -q "\"source_commit\": \"$V1\"" "$BASE/.harness/manifest.json" || errors+=("manifest に source_commit=$V1 が無い")
  [ "$(cat "$BASE/.harness/installed" 2>/dev/null)" = "$V1" ] || errors+=(".harness/installed が $V1 ではない")
  git -C "$BASE" check-ignore -q .harness/installed || errors+=(".harness/installed が ignore されていない")
  # push の前にセキュリティレビューの結果を確かめる関門（1.2.0。決定 0014）
  [ -f "$BASE/.harness/scripts/push-gate.sh" ] || errors+=("init が .harness/scripts/push-gate.sh を配っていない")
  git -C "$BASE" check-ignore -q .harness/scripts/push-gate.sh || errors+=("push-gate.sh が .gitignore に入っていない")
  if command -v node >/dev/null 2>&1; then
    node -e 'const s=require(process.argv[1]);const h=((s.hooks||{}).PreToolUse||[]).flatMap(e=>e.hooks||[]);process.exit(h.some(x=>String(x.command).includes(".harness/scripts/push-gate.sh"))?0:1)' "$BASE/.claude/settings.json" ||
      errors+=(".claude/settings.json の PreToolUse に push-gate が無い")
  fi
}
L1; ok_or_fail "L1: 配布物は .gitignore され、コミットされるのは manifest・seed・AGENTS.md・CLAUDE.md・settings だけ"

# ---------------------------------------------------------------- L2: clone 直後に install
L2() {
  local C="$WORK/l2" before
  clone_base "$C"
  [ -f "$C/.harness/bin/harness" ] && errors+=("clone 直後に同梱 CLI がある（コミットされている）")
  before="$(cat "$C/.harness/manifest.json")"
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install 2>&1)"; CODE=$?
  [ "$CODE" = 0 ] || errors+=("install の終了コード $CODE")
  [ -f "$C/.harness/bin/harness" ] && [ -f "$C/.agents/skills/harness/SKILL.md" ] && [ -f "$C/.githooks/pre-commit" ] ||
    errors+=("install が配布物を入れていない")
  [ "$(cat "$C/.harness/manifest.json")" = "$before" ] || errors+=("install が manifest を変えた")
  [ -z "$(git -C "$C" status --porcelain)" ] || errors+=("install 後に git status が空でない: $(git -C "$C" status --porcelain | tr '\n' ' ')")
  [ "$(cat "$C/.harness/installed" 2>/dev/null)" = "$V1" ] || errors+=(".harness/installed が書かれていない")
  [ "$(git -C "$C" config core.hooksPath)" = ".githooks" ] || errors+=("install が core.hooksPath を設定していない")
  (cd "$C" && bash .harness/bin/harness status) | grep -q 'missing=0' || errors+=("install 後に missing がある")
}
L2; ok_or_fail "L2: clone 直後の install で配布物が入り、manifest と git status は変わらない"

# ---------------------------------------------------------------- L3: source が進んでも固定した版が入る
L3() {
  local C="$WORK/l3"
  printf '\n# L3-NEWER-MARKER\n' >>"$SRC/harness/scripts/session-start.sh"
  g -C "$SRC" commit -q -am v2
  clone_base "$C"
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install 2>&1)"; CODE=$?
  [ "$CODE" = 0 ] || errors+=("install の終了コード $CODE")
  grep -q 'L3-NEWER-MARKER' "$C/.harness/scripts/session-start.sh" 2>/dev/null &&
    errors+=("install が固定した版ではなく source の最新を入れた")
  [ -f "$C/.harness/scripts/session-start.sh" ] || errors+=("session-start.sh が入っていない")
}
L3; ok_or_fail "L3: source が先に進んでいても、install は manifest に固定した版を入れる"

# ---------------------------------------------------------------- L4: update が版を上げ、固定を書き換える
L4() {
  local C="$WORK/l4" v2
  v2="$(git -C "$SRC" rev-parse HEAD)"
  cp -a "$BASE" "$C"
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash .harness/bin/harness update 2>&1)"; CODE=$?
  [ "$CODE" = 0 ] || errors+=("update の終了コード $CODE")
  grep -q "\"source_commit\": \"$v2\"" "$C/.harness/manifest.json" || errors+=("update が source_commit を $v2 に書き換えていない")
  grep -q 'L3-NEWER-MARKER' "$C/.harness/scripts/session-start.sh" || errors+=("update が新しい版を入れていない")
  [ "$(cat "$C/.harness/installed")" = "$v2" ] || errors+=(".harness/installed が新しい版になっていない")
  # 版を上げたときにコミットされるのは manifest だけ（配布物は ignore 済み）
  local changed; changed="$(git -C "$C" status --porcelain | awk '{print $2}' | tr '\n' ' ')"
  [ "$changed" = ".harness/manifest.json " ] || errors+=("update 後の変更が manifest だけではない: ${changed}")
}
L4; ok_or_fail "L4: update は版を上げて source_commit を書き換え、コミットに出るのは manifest だけ"

# ---------------------------------------------------------------- L5: 他の人が上げた版を pull した後
L5() {
  local C="$WORK/l5" A="$WORK/l5-a"
  clone_base "$C"; (cd "$C" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install) >/dev/null 2>&1
  # 別の clone（A さん）で update して manifest を push した、を BASE への commit で模す
  clone_base "$A"; (cd "$A" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install) >/dev/null 2>&1
  (cd "$A" && HARNESS_SOURCE="$SRC" bash .harness/bin/harness update) >/dev/null 2>&1
  g -C "$A" commit -q --no-verify -am "bump harness" && g -C "$A" push -q origin HEAD:main 2>/dev/null ||
    g -C "$BASE" pull -q "$A" main
  g -C "$C" pull -q origin main 2>/dev/null || g -C "$C" pull -q "$A" main
  OUT="$(cd "$C" && bash .harness/bin/harness status 2>&1)"
  printf '%s\n' "$OUT" | grep -q 'harness install で揃える' || errors+=("版ずれを status が案内しない")
  OUT="$(cd "$C" && bash .harness/scripts/session-start.sh 2>&1)"
  printf '%s\n' "$OUT" | grep -q 'harness install で揃える' || errors+=("版ずれを SessionStart が案内しない")
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install 2>&1)"; CODE=$?
  [ "$CODE" = 0 ] || errors+=("install の終了コード $CODE")
  grep -q 'L3-NEWER-MARKER' "$C/.harness/scripts/session-start.sh" || errors+=("pull 後の install が新しい固定の版を入れていない")
}
L5; ok_or_fail "L5: 他の clone が上げた manifest を pull すると版ずれを案内し、install で揃う"

# ---------------------------------------------------------------- L6: 固定したコミットが source に無い
L6() {
  local C="$WORK/l6" S2="$WORK/src-rewritten"
  # 履歴を作り直した source（固定したコミットを持たない）
  mkdir -p "$S2" && cp -R "$SRC/harness" "$SRC/bin" "$SRC/VERSION" "$SRC/CHANGELOG.md" "$S2/" &&
    g -C "$S2" init -q -b main . && g -C "$S2" add -A && g -C "$S2" commit -q -m fresh
  clone_base "$C"
  OUT="$(cd "$C" && HARNESS_SOURCE="$S2" bash "$SRC/bin/harness" install 2>&1)"; CODE=$?
  [ "$CODE" != 0 ] || errors+=("固定したコミットが無いのに install が成功した")
  printf '%s\n' "$OUT" | grep -q 'harness update' || errors+=("update を案内していない")
  [ -f "$C/.harness/bin/harness" ] && errors+=("止まるはずの install が配布物を書いた")
  return 0
}
L6; ok_or_fail "L6: 固定したコミットが source に無ければ、install は何も書かずに止まり update を案内する"

# ---------------------------------------------------------------- L7: source_commit の無い古い manifest
L7() {
  local C="$WORK/l7"
  cp -a "$BASE" "$C"
  sed '/"source_commit"/d' "$C/.harness/manifest.json" >"$C/m.tmp" && mv "$C/m.tmp" "$C/.harness/manifest.json"
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash "$SRC/bin/harness" install 2>&1)"; CODE=$?
  [ "$CODE" != 0 ] || errors+=("source_commit が無いのに install が成功した")
  printf '%s\n' "$OUT" | grep -q 'harness update' || errors+=("update を案内していない")
  return 0
}
L7; ok_or_fail "L7: source_commit の無い（1.0.0 より前の）manifest では install は止まり update を案内する"

# ---------------------------------------------------------------- L8: 配布物をコミット済みの古い導入先の移行
L8() {
  local C="$WORK/l8"
  cp -a "$BASE" "$C"
  # 1.0.0 より前の導入先を模す: 配布物を強制的にコミットし、.gitignore の管理ブロックを消す
  awk '/^# >>> agent-harness managed/{s=1;next} /^# <<< agent-harness managed/{s=0;next} !s' "$C/.gitignore" >"$C/gi.tmp" &&
    cat "$C/gi.tmp" >"$C/.gitignore" && rm -f "$C/gi.tmp"
  g -C "$C" add -A && g -C "$C" commit -q --no-verify -m "old style"
  local n_before; n_before="$(git -C "$C" ls-files | wc -l | tr -d ' ')"
  OUT="$(cd "$C" && HARNESS_SOURCE="$SRC" bash .harness/bin/harness update 2>&1)"; CODE=$?
  [ "$CODE" = 0 ] || errors+=("update の終了コード $CODE")
  printf '%s\n' "$OUT" | grep -q 'git rm -q --cached' || errors+=("index から外す手順を案内していない")
  [ "$(git -C "$C" ls-files | wc -l | tr -d ' ')" = "$n_before" ] || errors+=("update が勝手に追跡を外した")
  grep -qxF '# >>> agent-harness managed (do not commit; restore with: harness install)' "$C/.gitignore" ||
    errors+=("update が .gitignore の管理ブロックを足していない")
  OUT="$(cd "$C" && bash .harness/bin/harness doctor 2>&1)"
  printf '%s\n' "$OUT" | grep -q '^WARN .*配布物がまだ git に追跡されている' || errors+=("doctor が追跡中の配布物を報告しない")
  # 案内どおりに外すと、作業ツリーのファイルは残り、doctor の WARN が消える
  (cd "$C" && git ls-files -ci --exclude-standard -z | xargs -0 git rm -q --cached --) >/dev/null 2>&1
  [ -f "$C/.harness/bin/harness" ] || errors+=("追跡を外したら作業ツリーのファイルが消えた")
  OUT="$(cd "$C" && bash .harness/bin/harness doctor 2>&1)"
  printf '%s\n' "$OUT" | grep -q '^OK .*配布物は git に追跡されていない' || errors+=("追跡を外した後も doctor が OK にならない")
}
L8; ok_or_fail "L8: 配布物をコミット済みの導入先は、update が外し方を案内し（勝手に外さない）、doctor が WARN を出す"

# ---------------------------------------------------------------- L9: clone 直後の案内
L9() {
  local C="$WORK/l9" cmd
  clone_base "$C"
  OUT="$(cd "$C" && bash "$SRC/bin/harness" doctor 2>&1)"; CODE=$?
  printf '%s\n' "$OUT" | grep -q 'harness install' || errors+=("clone 直後の doctor が install を案内しない")
  OUT="$(cd "$C" && bash "$SRC/bin/harness" check 2>&1)"; CODE=$?
  [ "$CODE" != 0 ] || errors+=("clone 直後の check が成功した")
  printf '%s\n' "$OUT" | grep -q 'harness install' || errors+=("clone 直後の check が install を案内しない")
  # コミットされている .claude/settings.json の SessionStart は、スクリプトが無くても黙らない
  if command -v node >/dev/null 2>&1; then
    cmd="$(node -e 'const s=require(process.argv[1]);const h=s.hooks.SessionStart.flatMap(e=>e.hooks).find(h=>h.command.includes(".harness/"));console.log(h?h.command:"")' "$C/.claude/settings.json")"
    if [ -z "$cmd" ]; then errors+=("settings.json に harness の SessionStart が無い")
    else
      OUT="$(cd "$C" && CLAUDE_PROJECT_DIR="$C" bash -c "$cmd" 2>&1)"; CODE=$?
      [ "$CODE" = 0 ] || errors+=("SessionStart のコマンドが非 0 で終わった（${CODE}）")
      printf '%s\n' "$OUT" | grep -q 'harness install' || errors+=("SessionStart が install を案内しない")
    fi
  fi
}
L9; ok_or_fail "L9: clone 直後（配布物なし）は doctor・check・SessionStart が install を案内する"

# ---------------------------------------------------------------- L10: CRLF の .gitignore
L10() {
  local C="$WORK/l10" n
  cp -a "$BASE" "$C"
  # Windows の core.autocrlf で .gitignore が CRLF になった状態
  awk '{printf "%s\r\n", $0}' "$C/.gitignore" >"$C/gi.tmp" && cat "$C/gi.tmp" >"$C/.gitignore" && rm -f "$C/gi.tmp"
  (cd "$C" && HARNESS_SOURCE="$SRC" bash .harness/bin/harness update) >/dev/null 2>&1
  (cd "$C" && HARNESS_SOURCE="$SRC" bash .harness/bin/harness update) >/dev/null 2>&1
  n="$(tr -d '\r' <"$C/.gitignore" | grep -cxF '# >>> agent-harness managed (do not commit; restore with: harness install)')"
  [ "$n" = 1 ] || errors+=("管理ブロックが ${n} 個ある（CRLF の .gitignore でダブった）")
  OUT="$(cd "$C" && bash .harness/bin/harness doctor 2>&1)"
  printf '%s\n' "$OUT" | grep -q '^OK .*配布物の管理ブロックがある' || errors+=("CRLF の .gitignore で doctor が管理ブロックを見つけられない")
}
L10; ok_or_fail "L10: CRLF の .gitignore でも管理ブロックはダブらず、doctor も見つける"

echo
echo "tests/lockfile.sh: pass=$passed fail=$failed"
[ "$failed" = 0 ] || { printf '  failed: %s\n' "${failed_names[@]}"; exit 1; }
