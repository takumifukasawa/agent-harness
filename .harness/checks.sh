# .harness/checks.sh — agent-harness リポジトリ自身の検査（seed: このプロジェクトが編集する）
#
# 書式:  check [fast] "<表示名>" "<コマンド>"
# 失敗出力には「どう直すか」を含める。

check fast "bash syntax: bin/harness"     "bash -n bin/harness || { echo 'bin/harness に構文エラー。上の行番号を見る。'; exit 1; }"
check fast "bash syntax: payload scripts" "for f in harness/scripts/*.sh harness/checks.seed.sh; do bash -n \"\$f\" || { echo \"\$f に構文エラー\"; exit 1; }; done"
check fast "json: templates"              "node -e 'for (const f of process.argv.slice(1)) JSON.parse(require(\"fs\").readFileSync(f,\"utf8\"))' harness/state-template/progress.json harness/state-template/stages.json harness/manifest.example.json harness/adapters/claude/settings.fragment.json || { echo 'JSON が壊れている。上のファイルを直す。'; exit 1; }"
check fast "skill name == dir"            "bad=0; for d in harness/skills/*/; do n=\$(basename \"\$d\"); fm=\$(sed -n 's/^name: *//p' \"\$d/SKILL.md\" | head -1); [ \"\$n\" = \"\$fm\" ] || { echo \"SKILL.md の name (\$fm) がディレクトリ名 (\$n) と違う。agentskills 仕様で一致が必要。\"; bad=1; }; done; exit \$bad"
check fast "AGENTS.core.md <= 60 lines"   "n=\$(wc -l < harness/AGENTS.core.md); [ \"\$n\" -le 60 ] || { echo \"AGENTS.core.md が \$n 行。目次であって百科事典ではない（DESIGN.md §2）。docs へ逃がす。\"; exit 1; }"
check fast "VERSION in CHANGELOG"         "v=\$(tr -d '\\r\\n' < VERSION); grep -q \"^## \\[\$v\\]\" CHANGELOG.md || { echo \"CHANGELOG.md に ## [\$v] の見出しが無い。版を上げたら CHANGELOG に節を書く（プロジェクト側で必要な作業も）。\"; exit 1; }"
check      "installed copies in sync"     "out=\$(bash .harness/bin/harness status); echo \"\$out\" | grep -qE '^  (managed|merge|generated) +MODIFIED' && { echo \"\$out\" | grep MODIFIED; echo 'このリポジトリでは .agents/skills 等は harness/ からの導入コピー。直すのは harness/ 側で、その後 bash bin/harness update で同期する。'; exit 1; } || true"
check      "init smoke test"              "T=\$(mktemp -d); mkdir -p \"\$T/p\" && cd \"\$T/p\" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init && bash \"\$OLDPWD/bin/harness\" init --source \"\$OLDPWD\" >/dev/null 2>&1 && bash .harness/bin/harness status | grep -qE '^  (managed|merge|generated) +MODIFIED' && { echo 'init 直後に MODIFIED がある'; rm -rf \"\$T\"; exit 1; }; rm -rf \"\$T\""
check      "seed checks are green"        "bash tests/seed.sh"
check      "doctor scenarios"             "bash tests/doctor.sh"
check      "update scenarios"             "bash tests/update.sh"
check      "doctor: FAIL 0"               "bash .harness/bin/harness doctor || { echo 'doctor が FAIL を報告した。上の FAIL 行の「→」に従って直す。'; exit 1; }"
check fast "manifest source is shared value" "src=\$(sed -n 's/^  \"source\": \"\([^\"]*\)\".*/\1/p' .harness/manifest.json | head -1); case \"\$src\" in http://*|https://*|ssh://*|git://*|git@*) ;; *) echo \"manifest.json の source が機械ローカルの絶対パス（\$src）。bash .harness/bin/harness update で共有値に戻す（決定 0004。機械ローカルのパスは .harness/source.local へ）\"; exit 1 ;; esac"

# bash 3.2 互換（決定 0006）。macOS 既定の bash はアップデートされない前提で、この 2 つを機械的に締め出す。
# 対象は bin/harness・harness/scripts/*.sh・tests/*.sh（tests/lint-bash-compat.sh 自身は自己参照になるため対象外）。
check fast "bash 3.2: no bash4+-only syntax" "bash tests/lint-bash-compat.sh forbidden-syntax"
check fast "bash 3.2: no unbraced var before non-ASCII" "bash tests/lint-bash-compat.sh nonascii-var"
