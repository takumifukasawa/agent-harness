# payload-containment — ペイロードの混入を検査で止め、導入先にはコミットさせない

- 開始: 2026-10-16
- 状態: 計画中
- 関連: [決定 0013](../../decisions/0013-contain-payload-leaks.md)

## 目的（何ができれば完了か）

ペイロードに固有情報（会社名・プロジェクト名・個人情報など）が混入しても、(1) 配る前に機械で止まり、(2) すり抜けて配ってしまっても導入先の履歴には残らず、次の `update` で消える状態にする。

## 受け入れ条件（検査で確認できる形に）

- [ ] 禁止語リストに載った語を、このリポジトリのどのファイル（ペイロードに限らず `docs/` なども）に入れてコミットしようとしても、pre-commit が止める（`tests/` のシナリオで確認）
- [ ] `git config user.email` が禁止語に当たるとき、このリポジトリの pre-commit が止める（今回は作者のメールアドレスからも会社名が出た）
- [ ] 禁止語リストの場所は環境変数（例: `HARNESS_SENSITIVE_PATTERNS`）で上書きでき、テストは実際の PC のリストを読まない
- [ ] 同じ語が入ったペイロードで `init` / `update` を回すと、導入先へ何も書かずに止まる
- [ ] 同じ語が入った変更を `upstream` しようとすると止まる
- [ ] 禁止語リストが無い PC では検査をスキップし、黙らずに NOTE を出す
- [ ] 新しく `init` した導入先で、managed / generated が `git status` に出ない（gitignore されている）。コミットされるのは manifest、seed、`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` だけ
- [ ] managed をコミット済みの既存の導入先で `update` すると、index から外す手順（`git rm --cached`）を案内する。勝手に消さない
- [ ] clone 直後（managed が無い状態）に `doctor` が FAIL で `harness update` を案内する（`self-install` 済みの `harness` で実行した場合。同梱の CLI も gitignore されるため）
- [ ] clone 直後にエージェントのセッションを始めると、コミットされている `.claude/settings.json` の SessionStart が、スクリプトが無いことを黙らずに「`harness update` を回す」と案内する。CLI が PC に無い場合の取り方（curl）も案内する
- [ ] `harness check` が全件 pass

## タスク分解（依存順）

| # | タスク | 状態 | 備考 |
|---|---|---|---|
| T01 | 禁止語リストの置き場と書式を決め、ファイルとメールアドレスを検査する関数を作る | todo | 置き場は未確定事項 1。環境変数で上書きできるようにする（テスト用） |
| T02 | このリポジトリの `checks.sh` に fast の検査として登録する（pre-commit で回る） | todo | T01 に依存。**ペイロードだけでなく全ファイルと `user.email` を見る**（今回公開されたものの大半は `docs/` と作者メールだった） |
| T03 | `init` / `update` の書き込み前に同じ検査をかける | todo | T01 に依存 |
| T04 | `upstream` に同じ検査をかける | todo | T01 に依存 |
| T05 | 調査: Codex が `AGENTS.md` 以外のファイルを読み込めるか（確認日と確認元を残す） | todo | 未確定事項 2 の材料。T01〜T04 と並列可 |
| T06 | lockfile 方式の設計: gitignore する範囲、既存の導入先の移行、clone 直後の案内（`doctor` / SessionStart） | todo | T05 の結果で `AGENTS.md` の扱いを決める。**`CLAUDE.md` は managed だがプロジェクトの内容を残す特別扱い（`bin/harness` の apply_plan）なので gitignore しない。** `.claude/settings.json` はマージ方式でコミットされ続けるので、SessionStart のコマンドがスクリプト不在時に案内する形にする。clone 直後は同梱の CLI も無いので、`self-install` 済みの `harness` か curl で取る経路を案内する |
| T07 | lockfile 方式の実装と 1.0.0（`VERSION` / `CHANGELOG.md` に「プロジェクト側で必要な作業」） | todo | T06 に依存 |
| T08 | このリポジトリ（dogfood）と既存の導入先を移行する | todo | T07 に依存。導入先ではユーザーの許可を取る |

## 決定ログ（日付・決めたこと・理由・落選案）

- **2026-10-16 / 検査と lockfile 方式の両方をやる。** 理由と落選案は決定 0013。検査（T01〜T04）は小さく作れて lockfile 方式の後も無駄にならないので先に進める。
- **2026-10-16 / 計画の検算で 4 点を直した。** (1) 混入が配られた範囲は 0.10.x 以降ではなく 0.8.0 以降。(2) `CLAUDE.md` は managed だがプロジェクトの内容を残すので gitignore しない。(3) clone 直後は CLI も SessionStart のスクリプトも無いので、案内の経路を T06 で設計する。(4) このリポジトリの pre-commit はペイロードだけでなく全ファイルと `user.email` を見る。

## 進捗ログ（セッションごとに 1〜3 行）

- **2026-10-16**: 公開前の精査でペイロードへの混入が見つかったことを受けて計画を作成。リポジトリは履歴を 1 コミットに作り直して公開し直した。

## 未確定事項（人間の判断待ち）

1. **禁止語リストの置き場。** 案: `~/.config/agent-harness/sensitive-patterns`（PC 単位。このリポジトリでも `init` / `update` でも同じものを使える）、または source の clone 内の gitignore 対象ファイル。前者を推す。
2. **`AGENTS.md` の管理ブロックの扱い。** Claude は `CLAUDE.md` からの `@` 読み込みで gitignore したファイルに移せる。Codex で同じことができなければ、管理ブロックを数行の案内に縮めてコミットする（混入し得る面積を目で確かめられる量に減らす）。T05 の結果で決める。
3. **既に配った分の後始末。** 実プロジェクトの名前が入ったコメント（`.harness/scripts/seed-case.sh` と `.harness/scripts/doctor.sh`）は onboarding-polish T02 で入ったもので、**0.8.0 以降に `init` / `update` した導入先すべて**にコミットされている可能性がある（`CHANGELOG.md` の 0.8.0 の節）。各リポジトリで実際に入っているか、公開されているかを確かめる。
