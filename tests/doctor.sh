#!/usr/bin/env bash
# tests/doctor.sh — harness doctor のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方:  bash tests/doctor.sh [<シナリオ名の部分一致>]
#   引数なし: 全シナリオを実行する。
#   引数あり: シナリオ名（scenario の第 1 引数）にその文字列を含むものだけ実行する。
#             例:  bash tests/doctor.sh "B6"        core.hooksPath のシナリオだけ
#                  bash tests/doctor.sh "gitignore"  gitignore 関連だけ
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。フィルタに 1 件も一致しなければ 1。
#
# 枠:  scenario "<名前>" <setup関数> <expect関数>
#   setup 関数 : ${WORK}（使い捨ての一時ディレクトリ）にプロジェクトを作り、$PROJ を設定する
#   expect 関数: run_doctor / run_doctor_no_path などを呼び、expect_* で表明する
# シナリオを足すときは、先に落ちるシナリオを書いてから doctor.sh に診断項目を足す（TDD）。
#
# doctor の診断だけでなく、B10 が前提にする source の解決順（環境変数 HARNESS_SOURCE >
# .harness/source.local > manifest.json の source。決定 0004）も、末尾の「T09」節でまとめて表明する。
# init / update / status / diff / upstream がその順を通ることと、上書きが無いときに status / doctor が
# ネットワークへ出ないことが対象。
#
# 直し方が単一の実行可能なコマンドである項目は、expect 関数の中で
# 「壊す → doctor で当該行が出る → apply_fix で直し方どおりに実行 → doctor で当該行が消える」
# まで表明する。T14 時点でこの枠に乗っているのは B3（manifest 破損。決定 0003 のとおり、
# version/source/agents の見出しが読めれば harness update、読めなければ壊れたものを退避して
# harness init --source をやり直す）/ B4（managed・seed ファイルの欠落）/ B5（CRLF 化。決定
# 0002 以降 update が生バイトで復元する）/ B6（git hooks。プロジェクトルートが git リポジトリで
# なければ git init から）/ B7（版ずれ・マーカー重複。決定 0002 以降 update が畳む）。
# B8 の「既存ファイルを書き換えた」系（.claude/skills のドリフトなど）はまだ個別の手順を
# 決めていないため、この枠にまだ入れていない。
#
# フィクスチャ共有: harness init はプロセス生成とファイル I/O が支配的で 1 回 ≒ 11 秒かかる。
# 26 シナリオの大半が「まず素の harness init をする」という同じ前提から始まるので、その前提を
# ensure_fixture で 1 回だけ作り、setup_init はそれを cp -a で複製するだけにする（init は再実行
# しない）。複製が「init 直後の状態」とずれていないかは、最初のシナリオ（D1）が複製直後の
# doctor で FAIL 0 になることを確認して担保する。ずれれば D1 が落ちて気付ける。
#
# 確認項目の束ね: 互いに干渉しない WARN（B4 の seed ファイル欠落 / B5 の .gitattributes /
# B6 の hooksPath / B11 の gitignore）は、ensure_warn_bundle が 1 つのプロジェクトでまとめて
# 壊し、doctor の前後 2 回分の出力をキャッシュする。対応する scenario はそのキャッシュを読んで
# 自分の持ち場だけを assert する（往復は 1 回に減るが、scenario 本体の本数・assert の本数は
# 個別に検証していたときのまま変えていない）。診断を途中で止めうる FAIL（manifest 破損など）
# は束ねず独立に残す。
#
# 同じ理由で、互いに独立して検証できる FAIL（B4 の managed ファイル欠落 / B8 の
# implementer.md 欠落 / B9 の role-reviewer 欠落。いずれも harness update で復元できる）は
# ensure_fail_bundle が同様に 1 つのプロジェクトにまとめて壊す。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"
FILTER="${1:-}"

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
run_doctor_without_node_jq() { # node/jq の実行ファイルだけを隠して doctor を回す（C3 の検証）
  # PATH=/nonexistent（run_doctor_without_path）は git/sed/awk まで消してしまい、C3（node/jq が
  # 無くても「全項目」が動く）の検証にならない（manifest が読めず B4/B5/B8 が丸ごとスキップされる）。
  # 「node/jq を含むディレクトリごと PATH から外す」だと、macOS 15+ のように jq が /usr/bin に
  # git・sed・tr 等と同居している実機で、それらまで道連れに消えてしまう（実測。tech-debt #3）。
  # ディレクトリ単位ではなく実行ファイル単位で隠す: 元の PATH を先頭から辿り、node/jq 以外の
  # 実行ファイルだけを 1 つのスタブディレクトリへ最初に見つかったものだけ symlink し、
  # PATH をそのスタブ 1 本に絞る（PATH の優先順位はそのまま保たれる）。
  local stub="$WORK/stub-no-node-jq" dir f name
  rm -rf "$stub"; mkdir -p "$stub"
  local IFS=':'
  for dir in $PATH; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      name="$(basename "$f")"
      case "$name" in node|jq) continue;; esac
      [ -e "$stub/$name" ] || ln -s "$f" "$stub/$name" 2>/dev/null
    done
  done
  OUT="$(cd "$PROJ" && PATH="$stub" "$BASH_BIN" .harness/bin/harness doctor 2>&1)"; CODE=$?
}
apply_fix() { # <直し方どおりのコマンド文字列> — $PROJ の中でコピペしたのと同じように実行する
  ( cd "$PROJ" && eval "$1" ) >/dev/null 2>&1
}
# GNU sed の `sed -i 'expr' file` は BSD/macOS sed では通らない（-i の直後に空でもバックアップ拡張子の
# 引数が要る。付けないと sed 側の解釈がずれ、次の引数=ファイルパスをスクリプトとして食って
# 「invalid command code」で壊れる。実測: macOS 実機）。両方で同じ結果になる tmp+mv に統一する。
sed_i() { # <sed 式> <file>
  local tmp; tmp="$(mktemp)"
  sed "$1" "$2" >"$tmp" && mv "$tmp" "$2"
}

# ---------------------------------------------------------------- フィクスチャ（init 済みツリーの共有）
# SHARED はスイート全体で使う一時置き場。フィクスチャ本体はこの下に作り、個々のシナリオの
# ${WORK}（scenario ごとに作って rm -rf する）とは別に、最後にまとめて消す。
SHARED="$(mktemp -d)" || { echo "tests/doctor.sh: mktemp -d に失敗した（フィクスチャ置き場）"; exit 2; }
# Ctrl-C / CI のタイムアウト kill / 途中の exit のいずれでも使い捨てディレクトリを残さない
# （$WORK は scenario() が毎回作り直すので、trap 発火時点の最新値をそのまま参照すればよい）。
trap 'rm -rf "$WORK" "$SHARED" 2>/dev/null' EXIT INT TERM

FIXTURE_DONE=0; FIXTURE=""
ensure_fixture() { # 使い捨てプロジェクトに harness init した雛形ツリーを 1 回だけ作る
  [ "$FIXTURE_DONE" = 1 ] && return 0
  FIXTURE="$SHARED/fixture"; mkdir -p "$FIXTURE"
  (
    cd "$FIXTURE" &&
    git init -q . &&
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    bash "$REPO/bin/harness" init --source "$REPO"
  ) >/dev/null 2>&1 || { errors+=("setup: フィクスチャ構築（harness init）に失敗した"); return 1; }
  FIXTURE_DONE=1
}

# ---------------------------------------------------------------- setup 部品
setup_empty() { # 未導入（git リポジトリですらない）ディレクトリ
  PROJ="$WORK/empty"; mkdir -p "$PROJ"
}
setup_init() { # 使い捨てプロジェクトをフィクスチャ（${FIXTURE}）から複製する。harness init は走らせない
  ensure_fixture || return 1
  PROJ="$WORK/p"
  cp -a "$FIXTURE" "$PROJ" 2>/dev/null || { errors+=("setup: フィクスチャの複製に失敗した"); return 1; }
}

# ---------------------------------------------------------------- 束ね: 干渉しない WARN（B4/B5/B6/B11）
# .gitattributes の行 / core.hooksPath / .gitignore の行 / seed ファイル（docs/tech-debt.md）の欠落は、
# 別ファイル・別設定で互いに干渉しない WARN。4 シナリオ分の「壊す→doctor→直す→doctor」を 1 回の
# 往復にまとめ、各シナリオはキャッシュされた doctor 出力（前 / 後）を読むだけにする。直し方は元の
# シナリオごとの文言をそのまま使う（hooksPath は git config core.hooksPath .githooks 単体、他は
# harness update。apply_plan は mode に関わらずこの 3 つを毎回打ち直し、欠けた seed ファイルも
# 復元する＝実測済み。詳細は setup_missing_seed_file の注記）ので、両方適用しても矛盾はしない。
WARN_BUNDLE_DONE=0; WARN_BUNDLE_DIR=""
WARN_BUNDLE_OUT_BEFORE=""; WARN_BUNDLE_CODE_BEFORE=0
WARN_BUNDLE_OUT_AFTER=""; WARN_BUNDLE_CODE_AFTER=0
ensure_warn_bundle() {
  [ "$WARN_BUNDLE_DONE" = 1 ] && return 0
  ensure_fixture || return 1
  WARN_BUNDLE_DIR="$SHARED/warn-bundle"
  cp -a "$FIXTURE" "$WARN_BUNDLE_DIR" 2>/dev/null || { errors+=("setup: WARN 束ねフィクスチャの複製に失敗した"); return 1; }
  ( grep -vxF '.harness/** text eol=lf' "$WARN_BUNDLE_DIR/.gitattributes" >"$WARN_BUNDLE_DIR/.gitattributes.tmp" &&
    mv "$WARN_BUNDLE_DIR/.gitattributes.tmp" "$WARN_BUNDLE_DIR/.gitattributes" ) ||
    { errors+=("setup: .gitattributes の書き換えに失敗した"); return 1; }
  git -C "$WARN_BUNDLE_DIR" config --unset core.hooksPath ||
    { errors+=("setup: core.hooksPath の解除に失敗した"); return 1; }
  # B11 は state/ backup/ conflicts/ の 3 つを見る。3 つとも消してから doctor に通す
  # （以前は state/ だけを消しており、backup/ conflicts/ の欠落検知は未検証だった。low 指摘）。
  ( grep -vxF '.harness/state/' "$WARN_BUNDLE_DIR/.gitignore" | grep -vxF '.harness/backup/' | grep -vxF '.harness/conflicts/' \
      >"$WARN_BUNDLE_DIR/.gitignore.tmp" &&
    mv "$WARN_BUNDLE_DIR/.gitignore.tmp" "$WARN_BUNDLE_DIR/.gitignore" ) ||
    { errors+=("setup: .gitignore の書き換えに失敗した"); return 1; }
  rm -f "$WARN_BUNDLE_DIR/docs/tech-debt.md"
  WARN_BUNDLE_OUT_BEFORE="$(cd "$WARN_BUNDLE_DIR" && bash .harness/bin/harness doctor 2>&1)"; WARN_BUNDLE_CODE_BEFORE=$?
  ( cd "$WARN_BUNDLE_DIR" && git config core.hooksPath .githooks ) >/dev/null 2>&1
  ( cd "$WARN_BUNDLE_DIR" && bash .harness/bin/harness update ) >/dev/null 2>&1
  WARN_BUNDLE_OUT_AFTER="$(cd "$WARN_BUNDLE_DIR" && bash .harness/bin/harness doctor 2>&1)"; WARN_BUNDLE_CODE_AFTER=$?
  WARN_BUNDLE_DONE=1
}

# ------------------------------------------------ 束ね: 独立に検証できる FAIL（欠落 → update で復元）
# manifest 記載の managed ファイル（state-template/progress.json）/ .claude/agents/implementer.md /
# .agents/skills/role-reviewer は、どれも「manifest 記載ファイルが無い」という独立の FAIL で、
# B3 の manifest 破損のように後続の診断をスキップさせるものではない。直し方はどれも harness
# update 1 回。3 シナリオ分の往復を 1 回にまとめる。
FAIL_BUNDLE_DONE=0; FAIL_BUNDLE_DIR=""
FAIL_BUNDLE_OUT_BEFORE=""; FAIL_BUNDLE_CODE_BEFORE=0
FAIL_BUNDLE_OUT_AFTER=""; FAIL_BUNDLE_CODE_AFTER=0
ensure_fail_bundle() {
  [ "$FAIL_BUNDLE_DONE" = 1 ] && return 0
  ensure_fixture || return 1
  FAIL_BUNDLE_DIR="$SHARED/fail-bundle"
  cp -a "$FIXTURE" "$FAIL_BUNDLE_DIR" 2>/dev/null || { errors+=("setup: FAIL 束ねフィクスチャの複製に失敗した"); return 1; }
  rm -f "$FAIL_BUNDLE_DIR/.harness/state-template/progress.json"
  rm -f "$FAIL_BUNDLE_DIR/.claude/agents/implementer.md"
  rm -rf "$FAIL_BUNDLE_DIR/.agents/skills/role-reviewer"
  FAIL_BUNDLE_OUT_BEFORE="$(cd "$FAIL_BUNDLE_DIR" && bash .harness/bin/harness doctor 2>&1)"; FAIL_BUNDLE_CODE_BEFORE=$?
  ( cd "$FAIL_BUNDLE_DIR" && bash .harness/bin/harness update ) >/dev/null 2>&1
  FAIL_BUNDLE_OUT_AFTER="$(cd "$FAIL_BUNDLE_DIR" && bash .harness/bin/harness doctor 2>&1)"; FAIL_BUNDLE_CODE_AFTER=$?
  FAIL_BUNDLE_DONE=1
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
  WORK="$(mktemp -d)" || { echo "tests/doctor.sh: mktemp -d に失敗した"; exit 2; }
  # setup が非ゼロで返ったら expect を丸ごと飛ばす（従来どおり）が、その場合を明示的な失敗として
  # 記録する。以前は「setup 失敗 → expect 未実行 → errors が空 → PASS」という表明ゼロの緑があった。
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

# D1. 導入直後の doctor は FAIL 0 で exit 0。各行は「OK|WARN|FAIL  項目  →  直し方」形式、最後に集計行。
# フィクスチャの複製（cp -a）が「実際に harness init した直後の状態」とずれていないことも、
# ここで最初に確かめる（ずれれば FAIL 0 にならず、この最初のシナリオが落ちて気付ける）。
expect_fresh_install() {
  run_doctor
  expect_code 0
  expect_out '^(OK|WARN|FAIL) '
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=0 INFO=[0-9]+$'
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

# low 指摘: doctor はオプションを取らない。--fix / --json を黙って無視すると「指定どおり動いた」
# と誤解されうる（spec: --fix は範囲外、--json は要望が出るまで未実装）。usage を出して非 0 で終わる。
expect_unknown_option() {
  run_doctor_in "$PROJ" --fix
  expect_code 2
  expect_out '未知の引数'
  expect_out 'harness doctor'
  run_doctor_in "$PROJ" --json
  expect_code 2
  expect_out '未知の引数'
}
scenario "doctor は未知のオプション（--fix / --json 等）を usage 付きで拒否する" setup_init expect_unknown_option

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
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=[1-9][0-9]* INFO=[0-9]+$'
}
scenario "B1: git 不在なら FAIL / exit 1" setup_init expect_missing_git

# C3. node / jq が無くても「全項目」が実行できる。PATH 全潰し（B1 のシナリオ）は git/sed/awk も
# 道連れにして manifest が読めなくなり、B4/B5/B7/B11 が丸ごとスキップされるため C3 の検証にならない
# （最終レビュー low 指摘）。node/jq のディレクトリだけを外し、他の診断が一通り動くことを見る。
expect_no_node_jq() {
  run_doctor_without_node_jq
  expect_code 0
  expect_out '^WARN .*node'
  expect_out '^WARN .*jq'
  expect_not_out '^FAIL '
  # node/jq を隠しても他の診断（B4/B5/B7/B11）は最後まで実行される。
  expect_out '^OK .*manifest 記載ファイル'
  expect_out '^OK .*改行'
  expect_out '^OK .*AGENTS\.md'
  expect_out '^OK .*gitignore'
}
scenario "C3: node / jq が無くても全項目が実行できる（PATH から node/jq のディレクトリだけを外す）" setup_init expect_no_node_jq

# B3. manifest が壊れていれば FAIL（存在はするが harness_version 等が読めない形にする）。
# version/source/agents の見出しごと読めないケース: harness update は source を解決できず
# 失敗し、harness init は manifest.json があるだけで拒否するので、壊れたものを退避してから
# 元の source を指定して init をやり直す以外に道が無い（決定 0003。実測済み）。
setup_broken_manifest() {
  setup_init || return 1
  printf '{ "broken"\n' > "$PROJ/.harness/manifest.json"
}
expect_broken_manifest() {
  run_doctor
  expect_code 1
  expect_out '^FAIL .*manifest'
  expect_out 'init --source'
  # 黙ってスキップしない: manifest に依存する診断を飛ばしたことが出力で分かる
  expect_out '^WARN .*スキップ'
  apply_fix "mv .harness/manifest.json .harness/manifest.json.broken && bash .harness/bin/harness init --source '$REPO'"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*manifest'
  expect_not_out '^WARN .*スキップ'
}
scenario "B3: manifest が壊れていれば FAIL（退避して init --source で直る）" setup_broken_manifest expect_broken_manifest

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
  # version/source/agents の見出しは読めているので、files の記載が壊れていても
  # harness update がツリーの実物から作り直せる（決定 0003。実測済み）。
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*manifest'
}
scenario "B3: エントリが 1 行 1 件でなければ FAIL（偽の全快を出さない。update で直る）" setup_manifest_entries_one_line expect_manifest_entries_one_line

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
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*manifest'
}
scenario "B3: files が空なら FAIL（update で直る）" setup_manifest_empty_files expect_manifest_empty_files

# B4. manifest 記載の managed ファイルを削除すると FAIL で一覧に出る（update で直る）。
# 束ね: 下の B8（implementer.md 欠落）/ B9（role-reviewer 欠落）と同じプロジェクトにまとめて
# 壊し、doctor の前後 2 回分の出力を ensure_fail_bundle でキャッシュする。
setup_missing_managed_file() { ensure_fail_bundle && PROJ="$FAIL_BUNDLE_DIR"; }
expect_missing_managed_file() {
  OUT="$FAIL_BUNDLE_OUT_BEFORE"; CODE="$FAIL_BUNDLE_CODE_BEFORE"
  expect_code 1
  expect_out '^FAIL .*state-template/progress\.json'
  OUT="$FAIL_BUNDLE_OUT_AFTER"; CODE="$FAIL_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^FAIL .*state-template/progress\.json'
}
scenario "B4: managed ファイルの欠落は FAIL（update で直る）" setup_missing_managed_file expect_missing_managed_file

# B4. manifest 記載の seed ファイルを削除すると WARN（FAIL にはしない）。update を走らせると
# 実は復元される（apply_plan は seed が無ければ雛形から作る。実測済み。doctor 自体の直し方の
# 文言は「手で作る」寄りだが、実際に往復しても矛盾は出ない）。
# 束ね: 下の B5/B6/B11 と同じ ensure_warn_bundle のキャッシュを読む。
setup_missing_seed_file() { ensure_warn_bundle && PROJ="$WARN_BUNDLE_DIR"; }
expect_missing_seed_file() {
  OUT="$WARN_BUNDLE_OUT_BEFORE"; CODE="$WARN_BUNDLE_CODE_BEFORE"
  expect_code 0
  expect_out '^WARN .*docs/tech-debt\.md'
  expect_not_out '^FAIL .*docs/tech-debt\.md'
  OUT="$WARN_BUNDLE_OUT_AFTER"; CODE="$WARN_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^WARN .*docs/tech-debt\.md'
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
  # update は git checkout を経由せず生バイトで復元するので、core.autocrlf の設定に
  # 関係なく直る（決定 0002 / 0003。実測済み）。
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*scripts/gc\.sh'
}
scenario "B5: managed ファイルの CRLF 化は FAIL（update で直る）" setup_crlf_managed_file expect_crlf_managed_file

# B5. .gitattributes から .harness/** の行を消すと WARN。
# 束ね: 上の B4（seed 欠落）と下の B6/B11 と同じプロジェクトにまとめて壊し、doctor の前後
# 2 回分の出力を ensure_warn_bundle でキャッシュする。
setup_missing_gitattributes_line() { ensure_warn_bundle && PROJ="$WARN_BUNDLE_DIR"; }
expect_missing_gitattributes_line() {
  OUT="$WARN_BUNDLE_OUT_BEFORE"; CODE="$WARN_BUNDLE_CODE_BEFORE"
  expect_code 0
  expect_out '^WARN .*gitattributes'
  OUT="$WARN_BUNDLE_OUT_AFTER"; CODE="$WARN_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^WARN .*gitattributes'
  expect_out '^OK .*gitattributes'
}
scenario "B5: .gitattributes に .harness/** eol=lf が無ければ WARN（update で直る）" setup_missing_gitattributes_line expect_missing_gitattributes_line

# B6. core.hooksPath を外すと WARN（直し方に git config core.hooksPath .githooks）。
# 束ね: 上の B4/B5 と同じ ensure_warn_bundle のキャッシュを読む。
setup_no_hookspath() { ensure_warn_bundle && PROJ="$WARN_BUNDLE_DIR"; }
expect_no_hookspath() {
  OUT="$WARN_BUNDLE_OUT_BEFORE"; CODE="$WARN_BUNDLE_CODE_BEFORE"
  expect_code 0
  expect_out '^WARN .*hooks'
  expect_out 'git config core\.hooksPath \.githooks'
  OUT="$WARN_BUNDLE_OUT_AFTER"; CODE="$WARN_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^WARN .*hooks'
  expect_out '^OK .*hooks'
}
scenario "B6: core.hooksPath が外れていれば WARN（直し方のコマンドで直る）" setup_no_hookspath expect_no_hookspath

# B6. プロジェクトルートが git リポジトリでなければ（.git が無い）、core.hooksPath はそもそも
# 設定できない（git config core.hooksPath ... は fatal: not in a git directory で落ちる。
# 実測済み）。「未設定」と混同せず、根本原因を先に告げる（決定 0003）。
# .git ごと消す性質上、他の WARN 束ね（git config を使う）とは同居できないので独立させる。
setup_no_git_repo() {
  setup_init || return 1
  rm -rf "$PROJ/.git"
}
expect_no_git_repo() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*git リポジトリではない'
  expect_out 'fatal: not in a git directory'
  expect_out 'git init'
  apply_fix "git init . && git config core.hooksPath .githooks"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*git リポジトリではない'
  expect_out '^OK .*git hooks'
}
scenario "B6: プロジェクトルートが git リポジトリでなければ根本原因を告げる（git init で直る）" setup_no_git_repo expect_no_git_repo

# B7. AGENTS.md のマーカーの v= を manifest と食い違わせると WARN（harness update を案内）。
setup_agents_version_mismatch() {
  setup_init || return 1
  sed_i 's/<!-- harness:begin v=[^ ]* -->/<!-- harness:begin v=0.0.0-mismatch -->/' "$PROJ/AGENTS.md"
}
expect_agents_version_mismatch() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*AGENTS\.md'
  expect_out 'harness update'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*AGENTS\.md'
  expect_out '^OK .*AGENTS\.md'
}
scenario "B7: AGENTS.md マーカーの版が manifest と食い違えば WARN（update で直る）" setup_agents_version_mismatch expect_agents_version_mismatch

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
  # update は begin/end が複数あっても 1 対に畳む（決定 0002。実測済み）。
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^FAIL .*AGENTS\.md'
}
scenario "B7: AGENTS.md のマーカーが 2 組あれば FAIL（update で直る）" setup_agents_marker_duplicated expect_agents_marker_duplicated

# B11. .gitignore から .harness/state/ .harness/backup/ .harness/conflicts/ を消すと WARN。
# 束ね: 上の B4/B5/B6 と同じ ensure_warn_bundle のキャッシュを読む。
setup_missing_gitignore_state() { ensure_warn_bundle && PROJ="$WARN_BUNDLE_DIR"; }
expect_missing_gitignore_state() {
  OUT="$WARN_BUNDLE_OUT_BEFORE"; CODE="$WARN_BUNDLE_CODE_BEFORE"
  expect_code 0
  expect_out '^WARN .*gitignore'
  expect_out '\.harness/state/'
  expect_out '\.harness/backup/'
  expect_out '\.harness/conflicts/'
  OUT="$WARN_BUNDLE_OUT_AFTER"; CODE="$WARN_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^WARN .*gitignore'
  expect_out '^OK .*gitignore'
}
scenario "B11: .gitignore に state|backup|conflicts/ が無ければ WARN（update で直る）" setup_missing_gitignore_state expect_missing_gitignore_state

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
# 束ね: 上の B4（managed ファイル欠落）/ 下の B9（role-reviewer 欠落）と同じ ensure_fail_bundle を読む。
setup_claude_agent_missing() { ensure_fail_bundle && PROJ="$FAIL_BUNDLE_DIR"; }
expect_claude_agent_missing() {
  OUT="$FAIL_BUNDLE_OUT_BEFORE"; CODE="$FAIL_BUNDLE_CODE_BEFORE"
  expect_code 1
  expect_out '^FAIL .*implementer\.md'
  # low 指摘: 欠落時に B8 自身も報告する（従来は B4 の汎用行任せで、B8 の項目が消えて見えた）。
  expect_out '^FAIL .*Claude アダプタの役割ファイルが足りない'
  OUT="$FAIL_BUNDLE_OUT_AFTER"; CODE="$FAIL_BUNDLE_CODE_AFTER"
  expect_code 0
  expect_not_out '^FAIL .*implementer\.md'
  expect_not_out 'Claude アダプタの役割ファイルが足りない'
  # T10 #12: 「FAIL が消えた」だけでなく、generated 所有ファイルの中身が実際に再生成されている
  # ところまで確認する（生成元コメントが無ければ、空ファイルや退避コピーで消えたのかもしれない）。
  if [ ! -f "$FAIL_BUNDLE_DIR/.claude/agents/implementer.md" ]; then
    errors+=(".claude/agents/implementer.md が harness update で復元されなかった")
  elif ! grep -q 'generated by agent-harness' "$FAIL_BUNDLE_DIR/.claude/agents/implementer.md"; then
    errors+=("復元された .claude/agents/implementer.md に生成元コメントが無い（中身が正しく再生成されていない）")
  fi
}
scenario "B8: .claude/agents/implementer.md が無ければ FAIL（B8 自身も報告し、update で中身ごと直る）" setup_claude_agent_missing expect_claude_agent_missing

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
  expect_out '^harness doctor: OK=[0-9]+ WARN=[0-9]+ FAIL=0 INFO=[0-9]+$'
  expect_not_out 'CLAUDE\.md'
  expect_not_out '\.claude/skills'
  expect_not_out '\.claude/agents'
}
scenario "B8: agents に claude が無ければ Claude アダプタの診断をしない" setup_init_codex_only expect_no_claude_adapter_check

# B9. .agents/skills/role-reviewer を消すと FAIL。
# 束ね: 上の B4/B8 と同じ ensure_fail_bundle を読む。
setup_role_reviewer_missing() { ensure_fail_bundle && PROJ="$FAIL_BUNDLE_DIR"; }
expect_role_reviewer_missing() {
  OUT="$FAIL_BUNDLE_OUT_BEFORE"; CODE="$FAIL_BUNDLE_CODE_BEFORE"
  expect_code 1
  expect_out '^FAIL .*role-reviewer'
  OUT="$FAIL_BUNDLE_OUT_AFTER"; CODE="$FAIL_BUNDLE_CODE_AFTER"
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
  # INFO 行もヘッダ契約どおり「INFO  項目  →  直し方」の形（直し方が付く）。
  expect_out '^INFO .*→'
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

# low 指摘: $mf_source/VERSION は書式検証・長さ制限をせずに出力へ載せると、無関係な内容や
# 長文がそのまま診断ログに出る。版番号の形式でなければ WARN に倒し、内容は出力に丸ごと出さない。
setup_source_version_malformed() {
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
  # 版番号らしくない・長い内容（誤って別ファイルの中身が VERSION に入った場合を模す）
  local i=0
  { while [ "$i" -lt 50 ]; do
      echo "this is not a version string, it is a long unrelated line of text"
      i=$((i + 1))
    done
  } > "$src/VERSION"
}
expect_source_version_malformed() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*VERSION'
  expect_out '版番号の形式ではない'
  expect_not_out 'this is not a version string, it is a long unrelated line of text'
  # 出力のどの行も極端に長くならない（内容を丸ごと 1 行に潰して出していないか）
  local maxlen
  maxlen="$(printf '%s\n' "$OUT" | awk '{ print length }' | sort -rn | head -1)"
  [ "$maxlen" -le 500 ] || errors+=("doctor の出力に長さ ${maxlen} の行がある（VERSION の内容が検証なしで出力に載っている）")
  return 0
}
scenario "B10: source の VERSION が版番号の形式でなければ WARN（内容は出力に丸ごと出さない）" setup_source_version_malformed expect_source_version_malformed

# B10. source が URL のときはネットワークに触らない（manifest の source を到達不能な URL に差し替えて確認）。
setup_source_is_url() {
  setup_init || return 1
  rm -f "$PROJ/.harness/source.local"   # 機械ローカルの上書きを外し、manifest の URL だけが残る状態にする
  sed_i 's#"source": "[^"]*"#"source": "https://example.invalid/agent-harness.git"#' "$PROJ/.harness/manifest.json"
}
expect_source_is_url() {
  run_doctor
  expect_code 0
  expect_not_out 'Could not resolve|clone に失敗|fetch に失敗'
}
scenario "B10: source が URL ならネットワークに触らず完走する" setup_source_is_url expect_source_is_url

# ================================================================ T09: source の解決順（B10 の前提）
# .harness/manifest.json はコミットされる共有ファイルなので、機械依存の絶対パスを置かない。
# 機械ローカルの source は gitignore 対象の上書き（環境変数 HARNESS_SOURCE / .harness/source.local）へ逃がす。
# 解決順: 環境変数 HARNESS_SOURCE > .harness/source.local > manifest.json の source（決定 0004）。
# doctor B10 はこの解決結果を診断するので、解決そのものの表明もここに置く。

run_cli() { # <サブコマンド...> — $PROJ で導入コピーの CLI を回す
  OUT="$(cd "$PROJ" && bash .harness/bin/harness "$@" 2>&1)"; CODE=$?
}
run_cli_env() { # <VAR=VAL> <サブコマンド...> — 環境変数を足して回す
  local kv="$1"; shift
  OUT="$(cd "$PROJ" && env "$kv" bash .harness/bin/harness "$@" 2>&1)"; CODE=$?
}
manifest_source_of() { # <PROJ> → manifest.json の source
  sed -n 's/^  "source": *"\(.*\)",$/\1/p' "$1/.harness/manifest.json" | head -1
}

# init は manifest に共有値（既定の公開リポジトリ URL）を書き、--source で渡されたローカルパスは
# .harness/source.local（gitignore 対象）へ逃がす。self_repo() 由来でも manifest には書かない。
expect_init_source_is_shared() {
  CODE=0; OUT="$(manifest_source_of "$PROJ")"
  printf '%s\n' "$OUT" | grep -qE '^(https?|git|ssh)://|^git@' ||
    errors+=("manifest の source が共有値（URL）でない: $OUT")
  if [ ! -f "$PROJ/.harness/source.local" ]; then
    errors+=(".harness/source.local が作られていない（機械ローカルの source の置き場）")
  elif ! grep -qxF "$REPO" "$PROJ/.harness/source.local"; then
    errors+=(".harness/source.local に導入元のローカルパス（${REPO}）が書かれていない")
  fi
  grep -qxF '.harness/source.local' "$PROJ/.gitignore" ||
    errors+=(".gitignore に .harness/source.local が無い（コミットされてしまう）")
  return 0
}
scenario "T09: init は manifest に共有値を書き、ローカルパスは .harness/source.local へ逃がす" setup_init expect_init_source_is_shared

# 解決順: 環境変数 > .harness/source.local > manifest.json の source。status の見出し行で確認する。
expect_source_resolution_order() {
  local a="$WORK/src-a" b="$WORK/src-b"
  mkdir -p "$a" "$b"
  printf '%s\n' "$a" > "$PROJ/.harness/source.local"
  run_cli status
  expect_code 0
  expect_out "source=$a"
  run_cli_env "HARNESS_SOURCE=$b" status
  expect_code 0
  expect_out "source=$b"
  rm -f "$PROJ/.harness/source.local"
  run_cli status
  expect_code 0
  expect_out 'source=(https?|git|ssh)://|source=git@'
  return 0
}
scenario "T09: source の解決順は 環境変数 > .harness/source.local > manifest" setup_init expect_source_resolution_order

# 事故の再現と解（docs/learnings.md 2026-09-18）: worktree の中で update を回すと、manifest の
# source（= main tree の絶対パス）を見に行き、main tree の未コミット変更を取り込んでしまった。
# HARNESS_SOURCE で自分の worktree を指せば、そちらのペイロードだけが入る。
setup_worktree_source() {
  setup_init || return 1
  FAKE_SRC="$WORK/worktree"
  mkdir -p "$FAKE_SRC" &&
    cp -r "$REPO/harness" "$FAKE_SRC/harness" &&
    cp -r "$REPO/bin" "$FAKE_SRC/bin" &&
    cp "$REPO/VERSION" "$FAKE_SRC/VERSION" ||
    { errors+=("setup: 疑似 worktree の作成に失敗した"); return 1; }
  printf '\n<!-- T09-WORKTREE-MARKER -->\n' >> "$FAKE_SRC/harness/skills/harness/SKILL.md"
}
expect_worktree_source() {
  local synced="$PROJ/.agents/skills/harness/SKILL.md"
  run_cli update
  expect_code 0
  if grep -q 'T09-WORKTREE-MARKER' "$synced" 2>/dev/null; then
    errors+=("上書きが無いのに疑似 worktree のペイロードが入った")
  fi
  run_cli_env "HARNESS_SOURCE=$FAKE_SRC" update
  expect_code 0
  if ! grep -q 'T09-WORKTREE-MARKER' "$synced" 2>/dev/null; then
    errors+=("HARNESS_SOURCE で worktree を指しても、そのペイロードが入らない")
  fi
  if [ "$(manifest_source_of "$PROJ")" = "$FAKE_SRC" ]; then
    errors+=("manifest の source に機械ローカルのパスが書き戻された（共有ファイルが汚れる）")
  fi
  return 0
}
scenario "T09: update は上書きを通る（worktree 事故の解。manifest は汚さない）" setup_worktree_source expect_worktree_source

# diff / upstream はローカル source が要る。manifest が URL でも、上書きがあれば die せず動く。
setup_upstream_override() {
  setup_init || return 1
  UP_SRC="$WORK/src"
  mkdir -p "$UP_SRC" &&
    cp -r "$REPO/harness" "$UP_SRC/harness" &&
    cp -r "$REPO/bin" "$UP_SRC/bin" &&
    cp "$REPO/VERSION" "$UP_SRC/VERSION" ||
    { errors+=("setup: 上流コピーの作成に失敗した"); return 1; }
  rm -f "$PROJ/.harness/source.local"
  # 回帰しても、このリポジトリの harness/ に書き込まないようにしておく（実際に一度やらかした）:
  # manifest の source を到達不能な URL に固定してから、上書きの有無で挙動を見る。
  sed "s#^  \"source\": \"[^\"]*\",#  \"source\": \"https://example.invalid/agent-harness.git\",#" \
    "$PROJ/.harness/manifest.json" > "$PROJ/.harness/manifest.tmp" &&
    mv "$PROJ/.harness/manifest.tmp" "$PROJ/.harness/manifest.json" ||
    { errors+=("setup: manifest の source 書き換えに失敗した"); return 1; }
  printf '\n<!-- T09-UPSTREAM-MARKER -->\n' >> "$PROJ/.agents/skills/harness/SKILL.md"
}
expect_upstream_override() {
  run_cli upstream .agents/skills/harness/SKILL.md
  expect_code 1
  expect_out 'source\.local|HARNESS_SOURCE'
  run_cli_env "HARNESS_SOURCE=$UP_SRC" diff
  expect_code 0
  expect_out 'T09-UPSTREAM-MARKER'
  run_cli_env "HARNESS_SOURCE=$UP_SRC" upstream .agents/skills/harness/SKILL.md
  expect_code 0
  grep -q 'T09-UPSTREAM-MARKER' "$UP_SRC/harness/skills/harness/SKILL.md" ||
    errors+=("upstream が上書きで指した source へ書いていない")
  return 0
}
scenario "T09: manifest が URL でも上書きがあれば diff / upstream は die しない" setup_upstream_override expect_upstream_override

# B10. source が辿れないとき（manifest の共有値だけで、この PC に上書きが無い）は OK と言い切らず WARN。
# 直し方どおりに .harness/source.local を置くと WARN が消える。ネットワークには触らない。
setup_source_not_reachable() {
  setup_init || return 1
  rm -f "$PROJ/.harness/source.local"
}
expect_source_not_reachable() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*source'
  expect_out 'source\.local'
  expect_not_out 'Could not resolve|clone に失敗|fetch に失敗'
  apply_fix "printf '%s\n' \"$REPO\" > .harness/source.local"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*source'
  expect_out '^OK .*source の版は'
  return 0
}
scenario "B10: source が辿れなければ WARN（.harness/source.local を置くと消える）" setup_source_not_reachable expect_source_not_reachable

# B10. manifest に機械依存の絶対パスが残っている（この形式より前に導入した）プロジェクトは WARN。
# harness update が manifest を共有値へ直し、そのパスを .harness/source.local へ移す。
setup_manifest_source_is_local_path() {
  setup_init || return 1
  rm -f "$PROJ/.harness/source.local"
  sed "s#^  \"source\": \"[^\"]*\",#  \"source\": \"$REPO\",#" \
    "$PROJ/.harness/manifest.json" > "$PROJ/.harness/manifest.tmp" &&
    mv "$PROJ/.harness/manifest.tmp" "$PROJ/.harness/manifest.json" ||
    { errors+=("setup: manifest の source 書き換えに失敗した"); return 1; }
}
expect_manifest_source_is_local_path() {
  run_doctor
  expect_code 0
  expect_out '^WARN .*manifest.*絶対パス'
  apply_fix "bash .harness/bin/harness update"
  run_doctor
  expect_code 0
  expect_not_out '^WARN .*manifest.*絶対パス'
  grep -qxF "$REPO" "$PROJ/.harness/source.local" 2>/dev/null ||
    errors+=("update が manifest のローカルパスを .harness/source.local へ移していない")
  return 0
}
scenario "B10: manifest の source が機械依存の絶対パスなら WARN（update で共有値へ移る）" setup_manifest_source_is_local_path expect_manifest_source_is_local_path

# 絶対に壊してはいけないこと: 上書きが無く manifest が URL でも、status / doctor はネットワークに触らない
# （CI や clone 直後がこの状態）。resolve_source の clone キャッシュが作られないことで確認する。
expect_no_network_without_override() {
  local home="$WORK/home"; mkdir -p "$home"
  OUT="$(cd "$PROJ" && HOME="$home" GIT_ALLOW_PROTOCOL=none bash .harness/bin/harness status 2>&1)"; CODE=$?
  expect_code 0
  expect_out 'source=(https?|git|ssh)://|source=git@'
  if [ -e "$home/.cache/agent-harness" ]; then
    errors+=("status が clone キャッシュ（~/.cache/agent-harness）を作った＝ネットワークに触っている")
  fi
  OUT="$(cd "$PROJ" && HOME="$home" GIT_ALLOW_PROTOCOL=none bash .harness/bin/harness doctor 2>&1)"; CODE=$?
  expect_code 0
  if [ -e "$home/.cache/agent-harness" ]; then
    errors+=("doctor が clone キャッシュ（~/.cache/agent-harness）を作った＝ネットワークに触っている")
  fi
  return 0
}
scenario "T09: 上書きが無く manifest が URL でも status / doctor はネットワークに触らない" setup_source_not_reachable expect_no_network_without_override

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

# 回帰（最終レビュー medium 指摘）: manifest 由来のパス（空白・シェルメタ文字を含みうる外部入力）が、
# 直し方（→ の右側。コピペ実行を想定する箇所）にクオートなしでそのまま埋め込まれると、コピペ実行で
# 壊れる／危険になる（過去の実例: CRLF の直し方にあった `git checkout -- $f_path`）。T14 で CRLF の
# 直し方が固定文字列の `bash .harness/bin/harness update` に変わり実害は無くなっているが、退行を
# 機械的に検知できるよう、manifest の path に注入した文字列が直し方に生で出ないことを表明する。
setup_manifest_path_injection() {
  setup_init || return 1
  local inj='docs/my file *.md; touch CANARY-injected'
  sed "s#\"path\":\"\.harness/scripts/gc\.sh\"#\"path\":\"$inj\"#" "$PROJ/.harness/manifest.json" \
    > "$PROJ/.harness/manifest.json.tmp" &&
    mv "$PROJ/.harness/manifest.json.tmp" "$PROJ/.harness/manifest.json"
}
expect_manifest_path_injection() {
  run_doctor
  expect_code 1
  # ラベル側（→ の左）に生で出るのは許容する（実際そこに出る。診断対象を特定するため）。
  # 直し方（→ の右）にさえ出なければコピペ実行で壊れないので、右側だけを取り出して見る。
  local after_arrow
  after_arrow="$(printf '%s\n' "$OUT" | grep -F '→' | sed -E 's/.*→//')"
  if printf '%s' "$after_arrow" | grep -qF 'CANARY'; then
    errors+=("manifest 由来のパスが直し方（→ の右側）にクオートなしで埋め込まれている")
  fi
  [ -f "$PROJ/CANARY-injected" ] && errors+=("doctor が manifest 由来の文字列をコマンドとして実行してしまった")
  return 0
}
scenario "認可回帰: manifest 由来のパスは直し方にクオートなしで埋め込まれない" setup_manifest_path_injection expect_manifest_path_injection

# ================================================================ 集計
rm -rf "$SHARED" 2>/dev/null
echo
echo "tests/doctor.sh: pass=$passed fail=$failed"
if [ -n "$FILTER" ] && [ $((passed + failed)) -eq 0 ]; then
  echo "  フィルタ「${FILTER}」に一致するシナリオが無かった。"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  doctor の出力（上の「直近の出力」）と harness/scripts/doctor.sh を突き合わせて直す。"
  echo "  導入コピー（.harness/scripts/doctor.sh）ではなく harness/scripts/doctor.sh を直し、bash bin/harness update で同期する。"
  exit 1
fi
