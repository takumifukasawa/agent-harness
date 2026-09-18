# 0004: manifest の source は共有値に固定し、機械ローカルのパスは gitignore 対象の上書きへ逃がす

- 日付: 2026-09-18
- 状態: 採用

## 背景

`.harness/manifest.json` は **コミット対象の共有ファイル**（`.gitignore` に入っていない。`status` / `update` / `doctor` が読む導入状態の正本）なのに、`source` には `harness init --source <path>` で渡された、あるいは `self_repo()` が返した **その PC の絶対パス**が入っていた。

これは `.harness/state/` を「個人ローカルの値を含むから」と gitignore しているのと扱いが矛盾している。実害も 2 つ出ている。

1. **他の PC で clone すると壊れる**: `update` / `diff` / `upstream` はいずれも `manifest_get source` しか見ないので、その絶対パスが存在しない PC では `clone に失敗` で落ちるか、`upstream` が「source が git URL」と誤った理由で die する。
2. **worktree で他人の作業を取り込んだ（2026-09-18 に発生）**: 複数の実装役を git worktree で並列に動かし、各自が `harness/` を直して `bash bin/harness update` で同期する運用にしたところ、worktree 内の `update` が manifest の `source`（= main tree の絶対パス）を見に行き、**main tree で別の実装役が編集中だった未コミットの `harness/skills/harness/SKILL.md`** を `.agents/skills/` 等に取り込みかけた。当座は `source` を自分の worktree パスに書き換えて `update` → 元に戻す、という手順で復旧した（`docs/learnings.md` 2026-09-18）。

## 採用案

**manifest の `source` は共有値（URL）に固定し、機械ローカルのパスは gitignore 対象の上書きへ逃がす。**

- **解決順**: 環境変数 `HARNESS_SOURCE` > `.harness/source.local` > `.harness/manifest.json` の `source`
- `init` は `--source` にローカルパスを渡されても（`self_repo()` が真でも）manifest には**書かない**。manifest には共有値（既定は `DEFAULT_SOURCE` の URL）を書き、渡されたローカルパスは `.harness/source.local` に書く。`ensure_gitignore` が `.harness/source.local` を `.gitignore` に足す。
- `update` は解決順で source を決めて動き、manifest に書き戻すのは共有値だけ。旧形式（`source` に絶対パス）で導入されたプロジェクトは、`update` がその値を `.harness/source.local` へ移し、manifest を共有値に直す（移行は 1 回の `update` で完結し、利用者の手作業は要らない）。
- `status` / `diff` / `upstream` も同じ解決順を通る。`upstream` はローカルの clone が要るので、辿れなければ「`.harness/source.local` に書く / `HARNESS_SOURCE=` を付ける」という直し方つきで die する。
- **doctor B10** は解決結果を診断する。source が辿れなければ **WARN**（OK と言い切らない）にし、上書きの置き方を案内する。manifest に機械依存の絶対パスが残っていれば、それ自体を WARN にして `harness update` を案内する。spec の決定「**URL source のときはネットワークに触らない**」は据え置き、`status` にも同じ原則を効かせた（URL のときは版を比べず、案内だけ出す）。

worktree の事故は、worktree 内で `HARNESS_SOURCE=<自分の worktree> bash bin/harness update` と唱えるだけで塞がる。manifest を書き換えて戻す手順は要らなくなった。

## 落選案と落選理由

- **(a) 現状維持 + doctor で WARN のみ**: 診断は出るようになるが、**コミットされる共有ファイルに機械依存の値が残る問題そのものが消えない**。他の PC で clone した人は WARN を読んでから結局 manifest を手で書き換えることになり、その書き換えが次のコミットに紛れ込む（＝別の PC を壊す）往復が続く。
- **(b) `self_repo()` を manifest より優先する**: dogfood（このリポジトリ自身）で起きた worktree 事故は、worktree 内の `bin/harness` が `self_repo()` で自分を指すので確かに解ける。しかし **利用側プロジェクトで `--source <path>` を使った場合に他人のローカルパスが混入する経路が塞がらない**（そのプロジェクトには `self_repo()` が真になる `bin/harness` が無いので、manifest の絶対パスがそのまま使われる）。共有ファイルを汚さないという本題に届かない。
- **`.harness/state/` の中に置く**: 既に gitignore されているので追加の設定は要らないが、`state/` は task-orchestrate の進行状態（`progress.json` / `stages.json`）の置き場で、意味が違う。`.harness/state/` は消して作り直す運用があり、環境設定が巻き添えになる。
- **`source` を manifest から消して上書きだけにする**: 既定の導入元が分からなくなり、`init` をやり直すときの `--source` を手掛かり無しに思い出すことになる（決定 0003 の B3「見出しごと読めない manifest」の復旧が困難になる）。共有値としての `source` には意味があるので残す。
- **`git config` に持たせる（`harness.source`）**: gitignore 対象という性質は満たすが、worktree は原則として設定を main tree と共有するため（`--local` は `.git/config` 由来）、事故の本題である「worktree ごとに別の値」を素直に表現できない。ファイル 1 つのほうが `cat` で見え、bash と git だけという依存の縛りとも相性が良い。

## 影響・やり直す条件

- `bin/harness`: `effective_source()` / `read_source_local()` / `write_source_local()` / `is_shared_source()` を足し、`init` / `update` / `status` / `diff` / `upstream` を解決順に乗せた。`ensure_gitignore` に `.harness/source.local` を追加。usage に解決順を明記。
- `harness/scripts/doctor.sh`: B10 を解決順に合わせ、辿れないときは WARN。manifest に絶対パスが残っていれば別途 WARN。B11 の gitignore 必須エントリに `.harness/source.local` を追加。
- `tests/doctor.sh`: 末尾に「T09」節を足し、解決順・worktree 事故の解（`HARNESS_SOURCE`）・`diff` / `upstream` の上書き経路・B10 の 2 つの WARN（T07 の apply_fix 枠に乗せた）・**上書きが無く manifest が URL でも `status` / `doctor` がネットワークに触らない**ことを表明する。最後の 1 件は偽の HOME を渡して `~/.cache/agent-harness` が作られないことで確認する（`resolve_source` の clone キャッシュ）。
- このリポジトリ自身の `.harness/manifest.json` は `bash bin/harness update` の移行経路で共有値に直り、`/d/Developments/agent-harness` は `.harness/source.local` へ移った。`.gitignore` に `.harness/source.local` が入ったので、この移行は他の PC へ伝播しない。
- **他のプロジェクトで必要な作業**: 特に無い（`harness update` が自動で移行する）。ただし移行前の clone を別 PC で使う場合は、先に `echo '<clone した絶対パス>' > .harness/source.local` を置くと `update` が一発で通る。
- やり直す条件: `source` を複数持ちたくなった（例: ペイロードとアダプタで別リポジトリ）場合。そのときは `.harness/source.local` を 1 行 1 値のままにせず、キー付きの形式に変える必要がある。
