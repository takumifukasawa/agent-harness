#!/usr/bin/env bash
# tests/check-runner.sh — harness/scripts/check.sh（検査の実行役）自身のシナリオテスト
#
# 使い方:  bash tests/check-runner.sh
# 終了コード: 全シナリオ pass で 0、1 つでも落ちれば 1。
#
# 使い捨てのリポジトリに .harness/checks.sh を書き、check.sh を直接回す（init は通さない。速さのため）。
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO/harness/scripts/check.sh"
WORK="$(mktemp -d)" || { echo "tests/check-runner.sh: mktemp -d に失敗した"; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

passed=0; failed=0
failed_names=()
ok()   { passed=$((passed + 1)); echo "PASS  $1"; }
ng()   { failed=$((failed + 1)); failed_names+=("$1"); echo "FAIL  $1"; printf '%s\n' "$OUT" | sed 's/^/      | /'; }

P="$WORK/p"; mkdir -p "$P/.harness" && git init -q "$P"
checks() { printf '%s\n' "$@" >"$P/.harness/checks.sh"; }
run() { OUT="$(cd "$P" && HARNESS_FAST_WARN_SEC="${WARN:-5}" bash "$RUNNER" "$@" 2>&1)"; RC=$?; }

# ---- C1〜C3: --fast で重い fast の検査を言う（決定 0015）----
checks 'check fast "quick" "true"' 'check fast "slow" "sleep 2"' 'check "full only" "sleep 2"'
WARN=1 run --fast
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'NOTE: fast の検査が 1 秒を超えた' \
  && printf '%s' "$OUT" | sed -n '/NOTE: fast/,$p' | grep -qE '^ +[0-9]+s  slow$' \
  && ! printf '%s' "$OUT" | sed -n '/NOTE: fast/,$p' | grep -qE '^ +[0-9]+s  quick$'; } \
  && ok "C1: --fast で閾値を超えた fast の検査だけを挙げ、落とさない" || ng "C1"
WARN=1 run
printf '%s' "$OUT" | grep -q 'NOTE: fast の検査' && ng "C2" || ok "C2: フルの検査では言わない"
WARN=5 run --fast
printf '%s' "$OUT" | grep -q 'NOTE: fast の検査' && ng "C3" || ok "C3: 閾値（既定 5 秒）以内なら言わない"

# ---- C4〜C7: --only で表示名に合う検査だけ回す（決定 0015）----
checks 'check fast "lint a" "true"' 'check "unit b" "true"' 'check "unit c" "false"'
run --only 'unit b'
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=0 skipped=2'; } && ok "C4: --only に合う検査だけ回す" || ng "C4"
run --only 'lint|unit c'
{ [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=1 skipped=1'; } && ok "C5: --only は拡張正規表現。落ちれば終了コードも落ちる" || ng "C5"
run --fast --only 'unit'
printf '%s' "$OUT" | grep -q 'pass=0 fail=0 skipped=3' && ok "C6: --fast と --only の両方に合うものだけ" || ng "C6"
run --only
{ [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q -- '--only の後ろに'; } && ok "C7: --only の値が無ければ使い方を言って止まる" || ng "C7"

# ---- C8〜C13: 並列（--jobs / CHECK_JOBS / check serial。決定 0015）----
# 後に登録した検査ほど早く終わるようにして、表示が登録順になるかを見る
checks 'check "a" "sleep 2; echo out-a"' 'check "b" "sleep 1; echo out-b; exit 3"' 'check "c" "echo out-c"'
run --jobs 3
names="$(printf '%s\n' "$OUT" | sed -n 's/^── //p' | tr '\n' ' ')"
{ [ "$names" = "a b c " ] && [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'pass=2 fail=1' \
  && printf '%s' "$OUT" | sed -n '/^── b$/,/^── c$/p' | grep -q 'out-b' \
  && printf '%s' "$OUT" | sed -n '/^── b$/,/^── c$/p' | grep -q 'FAIL'; } \
  && ok "C8: 並列でも登録順に出し、各検査の出力はその見出しの下に出る。落ちれば終了コードも落ちる" || ng "C8"
# 所要はランナー自身が出す秒数で見る（外から測ると、負荷の高い PC ではプロセスの起動待ちが乗って揺れる。
# 2026-11-26 に C11 が外側 6 秒以上・ランナー 4 秒で落ちた）。直列なら 2 秒 × 3 件でランナーも 6 秒以上になる
runner_sec() { printf '%s' "$OUT" | sed -n 's/^harness check: .*(\([0-9]*\)s)$/\1/p' | tail -1; }
checks 'check "x" "sleep 2"' 'check "y" "sleep 2"' 'check "z" "sleep 2"'
run --jobs 3; el="$(runner_sec)"
{ [ "$RC" -eq 0 ] && [ -n "$el" ] && [ "$el" -lt 6 ]; } && ok "C9: 並列で回る（2 秒 × 3 件が 6 秒未満。実測 ${el}s）" || { OUT="$OUT
elapsed=${el}s"; ng "C9"; }
# serial: 走っている間に他の検査が走っていないことを、走っている印のファイルで確かめる
L="$WORK/locks"; mkdir -p "$L"
checks "check \"p1\" \"touch $L/p1; sleep 2; rm $L/p1\"" \
       "check serial \"s\" \"ls $L | grep -q . && { echo others-running; exit 1; }; touch $L/s; sleep 1; rm $L/s\"" \
       "check \"p2\" \"sleep 0.3; [ -e $L/s ] && { echo serial-still-running; exit 1; }; true\""
run --jobs 4
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'pass=3 fail=0'; } && ok "C10: check serial は他と同時に走らない" || ng "C10"
printf 'CHECK_JOBS=3\n' >"$P/.harness/checks.sh"
printf '%s\n' 'check "x" "sleep 2"' 'check "y" "sleep 2"' 'check "z" "sleep 2"' >>"$P/.harness/checks.sh"
run; el="$(runner_sec)"
{ [ "$RC" -eq 0 ] && [ -n "$el" ] && [ "$el" -lt 6 ]; } && ok "C11: checks.sh の CHECK_JOBS で並列になる（実測 ${el}s）" || ng "C11"
s0=$SECONDS; run --jobs 1; el=$((SECONDS - s0))
{ [ "$RC" -eq 0 ] && [ "$el" -ge 6 ]; } && ok "C12: --jobs 1 は CHECK_JOBS より優先して直列（実測 ${el}s）" || ng "C12"
checks 'check fast "f1" "true"' 'check "n1" "true"' 'check fast "f2" "false"'
run --fast --jobs 2
{ [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=1 skipped=1'; } && ok "C13: 並列でも --fast の絞り込みと集計は同じ" || ng "C13"

# ---- C14〜C17: 同じ作業ツリーでの二重起動の防止（決定 0015）----
checks 'check fast "f" "true"' 'check "slow" "sleep 3"'
( cd "$P" && bash "$RUNNER" >"$WORK/first.log" 2>&1 ) &
first=$!
sleep 1
s0=$SECONDS; run; el=$((SECONDS - s0)); wait "$first"; frc=$?
{ [ "$RC" -eq 0 ] && [ "$frc" -eq 0 ] && printf '%s' "$OUT" | grep -q '別の harness check' && [ "$el" -ge 4 ]; } \
  && ok "C14: 先の check が走っている間、後の check は待ってから回る（実測 ${el}s）" || ng "C14"
( cd "$P" && bash "$RUNNER" >"$WORK/first.log" 2>&1 ) &
first=$!
sleep 1
run --fast; wait "$first"
{ [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '別の harness check'; } && ok "C15: --fast は待たない（pre-commit を重い check の後ろで止めない）" || ng "C15"
LK="$(cd "$P" && git rev-parse --absolute-git-dir)/harness-check.lock"
mkdir -p "$LK" && echo 999999 >"$LK/pid"
checks 'check "q" "true"'
run
{ [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q '別の harness check'; } && ok "C16: 持ち主のプロセスが無いロックは引き継ぐ" || ng "C16"
[ ! -e "$LK" ] && ok "C17: 終わればロックを外す" || { OUT="lock remains: $LK"; ng "C17"; }

# ---- C18〜C25: 既定は差分に関係する検査だけ / --full と記録（1.8.0。決定 0015）----
g() { git -c user.email=t@t -c user.name=t "$@"; }
git init -q --bare "$WORK/o.git"; g clone -q "$WORK/o.git" "$WORK/r" 2>/dev/null
R="$WORK/r"; mkdir -p "$R/.harness" "$R/src" "$R/docs"
printf '%s\n' 'check "always" "true"' 'check on "src/" "src tests" "true"' 'check on "*.md" "md lint" "true"' \
  'check on "lib" "lib tests" "true"' >"$R/.harness/checks.sh"
echo a >"$R/src/a.sh"; echo r >"$R/README.md"; g -C "$R" add -A && g -C "$R" commit -q -m base && g -C "$R" push -q origin HEAD 2>/dev/null
runr() { OUT="$(cd "$R" && bash "$RUNNER" "$@" 2>&1)"; RC=$?; }
runr
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=0 skipped=3' && printf '%s' "$OUT" | grep -q '飛ばした検査 3 件'; } \
  && ok "C18: 差分が無ければ on の無い検査だけ回し、飛ばした件数を言う" || ng "C18"
echo b >>"$R/src/a.sh"
runr
{ printf '%s' "$OUT" | grep -q '^── src tests' && ! printf '%s' "$OUT" | grep -q '^── md lint'; } \
  && ok "C19: コミットしていない変更が on のパス（末尾 /）に当たる検査を回す" || ng "C19"
g -C "$R" commit -q -am src && echo n >"$R/docs/new.md"
runr
{ printf '%s' "$OUT" | grep -q '^── src tests' && printf '%s' "$OUT" | grep -q '^── md lint'; } \
  && ok "C20: push していないコミットと、追跡していない新しいファイル（グロブ *.md）も差分に入る" || ng "C20"
rm "$R/docs/new.md"; mkdir -p "$R/lib/x"; echo l >"$R/lib/x/y.sh"
runr
printf '%s' "$OUT" | grep -q '^── lib tests' && ok "C21: 末尾 / の無いディレクトリ名も、その下のファイルに当たる" || ng "C21"
rm -rf "$R/lib"; echo '# changed' >>"$R/.harness/checks.sh"
runr
{ printf '%s' "$OUT" | grep -q 'pass=4 fail=0 skipped=0' && ! printf '%s' "$OUT" | grep -q '差分に関係する'; } \
  && ok "C22: .harness/checks.sh 自体が変われば全部回す" || ng "C22"
GDR="$(cd "$R" && git rev-parse --absolute-git-dir)"
grep -q . "$GDR/harness-check-passed" 2>/dev/null && ok "C22b: 差分モードでも結果として全部回って通れば、通った記録を残す" || { OUT="記録が無い"; ng "C22b"; }
rm -f "$GDR/harness-check-passed"
echo u >"$R/untracked.txt"
runr --full
{ printf '%s' "$OUT" | grep -q 'pass=4' && printf '%s' "$OUT" | grep -q '追跡していない新しいファイル.*残さない' && [ ! -s "$GDR/harness-check-passed" ]; } \
  && ok "C23: --full でも追跡していない新しいファイルがあれば、通った記録を残さない" || ng "C23"
rm "$R/untracked.txt"
runr --full
g -C "$R" commit -q -am checks
{ printf '%s' "$OUT" | grep -q 'フルの検査が通ったことを記録した' && grep -q "^$(g -C "$R" rev-parse 'HEAD^{tree}')	" "$GDR/harness-check-passed"; } \
  && ok "C24: コミット前に --full が全部通れば、検査した中身を記録し、そのままコミットした先端の中身と一致する" || ng "C24"
runr --only 'md lint'
{ printf '%s' "$OUT" | grep -q 'pass=1 fail=0 skipped=3' && ! printf '%s' "$OUT" | grep -q '差分に関係する'; } \
  && ok "C25: --only は差分に関係なく、名前で選んだ検査を回す（記録はしない）" || ng "C25"

# ---- C26〜C33: --since（タスク単位の軽い検査）と related（1.11.0。決定 0015 の追補）----
S="$WORK/s"; mkdir -p "$S/.harness" "$S/src" "$S/docs" && git init -q "$S"
printf '%s\n' 'check "always" "true"' \
  'check on "src/" related "bash rel.sh" "unit" "bash full.sh"' \
  'check on "docs/" "docs lint" "true"' >"$S/.harness/checks.sh"
printf '%s\n' 'printf "%s\n" "$@" >rel.out' >"$S/rel.sh"
printf '%s\n' 'echo full >full.out' >"$S/full.sh"
printf '%s\n' 'rel.out' 'full.out' >"$S/.gitignore"
echo a >"$S/src/a.ts"; echo b >"$S/src/b.ts"; echo x >"$S/docs/x.md"
g -C "$S" add -A && g -C "$S" commit -q -m base
START="$(g -C "$S" rev-parse HEAD)"
runs() { rm -f "$S/rel.out" "$S/full.out"; OUT="$(cd "$S" && bash "$RUNNER" "$@" 2>&1)"; RC=$?; }
runs --since "$START"
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'pass=1 fail=0 skipped=2' && printf '%s' "$OUT" | grep -q "${START} からの差分"; } \
  && ok "C26: --since で差分が無ければ on の検査は飛ばす（remote が無くても使える）" || ng "C26"
echo a2 >>"$S/src/a.ts"; g -C "$S" commit -q -am a; echo n >"$S/src/n m.ts"
runs --since "$START"
{ [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^── unit (related: 2 files)' && [ ! -f "$S/full.out" ] \
  && [ "$(sort "$S/rel.out" | tr '\n' '|')" = "src/a.ts|src/n m.ts|" ] && ! printf '%s' "$OUT" | grep -q '^── docs lint'; } \
  && ok "C27: related の検査は、起点からのコミット・未追跡を含む変わったファイルだけを渡して回す（空白入りの名前も 1 引数）" || ng "C27"
GDS="$(cd "$S" && git rev-parse --absolute-git-dir)"
[ ! -s "$GDS/harness-check-passed" ] && ok "C28: --since はフルの検査の記録を残さない" || { OUT="記録が残った"; ng "C28"; }
rm "$S/src/n m.ts"; g -C "$S" rm -q src/b.ts
runs --since "$START"
{ [ "$RC" -eq 0 ] && [ -f "$S/full.out" ] && [ ! -f "$S/rel.out" ] && printf '%s' "$OUT" | grep -q '消したファイルがある'; } \
  && ok "C29: 消したファイルがあれば related ではなく本来のコマンドを回す" || ng "C29"
g -C "$S" commit -q -m rm-b
runs --since no-such-ref
[ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'コミットとして解決できない' && ok "C30: 解決できない ref は exit 2 で止まる" || ng "C30"
runs --since "$START" --full
[ "$RC" -eq 2 ] && ok "C31: --since と --full は一緒に使えない" || ng "C31"
runs --full
{ [ "$RC" -eq 0 ] && [ -f "$S/full.out" ] && [ ! -f "$S/rel.out" ] && printf '%s' "$OUT" | grep -q '^── unit$'; } \
  && ok "C32: --since の無いときは related を使わず本来のコマンドを回す" || ng "C32"
NOW="$(g -C "$S" rev-parse HEAD)"; echo y >"$S/docs/y.md"
runs --since "$NOW"
{ printf '%s' "$OUT" | grep -q '^── docs lint' && ! printf '%s' "$OUT" | grep -q '^── unit'; } \
  && ok "C33: 起点より前の変更は差分に入らない（run 全体ではなくタスクの分だけを見る）" || ng "C33"

echo
echo "tests/check-runner.sh: pass=$passed fail=$failed"
[ "$failed" = 0 ] || { printf '  failed: %s\n' "${failed_names[@]}"; exit 1; }
