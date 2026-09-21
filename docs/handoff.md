# handoff — 現在地

最終更新: 2026-09-21（cross-env をクローズし tech-debt #12 を返済して**版 0.7.1**。続けて**実プロジェクト（aesthetic-comparison）へ初めて実地導入**し、seed の case 衝突（#13）を発見した）

## いま何をしているか（1〜3 行）

題材は **cross-env**（エージェントと OS を問わず同じに動く）。**準備フェーズは完了し、合意はすべて spec と決定 0006 に書き戻してある。** **フェーズ 1（macOS で動く）は完了。** 5 タスク done、版 **0.6.0**、最終レビュー 1 回と指摘 3 件の修正（T05）まで済み、`.harness/state/progress.json` は `phase: done`（**ユーザーの承認待ち**）。残るのは main へのマージとフェーズ 2（Codex）。

**`docs/spec/check-speed.md` は A（計測）完了・B は 2 件目まで完了**（`ac529ff` → `264892d` → `04c1353`）。フル `check` の推移:

| | 秒 | 内訳 |
|---|---|---|
| A 実装時 | 95s | `doctor scenarios` 58s + `update scenarios` 30s で 93% |
| B1（ハッシュのバッチ化）後 | 62s | 43s + 15s |
| **B2（プロセス起動の削減）後** | **50s** | **34s + 12s**。`--fast`（pre-commit）は 1s のまま |

B2 の中身は (1) `doctor` の B5（改行）を一括判定に（337→253ms）(2) `same_script` の重複 3 回 → 1 回（tech-debt #11 返済）(3) `apply_plan` の一時ファイル使い回し（`update` 793→611ms、`init` 1080→840ms）。**検査は 1 件も減らしていない**（18 件 pass のまま）。

**前提の訂正**: B1b で「`doctor` 13 回 / `init` 15 回」としていたのは**静的 grep 由来で外れ**（実測は `doctor` 45 回 / `init` 5 回）。「`doctor` を速くしても効かない」という結論は取り下げた。回数は実行時に数える（`docs/learnings.md` 2026-09-21）。計画と進捗は `docs/plans/active/cross-env.md`、機械可読な状態は `.harness/state/`。

**作業機は macOS（Darwin 24.6 / arm64 / 素の bash 3.2.57）。** 2026-09-20 に初めて実機で回し、`harness check` が **pass=9 fail=4** だったところを **pass=18 fail=0**（検査自体が 13 → 18 件）にした。**`.githooks/pre-commit` は T02 で本当に走るようになった**（index mode 100755）。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`main`**（`cross-env` の 35 コミットを FF マージして `origin/main` へ push 済。`c1de264`） | `git branch -vv` |
| VERSION | **0.7.1**（update が source 側の CLI で走る。2026-09-21）。`CHANGELOG.md` の `[0.7.1]` と `AGENTS.md` のマーカー `v=0.7.1`、`manifest.json` の `harness_version` が一致 | `VERSION`, `CHANGELOG.md` |
| 検査 | **20 件 pass / 0 fail**（**59 秒**。0.7.0 で `codex adapter`、0.7.1 で `tests/update.sh` の U14 が増えた）。T01 で禁止検査 2 件、T02 で `githooks are executable` / `gc scenarios` / `stdin (curl \| bash) install` の 3 件が増えた | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **OK=16 WARN=1 FAIL=0**。**WARN 1 は Codex の標準 deny hook が未信頼**（`.codex/hooks.json` は配られたが、この PC で `/hooks` による信頼をしていない。意図した挙動で、信頼すれば消える）。**T04 で B6 の重大度が WARN → FAIL になった**（フックが実行不可＝門番が不在。決定 0007）。このリポジトリは index が 100755 なので OK のまま | `/bin/bash .harness/bin/harness doctor` |
| macOS の素の bash | **3.2.57 のまま動く**（決定 0006 で「3.2 を切らない」と決めた）。`brew install bash` は**もう要らない** | 決定 0006 |
| 導入コピーの drift | なし（modified=0 missing=0）。**T02 以降 `update` は mode 差分も残さない**（実行ビットを index の正にしたため） | `harness status` |
| 決定 | 0001〜**0007**（0007: フックが実行不可なら doctor は FAIL） | `docs/decisions/` |
| 題材 | **cross-env は完了**（`docs/plans/completed/cross-env.md`）。`docs/plans/active/` は空。`.harness/state/` も畳んだ | `docs/plans/` |
| 最終レビュー | 観点 4 つ（仕様突合 / **機能の完結性** / **クロス環境** / **検査の実効性**。後ろ 2 つは既定の「並行性 / 認可」から差し替え）を下位モデルで並列。**指摘 4 件、すべて単独報告かつ修正コスト低なので反証は回していない**（条件は両方満たす場合のみ） | `.harness/state/reports/review-*.md` |
| 技術負債 | **#4 #7 #8 #11 #12 は返済済**、**#6 は打ち切り**（決定 0008）、**#3 はほぼ返済済**（残るのは古い macOS 15 未満）。未着手は **#1 #2 #9 #10** | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

**フェーズ 1 と check-speed は閉じた。次は cross-env のフェーズ 2（Codex）。**

1. **実プロジェクトへの初導入をやった（2026-09-21）。** `/Users/fukasawa-takumi/Documents/developer/aesthetic-comparison`（Next.js、既存の `AGENTS.md` と手書き docs 11 ファイルあり）に `harness init` を実行。**既存資産は無傷**（変更は `.gitignore` / `AGENTS.md` / `CLAUDE.md` の 3 ファイルに 65 行追加のみ、既存 docs は 0 件変更）で、`AGENTS.md` は Next.js が自動で足すブロック（`<!-- BEGIN:nextjs-agent-rules -->`）とも共存した。`doctor` FAIL 0 / `gc` 問題なし / `check` pass=2 まで持っていったが、**コミットはしていない**（ユーザーの判断待ち）。
   - **そこで #13 を発見**（seed の case 衝突）。その場は `git mv docs/HANDOFF.md docs/handoff.md` で解消した
   - **残りの一手**: 向こうの `.harness/checks.sh` はまだ seed の 2 件だけ。Next.js プロジェクトなので `npm run lint` / `tsc --noEmit` / `next build` を登録すると「完了の客観条件」が機能し始める
2. **次の題材が未定。** `docs/plans/active/` は空で、`.harness/state/` も無い。候補は残る未着手の負債:
   - **#1**（`.claude/settings.json` の自動マージが node 前提。無い環境では断片を手で反映）— 配布の穴。jq 対応か bash だけの簡易マージ
   - **#2**（`harness gc` の判定がヒューリスティック）— 誤検知が出たら精度を上げる、という保留のまま
   - **#9**（`init` 直後の perms が docs=0600 / スクリプト=0711）— まだ実害を踏んでいない
   - **#10**（ハッシュ常駐サーバが中断時に一時ディレクトリを残す）— `trap` の統合が要る
   **どれも低優先。** 新しい題材（spec から書く）を立てるほうが自然なら、そちらを先に決める。
3. **人間の作業が 1 つある（任意）: このリポジトリで Codex の hook を信頼する。** `doctor` の WARN 1 はこれ。ディレクトリで `codex` を起動し、プロジェクトの信頼を求められたら信頼したうえで `/hooks` で hook を信頼すると消える（各 PC で 1 回。git には乗らない）。**Codex をこの PC で使わないなら放置してよい。**
3. （参考）**未着手の負債**: #1（settings.json の node 依存）#2（gc のヒューリスティック）#7（`tests/source.sh` への分離）#9（init の perms）#10（常駐サーバの trap 統合）。いずれも低優先で、関連箇所を触るときに一緒に返す。

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
| `.harness/state/` | フェーズ 1 の記録（`phase: done`）。**フェーズ 2 を始めるときに作り直す**。捨てた場合は `docs/plans/active/cross-env.md` と git log から再構成する |

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
/bin/bash .harness/bin/harness check   # 18 件 pass（約 50 秒）
# 実行ビットは index に入っているので chmod は要らない（0.6.0 以降）
```

## 未確定事項（人間の判断待ち）

- なし。B6 の重大度は [決定 0007](decisions/0007-hook-not-executable-is-fail.md) で **FAIL に上げる**と合意し、T04 として切り出した。準備フェーズの 3 件も合意済み（spec の「合意済みの決定」と決定 0006）。

## このセッションで触らなかったが確認したもの

- **`harness/adapters/codex/README.md`**: Codex 側の事実は公式 docs 確認済み（2026-09-17）だが、**実機確認はこれから**（spec の B2）。Codex CLI はこの機に入っている。
- **古い macOS（15 未満）の経路**: `sha256sum` / `jq` が無い前提のコードは、この機では確かめられていない（tech-debt #3 の残り）。
- **`harness init` の perms**: 新規導入直後が docs=0600 / スクリプト=0711 になる。踏んでいないので直していない（tech-debt #9）。
- **`core.hooksPath` 未設定 / `.githooks/pre-commit` 自体が無いケース**: B6 の別分岐で、**WARN のまま**（決定 0007 のスコープ外。T04 の申し送り）。clone 直後の正常な途中状態でもあり、直し方も案内済み。「門番が不在なら FAIL」の論理をここまで広げるかは未検討。
- **T05 で受け入れ条件を実測で調整した点**: C3 のスタブ化は「`ln -s` も `cp` も失敗したら落とす」と指示したが、実装役は `/usr/bin/sudo`（setuid・所有者以外読み取り不可）で `cp` が Permission denied になる実例を踏み、**「1 件も stub 化できなかったときだけ失敗」**に変えた。判断は妥当だが、**診断に要るコマンド（git / sed）だけが失敗したケースは依然見逃す**。実害が出たら区別を足す。
