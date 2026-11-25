#!/usr/bin/env bash
# harness check — プロジェクトが .harness/checks.sh に登録した検査を順に実行する。
# エージェントはこの結果を「実装完了の客観条件」として使う。LLM は使わない。
#
# 使い方:  bash .harness/scripts/check.sh [--fast] [--only <表示名の一部>]
#   --fast : pre-commit 用。checks.sh で `fast` と印を付けた検査だけ実行する。
#   --only <表示名の一部>: 表示名がこの拡張正規表現に合う検査だけ実行する（作業の途中で、変更に関係する
#            検査だけを回すため。完了の判定はフルの check で行う。決定 0015）。--fast と併用すると両方に合うものだけ。
#
# 各検査の所要時間（秒）と、遅い順の要約を最後に出す。どこが遅いかを推定でなく実測で掴むため
# （`docs/spec/check-speed.md` の A）。粒度は秒。macOS 既定の bash 3.2 と BSD date には
# ミリ秒を外部プロセス無しで取る手段が無いので、組み込みの $SECONDS を使う（決定 0006）。
#
# .harness/checks.sh の書き方（seed ファイル。プロジェクトが編集する）:
#   check fast "lint"        "npm run lint"
#   check      "unit tests"  "npm test"
#   check      "structure"   "bash scripts/structural-test.sh"
#
# 検査コマンドのエラー出力は「何が違反か」だけでなく「どう直すか / どの doc を読むか」を含めること。
# エージェントはエラー出力をそのまま文脈に取り込むので、そこが最も安い指示経路になる。
set -u

FAST=0; ONLY=""; CLI_JOBS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1; shift ;;
    --only) [ $# -ge 2 ] && [ -n "$2" ] || { echo "harness check: --only の後ろに表示名（の一部。拡張正規表現）を書く。例: --only 'push gate|lint'" >&2; exit 2; }
            ONLY="$2"; shift 2 ;;
    --only=*) ONLY="${1#--only=}"; shift ;;
    -j|--jobs) [ $# -ge 2 ] || { echo "harness check: $1 の後ろに並列数（数字か auto）を書く" >&2; exit 2; }
            CLI_JOBS="$2"; shift 2 ;;
    --jobs=*) CLI_JOBS="${1#--jobs=}"; shift ;;
    *) echo "harness check: 知らない引数（$1）。使い方: harness check [--fast] [--only '<表示名の一部>'] [--jobs N|auto]" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CHECKS="$ROOT/.harness/checks.sh"

if [ ! -f "$CHECKS" ]; then
  echo "harness check: $CHECKS が無い。harness init で seed されるはずのファイル。" >&2
  echo "  直し方: agent-harness の harness/checks.seed.sh を .harness/checks.sh にコピーし、検査を登録する。" >&2
  exit 2
fi

# ---- 二重起動の防止（決定 0015）----
# 同じ作業ツリーでフルの check が 2 つ同時に走ると、取り合って両方遅くなる（2026-11-24 に実際に起きた）。
# 後から来た方は、先の check が終わるまで待つ。--fast（pre-commit）は軽いので取らない（重い check の後ろで
# コミットを待たせない）。持ち主のプロセスがもう無いロックは引き継ぐ。HARNESS_CHECK_NO_LOCK=1 で取らない。
LOCKDIR=""; QUEUE_PIDS=""; QUEUE_TMPD=""
cleanup() {
  local p
  for p in $QUEUE_PIDS; do kill "$p" 2>/dev/null; done
  [ -n "$QUEUE_TMPD" ] && rm -rf "$QUEUE_TMPD"
  if [ -n "$LOCKDIR" ] && [ "$(cat "$LOCKDIR/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCKDIR"; fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
if [ "$FAST" = 0 ] && [ "${HARNESS_CHECK_NO_LOCK:-0}" != 1 ]; then
  LOCKDIR="$(cd "$ROOT" && git rev-parse --git-path harness-check.lock 2>/dev/null)" || LOCKDIR=""
  if [ -n "$LOCKDIR" ]; then
    case "$LOCKDIR" in /*) ;; *) LOCKDIR="$ROOT/$LOCKDIR" ;; esac
    said=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
      owner="$(cat "$LOCKDIR/pid" 2>/dev/null)"
      if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then rm -rf "$LOCKDIR"; continue; fi
      if [ "$said" = 0 ]; then
        echo "harness check: この作業ツリーで別の harness check（pid ${owner:-?}）が走っている。終わるのを待つ（取り合うと両方遅くなる）。"
        echo "  待たずに回すなら HARNESS_CHECK_NO_LOCK=1。走っている方が要らなければ止める。"
        said=1
      fi
      sleep 2
    done
    echo "$$" >"$LOCKDIR/pid"
  fi
fi

pass=0; fail=0; skipped=0
product=0    # seed 以外の検査（プロダクトの検査）の実行件数。0 なら pass は何も保証しない（決定 0012）
failed_names=()
timings=""   # "<秒>\t<表示名>" の行を貯める。遅い順の要約に使う（配列だと空のとき set -u で落ちる）
# --fast で、これより長くかかった fast の検査を最後に言う（pre-commit のたびに走るので、重い検査に fast を
# 付けるとコミットが遅くなる。2026-11-25 に 1 秒 → 約 4.6 分になっていた。決定 0015）。判定はしない（落とさない）
FAST_WARN_SEC="${HARNESS_FAST_WARN_SEC:-5}"
case "$FAST_WARN_SEC" in ''|*[!0-9]*) FAST_WARN_SEC=5 ;; esac
slow_fast=""

# ---- 並列数（決定 0015）----
# 優先順: --jobs > 環境変数 HARNESS_CHECK_JOBS > checks.sh の先頭に書いた CHECK_JOBS=N > 1（直列。従来どおり）。
# auto は CPU 数。並列のときも、出力は検査ごとにファイルへ分け、登録順に表示する（どれがなぜ落ちたか読めるように）。
# 他の検査と同時に走らせられない検査（同じポートや固定のファイルを使うなど）は check serial で登録する。
JOBS=""
resolve_jobs() {
  [ -n "$JOBS" ] && return 0
  local j="${CLI_JOBS:-${HARNESS_CHECK_JOBS:-${CHECK_JOBS:-1}}}"
  if [ "$j" = auto ]; then j="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"; fi
  case "$j" in ''|*[!0-9]*|0) echo "harness check: 並列数（${j}）は 1 以上の数字か auto。1（直列）で回す" >&2; j=1 ;; esac
  JOBS="$j"
}
Q_NAME=(); Q_CMD=(); Q_SERIAL=()

check() {
  local speed="" serial=0 name cmd
  while :; do
    case "${1:-}" in
      fast) speed="fast"; shift ;;
      serial) serial=1; shift ;;
      *) break ;;
    esac
  done
  name="${1:-}"; cmd="${2:-}"
  if [ -z "$name" ] || [ -z "$cmd" ]; then
    echo "harness check: checks.sh の書式エラー。check [fast] [serial] \"<表示名>\" \"<コマンド>\" の形で書く（name='$name')" >&2
    fail=$((fail + 1)); failed_names+=("(malformed check)"); return
  fi
  if [ "$FAST" = 1 ] && [ "$speed" != "fast" ]; then
    skipped=$((skipped + 1)); return
  fi
  if [ -n "$ONLY" ] && ! printf '%s\n' "$name" | grep -qE -- "$ONLY"; then
    skipped=$((skipped + 1)); return
  fi
  case "$name" in
    "docs index exists"|"doctor: FAIL 0") ;;   # seed（checks.seed.sh）の検査。名前を変えたら tests/seed.sh が落ちる
    *) product=$((product + 1)) ;;
  esac
  resolve_jobs
  if [ "$JOBS" -gt 1 ]; then
    Q_NAME+=("$name"); Q_CMD+=("$cmd"); Q_SERIAL+=("$serial"); return
  fi
  printf '── %s\n' "$name"
  local start=$SECONDS rc=0
  (cd "$ROOT" && bash -c "$cmd") || rc=$?
  record "$name" "$cmd" "$rc" $((SECONDS - start))
}

record() { # <表示名> <コマンド> <終了コード> <秒>  — 結果の行を出し、集計に足す
  local name="$1" cmd="$2" rc="$3" sec="$4"
  if [ "$rc" -eq 0 ]; then
    printf '   PASS (%ss)\n' "$sec"; pass=$((pass + 1))
  else
    printf '   FAIL (%ss) (%s)\n' "$sec" "$cmd"; fail=$((fail + 1)); failed_names+=("$name")
  fi
  timings="${timings}${sec}	${name}
"
  if [ "$FAST" = 1 ] && [ "$sec" -gt "$FAST_WARN_SEC" ]; then
    slow_fast="${slow_fast}    ${sec}s  ${name}
"
  fi
}

# 並列で回す（JOBS > 1 のとき、checks.sh を読み終えてから）。bash 3.2 には wait -n が無いので、
# 終わった印のファイルを短い間隔で見る。表示は登録順に、先頭から終わったものを流す。
run_queue() {
  local n=${#Q_NAME[@]} launched=0 printed=0 running i rc sec tmpd
  [ "$n" -gt 0 ] || return 0
  tmpd="$(mktemp -d)" || { echo "harness check: mktemp -d に失敗した（並列実行の置き場）" >&2; exit 2; }
  QUEUE_TMPD="$tmpd"   # 中断されたら cleanup が消す
  while [ "$printed" -lt "$n" ]; do
    running=0; i=$printed
    while [ "$i" -lt "$launched" ]; do [ -f "$tmpd/$i.done" ] || running=$((running + 1)); i=$((i + 1)); done
    while [ "$launched" -lt "$n" ] && [ "$running" -lt "$JOBS" ]; do
      # serial は単独で走らせる: 走っているものが終わるのを待ち、走っている間は次を始めない
      if [ "${Q_SERIAL[$launched]}" = 1 ] && [ "$running" -gt 0 ]; then break; fi
      if [ "$launched" -gt 0 ] && [ "${Q_SERIAL[$((launched - 1))]}" = 1 ] && [ ! -f "$tmpd/$((launched - 1)).done" ]; then break; fi
      (
        s=$SECONDS; r=0
        (cd "$ROOT" && bash -c "${Q_CMD[$launched]}") >"$tmpd/$launched.log" 2>&1 </dev/null || r=$?
        printf '%s %s\n' "$r" $((SECONDS - s)) >"$tmpd/$launched.tmp" && mv "$tmpd/$launched.tmp" "$tmpd/$launched.done"
      ) &
      QUEUE_PIDS="$QUEUE_PIDS $!"
      launched=$((launched + 1)); running=$((running + 1))
    done
    if [ -f "$tmpd/$printed.done" ]; then
      while [ "$printed" -lt "$launched" ] && [ -f "$tmpd/$printed.done" ]; do
        printf '── %s\n' "${Q_NAME[$printed]}"
        cat "$tmpd/$printed.log"
        read -r rc sec <"$tmpd/$printed.done"
        record "${Q_NAME[$printed]}" "${Q_CMD[$printed]}" "$rc" "$sec"
        printed=$((printed + 1))
      done
    else
      sleep 0.2 2>/dev/null || sleep 1
    fi
  done
  wait 2>/dev/null
  QUEUE_PIDS=""; QUEUE_TMPD=""; rm -rf "$tmpd"
}

# shellcheck disable=SC1090
source "$CHECKS"
run_queue

echo
echo "harness check: pass=$pass fail=$fail skipped=$skipped  (${SECONDS}s)"

# 遅い順の要約。どの検査を直せば効くかを、推定ではなく実測で決めるための材料
# （`docs/spec/check-speed.md` の A3）。秒未満は 0s と出るので、合計と食い違う分は
# 「1 秒未満の検査の積み上げ」と読む。
if [ -n "$timings" ]; then
  slow="$(printf '%s' "$timings" | sort -rn | head -5 | awk -F'\t' '{ printf "    %ss  %s\n", $1, $2 }')"
  if [ -n "$slow" ]; then
    echo "  遅い順（上位 5 件）:"
    printf '%s\n' "$slow"
  fi
fi
if [ -n "$slow_fast" ]; then
  echo "  NOTE: fast の検査が ${FAST_WARN_SEC} 秒を超えた（pre-commit のたびに走る）:"
  printf '%s' "$slow_fast"
  echo "    数秒で終わらない検査（シナリオテストなど）は、.harness/checks.sh で fast を外してフルの検査に回す。"
  echo "    検査は減らない（harness check では今までどおり走る）。"
fi
# seed の検査しか無いと pass は常に空振りする（決定 0012）。pre-commit（--fast）では毎回うるさいので出さない。
if [ "$FAST" = 0 ] && [ "$product" -eq 0 ]; then
  echo "  NOTE: プロダクトの検査が 0 件。この pass は何も保証しない。"
  echo "    テスト・lint・型検査など「緑なら完了」と言えるコマンドを .harness/checks.sh に"
  echo "    check \"<表示名>\" \"<コマンド>\" の形で登録する（例は同ファイル冒頭のコメント）。"
fi
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failed_names[@]}"
  echo "  失敗した検査の出力を読み、修復手順があればそれに従う。無ければ直した後に検査側へ手順を足す。"
  exit 1
fi
