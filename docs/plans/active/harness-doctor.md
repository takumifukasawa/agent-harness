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

## 未確定事項（人間の判断待ち）

- なし（分解案は 2026-09-17 に合意）。
