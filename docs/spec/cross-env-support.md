# cross-env — エージェントと OS を問わず同じように動く

状態: **未合意（草案）**。準備フェーズ（`task-orchestrate` §1）で 1 件ずつ突き合わせてから実装に入る。

## 目的

ハーネスの前提は「**エージェント（Claude / Codex）を問わず、PC（Windows / macOS / Linux）を問わず、同じ役割を果たす**」こと。設計はその形になっているが、**実機で確かめたのは 4 象限のうち 1 つだけ**。

```
                Claude          Codex
Windows         検証済み         未検証
macOS           未検証           未検証
```

残り 3 象限を埋め、「動く」を**機械検査で判定できる状態**にする。埋める過程で見つかる環境差は、文書ではなく**コードと検査**に落とす（次の環境で同じ発見をしないため）。

## 受け入れ条件

### A. macOS で動く

- A1. `bash .harness/bin/harness doctor` が **FAIL 0** で終わる（WARN は任意依存のみ）
- A2. `bash .harness/bin/harness check` が **全件 pass**
- A3. `harness init` が公開 URL からも動く（現状 `bin/harness:87` の `sha256sum` は macOS に無い）
- A4. bash の要件を決めて守らせる。現在 `bin/harness` の `declare -A` と `doctor.sh` の `mapfile` は **bash 4+ 必須**だが macOS の既定は 3.2。**「4+ 必須」と割り切って doctor の FAIL に導入手順を書く**か、**3.2 でも動く形に落とす**かを決め、`docs/decisions/` に残す
- A5. 環境差で壊れた箇所は、直すと同時に**その環境で落ちるテスト**を足す（`tests/` に OS 分岐を持ち込むのではなく、両方で通る書き方に直すのが既定）

**着手前に読む**: `docs/tech-debt.md` #3 に、静的走査で特定した 4 箇所（bash 3.2 / `sha256sum` / `date -d` / `sed -i`）が具体的に書いてある。ただし**実機で動かせばさらに出る**前提で進める。

### B. Codex で動く

- B1. Codex 実機で `harness init --agents codex` したプロジェクトが成立する（`.agents/skills/` が読まれ、`$role-implementer` / `$role-reviewer` が呼べる）
- B2. `harness/adapters/codex/README.md` の表の各行を**実機で確認**し、確認日と結果を更新する（現状は公式 docs のみが出典、確認日 2026-09-17）
- B3. `task-orchestrate` の 1 タスクを Codex で最後まで回せる（実装役の起動 → 戻り値 → 統括の 3 点判定）
- B4. 標準 deny（`git push --force` 等）を Codex 側でどう効かせるか決める。現状 `config.toml` の sandbox / approval への翻訳表が無く、`.githooks/` でしか塞げていない。決定を `docs/decisions/` に残す

### C. 回帰を止める

- C1. 環境差の修正には必ず検査かテストを付ける。**「直した」だけで終わらせない**
- C2. 各環境で確認した事実は `harness/adapters/<agent>/README.md` に**確認日つき**で書く（このリポジトリの規約）

## 範囲外（やらないこと）

- **CI の構築**（GitHub Actions 等での自動マトリクス実行）。まず人が 1 周回して何が壊れるかを知る。自動化はその後の判断
- **Linux**。macOS が通れば多くは通るが、今回は確認対象に含めない（含めるなら受け入れ条件を足す）
- **他のエージェント**（Cursor / Windsurf 等）への対応
- 環境差を吸収するための**大掛かりな抽象化**（POSIX 互換レイヤの自作など）。個別に直す

## 未確定事項（人間の判断待ち）

1. **bash 3.2 を切るか**（A4）。切れば `brew install bash` が前提条件になり、doctor の FAIL にその手順を書く。切らなければ `declare -A` と `mapfile` を書き換える。**影響範囲と手間が大きく違うので、準備フェーズで最初に決める。**
2. **Codex の実機確認を誰がやるか**。Codex CLI が入った環境が要る。無ければ B は後回しにして A だけ先に進める
3. **macOS の検証をどこまでやるか**。`doctor` / `check` が通るところまでか、`task-orchestrate` を 1 周回すところまでか
