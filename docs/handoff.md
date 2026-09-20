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

## 別の PC で再開するとき

**スキルには 2 系統あり、配られ方が違う。**

| 系統 | 置き場 | 別 PC へは |
|---|---|---|
| ハーネスのスキル（`session-catchup` / `session-handoff` / `task-orchestrate` / `harness` / `harness-maintain`） | **各プロジェクトの `.claude/skills/`**（コミット対象。`harness init` が置く） | **clone で付いてくる。作業不要** |
| 汎用スキル（`context-catchup` / `task-eta` / `skill-creator` / `blog-review` / `game-*` など） | **マシン全体の `~/.claude/skills/`** | **`agent-skills` を clone して installer を回す** |

`.claude/settings.json`（SessionStart フック、`git push --force` 等の deny）と `.claude/agents/`（implementer / reviewer）も**コミット対象なので clone で付いてくる**。

### git に乗らないもの（再作成が要るのは 2 つ）

| | どうするか |
|---|---|
| **`.harness/source.local`** | **再作成する**: `echo '<clone した絶対パス>' > .harness/source.local`。無いと `update` / `diff` / `upstream` が公開 URL を見に行き、**手元の編集ではなく GitHub の内容を取り込む**。FAIL にはならず `harness doctor` が WARN で直し方のコマンドごと案内する（実測: OK=15 WARN=2 FAIL=0） |
| **`core.hooksPath`** | **再設定する**: `git config core.hooksPath .githooks`。`.git/config` はリポジトリに乗らないので、`harness init` ではなく `git clone` で持ってくると未設定になり、pre-commit の fast 検査が走らない。`doctor` の B6 が WARN で同じコマンドを案内する |
| `.harness/state/` `.harness/backup/` `.harness/conflicts/` | 不要。題材は完了済み（`phase: done`、計画は `docs/plans/completed/`）。新しい題材は `task-orchestrate` §1 がゼロから作る |
| `.install.local.sh` / `.install.local.ps1`（agent-skills） | 導入先を複数指定している場合だけ再作成する。無ければ `~/.claude/skills` 1 か所が既定 |
| assistant memory（エージェント固有のメモリ） | 不要。中身は `docs/learnings.md` と `docs/decisions/` に書き戻してあり、v0.5.0 でスキル本体にも昇格済み |

### 手順

```bash
# 1. agent-harness
git clone https://github.com/takumifukasawa/agent-harness.git
cd agent-harness
echo "$(pwd)" > .harness/source.local     # 機械ローカルの source（gitignore 対象）
git config core.hooksPath .githooks       # clone では引き継がれない
bash .harness/bin/harness doctor          # FAIL 0 を確認（jq が無ければ WARN 1 件。任意依存）
bash .harness/bin/harness check           # 13 件 pass（6〜8 分）

# 2. agent-skills（汎用スキルをマシン全体に入れる）
git clone https://github.com/takumifukasawa/agent-skills.git
cd agent-skills
./install.sh                              # bash: symlink。編集は即反映、追加時だけ再実行
```

Windows で PowerShell から使う場合は `./install.ps1 -Link`（junction。管理者権限も開発者モードも不要、ドライブを跨いでも動く）。`-Link` を付けないと**コピー**になり、スキルを編集するたびに再実行が要る。導入先を複数にするなら `-Dest 'C:one','C:	wo'` か、gitignore 対象の `.install.local.ps1` に `$Dest = @(...)` を書く。

**スキルはセッション開始時に読み込まれる。** 入れ直したら新しいセッションを開くか `/clear` する。

## 未確定事項（人間の判断待ち）

- なし。

## このセッションで触らなかったが確認したもの

- `harness/adapters/codex/README.md`: Codex 側の事実は公式 docs 確認済みだが、**Codex 実機での `.agents/skills/` 読み込みは未確認のまま**。dogfood で Codex を使うなら最初に確認する。
- `docs/README.md`: 索引は `docs/plans/` と `docs/decisions/` を既に指しているので変更不要。
- git tag: **v0.1.0 〜 v0.5.0 をすべて origin に push 済み**（main も追いついている）。
- `.harness/state/reports/` の各タスク report とレビュー報告全文（gitignore 対象）。要約はすべて `docs/plans/completed/harness-doctor.md` に転記済みなので、**state を捨てても経緯は追える**。
