# agent-harness

AI コーディングエージェント（Claude Code / Codex CLI / その他）に**プロジェクトをどう進めさせるか**のワークフローを、このリポジトリで管理し、各プロジェクトに配って更新する。

- **主役はワークフロー**: 1 セッション 1 タスク、統括 / 実装 / レビュー / 機械検査の役割分離、状態の外部化、spec と規律の分離、合意の書き戻し（SmartHR 型）。AGENTS.md は目次で、`docs/` が正本。
- **エージェント非依存**: 正本は `AGENTS.md`・`SKILL.md`・Markdown・シェル・git hooks。エージェント固有部分は薄いアダプタに閉じ込める。
- **配管は最小限**: `harness init` で入れ、`harness update` で版を上げ、`harness upstream` で直したものを戻す。手変更は manifest のハッシュで検出し、壊さない。

設計の全体は [DESIGN.md](DESIGN.md)。版履歴は [CHANGELOG.md](CHANGELOG.md)。依存は **git と bash** だけ（Windows は Git for Windows 同梱の Git Bash）。

## 使い方

### プロジェクトに入れる（初回）

```bash
# このリポジトリを clone してあるなら
bash /path/to/agent-harness/bin/harness init

# clone していない PC でも、URL から直接
curl -fsSL https://raw.githubusercontent.com/takumifukasawa/agent-harness/main/bin/harness \
  | bash -s -- init --source https://github.com/takumifukasawa/agent-harness.git
```

入るもの: `AGENTS.md` の管理ブロック、`CLAUDE.md`（`@AGENTS.md`）、`.agents/skills/`（Codex）と `.claude/skills/`（Claude）、`docs/` の雛形、`.harness/`（manifest、検査ランナー、CLI 自身のコピー）、`.githooks/pre-commit`。既存の `AGENTS.md` / `CLAUDE.md` は壊さず先頭に足すだけ。

### 以後（どの PC でも）

CLI はプロジェクトに同梱されるので、clone した PC で追加インストールは不要。呼び方は 3 つ。

**エージェントのセッション内から（推奨）** — Claude Code は `/harness ...`、Codex は `$harness ...`。CLI を実行し、結果を読んで次の行動まで案内する。

```
/harness status
/harness update
/harness diff
/harness check
```

**PATH に置いて短く** — 一度だけ `self-install` する。Windows では `harness.cmd` も置かれ、PowerShell / cmd から `harness status` と打てる（中身は Git Bash に委譲）。プロジェクト内では同梱コピーへ委譲するので、版はプロジェクトに固定される。

```bash
bash .harness/bin/harness self-install      # ~/.local/bin（Windows は ~/bin）へ。PATH の案内が出る
harness status
```

**同梱コピーを直接** — `bash .harness/bin/harness status`（Windows の PowerShell / cmd は `.harness\bin\harness.cmd status`）。

| サブコマンド | やること |
|---|---|
| `status` | 導入版、手で直したファイル（MODIFIED）の一覧 |
| `update [--ref <tag>]` | 新版を取り込む。CHANGELOG を表示し、手変更は保持して `.harness/conflicts/` に新版を置く |
| `diff` | 手で直した管理ファイルの差分（上流に戻す候補） |
| `upstream <path>...` | このリポジトリへ書き戻す（source がローカル clone のとき） |
| `check [--fast]` | `.harness/checks.sh` に登録した検査を回す（`--fast` は pre-commit 用） |
| `gc [--days N] [--strict]` | docs の腐敗検知（handoff の鮮度、索引やリンクの切れ、放置された計画・負債・state、管理ファイルの drift） |
| `doctor` | 環境と導入状態の診断（ツール確認、manifest、改行、アダプタ、source の新版など）。OK/WARN/FAIL の一覧と集計を表示 |

### ハーネスの中身を更新する

**プロジェクト側から**: 管理ファイル（スキル、スクリプト）を直す → `/harness diff` → `/harness upstream <path>`。source が git URL のプロジェクトでは、このリポジトリを clone し、その絶対パスを `.harness/source.local`（gitignore 対象。1 行に書く）に置くか、`HARNESS_SOURCE=<clone した絶対パス>` を付けて一度だけ実行する。manifest の `source` は共有値（コミットされる）なので書き換えない。解決順は 環境変数 `HARNESS_SOURCE` > `.harness/source.local` > manifest の `source`（決定 0004）。

**このリポジトリで**:

1. `harness/` を直す。
2. `CHANGELOG.md` の `[Unreleased]` に変更と「プロジェクト側で必要な作業」を書く。
3. `VERSION` を上げ、CHANGELOG の見出しにする（managed ファイルの移動やマーカー形式の変更は major）。`AGENTS.md` のマーカー版は CLI が自動で埋めるので触らない。
4. commit → push。tag を打てば `harness update --ref vX.Y.Z` で pin できる。
5. 各プロジェクトで `/harness update`。

`docs/learnings.md` に溜まった学びをルール・スキル・検査へ昇格させる手順は、導入先の `.agents/skills/harness-maintain/SKILL.md`。

## 構成

```
bin/harness              # CLI（bash）。init | update | status | diff | upstream | check | self-install | version
bin/harness.cmd          # Windows 用シム（PowerShell / cmd → Git Bash）
harness/                 # プロジェクトに入るペイロード
├── AGENTS.core.md       # AGENTS.md の managed ブロック（共通ルール。目次であって百科事典ではない）
├── docs-template/       # docs/ の雛形（索引・handoff・architecture・plans・decisions・learnings・tech-debt・references・spec・roles・rules）
├── skills/              # task-orchestrate（大きなタスクを回す）/ session-catchup / session-handoff / harness（CLI 実行）/ harness-maintain
├── scripts/             # check.sh（検査ランナー、LLM 不使用）、session-start.sh
├── checks.seed.sh       # プロジェクトが編集する検査一覧の雛形
├── state-template/      # progress.json / stages.json（長期タスクの機械可読な状態）
├── adapters/claude/     # CLAUDE.md 雛形・settings 断片・確認済み事実
├── adapters/codex/      # 確認済み事実
└── manifest.example.json
```

## 隣のリポジトリとの関係

[`agent-skills`](../agent-skills) は個人の汎用スキル集（マシン単位・シンボリックリンク）。こちらはプロジェクト運用の足場（リポジトリ単位・コミットされる）。詳細は DESIGN.md §9。

### 入れた後にやること（init は足場を置くだけ）

`init` 直後の `check` は seed の 2 件しか回らない。仕組みが働き始めるのはここから。

1. **`.harness/checks.sh` に検査を登録する。** これが「完了の客観条件」（`AGENTS.md`）。テスト・lint・型検査・ビルドなど、**そのプロジェクトで緑なら完了と言えるもの**を並べる。速いものには `fast` を付けると pre-commit でも回る。
2. **`docs/spec/` に何を作るかを書く。** 受け入れ条件はここが唯一の正で、会話ではなくここに書き戻す。
3. **`bash .harness/bin/harness doctor`** で FAIL 0 を確認する。
4. Codex を使うなら、`codex` を起動して **`/hooks` で標準 deny の hook を信頼する**（0.7.0 以降。各 PC で 1 回。`doctor` が状態を報告する）。

**既存の `docs/` があるプロジェクトに入れるとき**は、先に `ls docs/` を見て、雛形の名前（`README.md` / `handoff.md` / `architecture.md` / `learnings.md` / `tech-debt.md`）と**大文字違いで被るもの**がないか確認する。case を区別しないファイルシステム（macOS / Windows）では、既存の `HANDOFF.md` があると雛形の `handoff.md` は配られないのに manifest には載る（`docs/tech-debt.md` #13）。被っていたら `git mv` で雛形側の名前に寄せるのが手っ取り早い。

## 既知の制約

- `.claude/settings.json` の自動マージは `node` がある環境のみ。無ければ `.harness/adapters/claude.settings.fragment.json` を手で反映する（`docs/tech-debt.md` #1）。
- 動作確認は **Windows（Git Bash）と macOS（Darwin 24.6 / arm64 / 素の bash 3.2.57）**。macOS は 2026-09-20〜21 に実機で確認し、`init` / `update` / `doctor` / `check` / `gc` が通る（決定 0006 で bash 3.2 を切らないと決めた）。**Linux は未検証**、**古い macOS（15 未満、`sha256sum` / `jq` が無い）も未検証**。詳細は `docs/tech-debt.md` #3。
- **0.7.0 以前から上げるときだけ、`harness update` を 2 回回す**（1 回目で CLI 自身が入れ替わり、2 回目から新しい配布物が入る。0.7.1 で解消。`docs/tech-debt.md` #12）。
