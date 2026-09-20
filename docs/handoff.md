# handoff — 現在地

最終更新: 2026-09-20（次の題材を cross-env に決定。作業は macOS へ移す）

## いま何をしているか（1〜3 行）

次の題材は **cross-env**（エージェントと OS を問わず同じに動く）で、草案は `docs/spec/cross-env-support.md`。**未合意なので準備フェーズ（`task-orchestrate` §1）から始める。** 作業機は macOS へ移す。

前の題材（`harness doctor` を使った dogfood）は**完了した**。実装 5 タスク → 最終レビュー（4 観点 + 反証 1 回）→ 修正 10 タスクで、high 4 件を含む指摘をすべて処理し、VERSION 0.4.0 を切った。記録は `docs/plans/completed/harness-doctor.md`（結果と実測値つき）。**`.harness/state/` の進行状態はもう使っていないので捨ててよい。**

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

**作業機を macOS に移す。下の「別の PC で再開するとき」の手順を先に済ませること。**

1. **macOS で `harness doctor` を回し、本物の FAIL を見る。** 静的走査では 4 箇所（`docs/tech-debt.md` #3）だが、動かせばさらに出る前提。**ここで出た FAIL が spec の受け入れ条件 A の実体になる**ので、潰す前に出力を控える
2. **`docs/spec/cross-env-support.md` の未確定事項 3 件をユーザーと 1 件ずつ詰める**（`task-orchestrate` §1.3。まとめて聞かない）。特に **1 件目（bash 3.2 を切るか）は影響範囲が大きく、これが決まらないとタスク分解ができない**
3. 合意したら §1.6 でタスク分解 → `.harness/state/` を作って §2 の反復へ。**検査（§1.7）は「macOS で `harness check` が全件 pass」を判定できる形にする**
4. Codex の実機確認（spec の B）は、Codex CLI が入った環境が要る。無ければ A（macOS）だけ先に進める

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

### macOS の場合は先にこれ

**`bin/harness` の `declare -A` と `doctor.sh` の `mapfile` は bash 4+ を要求するが、macOS の既定 bash は 3.2**（GPLv3 を避けて更新されていない）。そのままでは `harness` 自体が動かない。

```bash
brew install bash          # 5.x が /opt/homebrew/bin/bash に入る（Intel Mac は /usr/local/bin/bash）
/opt/homebrew/bin/bash --version | head -1
```

以降 `harness` を叩くときはその bash を使う（`/opt/homebrew/bin/bash .harness/bin/harness doctor`）。**doctor の B1 が「bash の版が 4 未満」を FAIL で検出する**ので、間違えれば黙って壊れるのではなく止まる。そもそも 3.2 を切るのか 3.2 でも動く形に直すのかは、`docs/spec/cross-env-support.md` の未確定事項 1 件目（ユーザーと決める）。

macOS では他に 3 箇所の既知のブロッカーがある（`sha256sum` が無い / `date -d` が違う / `sed -i` に引数が要る）。詳細は `docs/tech-debt.md` #3。**これらは直す対象であって回避する対象ではない**（それが次の題材）。

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
