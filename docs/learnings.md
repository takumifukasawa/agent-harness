# learnings — 踏んだ罠と対処

<!-- 書くのは「コードや git log から導出できないこと」だけ。
     形式は「症状 → 原因 → 対処（再発したらまず X を見る）」。日付は絶対日付。
     プロジェクト非依存のものには [harness候補] を付ける。 -->

## 2026-09-17 update が同梱 CLI 自身を上書きすると bash が構文エラーで落ちる
- 症状: `bash .harness/bin/harness update` の処理は完了するのに、直後に `syntax error near unexpected token` で exit 2。
- 原因: bash は実行中のスクリプトを逐次読むので、`cp` で同じ inode を書き換えると残りを新内容で読む。
- 対処 / 再発したら: `reexec_if_vendored` が一時コピーから `exec` し直しているか、`HARNESS_REEXEC` が渡っているかを見る。

## 2026-09-17 Windows で「同じファイルか」の判定が全部すり抜ける [harness候補]
- 症状: 上の再実行ガードを入れても効かない。PATH の `harness` からの委譲も抑止されない。
- 原因: `git rev-parse --show-toplevel` は `C:/...`、`realpath` は `/tmp/...` や `/c/...` を返し、文字列比較は一致しない。`[ a -ef b ]` も `C:/` 形式で偽を返した。
- 対処 / 再発したら: パスで判定せず `same_script`（内容ハッシュ）で判定する。`project_root` は `cygpath -u` で正規化する。Windows で「一致するはずなのに一致しない」ときは、まずパス形式の混在を疑う。

## 2026-09-17 相対パスの --source は別ディレクトリからの update で壊れる
- 症状: サブディレクトリから `update` すると `clone に失敗: ../up stream`。
- 原因: manifest に相対パスのまま保存していた。
- 対処 / 再発したら: `cmd_init` で `[ -d "$source" ] && source="$(cd "$source" && pwd)"`。

## 2026-09-17 Windows の autocrlf で managed ファイルが全部 MODIFIED になる [harness候補]
- 症状: 別 PC で clone すると `harness status` が全件 MODIFIED、bash スクリプトも動かない。
- 原因: checkout 時に CRLF へ変換され、ハッシュも実行も壊れる。
- 対処 / 再発したら: init が `.gitattributes` に `.harness/** text eol=lf` 等を書く。ハッシュ比較の対象（managed / generated とその生成元）はすべて LF 固定にする。`*.cmd` だけ CRLF。

## 2026-09-17 Codex のサブディレクトリ AGENTS.md は cwd 基準 [harness候補]
- 症状: パス限定の規律を置いても Codex で効かない。
- 原因: Codex はルートから cwd までの連鎖しか読まない（公式 docs）。Claude Code はファイル基準で読む。
- 対処 / 再発したら: 統括が規律ファイルの全文を実装役に貼る（`task-orchestrate` §2.1）。確実に効かせたい規律は検査に落とす。

## 2026-09-17 heredoc がツール経由の bash で失敗する
- 症状: `cat > file <<'EOF'` を含む長いコマンドが `unexpected EOF while looking for matching quote` で落ちる。
- 原因: ツールのコマンド受け渡しで引用が崩れる（詳細は未特定）。
- 対処 / 再発したら: 長いファイルは Write ツールで書く。bash の heredoc は短いものに限る。

## 2026-09-17 Git for Windows の grep で CR（`\r`）がマッチしない [harness候補]
- 症状: ファイルに CR バイトが実在する（`od -c` / `cat -A` で見える）のに、`grep -q $'\r' file` や CR だけのパターンファイルを使った `grep -f` が一貫して不一致になる。
- 原因: 未特定（Git for Windows 同梱 grep 3.0 で再現。`harness doctor` の B5 実装時に遭遇）。2026-09-18 に原因判明、下の学びを参照。
- 対処 / 再発したら: grep で CR を探さない。`tr -d '\r'` の前後でバイト数（`wc -c`）を比べて CR の有無を判定する（`harness/scripts/doctor.sh` の B5 がその形）。

## 2026-09-18 Git Bash の grep はテキストモードで CR を落とすため CRLF 検出に使えない [harness候補]
- 症状: 上の 2026-09-17 の学びの原因調査。CRLF 化されたファイル（`cmp` や `od -c` では CR が見える）に対し、どんな書き方で `grep` に CR（`\r`）を探させても一致しない。
- 原因: Git Bash（MSYS2）同梱の grep はテキストモードでファイル・パイプを読み、CR を改行の一部として落としてから照合する。渡す前のバイト列に CR が実在しても grep 自身が消費前に捨てるので、パターンの書き方では回避できない。
- 対処 / 再発したら: CRLF・CR の有無を判定するのに grep を使わない。`cmp -s a b` で2ファイルの一致を見るか、`od -c file` の出力（`\r` が文字列として現れる）を見る。バイト数比較でもよい（`tr -d '\r' < f | wc -c` と `wc -c < f` の差）。

## 2026-09-18 `git hash-object` はリポジトリの外・素で呼んでも core.autocrlf を適用する [harness候補]
- 症状: `--no-filters` を付けずに `git hash-object` で 2 ファイルの内容一致を判定すると、CRLF 化されただけの LF 管理ファイルが「一致（未変更）」と誤判定される。`status` の MODIFIED 判定・`update` の上書き/復元判断・検査 "installed copies in sync" の 3 経路が同時にこれで壊れていた（`docs/decisions/0002-update-repairs-managed-files.md`）。
- 原因: 素の `git hash-object` は `.gitattributes` の `text eol=lf` と環境の `core.autocrlf` によるフィルタを通してから hash を取る。CRLF 化されたファイルもフィルタで LF に正規化されてから hash されるため、ハッシュだけ比べると「同じ」に見える。
- 対処 / 再発したら: 2 つのファイルの内容が同じかを判定する処理はすべて `git hash-object --no-filters` を使う（素の `git hash-object` を使っている箇所が無いか grep する）。`harness/scripts/doctor.sh` の `content_eq` と `bin/harness` の `hash_of()` がその形。

## 2026-09-18 worktree 内の `harness update` が main tree の未コミット変更を取り込む [harness候補]
- 症状: 複数の実装役を git worktree で並列に動かし、各自が `harness/` を直して `bash bin/harness update` で同期する運用にしたところ、worktree 側の update が **main tree で別の実装役が編集中だった未コミットの `harness/skills/harness/SKILL.md`** を `.agents/skills/` 等に取り込みかけた。
- 原因: `.harness/manifest.json` の `source` に **main tree の絶対パス**が入っており、`cmd_update` はそれしか見ない（`--source` 上書きが無い）。worktree はコミット済みの manifest をそのまま持つので、自分ではなく main tree を指す。
- 対処 / 再発したら: **worktree の中で update / diff / upstream を回すときは `HARNESS_SOURCE=$(pwd)` を付ける**（`HARNESS_SOURCE=$(pwd) bash bin/harness update`）。manifest を書き換えて戻す手順は要らない。T09（決定 0004）で解決順が 環境変数 `HARNESS_SOURCE` > `.harness/source.local` > `manifest.source` になり、manifest には機械依存の絶対パスを書かなくなった。どこを見ているかは `bash .harness/bin/harness status` の見出し行（`source=... [由来]`）で確認できる。`harness doctor` の B10 も辿れなければ WARN を出す。

## 2026-09-18 worktree は古い分岐点で払い出されることがある [harness候補]
- 症状: サブエージェント用に払い出した worktree が、main の最新ではなく**かなり古いコミット**（このときは 14 コミット前）で止まっていた。spec も実装も無い状態で作業を始めかけた。
- 原因: worktree の作成元が最新の main とは限らない。払い出し側（エージェント基盤）の都合で決まる。
- 対処 / 再発したら: **worktree で着手する前にまず `git merge-base --is-ancestor <branch> main` を見る**（`main` がこの worktree の祖先か = 追いついているか）。追いついていなければ、独自コミットが無いうちに `git merge --ff-only main` で追いつく。spec や前提のタスクの成果物が「無い」ように見えたら、ファイルを探す前にこれを疑う。統括は払い出し直後に一度確認する。

## 2026-09-18 レビュアーを全部上位モデルで並列起動するとセッションのレート上限に当たる [harness候補]
- 症状: `task-orchestrate` §3 の最終レビューで観点別レビュアー 4 体を全部 opus で同時起動したところ、3 体が起動直後に 429（session limit）で停止。レポートは 1 件も書かれなかった。
- 原因: 1 体あたり 10〜18 万トークン読む役を 4 体同時に走らせると、5 時間枠の残量を一度に食い潰す。
- 対処 / 再発したら: **レビュアーと反証役は既定で下位モデル**にする（根拠を「コードの該当行かテストの出力」に縛ってあるので足りる）。統括だけ上位を保つ。停止した体は破棄せず、上限リセット後に同じエージェントへ「中断地点から再開」を送れば文脈を保ったまま続きから書かせられる。
- → **harness v0.5.0 へ昇格**（`harness/skills/task-orchestrate/SKILL.md` §3.2 と `harness/docs-template/roles/reviewer.md`）。

## 2026-09-18 下位モデルに落としても壁時計時間は短くならない [harness候補]
- 症状: コスト削減のため実装役を opus → sonnet に下げたが、所要時間が縮まらなかった。
- 原因: 実測 — T06(opus) 39 分 / 40 ツール往復 / 116k トークン、T07(sonnet) 45 分 / **344 ツール往復** / **462k トークン**。下位モデルは試行回数で補うのでツール往復が桁で増える。単価差でコストは下がるが、往復ぶん時間は延びる。
- 対処 / 再発したら: モデルを下げるのは**コスト**のため。ETA を縮めたいならモデルではなく、検査の実行時間・タスクの並列化・スコープで削る。

## 2026-09-18 実装役は CHANGELOG に書かないので版切りで取りこぼす [harness候補]
- 症状: 版を切る段になって、利用者に影響する変更（`doctor` の頑健性修正、検査 2 件の追加）が `CHANGELOG.md` の `[Unreleased]` にまったく無いことが発覚した。版切り担当は「`[Unreleased]` を版見出しへ移す」指示しか持っていないので、**空のまま移してしまう**。
- 原因: 実装役への指示テンプレ（`task-orchestrate` §2.1）に CHANGELOG が入っていない。受け入れ条件に明示したタスク（T05・T08）は書いたが、明示しなかったタスク（T10）は書かなかった。**指示に無いことはやらない**のが実装役の正しい振る舞いなので、これは実装役の落ち度ではなく手順の穴。
- 対処 / 再発したら: 版が合わない・移行手順が足りないと気づいたら、まず **`git log <前の版>..HEAD` と `CHANGELOG` の差**を突き合わせる。恒久対策は §2.1 の指示テンプレに「利用者に影響する変更なら `CHANGELOG.md` の `[Unreleased]` に書く（挙動変更とプロジェクト側で必要な作業）」を足すこと。
- → **harness v0.5.0 へ昇格**（`harness/skills/task-orchestrate/SKILL.md` §2.1 の指示テンプレ）。

## 2026-09-18 統括はレビューの「単独報告かつ修正コスト高」を自分で見積もる必要がある [harness候補]
- 症状: `task-orchestrate` §3.4 は「報告者が 1 体だけ **かつ** 修正コストが高い指摘だけ反証に回す」と決めているが、**統括はレビュー本文を開かない**規律なので、要約に修正コストが書かれていないと判定できない。
- 原因: レビュアーへの指示で「報告 1 件ごとに修正コスト（高/低）」を report 本文に書かせていたが、**統括が受け取る要約の項目に入れていなかった**。
- 対処 / 再発したら: レビュアーに返させる要約の形式に **重大度・場所・見出しに加えて「修正コスト（高/低）」**を必ず入れる。入っていなければ、本文を開かずに当人へ聞き返す（1 往復で済む）。
- → **harness v0.5.0 へ昇格**（`harness/skills/task-orchestrate/SKILL.md` §3.2 と `harness/docs-template/roles/reviewer.md` の「報告の形式」）。

## 2026-09-17 実装役が検査を裏プロセスで回して自分の完了待ちで止まる [harness候補]
- 症状: 実装役に「終わったら検査を回して出力を report に貼れ」と指示すると、検査をバックグラウンドで起動してからその完了を待つ形になり、**待ちのまま進まなくなる**。統括が「前面で回して報告せよ」と催促して初めて動いた。
- 原因: 指示が「回す」としか書いておらず、前面／裏を決めていなかった。検査は数分かかるので、裏に回したくなる動機がある。
- 対処 / 再発したら: 実装役が黙り込んだら、まず**検査を裏で回していないか**を疑う（report が空のまま時間だけ経っているのが徴候）。指示テンプレに「前面（フォアグラウンド）で回す」と明記する。
- → **harness v0.5.0 へ昇格**（`harness/skills/task-orchestrate/SKILL.md` §2.1 の指示テンプレ）。

## 2026-09-18 checks.sh に inline で `$(...)` を書くと harness check が無限再帰する [harness候補]
- 症状: `.harness/checks.sh` に検査を 1 行足したら、`harness check` が終わらなくなった。5 時間で **bash プロセスが 1833 個**に増え、14 秒おきに 1 段ずつ親子関係が伸びていた（全部同じ PGID）。使い捨てディレクトリも増え続ける。
- 原因: `checks.sh` は check.sh に **source される**シェルファイルで、`check "名前" "コマンド"` の第 2 引数は二重引用符の文字列。ここに `$(...)` や `$VAR` を**エスケープせずに**書くと、**checks.sh を読み込んだ瞬間に展開される**（検査が実行される時ではない）。展開された中身が `harness check` だったため、checks.sh のロード → harness check → checks.sh のロード → … と再帰した。`\"` は正しくエスケープできていたのに `$` だけ落としていた、という 1 文字の取りこぼしで起きる。
- 対処 / 再発したら: **`harness check` が返ってこない / プロセスが増え続けるときは、まず `checks.sh` の各行で `$` がエスケープされているかを見る**（`grep -n '[^\]$' .harness/checks.sh`）。暴走を止めるには `ps -W | awk '$3==<PGID>'` で群を特定して `kill -9 -<PGID>`。
- **予防（これが本質）**: 数行を超える検査、特に**使い捨てプロジェクトを作る・`harness` 自身を呼ぶ**検査は、inline で書かず `tests/<name>.sh` に逃がして `check "名前" "bash tests/<name>.sh"` で登録する。エスケープの問題が構造的に消え、`trap` で後片付けも書ける。既存の `doctor scenarios` / `update scenarios` / `seed checks are green` がその形。

## 2026-09-20 macOS の既定 bash 3.2 + UTF-8 では `"$var日本語"` が unbound variable になる [harness候補]
- 症状: macOS で `harness doctor` が途中の行で `doctor.sh: line 421: eff_source?: unbound variable` と言って異常終了する。その変数は数行上で普通に代入されている。FAIL 行は出るのに総括行まで届かない。
- 原因: bash 3.2 はマルチバイト文字を変数名の境界として扱わず、`"$eff_source。"` の「。」の先頭バイトを変数名に食い込ませる。`set -u` があるので未定義として落ちる。Apple は GPLv3 を避けて bash を 3.2.57 のまま置いているので、**この環境は今後も無くならない**。
- 対処 / 再発したら: 変数展開を `${var}` と波括弧で括る。`bash tests/lint-bash-compat.sh nonascii-var` が `bin/harness`・`harness/scripts/*.sh`・`tests/*.sh` を機械的に締め出しているので、**まずこの検査を回す**。対象外（`harness/adapters/` 等）に書く時は自分で気をつける。日本語でメッセージを書くプロジェクトは必ず踏む。

## 2026-09-20 PATH からディレクトリを丸ごと外すテストは macOS 15+ で誤検知する [harness候補]
- 症状: 「node / jq が無くても全項目が実行できる」テスト（`tests/doctor.sh` の C3）が macOS でだけ落ちる。`jq` を消したいだけなのに、テストが見ている別の項目まで壊れる。
- 原因: macOS 15 以降は `jq` が Apple 提供で `/usr/bin/jq` に居る。`git`・`sed`・`grep` と**同じディレクトリ**なので、`jq` のあるディレクトリを PATH から外すとそれらも巻き添えで消える。Linux / Windows では `jq` が `/usr/local/bin` などに単独で居るため表に出ない。
- 対処 / 再発したら: ディレクトリ単位で PATH を削らず、**実行ファイル単位でスタブ化する**（空のディレクトリを PATH 先頭に置き、消したいコマンド名だけ `exit 127` のスクリプトで覆う）。「任意依存が無い環境」を作るテストが特定の OS でだけ落ちたら、まずそのコマンドが標準ディレクトリに同居していないか `command -v` で見る。
