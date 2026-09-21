# Codex CLI アダプタ

確認日: **2026-09-21（Codex CLI 0.154.0 / macOS 15.6.1 / model gpt-6-astra で実機確認）**。
それ以前の記述は公式 docs のみが出典だった（2026-09-17）。**実機で確かめた行には「実機」と書く。書いていない行はまだ推定である。**

| 正本 | Codex 側 | 方法 |
|---|---|---|
| `AGENTS.md`（トップ） | **そのまま読む（実機）** | アダプタ不要。`AGENTS.override.md` があればそちらが優先 |
| `<subdir>/AGENTS.md` | **ルートから cwd までの連鎖を読む（実機）**。合計 32 KiB 上限（`project_doc_max_bytes`） | アダプタ不要。cwd をサブディレクトリにして起動しても、**ルートの `AGENTS.md` は一緒に読まれる**（公式 docs: learn.chatgpt.com/docs/agent-configuration/agents-md） |
| `.agents/skills/<name>/SKILL.md` | **`$CWD/.agents/skills` から `$REPO_ROOT/.agents/skills` まで探索（実機）**。個人は `$HOME/.agents/skills` | アダプタ不要。**`$skill-name` での明示呼び出しも実機で動く**（`$role-implementer` を呼び、SKILL.md の戻り値 6 フィールドと禁止事項を正しく再現した） |
| `.harness/scripts/*.sh` | **hook は実在する（実機）**。`<repo>/.codex/hooks.json`（または `<repo>/.codex/config.toml` の `[hooks]`）／個人は `$CODEX_HOME/hooks.json` | イベントは `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PermissionRequest` / `PostToolUse` / `SubagentStart` / `SubagentStop` / `Stop` など。形式は Claude Code に近い（`{"hooks":{"<Event>":[{"hooks":[{"type":"command","command":"...","timeout":5}]}]}}`）。**hook は stdin に JSON を受ける**（`session_id` / `turn_id` / `transcript_path` / `cwd` / `hook_event_name` / `model`、PreToolUse は加えて `tool_name` / `tool_use_id` / `tool_input`） |
| 標準 deny | **`PreToolUse` hook で拒否できる（実機）** | hook が `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` を返すと、コマンドは実行されず `hook: PreToolUse Blocked` になり、モデルにも拒否理由が伝わる（exit 2 + stderr でも可）。**採否と配り方は [決定 0009](../../../docs/decisions/0009-codex-deny-via-pretooluse-hook.md)** |
| `docs/roles/<role>.md` | `.agents/skills/role-<role>/SKILL.md` | `harness init/update` が生成（generated）。**`$role-implementer` のように明示呼び出しできることを実機で確認**。統括は `task-orchestrate` の手順で新しいスレッドから呼ぶ |

## 実機で分かった落とし穴（2026-09-21）

- **プロジェクトの `.codex/hooks.json` は、置いただけでは走らない。** 2 段階の信頼が要る:
  1. プロジェクトが trusted であること（`~/.codex/config.toml` の `[projects."<絶対パス>"] trust_level = "trusted"`）。**untrusted なら `.codex/` 層そのものが無視される**（hook もルールも config も）
  2. **さらに hook 定義ごとの信頼**。1 だけでは走らない（実機で確認: trusted のまま hook が 1 つも発火しなかった）。`codex` の `/hooks` で hook を信頼するか、`--dangerously-bypass-hook-trust` を付ける。信頼は hook 定義のハッシュで `config.toml` の `[hooks.state]` に記録される
  - つまり **hook は「git に乗らないもの」の仲間**（`core.hooksPath` や `.harness/source.local` と同じで、clone しただけでは効かない。各マシンで 1 回の操作が要る）
- **`PreToolUse` の deny は `apply_patch` には効かない**（既知の不具合。openai/codex#27833: 「hook fires, write proceeds」）。**ファイル書き込み系を hook で止められると当てにしない。**
- `~/.agents/skills`（個人スキル）はこの機に存在せず未検証。**スキル一覧には Codex 側の組み込み/プラグイン由来のもの（`imagegen` / `skill-creator` など）も混ざる**ので、「列挙に出た＝ハーネスが配ったもの」とは限らない。
- `codex exec` は**引数でプロンプトを渡しても stdin を読もうとする**。非対話で回すときは `< /dev/null` を付ける（付けないと `Reading additional input from stdin...` で止まる）。

## 確認に使った方法（再現手順）

**LLM に「読めていますか」と聞くだけでは確認にならない**（`docs/learnings.md` 2026-09-21）。実機確認は次の形で行った:

1. 対象ファイルに一意な canary 文字列を仕込む（例: `ROOT-CANARY-5513`）
2. `codex exec --sandbox read-only "... いま与えられているコンテキストだけで答えて ..." < /dev/null` で聞く
3. canary がそのまま返れば「読めている」、返らなければ「読めていない」

hook の確認は、hook 自身にファイルを書かせて（`date > .codex/ran-<event>.txt`）**副作用で証拠を残す**。出力ラベル（`hook: PreToolUse`）だけでは、個人 hook が走ったのかプロジェクト hook が走ったのか区別できない。
