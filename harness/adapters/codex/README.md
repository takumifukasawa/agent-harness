# Codex CLI アダプタ

確認日: 2026-09-17（公式 docs で確認。実機で `harness init` 後に再確認すること）

| 正本 | Codex 側 | 方法 |
|---|---|---|
| `AGENTS.md`（トップ） | そのまま読む | アダプタ不要。`AGENTS.override.md` があればそちらが優先 |
| `<subdir>/AGENTS.md` | **ルートから cwd までの連鎖**のみ読む。合計 32 KiB 上限（`project_doc_max_bytes`） | cwd をそのディレクトリにして起動するか、統括役が内容を明示的に渡す。ファイル基準では載らない（公式 docs: learn.chatgpt.com/docs/agent-configuration/agents-md） |
| `.agents/skills/<name>/SKILL.md` | `$CWD/.agents/skills` から `$REPO_ROOT/.agents/skills` まで探索。個人は `$HOME/.agents/skills` | アダプタ不要。`$skill-name` で明示呼び出しも可（公式 docs: learn.chatgpt.com/docs/build-skills） |
| `.harness/scripts/*.sh` | hook 相当は任意 | 仕様変動が大きいため v0 では使わない。git hooks と AGENTS.md の文章で代替 |
| 標準 deny | `config.toml` の sandbox / approval 設定 | 翻訳表は未作成。破壊的 git 操作は `.githooks/` 側でも塞ぐ |
| `docs/roles/<role>.md` | `.agents/skills/role-<role>/SKILL.md` | 役割文をスキル化し `$role-implementer` のように明示呼び出し。サブエージェント機構の有無に依存しない |

既知の注意: `~/.agents/skills` の個人スキルが新セッションで検出されない報告がある（community.openai.com）。リポジトリ内 `.agents/skills/` を正にしているのはこのため。
