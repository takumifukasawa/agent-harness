# handoff — 現在地

最終更新: 2026-09-18（`harness doctor` の題材が完了。**VERSION 0.4.0 で出荷**）

## いま何をしているか（1〜3 行）

`harness doctor` を題材にした `task-orchestrate` の dogfood が**完了した**。実装 5 タスク → 最終レビュー（4 観点 + 反証 1 回）→ 修正 10 タスクで、high 4 件を含む指摘をすべて処理し、VERSION 0.4.0 を切った。記録は `docs/plans/completed/harness-doctor.md`（結果と実測値つき）。**`.harness/state/` の進行状態はもう使っていないので捨ててよい。**

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| VERSION | **0.4.0**（2026-09-18） | `VERSION`, `CHANGELOG.md` |
| 検査 | **12 件 pass**（`doctor scenarios` 38 / `update scenarios` 13 を含む） | `.harness/checks.sh` |
| `harness doctor` | OK=16 WARN=1 FAIL=0（WARN は開発機に jq が無いだけ） | `harness doctor` |
| 導入コピーの drift | なし（`modified=0 missing=0`） | `harness status` |
| CLI | init / update / status / diff / upstream / check / gc / doctor / self-install | `bin/harness` |
| `update` の挙動 | **変更済みの managed/generated を正本の内容に復元**（変更前は `.harness/backup/<ts>/`） | 決定 0002 |
| `source` の持ち方 | manifest は共有値（公開 URL）。機械ローカルは `HARNESS_SOURCE` > `.harness/source.local` > manifest の順で上書き | 決定 0004 |
| 決定 | 0001〜0004 | `docs/decisions/` |
| 技術負債 | #6（テストの下限は doctor 呼び出し ≒3 秒）、#7（source のテストが `tests/doctor.sh` に同居） | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

1. **`[harness候補]` を `harness/` へ昇格する**（`harness-maintain` の手順）。`docs/learnings.md` に 8 件ある。**効果が大きい順に 3 件**:
   - **レビュアーと反証役は既定で下位モデル** → `harness/skills/task-orchestrate/SKILL.md` §3 と `harness/roles/reviewer.md`。根拠: opus 4 体を並列起動してレート上限に当たり 3 体が停止した（2026-09-17 の実測）
   - **実装役の指示テンプレに「検査は前面で回す」と「利用者に影響する変更なら `CHANGELOG` の `[Unreleased]` に書く」を足す** → §2.1。後者が無かったせいで T10 の変更を版切りで取りこぼしかけた
   - **レビュアーに返させる要約に「修正コスト（高/低）」を入れる** → §3.2。統括はレビュー本文を開かない規律なので、これが無いと §3.4 の反証条件（単独報告かつコスト高）を判定できない
2. `harness/checks.seed.sh`（新規プロジェクトに配られる雛形）に **`doctor: FAIL 0` 相当の検査を入れるか**を決める。今回このリポジトリの `.harness/checks.sh` にだけ入れた。seed は「docs の存在確認 1 件」しか無く、`AGENTS.md` 自身が「このままだと検査は常に pass し、完了判定が空洞化する」と書いている。**入れるなら決定を `docs/decisions/` に残す。**
3. `agent-skills` 側の `context-catchup` / `context-handoff` の description に「ハーネス未導入のリポジトリで使う」と書き、発火の重なりを解消する（別リポジトリの作業）。
4. 次の題材を選ぶなら、**1 セッションで終わらない規模のもの**にする。今回の doctor は 810 行で `task-orchestrate` §5「1 セッションで終わる変更には使わない」に該当しており、ワークフローの価値を測る題材としては小さすぎた（`docs/plans/completed/harness-doctor.md` の「結果」を参照）。

## 未確定事項（人間の判断待ち）

- なし。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md`: Codex 側の事実は公式 docs 確認済みだが、**Codex 実機での `.agents/skills/` 読み込みは未確認のまま**。dogfood で Codex を使うなら最初に確認する。
- `docs/README.md`: 索引は `docs/plans/` と `docs/decisions/` を既に指しているので変更不要。
- git tag: v0.4.0 は**打っていない**（v0.1.0 / v0.2.0 は打ってある）。push もしていない。origin より先行している。
- `.harness/state/reports/` の各タスク report とレビュー報告全文（gitignore 対象）。要約はすべて `docs/plans/completed/harness-doctor.md` に転記済みなので、**state を捨てても経緯は追える**。
