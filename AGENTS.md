<!-- harness:begin v=0.7.1 -->
# エージェント運用の共通ルール（agent-harness 管理領域）

このブロックは agent-harness が管理する。直したい場合は直してよいが、`harness diff` で差分を確認し上流へ戻すこと（詳細: `.agents/skills/harness-maintain/SKILL.md`）。
プロジェクト固有のことは、このブロックの**外**に書く。

## 地図（まず索引を読み、必要な doc だけ開く）

| 知りたいこと | 場所 |
|---|---|
| 何がどこにあるか | `docs/README.md`（索引） |
| いま何が済み・何が途中・次は何か | `docs/handoff.md` |
| 数セッションに跨る作業の計画・進捗・決定ログ | `docs/plans/active/`（完了後は `completed/`） |
| モジュール境界・依存の向き・機械的に強制している不変条件 | `docs/architecture.md` |
| なぜそう決めたか（採用案と落選案） | `docs/decisions/` |
| 過去に踏んだ罠と対処 | `docs/learnings.md` |
| 既知の負債 | `docs/tech-debt.md` |
| 依存ライブラリ等の外部知識の抜粋 | `docs/references/` |
| 何を作るか（唯一の正） | `docs/spec/` |
| 長期タスクの役割分担（統括 / 実装 / レビュー / 機械検査） | `docs/roles/` |
| 長期タスクの機械可読な進行状態 | `.harness/state/progress.json`, `stages.json`（gitignore） |
| 特定ディレクトリだけに効く規律 | そのディレクトリの `AGENTS.md`（一覧: `docs/rules/README.md`） |

`docs/` がこのプロジェクトの永続事実の正本。エージェント固有のメモリ機能には「docs のどこを見るか」だけを残し、事実そのものは docs に書く。
**リポジトリに無い知識は存在しない**: チャット・会議・口頭で決まったことは、docs に書き戻すまで「決まっていない」とみなす。

## セッションの入口と出口

- 開始時: `.agents/skills/session-catchup/SKILL.md` の手順で現在地を掴む。全 doc を頭から読まない。
- 終了時・`/clear` 前・長い区切り: `.agents/skills/session-handoff/SKILL.md` の手順で `docs/handoff.md` を更新し、`harness status` の結果を報告する。

## 検証と報告

- 実装後は `.harness/scripts/check.sh`（`harness check`）を回す。これが「完了」の客観条件。
- 結果は出力ごと報告する。失敗はそのまま伝え、スキップした検査は明言する。
- 検査を通すためにテストや検査そのものを弱めない。必要なら理由を `docs/decisions/` に残して人間に判断を委ねる。
- 検査のエラー文に修復手順が書かれていれば、それに従う。書かれていなければ、直した後に検査側へ修復手順を足す（同じ迷いを二度させない）。

## 計画と長期タスク

- 数セッションに跨る作業は、着手前に `docs/plans/active/<slug>.md` に計画を書く（目的・受け入れ条件・タスク分解・決定ログ・進捗）。
- 進捗と途中の決定は計画ファイルに追記する。会話に残さない。完了したら `docs/plans/completed/` へ移す。
- 1 セッションに収まらない大きなタスクは `.agents/skills/task-orchestrate/SKILL.md` の手順で進める（統括は自分で実装せず、実装は 1 タスク 1 体、レビューは全タスク完了後に 1 回、検査は機械で。役割の定義は `docs/roles/`）。
- 機械可読な進行状態は `.harness/state/` に置く。確定したことは spec / docs / コードに書き戻し、JSON には未確定だけ残す。

## 記録の作法

- 決定は「採用案・落選案・理由」の 3 点を `docs/decisions/` に書く。落選理由は再浮上時に効く。
- ユーザーと合意した仕様変更は、会話に残すのではなく spec や docs に**書き戻す**。
- 相対日付（「先週」「今日」）は絶対日付に直す。
- `docs/learnings.md` に書くのは、コードや git log から導出できない罠と対処だけ。「再発したらまず X を見る」の形にする。

## やらないこと

- 破壊的な git 操作（`push --force`、履歴の書き換え、ブランチ削除）を指示なしに行わない。
- 秘密情報・個人情報をコミットしない。
- ハーネス管理ファイル（`.harness/manifest.json` に `managed` と記録されているもの）を黙って改変したまま放置しない。
<!-- harness:end -->

# プロジェクト固有のルール（agent-harness リポジトリ）

## 目的

AI エージェントにプロジェクトを進めさせるワークフロー（SmartHR 型）と、それを配る最小限の配管（CLI）を管理する。設計は `DESIGN.md`、境界は `docs/architecture.md`。

## 二重構造に注意

- `harness/` が**正本（ペイロード）**。`bin/harness` が CLI。
- `.agents/` `.claude/` `.harness/` `.githooks/` `AGENTS.md` の管理ブロック `CLAUDE.md` `docs/` は、このリポジトリ自身に `harness init` で入れた**導入コピー**（dogfood）。
- **スキルや役割文を直すときは `harness/` 側を直し、`bash bin/harness update` で同期する。** 導入コピーを直接編集しない（検査 "installed copies in sync" が落ちる）。
- `docs/` は seed なのでこのリポジトリの資産。自由に書く。

## コマンド

- 検査: `bash .harness/bin/harness check`（構文、JSON、スキル名、行数、CHANGELOG、同期、init のスモーク）
- docs の腐敗: `bash .harness/bin/harness gc`
- 導入コピーの同期: `bash bin/harness update`
- 使い捨てプロジェクトでの動作確認: `T=$(mktemp -d); mkdir -p $T/p; cd $T/p; git init -q .; bash /d/Developments/agent-harness/bin/harness init --source /d/Developments/agent-harness`

## 規約

- 依存は git と bash だけ。node / jq は「あれば使う」に留め、無くても動く経路を残す。
- ペイロード（`harness/`）に Claude / Codex 固有の依存を入れない。固有部分は `harness/adapters/` に。
- 版を上げるときは `VERSION` と `CHANGELOG.md` の見出しを一致させ、「プロジェクト側で必要な作業」を書く。managed ファイルの移動やマーカー形式の変更は major。
- **版を上げたら `bash bin/harness update` でこのリポジトリ自身の導入コピーを追従させる。** 上げ忘れると `harness doctor` が INFO（source に新版がある）を出し続ける。
- bash スクリプトは LF、`*.cmd` は CRLF（`.gitattributes`）。
- Windows のパスは `C:/`・`/c/`・`/tmp` が混在する。ファイルの同一性は内容ハッシュで判定する（`docs/learnings.md`）。
- 各エージェントの仕様に依存する記述には確認日と確認元を書く（`harness/adapters/*/README.md`）。

## やらないこと

- PowerShell への移植（`harness.cmd` シムで bash に委譲する。決定 #9）。
- マーケットプレイス配布（決定 #8）。
- セッションログや auto-memory の自動採掘（非ゴール。DESIGN.md §12）。
