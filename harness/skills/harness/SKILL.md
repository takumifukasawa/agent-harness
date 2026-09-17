---
name: harness
description: agent-harness の CLI をセッション内から実行し、結果を読んで次の行動を案内する。"/harness status", "/harness update", "/harness diff", "/harness check", "/harness upstream <path>" のように引数でサブコマンドを受ける。発火例 - "ハーネスの状態を見て", "ハーネスを更新して", "harness status", "検査を回して", "ハーネスの差分を見て", "このスキルの変更を上流に戻して"。引数が無ければ status を実行する。
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
| `update [--ref <tag>]` | 新版を取り込む。CHANGELOG を表示 | 表示された「プロジェクト側で必要な作業」を必ずユーザーに伝える。`CONFLICT` が出たら `.harness/conflicts/<path>.new` と現ファイルの差分を取って提示し、採否を聞く |
| `diff` | 手で直した managed ファイルの差分 | 上流に戻す候補。秘密情報・プロジェクト名が混ざっていないか見る |
| `upstream <path>...` | agent-harness リポジトリへ書き戻す（source がローカル clone のとき） | 成功したら「agent-harness 側で commit → CHANGELOG → VERSION」が次の作業だと伝える |
| `check [--fast]` | `.harness/checks.sh` の検査を回す | 失敗した検査の出力をそのまま報告。修復手順が書かれていればそれに従う |
| `version` | 版を表示 | |

## やらないこと

- `init` はこのスキルから実行しない（未導入のプロジェクトで発火することはないはず。導入は人間が行う）。
- 衝突ファイルを黙って上書きしない。`.harness/conflicts/` の中身を消さない。
- upstream 先のリポジトリで commit しない（レビューは人間）。

## 関連

- 育て方の手順（更新の取り込み、learnings の昇格、上流への戻し方、gc）: `.agents/skills/harness-maintain/SKILL.md`
