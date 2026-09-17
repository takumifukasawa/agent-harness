# Changelog

各版に「プロジェクト側で必要な作業」を必ず書く。`harness update` はこの節を表示する。
semver: managed ファイルの移動・マーカー形式変更は major、ルール/スキルの追加は minor、文言修正は patch。

## [Unreleased]

## [0.3.0] - 2026-09-17

配管の残りを埋め、このリポジトリ自身に導入した版。

- 追加: `harness gc`（`scripts/gc.sh`）。handoff の鮮度、索引にあるが無い doc / あるが索引に無い doc、docs 内のリンク切れ、放置された `plans/active` と `.harness/state`、未着手の負債、管理ファイルの drift、古い references を一覧にする。`--strict` で CI 用に exit 1。判断と修正はしない。
- 追加: `.claude/settings.json` の自動マージ（node があるとき）。断片の `permissions.deny` と、command に `.harness/` を含む hooks だけを差し込み、プロジェクトの項目は保持。上書き前にバックアップ。無いときは手順を案内。
- 追加: このリポジトリ自身に `harness init` で導入（dogfood）。`.harness/checks.sh` に 8 件の検査（構文、JSON、スキル名、AGENTS.core.md の行数、VERSION と CHANGELOG の整合、導入コピーとペイロードの同期、init のスモークテスト）。`docs/` に architecture / learnings / tech-debt / decisions 0001 / handoff を記入。
- 変更: origin を HTTPS に切替（この PC の運用）。
- プロジェクト側で必要な作業: `harness update` で `gc.sh` が入り、Claude を使うプロジェクトでは `.claude/settings.json` に deny と SessionStart hook が差し込まれる（バックアップは `.harness/backup/`）。不要なら該当項目を削除してよいが、次の update で再度差し込まれる。

## [0.2.0] - 2026-09-17

ワークフローを実際に回せるようにした版。

- 追加: `task-orchestrate` スキル。準備 → 反復（1 セッション = 1 タスク）→ 最終レビュー を `.harness/state/` の JSON で管理する統括の手順。実装役への指示テンプレート、再試行（新しい 1 体に失敗出力を渡す、3 回で人へ）、レビューの重複排除と反証の 3 縛りを含む。
- 追加: Codex 用の役割スキル生成。`docs/roles/{implementer,reviewer}.md` から `.agents/skills/role-<name>/SKILL.md` を生成（generated。生成元が変われば再生成）。
- 変更: `AGENTS.core.md` と `docs/roles/README.md` が `task-orchestrate` を指すように。orchestrator の準備フェーズに「state を雛形からコピー」を明記。
- プロジェクト側で必要な作業: `harness update` で `task-orchestrate` と `role-*` スキルが入る。追加の手作業なし。

## [0.1.0] - 2026-09-17

CLI 実装版。`bin/harness`（bash。依存は git と bash だけ）。

- 追加: `harness init | update | status | diff | upstream | check | version`。所有権 managed / seed / merge / generated を manifest（1 エントリ 1 行の JSON、`src` で逆マッピング）で追跡。
- 追加: CLI 自身を `.harness/bin/harness` としてプロジェクトに同梱。clone した別 PC では `bash .harness/bin/harness update` がそのまま動く。source は ローカルパス か git URL（`~/.cache/agent-harness/` に clone）。
- 追加: init が `.gitignore`（state / backup / conflicts）と `.gitattributes`（`.harness/**` 等を LF 固定。Windows の autocrlf 対策）を書く。サブディレクトリ `AGENTS.md` の隣に `CLAUDE.md` アダプタを自動生成。`docs/roles/{implementer,reviewer}.md` から `.claude/agents/*.md` を生成。`core.hooksPath=.githooks` と pre-commit（`check --fast`）を設定。
- 決定: マーケットプレイス配布は採用しない（Claude 専用でリポジトリに入らないため）。DESIGN.md §10 #8。
- 追加: `harness self-install`（`harness` を PATH に置く。Windows は `harness.cmd` シムも置き、PowerShell / cmd から使える）。PATH 上の `harness` はプロジェクト内では同梱コピーへ委譲する。プロジェクトにも `.harness/bin/harness.cmd` を同梱。
- 追加: `harness` スキル（`/harness status` のようにセッション内から CLI を実行し、結果を解釈して次の行動を案内する）。
- 変更: `AGENTS.md` のマーカー版は CLI が VERSION から埋める（`AGENTS.core.md` の `v=` を手で合わせる必要が無くなった）。
- 設計: DESIGN.md を 2 部構成に書き直し。第 I 部「ワークフロー」（主役。SmartHR 型の遂行手順）、第 II 部「配管」（配布・更新、最小限）。DeNA 型のログ・メモリ採掘は非ゴールに。次の一手は `task-orchestrate` スキルと Codex 用役割スキルの生成（§11）。
- 修正（検算で発見）: 相対パスの `--source` を絶対パスにして保存（別ディレクトリからの update が壊れていた）。同梱 CLI 自身を update で上書きすると実行中の bash が壊れた内容を読む問題を、一時コピーからの再実行で回避。Windows で `C:/`・`/c/`・`/tmp` のパス形式が混在して同一ファイル判定（文字列比較・`-ef`）が失敗していたため、内容ハッシュでの判定に変更し、`git rev-parse` の結果を `cygpath -u` で正規化。
- 未実装: `harness gc`、`.claude/settings.json` の自動マージ（断片を `.harness/adapters/claude.settings.fragment.json` に置き、手で反映）。
- プロジェクト側で必要な作業: なし（初回配布）。

## [0.0.1] - 2026-09-17

設計版。CLI は未実装。

- 追加: `DESIGN.md`（設計）、`harness/AGENTS.core.md`、`harness/docs-template/`（索引・handoff・architecture・plans・decisions・learnings・tech-debt・references・rules）、スキル 3 本（session-catchup / session-handoff / harness-maintain）、`harness/scripts/check.sh` と `checks.seed.sh`、アダプタ README（claude / codex）、`manifest.example.json`。
- 追加（同日、対話で決定）: SmartHR 型ワークフローの取り込み。`docs-template/roles/`（orchestrator / implementer / reviewer）、`docs-template/spec/`、`state-template/`（progress.json / stages.json）。未決事項 7 件を決定ログに変換（DESIGN.md §10）。
- 追加（同日、検算で修正）: `harness/scripts/session-start.sh`（Claude の SessionStart hook から呼ぶ補助）。所有権に `generated`（seed から生成されるアダプタ出力。生成元のハッシュも追跡）を追加。Codex のサブディレクトリ AGENTS.md は cwd 基準で読まれる事実を反映（DESIGN.md §2 の正本の形式表、rules 雛形、Codex アダプタ README）。SmartHR 原文との突合で `roles/`・`state-template/`・`checks.seed.sh` を修正（反証の 3 条件、戻り値の絞り込み、検査は回避手段も塞ぐ）。再試行は「新しい 1 体に失敗出力を渡す。統括のセッションは切らない」で統一。
- プロジェクト側で必要な作業: なし（まだ配布していない）。
