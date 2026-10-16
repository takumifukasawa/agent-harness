#!/usr/bin/env bash
# tests/codex.sh — Codex アダプタ（標準 deny の hook）の検査（このリポジトリ専用。ペイロードではない）。
#
# 使い方:  bash tests/codex.sh
# 終了コード: 全件 pass で 0、1 つでも落ちれば 1。
#
# **codex CLI には依存しない。** hook が受け取る JSON を自前で作って deny スクリプトに食わせ、
# doctor の診断は CODEX_HOME を偽装して確かめる。Codex が入っていない PC / CI でも同じに走る。
#
# 見るのは 3 つ:
#   1. 配布   — --agents codex のときだけ .codex/hooks.json と .harness/scripts/codex-deny.sh が入る
#   2. 実効性 — deny スクリプトが標準 deny の 5 つを実際に拒否し、無害なコマンドは通す（jq の有無を問わず）。
#              空白・区切り・グローバルオプション・別表記で書き換えても止まる（issue #1）
#   3. 診断   — hook は「置いただけでは効かない」（プロジェクトの信頼 + hook 定義ごとの信頼）ので、
#              効いていない状態を doctor が WARN で報告し、信頼済みなら OK を出す（決定 0009）
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
passed=0; failed=0

ok()   { printf 'PASS  %s\n' "$1"; passed=$((passed + 1)); }
ng()   { printf 'FAIL  %s\n' "$1"; printf '        %s\n' "${2:-}"; failed=$((failed + 1)); }

# ---------------------------------------------------------------- 1. 配布
WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cx" "$WORK/cl"
(cd "$WORK/cx" && git init -q . && bash "$REPO/bin/harness" init --agents codex --source "$REPO") >/dev/null 2>&1
(cd "$WORK/cl" && git init -q . && bash "$REPO/bin/harness" init --agents claude --source "$REPO") >/dev/null 2>&1

if [ -f "$WORK/cx/.codex/hooks.json" ] && [ -f "$WORK/cx/.harness/scripts/codex-deny.sh" ]; then
  ok "配布: --agents codex で .codex/hooks.json と codex-deny.sh が入る"
else
  ng "配布: --agents codex で .codex/hooks.json と codex-deny.sh が入る" "どちらかが無い"
fi
if [ ! -e "$WORK/cl/.codex" ] && [ ! -e "$WORK/cl/.harness/scripts/codex-deny.sh" ]; then
  ok "配布: --agents claude には配らない"
else
  ng "配布: --agents claude には配らない" "Codex を使わないプロジェクトに .codex/ か codex-deny.sh が入った"
fi

DENY="$WORK/cx/.harness/scripts/codex-deny.sh"

# ---------------------------------------------------------------- 2. 実効性
# hook の入力は Codex 実機で採取した形（2026-09-21 / CLI 0.154.0）:
#   {"tool_name":"Bash","tool_input":{"command":"..."},"hook_event_name":"PreToolUse", ...}
json_escape() { # 文字列 → JSON 文字列の中身（\ " タブ 改行 だけ。Codex も同じ形で送ってくる）
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
judge_raw() { # JSON 文字列の中身（エスケープ済み） [PATH] → deny か pass を出す
  local path="${2:-$PATH}" out
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"hook_event_name":"PreToolUse"}' "$1" \
        | PATH="$path" bash "$DENY" 2>/dev/null)"
  case "$out" in *'"permissionDecision":"deny"'*) printf 'deny';; *) printf 'pass';; esac
}
judge() { # コマンド [PATH] → deny か pass を出す
  judge_raw "$(json_escape "$1")" "${2:-$PATH}"
}
expect_judge() { # コマンド 期待 [PATH] [ラベル追記]
  local got; got="$(judge "$1" "${3:-$PATH}")"
  if [ "$got" = "$2" ]; then ok "実効性${4:-}: $1 → $2"; else ng "実効性${4:-}: $1 → $2" "実際は $got"; fi
}
expect_judge_raw() { # JSON 文字列の中身 期待 [PATH] [ラベル追記]
  local got; got="$(judge_raw "$1" "${3:-$PATH}")"
  if [ "$got" = "$2" ]; then ok "実効性${4:-}: (JSON) $1 → $2"; else ng "実効性${4:-}: (JSON) $1 → $2" "実際は $got"; fi
}

# .claude/settings.json の deny と同じ 5 つ（エージェントを問わず同じに止まることが目的）
expect_judge "git push --force"            deny
expect_judge "git push -f origin main"     deny
expect_judge "git push --force-with-lease" deny
expect_judge "git reset --hard HEAD~1"     deny
expect_judge "git branch -D feature"       deny
expect_judge "gh repo delete owner/repo"   deny
# 通すもの（過剰に止めるとエージェントが何もできなくなる）
expect_judge "git push origin main"        pass
expect_judge "git status"                  pass
expect_judge "echo hello"                  pass
expect_judge "grep -f patterns.txt file"   pass

# 書き方を変えただけの同じ操作も止める（issue #1。以前は文字列の部分一致だったので素通りした）
TAB="$(printf '\t')"; NL="$(printf '\nx')"; NL="${NL%x}"
BYPASS=(
  "git  push --force"                  # 空白が 2 つ
  "git${TAB}reset --hard"              # タブ
  "git -c core.x=y push -f"            # グローバルオプション -c
  "git -C path reset --hard"           # グローバルオプション -C
  "git --git-dir=.git push --force"    # グローバルオプション（= つき）
  "git --work-tree . branch -D x"      # グローバルオプション（値が別の語）
  "git --no-pager push -f"             # 値を取らないグローバルオプション
  "git push origin +main"              # refspec の +
  "git push origin +HEAD:refs/heads/main"
  "git push -uf origin main"           # 短いオプションの連結
  "git push --force=origin"            # --force の変形
  "cd x&&git push --force"             # && の直後に空白が無い
  ";git reset --hard"                  # ; の直後
  "true||git reset --hard"             # || の直後
  "echo a|git branch -D x"             # | の直後
  "(git reset --hard)"                 # サブシェル
  "echo \$(git reset --hard)"          # コマンド置換
  "ls${NL}git push --force"            # 改行で区切った 2 行目
  "git push \\${NL}  --force"          # 行継続
  "git 'push' --force"                 # クォートした subcommand
  "bash -c 'git push --force'"         # 別のシェルに渡す
  "sudo git reset --hard"
  "FOO=1 git push -f"
  "git branch -d -f x"                 # 削除 + force（-D と同じ意味）
  "git branch --delete --force x"
  "git branch --force --delete x"
  "git branch -df x"
  "git branch -fd x"
  "git branch -D${TAB}x"
  "/usr/bin/git push --force"          # パスつきの git
  "gh  repo  delete owner/repo"
  "cd x;gh repo delete owner/repo"
)
for c in "${BYPASS[@]}"; do expect_judge "$c" deny; done

# 通すもの（正規化で止めすぎていないこと）
for c in \
  "git push -u origin main" \
  "git push --follow-tags" \
  "git push origin main+fix" \
  "git -C path status" \
  "git -c push.default=current push" \
  "git branch -d merged-feature" \
  "git branch -f topic HEAD~1" \
  "git branch --format=%(refname) -a" \
  "git reset --soft HEAD~1" \
  "git log --grep=force" \
  "git fetch -f" \
  "gh repo view owner/repo" \
  "echo reset --hard" \
  "ls -fd" ; do
  expect_judge "$c" pass
done

# JSON のエスケープを解いてから判定すること（jq が無い経路で特に効く）
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"
printf '#!/bin/sh\nexit 127\n' > "$NOJQ/jq"; chmod +x "$NOJQ/jq"
for p in "$PATH" "$NOJQ:/usr/bin:/bin"; do
  label=""; [ "$p" = "$PATH" ] || label="（jq なし）"
  expect_judge_raw 'git push --force'                deny "$p" "$label"
  expect_judge_raw 'git\tpush --force'               deny "$p" "$label"
  expect_judge_raw 'ls\ngit push --force'            deny "$p" "$label"
  expect_judge_raw 'git\u0020push --force'           deny "$p" "$label"
  expect_judge_raw 'cd x\u0026\u0026git reset --hard' deny "$p" "$label"
  expect_judge_raw 'git \"push\" --force'            deny "$p" "$label"
  expect_judge_raw 'echo \\\"; git push -f'           deny "$p" "$label"
  expect_judge_raw 'git push origin main'            pass "$p" "$label"
  expect_judge_raw 'echo \"a\\\\\" b'                pass "$p" "$label"
done

# command が配列で来ても同じに見る（jq の有無を問わず）
for p in "$PATH" "$NOJQ:/usr/bin:/bin"; do
  label=""; [ "$p" = "$PATH" ] || label="（jq なし）"
  for pair in 'git push --force|deny' 'git push origin main|pass'; do
    c="${pair%|*}"; want="${pair##*|}"
    got="$(printf '{"tool_name":"Bash","tool_input":{"command":["bash","-lc","%s"]}}' "$c" | PATH="$p" bash "$DENY" 2>/dev/null)"
    case "$got" in *'"permissionDecision":"deny"'*) got=deny;; *) got=pass;; esac
    if [ "$got" = "$want" ]; then ok "実効性$label: 配列 [bash -lc $c] → $want"
    else ng "実効性$label: 配列 [bash -lc $c] → $want" "実際は $got"; fi
  done
done

# jq が無い経路（sed で抜く）でも、上の書き換えを同じに止めること。依存は git と bash だけ、が前提。
for c in "${BYPASS[@]}"; do expect_judge "$c" deny "$NOJQ:/usr/bin:/bin" "（jq なし）"; done
expect_judge "git push origin main" pass "$NOJQ:/usr/bin:/bin" "（jq なし）"

# 取り出せなかったときは素通りのまま（決定 0009）。ただし黙らず stderr に残す
err="$(printf '{"tool_name":"Bash","tool_input":{"command":12}}' | bash "$DENY" 2>&1 >/dev/null)"
case "$err" in
  *"取り出せなかった"*) ok "取り出し失敗: 素通りするが stderr に残す";;
  *) ng "取り出し失敗: 素通りするが stderr に残す" "stderr: $err";;
esac
out="$(printf '{"tool_name":"Bash","tool_input":{"command":12}}' | bash "$DENY" 2>/dev/null)"
case "$out" in
  *deny*) ng "取り出し失敗: 素通り（fail-open）のまま" "deny を返した";;
  *) ok "取り出し失敗: 素通り（fail-open）のまま";;
esac
err="$(printf '{"tool_name":"apply_patch","tool_input":{"input":"x"}}' | bash "$DENY" 2>&1 >/dev/null)"
if [ -z "$err" ]; then ok "取り出し失敗: command を持たない道具では何も言わない"
else ng "取り出し失敗: command を持たない道具では何も言わない" "stderr: $err"; fi

# ---------------------------------------------------------------- 3. 診断（doctor）
# 偽の CODEX_HOME を作り、信頼の有無で doctor の出方が変わることを見る。
FAKE="$WORK/codex-home"; mkdir -p "$FAKE"
run_doctor_with_home() { # config.toml の中身（空文字なら config.toml を置かない）
  if [ -n "$1" ]; then printf '%s\n' "$1" > "$FAKE/config.toml"; else rm -f "$FAKE/config.toml"; fi
  (cd "$WORK/cx" && CODEX_HOME="$FAKE" bash .harness/bin/harness doctor 2>&1)
}
CXROOT="$(cd "$WORK/cx" && pwd -P)"

out="$(run_doctor_with_home "")"
case "$out" in
  *"Codex の設定"*) ok "診断: Codex の設定が無い PC では INFO で確認できないと言う";;
  *) ng "診断: Codex の設定が無い PC では INFO で確認できないと言う" "その行が出ていない";;
esac

out="$(run_doctor_with_home "[projects.\"$CXROOT\"]
trust_level = \"untrusted\"")"
case "$out" in
  *"WARN"*"標準 deny hook が効いていない"*) ok "診断: プロジェクトが信頼されていなければ WARN";;
  *) ng "診断: プロジェクトが信頼されていなければ WARN" "WARN の行が出ていない";;
esac

# プロジェクトは信頼されているが hook 定義は未信頼（実機で踏んだ状態。これで hook は 1 つも発火しない）
out="$(run_doctor_with_home "[projects.\"$CXROOT\"]
trust_level = \"trusted\"")"
case "$out" in
  *"WARN"*"hook 定義が信頼されていない"*) ok "診断: trust_level だけでは足りないことを言い分ける";;
  *) ng "診断: trust_level だけでは足りないことを言い分ける" "hook 定義の未信頼を指す WARN が出ていない";;
esac

out="$(run_doctor_with_home "[projects.\"$CXROOT\"]
trust_level = \"trusted\"

[hooks.state.\"$CXROOT/.codex/hooks.json:pre_tool_use:0:0\"]
trusted_hash = \"sha256:dummy\"")"
case "$out" in
  *"OK"*"標準 deny hook"*"信頼されている"*) ok "診断: 両方そろえば OK";;
  *) ng "診断: 両方そろえば OK" "OK の行が出ていない";;
esac

# Codex を使わないプロジェクトでは、この診断そのものを出さない
out="$(cd "$WORK/cl" && CODEX_HOME="$FAKE" bash .harness/bin/harness doctor 2>&1)"
case "$out" in
  *"標準 deny hook"*) ng "診断: Codex を使わないプロジェクトでは出さない" "Codex 向けの行が出ている";;
  *) ok "診断: Codex を使わないプロジェクトでは出さない";;
esac

echo
echo "tests/codex.sh: pass=$passed fail=$failed"
[ "$failed" -eq 0 ]
