# harness doctor — 導入先の環境とハーネス導入状態の診断

- 状態: **完了（2026-09-18、VERSION 0.4.0 で出荷）**。計画は [`docs/plans/completed/harness-doctor.md`](../plans/completed/harness-doctor.md) へ畳んだ（合意は 2026-09-17。未確定 4 件をユーザーと確認し、すべて案どおりに決定）
- 起票: 2026-09-17

## 目的

別 PC や別 OS で「ハーネスが動かない」「status が全部 MODIFIED になる」といった状況で、原因と直し方を **1 コマンドで一覧にする**。`gc` が docs の健康診断なら、`doctor` は環境の健康診断。LLM は使わない。

## 受け入れ条件

### A. 起動と終了コード
- A1. `bash .harness/bin/harness doctor` で実行でき、`harness doctor` の usage 行が CLI の help に載る。
- A2. 終了コード: 問題なし `0`、WARN のみ `0`、FAIL あり `1`、実行環境不備（bash が無い等で診断自体ができない） `2`。
- A3. 未導入ディレクトリ（`.harness/manifest.json` が無い）で実行すると、導入コピーが無い旨と `harness init` の案内を出して `2` で終わる。

### B. 診断項目（各行: `OK|WARN|FAIL  項目  →  直し方`）
- B1. ツール: `bash` の版が 4 以上、`git` がある。無ければ FAIL。
- B2. 任意ツール: `node`、`jq` の有無。無ければ WARN（「settings 自動マージは手動になる」等、影響を添える）。Windows（`uname -s` が MINGW/MSYS/CYGWIN）では `cygpath` の有無も見る。
- B3. manifest: `.harness/manifest.json` が読め、1 エントリ 1 行の形式で、`harness_version` / `source` / `agents` が取れる。壊れていれば FAIL。
- B4. ファイルの存在: manifest に記載された path がすべて存在する（seed は除く。seed の欠落は WARN）。無いものは FAIL で一覧。
- B5. 改行: managed / generated のファイルに CR（`\r`）が含まれない。含まれれば FAIL（autocrlf を疑う直し方を添える）。**`*.cmd` は CRLF が正しい規約（`.gitattributes` の `*.cmd text eol=crlf`）なので判定から除外する。** `.gitattributes` に `.harness/** text eol=lf` があるか、無ければ WARN。
- B6. git hooks: `core.hooksPath` が `.githooks` で、`.githooks/pre-commit` が存在する。違えば WARN（直し方: `git config core.hooksPath .githooks`）。
- B7. AGENTS.md: マーカー `<!-- harness:begin v=X -->` と `<!-- harness:end -->` がちょうど 1 組あり、`X` が manifest の `harness_version` と一致。不一致は WARN（`harness update` を案内）、マーカー欠落や複数は FAIL。
- B8. Claude アダプタ（manifest の agents に `claude` を含むとき）: `CLAUDE.md` に `@AGENTS.md` がある。`.claude/skills/<name>` が `.agents/skills/<name>` と内容一致（ずれていれば WARN、`harness update` を案内）。`.claude/agents/*.md` が manifest どおりにある。
- B9. Codex アダプタ（`codex` を含むとき）: `.agents/skills/` に `role-implementer` と `role-reviewer` がある。
- B10. 版: source がローカルディレクトリなら、その `VERSION` と manifest の版を比べ、差があれば INFO で「新版あり」。source が URL のときはネットワークに触らない。
- B11. gitignore: `.harness/state/` `.harness/backup/` `.harness/conflicts/` が `.gitignore` にある。無ければ WARN。

### C. 出力と品質
- C1. 各 WARN / FAIL 行に直し方（可能ならそのまま実行できるコマンド）を含める。
- C2. 最後に集計行（OK / WARN / FAIL の件数）を出す。
- C3. 診断は bash と git だけで動く。node / jq が無くても全項目が実行できる。
- C4. 実装は `harness/scripts/doctor.sh`（managed）に置き、CLI の `doctor` サブコマンドはそれを `exec` する（`check` / `gc` と同じ構造）。
- C5. このリポジトリの `.harness/checks.sh` に「doctor が FAIL 0 で通る」検査を登録する。
- C6. `harness` スキルの表、README の表、DESIGN.md §8 に `doctor` を追記し、init の最後の案内文に `harness doctor` を促す 1 行を足す。
- C7. シナリオテスト `tests/doctor.sh`（このリポジトリ専用。ペイロードではない）を置き、D1〜D3 を自動で検証する。`.harness/checks.sh` に登録する。診断項目を足すときは先に失敗するシナリオを足す（TDD）。

### D. 検証
- D1. 使い捨てプロジェクトに `init` した直後の `doctor` は FAIL 0。
- D2. 意図的に壊した状態（managed ファイルを CRLF に変換、manifest 記載ファイルを削除、AGENTS.md のマーカー版を書き換え、hooksPath を外す）で、対応する項目が FAIL / WARN になる。
- D3. 未導入ディレクトリで A3 のとおり動く。

## 範囲外（やらないこと）

- 自動修復（`--fix`）。報告のみ。gc と同じ思想で、直すのは人か `harness update`。
- ネットワーク到達性（GitHub に届くか）の確認。
- 各エージェント（Claude Code / Codex）が実際にインストールされているかの確認。ハーネスはエージェントの有無に依存しない。
- macOS / Linux での実機検証（別タスク。doctor はその切り分けに使う）。

## 決定済み（2026-09-17）

- 自動修復 `--fix` は含めない。報告のみ（範囲外に記載）。
- 出力は人向けテキストのみ。`--json` は要望が出てから。
- 未導入ディレクトリでの終了コードは `2`（環境不備扱い。A3 に反映）。
- `init` / `update` の最後に doctor は自動で回さない。init の案内文に `harness doctor` を促す 1 行を足す（C6 に含める）。

## 未確定事項（人間の判断待ち）

なし。
