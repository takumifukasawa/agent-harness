# handoff — 現在地

最終更新: 2026-09-17（T05 完了・全タスク done、最終レビュー待ち）

## いま何をしているか（1〜3 行）

`harness doctor` を題材に `task-orchestrate` の dogfood 中。計画: `docs/plans/active/harness-doctor.md`。T01〜T05 がすべて done（再試行 0）。`progress.json` の phase は `review`、次は §3 の最終レビュー（reviewer 4 観点並列）。VERSION は 0.3.0 据え置き、CHANGELOG は Unreleased に doctor を記載済み。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| 設計（2 部構成、決定ログ 11 件） | 確定 | `DESIGN.md` |
| CLI: init / update / status / diff / upstream / check / gc / doctor / self-install | 実装済み・Windows で検証済み | `bin/harness`, `docs/learnings.md` |
| Claude settings 自動マージ（node 前提） | 実装済み・検証済み | `bin/harness` `merge_claude_settings` |
| `task-orchestrate` スキル | 実装済み・**dogfood 中**（doctor で T01-T05 全通過、再試行 0、実装役 1 タスク 8〜20 分） | `harness/skills/task-orchestrate/SKILL.md` |
| Codex 用 `role-*` スキル生成 | 実装済み | `bin/harness` `plan()` |
| このリポジトリへの導入（dogfood の土台） | 導入済み・検査 9 件 pass（doctor scenarios 21 件含む） | `.harness/checks.sh` |
| v0.1.0 / v0.2.0 | push 済み（origin は HTTPS に切替済み） | git tags |

## NEXT（依存順。順序制約があれば明記）

1. **最終レビューを回す**: 新しいセッションで「最終レビューを回して」→ `task-orchestrate` §0 が phase `review` を読み §3 へ。`reviewer` を 4 観点（仕様突合 / 並行性 / 認可 / 機能の完結性）で並列起動し、差分は `37db608..HEAD`、spec は `docs/spec/harness-doctor.md`。報告先 `.harness/state/reports/review-<観点>.md`。統括は要約だけ受け取る。残った指摘は修正タスクとして `stages.json` に追加して §2 で潰す。
2. レビューが片付いたら VERSION を 0.4.0 に上げ、CHANGELOG の Unreleased（doctor）をその版見出しへ移す（managed ファイルの移動は無いので minor）。計画を `docs/plans/completed/` へ移す。
3. 題材を通したら、統括が手順で迷った箇所・再試行の精度とコスト・検査に何を登録すると効いたか を `docs/learnings.md` に残し、`[harness候補]` を `harness/` へ昇格する（候補 2 件: Git for Windows の grep で CR がマッチしない / 実装役が検査を裏プロセスで回して完了待ちで停止する → 指示に「検査は前面で回す」）。
4. `agent-skills` 側の `context-catchup` / `context-handoff` の description に「ハーネス未導入のリポジトリで使う」と書き、発火の重なりを解消する（別リポジトリの作業）。

## 未確定事項（人間の判断待ち）

- なし（`progress.json` の `open_questions` も空）。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md` の Codex 側の事実は公式 docs 確認済みだが、Codex 実機での `.agents/skills/` 読み込みは未確認。dogfood で Codex を使うなら最初に確認する。
