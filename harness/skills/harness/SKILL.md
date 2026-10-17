---
name: harness
description: agent-harness の CLI をセッション内から実行し、結果を読んで次の行動を案内する。"/harness status", "/harness update", "/harness install", "/harness diff", "/harness check", "/harness upstream <path>", "/harness doctor" のように引数でサブコマンドを受ける。発火例 - "ハーネスの状態を見て", "ハーネスを更新して", "harness status", "検査を回して", "ハーネスの差分を見て", "このスキルの変更を上流に戻して", "ハーネスの環境を診断して"。引数が無ければ status を実行する。
---

# harness — CLI をセッション内から使う

CLI はプロジェクトに同梱されている: `.harness/bin/harness`（bash。Windows は Git Bash 経由。`harness` が PATH にあればそれでもよい）。
このスキルは CLI を**実行して結果を解釈する**だけ。判断（衝突の採否、上流に戻すか）はユーザーに返す。

## 実行

```bash
bash .harness/bin/harness <subcommand> [args]
```

| 引数 | やること | 結果の読み方 |
|---|---|---|
| `status`（既定） | 導入版、各ファイルの unchanged / MODIFIED / missing | MODIFIED な managed があれば「diff で見て、汎用なら upstream、プロジェクト固有なら AGENTS.md のプロジェクト領域へ移す」と案内。`source-changed` は `update` で再生成される |
| `update [--ref <tag>]` | 新版を取り込み、manifest の `source_commit`（版の固定）を書き換える。CHANGELOG を表示 | **実行する前に**、`status` の 1 行目で source を見る。`[.harness/source.local]`（この PC の agent-harness の clone）なら、ユーザーは最新を求めているので先にその clone を `git -C <パス> pull --ff-only` で最新にする（pull しないと古い版のまま「更新した」ことになる。pull できなければ止めて理由を伝える）。URL（`[manifest]`）なら pull は要らない。実行後に版が変わっていなければ（`update X -> X`）、source が最新か確かめる。表示された「プロジェクト側で必要な作業」を必ずユーザーに伝える。コミットするのは `.harness/manifest.json`（と `.gitignore` の変化）だけと伝える。`CONFLICT` が出たら `.harness/conflicts/<path>.new` と現ファイルの差分を取って提示し、採否を聞く。「追跡から外した」と出たら（1.0.0 より前からの移行）、外したことは stage 済みなので update の変更と一緒にコミットすること、そのコミットを pull した他の clone では `harness install` が要ることを伝える。「source の clone が上流より遅れている」と出たら、その clone で `git pull` してから update し直すよう伝える |
| `install` | manifest に固定された版（`source_commit`）をそのまま入れる。manifest は変えない | clone 直後・他の人が版を上げた manifest を pull した後に使う（配布物はコミットしない lockfile 方式）。「固定した版が source に無い」で止まったら、`update` で版を上げ直して manifest をコミットするよう案内する |
| `diff` | 手で直した managed ファイルの差分 | 上流に戻す候補。秘密情報・プロジェクト名が混ざっていないか見る |
| `upstream <path>...` | agent-harness リポジトリへ書き戻す（source がローカル clone のとき） | 成功したら「agent-harness 側で commit → CHANGELOG → VERSION」が次の作業だと伝える |
| `check [--fast]` | `.harness/checks.sh` の検査を回す | 失敗した検査の出力をそのまま報告。修復手順が書かれていればそれに従う |
| `doctor` | 環境と導入状態を診断する（終了コード: 0=FAIL 0 件、1=FAIL あり、2=未導入） | 1 行 1 項目 `OK\|WARN\|FAIL  項目  →  直し方`、末尾の集計行 `harness doctor: OK=n WARN=n FAIL=n` を報告。WARN/FAIL があれば各行の「→」の直し方に従う。`INFO`（source に新版あり）は集計に含めず、`harness update` を促す |
| `task start <id>` / `task done <id>` | タスクやレビューの所要時間を記録する（`.harness/state/stages.json` の `timings`）。id はタスク（`T01`）でもレビュー（`review`）でもよい | **`task-orchestrate` を使っていない単発の作業でも単独で使える**（計画やタスク分解は不要）。`.harness/state/` や `stages.json` が無ければ最小 state（`tasks: []` / `timings: []`）を自動で作り、作ったことを出力する（`docs/spec/timing-anywhere.md`） |
| `eta [--json]` | 進捗と残りの推定を出す。完了数 / 全体数、経過、幅のある推定、推定完了時刻。実績が足りなければ「不明」と言う | **`tasks` が空でも `timings` の実績があれば所要時間・実行中の経過時間を出す**（進捗 N/M だけは分母が無いので「不明」のまま。数字は捏造しない） |
| `version` | 版を表示 | |

## 別のプロジェクトへ入れる

「これを別のプロジェクトにも入れたい」と頼まれたとき（**今のプロジェクトではなく、他の作業先**への初導入）の案内。導入先のディレクトリで実行する。

- **agent-harness を clone 済みのとき**:
  ```bash
  bash /path/to/agent-harness/bin/harness init
  ```
- **clone していない PC でも、URL から直接**:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/takumifukasawa/agent-harness/main/bin/harness \
    | bash -s -- init --source https://github.com/takumifukasawa/agent-harness.git
  ```

入るもの: `AGENTS.md` の管理ブロック、`CLAUDE.md`（`@AGENTS.md`）、`.agents/skills/` と `.claude/skills/`、`docs/` の雛形、`.harness/`、`.githooks/pre-commit`。既存の `AGENTS.md` / `CLAUDE.md` は壊さず先頭に足すだけ。

**`init` は足場を置くだけ。** 直後の `check` は seed の検査しか回らないので、続けて案内する:

1. `.harness/checks.sh` にそのプロジェクトの検査（テスト・lint・型検査・ビルドなど、緑なら完了と言えるもの）を登録する。これが「完了の客観条件」になる。
2. `docs/spec/` に何を作るかを書く。受け入れ条件はここが唯一の正。
3. `bash .harness/bin/harness doctor` を回し、FAIL 0 を確認する。

## やらないこと

- `init` はこのスキルから実行しない（このスキル自身は既に導入済みのプロジェクトで発火する想定。今のプロジェクトへの導入は人間が行う。上の「別のプロジェクトへ入れる」は導入**先**で実行するコマンドの案内であり、この制約と矛盾しない）。
- 衝突ファイルを黙って上書きしない。`.harness/conflicts/` の中身を消さない。
- upstream 先のリポジトリで commit しない（レビューは人間）。

## 関連

- 育て方の手順（更新の取り込み、learnings の昇格、上流への戻し方、gc）: `.agents/skills/harness-maintain/SKILL.md`
