# handoff — 現在地

最終更新: 2026-09-20（題材 cross-env のフェーズ 1 / T01 完了。作業機は macOS に移した）

## いま何をしているか（1〜3 行）

題材は **cross-env**（エージェントと OS を問わず同じに動く）。**準備フェーズは完了し、合意はすべて spec と決定 0006 に書き戻してある。** いま反復フェーズで、**3 タスク中 1 つ（T01）が done**。計画と進捗は `docs/plans/active/cross-env.md`、機械可読な状態は `.harness/state/`。

**作業機は macOS（Darwin 24.6 / arm64 / 素の bash 3.2.57）。** 2026-09-20 に初めて実機で回し、`harness check` が **pass=9 fail=4** だったところを **pass=15 fail=0** にした。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`cross-env`**（main から分岐。push していない） | `git branch` |
| VERSION | **0.5.0**。T01 の変更は `CHANGELOG.md` の `[Unreleased]` にあり、版はまだ切っていない（T03 でやる） | `VERSION`, `CHANGELOG.md` |
| 検査 | **15 件 pass / 0 fail**（1分27秒）。T01 で禁止検査 2 件が増えた | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **OK=16 WARN=0 FAIL=0** | `/bin/bash .harness/bin/harness doctor` |
| macOS の素の bash | **3.2.57 のまま動く**（決定 0006 で「3.2 を切らない」と決めた）。`brew install bash` は**もう要らない** | 決定 0006 |
| 導入コピーの drift | なし（T01 で `bash bin/harness update` 済み） | `harness status` |
| 決定 | 0001〜**0006** | `docs/decisions/` |
| 技術負債 | #3（返済中）、#6、#7、**#8（新規: `harness gc` に実行経路の検査が無い）** | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

**`task-orchestrate` の反復フェーズの続き。** `.harness/state/progress.json` が `phase: iterate` / `current_task: T02` なので、スキルの §0 から入れば続きから拾える。

1. **T02 を実装役に渡す**（`stages.json` の T02 をそのまま指示にする）。内容:
   - **`.githooks/pre-commit` の実行ビット**。git index 上で mode 100644 なので、**clone したツリーでは pre-commit が黙って無視される**（`harness init` は `chmod +x` するが clone には効かない）。**今このリポジトリでもフックは走っていない。**
   - **`doctor` の B6 の偽 OK**。`-f`（存在）しか見ておらず、実行不可でも `OK git hooks` と報告する。`-x` を見るように直す。ただし Windows（`core.filemode=false`）で偽の警告を出さないこと
   - **A3**: `harness init` が公開 URL からも動く（tech-debt #4 が未確認のまま）
   - T01 の申し送り: **`bash bin/harness update` は `.githooks/pre-commit` と `.harness/bin/harness`・`.harness/scripts/*.sh` に `chmod +x` する副作用がある**。T01 では指示どおり `chmod -x` で 100644 に戻してコミットした。T02 で実行ビットを正とするなら、update 後に `chmod +x` してから `git add` する
2. T03（導入コピー同期・CHANGELOG・版上げ）。**managed の移動もマーカー形式の変更も無いので minor（0.6.0）**
3. **フェーズ 2（Codex）のタスクを `stages.json` に足す**（spec の B1〜B4）。**Codex CLI 0.154.0 がこの機に入っている**（`/opt/homebrew/bin/codex`）ので環境待ちにはならない
4. 全タスク完了後に最終レビュー 1 回（`task-orchestrate` §3）。**レビュアーは既定で下位モデル**（上位を並列起動するとレート上限に当たる。`docs/learnings.md`）

## 別の PC で再開するとき

**スキルには 2 系統あり、配られ方が違う。**

| 系統 | 置き場 | 別 PC へは |
|---|---|---|
| ハーネスのスキル（`session-catchup` / `session-handoff` / `task-orchestrate` / `harness` / `harness-maintain`） | **各プロジェクトの `.claude/skills/`**（コミット対象） | **clone で付いてくる。作業不要** |
| 汎用スキル（`context-catchup` / `task-eta` / `skill-creator` / `blog-review` / `game-*` など） | **マシン全体の `~/.claude/skills/`** | **`agent-skills` を clone して installer を回す** |

### git に乗らないもの（再作成が要る）

| | どうするか |
|---|---|
| **`.harness/source.local`** | `echo '<clone した絶対パス>' > .harness/source.local`。無いと `update` / `diff` / `upstream` が公開 URL を見に行く。`doctor` が WARN で直し方ごと案内する |
| **`core.hooksPath`** | `git config core.hooksPath .githooks`。`.git/config` は clone で引き継がれない |
| **`.githooks/pre-commit` の実行ビット** | **T02 で直るまでは `chmod +x .githooks/pre-commit` が要る。** git index が 100644 なので clone しただけでは実行ビットが付かず、git がフックを**警告 1 行だけ出して無視する**（`hint: ... not set as executable`）。`doctor` はまだこれを検出しない（B6 の穴） |
| `.harness/state/` | **捨てない。** 題材 cross-env が進行中（`phase: iterate`）。捨てた場合は `docs/plans/active/cross-env.md` と git log から再構成する |

### macOS の場合

**もう `brew install bash` は要らない**（決定 0006 で bash 3.2 を切らないと決め、T01 で 27 箇所を直した）。素の `/bin/bash`（3.2.57）で `init` / `doctor` / `check` がすべて通る。

再発を止める検査が 2 件入っている。**新しく bash を書くときはこれに従う**:

- `bash tests/lint-bash-compat.sh forbidden-syntax` — `declare -A` / `local -A` / `declare -n` / `local -n` / `mapfile` / `readarray` を締め出す
- `bash tests/lint-bash-compat.sh nonascii-var` — `"$var日本語"` を締め出す（**bash 3.2 + UTF-8 では変数名にマルチバイトの先頭バイトが食い込んで `unbound variable` になる**。`${var}` と括れば通る）

対象は `bin/harness`・`harness/scripts/*.sh`・`tests/*.sh`。**`harness/adapters/` は対象外**なので、そこに書くときは自分で気をつける。

`sha256sum` と `jq` は macOS 15 以降なら Apple 提供のものが `/sbin` / `/usr/bin` にある。**古い macOS（15 未満）は未検証**。

### 手順

```bash
git clone https://github.com/takumifukasawa/agent-harness.git
cd agent-harness
echo "$(pwd)" > .harness/source.local
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit          # T02 で不要になる予定
/bin/bash .harness/bin/harness doctor  # FAIL 0
/bin/bash .harness/bin/harness check   # 15 件 pass（約 1.5 分）
```

## 未確定事項（人間の判断待ち）

- なし。準備フェーズの 3 件はすべて合意済み（spec の「合意済みの決定」と決定 0006）。

## このセッションで触らなかったが確認したもの

- **`harness/adapters/codex/README.md`**: Codex 側の事実は公式 docs 確認済み（2026-09-17）だが、**実機確認はこれから**（spec の B2）。Codex CLI はこの機に入っている。
- **`gc.sh:42` の `date -d`**: macOS で壊れているはずだが、**`harness gc` は `check` の経路に無いので機械で検出できていない**。直すだけでなく経路を作る必要がある（tech-debt #8）。
- **古い macOS（15 未満）の経路**: `sha256sum` / `jq` が無い前提のコードは、この機では確かめられていない。
