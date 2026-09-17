#!/usr/bin/env bash
# tests/doctor.sh — harness doctor のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/doctor.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 枠:  scenario "<名前>" <setup関数> <expect関数>
#   setup 関数 : $WORK（使い捨ての一時ディレクトリ）にプロジェクトを作り、$PROJ を設定する
#   expect 関数: run_doctor / run_doctor_no_path などを呼び、expect_* で表明する
# シナリオを足すときは、先に落ちるシナリオを書いてから doctor.sh に診断項目を足す（TDD）。
#
# 直し方が単一の実行可能なコマンドである項目は、expect 関数の中で
# 「壊す → doctor で当該行が出る → apply_fix で直し方どおりに実行 → doctor で当該行が消える」
# まで表明する。手順設計が要るもの（B3 の manifest 破損全般、B5 の CRLF 化、B7 の版ずれとマーカー
# 重複、B8 の「既存ファイルを書き換えた」系）は harness update が .harness/conflicts/ への
# CONFLICT を出すだけで直らない（実測済み）。個別に手順を決めるまでこの枠には入れない。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"

passed=0; failed=0
failed_names=()
WORK=""; PROJ=""; OUT=""; CODE=0
errors=()

# ---------------------------------------------------------------- 表明
expect_code() { # 期待する終了コード
  [ "$CODE" = "$1" ] || errors+=("終了コード: 期待 $1 / 実際 $CODE")
}
expect_out() { # 出力にこの正規表現があること
  printf '%s\n' "$OUT" | grep -qE "$1" || errors+=("出力に /$1/ が無い")
}
expect_not_out() { # 出力にこの正規表現が無いこと
  if printf '%s\n' "$OUT" | grep -qE "$1"; then errors+=("出力に /$1/ があってはいけない"); fi
}

# ---------------------------------------------------------------- 実行
run_doctor() { # 導入済みプロジェクトで CLI 経由の doctor を回す
  OUT="$(cd "$PROJ" && bash .harness/bin/harness doctor 2>&1)"; CODE=$?
}
run_doctor_in() { # <dir> [args...] 任意のディレクトリで、このリポジトリの bin/harness から doctor を回す
  local dir="$1"; shift
  OUT="$(cd "$dir" && bash "$REPO/bin/harness" doctor "$@" 2>&1)"; CODE=$?
}
run_doctor_without_path() { # PATH を潰して doctor.sh を直接回す（git 不在の再現）
  OUT="$(cd "$PROJ" && PATH=/nonexistent "$BASH_BIN" .harness/scripts/doctor.sh 2>&1)"; CODE=$?
}
run_doctor_with_broken_git() { # git だけが使えない PATH で doctor.sh を直接回す（git 無しでも内容比較が効くか）
  OUT="$(cd "$PROJ" && PATH="$WORK/nogit:$PATH" "$BASH_BIN" .harness/scripts/doctor.sh 2>&1)"; CODE=$?
}
apply_fix() { # <直し方どおりのコマンド文字列> — $PROJ の中でコピペしたのと同じように実行する
  ( cd "$PROJ" && eval "$1" ) >/dev/null 2>&1
}

# ---------------------------------------------------------------- setup 部品
setup_empty() { # 未導入（git リポジトリですらない）ディレクトリ
  PROJ="$WORK/empty"; mkdir -p "$PROJ"
}
setup_init() { # 使い捨てプロジェクトを作って harness init する
  PROJ="$WORK/p"; mkdir -p "$PROJ"
  (
    cd "$PROJ" &&
    git init -q . &&
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    bash "$REPO/bin/harness" init --source "$REPO"
  ) >/dev/null 2>&1 || { errors+=("setup: harness init に失敗した"); return 1; }
}

# ---------------------------------------------------------------- 枠
scenario() { # <名前> <setup関数> <expect関数>
  local name="$1" setup="$2" expect="$3"
  errors=(); PROJ=""; OUT=""; CODE=0
  WORK="$(mktemp -d)" || { echo "tests/doctor.sh: mktemp -d に失敗した"; exit 2; }
  if "$setup"; then "$expect"; fi
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

# D1. 導入直後の doctor は FAIL 0 で exit 0。各行は「OK|WARN|FAIL  項目  →  直し方」形式、最後に集計行。
expect_fresh_install() {
  run_doctor
  expect_code 0
  expect_out '^(OK|WARN|FAIL) '
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=0$'
  expect_not_out '^FAIL '
  # WARN / FAIL 行には直し方（→）が付く
  if printf '%s\n' "$OUT" | grep -E '^(WARN|FAIL) ' | grep -qv '→'; then
    errors+=("直し方（→）の無い WARN / FAIL 行がある")
  fi
}
scenario "D1: init 直後の doctor は FAIL 0 / exit 0" setup_init expect_fresh_install

# A1. help に doctor の usage 行がある。
expect_help_has_doctor() {
  OUT="$(cd "$PROJ" && bash .harness/bin/harness help 2>&1)"; CODE=$?
  expect_code 0
  expect_out 'harness doctor'
}
scenario "A1: help に doctor の usage 行がある" setup_init expect_help_has_doctor

# D3 / A3. 未導入ディレクトリでは導入コピーが無い旨と harness init の案内を出して exit 2。
expect_not_installed() {
  run_doctor_in "$PROJ"
  expect_code 2
  expect_out '導入コピーが無い'
  expect_out 'harness init'
}
scenario "D3: 未導入ディレクトリで exit 2 と harness init の案内" setup_empty expect_not_installed

# B1. git が無ければ FAIL（PATH を潰した sub-shell で再現）。exit は 1。
# 注: bash の版判定は BASH_VERSINFO[0] で行うが、BASH_VERSINFO は readonly で上書きできないため
#     「bash < 4」のシナリオはここでは再現しない（実機が bash 3 の環境で doctor を回して確認する）。
expect_missing_git() {
  run_doctor_without_path
  expect_code 1
  expect_out '^FAIL .*git'
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=[1-9][0-9]*$'
}
scenario "B1: git 不在なら FAIL / exit 1" setup_init expect_missing_git

# B3. manifest が壊れていれば FAIL（存在はするが harness_version 等が読めない形にする）。
setup_broken_manifest() {
  setup_init || return 1
  printf '{ "broken"\n' > "$PROJ/.harness/manifest.json"
}
expect_broken_manifest() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*manifest'
  # 黙ってスキップしない: manifest に依存する診断を飛ばしたことが出力で分かる
  expect_out '^WARN .*スキップ'
}
scenario "B3: manifest が壊れていれば FAIL" setup_broken_manifest expect_broken_manifest

# B3. manifest のエントリが 1 行 1 件で書かれていなければ FAIL（bin/harness も同じ前提で読めない）。
# 偽の全快の再発防止: 以前は grep -c の `|| echo 0` が "0\n0" を作って整数比較が壊れ、
# 「エントリ 0 件」のガードが常に偽になり、managed ファイルを消しても FAIL 0 / exit 0 を返していた。
setup_manifest_entries_one_line() {
  setup_init || return 1
  # files の各エントリを 1 行に畳む（整形ツールを通した manifest を模す）。見出しキーは 1 行 1 個のまま。
  awk '/^    \{"path"/ { sub(/^ +/, ""); printf "%s", $0; next } { print }' \
    "$PROJ/.harness/manifest.json" > "$PROJ/.harness/manifest.tmp" &&
    mv "$PROJ/.harness/manifest.tmp" "$PROJ/.harness/manifest.json" || return 1
  # 壊れた manifest を「全部そろっている」と報告しないことを見るため、managed ファイルも消しておく
  rm -f "$PROJ/.harness/scripts/gc.sh" "$PROJ/.harness/state-template/progress.json"
}
expect_manifest_entries_one_line() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*manifest'
  expect_not_out 'integer expression expected'
  expect_not_out '^OK .*manifest 記載ファイル'
  expect_out '^WARN .*スキップ'
}
scenario "B3: エントリが 1 行 1 件でなければ FAIL（偽の全快を出さない）" setup_manifest_entries_one_line expect_manifest_entries_one_line

# B3. files が空なら FAIL（エントリ 0 件のガードが効いているか）。
setup_manifest_empty_files() {
  setup_init || return 1
  awk '/^  "files": \[/ { print "  \"files\": []"; skip = 1; next }
       skip == 1 && /^  \]/ { skip = 0; next }
       skip == 1 { next }
       { print }' \
    "$PROJ/.harness/manifest.json" > "$PROJ/.harness/manifest.tmp" &&
    mv "$PROJ/.harness/manifest.tmp" "$PROJ/.harness/manifest.json" || return 1
  rm -f "$PROJ/.harness/scripts/gc.sh"
}
expect_manifest_empty_files() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*manifest'
  expect_not_out 'integer expression expected'
  expect_not_out '^OK .*manifest 記載ファイル'
  expect_out '^WARN .*スキップ'
}
scenario "B3: files が空なら FAIL" setup_manifest_empty_files expect_manifest_empty_files

# B4. manifest 記載の managed ファイルを削除すると FAIL で一覧に出る。
setup_missing_managed_file() {
  setup_init || return 1
  rm -f "$PROJ/.harness/state-template/progress.json"
}
expect_missing_managed_file() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*state-template/progress\.json'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*state-template/progress\.json'
}
scenario "B4: managed ファイルの欠落は FAIL（update で直る）" setup_missing_managed_file expect_missing_managed_file

# B4. manifest 記載の seed ファイルを削除すると WARN（FAIL にはしない）。
setup_missing_seed_file() {
  setup_init || return 1
  rm -f "$PROJ/docs/tech-debt.md"
}
expect_missing_seed_file() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*docs/tech-debt\.md'
  expect_not_out '^FAIL .*docs/tech-debt\.md'
}
scenario "B4: seed ファイルの欠落は WARN" setup_missing_seed_file expect_missing_seed_file

# B5. managed ファイルを CRLF 化すると FAIL（autocrlf を疑う直し方付き）。
setup_crlf_managed_file() {
  setup_init || return 1
  awk '{printf "%s\r\n", $0}' "$PROJ/.harness/scripts/gc.sh" > "$PROJ/.harness/scripts/gc.sh.tmp" &&
    mv "$PROJ/.harness/scripts/gc.sh.tmp" "$PROJ/.harness/scripts/gc.sh"
}
expect_crlf_managed_file() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*scripts/gc\.sh'
  expect_out 'autocrlf'
}
scenario "B5: managed ファイルの CRLF 化は FAIL（autocrlf を疑う）" setup_crlf_managed_file expect_crlf_managed_file

# B5. .gitattributes から .harness/** の行を消すと WARN。
setup_missing_gitattributes_line() {
  setup_init || return 1
  grep -vxF '.harness/** text eol=lf' "$PROJ/.gitattributes" > "$PROJ/.gitattributes.tmp" &&
    mv "$PROJ/.gitattributes.tmp" "$PROJ/.gitattributes"
}
expect_missing_gitattributes_line() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*gitattributes'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*gitattributes'
  expect_out '^OK .*gitattributes'
}
scenario "B5: .gitattributes に .harness/** eol=lf が無ければ WARN（update で直る）" setup_missing_gitattributes_line expect_missing_gitattributes_line

# B6. core.hooksPath を外すと WARN（直し方に git config core.hooksPath .githooks）。
setup_no_hookspath() {
  setup_init || return 1
  git -C "$PROJ" config --unset core.hooksPath
}
expect_no_hookspath() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*hooks'
  expect_out 'git config core\.hooksPath \.githooks'
  apply_fix "git config core.hooksPath .githooks"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*hooks'
  expect_out '^OK .*hooks'
}
scenario "B6: core.hooksPath が外れていれば WARN（直し方のコマンドで直る）" setup_no_hookspath expect_no_hookspath

# B7. AGENTS.md のマーカーの v= を manifest と食い違わせると WARN（harness update を案内）。
setup_agents_version_mismatch() {
  setup_init || return 1
  sed -i 's/<!-- harness:begin v=[^ ]* -->/<!-- harness:begin v=0.0.0-mismatch -->/' "$PROJ/AGENTS.md"
}
expect_agents_version_mismatch() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*AGENTS\.md'
  expect_out 'harness update'
}
scenario "B7: AGENTS.md マーカーの版が manifest と食い違えば WARN" setup_agents_version_mismatch expect_agents_version_mismatch

# B7. AGENTS.md からマーカーを消すと FAIL。
setup_agents_marker_missing() {
  setup_init || return 1
  grep -v 'harness:begin\|harness:end' "$PROJ/AGENTS.md" > "$PROJ/AGENTS.md.tmp" &&
    mv "$PROJ/AGENTS.md.tmp" "$PROJ/AGENTS.md"
}
expect_agents_marker_missing() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*AGENTS\.md'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*AGENTS\.md'
}
scenario "B7: AGENTS.md のマーカーが無ければ FAIL（update で直る）" setup_agents_marker_missing expect_agents_marker_missing

# B7. AGENTS.md のマーカーを 2 組にすると FAIL。
setup_agents_marker_duplicated() {
  setup_init || return 1
  {
    echo '<!-- harness:begin v=0.3.0 -->'
    echo '<!-- harness:end -->'
  } >> "$PROJ/AGENTS.md"
}
expect_agents_marker_duplicated() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*AGENTS\.md'
}
scenario "B7: AGENTS.md のマーカーが 2 組あれば FAIL" setup_agents_marker_duplicated expect_agents_marker_duplicated

# B11. .gitignore から .harness/state/ を消すと WARN。
setup_missing_gitignore_state() {
  setup_init || return 1
  grep -vxF '.harness/state/' "$PROJ/.gitignore" > "$PROJ/.gitignore.tmp" &&
    mv "$PROJ/.gitignore.tmp" "$PROJ/.gitignore"
}
expect_missing_gitignore_state() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*gitignore'
  expect_out '\.harness/state/'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*gitignore'
  expect_out '^OK .*gitignore'
}
scenario "B11: .gitignore に .harness/state/ が無ければ WARN（update で直る）" setup_missing_gitignore_state expect_missing_gitignore_state

# B8. CLAUDE.md から @AGENTS.md の import を消すと FAIL。
setup_claude_md_no_import() {
  setup_init || return 1
  grep -v '^@AGENTS\.md' "$PROJ/CLAUDE.md" > "$PROJ/CLAUDE.md.tmp" &&
    mv "$PROJ/CLAUDE.md.tmp" "$PROJ/CLAUDE.md"
}
expect_claude_md_no_import() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*CLAUDE\.md'
}
scenario "B8: CLAUDE.md に @AGENTS.md の import が無ければ FAIL" setup_claude_md_no_import expect_claude_md_no_import

# B8. .claude/skills/<name>/SKILL.md を書き換えて .agents/skills 側とずらすと WARN（harness update 案内付き）。
setup_claude_skill_drift() {
  setup_init || return 1
  echo "drift" >> "$PROJ/.claude/skills/harness/SKILL.md"
}
expect_claude_skill_drift() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*\.claude/skills/harness'
  expect_out 'harness update'
}
scenario "B8: .claude/skills が .agents/skills とずれれば WARN" setup_claude_skill_drift expect_claude_skill_drift

# B8. .claude/skills が CRLF 化されていれば内容のずれとして WARN。
# git hash-object は .gitattributes の text eol=lf フィルタを通すため、CRLF 化しただけの
# ファイルを「一致」と誤診していた（生バイトは違うのにハッシュが同じになる）。
setup_claude_skill_crlf() {
  setup_init || return 1
  local f="$PROJ/.claude/skills/harness/SKILL.md"
  awk '{ printf "%s\r\n", $0 }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}
expect_claude_skill_crlf() {
  run_doctor
  # 同じファイルは B5（CR の検出）でも FAIL する。ここで見るのは B8 の一致判定のほう。
  expect_code 1
  expect_out '^WARN .*\.claude/skills/harness'
  expect_not_out '^OK +\.claude/skills/\* は'
}
scenario "B8: CRLF 化した .claude/skills を内容のずれとして検出する" setup_claude_skill_crlf expect_claude_skill_crlf

# B8. git が使えない環境でも .claude/skills のずれを検出する（git 頼みの比較は両辺が空になって常に真だった）。
setup_claude_skill_drift_nogit() {
  setup_init || return 1
  echo "drift" >> "$PROJ/.claude/skills/harness/SKILL.md"
  mkdir -p "$WORK/nogit" &&
    printf '#!/usr/bin/env bash\nexit 127\n' > "$WORK/nogit/git" &&
    chmod +x "$WORK/nogit/git"
}
expect_claude_skill_drift_nogit() {
  run_doctor_with_broken_git
  expect_out '^WARN .*\.claude/skills/harness'
  expect_not_out '^OK +\.claude/skills/\* は'
  # ずれていないスキルまで巻き添えで WARN にしない
  expect_not_out '^WARN .*\.claude/skills/harness-maintain'
}
scenario "B8: git が使えなくても .claude/skills のずれを検出する" setup_claude_skill_drift_nogit expect_claude_skill_drift_nogit

# B8. .claude/agents/implementer.md を消すと FAIL。
setup_claude_agent_missing() {
  setup_init || return 1
  rm -f "$PROJ/.claude/agents/implementer.md"
}
expect_claude_agent_missing() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*implementer\.md'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*implementer\.md'
}
scenario "B8: .claude/agents/implementer.md が無ければ FAIL（update で直る）" setup_claude_agent_missing expect_claude_agent_missing

# B8. manifest の agents に claude を含まないとき（--agents codex で init）は CLAUDE.md 系の診断をしない。
setup_init_codex_only() {
  PROJ="$WORK/p"; mkdir -p "$PROJ"
  (
    cd "$PROJ" &&
    git init -q . &&
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    bash "$REPO/bin/harness" init --source "$REPO" --agents codex
  ) >/dev/null 2>&1 || { errors+=("setup: harness init --agents codex に失敗した"); return 1; }
}
expect_no_claude_adapter_check() {
  run_doctor
  expect_code 0
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=0$'
  expect_not_out 'CLAUDE\.md'
  expect_not_out '\.claude/skills'
  expect_not_out '\.claude/agents'
}
scenario "B8: agents に claude が無ければ Claude アダプタの診断をしない" setup_init_codex_only expect_no_claude_adapter_check

# B9. .agents/skills/role-reviewer を消すと FAIL。
setup_role_reviewer_missing() {
  setup_init || return 1
  rm -rf "$PROJ/.agents/skills/role-reviewer"
}
expect_role_reviewer_missing() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*role-reviewer'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*role-reviewer'
}
scenario "B9: .agents/skills/role-reviewer が無ければ FAIL（update で直る）" setup_role_reviewer_missing expect_role_reviewer_missing

# B10. source（ローカル）の VERSION を上げていると INFO で新版ありと出る。
setup_source_version_bump() {
  local src="$WORK/src"
  mkdir -p "$src" &&
    cp -r "$REPO/harness" "$src/harness" &&
    cp -r "$REPO/bin" "$src/bin" &&
    cp "$REPO/VERSION" "$src/VERSION" || { errors+=("setup: source コピーに失敗した"); return 1; }
  PROJ="$WORK/p"; mkdir -p "$PROJ"
  (
    cd "$PROJ" &&
    git init -q . &&
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    bash "$src/bin/harness" init --source "$src"
  ) >/dev/null 2>&1 || { errors+=("setup: harness init に失敗した"); return 1; }
  echo "9.9.9" > "$src/VERSION"
}
expect_source_version_bump() {
  run_doctor
  expect_code 0
  expect_out '^INFO .*9\.9\.9'
  # 回帰: 導入先に存在しない「bash bin/harness」を案内していないこと（この行が過去の実バグ）。
  expect_not_out 'bash bin/harness'
  expect_out 'bash \.harness/bin/harness update'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^INFO .*9\.9\.9'
  expect_out '^OK .*source の版は'
}
scenario "B10: source（ローカル）に新版があれば INFO（直し方どおりに update すると追従して消える）" setup_source_version_bump expect_source_version_bump

# B10. source が URL のときはネットワークに触らない（manifest の source を到達不能な URL に差し替えて確認）。
setup_source_is_url() {
  setup_init || return 1
  sed -i 's#"source": "[^"]*"#"source": "https://example.invalid/agent-harness.git"#' "$PROJ/.harness/manifest.json"
}
expect_source_is_url() {
  run_doctor
  expect_code 0
  expect_not_out 'Could not resolve|clone に失敗|fetch に失敗'
}
scenario "B10: source が URL ならネットワークに触らず完走する" setup_source_is_url expect_source_is_url

# 回帰: spec C1（直し方はそのまま実行できるコマンド）/ A1（導入先の CLI は .harness/bin/harness）。
# ソース（harness/scripts/doctor.sh。正本。導入コピーの .harness/scripts/doctor.sh ではない）に、
# 導入先に存在しない「bash bin/harness」（.harness/ を欠いた CLI パス）が二度と紛れ込まないことを
# 個別のシナリオに頼らず機械的に保証する。使い捨てプロジェクトは要らない。
setup_repo_source() { PROJ="$WORK"; }
expect_no_bare_bin_harness_path() {
  CODE=0
  local hits
  hits="$(grep -n 'bash bin/harness' "$REPO/harness/scripts/doctor.sh" 2>/dev/null || true)"
  OUT="$hits"
  if [ -n "$hits" ]; then
    errors+=("harness/scripts/doctor.sh に、導入先に存在しない「bash bin/harness」が残っている（.harness/bin/harness に統一する）: $hits")
  fi
}
scenario "回帰: doctor.sh の直し方に「bash bin/harness」(存在しないパス) が残っていない" setup_repo_source expect_no_bare_bin_harness_path

# ================================================================ 集計
echo
echo "tests/doctor.sh: pass=$passed fail=$failed"
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  doctor の出力（上の「直近の出力」）と harness/scripts/doctor.sh を突き合わせて直す。"
  echo "  導入コピー（.harness/scripts/doctor.sh）ではなく harness/scripts/doctor.sh を直し、bash bin/harness update で同期する。"
  exit 1
fi
