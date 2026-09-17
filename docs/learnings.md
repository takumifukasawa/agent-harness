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
