# handoff — 現在地

最終更新: 2026-09-29（**0.10.1 で生成物から `model: inherit` を外し（効果の実機確認は次のセッション）、0.10.2 で地図の場所を「雛形の既定・索引が正」に改めた**。統括の既定モデルを Opus 5.5 に寄せる方針はチャット上の合意で、docs への書き戻し先は未決）

## いま何をしているか（1〜3 行）

**題材はすべて完了**（`timing-anywhere` は 0.10.0 でクローズ、`915f255`）。**`docs/plans/active/` は空。**

2026-09-29 に「Opus 5.5 と Fable 5.1 の使い分け」の相談から、**implementer / reviewer が `model: inherit` のせいで統括と同じモデル（Fable）で走っていた**ことを実機で見つけ、[決定 0011](decisions/0011-generated-agents-do-not-pin-model.md) で生成物から `model` 行を外した（0.10.1、patch）。**同じセッションでは `.claude/agents/` の変更が反映されず、省略時にサブエージェント既定（`CLAUDE_CODE_SUBAGENT_MODEL`）で走ることは未確認**（公式 docs の解決順ではそうなる）。

同日、ユーザーの Claude Code 設定（`~/.claude/settings.json`、このリポジトリの外）の effort を xhigh → high に下げた。元のファイルは同じ場所に `.bak-20260929`。

## 状態

| 項目 | 状態 | 出典 |
|---|---|---|
| ブランチ | **`main`**。**push 済みが期待値**（`ahead` が出たら push 忘れ） | `git status -sb` |
| VERSION | **0.10.2**（2026-09-29。0.10.1 は生成物の変更、0.10.2 は地図の文言。どちらも patch）。**実プロジェクト（`aesthetic-comparison`）への 0.10.x の配布は未確認**（向こうで `harness doctor` を叩けば source に新版があるかが INFO で出る） | `VERSION`, `CHANGELOG.md` |
| 検査 | **全件 pass が期待値**（件数・所要時間は都度コマンドで確認。手で数値を書かない） | `/bin/bash .harness/bin/harness check` |
| `harness doctor` | **FAIL 0 が期待値**。**既知の WARN: Codex の標準 deny hook が未信頼**（この PC で `/hooks` による信頼をしていない。意図した挙動） | `/bin/bash .harness/bin/harness doctor` |
| `harness gc` | **`docs/tech-debt.md` の未着手負債の INFO だけが期待値**。WARN が出たら書き戻し漏れなので直す | `/bin/bash .harness/bin/harness gc` |
| 導入コピーの drift | なし（0.10.1 に追従済み） | `harness status` |
| 決定 | 0001〜**0011** | `docs/decisions/` |
| 進捗と残り時間 | **`harness eta`** が記録から出す（`harness task start/done` で貯める）。推測で答えない | `/bin/bash .harness/bin/harness eta` |
| `DESIGN.md` §11 | **⬜ はゼロ**（2026-09-23）。実装状況の表は全項目 ✅ | `grep '⬜' DESIGN.md` |
| 題材 | **7 題材完了**（cross-env / check-speed / onboarding-polish / no-silent-failures / writeback-sensors / handoff-writeback / timing-anywhere）。**`docs/plans/active/` は空** | `docs/plans/`, `docs/spec/` |
| 技術負債 | 未着手は **#1 #2 #9 #10 #16 #17**（#18 は 2026-09-23 に返済済み） | `docs/tech-debt.md` |
| `.harness/state/` | `timing-anywhere` の完了状態（`phase: done`）が残っているだけ。確定事項は docs に書き戻し済みなので**捨ててよい** | `.harness/state/progress.json` |

## NEXT（依存順。順序制約があれば明記）

1. **0.10.1 の実機確認（新しいセッションで。同じセッションでは定義が再読み込みされない）。** `implementer` を `model` 無指定で起動し、「自分の system prompt のモデル名を 1 行で報告」させる。`CLAUDE_CODE_SUBAGENT_MODEL`（opus）のモデルと答えれば完了。**確認できたら**、[決定 0011](decisions/0011-generated-agents-do-not-pin-model.md) の「実機では未確認」と `CHANGELOG.md` 0.10.1 の「未確認」を消す。**親と同じモデルと答えたら**、公式 docs の解決順がこの環境では成り立っていないということなので、決定 0011 の落選案（`model: opus` を書く）を再検討する。
2. **統括の既定モデル方針の書き戻し**（`未確定事項` 参照）。1 とは独立。
3. **他プロジェクトへの配布（0.10.0〜0.10.2）。** `aesthetic-comparison` と、`docs/GAME.md` を仕様にしているプロジェクト。向こうのプロジェクト固有の作業には触らず、managed のファイルだけコミットする。1 の確認が済んでからの方が「実装役が既定モデルで走る」ことを説明できる。**GAME.md のプロジェクトでは配布後に一回だけ**: `docs/README.md` に GAME.md / AGENTS_NOTES.md の行、`docs/spec/README.md` の表に `../GAME.md` の行を足す（seed なので `update` では届かない。移動はしない）。
4. **未着手の負債**（どれも低優先）: #17（`gc` の docs 全体スキャン。3 秒を超えたら着手）/ #16（`settings.json` の case 衝突。被害事例が出るまで着手しない）/ #1 / #2 / #9 / #10
5. **dogfood で見つかった 2 つの想定外**（`DESIGN.md` §11 の小節に記録済み。**直すかは未判断**）: 別リポジトリを操作すると向こうの `AGENTS.md` が統括に載らない / `task-orchestrate` の「各段階でコミット」とプロジェクト側の「コミットは都度許可」が衝突する
6. **（任意・人間の作業）Codex の hook を信頼する。** `doctor` の WARN 1 件はこれ。

## 別の PC で再開するとき

**スキルには 2 系統あり、配られ方が違う。**

| 系統 | 置き場 | 別 PC へは |
|---|---|---|
| ハーネスのスキル（`session-catchup` / `session-handoff` / `task-orchestrate` / `harness` / `harness-maintain`） | **各プロジェクトの `.claude/skills/`**（コミット対象） | **clone で付いてくる。作業不要** |
| 汎用スキル（`context-catchup` / `task-eta` / `orchestrator-model-split` / `skill-creator` / `blog-review` / `game-*` など） | **マシン全体の `~/.claude/skills/`** | **`agent-skills` を clone して installer を回す** |

### git に乗らないもの（再作成が要る）

| | どうするか |
|---|---|
| **`.harness/source.local`** | `echo '<clone した絶対パス>' > .harness/source.local`。無いと `update` / `diff` / `upstream` が公開 URL を見に行く。`doctor` が WARN で直し方ごと案内する |
| **`core.hooksPath`** | `git config core.hooksPath .githooks`。`.git/config` は clone で引き継がれない |
| ~~`.githooks/pre-commit` の実行ビット~~ | **T02 で不要になった。** index が 100755 になったので clone しただけで実行ビットが付く。`doctor` の B6 も実行可否まで見る（`core.filemode=false` の Windows では偽警告を出さない） |
| `.harness/state/` | **`timing-anywhere`（完了）のものが残っているだけ。** 確定事項はすべて docs に書き戻してあるので**捨ててよい**（次の題材を始めると `state-template` から作り直される） |
| **`~/.claude/settings.json`** | このリポジトリの外。`env.CLAUDE_CODE_SUBAGENT_MODEL`（opus）と `effortLevel`（high）はここ。**implementer / reviewer がどのモデルで走るかはこの設定で決まる**（0.10.1 以降、生成物はモデルを固定しない） |

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

- **統括（メインセッション）の既定モデルを Opus 5.5 にし、Fable 5.1 を「上げる先」にする方針。** 2026-09-29 のチャットで合意寄りだが、`/model` の切り替えはユーザーの手作業で、まだ実施されたか不明。根拠: Anthropic の Opus 5.5 発表（2026-09-22）の 9 項目ベンチはすべて Opus 5.5 が上、ただし発表自身が「ほとんどの仕事で Fable 5.1 と同水準」「実利用での差はスコアが示すより小さい」と注記。公式モデル一覧のレイテンシ区分は Opus 5.5 = Moderate、Fable 5.1 = Slower。**書き戻し先の候補**: `AGENTS.md` のプロジェクト固有節に「`task-orchestrate` の上位 = fable、下位 = opus / sonnet。統括ごと Fable に上げるのは長い自律実行・分解が難しい曖昧な仕様・Opus 5.5 の xhigh でも足りない時」と 1 行。ハーネス本体の文書は「上位・下位」の相対表現なので変更不要。
- **`.harness/state/` の `timing-anywhere` 分を捨てるか。** 捨ててよい状態（上の表）。

## このセッションで触らなかったが確認したもの

- **`docs/roles/implementer.md` / `reviewer.md`**: 変更なし。0.10.1 は生成物の既定を `reviewer.md` の「モデルは既定で下位で足りる」に揃えただけで、役割文自体は正しかった。
- **`DESIGN.md`**: 「モデル選択: 設計の余地で決める」（§ 反復）は相対表現のままで正しい。変更なし。
- **`harness/adapters/codex/README.md`**: `inherit` の記述は Codex の `--model` 指定に関するもので、今回の件とは別。正しいので変更なし。
- **`tests/`**: 生成物の frontmatter に `model` 行が無いことを固定する回帰テストは足していない（`harness check` の「installed copies in sync」で導入コピーは追従するが、生成器の出力そのものは検査していない）。踏み直したら足す。
- **`docs/architecture.md` / `docs/tech-debt.md`**: 変更なし。負債の増減もなし。
- **古い macOS（15 未満）の経路 / `harness init` の perms（#9）/ `core.hooksPath` 未設定時の `doctor` B6**: 前回と同じく未着手。
