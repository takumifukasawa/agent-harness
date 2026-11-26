# .harness/checks.sh — このプロジェクトの検査一覧（seed: プロジェクトが編集する。harness update は触らない）
#
# 書式:  check [fast] [serial] [on "<パス…>"] [related "<コマンド>"] "<表示名>" "<コマンド>"
#   fast を付けた検査は pre-commit（harness check --fast）でも走る。数秒で終わるものだけに付ける。
#   on "<パス…>" を付けた検査は、そのパスが変わったときだけ普段の harness check で回る（時間のかかる検査に付ける。
#   パスは広めに取る）。harness check --full では全部回る。on を付けた検査があると、push の前に --full が求められる。
#   related "<コマンド>" を付けた検査は、harness check --since <ref>（実装役がタスクごとに回す軽い検査）のとき、
#   本来のコマンドの代わりに「<コマンド> <変わったファイル…>」を回す。関係するテストだけを選べるツールに使う
#   （例: related "npx vitest related --run --passWithNoTests"、related "npx jest --findRelatedTests --passWithNoTests"）。
#   import をたどらない影響（文言・CSS・設定ファイル）は選べないので、それらのパスでも本来のコマンドが要るなら
#   --full（最終レビューの前と push の前）に任せる。消したファイルがあるときは本来のコマンドを回す。
#   fast と related を両方書いた検査は、pre-commit（--fast）ではステージしたファイルだけを渡して回す
#   （例: check fast related "npx prettier --check --ignore-unknown" "format" "npx prettier --check ."。
#   ステージしたファイルが無ければ飛ばす）。リポジトリ全体を見る整形・lint を、コミットのたびに全体へかけない。
#   並列に回すなら、このファイルの先頭（最初の check より前）に CHECK_JOBS=auto（または数）を書く。
#   他の検査と同時に走らせられない検査（同じポート・固定の一時ファイル・同じ DB を使う）は
#   check serial "<表示名>" "<コマンド>" で登録する。既定は直列。
#   一時ファイルは固定のパス（/tmp/build.log など）に書かず、mktemp か作業ツリーの下に置く。git worktree で
#   並列に作業すると、別の作業ツリーの check と同じファイルを壊し合う（serial はその作業ツリーの中しか守らない）。
#
# 原則:
# - 各コマンドの失敗出力には「どう直すか」「どの doc を読むか」を含める。
# - 検査は「回避手段」も見る。テスト 0 件で green、除外リストへの追記、フラグ ON 設定の追加 など、
#   通すための抜け道を同じ検査で塞ぐ。エージェントの自己申告ではなく実行結果で判定するのが目的。
# - 機械で判定しきれない項目は自動 pass にせず「要確認」として人間に回す（例: 共有テーブルの変更、画面側のフラグ漏れ）。

# --- 例（SmartHR の 12 項目から。プロジェクトに合わせて書き換える） ---
# check fast "lint"                 "npm run lint"
# check fast "typecheck"            "npm run typecheck"
# check on "src/ test/" related "npx vitest related --run --passWithNoTests" "unit" "npx vitest run"
# check      "tests green (>0)"     "out=\$(npm test -- --json 2>&1); n=\$(echo \"\$out\" | jq .numTotalTests); [ \"\$n\" -gt 0 ] || { echo 'テストが 0 件。0 件で green は不合格。受け入れ条件をテストに落とす。'; exit 1; }"
# check      "flag OFF = baseline"  "bash scripts/check-flag-off-behavior.sh"        # フラグ ON 設定の追加も検知
# check      "changed files in scope" "bash scripts/check-allowed-paths.sh .harness/allowed-paths.txt"  # 許可パスの定義は 1 ファイルだけ
# check      "no new dep violations" "bash scripts/check-dependency-direction.sh"      # 除外リストへの追記も検知。docs/architecture.md の不変条件
# check      "TDD trace in commits"  "bash scripts/check-tdd-trace.sh"                 # test → impl の順にコミットがあるか
# check      "NEEDS HUMAN: shared tables" "git diff --name-only origin/main | grep -q '^db/schema' && { echo '要確認: 共有テーブルの変更あり。人間がレビュー。'; exit 1; } || true"

check fast "docs index exists" "test -f docs/README.md || { echo 'docs/README.md が無い。docs の索引。agent-harness の docs-template/README.md から作る。'; exit 1; }"
# doctor は普段の check のたびに回る。プロセスの起動が遅い PC で重ければ、on ".harness/ .githooks/ .claude/ .agents/
# .codex/ AGENTS.md CLAUDE.md docs/roles/" を付けて、それらが変わったときだけ回すこともできる（--full では必ず回る）。
# ただし on を 1 つでも書くと push の前に --full が要るようになり、git の設定（hooksPath）など作業ツリーの外の
# 問題に気付くのが --full まで遅れる。
check      "doctor: FAIL 0"    "bash .harness/bin/harness doctor || { echo 'doctor が FAIL を報告した。上の FAIL 行の「→」に従って直す。'; exit 1; }"
