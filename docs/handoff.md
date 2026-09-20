# handoff — 現在地

最終更新: 2026-09-20（題材 cross-env のフェーズ 1 / T01・T02・T04 完了。残るは T03（版上げ）のみ）

## いま何をしているか（1〜3 行）

題材は **cross-env**（エージェントと OS を問わず同じに動く）。**準備フェーズは完了し、合意はすべて spec と決定 0006 に書き戻してある。** いま反復フェーズで、**4 タスク中 3 つ（T01・T02・T04）が done**。残るは T03（導入コピー同期・CHANGELOG・版上げ）だけ。計画と進捗は `docs/plans/active/cross-env.md`、機械可読な状態は `.harness/state/`。

**作業機は macOS（Darwin 24.6 / arm64 / 素の bash 3.2.57）。** 2026-09-20 に初めて実機で回し、`harness check` が **pass=9 fail=4** だったところを **pass=18 fail=0**（検査自体が 13 → 18 件）にした。**`.githooks/pre-commit` は T02 で本当に走るようになった**（index mode 100755）。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`cross-env`**（main から分岐。push していない） | `git branch` |
| VERSION | **0.5.0**。T01・T02 の変更は `CHANGELOG.md` の `[Unreleased]` にあり、版はまだ切っていない（T03 でやる） | `VERSION`, `CHANGELOG.md` |
| 検査 | **18 件 pass / 0 fail**（約 1.5 分）。T01 で禁止検査 2 件、T02 で `githooks are executable` / `gc scenarios` / `stdin (curl \| bash) install` の 3 件が増えた | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **OK=16 WARN=0 FAIL=0**。**T04 で B6 の重大度が WARN → FAIL になった**（フックが実行不可＝門番が不在。決定 0007）。このリポジトリは index が 100755 なので OK のまま | `/bin/bash .harness/bin/harness doctor` |
| macOS の素の bash | **3.2.57 のまま動く**（決定 0006 で「3.2 を切らない」と決めた）。`brew install bash` は**もう要らない** | 決定 0006 |
| 導入コピーの drift | なし（modified=0 missing=0）。**T02 以降 `update` は mode 差分も残さない**（実行ビットを index の正にしたため） | `harness status` |
| 決定 | 0001〜**0007**（0007: フックが実行不可なら doctor は FAIL） | `docs/decisions/` |
| 技術負債 | **#8 は返済済**（`tests/gc.sh` で経路を新設）、**#3 はほぼ返済済**（残るのは古い macOS 15 未満）、**#4 は機構まで確認済**（確定は main へ載せた後）、**#9 を新規起票**（init の perms）。未着手は #1 #2 #6 #7 | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

**`task-orchestrate` の反復フェーズの続き。** `.harness/state/progress.json` が `phase: iterate` / `current_task: T03` なので、スキルの §0 から入れば続きから拾える。

1. **T03 を実装役に渡す**（`stages.json` の T03 をそのまま指示にする）。導入コピー同期・CHANGELOG・版上げ。**managed の移動もマーカー形式の変更も無いので minor（0.6.0）**。CHANGELOG の `[Unreleased]` には T02・T04 の内容（実行ビットの修復手順、B6 が FAIL になったこと）が既に入っているので、**版の見出しを切って VERSION と一致させるのが主な仕事**。
3. **T03 の後に main へ載せ、tech-debt #4 を閉じる**: `bash bin/harness init --source https://github.com/takumifukasawa/agent-harness.git` を 1 回回して `doctor` が FAIL 0 になることを確認する。**今落ちているのは公開 main が T01 前（305d57b）だからで、コード側の欠陥ではない**（現ブランチ内容の clone 経路では通る）。
4. **フェーズ 2（Codex）のタスクを `stages.json` に足す**（spec の B1〜B4）。**Codex CLI 0.154.0 がこの機に入っている**（`/opt/homebrew/bin/codex`）ので環境待ちにはならない
5. 全タスク完了後に最終レビュー 1 回（`task-orchestrate` §3）。**レビュアーは既定で下位モデル**（上位を並列起動するとレート上限に当たる。`docs/learnings.md`）

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
| ~~`.githooks/pre-commit` の実行ビット~~ | **T02 で不要になった。** index が 100755 になったので clone しただけで実行ビットが付く。`doctor` の B6 も実行可否まで見る（`core.filemode=false` の Windows では偽警告を出さない） |
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
/bin/bash .harness/bin/harness doctor  # FAIL 0
/bin/bash .harness/bin/harness check   # 18 件 pass（約 1.5 分）
```

## 未確定事項（人間の判断待ち）

- なし。B6 の重大度は [決定 0007](decisions/0007-hook-not-executable-is-fail.md) で **FAIL に上げる**と合意し、T04 として切り出した。準備フェーズの 3 件も合意済み（spec の「合意済みの決定」と決定 0006）。

## このセッションで触らなかったが確認したもの

- **`harness/adapters/codex/README.md`**: Codex 側の事実は公式 docs 確認済み（2026-09-17）だが、**実機確認はこれから**（spec の B2）。Codex CLI はこの機に入っている。
- **古い macOS（15 未満）の経路**: `sha256sum` / `jq` が無い前提のコードは、この機では確かめられていない（tech-debt #3 の残り）。
- **`harness init` の perms**: 新規導入直後が docs=0600 / スクリプト=0711 になる。踏んでいないので直していない（tech-debt #9）。
- **`core.hooksPath` 未設定 / `.githooks/pre-commit` 自体が無いケース**: B6 の別分岐で、**WARN のまま**（決定 0007 のスコープ外。T04 の申し送り）。clone 直後の正常な途中状態でもあり、直し方も案内済み。「門番が不在なら FAIL」の論理をここまで広げるかは未検討。
