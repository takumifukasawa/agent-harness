# handoff — 現在地

最終更新: 2026-09-17

## いま何をしているか（1〜3 行）

agent-harness を設計・実装し、このリポジトリ自身に `harness init` で導入した（dogfood 開始）。`task-orchestrate` で機能 1 つを通す本番の dogfood は、題材が未決。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| 設計（2 部構成、決定ログ 11 件） | 確定 | `DESIGN.md` |
| CLI: init / update / status / diff / upstream / check / gc / self-install | 実装済み・Windows で検証済み | `bin/harness`, `docs/learnings.md` |
| Claude settings 自動マージ（node 前提） | 実装済み・検証済み | `bin/harness` `merge_claude_settings` |
| `task-orchestrate` スキル | 実装済み・独立レビュー 25 件反映・**未使用** | `harness/skills/task-orchestrate/SKILL.md` |
| Codex 用 `role-*` スキル生成 | 実装済み | `bin/harness` `plan()` |
| このリポジトリへの導入（dogfood の土台） | 導入済み・検査 8 件 pass | `.harness/checks.sh` |
| v0.1.0 / v0.2.0 | push 済み（origin は HTTPS に切替済み） | git tags |

## NEXT（依存順。順序制約があれば明記）

1. **dogfood の題材を決める**（ユーザー判断）。候補: `harness release`（VERSION と CHANGELOG の整合を確認し tag を打つ補助）、`harness doctor`（導入先の環境診断: bash / git / node / cygpath / 改行）、macOS・Linux 対応の検証と修正。題材が決まったら `docs/spec/` に spec を書き、`task-orchestrate` の準備フェーズから始める。
2. 題材を通したら、統括が手順で迷った箇所・再試行「新しい 1 体」の精度とコスト・検査に何を登録すると効いたか を `docs/learnings.md` に残し、`[harness候補]` を `harness/` へ昇格する。
3. `agent-skills` 側の `context-catchup` / `context-handoff` の description に「ハーネス未導入のリポジトリで使う」と書き、発火の重なりを解消する（別リポジトリの作業）。

## 未確定事項（人間の判断待ち）

- dogfood の題材（上の 1）。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md` の Codex 側の事実は公式 docs 確認済みだが、Codex 実機での `.agents/skills/` 読み込みは未確認。dogfood で Codex を使うなら最初に確認する。
