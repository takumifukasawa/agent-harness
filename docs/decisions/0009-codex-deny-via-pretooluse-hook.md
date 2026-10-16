# 0009: Codex の標準 deny は `PreToolUse` hook で効かせる（git hooks との二重で）

- 日付: 2026-09-21
- 状態: 採用

## 背景

ハーネスには「やらないこと」がある（`AGENTS.md`: 破壊的な git 操作を指示なしに行わない、秘密情報をコミットしない）。Claude 側は `.claude/settings.json` の deny で機械的に塞げるが、**Codex 側には翻訳表が無く、`.githooks/` でしか塞げていなかった**（`harness/adapters/codex/README.md` の「標準 deny」行、2026-09-17 時点）。`docs/spec/cross-env-support.md` の B4 がこれを決めることを要求している。

2026-09-21 に Codex CLI 0.154.0 で実機確認した結果、判断に足る事実が出た:

- **`PreToolUse` hook で拒否できる。** hook が `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` を返すと、コマンドは実行されず `hook: PreToolUse Blocked` になり、モデルにも拒否理由が伝わる（実機で `echo FORBIDDEN-CANARY-3355` を止め、モデルが理由を引用した）
- hook はプロジェクトに置ける（`<repo>/.codex/hooks.json`）。**つまりハーネスが配れる**
- ただし **2 段階の信頼が要る**: (1) プロジェクトが `trust_level = "trusted"`（`~/.codex/config.toml`） (2) **さらに hook 定義ごとの信頼**（`/hooks` または `--dangerously-bypass-hook-trust`）。(1) だけでは hook は 1 つも発火しなかった（実機）
- **`apply_patch` には deny が効かない**（既知の不具合 openai/codex#27833: 「hook fires, write proceeds」）

## 採用案

**`PreToolUse` hook を配る。ただし「これだけで塞げる」とは考えず、`.githooks/` の門番を残したまま二重にする。**

1. `harness init --agents codex` が `<repo>/.codex/hooks.json` と deny スクリプト（`.harness/scripts/codex-deny.sh` 相当）を **managed** で配る。判定の中身は `AGENTS.md` の「やらないこと」と同じ対象（`git push --force` / 履歴の書き換え / ブランチ削除）
2. **信頼は「git に乗らないもの」として扱う。** `core.hooksPath` や `.harness/source.local` と同じ枠で、`doctor` が「hook が信頼されていないので効いていない」ことを検出し、直し方（`codex` を起動して `/hooks` で信頼する）を案内する。clone しただけで効くとは書かない
3. **`.githooks/pre-commit` は残す。** hook は `apply_patch` を止められず、信頼されるまで効かない。**git 側の門番が最後の砦**である状態を変えない（決定 0007 で FAIL に上げたのはこの砦のため）

「hook は仕様変動が大きいので v0 では使わない」という当初の判断（`harness/adapters/codex/README.md`、2026-09-17）はここで改める。実機で形式・イベント名・stdin の JSON・deny の効き方まで確認でき、Claude Code の hook と構造がほぼ同じであることが分かったため。**ただし「置けば効く」ものではない**という点は、README と `doctor` に正直に出す。

## 落選案と落選理由

- **`config.toml` の `sandbox_mode` / `approval_policy` で済ませる**: `sandbox_mode`（`read-only` / `workspace-write` / `danger-full-access`）は**ファイル書き込みとネットワークの範囲**の制御で、「`git push --force` だけを止める」という**コマンド名指しの禁止ができない**。`approval_policy` は人間に承認を求める運用へ戻す話で、`task-orchestrate` が実装役を自動で回す前提と噛み合わない（毎回止まる）。**粒度が合わない。**
- **現状どおり `.githooks/` だけで塞ぐ**: コミット経路は止まるが、`git push --force` はコミットを伴わないので **pre-commit では止まらない**。破壊的操作の多くが素通りする。hook が使えると実機で分かった以上、使わない理由がない。
- **hook だけにして `.githooks/` をやめる**: 信頼されるまで効かず、`apply_patch` にも効かない。**二重にしておく方が、どちらかが欠けても最低限が残る。**
- **`--dangerously-bypass-hook-trust` を既定の運用に入れる**: hook は確実に走るが、**プロジェクトが置いた任意のスクリプトを無条件に実行する状態**を常用することになる。ハーネスが配る hook のためにその穴を開けるのは、守ろうとしているものと釣り合わない。

## 影響・やり直す条件

- `harness init --agents codex` の配布物が増える（`.codex/hooks.json` と deny スクリプト）。**Claude だけを使うプロジェクトには配らない**（`--agents` の指定に従う）
- `doctor` に Codex 用の診断が 1 件増える。**Codex を使っていないプロジェクトでは出さない**（`manifest.json` の `agents` を見る）
- **やり直す条件**: (a) Codex が hook の信頼を要求しなくなる、または信頼を非対話で与える公式の手段が出たとき（案内文を差し替える） (b) `apply_patch` の deny が修正されたとき（`.githooks/` との二重を見直せる） (c) hook の JSON 形式が変わったとき（`harness/adapters/codex/README.md` の確認日を更新して追随する）

## 追記（2026-10-15、0.11.1）

[issue #1](https://github.com/takumifukasawa/agent-harness/issues/1) で、判定が文字列の部分一致のため書き方を変えると素通りすることが指摘された。判定は正規化してから語で見る形に直した（`CHANGELOG.md` の 0.11.1）。**取り出し失敗時の fail-open はこの決定のまま変えない**（Codex が何もできなくなるのを避ける。最後の砦は `.githooks/`）。ただし `command` を持つ入力なのに取り出せなかったときは stderr に残し、黙って通さないようにした。この hook は「エージェントの事故を止める安全網」で、意図して迂回する相手（`git` の alias、変数に入れたコマンド名、`eval` など）に対する境界ではない。そこまで塞ぐことは目的に入れない。

