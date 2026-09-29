# 0011: 生成する `.claude/agents/<role>.md` にモデルを書かない

- 日付: 2026-09-29
- 状態: 採用

## 背景

`harness init` / `update` は `docs/roles/<role>.md` から `.claude/agents/<role>.md` を生成し、frontmatter に `model: inherit` を書いていた（0.3.0 から）。Claude Code では frontmatter の `model` がユーザーのサブエージェント既定（`~/.claude/settings.json` の `env.CLAUDE_CODE_SUBAGENT_MODEL`）より優先され、`inherit` は「メインセッション（統括）と同じモデル」を意味する。

2026-09-29 に実機で確認した: 統括 Fable 5.1、`CLAUDE_CODE_SUBAGENT_MODEL=opus` の環境で、`implementer`（`model: inherit`）は Fable 5.1 で、`model` 無指定の汎用エージェントは Opus 5.5 で起動した（どちらも空のエージェントに自分の system prompt のモデル名を報告させた）。

つまり「統括だけ上位、実装役とレビュアーは下位」という運用（`docs/roles/reviewer.md` の「モデルは既定で下位で足りる」、`docs/learnings.md` 2026-09-18）は、統括が起動時に `model` を毎回明示した場合にしか成立していなかった。明示を忘れると実装役もレビュアーも上位で走り、レビュアーを観点ぶん並列起動した時のレート上限（learnings 2026-09-18）を踏む。

## 採用案

**生成物に `model` 行を書かない。** Claude Code はサブエージェント既定（未設定なら Claude Code の既定モデル）を使い、統括が `stages.json` の `model` を起動時に渡せばそれが勝つ。ハーネスはモデルの段を決めず、ユーザーの設定と統括の判断に委ねる。

あわせて `task-orchestrate` の `model` 欄と `stages.json` 雛形の説明を「`inherit` = 起動時に指定しない（Claude Code ではサブエージェント既定）」に正した。従来の「メインセッションと同じ」は、この変更後は成り立たない。

## 落選案と落選理由

- **`model: opus` などの別名を書く**: ハーネスが「下位 = opus」と決め打ちすることになる。上位・下位の段はユーザーの契約や時期で変わる（この決定の時点でも Fable / Opus / Sonnet の 3 段ある）し、ペイロードに Claude 固有の別名を焼き込むことになる。置き場としてはユーザー設定（`CLAUDE_CODE_SUBAGENT_MODEL`）が適切。
- **`model: inherit` のまま、統括の手順で「必ず明示する」と強調する**: 手順の強調は忘れた時に効かない。既定が役割文（「既定で下位で足りる」）と逆を向いているのが問題で、既定を役割文に合わせる方が安い。

## 影響・やり直す条件

- `update` で `.claude/agents/implementer.md` / `reviewer.md` が再生成される。統括と同じモデルでサブエージェントを動かしたいプロジェクトは `CLAUDE_CODE_SUBAGENT_MODEL` をそのモデルにするか、統括が起動時に `model` を明示する。
- 確認元: `model: inherit` が親のモデルになることは 2026-09-29 の実機確認（上記）。**省略時にサブエージェント既定が使われること**は公式 docs の「Model resolution order」（https://code.claude.com/docs/en/sub-agents.md#model-resolution-order、2026-09-29 確認: 起動時の `model` 指定 > frontmatter > `CLAUDE_CODE_SUBAGENT_MODEL` > メイン会話のモデル）による。**実機では未確認**: 同じセッション内では `.claude/agents/` の変更が反映されず（docs は数秒で再読み込みすると言うが、再生成後に起動した implementer は親と同じモデルのまま、新規に置いた定義ファイルは「not found」だった）、新しいセッションで確認する必要がある。
- Claude Code が「frontmatter に `model` が無い時の既定」を変えたら見直す。
