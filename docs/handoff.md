# handoff — 現在地

最終更新: 2026-09-22（**題材 writeback-sensors が完了・ユーザー承認済み。これで 5 題材目**。次は `DESIGN.md` の書き戻しか、負債 #18 を題材にするか）

## いま何をしているか（1〜3 行）

**進行中の題材は無い。** 直前の **writeback-sensors**（統括の書き戻し漏れを、文章ではなく検査＝sensor に落とす）は 2026-09-22 に完了・承認済み（`docs/plans/completed/writeback-sensors.md`）。

**この題材の結論は「半分効いて、半分は効かないと分かった」**。`gc` の項目 10（plan の状態欄）と新設した項目 11（spec の状態欄）は**状態の矛盾**を見るので確実に効き、作業中に実際に本物の漏れを 3 件見つけた。一方 **A（handoff の鮮度をコミット数で見る）は「頻度」を見ているため、日常的な漏れが設計上すべて閾値の下に隠れる**（既定値 10 の根拠データが中央値 2 なので、発火するのは例外的なケースだけ）。**この非対称が [#18](tech-debt.md) で、次の題材の第一候補**。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`main`**。**未 push のコミットが 10 件ある**（`origin/main` は `c1de264` のまま） | `git status -sb` |
| VERSION | **0.7.1**。`CHANGELOG.md` の `[Unreleased]` に writeback-sensors の変更が溜まっている（**次に版を上げるときここを切り替える**） | `VERSION`, `CHANGELOG.md` |
| 検査 | **全件 pass が期待値**（件数・所要時間は都度コマンドで確認。手で数値を書かない）。この題材で `tests/gc.sh` のシナリオが大幅に増えた | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **FAIL 0 が期待値**（内訳は都度コマンドで確認）。**既知の WARN が残ることがある: Codex の標準 deny hook が未信頼**（この PC で `/hooks` による信頼をしていない。意図した挙動で、信頼すれば消える） | `/bin/bash .harness/bin/harness doctor` |
| `harness gc` | **`docs/tech-debt.md` の未着手負債の INFO だけが期待値**。WARN が出たら書き戻し漏れなので直す | `/bin/bash .harness/bin/harness gc` |
| 導入コピーの drift | なし | `harness status` |
| 決定 | 0001〜**0009** | `docs/decisions/` |
| 題材 | **5 題材完了**（cross-env / check-speed / onboarding-polish / no-silent-failures / writeback-sensors）。**`docs/plans/active/` は空** | `docs/plans/` |
| 技術負債 | 未着手は **#1 #2 #9 #10 #16 #17 #18**（#17 #18 はこの題材で起票）。返済済みと打ち切りの内訳はファイルを見る | `docs/tech-debt.md` |

## NEXT（依存順。順序制約があれば明記）

1. **次の題材の第一候補: [#18](tech-debt.md)（A の sensor が同一セッション内の書き戻し漏れを検出しない）。** 2026-09-22 にユーザーと「次の題材に格上げする」と合意済み。**閾値の調整では解けない**（5 に下げる案は「警告が出すぎる」として決定ログで落選済みで、その理由は今も正しい）。**頻度ではなく状態を見る角度から設計し直す**: `.harness/state/progress.json` の `phase` と handoff の記述を突き合わせる、または `session-handoff` を通らずにセッションが終わること自体を検出する（後者は sensor ではなく guide の領域かもしれない）。**着手するなら spec から書く**（受け入れ条件を後付けにしない）。
2. **`DESIGN.md` の書き戻し（統括の書き戻し漏れが 3 件たまっている）。** 題材を立てるほどではないので、次の題材の準備フェーズと並行してよい。
   - **§11 の状態行が「0.3.0（2026-09-17）」のまま。** 実際は **0.7.1**。5 日・5 題材ぶんの化石
   - **⬜3 dogfood**: `task-orchestrate` を 5 題材ぶん回した実測があるのに未記入。確かめること として挙がっているのは「再試行『新しい 1 体』の精度とコスト」「Codex でのパス限定規律」「`checks.sh` に何を登録すると効くか」「統括が迷う箇所」
   - **⬜6 `curl | bash` init**: [tech-debt #4](tech-debt.md) は「**返済済（2026-09-21）**」、macOS も #3 で実機確認済みなのに、表は ⬜ かつ「macOS / Linux 未確認」のまま
   - **あわせて「セッションの切り方」も書き戻す**: `DESIGN.md` §5 は「統括のセッションを切らない」と解釈したことを**事実ではなく解釈**と明記し、dogfood で確かめるとしている。**2026-09-22 のセッションは 6 タスク + レビュー 4 体を 1 セッションで通してしまい、`task-orchestrate` §2.3「タスクが完了したら切る」から外れた**（前回も同じことを書いて、また守れていない）。**「守れない原則」なら原則の方を直すべきで、その判断こそ dogfood の成果**
3. **未着手の負債**（どれも低優先。関連箇所を触るときに一緒に返す）:
   - **#17**（`gc` の docs 全体スキャンが plans の規模で重い）— 合成データで 9.2s 残る。**`gc` が 3 秒を超えたら着手**。T04 と同じ「全体を 1 回走査して対応表を作る」手が使えるはず
   - **#18 はここから外した**（NEXT 1 の題材候補に格上げ）
   - **#16**（`.claude/settings.json` の case 衝突）— 実害は反証で覆っており、既存挙動。**実際の被害事例が出るまで着手しない**
   - #1（settings.json の node 依存）/ #2（gc のヒューリスティック）/ #9（init の perms）/ #10（常駐サーバの trap 統合）
4. **実プロジェクト（`aesthetic-comparison`）の続き（2026-09-21 に初導入済み、コミットは未）。** 向こうの `.harness/checks.sh` はまだ seed の 2 件だけ。Next.js プロジェクトなので `npm run lint` / `tsc --noEmit` / `next build` を登録すると「完了の客観条件」が機能し始める。
5. **（任意・人間の作業）このリポジトリで Codex の hook を信頼する。** `doctor` の WARN 1 件はこれ。ディレクトリで `codex` を起動し、プロジェクトを信頼したうえで `/hooks` で hook を信頼すると消える（各 PC で 1 回。git には乗らない）。**Codex をこの PC で使わないなら放置してよい。**

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
| `.harness/state/` | **`writeback-sensors`（完了・承認済み）のものが残っているだけ。** 確定事項はすべて docs に書き戻してあるので**捨ててよい**（次の題材を始めると `state-template` から作り直される）。`reports/` にタスクとレビューの報告が参照用に入っている |

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

- **なし。** writeback-sensors は 2026-09-22 に完了として承認された。**未解決のレビュー指摘が 1 件だけ残っている**: `tests/gc.sh` の G24 がフルスイート初回実行で単発 FAIL したという報告（直後の単体実行は PASS、フルスイート 18 回連続では再現せず、原因未特定）。`.harness/state/progress.json` の `final_review.unresolved_findings` に記録してある。**再発したら G24 の一時ディレクトリと git 初期化まわりを最初に疑う。**

## このセッションで触らなかったが確認したもの

- **`DESIGN.md`**: §11 に書き戻し漏れが 3 件あることを確認したが、題材の途中だったので直していない（NEXT 2）。
- **`docs/learnings.md`**: 今回は新しい罠を踏んでいない（過去の学び「並列可否は全体同期コマンドの有無で見る」に従って 6 タスクすべて逐次にし、事故は起きなかった）。
- **`harness/adapters/codex/README.md`**: Codex 側の事実は公式 docs 確認済み（2026-09-17）。
- **古い macOS（15 未満）の経路**: `sha256sum` / `jq` が無い前提のコードは、この機では確かめられていない（tech-debt #3 の残り）。
- **`harness init` の perms**: 新規導入直後が docs=0600 / スクリプト=0711 になる。踏んでいないので直していない（tech-debt #9）。
- **`core.hooksPath` 未設定 / `.githooks/pre-commit` 自体が無いケース**: `doctor` B6 の別分岐で **WARN のまま**（決定 0007 のスコープ外）。clone 直後の正常な途中状態でもある。
