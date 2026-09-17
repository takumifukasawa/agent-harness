# Claude Code アダプタ

確認日: 2026-09-17（公式 docs code.claude.com/docs/en/{memory,skills,sub-agents,hooks,permissions}.md で確認）

確認済みの事実: hook は「現在のディレクトリ」で実行され、`${CLAUDE_PROJECT_DIR}` にセッション開始時のプロジェクトルートが入る（hooks.md）。断片ではこれでスクリプトを参照する。`@path` import は CLAUDE.md の位置基準で解決する。サブディレクトリの CLAUDE.md はそのディレクトリのファイルを読んだ時点で載る。Claude Code は `AGENTS.md` を直接読まず、`.agents/skills/` も探索しない（だからこのアダプタが要る）。`SessionStart` は有効な hook イベント。deny の `*` は前方一致。

| 正本 | Claude Code 側 | 方法 |
|---|---|---|
| `AGENTS.md` | `CLAUDE.md` | `CLAUDE.md.template` を置く。中身は `@AGENTS.md` の import のみ |
| `<subdir>/AGENTS.md` | `<subdir>/CLAUDE.md` | 同じ template を隣に置く（`harness update` が走査して生成） |
| `.harness/scripts/*.sh` | `.claude/settings.json` の hooks | `settings.fragment.json` を参考に手で反映（v0）。SessionStart で handoff の要約を出す等は**補助**。無くても運用は成立する |
| 標準 deny | `.claude/settings.json` の `permissions.deny` | `settings.fragment.json` 参照。v0 は差分表示のみ、手で反映 |
| `docs/roles/<role>.md` | `.claude/agents/<role>.md` | 役割文を本文にし、frontmatter に `name` / `description` / `model` を付けて生成。model は設計余地で使い分ける（設計判断あり → 上位モデル、定型実装 → 下位モデル） |
| `.agents/skills/<name>` | `.claude/skills/<name>` | **コピー**（symlink は Windows で開発者モードが要るため不採用。`update` で再コピー） |

Claude Code の auto-memory（`~/.claude/projects/<slug>/memory/`）はリポジトリ外にあるため、正本にしない。`AGENTS.core.md` のルール通り「docs への参照」だけを書く。
