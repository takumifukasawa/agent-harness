# 0002: update は変更済みの managed / merge を「退避」ではなく「復元」する

- 日付: 2026-09-17
- 状態: 採用

## 背景

`harness doctor` の診断項目に「直し方」を書いたが、**直し方どおりに `harness update` を実行しても直らない**項目が 5 つあった（T07 が実測）。B5 CRLF 化した managed ファイル / B7 AGENTS.md マーカーの版ずれ / B7 マーカーの重複 / B8 CLAUDE.md の `@AGENTS.md` import 欠落 / B8 `.claude/skills` の drift。

原因は個別の文言ではなく `bin/harness` の `apply_plan` の単一の挙動だった。既存の managed / merge ファイルが導入時のハッシュと違うと、`.harness/conflicts/<path>.new` に**新版を置くだけ**で実ファイルは触らない。つまり `update` を何回叩いても状態は変わらず、`doctor` は同じ FAIL を出し続ける。

同じコード経路にもう 1 つ欠陥があった。`hash_of()` が素の `git hash-object` を使っており、`.gitattributes` の `text eol=lf` と `core.autocrlf` のフィルタを通す。CRLF 化しただけの導入コピーは LF に正規化されてから hash されるので「未変更」に見える。これに騙されるのは `status` の MODIFIED 判定・`update` の上書き判断・検査 "installed copies in sync" の 3 つ全部で、B5 が `update` で直らなかった直接の理由でもある（`doctor` 側は T06 が `content_eq` で既に生バイト比較へ移している）。

## 採用案

**所有権の宣言どおりに振る舞わせる。managed / generated は harness が正本なので、ローカルの変更は `update` が正本の内容に戻す。**

| 所有権 | 変更されていたとき |
|---|---|
| managed / generated | **復元**（正本の内容で上書き）。変更前は `.harness/backup/<ts>/<path>` へ。出力に `restore <path>` と退避先を 1 行出し、集計に `restored=N` を足す |
| merge（AGENTS.md） | managed ブロックだけを現行版に戻す。ブロック外（プロジェクトの記述）は触らない。マーカーが重複していれば 1 対に畳む。変更前はファイルごと backup へ |
| CLAUDE.md | 上書きしない。**import スタブ**として `@AGENTS.md` の行だけを保証し、プロジェクトが書いた内容は残す |
| seed | 触らない（従来どおり） |
| manifest に無いのに存在する | 上書きしない。`.harness/conflicts/<path>.new` に新版（従来どおり） |

付随して決めたこと:

- **比較は生バイトで行う。** `hash_of()` を `git hash-object --no-filters` にし、空ハッシュを弾く。`doctor.sh` の `content_eq` と同じ方針。
- **ブロックのハッシュは全ブロックを連結して取る。** `block_hash()` が先頭ブロックしか見ていなかったので、重複したブロックが「未変更」になり検出すらされなかった。
- **`same_script()` だけは改行コードの違いを無視する。** 委譲（`maybe_delegate`）と自己上書き回避（`reexec_if_vendored`）の判断に使う関数で、CRLF 化しただけの同梱コピーを「別のスクリプト」と見なすと、正本側の `bin/harness` が壊れた同梱コピーへ `exec` してしまい、直す道が塞がる。
- **end マーカーが見つからない begin は、その 1 行だけを落とす。** 旧実装は begin からファイル末尾までをブロックと見なして捨てており、マーカーが 1 つ壊れただけでプロジェクトの記述が消えた。残骸が残る方を選び、「要らなければ手で消す」と出力で案内する。

## 落選案と落選理由

- **現状維持（conflicts に退避するだけ）**: 「直し方」が存在しない項目が残り、`doctor` が同じ FAIL を出し続ける。managed の宣言（harness が正本）とも矛盾する。
- **既定は退避のまま、`--force` で上書き**: 直し方が `harness update --force` になるだけで、既定の `update` は相変わらず直さない。エージェントも人も既定しか叩かないので、偽の「直し方」が残る。フラグの追加は API を増やす割に得るものが無い。
- **`--keep-local` のような逃げ道を足す**: 「managed をローカルで持ち続ける」を公式に認めることになる。残したい変更は `harness diff` → `harness upstream` で正本へ戻すのが唯一の道（DESIGN.md §9）。`.harness/backup/` があるので取り返しはつく。
- **対話で 1 件ずつ聞く**: エージェントが非対話で回す前提なので採らない。
- **ユーザーの変更を黙って捨てる（backup も報告もしない）**: 論外。復元は必ず backup と 1 行の報告を伴う。
- **CLAUDE.md も他の managed と同じく上書きする**: プロジェクトが CLAUDE.md に直接書いた内容（既存プロジェクトへ後から導入した場合に起きる）が消える。CLAUDE.md は `@AGENTS.md` を読ませるためのスタブなので、行が 1 本あれば目的を果たす。
- **AGENTS.md の end マーカー欠落を「begin から EOF まで」とみなして捨てる**: プロジェクトのルールが丸ごと消える。残骸が残る不格好さより、消えない方を優先する。

## 影響・やり直す条件

- **manifest の `sha256` は移行不要。** 記録済みの値はフィルタ後のハッシュだが、LF のファイルではフィルタの有無で値が変わらない。値が変わるのは「ディスク上が CRLF のファイル」＝ これまで誤って『未変更』とされていたファイルだけで、次の `update` で復元され、正しい生バイトのハッシュが記録し直される。`.harness/bin/harness.cmd`（意図的に CRLF）も同様に 1 回だけ記録が書き換わる（以後は安定する。従来は環境によって毎回 `update` が走っていた）。
- **`DESIGN.md` §9 の所有権の表（「改変済みなら保持し `.harness/conflicts/<path>.new` に新版」）はこの決定と食い違うので直す必要がある。** この実装タスク（T08）の担当範囲外なので、統括に差し戻す。
- `doctor` 側の「直し方」の文面（`harness/scripts/doctor.sh`）は T14 で、この挙動を前提に書き直す。
- 回帰は `tests/update.sh`（検査 "update scenarios"）が押さえる。12 シナリオ。所有権の規則を変えるときは、まずここにシナリオを足す。
- やり直す条件: 「managed をプロジェクトごとにフォークして持ちたい」要求が実際に出てきたら、所有権に `fork` のような区分を足す案を再検討する（ローカル変更を無条件に復元する今の規則の見直しになる）。
