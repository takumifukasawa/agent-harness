# agent-harness 設計

> **主役は「プロジェクトをエージェントにどう進めさせるか」のワークフロー。** それを各プロジェクトに配って更新する仕組みは、ワークフローを支える最小限の配管。
> 対象エージェント: Claude Code / Codex CLI / 今後の他エージェント。
> 状態: 0.3.0（2026-09-17）。ワークフローの雛形・それを回す `task-orchestrate` スキル・配管の CLI（gc と settings マージ含む）は実装済み。このリポジトリ自身に導入済み。`task-orchestrate` で機能 1 つを通す dogfood は題材待ち（§11）。

---

## 0. この文書の読み方（2 層）

| 層 | 問い | 本設計での位置づけ | 主な参考 |
|---|---|---|---|
| **① ワークフロー** | 1 つの機能・タスクを、エージェントにどう進めさせるか | **主役**。第 I 部 | SmartHR（ani 氏）、OpenAI の docs 構造と機械強制、Fowler の guide / sensor |
| **② 配管** | ワークフロー（指示・docs 構造・スキル・検査）を、どう配って、更新して、戻すか | **支え**。第 II 部。最小限に留める | OpenAI の garbage collection、DeNA の「効くのに勝手には育たない」問題 |

2 層を分けて書く理由: 「再試行は新しい 1 体か」（①）と「配布はコピーか subtree か」（②）は別の議論で、混ぜると読み手がどちらを判断しているのか分からなくなる。2026-09-17 のレビューでこの混在を指摘され、①を主役にすると決めた（§10 #10）。

---

# 第 I 部 ワークフロー（主役）

## 1. 解きたいこと

| 症状 | 原因 |
|---|---|
| 1 機能が 1 つのコンテキストに収まらず、後半ほど仕様やコードを読む余地が減る | 1 セッションで扱う範囲と読ませるものを絞っていない |
| 仕様の取り違えが終盤にまとまって見つかり、数週間の手戻りになる | 合意が会話に残り、仕様に書き戻されていない |
| 既存機能へのデグレを LLM の自己申告で「大丈夫」と通してしまう | 完了条件が機械で判定されていない |
| プロジェクトごとに指示ファイルや docs の置き方が違い、エージェントの挙動が毎回違う | 運用の規約に正本がない |
| Claude 前提で書いたものが Codex で動かない | エージェント固有の機構に依存している |

## 2. 原則

1. **AGENTS.md は目次、`docs/` が正本。** 1 つの巨大な指示ファイルは文脈を圧迫し、腐り、機械検証できない（OpenAI の失敗談）。入口は短く、深い情報は索引から辿る。
2. **リポジトリに無い知識は存在しない。** チャット・会議・口頭の合意は docs に書き戻すまで「決まっていない」。エージェントは実行中に文脈へ入らないものを知らない。
3. **決定的なものを優先する。** Fowler の区分で、事前に導く guide（指示・docs・雛形）と事後に検知する sensor（検査・git hooks・CI）があり、それぞれ computational（決定的・速い・トークン不要）と inferential（LLM 判断）がある。守らせたいことは文章より検査に落とす。強制の階層は `git hooks / CI` > `エージェント hook` > `AGENTS.md の文章`。
4. **検査は回避手段も塞ぐ。** テスト 0 件で green、除外リストへの追記、フラグ ON 設定の追加。抜け道を残すと「自己申告に頼らない」目的が崩れる。検査のエラー文には修復手順を埋める。エージェントはそれをそのまま文脈に取り込むので、最も安い指示経路になる。
5. **計画は成果物。** 数セッションに跨る作業は計画ファイルに進捗と決定ログを追記し、コミットする。
6. **エージェント非依存。** 正本は複数エージェントが読める形式に置き、固有機能は無くても運用が成立する補助にする。

### 正本の形式（エージェント非依存の根拠）

| 層 | 正本 | Claude Code | Codex CLI |
|---|---|---|---|
| 指示（憲法） | `AGENTS.md` | `CLAUDE.md` に `@AGENTS.md`（Claude は AGENTS.md を直接読まない） | ネイティブ |
| パス限定の規律 | サブディレクトリの `AGENTS.md` | そのディレクトリのファイルを読んだ時点で隣の `CLAUDE.md` 経由で載る（ファイル基準） | **ルートから cwd までの連鎖**のみ、合計 32 KiB（cwd 基準）。cwd をそこにするか、統括が明示的に渡す |
| スキル | `SKILL.md`（agentskills.io 仕様）を `.agents/skills/` に | `.claude/skills/` へコピー（`.agents/skills/` は探索しない） | `$CWD/.agents/skills` から `$REPO_ROOT/.agents/skills` まで探索 |
| プロジェクト文脈 | `docs/` の Markdown | ○ | ○ |
| 作業状態 | `.harness/state/*.json`（gitignore） | ○ | ○ |
| 検査 | `.harness/checks.sh` + `.githooks/` + CI | 加えて `settings.json` hooks（任意） | 任意 |
| 権限・deny | 固有 | `settings.json` の `permissions.deny` | `config.toml` |
| サブエージェント | `docs/roles/*.md`（役割文） | `.claude/agents/*.md` を生成 | `.agents/skills/role-*/SKILL.md` を生成し `$role-implementer` と明示呼び出し |

各アダプタの README に「確認日」と「確認元」を書く。上の事実は 2026-09-17 に公式 docs で確認した。

## 3. プロジェクトに置くもの

```
<project>/
├── AGENTS.md                 # 管理ブロック（地図 + 共通ルール、60 行以内）+ プロジェクト自由記述
├── CLAUDE.md                 # "@AGENTS.md" の 1 行（Claude アダプタ）
├── <subdir>/AGENTS.md        # パス限定の規律（プロジェクトが置く）。隣に CLAUDE.md が自動生成される
├── .agents/skills/           # session-catchup / session-handoff / harness / harness-maintain
├── .claude/skills/, .claude/agents/   # Claude 用コピーと生成物
├── .githooks/pre-commit      # 速い検査だけ回す
├── .harness/                 # 配管: manifest, CLI 同梱コピー, checks.sh, scripts, state-template, state(gitignore)
└── docs/                     # 事実の正本（system of record）
    ├── README.md             # 索引。まずここ。索引に無い doc は存在しないものとして扱う
    ├── handoff.md            # 現在地。何が済み / 途中 / 次 / 順序制約。active な plan への入口
    ├── spec/                 # 何を作るか（唯一の正）。受け入れ条件はここに。UI プロトタイプも
    ├── rules/README.md       # パス限定の規律の一覧（規律本体はサブディレクトリの AGENTS.md）
    ├── roles/                # 統括 / 実装 / レビュアーの役割文（§5）
    ├── plans/active,completed/  # 数セッションに跨る作業の計画。進捗・決定ログ込み
    ├── decisions/            # 決定記録（採用案・落選案・理由）
    ├── architecture.md       # 境界・依存の向き・機械的に強制する不変条件と強制手段
    ├── learnings.md          # 踏んだ罠と対処。ハーネスへ昇格する候補の溜まり場
    ├── tech-debt.md          # 既知の負債（gc の対象）
    └── references/           # 依存ライブラリの仕様抜粋など、外部知識をリポジトリに持ち込む場所
```

OpenAI のレイアウト（design-docs / exec-plans / tech-debt-tracker / product-specs / references）に、SmartHR の spec / rules / roles を足した形。`generated/`（スキーマ等の生成 doc）と領域別の品質グレードはプロジェクト任せで、雛形には含めない。

### AGENTS.md の管理ブロックに入れるもの

プロジェクトを跨いで真であることだけ。地図（上の docs のどこに何があるか）、セッションの入口と出口、検証と報告の作法、計画と長期タスクの進め方、記録の作法、やらないこと。言語・フレームワーク・ビルドコマンド・ブランチ運用はブロックの外にプロジェクトが書く。

## 4. 毎セッションの流れ

| 場面 | すること | 理由 |
|---|---|---|
| 開始 | `session-catchup`: 索引 → handoff → git 実態（log / status）の順に安く読む | 全 doc を読むとトークンを溶かし古い記述で頭が埋まる。読まないと revert 済みを実装済みと信じる。索引から入り最後に実態と照合する |
| 作業中 | 決定は `decisions/`、罠は `learnings.md`、合意は spec に**書き戻す**。相対日付は絶対日付に | 原則 2 |
| 実装後 | `harness check`（`.harness/checks.sh` の検査）。結果は出力ごと報告、スキップは明言。検査を通すために検査を弱めない | 原則 3・4 |
| 終了 | `session-handoff`: handoff を実態に合わせ、`NEXT` を依存順に、未確定は人間へ。`harness status` で管理ファイルの drift を報告。docs をコミット | 次のセッションが catchup しても VCS と照合してズレない状態にする |

## 5. 大きなタスクの流れ（SmartHR 型）

1 つのコンテキストに収まらない機能を、**1 セッション = 1 タスク**で進める。役割・状態・検査の 3 点セット。

### 4 つの役割（`docs/roles/`）

| 役割 | 責務 | 持たせないもの（こちらの方が効く） |
|---|---|---|
| **orchestrator**（メインセッションそのもの） | フェーズ遷移、状態ファイルの更新、検査の実行、実装役の起動、モデル選択、ユーザーとの対話 | 自分で実装しない。spec 本文とレビュー全文を文脈に載せない。統括を別エージェントに委譲しない（要約でノイズが増え精度が落ちる） |
| **implementer**（1 タスク 1 体、毎回新しく） | 渡された spec の節・規律・受け入れ条件だけを読み、TDD でコミットまで | ユーザーに質問しない（戻り値の `questions` に書く）。spec 全体を読まない。担当外を触らない |
| **reviewer**（全タスク完了後に 1 回、観点別に並列） | 仕様突合 / 並行性 / 認可 / 機能の完結性 | 毎タスクでの起動（偽陽性とコストが積み上がり、つなぎ目の欠陥は全部そろわないと見えない） |
| **machine check**（`harness check`） | 完了条件の決定的判定。トークンを使わない | 判断 |

### 状態の外部化（`.harness/state/`、gitignore）

| ファイル | 中身 | 原則 |
|---|---|---|
| `progress.json` | フェーズ、進捗、終わったぶんの 1 行サマリ、未確定事項、最終レビュー結果、ブランチ等のローカル値 | 毎ターン読む。**確定したことは書かない**（spec / 規律 / コードのコメントへ書き戻す）。残すのは未確定の前提・未回答の質問・次タスクへの注意点 1 行 |
| `stages.json` | タスク一覧（受け入れ条件、参照 spec、規律、モデル、戻り値、次タスクへの注意点） | 進行中のぶんだけ読む。1 ファイルだと 10 タスクで 118 KB になった実例があるので分ける |

gitignore にする理由: 作業中の分解や進み具合は他人が知る必要がなく、ローカル固有の値を含む。別の人が続ける時は state を捨てて起動し直し、実装済み範囲は git 履歴から拾う。`docs/handoff.md` と `docs/plans/` は人間向けの要約・計画で残る。state は捨てられる。

### spec と規律

- **spec**（何を作るか）: `docs/spec/`。唯一の正。
- **規律**（常に守ること、やらないこと）: 効かせたいパスの `AGENTS.md`。矛盾したら**規律が勝つ**。
- 必ず**セットで**渡す。規律を渡し忘れるとエージェントは「spec に無いから自由」と解釈して破る。

### フェーズ

1. **準備（最初の 1 セッションだけ）**: spec と依頼の乖離を 1 件ずつユーザーと合意し、spec と規律に書き戻す。**乖離が 1 件でも未解決ならタスク分解に進まない。** 設計判断を `decisions/` へ。タスクごとに受け入れ条件（文で数件）を付けて `stages.json` へ。手戻りがほぼ出なかった最大の要因はここ。
2. **反復（1 セッション = 1 タスク）**: 統括が実装役を起こし、spec の節・規律・受け入れ条件・使うモデルを渡す。実装役は Red → Green → Refactor でコミットまで。統括が**自分で**検査を叩く（自己申告を信用しない）。fail なら**新しい 1 体**に失敗出力と前回レポートのパスを渡してやり直し、3 回で人へ。統括自身のセッションは切らない。3 行で報告してセッションを終える。
3. **最終レビュー（1 回）**: 観点別に並列起動し、重複排除。反証は「報告者が 1 体だけ、かつ修正コストが高い」指摘にだけ回す。根拠はコード行かテスト出力のみ。白黒つかなければ強度を下げて残す。多数決もしない。

TDD を固定する理由: テストが「曖昧さのないゴール」「ハルシネーションをその場で弾く」「人を待たずに自己判定できる」の 3 役を果たす。受け入れ条件の解釈違いが最初のテストで表面化する。

モデル選択: 設計の余地で決める。データモデルや状態遷移を組み立てるタスクは上位モデル、決まった型に沿って API や画面を足す・テストを足すタスクは下位モデル。spec と規律を絞って渡すほど下位モデルでも安定する。

再試行を「新しい 1 体」にした根拠: SmartHR 原文は図 1 で「新しい 1 体で」、シーケンス図で「同じセッション内で」と書き分けており、後者は統括のセッションを切らない意味と**解釈**した。事実ではなく解釈なので、dogfood で確かめる（§11）。

### アダプタへの翻訳

- Claude Code: `docs/roles/{implementer,reviewer}.md` から `.claude/agents/*.md` を生成（frontmatter に name / description / model）。統括はメインセッションなので生成しない。
- Codex: 役割文を `.agents/skills/role-<name>/SKILL.md` として生成し、`$role-implementer` と明示呼び出しする。
- 手順そのものは `task-orchestrate` スキル（両エージェント共通）。実装役の起動手段だけがエージェントで異なり、スキル内で分岐を書いている。
- パス限定の規律は Codex では cwd 基準なので、統括が該当 `AGENTS.md` を実装役に明示的に渡す（SmartHR の「必要なセッションにだけ動的に読み込む」と同じ）。

## 6. 学びを環境に戻す（プロジェクト内）

「同じミスを二度させない恒久修正を環境側に施す」。罠を踏んで解決したら `learnings.md` に「症状 → 原因 → 再発したら」で書き、昇格先を **検査 > スキル > AGENTS.md の文章** の優先順位で選ぶ。文章は常時ロードされ、守られにくく、腐る。検査は二度と起きない。

プロジェクト非依存の学びには `[harness候補]` を付け、第 II 部の経路で正本へ戻す。

docs の腐敗（handoff の鮮度、as-of 日付の化石、索引と実体の食い違い、切れたリンク、放置された plan と負債、管理ファイルの drift）は `harness gc` で機械的に検知し（未実装）、修正は人か `harness-maintain` が行う。OpenAI の doc-gardening に相当。

---

# 第 II 部 配管（支える仕組み、最小限）

## 7. 配布の形

- **正本はこのリポジトリの `harness/`（ペイロード）。** `AGENTS.core.md`、`docs-template/`、`skills/`、`scripts/`、`checks.seed.sh`、`state-template/`、`adapters/`。
- **導入はコピー + manifest。** `.harness/manifest.json` に版・source・ファイルごとの所有権とハッシュ（`git hash-object`）を記録する。1 エントリ 1 行の JSON で、bash の sed だけで読む。各エントリの `src`（ペイロード側パス）で逆マッピングできる。
- **CLI 自身も同梱**（`.harness/bin/harness` + Windows 用 `harness.cmd`）。プロジェクトを clone した PC は追加インストールなしで update できる。source は ローカルパス か git URL（`~/.cache/agent-harness/` に clone）。

### 所有権

| 所有権 | 意味 | update 時 |
|---|---|---|
| **managed** | ハーネスが正本（スキル、スクリプト、CLI、CLAUDE.md） | 未改変なら上書き。改変済みなら保持し `.harness/conflicts/<path>.new` に新版 |
| **seed** | 雛形から一度だけ生成。以後プロジェクトの資産（docs、checks.sh） | 触らない。無ければ生成 |
| **merge** | AGENTS.md。マーカー `<!-- harness:begin v=X -->`…`<!-- harness:end -->` の内側だけハーネス | ブロックだけ差し替え。ブロックが手で変わっていたら衝突。`v=` は CLI が VERSION から埋める |
| **generated** | seed から生成されるアダプタ出力（`.claude/agents/*.md`） | 生成元のハッシュも記録。生成元が変われば再生成、出力だけ変わっていれば衝突 |

改変判定は 2-way（導入時ハッシュ vs 現在）。上書き前に `.harness/backup/<ts>/` へ退避。既存の `AGENTS.md` / `CLAUDE.md` は壊さず先頭に足すだけ。manifest に無いのに存在する managed パスは衝突扱いにして上書きしない。

## 8. CLI

```
harness init   [--source <path|git-url>] [--ref <tag>] [--agents claude,codex]
harness update [--ref <tag>]      # CHANGELOG の差分を表示してから所有権規則で更新
harness status                    # 版と、unchanged / MODIFIED / missing
harness diff                      # 手で直した managed の差分（上流に戻す候補）
harness upstream <path>...        # 正本の harness/ へ書き戻す（source がローカル clone のとき）
harness check [--fast]            # .harness/checks.sh の検査を実行
harness gc [--days N] [--strict]  # docs の腐敗検知（§6）。判断はしない
harness doctor                    # 環境と導入状態の診断（OK/WARN/FAIL の一覧。判断はしない）
harness self-install [--dir]      # PATH に置く。Windows は harness.cmd も
```

呼び方は 3 つ: セッション内から `/harness status`（Claude）/ `$harness status`（Codex）、PATH の `harness status`、同梱コピーを直接。PATH 上の `harness` はプロジェクト内では同梱コピーへ委譲し、版をプロジェクトに固定する。

### 実装メモ
- 依存は git と bash だけ。Windows は Git for Windows の bash。PowerShell 移植はせず 1 行のシムで委譲。
- `.gitattributes` で `.harness/**`、`.claude/**`、`.agents/**`、`docs/roles/**`、`AGENTS.md`、`CLAUDE.md` を LF 固定（autocrlf で bash が壊れ、ハッシュも狂う）。`harness.cmd` だけ CRLF。
- update は同梱 CLI 自身を上書きするので、同梱コピーから起動されたときは一時ファイルに自分を写して `exec` し直す。
- 「同じスクリプトか」はパス文字列でも `-ef` でも判定しない。Windows では `git rev-parse` が `C:/...`、`realpath` が `/c/...` や `/tmp/...` を返し、`-ef` も `C:/` 形式で偽を返した。内容ハッシュで判定し、`project_root` は `cygpath -u` で正規化する。
- ローカルの `--source` は絶対パスにして保存する。
- 検証済み（2026-09-17、Windows）: init → 改変 → diff → upstream → 版上げ update → 衝突退避 → 再生成 → `file://` URL init → `curl | bash` 相当 → cmd / PowerShell 経由 → self-install と委譲 → 自己上書き → 空白パス → git 管理外 → CRLF の既存 AGENTS.md。

## 9. 更新と吸い上げのループ

```
   agent-harness（正本）                            各プロジェクト
   ┌──────────────┐        init / update           ┌──────────────┐
   │ harness/     │ ─────────────────────────────▶ │ AGENTS.md    │
   │ CHANGELOG    │                                │ .agents/     │
   │ VERSION      │ ◀───────────────────────────── │ .harness/    │
   └──────────────┘        diff / upstream         │ docs/        │
          ▲                                        └──────────────┘
          │  learnings の [harness候補] を 検査 > スキル > 文章 へ昇格
          └──────────────────────────────────────────────┘
```

- プロジェクトで managed を直した → `diff` → `upstream` → 正本でレビュー・commit → `CHANGELOG.md` に「プロジェクト側で必要な作業」→ `VERSION` → 他プロジェクトで `update`。
- 破壊的変更（ファイル移動、マーカー形式）は major。
- managed の改変を放置するのは負債。`session-handoff` が `harness status` で毎回可視化する。

### 隣の `agent-skills` との分担

`agent-skills` は個人の汎用ノウハウ（マシン単位、`~/.claude/skills` にリンク）。こちらはプロジェクト運用の足場（リポジトリ単位、コミットされ、Codex や共同作業者にも見える）。`context-catchup` / `context-handoff`（agent-skills）と `session-catchup` / `session-handoff`（本ハーネス）は発火語が重なるので、dogfood を始めたら agent-skills 側の description に「ハーネス未導入（`.harness/` が無い）リポジトリで使う」と書いて分ける。

---

## 10. 決定ログ

| # | 層 | 論点 | 決定 | 理由 |
|---|---|---|---|---|
| 1 | ② | 配布方式 | コピー + manifest | submodule は人もエージェントも事故が多い。subtree は履歴が重く、AGENTS.md 等を外に出す処理が別に要る |
| 2 | ② | Windows の skills リンク | コピー | symlink は開発者モードが必要 |
| 3 | ② | `.claude/settings.json` | v0 は断片を手で反映 → **0.3.0 で自動マージ**（node があれば。無ければ手で反映） | 管理するのは断片の deny と `.harness/` を含む hooks だけ。プロジェクトの項目は触らない |
| 4 | ② | Codex 側 hook | 当面使わない | git hooks と AGENTS.md の文章で代替 |
| 5 | ① | Claude auto-memory と docs | docs が正。memory は参照と個人の好みだけ | Codex と共有でき、二重管理を避ける |
| 6 | ① | 長期タスクの状態 | SmartHR 型 JSON 2 ファイル、gitignore | §5 |
| 7 | ① | サブエージェントの役割 | SmartHR 型 4 役割を `docs/roles/` に | §5 |
| 8 | ② | 別 PC への配布 | マーケットプレイスは使わず、CLI 同梱 + source は git URL | プラグインは Claude 専用でリポジトリに入らず、manifest の衝突検出と噛み合わない |
| 9 | ② | Windows と短い呼び出し | `harness.cmd` シム、`self-install`、`/harness` スキル | git 前提なので bash は常にある。スキルなら両エージェントで同じ呼び方 |
| 10 | ① | 再試行 | 新しい 1 体に失敗出力を渡す。統括のセッションは切らない | SmartHR 原文の解釈。実装役の使い回しは履歴で精度が落ちるという同記事の原則に沿う |
| 11 | — | この設計の主役 | **① ワークフロー**。②は最小限 | SmartHR は①、DeNA は②の話で、混在していた。2026-09-17 にユーザーが①を選択 |

## 11. 実装状況と次の一手（①を優先）

| 状態 | 項目 |
|---|---|
| ✅ | ① の雛形: `AGENTS.core.md`、`docs-template/`（spec / roles / rules / plans / decisions / learnings / tech-debt / references / architecture）、`state-template/`、`check.sh` と `checks.seed.sh`、`session-catchup` / `session-handoff` |
| ✅ | ② の配管: CLI 一式、所有権、manifest、Windows 対応、`harness` / `harness-maintain` スキル |
| ✅ | ① `task-orchestrate` スキル（0.2.0）: §5 の 3 フェーズを回す手順。state の初期化、実装役への指示テンプレート、検査、再試行、最終レビューの重複排除と反証 |
| ✅ | ① Codex 用の役割スキル生成（0.2.0）: `.agents/skills/role-{implementer,reviewer}/` |
| ⬜ 3 | **① dogfood**: 自分のプロジェクト 1 つで機能 1 つを §5 で通す。確かめること: 再試行「新しい 1 体」の精度とコスト、Codex でのパス限定規律（cwd か明示渡し）、`checks.sh` に何を登録すると効くか、`task-orchestrate` の手順で統括が迷う箇所 |
| ✅ | ② `harness gc`（0.3.0）: handoff の鮮度、索引とリンクの切れ、放置された plan / state / 負債、管理ファイルの drift、古い references |
| ✅ | ② `.claude/settings.json` の自動マージ（0.3.0）: node があれば deny と `.harness/` hooks だけを差し込み、プロジェクトの項目は保持。無ければ手順を案内 |
| ✅ | このリポジトリ自身への導入（0.3.0）: 検査 8 件を `.harness/checks.sh` に登録。導入コピーとペイロードの同期を検査で強制 |
| ⬜ 6 | ② GitHub からの `curl | bash` init を実機で確認。macOS / Linux 未確認（`docs/tech-debt.md`） |

## 12. 非ゴール

- **DeNA 型のログ・メモリ採掘**（セッションログや auto-memory から CLAUDE.md の改善案やスキルを自動生成する）。②の発展形だが、主役を①にしたので範囲外。`learnings.md` に人が書いたものを昇格させる経路で代替する。
- 汎用スキル集（`agent-skills` の役割）。
- マルチエージェント実行基盤そのもの（エージェントを起動する機構は各エージェントに任せ、役割文・状態・検査の置き場だけ持つ）。
- プロジェクトのビルド／テスト基盤（ハーネスは「呼ぶ」だけ）。

## 付録: 参考にした考え方

| 出典 | 層 | 取り入れたこと |
|---|---|---|
| SmartHR「Claude Code で開発期間を 2.5 か月から 1 か月に縮めた『ハーネス』の設計手法」（ani 氏、2026-09-16） | ① | 4 役割、1 セッション 1 タスク、状態 JSON 2 ファイル、spec と規律の分離とパス指定、12 項目の機械検査と回避手段の封じ込め、合意の書き戻し、最後に 1 回のレビューと反証の 3 縛り、モデルの使い分け |
| OpenAI「Harness engineering」 | ①② | AGENTS.md は目次、docs が正本、計画は成果物、リポジトリに無い知識は存在しない、カスタムリンタと構造テストで機械強制、エラー文に修復手順、garbage collection、レビューの好みを docs か検査に昇格 |
| Martin Fowler「Harness engineering for coding agent users」 | ① | guide / sensor、computational / inferential、品質を左へ |
| DeNA「geni ハーネスくん」 | ② | 「勝手に溜まるもの」と「効くのに勝手には育たないもの」の非対称。共有時の個人情報除去、上書き前バックアップ、人間承認 |
| DeNA「Claude Code 勉強会レポート」 | ① | 指示ファイルは短さより構造化、スキル description に具体例、hooks はセキュリティ用途 |
| sasadango28「Claude Code でハーネスエンジニアリングを実践する」 | ①② | 同じミスを二度させない恒久修正、決定的処理はスクリプトへ、hooks は動的判断が要るまで入れない、deny で静的に塞ぐ |
