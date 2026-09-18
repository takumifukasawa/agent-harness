# architecture — このリポジトリの境界

## 全体の地図

```
bin/harness            CLI（bash）。init / update / status / diff / upstream / check / gc / self-install
harness/               ペイロード。プロジェクトに配られる中身（正本）
├── AGENTS.core.md     AGENTS.md の管理ブロック
├── docs-template/     docs/ の雛形（seed）
├── skills/            スキル（managed）
├── scripts/           check.sh / gc.sh / session-start.sh（managed）
├── state-template/    progress.json / stages.json（managed）
├── checks.seed.sh     .harness/checks.sh の雛形（seed）
└── adapters/          Claude / Codex の薄いアダプタ
.agents/ .claude/ .harness/ .githooks/ AGENTS.md CLAUDE.md docs/
                       ↑ このリポジトリ自身に harness init で導入した「導入コピー」（dogfood）
```

## 依存の向き（許される辺だけ）

- `bin/harness` → `harness/`（読むだけ。ペイロードの内容に依存するのは配置表 `plan()` と生成 `render_*()` のみ）
- `harness/skills/*` → `harness/docs-template/roles/*`、`harness/scripts/*`（パスで参照）
- 導入コピー（`.agents/` 等）→ `harness/`（一方向。**導入コピーを直接編集しない**。直すのは `harness/` 側、その後 `bash bin/harness update` で同期）
- `harness/` → 導入コピー への依存は無い

## 不変条件と強制手段

| 不変条件 | 強制手段 | 状態 |
|---|---|---|
| 導入コピーがペイロードと一致している | `.harness/checks.sh` の "installed copies in sync"（`harness status` に MODIFIED が無い） | 強制済 |
| `SKILL.md` の `name` がディレクトリ名と一致（agentskills 仕様） | checks.sh "skill name == dir" | 強制済 |
| `AGENTS.core.md` は 60 行以内（目次であって百科事典ではない） | checks.sh | 強制済 |
| 版を上げたら CHANGELOG に節がある | checks.sh "VERSION in CHANGELOG" | 強制済 |
| bash スクリプトは LF、`*.cmd` は CRLF | `.gitattributes` | 強制済 |
| 空のプロジェクトに init して直後の status が全部 unchanged | checks.sh "init smoke test" | 強制済 |
| ペイロードに Claude / Codex 固有の依存を入れない（アダプタ以外） | 未強制（レビューで見る） | 未強制 |
| manifest は 1 エントリ 1 行（bash の sed で読める） | `harness doctor` の B3（エントリ行数と `"path"` キー数を照合し、ズレを FAIL で報告。`.harness/checks.sh` "doctor scenarios" が検出ロジックの回帰を防ぐ） | 検出のみ（`doctor` の実行が前提。`harness check` に自動接続はしていない） |
| manifest に機械依存の絶対パスを書かない（決定 0004。共有値は URL、その PC / worktree だけの source は `.harness/source.local` か `HARNESS_SOURCE` へ） | `harness doctor` の B10（解決順で source が辿れなければ WARN、manifest に絶対パスが残っていれば別途 WARN。`tests/doctor.sh` の T09 節のシナリオが検出ロジックの回帰を防ぐ） | 強制済（`.harness/checks.sh` の fast 検査 "manifest source is shared value"） |

## 意図的に許している自由

- スキル本文の長さと構成。
- 検査の中身（各プロジェクトが `checks.sh` に何を登録するか）。
- 役割文の観点数（reviewer の 4 観点は既定であって固定ではない）。
