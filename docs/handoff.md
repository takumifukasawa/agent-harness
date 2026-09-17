# handoff — 現在地

最終更新: 2026-09-17（T03 完了時点）

## いま何をしているか（1〜3 行）

`harness doctor` を題材に `task-orchestrate` の dogfood 中（反復フェーズ）。計画: `docs/plans/active/harness-doctor.md`。T01（骨格 B1-B2）・T02（B3-B5）・T03（B6/B7/B11）が done、次は T04（B8-B10）。統括は 1 タスクごとにセッションを切る運用。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| 設計（2 部構成、決定ログ 11 件） | 確定 | `DESIGN.md` |
| CLI: init / update / status / diff / upstream / check / gc / self-install | 実装済み・Windows で検証済み | `bin/harness`, `docs/learnings.md` |
| Claude settings 自動マージ（node 前提） | 実装済み・検証済み | `bin/harness` `merge_claude_settings` |
| `task-orchestrate` スキル | 実装済み・**dogfood 中**（doctor で T01-T03 通過、再試行 0、実装役 1 タスク 10〜20 分） | `harness/skills/task-orchestrate/SKILL.md` |
| Codex 用 `role-*` スキル生成 | 実装済み | `bin/harness` `plan()` |
| このリポジトリへの導入（dogfood の土台） | 導入済み・検査 9 件 pass（doctor scenarios 14 件含む） | `.harness/checks.sh` |
| v0.1.0 / v0.2.0 | push 済み（origin は HTTPS に切替済み） | git tags |

## NEXT（依存順。順序制約があれば明記）

1. **T04 を進める**: 新しいセッションで「続きのタスクを進めて」→ `task-orchestrate` §0 が `.harness/state/progress.json`（current_task: T04）を読み、実装役を 1 体起こす。T04 は B8（Claude アダプタ）/ B9（Codex アダプタ）/ B10（版比較。source がローカルか URL かで分岐）。同じ `doctor.sh` を触るので、着手前に `bash bin/harness update` で導入コピーの同期を確認。T05（文書と配線）は T04 の後。
2. 全タスク done 後に最終レビュー（§3、reviewer 4 観点並列）。通ったら VERSION を上げる。
3. 題材を通したら、統括が手順で迷った箇所・再試行の精度とコスト・検査に何を登録すると効いたか を `docs/learnings.md` に残し、`[harness候補]` を `harness/` へ昇格する（候補が 1 件増えた: Git for Windows の grep で CR がマッチしない）。
4. `agent-skills` 側の `context-catchup` / `context-handoff` の description に「ハーネス未導入のリポジトリで使う」と書き、発火の重なりを解消する（別リポジトリの作業）。

## 未確定事項（人間の判断待ち）

- なし（`progress.json` の `open_questions` も空）。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md` の Codex 側の事実は公式 docs 確認済みだが、Codex 実機での `.agents/skills/` 読み込みは未確認。dogfood で Codex を使うなら最初に確認する。
