# payload-containment — ペイロードの混入を検査で止め、導入先にはコミットさせない

- 開始: 2026-10-16
- 状態: 進行中（lockfile 方式は 1.0.0 で実装済み。形で分かるものの検査 T01〜T04 と既存の導入先の移行 T08 が残り）
- 関連: [決定 0013](../../decisions/0013-contain-payload-leaks.md)

## 目的（何ができれば完了か）

ペイロードに固有情報が混入しても、(1) 形で分かるもの（パス・メールアドレス・トークン・非公開リンク）は配る前に機械で止まり、(2) すり抜けて配ってしまっても導入先の履歴には残らず、次の `install` / `update` で消える状態にする。会社名やプロジェクト名のような固有名は機械では止めない（決定 0013）。

## 受け入れ条件（検査で確認できる形に）

検査（形で分かるもの）:

- [ ] ユーザー名入りの絶対パス・メールアドレス・トークン形の文字列・非公開ワークスペースのリンクを、このリポジトリのどのファイル（ペイロードに限らず `docs/` なども）に入れてコミットしようとしても、pre-commit が止める（`tests/` のシナリオで確認）
- [ ] 同じものがコミットメッセージにあるとき、または `git config user.email` が例示用・`noreply` 系以外で検査に当たるときの扱いを決め、テストで確認する（未確定事項 4）
- [ ] 例示用のもの（`example.com` / `example.invalid`、`noreply@anthropic.com`、テスト用の `t@t`、`/Users/<名前>` のようなプレースホルダ）では止まらない
- [ ] 同じものが入ったペイロードで `init` / `update` / `install` を回すと、導入先へ何も書かずに止まる
- [ ] 同じものが入った変更を `upstream` しようとすると止まる

lockfile 方式:

- [ ] manifest に `source_commit`（入れた source のコミット）が記録される
- [ ] `harness install` が manifest の `source_commit` の中身をそのまま入れ、manifest を変えない。source の既定ブランチが先に進んでいても、固定した版が入る
- [ ] `source_commit` が source に無い（履歴を作り直したなど）とき、`install` は黙って最新を入れず、止まって `update` を案内する
- [ ] `harness update` は今までどおり版を上げ、`source_commit` を書き換える
- [ ] 新しく `init` した導入先で、gitignore 対象の managed / generated が `git status` に出ない。コミットされるのは manifest、seed、`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` だけ
- [ ] managed をコミット済みの既存の導入先で移行すると、index から外す手順（`git rm --cached`）を案内する。勝手に消さない
- [ ] clone 直後（managed が無い状態）に `self-install` 済みの `harness` で `doctor` を回すと、FAIL で `harness install` を案内する
- [ ] 手元に入っている版と manifest の `source_commit` がずれているとき（他の人が版を上げて pull した後）、SessionStart と `doctor` が `harness install` を案内する
- [ ] clone 直後にエージェントのセッションを始めると、コミットされている `.claude/settings.json` の SessionStart が、スクリプトが無いことを黙らずに「`harness install` を回す」と案内する。CLI が PC に無い場合の取り方（curl）も案内する
- [ ] `harness check` が全件 pass

## タスク分解（依存順）

| # | タスク | 状態 | 備考 |
|---|---|---|---|
| T01 | 形で分かるもの（パス・メール・トークン・非公開リンク）を検査する関数を作る。例示用の除外も入れる | todo | 禁止語リストは作らない（決定 0013） |
| T02 | このリポジトリの `checks.sh` に fast の検査として登録する（pre-commit で回る） | todo | T01 に依存。**ペイロードだけでなく全ファイル**を見る。コミットメッセージと `user.email` は未確定事項 4 |
| T03 | `init` / `update` の書き込み前に同じ検査をかける | todo | T01 に依存。`install` は T07 で足すときに同じ検査を通す |
| T04 | `upstream` に同じ検査をかける | todo | T01 に依存 |
| T05 | 調査: Codex が `AGENTS.md` 以外のファイルを読み込めるか。Codex の PreToolUse hook のスクリプトが無いとき、操作を止めるのか素通りさせるのか（確認日と確認元を残す） | todo（1.0.0 では設計で避けたが、T10 のために後半だけ要る） | 未確定事項 2 と、`.codex/hooks.json` の扱いの材料。T01〜T04 と並列可 |
| T06 | lockfile 方式の設計: gitignore する範囲、manifest の `source_commit`、手元に入れた版の記録、`install` の動き、既存の導入先の移行、clone 直後と版ずれの案内（`doctor` / SessionStart） | **done** | T05 の結果で `AGENTS.md` と `.codex/hooks.json` の扱いを決める。`CLAUDE.md` と `.claude/settings.json` はコミットのまま |
| T07 | lockfile 方式の実装（`install` の新設、`source_commit` の記録、gitignore、案内）と 1.0.0（`VERSION` / `CHANGELOG.md` に「プロジェクト側で必要な作業」） | **done** | T06 に依存 |
| T09 | source の信用リストを PC 側に置く: `install` / `update` は、リポジトリの外（例: `~/.config/agent-harness/trusted-sources`。公式 URL は最初から信用）にある source からしか取らない。無ければ止まり、信用する手順（例: `harness trust <URL>`）を出す。あわせて `source_commit` が 40 / 64 桁の 16 進数であることを確かめる。README の curl を版のタグに向けるかも決める | todo | 2026-10-16 のコミット時のセキュリティレビューの指摘。manifest の `source` を 1 行書き換えたコミットを pull して `install` すると、そのリポジトリの CLI が動く（1.0.0 より前は同梱 CLI の差分で見えたが、1 行の差分は見落とされやすく、`install` は pull のたびに回す）。リストに入るのは取得元の URL だけで、漏れて困る名前は入らない |
| T10 | `.codex/hooks.json` をコミットに戻し、`codex-deny.sh` が無いときは操作を止める（fail-closed）形にする | todo | 同じレビューの指摘。1.0.0 では pull から `install` までの間、Codex の deny が効かない（Claude は `.claude/settings.json` で効く）。T05（Codex がフックの失敗をどう扱うか）を先に確かめる |
| T08 | このリポジトリ（dogfood）と既存の導入先を移行する | 進行中（このリポジトリは移行済み。既存の導入先は未） | T07 に依存。導入先ではユーザーの許可を取る |

## 決定ログ（日付・決めたこと・理由・落選案）

- **2026-10-16 / 検査と lockfile 方式の両方をやる。** 理由と落選案は決定 0013。検査（T01〜T04）は小さく作れて lockfile 方式の後も無駄にならないので先に進める。
- **2026-10-16 / 計画の検算で 4 点を直した。** (1) 混入が配られた範囲は 0.10.x 以降ではなく 0.8.0 以降。(2) `CLAUDE.md` は managed だがプロジェクトの内容を残すので gitignore しない。(3) clone 直後は CLI も SessionStart のスクリプトも無いので、案内の経路を T06 で設計する。(4) このリポジトリの pre-commit はペイロードだけでなく全ファイルを見る。
- **2026-10-16 / 禁止語リストは作らない。** リスト自体が漏らしたくない名前の一覧になる（ユーザーの判断）。機械で止めるのは形で分かるものだけにし、固有名は lockfile 方式と版を上げる前の通読で受ける。
- **2026-10-16 / clone 直後は `update` ではなく新設の `install` を回す。** 2 回目の検算で、`update` は `source_ref` が空だと既定ブランチの最新を入れる（`bin/harness` の `resolve_source`）ので版を固定できないと分かった。manifest に `source_commit` を記録し、`install` がそれを入れる。版を上げるのは今までどおり `update`。

- **2026-10-16 / T05 は調べずに設計で避けた。** `AGENTS.md` の管理ブロックはコミットのまま（`harness/AGENTS.core.md` の 60 行。混入し得る面積が小さく、通読で守れる）。`.codex/hooks.json` は gitignore する（コミットしたままスクリプトだけ無いと、Codex がフックの失敗をどう扱うか分からない。clone 直後は Codex の deny が効かないが、Claude の deny は `.claude/settings.json` に書いてありコミットされるので残る。`doctor` が報告する）。Codex の挙動を確かめる必要が出たら T05 を戻す。
- **2026-10-16 / `install` は固定コミットを `git archive` で一時ディレクトリへ取り出し、その版の CLI に exec して配る。** 配る判断（plan）を固定された版にさせるためと、同梱コピーを実行しながら上書きしないため。`install` は同梱コピーへ委譲しない（`maybe_delegate`）。固定された版が `install` を知らない（1.0.0 より前）なら止まって `update` を案内する。
- **2026-10-16 / `.gitignore` は 1 ファイルずつ管理ブロックに載せる。** ディレクトリ単位（`.agents/skills/` など）にすると、プロジェクトが自分で置いたスキルまで無視される。ブロックは毎回作り直す。
- **2026-10-16 / 既にコミットされた配布物は外し方を案内するだけ。** `update` の出力と `doctor` の B13 に `git rm --cached` のコマンドを出す。勝手に外さない（pull した他の clone では作業ツリーから消えるので、その人は `install` が要る。CHANGELOG に書いた）。

## 進捗ログ（セッションごとに 1〜3 行）

- **2026-10-16（1.0.0）**: lockfile 方式を実装した（`harness install`、manifest の `source_commit`、`.gitignore` の管理ブロック、`.harness/installed` と版ずれの案内、clone 直後の案内、doctor B13）。`tests/lockfile.sh` 9 シナリオ、`harness check` 26 件 pass。このリポジトリも移行した（配布物 27 件を index から外した）。実装中に `git ls-files --pathspec-from-file`（存在しないオプション）の失敗を `2>/dev/null || true` で握りつぶしていたのをテストが拾った。
- **2026-10-16**: 公開前の精査でペイロードへの混入が見つかったことを受けて計画を作成。リポジトリは履歴を 1 コミットに作り直して公開し直した。同日、検算 2 回とユーザーの判断で、禁止語リストの廃止と `install` / `source_commit` の追加を反映した。

## 未確定事項（人間の判断待ち）

1. （解決済み 2026-10-16）禁止語リストの置き場 → リストは作らない。
2. **`AGENTS.md` の管理ブロックの扱い。** Claude は `CLAUDE.md` からの `@` 読み込みで gitignore したファイルに移せる。Codex で同じことができなければ、管理ブロックを数行の案内に縮めてコミットする（混入し得る面積を目で確かめられる量に減らす）。T05 の結果で決める。
3. **既に配った分の後始末。** 実プロジェクトの名前が入ったコメント（`.harness/scripts/seed-case.sh` と `.harness/scripts/doctor.sh`）は onboarding-polish T02 で入ったもので、**0.8.0 以降に `init` / `update` した導入先すべて**にコミットされている可能性がある（`CHANGELOG.md` の 0.8.0 の節）。各リポジトリで実際に入っているか、公開されているかを確かめる。
4. **コミットメッセージと `git config user.email` の検査をどこまでやるか。** 今回は作者のメールアドレスから会社名が出たが、メールアドレスのドメインが会社のものかは形だけでは分からない。案: このリポジトリでは「`user.email` は `noreply` か、manifest や README に書いた公開済みの身元と一致すること」を求める。T02 で決める。
