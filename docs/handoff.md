# handoff — 現在地

最終更新: 2026-09-18（最終レビュー完了・修正 6 本中 4 本 done。T09 / T10 が残り）

## いま何をしているか（1〜3 行）

`harness doctor` を題材に `task-orchestrate` の dogfood 中。計画: `docs/plans/active/harness-doctor.md`。実装 T01〜T05 の後、最終レビュー（4 観点 + 反証 1 回）で high 4 / medium 6 / low 12 が出た。**high 4 件は T06 / T07 / T08 / T14 で全部解消済み**。残る修正タスクは T09（`source` をローカル上書きへ）と T10（頑健性・検査の穴）で、`progress.json` の `phase` は `iterate`、`current_task` は `T09`。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| 設計・決定 | 確定。決定 0001〜0003（workflow が主題 / update が変更済み managed を復元 / doctor の案内を update の実装に合わせる） | `DESIGN.md`, `docs/decisions/` |
| CLI: init / update / status / diff / upstream / check / gc / doctor / self-install | 実装済み・Windows で検証済み | `bin/harness` |
| `harness doctor`（B1〜B11） | 実装済み。最終レビュー後の修正は 4/6 done | `harness/scripts/doctor.sh` |
| `update` の挙動 | **変更済みの managed/generated を正本の内容に復元**（変更前は `.harness/backup/<ts>/`、出力 `restore <path>` と `restored=N`）。seed と manifest 外の既存ファイルは触らない | `bin/harness`, 決定 0002 |
| 検査 | **10 件 pass**（`doctor scenarios` 27 + `update scenarios` 13） | `.harness/checks.sh` |
| テスト実行時間 | 6m51s → 2m10s（T13 のフィクスチャ共有・絞り込み・束ね）。`bash tests/doctor.sh <名前の一部>` で絞れる | `tests/doctor.sh` |
| VERSION | **0.3.0 据え置き**。修正 2 本が残っている間は上げない。`CHANGELOG.md` の `[Unreleased]` に doctor の追加と決定 0002 の移行手順が入っている | `VERSION`, `CHANGELOG.md` |
| ハーネス導入コピー | drift なし（`modified=0 missing=0`） | `harness status` |
| `task-orchestrate` スキル | dogfood 2 周目（実装 5 + 修正 6）。統括側の観察は `docs/learnings.md` と計画の決定ログ | `harness/skills/task-orchestrate/SKILL.md` |

## NEXT（依存順。順序制約があれば明記）

1. **T09: `source` を機械ローカルの上書きへ逃がす**（opus）。受け入れ条件 9 件は `.harness/state/stages.json` に記載。決定（採用案・落選案・理由）は計画ファイルの決定ログ 2026-09-17 の項にあるので、**T09 の中で `docs/decisions/` に書き戻すこと**。
   - 内容: manifest の `source` は共有値（既定は URL）に固定し、機械ローカルのパスは gitignore 対象の上書き（環境変数 `HARNESS_SOURCE` / `.harness/source.local`）へ。解決順は 環境変数 > `source.local` > `manifest.source`。doctor は source が辿れないとき OK と言い切らず WARN。
   - **これは机上の懸念ではなく実害が出ている**: worktree 内で `update` を叩くと manifest の絶対パス（main tree）を見に行き、**main tree の未コミット `harness/` を取り込む**（`docs/learnings.md` 2026-09-18）。
2. **T10: 頑健性と検査の穴**（sonnet、受け入れ条件 12 件、`stages.json` 記載）。**T09 と直列**。`harness/scripts/doctor.sh` / `bin/harness` / `tests/doctor.sh` が全面的に重なるので並列にできない。
3. T09/T10 が済んだら **VERSION を 0.4.0 に上げ**、`CHANGELOG.md` の `[Unreleased]` をその版見出しへ移す（managed ファイルの移動は無いので minor）。**決定 0002 の移行手順（次回 update で CRLF のファイルと手で直した managed が戻る／残したい変更は先に `harness diff` → `harness upstream`）を必ず版見出し側に残す。** 計画を `docs/plans/completed/` へ。
4. `[harness候補]` を `harness/` へ昇格する（`harness-maintain` の手順）。現在 `docs/learnings.md` に 6 件。特に効くのは 2 つ:
   - **レビュアーと反証役は既定で下位モデル** → `harness/skills/task-orchestrate/SKILL.md` §3 と `harness/roles/reviewer.md`
   - **検査は前面（フォアグラウンド）で回す** → §2.1 の実装役の指示テンプレ
5. `agent-skills` 側の `context-catchup` / `context-handoff` の description に「ハーネス未導入のリポジトリで使う」と書く（別リポジトリの作業）。

## 未確定事項（人間の判断待ち）

- なし。`source` の扱いは 2026-09-17 にユーザーと決定済み（ローカル上書きへ逃がす）。`progress.json` の `open_questions` も空。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md`: Codex 側の事実は公式 docs 確認済みだが、**Codex 実機での `.agents/skills/` 読み込みは未確認のまま**。dogfood で Codex を使うなら最初に確認する。
- `docs/README.md`: 索引は `docs/decisions/` を既に指しているので変更不要。
- `.claude/worktrees/`: T13 / T14 を並列実行するために払い出した worktree。両方ともマージ済みで削除した。
- 最終レビューの報告全文は `.harness/state/reports/review-*.md`（gitignore 対象）。要約と重大度は `progress.json` の `final_review` に転記済みなので、**state を捨てても指摘の一覧は計画ファイルの決定ログから辿れる**。
