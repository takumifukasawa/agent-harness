# 0003: doctor の「直し方」を実測に合わせる（manifest 復旧経路 / CRLF・版ずれ・マーカー重複の一本化 / 非 git ディレクトリの根本原因）

- 日付: 2026-09-18
- 状態: 採用

## 背景

決定 0002（T08）で `harness update` は「壊れた managed / merge ファイルを退避ではなく復元する」ようになったが、`harness/scripts/doctor.sh` の「直し方」文言は決定 0002 より前のまま据え置かれていた。T14 はこの文言を決定 0002 の実装に合わせて書き直すタスクで、根拠は必ず使い捨てプロジェクトで実機確認した（T08 の実装や説明文を鵜呑みにしない）。

対象は 5 項目:

- **B3**: `.harness/manifest.json` が壊れている場合の復旧経路が、これまでどこにも無かった。`init` は manifest.json が存在するだけで「導入済み」として拒否し、`update` は manifest から `source` を読めず `clone に失敗` で落ち、`.harness/backup/` は init 直後には存在しない。
- **B4**: seed ファイル欠落の直し方が「harness の docs-template/ から取り直す」だったが、実際の src は docs-template/ の外にもある（例: `.harness/checks.sh` の src は `checks.seed.sh`）。
- **B5**: managed ファイルの CRLF 化の直し方に「`core.autocrlf false` のうえで」という不要な前提が付いていた。
- **B6**: プロジェクトルートが git リポジトリでない場合、core.hooksPath の WARN が「未設定」としか言わず、直し方（`git config core.hooksPath ...`）がそのままでは `fatal: not in a git directory` で失敗する根本原因を隠していた。
- **B7**: マーカー版ずれの直し方が `harness update`（`bin/harness` 抜きの表記）で他の項目と実行形が揃っていなかった。マーカー重複の直し方は「手で 1 組に整理する」のままで、決定 0002 で update が自動で畳むようになったことが反映されていなかった。

## 採用案

### B3: manifest の復旧経路は「見出しが読めるか」で二手に分ける

`.harness/manifest.json` は他の managed ファイルと違い、`apply_plan` の `ENTRIES`（`files` 配列）には現れない。`write_manifest` がツリーの実物から毎回新規に書き出すブックキーピングファイルなので、次のように分岐する（使い捨てプロジェクトで実測。手順は `tests/doctor.sh` の B3 シナリオに自動化した）。

| 状態 | 直し方 | 根拠 |
|---|---|---|
| `version` / `source` / `agents` の見出しは読める（`files` の記載だけが壊れている） | `bash .harness/bin/harness update` | update はこれらの見出しから source を解決し、ツリーの実物から `files` を作り直す。壊れた `files` の中身を読む必要が無い。実測: `update done: ... unchanged=39〜40 conflicts=0` で manifest が 41 件の正しい形に戻る |
| 見出しごと読めない | `mv .harness/manifest.json .harness/manifest.json.broken && bash .harness/bin/harness init --source <元の source>` | `update` は `source` を解決できず `clone に失敗` で落ちる。`init` は manifest.json が存在するだけで拒否するので、壊れたものを退避してから元の source を指定してやり直す以外に道が無い。init 時点でファイル本体が揃っていれば（＝壊れていたのは manifest.json だけ）、`apply_plan` は全ファイルを「変更なし」と判定し、正しい manifest.json だけが新しく書かれる（実測: `init done: new=0 updated=0 restored=0 unchanged=41 conflicts=0`） |

どちらのケースも **CLI（`bin/harness`）の変更は不要**。既存の `init` / `update` の挙動だけで復旧できることを実機で確認した。

### B4: seed 欠落は `harness update` に一本化

`apply_plan` は seed ファイルが無ければ src（docs-template/ 配下とは限らない）から作り直す。doctor の文言が「docs-template/ から取り直す」だったので、`.harness/checks.sh`（src は `checks.seed.sh`）のような docs-template/ 外の seed には当てはまらなかった。src を気にせず `bash .harness/bin/harness update` と案内すれば、実際に `seeded=N` として復元される（実測）。

### B5: CRLF の直し方は `harness update` 単体

`apply_plan` の復元は `cp` で生バイトを書き込むため、`core.autocrlf` の設定に関係なく直る（`git checkout` を経由しない）。「`autocrlf` を `false` にしてから」という前提は不要だったので削り、根本原因の説明（`autocrlf` が原因になりやすい）は残しつつ、直し方は `update` 単体にした。

### B6: 非 git ディレクトリは根本原因を先に告げる

`git -C "$ROOT" config --get core.hooksPath` は非 git ディレクトリでも `2>/dev/null` で握りつぶされ、「未設定」と見分けが付かない。`git -C "$ROOT" rev-parse --is-inside-work-tree` で先に判定し、非 git なら「git リポジトリではない」という根本原因と、`git init . && git config core.hooksPath .githooks` という完結する 2 コマンドを案内する。

### B7: 版ずれ・マーカー重複は `harness update` に一本化

版ずれの案内を他の項目と揃えて `bash .harness/bin/harness update` の実行形にした。マーカー重複は決定 0002 で update が begin/end を 1 対に畳むようになったので、「手で整理する」という古い案内を `bash .harness/bin/harness update` に置き換えた。いずれも実機で FAIL/WARN が消えることを確認した。

## 落選案と落選理由

- **B3: `.harness/backup/` からの復元を主経路にする**: `manifest.json` は `apply_plan` の `backup_file` を経由しないため、そもそも backup に入らない（`write_manifest` は無条件に上書きするだけ）。旧 doctor.sh はこれを主経路として案内していたが、実際には機能しない（今回の実測で確認した）。
- **B3: `git checkout -- .harness/manifest.json` を主経路にする**: `manifest.json` は gitignore されておらず通常はコミットされるので有効な場面もあるが、(a) 一度もコミットしていない間に壊れた場合は使えない、(b) doctor はプロジェクトが `manifest.json` を実際にコミットしているか・HEAD 側の内容が壊れていないかを安全に確認できない。プロジェクトの git 運用（コミット済みかどうか）に依存しない `update` / `init --source` を主経路にした。git で管理していればそちらでも直せるが、doctor の自動テストでは検証していない（tests/doctor.sh の使い捨てフィクスチャは `harness init` の結果をコミットしないため、このシナリオでは動かないことも確認済み）。
- **B3: `bin/harness` に専用の復旧コマンド（例: `harness repair-manifest`）を足す**: 実測の結果、既存の `init` / `update` だけで両ケースとも復旧できたため、CLI 変更は不要と判断した。T14 で触ってよい範囲が `harness/scripts/doctor.sh` ・`tests/doctor.sh` ・`docs/decisions/` に限られていた（`bin/harness` は別担当）こともあり、必要のない変更は増やさない。
- **B6: 「未設定」のまま据え置き、`git config core.hooksPath .githooks` だけを案内し続ける**: 非 git ディレクトリではこのコマンド自体が `fatal: not in a git directory` で失敗し、コピペしても直らない「偽の直し方」になる。spec C1（直し方は実行できるコマンド）に反するため採らない。

## 影響・やり直す条件

- `harness/scripts/doctor.sh`（正本）を直し、`bash bin/harness update` でこのリポジトリ自身の `.harness/scripts/doctor.sh` に同期した。
- `tests/doctor.sh` の対応シナリオに apply_fix（壊す → FAIL/WARN が出る → 直し方どおり実行 → 消える）を追加し、T07 が入れた既存の枠に乗せた。B6 は `.git` ごと消す性質上、既存の WARN 束ね（`ensure_warn_bundle`。git config に依存するセットアップを共有する）とは同居できないため、独立したシナリオにした。
- `DESIGN.md` §9 の所有権の表を決定 0002 に合わせて直す件は、決定 0002 の「影響・やり直す条件」に記載済みで、T14 の担当範囲外（docs 側を担当する別の実装役に委ねる）。
- やり直す条件: `bin/harness` に「見出しだけ壊れた manifest」を自動修復するサブコマンドを足す変更が別途入った場合、B3 の「見出しごと読めない」側の直し方をそちらに差し替える。
