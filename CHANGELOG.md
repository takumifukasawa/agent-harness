# Changelog

各版に「プロジェクト側で必要な作業」を必ず書く。`harness update` はこの節を表示する。
semver: managed ファイルの移動・マーカー形式変更は major、ルール/スキルの追加は minor、文言修正は patch。

## [0.6.0] - 2026-09-21

- 追加: `harness check` が**検査ごとの所要秒数**と**合計時間**、**遅い順の上位 5 件**を出すようにした。どの検査が重いかを推定でなく実測で掴むため（`$SECONDS` 組み込みを使うので外部プロセスは増えない。macOS の BSD `date` にミリ秒が無いため粒度は秒）。**プロジェクト側で必要な作業: 無し**（判定と終了コードは変わらない。出力に `(3s)` が付くだけ）。

macOS 既定の bash（3.2）で `harness init` / `update` / `check` / `gc` が動くようにし、pre-commit の門番（git hooks の実行ビット）が機能していないケースを検出できるようにした版。コードの互換性修正とバグ修正のみで、managed ファイルの移動もマーカー形式の変更も無い。

- 修正（決定 0006。T01）: macOS 既定の bash（3.2.57、Apple がアップデートしない見込み）で `harness init` / `update` / `check` が動くようにした。`bin/harness:355` の `declare -A`（連想配列）が bash 3.2 に無く、`harness init` が `declare: -A: invalid option` で即死していた（実測 pass=9 fail=4 のうち 3 件の根本原因）。連想配列は使わず、一時ファイル + `awk` で path ごとに旧 manifest の sha256 / source_sha256 を引く `old_manifest_field()` に置き換えた（挙動は変えていない）。`harness/scripts/doctor.sh` の `mapfile`（外部コマンド全滅時のフォールバック）も `while read` に置き換えた。`"$var日本語"`（変数展開の直後に非 ASCII が続く形）は bash 3.2 + UTF-8 ロケールで `unbound variable` になる罠で、`bin/harness`（6）・`harness/scripts/doctor.sh`（7）・`harness/scripts/gc.sh`（3）・`tests/doctor.sh`（5）・`tests/seed.sh`（2）・`tests/update.sh`（1）の 24 行を `${var}` に括り直した。`doctor` の B1 は「bash 4 未満なら FAIL」だったが、3.2 を切らない方針に合わせて「3.2 未満なら FAIL」に変え、案内文（`brew install bash` 一択だった）も実態に合わせた。
- 修正（T01）: `bin/harness` の `apply_plan` が、`.harness/manifest.json` の `files` が壊れて 0 行になっている状態（B3 が想定する故障）で `set -e` の下、無言で異常終了することがあった。旧コードは `manifest_entries` を `< <(...)`（process substitution）越しに読んでいたため exit 1 の影響を受けなかったが、bash 3.2 対応で直接読む形に変えた際に同じ耐性が失われていた。`manifest_entries >file || true` にして元の耐性へ戻した。
- 修正（T01。macOS 実機で新規発覚）: `tests/doctor.sh` の C3（node/jq が無くても他の診断が動くことの検証）が、macOS 15+ のように `jq` が `/usr/bin` に `git`/`sed`/`tr` 等と同居する環境で、node/jq のディレクトリごと PATH から外すとそれらまで道連れに消えて誤検知していた。ディレクトリ単位ではなく実行ファイル単位でスタブ化する方式に直した。
- 修正（T01。macOS 実機で新規発覚。決定 0006 が「踏んだら直す」としていたブロッカーの 1 つ）: `tests/doctor.sh` / `tests/update.sh` の `sed -i 'expr' file`（GNU sed 構文）が、`-i` の直後に空でもバックアップ拡張子の引数を要求する BSD/macOS の `sed` では引数解釈がずれ、`invalid command code` で壊れていた。両方の `sed` で同じ結果になる tmp+mv の `sed_i()` ヘルパー（各ファイルに 1 つ）に統一した（6 箇所）。
- 追加（決定 0006。T01）: このリポジトリ自身の検査に、bash 3.2 互換を機械で強制する禁止検査 2 件を追加（`tests/lint-bash-compat.sh` が `bin/harness` / `harness/scripts/*.sh` / `tests/*.sh` を走査）。(a) bash 4+ 専用構文（`declare -A` / `local -A` / `declare -n` / `local -n` / `mapfile` / `readarray`）、(b) 変数展開の直後に非 ASCII が来る形（`"$var日本語"`）。どちらも fast（pre-commit でも走る）で、失敗時に直し方を出力する。
- プロジェクト側で必要な作業: `harness update` で `.harness/bin/harness` と `.harness/scripts/doctor.sh` / `gc.sh`（配布ペイロード）が更新され、他プロジェクトも macOS 既定の bash（3.2）でこれらが動くようになる。**禁止検査 2 件と `tests/lint-bash-compat.sh` はこのリポジトリ専用**（`tests/` は配布ペイロードに含まれないので `harness init` / `update` では入らない）。自分のプロジェクトが bash スクリプトを配り bash 3.2 も支えたいなら、同種の走査を自分の `.harness/checks.sh` に書く（`docs/decisions/0006-support-bash-3-2.md` に判断の経緯と直し方の一覧がある）。
- 追加（決定 0005）: `harness init` が配る `.harness/checks.sh`（seed）に `doctor: FAIL 0` を最初から入れる。seed の検査が実質 1 件（docs の索引の存在確認）しか無く、**プロジェクトが自分で書くまで `harness check` がほぼ無条件に pass する**＝統括の完了判定の 1 本が最初から機能しない状態だった（`task-orchestrate` §1.7 が自分で警告している）。`doctor` はプロジェクトのコードではなくハーネスの導入状態を見るので言語やスタックに依存せず、init 直後は必ず FAIL 0 で通る（`tests/doctor.sh` の D1 が保証）。実測 4.7 秒で、`fast` は付けないので pre-commit は従来どおり。
- プロジェクト側で必要な作業: **既存のプロジェクトには自動では入らない**（`.harness/checks.sh` は seed なので `harness update` は触らない。触るとプロジェクトが書いた検査が消えるため）。取り込むなら次の 1 行を自分の `.harness/checks.sh` に足す: `check      "doctor: FAIL 0"    "bash .harness/bin/harness doctor || { echo 'doctor が FAIL を報告した。上の FAIL 行の「→」に従って直す。'; exit 1; }"`
- 修正（T02）: `harness doctor` の B6（git hooks）が、フックの**存在（`-f`）しか見ておらず、実行できない状態でも `OK` を出していた**。git は実行ビットの無いフックを黙って無視する（`hint: ... was ignored because it's not set as executable` が 1 行出るだけで commit は成功する）ため、「pre-commit で速い検査が回っている」つもりのまま一度も回っていない状態に緑が出ていた。これはハーネスの根幹（「`harness check` が完了の客観条件」）の入口が黙って無効化される穴なので、次の 2 つを見るようにした: (a) **git index の mode**（`100755` か。clone した先に配られる値なので OS を問わず意味がある）、(b) **作業ツリーの `-x`**。ただし (b) は `core.filemode=false` のとき（**Windows の Git の既定**）は見ない。そこで見ると Windows で全員に偽の警告が出て、本物の警告が読み飛ばされるため。直し方は追跡状態で出し分ける（未追跡なら `chmod +x` だけ。`git update-index` は未追跡ファイルには使えない）。**重大度は当初 WARN に据え置いたが、下の T04 で FAIL に上げた。**
- 変更（決定 0007。T04）: 上の B6 の重大度を **WARN から FAIL** に上げた。実行できない状態は劣化ではなく**検査の門番が不在**という状態であり、WARN のままでは `doctor` の総括行に `WARN=1` が出るだけで `harness check` は緑のままになる（このリポジトリ自身が数セッション見逃したのと同じ見落とし方を、既存プロジェクトでも許すことになる）。「`core.hooksPath` が未設定、または `.githooks/pre-commit` 自体が無い」ケースは対象外で、従来どおり WARN のまま（判定条件・直し方は T02 のまま変えていない）。配布 seed（`harness/checks.seed.sh`）には実行ビット専用の検査を**足していない**。決定 0005 で seed に既に入っている `doctor: FAIL 0` が、この FAIL を自動的に拾うため（検査を二重に持たない）。判断の経緯は `docs/decisions/0007-hook-not-executable-is-fail.md`。
- 修正（T02。macOS 実機で実証。tech-debt #8）: `harness gc` の日付判定が `date -d`（GNU 専用）だけを試し、失敗を握り潰していたため、**macOS では日付に依存する判定（handoff の鮮度・`plans/active/` の放置日数・state の放置・references の古さ）が全部無言でスキップされ、`gc` が「問題なし」と報告していた**。エラーも警告も出ないので、gc が仕事の半分をしていないことに気づけない出方だった。GNU（`date -d`）と BSD/macOS（`date -j -f`）の両方言に対応し、**それでも読めなかった日付は必ず WARN で報告する**（黙って飛ばすのをやめる）。あわせて `最終更新:` 行は行頭の `YYYY-MM-DD` だけを日付として読む（`最終更新: 2026-09-20（題材 …）` のように後ろへ一言添える書き方が実際にあり、行の残り全部を日付扱いすると新しい WARN が偽陽性になるため）。
- 修正（T02。macOS 実機で新規発覚）: `curl -fsSL <公開 URL>/bin/harness | bash -s -- init`（README が案内する導入経路）で、**標準入力から実行すると `${BASH_SOURCE[0]}` が設定されず** `set -u` のもとで `BASH_SOURCE[0]: unbound variable` を出していた。`self_repo()` では command substitution の subshell が死ぬだけなので**エラーを出しながら処理は続く**という分かりにくい出方をし、`harness self-install` に至っては「標準入力からは self-install できない」と案内する `die` に**到達する前に**落ちていた（案内が一度も読まれない）。5 箇所の参照を `${BASH_SOURCE[0]:-}` にし、標準入力からの `help` は短縮版の usage を出す。
- 追加（T02）: このリポジトリ自身の検査 3 件（`tests/githooks.sh` / `tests/gc.sh` / `tests/stdin.sh`）と `tests/doctor.sh` の B6 シナリオ 3 件、`tests/update.sh` の U13。**`harness gc` にはこれまで実行経路の検査が 1 つも無く**（`harness check` の経路にも `tests/` にも無い）、壊れていても誰も気づかなかった（tech-debt #8 の本体はこの穴）。`tests/gc.sh` がその経路になる。B6 の 3 シナリオは「作業ツリーの実行ビット欠落」「index mode が 100644」「`core.filemode=false` では警告を出さない（Windows の偽警告の回帰）」。
- プロジェクト側で必要な作業: `harness update` で `.harness/bin/harness` と `.harness/scripts/doctor.sh` / `gc.sh` が更新される。**そのうえで自分のリポジトリの `.githooks/pre-commit` が git index で `100755` になっているか確認すること。** `git ls-files -s .githooks/pre-commit` が `100644` なら、そのリポジトリでは pre-commit が（clone した全員のところで）一度も走っていない。直し方は `chmod +x .githooks/pre-commit && git update-index --chmod=+x .githooks/pre-commit` でコミットする。`harness init` / `update` は作業ツリーに `chmod +x` するが、**index の mode は git add 時の `core.filemode` 次第**なので、Windows（既定 `false`）でコミットされたリポジトリは `100644` のまま配られている。更新後の `harness doctor` はこれを **FAIL** で指摘する（決定 0007。T04。当初は WARN の予定だったが本リリースまでに FAIL へ上げた）。**`doctor: FAIL 0` を検査に組み込んでいるプロジェクトでは、この 1 点だけで `harness check` が一度赤くなる。** これは意図した動作（もともと機能していなかった検査の門番を可視化する）で、赤は「壊した」ではなく「もともと壊れていたものを可視化した」。上の直し方でコミットすればすぐ直る。
- 修正（最終レビュー指摘。T05）: `harness doctor` の B6 が、`core.hooksPath` は正しく `.githooks` を指しているのに `.githooks/pre-commit` 自体が無い状態で、「hooksPath が `.githooks` になっていない」という事実と矛盾した前置きと、no-op になる `git config core.hooksPath .githooks`（現在値はもう正しいので実行しても何も変わらない）を直し方として出していた（実機で再現）。hooksPath 未設定のケースと pre-commit 欠落のケースを別の分岐に分け、後者は B4 と同じ「`harness update` で復元する」を出す。他の B6 分岐（未設定 / `.git` 無し / 実行不可 / index mode 100644 / `core.filemode=false`）の判定・文言は変えていない。
- 修正（最終レビュー指摘。T05。このリポジトリ専用）: `tests/doctor.sh` の C3（node/jq が無くても他の診断が動くことの検証）のスタブ化が、`ln -s` の失敗を `2>/dev/null` で握り潰すだけでフォールバックが無かった。Windows の Git Bash（MSYS2）は非特権ユーザー・Developer Mode 無効では symlink 作成に失敗するため、T01 が macOS の PATH 丸ごと除外方式で踏んだのと同型の「node/jq と無関係な理由で診断が総崩れ」が今度は Windows で再発しうる状態だった。`ln -s` が失敗したら `cp` にフォールバックし、1 ファイル単位の失敗（実測: 読み取り制限つき setuid バイナリで cp が Permission denied になるケースがある）では全体を失敗にせず、1 件も stub 化できなかったときだけ失敗を返すようにした。
- 修正（最終レビュー指摘。T05。このリポジトリ専用）: `tests/lint-bash-compat.sh`（bash 3.2 互換の禁止検査）が `harness/checks.seed.sh`（`harness init` が各プロジェクトの `.harness/checks.sh` として配る配布ペイロード）を走査対象から漏らしていた。manifest 上 `ownership: seed` でドリフト検知の対象外でもあり、他のどの検査にも拾われていなかった（`declare -A` を仕込んでも rc=0 のまま通ることを実機で確認）。走査対象に追加した。

## [0.5.0] - 2026-09-18

`harness doctor` を題材にした dogfood で見つかった、**統括の手順の穴 3 件**を `task-orchestrate` と `reviewer` の役割文へ昇格させた版。コードの変更は無い。

- 変更（スキル）: `task-orchestrate` §2.1 の実装役への指示テンプレに 2 行追加。**検査は前面（フォアグラウンド）で回す**（裏プロセスで走らせて自分の完了待ちにすると止まる実例があった）。**利用者に影響する変更を入れたら `CHANGELOG.md` の `[Unreleased]` に書く**（これが無かったため、あるタスクの変更が版を切る段で取りこぼされかけた）。
- 変更（スキル）: `task-orchestrate` §3.2。統括がレビュアーから受け取る要約に **修正コスト（高 / 低）** を必ず含める。§3.4 の反証の条件（「報告者が 1 体だけ」かつ「修正コストが高い」）は、統括が report 本文を開かない規律と組み合わせると、要約に修正コストが無いと判定できなかった。
- 変更（スキル / 役割文）: レビュアーと反証役の**モデルは既定で下位**（統括だけ上位を保つ）。根拠を「コードの該当行かテストの出力」に縛ってあるので下位で足りる。上位モデルを観点ぶん並列に起動するとセッションのレート上限に当たり、実測で 4 体中 3 体が起動直後に停止して報告が 1 件も残らなかった。止まったレビュアーは破棄せず、上限のリセット後に「中断地点から再開」を送れば文脈を保ったまま続けられる、という復旧手順も書いた。
- プロジェクト側で必要な作業: `harness update` で `task-orchestrate` スキルが更新される。`docs/roles/reviewer.md` は seed（プロジェクトの資産）なので **`update` では更新されない**。自分で直すなら `harness diff` で新版との差を見て取り込む（報告の形式に「要約には修正コストを入れる」、冒頭に「モデルは既定で下位」の 2 点）。Claude の `.claude/agents/reviewer.md` は `docs/roles/reviewer.md` から生成されるので、そちらを直してから `update` する。

## [0.4.0] - 2026-09-18

`harness doctor` の追加と、`update` の復元・`source` の機械ローカル化を仕上げた版。

- 追加: `harness doctor`（`scripts/doctor.sh`）。環境とハーネス導入状態を機械的に診断する（bash/git/node/jq、manifest、改行、git hooks、AGENTS.md マーカー、Claude/Codex アダプタ、source の新版、`.gitignore`）。LLM は使わず報告のみ、自動修復はしない。終了コードは 0=問題なし/WARN のみ、1=FAIL あり、2=未導入。`harness init` の最後の案内にも `harness doctor` を促す 1 行を追加。
- 変更（挙動。決定 0002）: `harness update` が、変更済みの managed / generated を `.harness/conflicts/` へ退避するだけで放置せず、**正本の内容に復元する**（変更前は `.harness/backup/<ts>/` へ退避し、`restore <path>` と退避先を出力。集計に `restored=N` を追加）。`AGENTS.md` は managed ブロックだけを現行版に戻し、ブロック外のプロジェクトの記述は触らない。重複した managed ブロックは 1 対に畳む。`CLAUDE.md` は import スタブ扱いで、`@AGENTS.md` の行だけを保証して中身は残す。`seed` と「manifest に無いのに存在するファイル」の扱いは従来どおり（触らない / conflicts）。
- 修正: 内容の比較をフィルタ無し（生バイト）の `git hash-object --no-filters` に統一。素の `git hash-object` は `.gitattributes` の `text eol=lf` と `core.autocrlf` を通すため、CRLF 化しただけの導入コピーを「未変更」と誤判定していた（`harness status` の MODIFIED 判定、`update` の上書き判断、検査 "installed copies in sync" が揃って騙されていた）。
- 修正: `AGENTS.md` の `end` マーカーが失われていると、`update` が begin から末尾までを managed ブロックと見なしてプロジェクトの記述ごと消していた。今は begin の 1 行だけを落とし、残骸はファイルに残して案内する。
- 追加: `tests/update.sh`（このリポジトリ専用の検査 "update scenarios"、12 シナリオ）。所有権の規則の回帰を押さえる。
- 変更（挙動。決定 0004）: `.harness/manifest.json` の `source` は共有値（既定は公開リポジトリの URL）に固定し、機械依存の絶対パスは書かない。その PC / その worktree だけの source は `.harness/source.local`（gitignore 対象）か環境変数 `HARNESS_SOURCE` に置く。解決順は 環境変数 `HARNESS_SOURCE` > `.harness/source.local` > `manifest.json` の `source`。旧形式（`source` に絶対パス）で導入されたプロジェクトは、`harness update` が自動でその値を `.harness/source.local` へ移し、manifest を共有値に直す。`harness doctor` の B10 は解決結果を診断し、source が辿れなければ WARN、manifest に絶対パスが残っていれば別途 WARN。
- 修正: `harness doctor` の頑健性 4 件。B8 は `.claude/agents/*.md` の欠落時に B8 自身の行として FAIL を報告する（従来は B4 の汎用行に譲っていて、B8 を見ても項目が消えて見えた。B9 と同じ形に揃えた）。B10 は source の `VERSION` を使う前に書式検証（版番号らしい形式か）と長さ制限をし、版番号の形式でなければ WARN に倒して無関係な内容や長文を出力に丸ごと出さない。ヘッダ契約に `INFO` を明記し、集計行に `INFO=N` を出す（判定には影響しない参考情報）。doctor はオプションを取らないため、未知の引数（`--fix` / `--json` 等）を黙って無視せず usage を出して環境不備と同じ非 0 で終わる。
- 追加: このリポジトリ自身の検査 2 件。`.harness/checks.sh` に "doctor: FAIL 0"（このリポジトリの `harness doctor` が FAIL 0 で通ることを検査する。従来は使い捨てプロジェクトへの init 直後だけを見る "doctor scenarios" しか無く、自分自身の導入状態は誰も検査していなかった）と、fast 検査 "manifest source is shared value"（決定 0004 の回帰防止。manifest の `source` が機械依存の絶対パスへ戻ったら pre-commit（`harness check --fast`）で止める）を追加。
- プロジェクト側で必要な作業: `harness update` で `doctor.sh` が入る。**次回の `update` は、これまで「未変更」と誤判定されていた CRLF のファイルと、手で直した managed / generated を正本の内容に戻す**（変更前は `.harness/backup/<ts>/` に残る）。残したいローカルの変更があるなら、先に `harness diff` で確認し `harness upstream <path>` で正本へ戻してから `update` する。manifest の `sha256` は自動で書き直されるので手作業は不要。ローカル clone を `source` にしていたプロジェクトは、次回の `update` が自動でその絶対パスを `.harness/source.local` に逃がすので追加の作業は無い。ただし別 PC や worktree などその絶対パスが存在しない環境で `update` するときは、先に `.harness/source.local` に自分の clone の絶対パスを書くか、`HARNESS_SOURCE=<clone した絶対パス>`（worktree で作業するときは `HARNESS_SOURCE=$(pwd)`）を付けて実行する。

## [0.3.0] - 2026-09-17

配管の残りを埋め、このリポジトリ自身に導入した版。

- 追加: `harness gc`（`scripts/gc.sh`）。handoff の鮮度、索引にあるが無い doc / あるが索引に無い doc、docs 内のリンク切れ、放置された `plans/active` と `.harness/state`、未着手の負債、管理ファイルの drift、古い references を一覧にする。`--strict` で CI 用に exit 1。判断と修正はしない。
- 追加: `.claude/settings.json` の自動マージ（node があるとき）。断片の `permissions.deny` と、command に `.harness/` を含む hooks だけを差し込み、プロジェクトの項目は保持。上書き前にバックアップ。無いときは手順を案内。
- 追加: このリポジトリ自身に `harness init` で導入（dogfood）。`.harness/checks.sh` に 8 件の検査（構文、JSON、スキル名、AGENTS.core.md の行数、VERSION と CHANGELOG の整合、導入コピーとペイロードの同期、init のスモークテスト）。`docs/` に architecture / learnings / tech-debt / decisions 0001 / handoff を記入。
- 変更: origin を HTTPS に切替（この PC の運用）。
- プロジェクト側で必要な作業: `harness update` で `gc.sh` が入り、Claude を使うプロジェクトでは `.claude/settings.json` に deny と SessionStart hook が差し込まれる（バックアップは `.harness/backup/`）。不要なら該当項目を削除してよいが、次の update で再度差し込まれる。

## [0.2.0] - 2026-09-17

ワークフローを実際に回せるようにした版。

- 追加: `task-orchestrate` スキル。準備 → 反復（1 セッション = 1 タスク）→ 最終レビュー を `.harness/state/` の JSON で管理する統括の手順。実装役への指示テンプレート、再試行（新しい 1 体に失敗出力を渡す、3 回で人へ）、レビューの重複排除と反証の 3 縛りを含む。
- 追加: Codex 用の役割スキル生成。`docs/roles/{implementer,reviewer}.md` から `.agents/skills/role-<name>/SKILL.md` を生成（generated。生成元が変われば再生成）。
- 変更: `AGENTS.core.md` と `docs/roles/README.md` が `task-orchestrate` を指すように。orchestrator の準備フェーズに「state を雛形からコピー」を明記。
- プロジェクト側で必要な作業: `harness update` で `task-orchestrate` と `role-*` スキルが入る。追加の手作業なし。

## [0.1.0] - 2026-09-17

CLI 実装版。`bin/harness`（bash。依存は git と bash だけ）。

- 追加: `harness init | update | status | diff | upstream | check | version`。所有権 managed / seed / merge / generated を manifest（1 エントリ 1 行の JSON、`src` で逆マッピング）で追跡。
- 追加: CLI 自身を `.harness/bin/harness` としてプロジェクトに同梱。clone した別 PC では `bash .harness/bin/harness update` がそのまま動く。source は ローカルパス か git URL（`~/.cache/agent-harness/` に clone）。
- 追加: init が `.gitignore`（state / backup / conflicts）と `.gitattributes`（`.harness/**` 等を LF 固定。Windows の autocrlf 対策）を書く。サブディレクトリ `AGENTS.md` の隣に `CLAUDE.md` アダプタを自動生成。`docs/roles/{implementer,reviewer}.md` から `.claude/agents/*.md` を生成。`core.hooksPath=.githooks` と pre-commit（`check --fast`）を設定。
- 決定: マーケットプレイス配布は採用しない（Claude 専用でリポジトリに入らないため）。DESIGN.md §10 #8。
- 追加: `harness self-install`（`harness` を PATH に置く。Windows は `harness.cmd` シムも置き、PowerShell / cmd から使える）。PATH 上の `harness` はプロジェクト内では同梱コピーへ委譲する。プロジェクトにも `.harness/bin/harness.cmd` を同梱。
- 追加: `harness` スキル（`/harness status` のようにセッション内から CLI を実行し、結果を解釈して次の行動を案内する）。
- 変更: `AGENTS.md` のマーカー版は CLI が VERSION から埋める（`AGENTS.core.md` の `v=` を手で合わせる必要が無くなった）。
- 設計: DESIGN.md を 2 部構成に書き直し。第 I 部「ワークフロー」（主役。SmartHR 型の遂行手順）、第 II 部「配管」（配布・更新、最小限）。DeNA 型のログ・メモリ採掘は非ゴールに。次の一手は `task-orchestrate` スキルと Codex 用役割スキルの生成（§11）。
- 修正（検算で発見）: 相対パスの `--source` を絶対パスにして保存（別ディレクトリからの update が壊れていた）。同梱 CLI 自身を update で上書きすると実行中の bash が壊れた内容を読む問題を、一時コピーからの再実行で回避。Windows で `C:/`・`/c/`・`/tmp` のパス形式が混在して同一ファイル判定（文字列比較・`-ef`）が失敗していたため、内容ハッシュでの判定に変更し、`git rev-parse` の結果を `cygpath -u` で正規化。
- 未実装: `harness gc`、`.claude/settings.json` の自動マージ（断片を `.harness/adapters/claude.settings.fragment.json` に置き、手で反映）。
- プロジェクト側で必要な作業: なし（初回配布）。

## [0.0.1] - 2026-09-17

設計版。CLI は未実装。

- 追加: `DESIGN.md`（設計）、`harness/AGENTS.core.md`、`harness/docs-template/`（索引・handoff・architecture・plans・decisions・learnings・tech-debt・references・rules）、スキル 3 本（session-catchup / session-handoff / harness-maintain）、`harness/scripts/check.sh` と `checks.seed.sh`、アダプタ README（claude / codex）、`manifest.example.json`。
- 追加（同日、対話で決定）: SmartHR 型ワークフローの取り込み。`docs-template/roles/`（orchestrator / implementer / reviewer）、`docs-template/spec/`、`state-template/`（progress.json / stages.json）。未決事項 7 件を決定ログに変換（DESIGN.md §10）。
- 追加（同日、検算で修正）: `harness/scripts/session-start.sh`（Claude の SessionStart hook から呼ぶ補助）。所有権に `generated`（seed から生成されるアダプタ出力。生成元のハッシュも追跡）を追加。Codex のサブディレクトリ AGENTS.md は cwd 基準で読まれる事実を反映（DESIGN.md §2 の正本の形式表、rules 雛形、Codex アダプタ README）。SmartHR 原文との突合で `roles/`・`state-template/`・`checks.seed.sh` を修正（反証の 3 条件、戻り値の絞り込み、検査は回避手段も塞ぐ）。再試行は「新しい 1 体に失敗出力を渡す。統括のセッションは切らない」で統一。
- プロジェクト側で必要な作業: なし（まだ配布していない）。
