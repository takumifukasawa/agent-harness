# cross-env — エージェントと OS を問わず同じように動く

状態: **合意済み**（2026-09-20 に準備フェーズ §1.3 を完了）。フェーズ 1（受け入れ条件 A）から着手する。

## 目的

ハーネスの前提は「**エージェント（Claude / Codex）を問わず、PC（Windows / macOS / Linux）を問わず、同じ役割を果たす**」こと。設計はその形になっているが、**実機で確かめたのは 4 象限のうち 1 つだけ**だった。

```
                Claude          Codex
Windows         検証済み         未検証（今回の対象外）
macOS           フェーズ 1        フェーズ 2
```

今回埋めるのは **macOS の 2 象限**。Windows × Codex は残る（埋めるなら受け入れ条件を足す）。

埋める過程で見つかる環境差は、文書ではなく**コードと検査**に落とす（次の環境で同じ発見をしないため）。

## 進め方

**フェーズ 1（A）を完遂してからフェーズ 2（B）に入る。** A の修正が B の前提であり、順にやれば「Codex が悪いのか bash 3.2 が悪いのか」が混ざらない。

今回の修正作業そのものを `task-orchestrate` で進めるので、**macOS × Claude で task-orchestrate を 1 周回す検証は副産物として得られる**。そこで踏んだ罠は `docs/learnings.md` へ。

## 受け入れ条件

### A. macOS で動く（フェーズ 1）

- A1. `/bin/bash .harness/bin/harness doctor` が **FAIL 0**（WARN は任意依存のみ）。**`LC_ALL=C` を付けず `ja_JP.UTF-8` のまま**通ること
- A2. `/bin/bash .harness/bin/harness check` が **全件 pass**（T01 で禁止検査 2 件、T02 で `githooks are executable` / `gc scenarios` / `stdin (curl \| bash) install` の 3 件が増えて **18 件**）。同じくロケールを細工しない
- A3. `harness init` が公開 URL からも動く
- A4. **bash 3.2 を切らない**。macOS 既定の bash でそのまま動く形に落とす（**決定 0006**）
- A5. 環境差で壊れた箇所は、直すと同時に**その環境で落ちるテスト・検査**を足す（`tests/` に OS 分岐を持ち込むのではなく、両方で通る書き方に直すのが既定）

**判定はすべて機械**。人の目測は入らない。

### B. Codex で動く（フェーズ 2）

- B1. **完了（2026-09-21）。** 実機で `.agents/skills/` の 7 スキルが読まれ、`$role-implementer` の明示呼び出しが機能した（SKILL.md の戻り値 6 フィールドと禁止事項を正確に再現）
- B2. **完了（2026-09-21）。** `harness/adapters/codex/README.md` を実機確認の結果で全面更新（確認日 2026-09-21 / CLI 0.154.0）。「hook は v0 では使わない」という記述は実機で覆り、落とし穴（2 段階の信頼、`apply_patch` に deny が効かない）も併記した
- B3. **完了（2026-09-21）。** Codex の実装役（`$role-implementer`）に tech-debt #7（テストの分離）を 1 タスクとして渡し、**戻り値の JSON をスキルの形式どおり返して完走**した。統括（Claude）の 3 点判定も通った（受け入れ条件・範囲・報告の正確さ。独立検証と一致）。**範囲外の作業は自分でやらず統括へ申し送った**（tech-debt の返済記録と `architecture.md` の参照更新）
- B4. **完了（2026-09-21、版 0.7.0）。** 標準 deny は **`PreToolUse` hook** で効かせる（[決定 0009](../decisions/0009-codex-deny-via-pretooluse-hook.md)）。`init --agents codex` が `.codex/hooks.json` と `.harness/scripts/codex-deny.sh` を配り、`doctor` が「hook が信頼されていない＝効いていない」を WARN で報告する。対象は `.claude/settings.json` の deny と同じ 5 つ。検査は `tests/codex.sh`（19 件、codex CLI に依存しない）

**この機に Codex CLI 0.154.0 が入っている**（`/opt/homebrew/bin/codex`、確認日 2026-09-20）ので、環境待ちにはならない。

### C. 回帰を止める

- C1. 環境差の修正には必ず検査かテストを付ける。**「直した」だけで終わらせない**
- C2. 各環境で確認した事実は `harness/adapters/<agent>/README.md` に**確認日つき**で書く（このリポジトリの規約）

## 実機で分かっていること（2026-09-20、macOS 初回計測）

計測環境: Darwin 24.6 / arm64 / bash 3.2.57 / `LANG=ja_JP.UTF-8`。

`harness check` は **pass=9 fail=4**。**4 件のうち 3 件は根本原因が 1 つ**で、`harness init` が即死するためテストの setup が全滅していた。

| # | ブロッカー | 実体 | 箇所 | 状態 |
|---|---|---|---|---|
| 1 | `declare -A` | `declare: -A: invalid option` → **init が即死** | `bin/harness:355`（1） | **T01 で修正済み**（一時ファイル + awk に置換）。check の 3 FAIL の唯一の原因だった |
| 2 | `"$var日本語"` | bash 3.2 + UTF-8 で `unbound variable`。`${var}` と書けば通る | **24 行** | **T01 で修正済み**。禁止検査で再発を止めている。走査に無かった新発見 |
| 3 | `mapfile` | bash 4+ 専用。外部コマンド全滅時のフォールバック | `doctor.sh:76-77`（2） | **T01 で修正済み**（`while read` に置換） |
| 4 | `date -d` | `illegal option -- d` を確認 | `gc.sh:42` | **T02 で修正済み**。GNU/BSD 両方言に対応し、**読めない日付は無言でスキップせず WARN** を出すようにした（無言スキップが害の本体）。`tests/gc.sh`（7 シナリオ）を `checks.sh` に fast 登録して**検出経路も新設**（tech-debt #8 は返済済） |
| 5 | `sed -i` | 引数必須。`invalid command code` を確認 | `tests/doctor.sh`・`tests/update.sh` 計 6 | **T01 で踏んだので修正済み**（`sed_i()` ヘルパーで GNU/BSD 両対応） |
| 6 | `.githooks/pre-commit` の実行ビット | git index 上で mode **100644**。`harness init` は `chmod +x` する（`bin/harness:466`）が、**`git clone` で持ってくると実行ビットが付かず、git がフックを黙って無視する**（`hint: the '.githooks/pre-commit' hook was ignored because it's not set as executable`）。Windows の Git は `core.filemode=false` が既定なので気づかなかった | `.githooks/pre-commit` | **T02 で修正済み**。git index を 100755 に。doctor B6 は「index の mode は常に」「作業ツリーの `-x` は `core.filemode != false` のときだけ」見る（Windows で偽警告を出さない）。`tests/githooks.sh` を登録し、**別ディレクトリへ clone し直して門番が本当に働くこと**（壊した検査でコミットが拒否され HEAD が動かない）まで実測 |
| 7 | C3 テストの PATH 操作 | `node` / `jq` のディレクトリを PATH から丸ごと外す作りだったが、macOS 15+ では `jq` が `/usr/bin` に `git`・`sed` と同居しているため**それらも巻き添えで消え**、テストが誤検知する | `tests/doctor.sh` の C3 | **T01 で踏んだので修正済み**（実行ファイル単位のスタブ化に変更） |
| 8 | `${BASH_SOURCE[0]}` | `curl \| bash`（標準入力実行）で `unbound variable`。`self_repo()` の中では subshell だけが死ぬので**エラーを出しながら成功**し、`self-install` は案内の die に**届く前に**落ちる | `bin/harness` 5 箇所 | **T02 で修正済み**（`:-` 付きに）。A3 の確認中に新規発覚。`tests/stdin.sh` を登録 |

**#6 は doctor の穴でもある。** B6 は `core.hooksPath` の値と `-f`（存在）しか見ておらず、フックが実行不可でも `OK git hooks` と報告する。**検査が効いていないのに緑になる**のはハーネスの根幹（`AGENTS.md`「実装後は `check.sh` を回す。これが『完了』の客観条件」）に関わるので、`-x` を見るように直す。`handoff.md` の「別の PC で再開するとき」に書いてある `git config core.hooksPath .githooks` だけでは**不十分だった**ことになる。

**未到達のものは先回りで直さない**（当初の方針どおり）。T01 の修正で `init` が通るようになった結果、**`sed -i`（#5）と C3 の PATH 操作（#7）は実際に踏んだので直した**。`date -d`（#4）はまだ踏んでいないので触っていない。ただし**踏まない理由が「`harness gc` に実行経路が無い」ことなら、それは検査の穴**なので tech-debt #8 に起票した。

`sha256sum` と `jq` は **この機には Apple 提供のものが入っていた**（`/sbin/sha256sum` / `/usr/bin/jq`、macOS 15 以降）。`docs/tech-debt.md` #3 の「macOS には無い」という前提はこの機では当たらない。**古い macOS（15 未満）向けの経路は未検証のまま残る**。

`harness doctor` は（`LC_ALL=C` と `source.local` 設定後）**OK=15 WARN=0 FAIL=1**。FAIL は bash 版の 1 件だけ。

## 範囲外（やらないこと）

- **CI の構築**（GitHub Actions 等での自動マトリクス実行）。まず人が 1 周回して何が壊れるかを知る。自動化はその後の判断
- **Linux**。macOS が通れば多くは通るが、今回は確認対象に含めない
- **Windows × Codex**。今回埋めるのは macOS の 2 象限まで
- **古い macOS（15 未満）の実機確認**。`sha256sum` / `jq` が無い経路は `tests/doctor.sh` の C3 が PATH 操作で部分的に守っている
- **他のエージェント**（Cursor / Windsurf 等）への対応
- 環境差を吸収するための**大掛かりな抽象化**（POSIX 互換レイヤの自作など）。個別に直す

## 合意済みの決定（2026-09-20）

準備フェーズで 1 件ずつ詰めた。**会話ではなくここと `docs/decisions/` が正本。**

| # | 論点 | 決まったこと | 出典 |
|---|---|---|---|
| 1 | bash 3.2 を切るか | **切らない。** 3.2 で動く形に落とし、再発は検査で止める。実測 27 箇所（`declare -A` 1 / `${var}` 化 24 / `mapfile` 2） | [決定 0006](../decisions/0006-support-bash-3-2.md) |
| 2 | Codex の実機確認を誰がやるか | **この機でやる。** Codex CLI 0.154.0 が入っている。ただし **A を完遂してから B**（フェーズ 2） | この spec の「進め方」 |
| 3 | macOS の検証をどこまでやるか | **`check` 全件 pass まで**（A1〜A5）。判定はすべて機械。実運用の周回は今回の作業そのものが兼ねる | この spec の A |

## 未確定事項（人間の判断待ち）

- なし。
