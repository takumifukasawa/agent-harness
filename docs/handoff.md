# handoff — 現在地

最終更新: 2026-09-28（**題材 `timing-anywhere` 完了・ユーザー承認待ち**。計画を立てない小さな作業でも `harness task start/done` で記録でき、`eta` が実績を出す）

## いま何をしているか（1〜3 行）

**`timing-anywhere` が承認待ち**（[spec](spec/timing-anywhere.md)）。`.harness/state/` が無くても `harness task start <id>` を叩けば記録が始まり（作ったことは必ず言う）、`harness eta` は `tasks` が空でも「記録 N 件（最小〜最大、平均）」と実行中の経過を出す。**進捗 N/M だけは分母が無いので「不明」と言い、数字は捏造しない。**

**この題材で 3 日ぶんの落とし穴を 1 つ根本から潰した。** `timings` ブロックの書き込みが `timings_ensure_block` / `timings_splice` / `timings_render_block` に散らばり、「`timings` の後ろに必ず他のキーが続く」前提が**4 回**踏まれていた（配布テンプレートの 1 行空配列 / 最小 state のキー順 / キー 0 個の `{}`）。T03 で **`timings_write_block` に一本化**し、副次効果として**既に壊れた `stages.json` も `task start` を 1 回叩けば直る**（統括が実機確認）。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`main`**。**未 push のコミットが溜まっている**（`origin/main` は `c1de264` のまま） | `git status -sb` |
| VERSION | **0.9.0**（2026-09-28。`harness task` / `harness eta` の追加で minor）。**実プロジェクトへの配布はこれから** | `VERSION`, `CHANGELOG.md` |
| 検査 | **全件 pass が期待値**（件数・所要時間は都度コマンドで確認。手で数値を書かない） | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **FAIL 0 が期待値**。**既知の WARN が残ることがある: Codex の標準 deny hook が未信頼**（この PC で `/hooks` による信頼をしていない。意図した挙動） | `/bin/bash .harness/bin/harness doctor` |
| `harness gc` | **`docs/tech-debt.md` の未着手負債の INFO だけが期待値**。WARN が出たら書き戻し漏れなので直す | `/bin/bash .harness/bin/harness gc` |
| 導入コピーの drift | なし | `harness status` |
| 決定 | 0001〜**0010** | `docs/decisions/` |
| 進捗と残り時間 | **`harness eta`** が記録から出す（`harness task start/done` で貯める）。推測で答えない | `/bin/bash .harness/bin/harness eta` |
| `DESIGN.md` §11 | **⬜ はゼロ**（2026-09-23）。実装状況の表は全項目 ✅ | `grep '⬜' DESIGN.md` |
| 題材 | **6 題材完了**（cross-env / check-speed / onboarding-polish / no-silent-failures / writeback-sensors / handoff-writeback）。**`docs/plans/active/` は空** | `docs/plans/`, `docs/spec/` |
| 技術負債 | 未着手は **#1 #2 #9 #10 #16 #17**（#18 は 2026-09-23 に返済済み） | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

1. **`timing-anywhere` の承認 → クローズ。** 承認が取れたら spec の状態欄を「完了（承認済み）」にし、**版を上げる**（`harness task` の挙動が変わり `gc` に項目 13 が増えたので **minor（0.10.0）**）。上げたら `bash bin/harness update` でこのリポジトリを追従させ、**`aesthetic-comparison` にも配る**（向こうのプロジェクト固有の作業には触らず、managed のファイルだけコミットする）。
2. **未 push が溜まっている。**
3. **未着手の負債**（どれも低優先）: #17（`gc` の docs 全体スキャン。3 秒を超えたら着手）/ #16（`settings.json` の case 衝突。被害事例が出るまで着手しない）/ #1 / #2 / #9 / #10
4. **dogfood で見つかった 2 つの想定外**（`DESIGN.md` §11 の小節に記録済み。**直すかは未判断**）: 別リポジトリを操作すると向こうの `AGENTS.md` が統括に載らない / `task-orchestrate` の「各段階でコミット」とプロジェクト側の「コミットは都度許可」が衝突する
5. **（任意・人間の作業）Codex の hook を信頼する。** `doctor` の WARN 1 件はこれ。

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
| `.harness/state/` | **`handoff-writeback`（完了）のものが残っているだけ。** 確定事項はすべて docs に書き戻してあるので**捨ててよい**（次の題材を始めると `state-template` から作り直される） |

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
/bin/bash .harness/bin/harness doctor  # FAIL 0 が期待値
/bin/bash .harness/bin/harness check   # 全件 pass が期待値（件数・所要時間はこのコマンドで確認）
# 実行ビットは index に入っているので chmod は要らない（0.6.0 以降）
```

## 未確定事項（人間の判断待ち）

- **なし。** `handoff-writeback` は最終レビュー（検査の実効性）で**指摘 0 件**、未解決の指摘も無い。

## このセッションで触らなかったが確認したもの

- **`docs/architecture.md`**: カバレッジ表を置く案があったが、[決定 0010](decisions/0010-stop-building-plumbing.md) で落選にしたので触っていない。
- **`docs/learnings.md`**: 2026-09-22〜23 で新しい罠は踏んでいない（既存の学び「並列可否は全体同期コマンドの有無で見る」に従って全タスクを逐次にし、事故は起きなかった）。
- **古い macOS（15 未満）の経路**: `sha256sum` / `jq` が無い前提のコードは未検証（tech-debt #3 の残り）。
- **`harness init` の perms**: 新規導入直後が docs=0600 / スクリプト=0711。踏んでいないので直していない（tech-debt #9）。
- **`core.hooksPath` 未設定 / `.githooks/pre-commit` 自体が無いケース**: `doctor` B6 の別分岐で **WARN のまま**（決定 0007 のスコープ外）。clone 直後の正常な途中状態でもある。
