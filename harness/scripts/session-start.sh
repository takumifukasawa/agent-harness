#!/usr/bin/env bash
# harness session-start — セッション開始時に現在地の見出しだけを出す（補助。無くても運用は成立する）。
# Claude Code では SessionStart hook から呼ぶ（adapters/claude/settings.fragment.json）。
# 出力は短く保つ。全文は session-catchup スキルが必要な分だけ読む。
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HANDOFF="$ROOT/docs/handoff.md"

if [ -f "$HANDOFF" ]; then
  updated="$(grep -m1 -E '^最終更新:' "$HANDOFF" || true)"
  echo "[harness] docs/handoff.md ${updated:-（最終更新の行が無い）}"
  awk '/^## NEXT/{f=1; next} /^## /{f=0} f && NF' "$HANDOFF" | head -5 | sed 's/^/[harness]   /'
else
  echo "[harness] docs/handoff.md が無い。session-catchup の前に docs/README.md を確認。"
fi

# lockfile 方式（決定 0013）: 他の人が版を上げた manifest を pull すると、manifest の source_commit と
# この作業ツリーに入っている版（.harness/installed）がずれる。配布物はコミットしないので、install で揃える。
pin="$(sed -n 's/^  "source_commit": *"\(.*\)",\{0,1\}$/\1/p' "$ROOT/.harness/manifest.json" 2>/dev/null | head -1)"
here="$(tr -d '\r\n' <"$ROOT/.harness/installed" 2>/dev/null || true)"
if [ -n "$pin" ] && [ "$here" != "$pin" ]; then
  echo "[harness] 入っている版（${here:-不明}）が manifest の固定（${pin}）と違う。harness install で揃える。"
fi

if [ -d "$ROOT/.harness/state" ] && ls "$ROOT/.harness/state"/*.json >/dev/null 2>&1; then
  echo "[harness] .harness/state/ に進行中の状態あり。progress.json を読む。"
fi
echo "[harness] 開始: session-catchup / 終了: session-handoff"
