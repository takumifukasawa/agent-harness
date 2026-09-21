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
#   2. 実効性 — deny スクリプトが標準 deny の 5 つを実際に拒否し、無害なコマンドは通す（jq の有無を問わず）
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
judge() { # コマンド [PATH] → deny か pass を出す
  local cmd="$1" path="${2:-$PATH}" out
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"hook_event_name":"PreToolUse"}' "$cmd" \
        | PATH="$path" bash "$DENY" 2>/dev/null)"
  case "$out" in *'"permissionDecision":"deny"'*) printf 'deny';; *) printf 'pass';; esac
}
expect_judge() { # コマンド 期待 [ラベル追記]
  local got; got="$(judge "$1" "${3:-$PATH}")"
  if [ "$got" = "$2" ]; then ok "実効性${4:-}: $1 → $2"; else ng "実効性${4:-}: $1 → $2" "実際は $got"; fi
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

# jq が無い経路（sed で抜く）でも同じ判定になること。依存は git と bash だけ、が前提。
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"
printf '#!/bin/sh\nexit 127\n' > "$NOJQ/jq"; chmod +x "$NOJQ/jq"
expect_judge "git push --force"     deny "$NOJQ:/usr/bin:/bin" "（jq なし）"
expect_judge "git push origin main" pass "$NOJQ:/usr/bin:/bin" "（jq なし）"

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
