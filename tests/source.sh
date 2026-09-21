#!/usr/bin/env bash
# tests/source.sh — source の解決順のシナリオテスト（このリポジトリ専用。ペイロードではない）
#
# 使い方: bash tests/source.sh [<シナリオ名の部分一致>]
# 引数なしで全件、引数ありで名前の部分一致。全件 pass で 0、失敗・一致なしで 1。
# 枠: scenario "<名前>" <setup関数> <expect関数>
# setup は使い捨ての $WORK に $PROJ を用意し、expect は expect_* / errors で表明する。
# tests/doctor.sh と同じ枠・共有 init フィクスチャを使う。setup 失敗は FAIL にする。
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

# ---------------------------------------------------------------- フィクスチャ（init 済みツリーの共有）
# SHARED はスイート全体で使う一時置き場。フィクスチャ本体はこの下に作り、個々のシナリオの
# ${WORK}（scenario ごとに作って rm -rf する）とは別に、最後にまとめて消す。
SHARED="$(mktemp -d)" || { echo "tests/source.sh: mktemp -d に失敗した（フィクスチャ置き場）"; exit 2; }
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
setup_init() { # 使い捨てプロジェクトをフィクスチャ（${FIXTURE}）から複製する。harness init は走らせない
  ensure_fixture || return 1
  PROJ="$WORK/p"
  cp -a "$FIXTURE" "$PROJ" 2>/dev/null || { errors+=("setup: フィクスチャの複製に失敗した"); return 1; }
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
  WORK="$(mktemp -d)" || { echo "tests/source.sh: mktemp -d に失敗した"; exit 2; }
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

# ================================================================ T09: source の解決順（B10 の前提）
# .harness/manifest.json はコミットされる共有ファイルなので、機械依存の絶対パスを置かない。
# 機械ローカルの source は gitignore 対象の上書き（環境変数 HARNESS_SOURCE / .harness/source.local）へ逃がす。
# 解決順: 環境変数 HARNESS_SOURCE > .harness/source.local > manifest.json の source（決定 0004）。
# doctor B10 が診断する source の解決そのものをここで表明する。

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

# ================================================================ 集計
rm -rf "$SHARED" 2>/dev/null
echo
echo "tests/source.sh: pass=$passed fail=$failed"
if [ -n "$FILTER" ] && [ $((passed + failed)) -eq 0 ]; then
  echo "  フィルタ「${FILTER}」に一致するシナリオが無かった。"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  printf '  失敗: %s\n' "${failed_names[@]}"
  echo "  上の「直近の出力」と bin/harness の source 解決処理を突き合わせて直す。"
  exit 1
fi
