# harness doctor — 実行計画

- 開始: 2026-09-17
- 状態: 進行中（T01 から）
- 関連: `docs/spec/harness-doctor.md`（合意済 spec）、`docs/decisions/0001`
- 進め方: `task-orchestrate`（統括 = メインセッション、実装役は 1 タスク 1 体、検査は `harness check`、レビューは最後に 1 回）。機械可読な状態は `.harness/state/`。

## 目的（何ができれば完了か）

`bash .harness/bin/harness doctor` が、導入先の環境とハーネス導入状態を診断し、WARN / FAIL の各行に直し方を添えて一覧にする。spec の受け入れ条件 A〜D をすべて満たし、`tests/doctor.sh` で自動検証される。

## 受け入れ条件（検査で確認できる形に）

- [ ] `bash .harness/bin/harness check` が pass（`doctor scenarios` を含む）
- [ ] 使い捨てプロジェクトに init 直後の doctor が FAIL 0
- [ ] 未導入ディレクトリで exit 2
- [ ] spec の D2 の壊し方それぞれに対応する行が出る

## タスク分解（依存順）

| # | タスク | 状態 | モデル | 備考 |
|---|---|---|---|---|
| T01 | 骨格: doctor.sh、CLI サブコマンド、終了コード、ツール診断（B1-B2）、`tests/doctor.sh` の土台と検査登録 | done (87ae970) | opus | 構造を決めるので上位モデル |
| T02 | 導入状態: manifest（B3）、ファイル存在（B4）、改行と .gitattributes（B5） | done (d436aee) | sonnet | T01 依存 |
| T03 | git と AGENTS.md: hooks（B6）、マーカーと版（B7）、gitignore（B11） | done (609ae7c) | sonnet | T01 依存 |
| T04 | アダプタと版: Claude（B8）、Codex（B9）、新版（B10） | done (a976d85) | sonnet | T01 依存 |
| T05 | 文書と配線: スキルの表、README、DESIGN §8、init の案内、CHANGELOG | todo | sonnet | T02-T04 依存 |

T02〜T04 は互いに独立だが、同じ `doctor.sh` を編集するので直列に進める（並行させると衝突する）。

## 決定ログ（日付・決めたこと・理由・落選案）

- 2026-09-17: `--fix` 無し、テキスト出力のみ、未導入は exit 2、init/update から自動で回さない（ユーザーと確認。spec「決定済み」）。
- 2026-09-17: シナリオテストは `tests/doctor.sh` としてこのリポジトリ専用に置き、ペイロードには入れない。理由: 使い捨てプロジェクトを作って壊す検証はこのリポジトリの開発にしか要らない。
- 2026-09-17: 診断項目は 1 タスクに 3 項目ずつ。理由: 1 セッションで TDD（失敗シナリオ → 実装）を回して終わる粒度。

## 進捗ログ（セッションごとに 1〜3 行）

- 2026-09-17: 準備フェーズ。spec 合意、分解案作成。
- 2026-09-17: T01 done（Red→Green の 2 コミット、check 9 件 pass、再試行 0）。実装役の判断: 行形式は 1 行（spec どおり。gc の 2 行形式は範囲外で触らない）、B2 は有無のみで版の下限は見ない。
- 2026-09-17: T02 done（Red c504636 → Green d436aee、check 9 件 pass、doctor scenarios 9 件、再試行 0）。実装役の発見: Windows の grep で CR がマッチしない罠（`docs/learnings.md` に記録、[harness候補]）。
- 2026-09-17: T03 done（Red 2cd33d3 → Green 609ae7c、check 9 件 pass、doctor scenarios 14 件、再試行 0、実装役 約 12 分）。
- 2026-09-17: T04 done（Red 010ae34 → Green a976d85、check 9 件 pass、doctor scenarios 21 件、再試行 0、実装役 約 19 分）。実装役の判断: B8/B9 の個別ファイル欠落は B4 の汎用存在チェックに譲り、アダプタ診断は集計 OK 行だけ足す。T05 の文書は実装済み一覧（B1-B11）と一致させる。
- 2026-09-17: T05 done（851798f、1 コミット、check 9 件 pass、doctor scenarios 21 件、再試行 0、実装役 約 8 分）。全 5 タスク done、phase を review に。統括の観察: 実装役が check を裏プロセスで回して自分の完了待ちで停止し、統括が「前面で回して報告せよ」と 1 回催促した（実装役の指示に「検査は前面で回す」を足す候補）。

- 2026-09-17: 最終レビュー（§3）。4 観点を並列起動 → 3 体がセッションのレート上限で停止し、21:30 リセット後に中断地点から再開。重複排除の結果 high 4 / medium 6 / low 12。`doctor.sh` の行カウント破綻は**3 観点が独立に報告**（反証不要）。単独報告かつコスト高の 1 件（B10/B7 の直し方）だけ反証を回し、**「update が manifest の version を更新しない」は不成立**・欠陥は doctor の文言側のみ・コストは高→低 と判明（高コストの偽陽性を 1 件潰せた）。統括の観察: レビュアー 4 体を全部 opus で並列起動したことがレート上限の原因。**レビュアーと反証役は既定で下位モデルにすべき**（[harness候補]）。
- 2026-09-17: ユーザー決定 — manifest の `source` は共有値（既定は URL）に固定し、機械ローカルのパスは gitignore 対象の上書き（`.harness/source.local` / 環境変数 `HARNESS_SOURCE`）へ逃がす。解決順は 環境変数 > source.local > manifest.source。理由: `.harness/manifest.json` はコミット対象なのに絶対ローカルパスが入り、他の PC で update / diff / upstream が壊れる（`.harness/state/` を「個人ローカルの値を含むから」と ignore しているのと扱いが矛盾）。落選案: 現状維持 + doctor で WARN のみ / self_repo を優先する。→ T09 で実装し `docs/decisions/` に書き戻す。
- 2026-09-17: 修正タスク T06〜T10 を登録（T11 は T10 に統合。どちらも sonnet・設計判断なし・files_scope が重なるため）。
- 2026-09-17: T06 done（Red acb5efb → Green b65e4fb、check 9 件 pass、doctor scenarios 21→25 件、再試行 0、実装役 約 39 分）。**high の最悪 1 件（壊れた manifest で「異常なし / exit 0」を返す偽の全快）を解消。** 実装役の発見: `bin/harness:29` の `hash_of()` も同じフィルタ付き `git hash-object` を使っており、`status` の MODIFIED 判定・`update` の上書き判断・検査 installed copies in sync に波及する → **T12 として登録**。統括判断: CHANGELOG は `[Unreleased]` の doctor 項目に含まれるので別項目を立てない。

- 2026-09-17: T07 done（Red 8733a8e → Green 0a07688、check 9 件 pass、doctor scenarios 25→26 件、再試行 0、実装役 約 45 分・344 ツール往復）。導入先に存在しない `bash bin/harness` の案内を 8 箇所で `.harness/bin/harness` に統一し、「壊す→出る→直し方どおり実行→消える」の `apply_fix` 枠を 8 シナリオに適用。静的回帰チェック（正本を grep して `bash bin/harness` が二度と混入しない）も追加。
- 2026-09-17: **T07 が根本原因を特定** — 直し方が直らない件は個別の文言の問題ではなく、`bin/harness` の `apply_plan` が「既存の managed/merge ファイルが変更されていたら `.harness/conflicts/<path>.new` に退避するだけで実ファイルを直さない」という単一の挙動。実測で 5 箇所（B5 CRLF / B7 版ずれ / B7 マーカー重複 / B8 CLAUDE.md import 欠落 / B8 skill drift）。これは T12（`hash_of` のフィルタ問題）と同じコード経路なので **T08 を根本原因タスクに書き換えて T12 を吸収**し、doctor 側の文面は **T14** に分離した。
- 2026-09-17: 実行時間の実測 — `harness init` 1 回 = 11.25 秒（`sys 7.0s`＝Windows のプロセス生成）、シナリオ 25 件でスイート 4 分 41 秒。テストスイートの実行時間はほぼ丸ごと「init をシナリオごとに踏み直す時間」。→ **T13**（フィクスチャ共有・シナリオ絞り込み・確認項目の束ね）を差し込む。統括の観察: 往復削減（フィルタ・`--fast`）とフィクスチャ共有は同じ待ち時間を取り合うので、フィクスチャ共有が上位互換。
- 2026-09-17: **T13 ∥ T08 を worktree で並列実行**（`tests/doctor.sh` と `bin/harness` で重なりゼロ。T13 は `.harness/checks.sh` に触らない）。統括の観察: 並列化できたのは 1 ペアだけで、残りは `doctor.sh` / `tests/doctor.sh` / `bin/harness` に集中していて分離できない。モデル配分の実測 — T06(opus) 39 分・40 ツール往復・116k トークン、T07(sonnet) 45 分・344 ツール往復・462k トークン。**下位モデルはトークンを多く使い、壁時計時間も短くならない**（コストは下がるが速くはならない）。

- 2026-09-18: T08 done（Red 7ba8c24 → Green 7d522d5 → Refactor 89fc8c6、check 9→10 件 pass、tests/update.sh 13 シナリオ新設、再試行 0）。`update` が変更済みの managed/generated を正本の内容に復元するようにした（決定 0002）。同居していた欠陥 3 件を同時修正: `hash_of` のフィルタ付き `git hash-object`（`status` / `update` / 検査 "installed copies in sync" の 3 経路で CRLF を未変更と誤判定）、`block_hash` の先頭ブロック `exit`（マーカー重複を検出していなかった）、**`merge_agents_md` が end 無しの begin でファイル末尾を捨てる**（プロジェクトのルールが消えるデータ欠損）。
- 2026-09-18: T13 done（マージ cf3a657）。テストスイート 6m50.983s → 2m9.518s（3.2 倍、シナリオ 26 件・assert 97→99 で減らしていない）。**受け入れ条件の数値目標 20〜40 秒は未達**で、下限は `doctor` 呼び出し 1 回 ≒ 3 秒（`doctor.sh` 側の外部コマンド数）＝ `files_scope` 外のため done と判定し、技術負債 #6 に登録。統括の反省: 今夜の回収は約 10 分で**投資（約 60 分）を回収できていない**。テスト高速化は「次セッション以降に効く」投資であって当夜の ETA 短縮策ではない。
- 2026-09-18: T15 done（6ef538b）。文書 5 件を実装の実態に合わせた（spec の `*.cmd` 除外、SKILL.md の description、architecture の不変条件を「検出のみ」に、DESIGN §9 の所有権表を決定 0002 に、learnings に Windows の罠 2 件）。
- 2026-09-18: T14 done（マージ 05e99b3、決定 0003）。doctor の直し方を実測ベースで書き直し、B3 の復旧経路を**新しく決めた**（manifest の見出しが読めれば `update`、読めなければ `manifest.json.broken` へ退避して `init --source`）。**CLI 変更は不要**と実機で確認。B4/B5/B7 は `update` に一本化、B6 は `git rev-parse --is-inside-work-tree` で非 git を先に判定。tests/doctor.sh 26→27。**これで high 4 件すべて解消。**
- 2026-09-18: T14 の発見 — **worktree 内の `harness update` が main tree の未コミット `harness/` を取り込む**（manifest の `source` が main tree の絶対パスだから）。実際に編集中の SKILL.md を混入させかけて復旧した。ユーザーが最初に投げた「そもそも `source` はローカルパスでいいのか」という問いが、机上ではなく実害として出た形。T09 の受け入れ条件に追加。
- 2026-09-18: **セッションをここで畳む**（ユーザー合意）。high 4 件が解消し検査 10 件・シナリオ 40 件が緑になった時点を区切りとした。残る T09（`source` の設計変更）と T10（頑健性・検査の穴）は medium/low で、深夜に急ぐより判断の質が効くため次セッションへ。VERSION は 0.3.0 据え置き。

## 未確定事項（人間の判断待ち）

- なし（分解案は 2026-09-17 に合意）。
