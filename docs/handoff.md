# handoff — 現在地

最終更新: 2026-09-23（**`handoff-writeback` 完了で `gc` の項目追加は打ち止め（[決定 0010](decisions/0010-stop-building-plumbing.md)）。次は `DESIGN.md` §11 の ⬜3 dogfood** ＝ ①ワークフローの検証に戻る）

## いま何をしているか（1〜3 行）

**進行中の題材は無い。** 直前の `handoff-writeback`（[spec](spec/handoff-writeback.md)）で [tech-debt #18](tech-debt.md) を返済し、**`gc` は 12 項目で打ち止め**にした。

**2026-09-23 に方針を変えた**（[決定 0010](decisions/0010-stop-building-plumbing.md)）。`DESIGN.md` は「①ワークフローが主役、②配管は最小限」と書いているのに、**6 題材のうち 5 題材が②の配管**で、§11 の **⬜3 dogfood は ⬜ のまま**だった。SmartHR から取り入れたのは①（プロダクトのコードに対する検査を含む）で、**`gc` は②配管の一部（出典は OpenAI の doc-gardening）**。同じものとして数えていたのが混同の元。**以後 `gc` の項目は実害を踏んでから足す（再開条件: 同じ腐りを 2 回踏んだとき）。**

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`main`**。**未 push のコミットが溜まっている**（`origin/main` は `c1de264` のまま） | `git status -sb` |
| VERSION | **0.7.1**。`CHANGELOG.md` の `[Unreleased]` に writeback-sensors と handoff-writeback の変更が溜まっている（**次に版を上げるときここを切り替える**） | `VERSION`, `CHANGELOG.md` |
| 検査 | **全件 pass が期待値**（件数・所要時間は都度コマンドで確認。手で数値を書かない） | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **FAIL 0 が期待値**。**既知の WARN が残ることがある: Codex の標準 deny hook が未信頼**（この PC で `/hooks` による信頼をしていない。意図した挙動） | `/bin/bash .harness/bin/harness doctor` |
| `harness gc` | **`docs/tech-debt.md` の未着手負債の INFO だけが期待値**。WARN が出たら書き戻し漏れなので直す | `/bin/bash .harness/bin/harness gc` |
| 導入コピーの drift | なし | `harness status` |
| 決定 | 0001〜**0010**（0010: ②配管の作り込みを打ち止めにして①に戻る） | `docs/decisions/` |
| 題材 | **6 題材完了**（cross-env / check-speed / onboarding-polish / no-silent-failures / writeback-sensors / handoff-writeback）。**`docs/plans/active/` は空** | `docs/plans/`, `docs/spec/` |
| 技術負債 | 未着手は **#1 #2 #9 #10 #16 #17**（#18 は 2026-09-23 に返済済み） | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

1. **`DESIGN.md` §11 の ⬜3 dogfood。残る ⬜ はこれ 1 件だけ。** 実プロジェクト `/Users/fukasawa-takumi/Documents/developer/aesthetic-comparison`（Next.js）に `harness init` は済んでいる（2026-09-21、**コミットはまだ**）。**向こうの `.harness/checks.sh` は seed の 2 件だけなので、`npm run lint` / `tsc --noEmit` / `next build` を登録すると「完了の客観条件」が機能し始める。** §11 が「確かめること」に挙げているのは 4 つ:
   - **`checks.sh` に何を登録すると効くか**（これが今の主眼。②ではなく①の検証）
   - 再試行「新しい 1 体」の精度とコスト
   - Codex でのパス限定規律（cwd か明示渡し）
   - `task-orchestrate` の手順で統括が迷う箇所
   **このリポジトリ自身では 6 題材を通した実測があるので、うち 3 つは書き戻せる。** 残る「`checks.sh` に何を登録すると効くか」だけが、実プロジェクトでやらないと分からない。
2. **`DESIGN.md` §5 の「セッションの切り方」を書き戻す。** §5 は「統括のセッションを切らない」と解釈したことを**事実ではなく解釈**と明記し、dogfood で確かめるとしている。**2026-09-22〜23 のセッションは 7 タスク + レビュー 5 体を 1 セッションで通しており、`task-orchestrate` §2.3「タスクが完了したら切る」から 3 回続けて外れた。3 回守れない原則は、原則の方が実態に合っていない。** 1 の dogfood と一緒に判断する。
3. **未着手の負債**（どれも低優先。関連箇所を触るときに一緒に返す）:
   - **#17**（`gc` の docs 全体スキャンが plans の規模で重い）— 合成データで 9.2s 残る。**`gc` が 3 秒を超えたら着手**
   - **#16**（`.claude/settings.json` の case 衝突）— 実害は反証で覆っており既存挙動。**実際の被害事例が出るまで着手しない**
   - #1（settings.json の node 依存）/ #2（gc のヒューリスティック）/ #9（init の perms）/ #10（常駐サーバの trap 統合）
4. **（任意・人間の作業）このリポジトリで Codex の hook を信頼する。** `doctor` の WARN 1 件はこれ。ディレクトリで `codex` を起動し、プロジェクトを信頼したうえで `/hooks` で hook を信頼すると消える（各 PC で 1 回。git には乗らない）。**Codex をこの PC で使わないなら放置してよい。**

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
