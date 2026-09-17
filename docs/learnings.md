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
- 対処 / 再発したら: worktree で update する前に `source` が自分の worktree を指しているか確認する。当座は `source` を自分の worktree パスへ書き換えて update し、元に戻す。恒久対策は `source` を機械ローカルの上書き（環境変数 `HARNESS_SOURCE` / `.harness/source.local`）へ逃がすこと（T09、決定は `docs/plans/active/harness-doctor.md` の決定ログ）。

## 2026-09-18 worktree は古い分岐点で払い出されることがある [harness候補]
- 症状: サブエージェント用に払い出した worktree が、main の最新ではなく**かなり古いコミット**（このときは 14 コミット前）で止まっていた。spec も実装も無い状態で作業を始めかけた。
- 原因: worktree の作成元が最新の main とは限らない。払い出し側（エージェント基盤）の都合で決まる。
- 対処 / 再発したら: worktree で着手する前に `git merge-base --is-ancestor <branch> main` で確認し、独自コミットが無ければ `git merge --ff-only main` で追いつく。統括は払い出し直後に一度確認する。

## 2026-09-18 レビュアーを全部上位モデルで並列起動するとセッションのレート上限に当たる [harness候補]
- 症状: `task-orchestrate` §3 の最終レビューで観点別レビュアー 4 体を全部 opus で同時起動したところ、3 体が起動直後に 429（session limit）で停止。レポートは 1 件も書かれなかった。
- 原因: 1 体あたり 10〜18 万トークン読む役を 4 体同時に走らせると、5 時間枠の残量を一度に食い潰す。
- 対処 / 再発したら: **レビュアーと反証役は既定で下位モデル**にする（根拠を「コードの該当行かテストの出力」に縛ってあるので足りる）。統括だけ上位を保つ。停止した体は破棄せず、上限リセット後に同じエージェントへ「中断地点から再開」を送れば文脈を保ったまま続きから書かせられる。

## 2026-09-18 下位モデルに落としても壁時計時間は短くならない [harness候補]
- 症状: コスト削減のため実装役を opus → sonnet に下げたが、所要時間が縮まらなかった。
- 原因: 実測 — T06(opus) 39 分 / 40 ツール往復 / 116k トークン、T07(sonnet) 45 分 / **344 ツール往復** / **462k トークン**。下位モデルは試行回数で補うのでツール往復が桁で増える。単価差でコストは下がるが、往復ぶん時間は延びる。
- 対処 / 再発したら: モデルを下げるのは**コスト**のため。ETA を縮めたいならモデルではなく、検査の実行時間・タスクの並列化・スコープで削る。
