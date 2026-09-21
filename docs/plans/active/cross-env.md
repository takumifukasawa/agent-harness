# cross-env — エージェントと OS を問わず同じように動く

- 開始: 2026-09-20
- 状態: **フェーズ 1 完了**（5 タスク done、版 0.6.0、最終レビューと指摘の修正まで済み）。フェーズ 2（Codex）が残り
- 関連: [spec](../../spec/cross-env-support.md), [決定 0006](../../decisions/0006-support-bash-3-2.md), [決定 0007](../../decisions/0007-hook-not-executable-is-fail.md), `docs/tech-debt.md` #3

## 目的（何ができれば完了か）

4 象限（Claude / Codex × Windows / macOS）のうち、**macOS の 2 象限**を埋める。埋める過程で見つかる環境差は文書ではなく**コードと検査**に落とし、次の環境で同じ発見をしないようにする。

- フェーズ 1（受け入れ条件 A）: macOS の**素の bash 3.2** で `harness check` が全件 pass する
- フェーズ 2（受け入れ条件 B）: Codex 実機でハーネスが成立する

Windows × Codex は今回の対象外。

## 受け入れ条件（検査で確認できる形に）

フェーズ 1（A）:

- [x] A1. `/bin/bash .harness/bin/harness doctor` が **FAIL 0**。`LC_ALL=C` を付けず `ja_JP.UTF-8` のまま
- [x] A2. `/bin/bash .harness/bin/harness check` が **全件 pass**（T01 で 15 件、T02 で 18 件に増えた。pass=18 fail=0）
- [ ] A3. `harness init` が公開 URL からも動く — **機構は T02 で確認済**（URL 解決・`curl \| bash` とも動く）。公開 main が T01 前なので導入後の doctor だけ落ちる。**T03 で main に載せた後の 1 回で確定**（tech-debt #4）
- [x] A4. 決定 0006（bash 3.2 を切らない）に従っている
- [x] A5. 環境差の修正それぞれに検査・テストが付いている（T02。踏んだ 3 件それぞれに `tests/githooks.sh` / `tests/gc.sh` / `tests/stdin.sh`）

フェーズ 2（B）: spec の B1〜B4。A 完了時にタスクを足す。

## タスク分解（依存順）

| # | タスク | 状態 | 備考 |
|---|---|---|---|
| T01 | bash 3.2 で動く形に直す（27 箇所）+ 禁止検査 2 件 | **done** | `declare -A` 1 / `mapfile` 2 / `${var}` 化 24。受け入れは「素の `/bin/bash` で `check` 全件 pass」 |
| T02 | 踏んだ環境差を直す + A1 / A3 を確定 | **done** | 未到達だった `date -d` / `sed -i` は**踏んだぶんだけ**直す。**`.githooks/pre-commit` の実行ビット（git index を 100755 に）と、それを見逃す doctor B6 の偽 OK（`-x` を見ていない）もここ。** 公開 URL からの `init`（tech-debt #4）もここ |
| T04 | doctor B6 をフック実行不可で FAIL に上げる（決定 0007） | **done** | T02 は WARN 据え置きにしたが、`check` が緑のままでは今回と同じ見落とし方が残るため FAIL に上げる。Windows（`core.filemode=false`）で偽 FAIL を出さない判定は T02 の形を保つ |
| T03 | 導入コピー同期・CHANGELOG・版上げ | **done** | `harness status` drift 0 ／「プロジェクト側で必要な作業」を CHANGELOG に |
| T05 | 最終レビュー指摘 3 件の修正 | **done** | doctor B6 の文言 2 分岐化 / C3 の cp フォールバック / bash 3.2 lint に `harness/checks.seed.sh` を追加 |
| — | **フェーズ 1 完了・main へ載せた（`c1de264`）。tech-debt #4 も実機で返済** | **done** | 公開 URL からの init で new=25 seeded=15 / doctor FAIL 0 |
| T06 | Codex 実機の下ごしらえ（B1） | **done** | `codex login` は対話（ブラウザ）なので**人間が 1 回実行する**。そのうえで `harness init --agents codex` したプロジェクトで `.agents/skills/` が読まれ `$role-implementer` が呼べるかを実機で確認する。**ハーネス側の生成物は 2026-09-21 に確認済み**（7 スキル + `role-implementer` / `role-reviewer` が generated で入り、`.claude/` は作られない） |
| T07 | `harness/adapters/codex/README.md` の表を実機で確認して更新（B2 / C2） | **done** | 各行に確認日と結果を入れる。**すでに 1 行は実機で覆っている**（下の決定ログ 2026-09-21）: 「hook 相当は任意、仕様変動が大きいので v0 では使わない」→ **Codex 0.154.0 には hooks が実在する** |
| T08 | `task-orchestrate` の 1 タスクを Codex で最後まで回す（B3） | 次にやる | 実装役の起動 → 戻り値 → 統括の 3 点判定まで。題材は小さい実タスク（未着手の負債 #2 や #7 が候補） |
| T09 | 標準 deny を Codex でどう効かせるか決めて `docs/decisions/` に残す（B4） | **決定は done / 実装は未** | 候補は (a) `config.toml` の `sandbox_mode` / approval (b) **`PermissionRequest` / `PreToolUse` hook**（実機で形式を確認済み）(c) 現状どおり `.githooks/` だけで塞ぐ。**「どれが効くか」は実機で確かめてから決める**（この題材で 4 回続けて、推定のまま決めると外している） |

## 決定ログ（日付・決めたこと・理由・落選案）

- **2026-09-20 / bash 3.2 を切らない。** 実測で修正コストが 27 箇所しかないと分かったため。落選: 「4+ 必須 + 入口だけ 3.2 対応」（コスト差が 3 箇所しかないのに得るものが大きく違う）、「4+ 必須で現状維持」（doctor 自身が完走せず『止まるから安全』が成り立っていない）。詳細は [決定 0006](../../decisions/0006-support-bash-3-2.md)
- **2026-09-20 / A を完遂してから B。** A の修正が B の前提。順にやれば「Codex が悪いのか bash 3.2 が悪いのか」が混ざらない。落選: 並行分解（障害の切り分けが難しくなる。bash 3.2 の修正は 27 箇所しかないので並行で稼げる時間が小さい）、B を別題材に切り出す（Codex CLI が入ったこの機を使わない手はない）
- **2026-09-20 / フックが実行不可なら `doctor` は FAIL（WARN ではない）。** 「門番が不在」は劣化ではなく失敗。WARN だと `check` が緑のままで、今回の見落としを制度化することになる。既存プロジェクトが一度赤くなるのは意図した動作（`CHANGELOG` に修復手順）。落選: WARN 据え置き（見落とし経路が残る）、WARN + seed に独立検査を足す（重大度の問題を検査の数で埋める形。init 直後は素通りし、直す場所が 2 つに増える）。詳細は [決定 0007](../../decisions/0007-hook-not-executable-is-fail.md)
- **2026-09-20 / A の完了判定は `check` 全件 pass まで。** すべて機械判定。人の目測を入れない。実運用の周回検証は今回の作業そのものが兼ねる
- **2026-09-20 / T01 と T02 を 1 タスクにまとめた（当初案では別タスク）。** この題材は「`check` を赤から緑にする」作業なので、分けると**中間タスクで `check` が赤いまま**になり、`task-orchestrate` §2.3 の 3 点判定（終了コード 1 = fail → 再試行）が成功を fail と誤判定する。落選: 「判定だけ差し替える（fail 件数が減ればよしとする）」（検査が赤いのに done を認める前例になる）、「落ちる検査を一時的に skip する」（AGENTS.md の「検査を通すためにテストや検査そのものを弱めない」に正面から反する）

- **2026-09-21 / `check` の最適化は 50 秒で打ち切る。** B2 で取った実測から、残る候補の効果は 2〜4 秒で、`apply_plan` の復元判断やシナリオの独立性という壊してはいけないものを触る取引になる。落選: `apply_plan` の no-op スキップ（効果 2.4s に対し `init`/`update` の中核を触る）、使い捨てプロジェクトの数を減らす（spec の B2「検査を弱めない」に接触）、C の並列化（50s のうち 46s が 2 件なので 18 件の並列化では 4 秒ぶんしか縮まない。C1 の発動条件も満たさない）。詳細は [決定 0008](../../decisions/0008-stop-optimizing-check-at-50s.md)
- **2026-09-21 / フェーズ 2 は「実機で確かめてから書く」を徹底する。** 初回の実機確認だけで、README の表の 1 行（「hook 相当は任意。仕様変動が大きいため v0 では使わない」）が**事実と違う**ことが分かった。Codex 0.154.0 には `~/.codex/hooks.json` があり、`SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PermissionRequest` / `PostToolUse` / `SubagentStart` / `SubagentStop` / `Stop` を **Claude Code とよく似た形式**（`{"hooks": {"<Event>": [{"hooks": [{"type": "command", "command": "...", "timeout": 10}]}]}}`）で受け、`config.toml` の `[hooks.state]` に信頼ハッシュを持つ。**B4（標準 deny）の実装先としてまず疑うのはここ**で、`config.toml` の sandbox / approval だけではない。落選: 公式 docs の記述だけで README を確定する（2026-09-17 の記述がすでに 1 行外れていた）

## 進捗ログ（セッションごとに 1〜3 行）

- **2026-09-20**: 作業機を macOS に移し、初めて実機で計測。`check` は **pass=9 fail=4**、根本原因は `declare -A` による `init` の即死。走査に無かった 5 つ目のブロッカー（bash 3.2 + UTF-8 で `"$var日本語"` が `unbound variable`、24 行）を発見。準備フェーズの未確定 3 件をすべて合意し、決定 0006 を起票、spec と tech-debt #3 を実測に更新、3 タスクに分解した。
- **2026-09-20（続き）**: 準備フェーズの docs をコミットした際、**6 つ目のブロッカー**が出た。`.githooks/pre-commit` が git index 上で mode 100644 なので、`git clone` で持ってきたこのリポジトリでは **pre-commit が黙って無視されている**（`harness init` は `chmod +x` するが clone には効かない）。さらに `doctor` の B6 は `-f` しか見ていないため **`OK git hooks` と偽の緑を出していた**。T02 のスコープに追加。

- **2026-09-20（T01 完了）**: bash 3.2 対応 27 箇所 + 禁止検査 2 件（`tests/lint-bash-compat.sh`）。**`check` は pass=9 fail=4 → pass=15 fail=0**（検査自体が 13→15 件に増えた）、**`doctor` は OK=16 WARN=0 FAIL=0**、所要 1分27秒。統括が 3 点判定を実施し、禁止検査については**別の git リポジトリに違反を仕込んで実際に捕まることまで確認**した（空洞でない）。`init` が通るようになった結果 `sed -i`（6 箇所）と C3 の PATH 誤検知を新たに踏んだので同時に修正。`date -d`（`gc.sh:42`）は `gc` に実行経路が無く未到達のため未修正 → **tech-debt #8 に「gc に検査の経路が無い」ことを起票**。コミット 5 件（`567c1a5`..`de1e264`）。

## 未確定事項（人間の判断待ち）

- なし。
- **2026-09-20（T02 完了）**: `.githooks/pre-commit` の index mode を 100755 にし、doctor B6 を「index の mode は常に／作業ツリーの `-x` は `core.filemode != false` のときだけ」見る形に直した（Windows の偽警告を macOS から `core.filemode=false` で再現して回帰テスト化）。別ディレクトリへ clone し直し、**検査をわざと壊したコミットが拒否される**ところまで実測。`gc.sh` の `date -d` は GNU/BSD 両対応 + **読めない日付は WARN** にし、`tests/gc.sh`（7 シナリオ）で**検出経路を新設**（tech-debt #8 返済）。A3 の確認中に **7 つ目のブロッカー**を新規発見: `curl \| bash` 経路で `${BASH_SOURCE[0]}` が `unbound variable`（`self_repo()` では subshell だけ死ぬので**エラーを出しながら成功**していた。5 箇所を `:-` 付きに、`tests/stdin.sh` を登録）。**`check` は pass=15 → pass=18 fail=0**、`doctor` は OK=16 WARN=0 FAIL=0。コミット 3 件（`41153f0`..`b57206e`）。踏まなかったもの（`sha256sum` 不在、init の perms → tech-debt #9）は直していない。
- **2026-09-20（T04 完了）**: [決定 0007](../../decisions/0007-hook-not-executable-is-fail.md) に従い、`doctor` B6 の重大度を WARN → FAIL に。判定ロジック（index の mode は常に／作業ツリーの `-x` は `core.filemode != false` のときだけ）と直し方の文言は T02 のまま無変更で、**変えたのは重大度だけ**。`tests/doctor.sh` は 41 件 pass で、(a) 実行ビット無しで FAIL (b) index 100644 で FAIL (c) `core.filemode=false` では警告を出さない、の 3 シナリオが揃った。`check` は pass=18 fail=0、`doctor` は OK=16 WARN=0 FAIL=0 のまま。コミット 4 件（`3d4b826`..`94a8a58`）。**`core.hooksPath` 未設定 / フックが存在しない分岐は WARN のまま**（決定 0007 のスコープ外）。
- **2026-09-21（T03 完了 / フェーズ 1 完了）**: `VERSION` 0.5.0 → **0.6.0**（minor。managed の移動もマーカー形式の変更も無い）。`CHANGELOG` の `[Unreleased]` を `[0.6.0] - 2026-09-21` に切り替え、`harness update` で導入コピーを追従（`AGENTS.md` の `v=0.6.0`、`manifest.json` の `harness_version`。他 39 ファイルは drift 無し）。`check` pass=18 fail=0 / `doctor` OK=16 WARN=0 FAIL=0 / `status` drift 0。**これでフェーズ 1 の受け入れ条件 A1・A2・A4・A5 が揃った**（A3 は機構のみ確認、確定は main へ載せた後）。統括は `phase: review` に移し、観点を 4 つ（仕様突合 / 機能の完結性 / クロス環境 / 検査の実効性）に調整して最終レビューへ。
- **2026-09-21（最終レビュー + T05 完了 / フェーズ 1 クローズ）**: 観点 4 つ（仕様突合 / 機能の完結性 / クロス環境 / 検査の実効性。後ろ 2 つは既定の「並行性 / 認可」から差し替え）を下位モデルで並列に 1 回。**指摘 4 件、重複なし、すべて単独報告かつ修正コスト低**のため反証は回さず（条件は両方を満たす場合のみ）。1 件（spec A2 の件数ずれ）は統括の書き戻し漏れとして直接修正、残り 3 件を **T05** で潰した: (a) `doctor` B6 が「hooksPath は正しいが pre-commit が無い」状態で矛盾した文言と no-op の直し方を出していた → 2 分岐に分けて `harness update` を案内 (b) C3 のスタブ化が `ln -s` の失敗を握り潰していた → `cp` フォールバック。ただし実 `$PATH` 全体を対象にすると**タイムアウトと setuid の権限エラー**を踏んだので、ロジックを `build_exe_stub()` に切り出し「1 件も作れなかったときだけ失敗」に調整（`docs/learnings.md`） (c) bash 3.2 lint が **`harness/checks.seed.sh` を走査していなかった** → 追加し、`declare -A` を仕込んで実際に検出されることを確認。`check` pass=18 fail=0 / `doctor` OK=16 WARN=0 FAIL=0。コミット 3 件（`5126e91`..`06d626b`）。**フェーズ 1 はここでクローズ。**

- **2026-09-21（check-speed B2 / フェーズ 1 を main へ / フェーズ 2 の下ごしらえ）**: `check-speed` の B を 2 件目まで実施して**フル `check` 95s → 50s（−47%）**にし、[決定 0008](../../decisions/0008-stop-optimizing-check-at-50s.md) で打ち切りを決めて題材を閉じた（`04c1353`）。**前提の訂正**: B1b の「`doctor` 13 回 / `init` 15 回」は静的 grep 由来で外れ（実測 45 回 / 5 回。ヘルパー経由の呼び出しが grep に出ない）。cross-env フェーズ 1 の 35 コミットを **main へ FF マージして push**（`305d57b` → `c1de264`）、公開 URL からの `init` を実機で通して **tech-debt #4 を返済**（new=25 seeded=15 / `doctor` OK=15 WARN=1 FAIL=0。WARN は `source.local` 不在＝正常）。フェーズ 2 は **Codex が未ログイン**（`codex doctor` の auth が ✗）で止まっているので、T06〜T09 に分解して人間のログイン待ちにした。ログイン不要な範囲（`init --agents codex` の生成物、hooks の実在）は確認済み。

- **2026-09-21（フェーズ 2: T06 / T07 / T09 の決定まで）**: ユーザーが `codex login` を実行し、実機確認に入れた。**B1 達成**: `harness init --agents codex` したプロジェクトで、トップの `AGENTS.md`・`<subdir>` からの連鎖・`.agents/skills/` の 7 スキルがすべて読まれ、**`$role-implementer` の明示呼び出しが機能**した（SKILL.md の戻り値 6 フィールドと禁止事項を正確に再現）。**B2 達成**: `harness/adapters/codex/README.md` を実機確認の結果で全面更新（確認日 2026-09-21）。**B4 は決定まで完了**（[決定 0009](../../decisions/0009-codex-deny-via-pretooluse-hook.md)）: `PreToolUse` hook で deny が実際に効くことを実機で確認したが、**2 段階の信頼が要る**（プロジェクトの `trust_level` だけでは hook が 1 つも発火せず、hook 定義ごとの信頼が別途要る）ので「git に乗らないもの」として `doctor` で検出・案内する設計にし、`apply_patch` に deny が効かない既知の不具合（openai/codex#27833）もあるため `.githooks/` との二重を維持する。**途中で危うく誤った事実を README に書きかけた**（「ルートの AGENTS.md が読まれない」→ canary を仕込んだら読めていた）ので、確認手順を `docs/learnings.md` と README の「確認に使った方法」に残した。残りは **T08（task-orchestrate を Codex で 1 周）と T09 の実装**。
