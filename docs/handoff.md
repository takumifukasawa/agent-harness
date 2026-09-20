# handoff — 現在地

最終更新: 2026-09-20（`harness doctor` の題材が完了し **v0.4.0** で出荷。学びの昇格まで済ませて **v0.5.0** を切った。どちらも push 済み。その後 seed の検査強化（決定 0005）と agent-skills の棲み分けまで完了）

## いま何をしているか（1〜3 行）

`harness doctor` を題材にした `task-orchestrate` の dogfood が**完了した**。実装 5 タスク → 最終レビュー（4 観点 + 反証 1 回）→ 修正 10 タスクで、high 4 件を含む指摘をすべて処理し、VERSION 0.4.0 を切った。記録は `docs/plans/completed/harness-doctor.md`（結果と実測値つき）。**`.harness/state/` の進行状態はもう使っていないので捨ててよい。**

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| VERSION | **0.5.0**（2026-09-18）。v0.1.0〜v0.5.0 すべて origin に push 済み | `VERSION`, `CHANGELOG.md`, git tags |
| 検査 | **13 件 pass**（`doctor scenarios` 38 / `update scenarios` 13 / `seed checks are green` を含む） | `.harness/checks.sh` |
| `harness doctor` | OK=16 WARN=1 FAIL=0（WARN は開発機に jq が無いだけ） | `harness doctor` |
| 導入コピーの drift | なし（`modified=0 missing=0`） | `harness status` |
| CLI | init / update / status / diff / upstream / check / gc / doctor / self-install | `bin/harness` |
| `update` の挙動 | **変更済みの managed/generated を正本の内容に復元**（変更前は `.harness/backup/<ts>/`） | 決定 0002 |
| `source` の持ち方 | manifest は共有値（公開 URL）。機械ローカルは `HARNESS_SOURCE` > `.harness/source.local` > manifest の順で上書き | 決定 0004 |
| 決定 | 0001〜0005 | `docs/decisions/` |
| 新規プロジェクトの検査 | `harness init` の時点で 2 件（docs の索引 + `doctor: FAIL 0`）。決定 0005。`tests/seed.sh` が回帰を守る | `harness/checks.seed.sh` |
| 技術負債 | #6（テストの下限は doctor 呼び出し ≒3 秒）、#7（source のテストが `tests/doctor.sh` に同居） | `docs/tech-debt.md` |

**v0.5.0 で昇格済み**（`docs/learnings.md` の該当項目に「→ harness v0.5.0 へ昇格」と印がある）: レビュアーと反証役は既定で下位モデル / 統括が受け取る要約に修正コストを入れる / 実装役の指示テンプレに「検査は前面で回す」と「`CHANGELOG` の `[Unreleased]` に書く」。残りの `[harness候補]` 9 件は Windows 固有の罠が中心で、`harness/scripts/` の実装側に既に織り込み済みのものが多い。

## NEXT（依存順。順序制約があれば明記）

1. 次の題材を選ぶなら、**1 セッションで終わらない規模のもの**にする。今回の doctor は 810 行で `task-orchestrate` §5「1 セッションで終わる変更には使わない」に該当しており、ワークフローの価値を測る題材としては小さすぎた（`docs/plans/completed/harness-doctor.md` の「結果」を参照）。

## 未確定事項（人間の判断待ち）

- なし。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md`: Codex 側の事実は公式 docs 確認済みだが、**Codex 実機での `.agents/skills/` 読み込みは未確認のまま**。dogfood で Codex を使うなら最初に確認する。
- `docs/README.md`: 索引は `docs/plans/` と `docs/decisions/` を既に指しているので変更不要。
- git tag: **v0.1.0 〜 v0.5.0 をすべて origin に push 済み**（main も追いついている）。
- `.harness/state/reports/` の各タスク report とレビュー報告全文（gitignore 対象）。要約はすべて `docs/plans/completed/harness-doctor.md` に転記済みなので、**state を捨てても経緯は追える**。
