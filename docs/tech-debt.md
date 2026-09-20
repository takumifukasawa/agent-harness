# tech-debt — 既知の負債

<!-- 負債は高金利のローン。溜めて一括返済するより、小さく継続的に返す。
     `harness gc` はここに載っている項目の放置日数を報告する。返済したら行を消さず「返済済 (コミット)」にする。 -->

| # | 内容 | 影響範囲 | 起票日 | 状態 |
|---|---|---|---|---|
| 1 | `.claude/settings.json` の自動マージが `node` 前提。無い環境では断片を手で反映 | Claude アダプタ | 2026-09-17 | 未着手（jq 対応か、bash だけで済む簡易マージを検討） |
| 2 | `harness gc` の判定がヒューリスティック（日付の文字列パース、索引は `(` 前方一致） | gc | 2026-09-17 | 未着手（誤検知が出たら精度を上げる） |
| 3 | macOS で**実機確認した**（2026-09-20、Darwin 24.6 / arm64 / bash 3.2.57 / ja_JP.UTF-8）。`harness check` は pass=9 fail=4。**4 件中 3 件の根本原因は 1 つ**で、`declare -A`（`bin/harness:355`）が `invalid option` で **`init` を即死**させ、テストの setup が全滅していた。走査で挙げていた 4 箇所の実測結果: (a) **bash 4+ 必須は的中**（ただし doctor の B1 は FAIL を出すものの doctor 自身も完走しない）(b) **`sha256sum` は外れ。この機には `/sbin/sha256sum` が、`jq` も `/usr/bin/jq` にあった**（Apple 提供、macOS 15 以降）。古い macOS では依然リスク (c) `date -d` は `illegal option` を確認したが**未到達** (d) `sed -i` の引数必須も確認したが**未到達**。加えて**走査に無かった 5 つ目**: bash 3.2 + UTF-8 では `"$var日本語"` が `unbound variable` になる（**24 行**。`${var}` に括れば通る） | CLI 全体 / テスト | 2026-09-17 | **実装中**（題材 cross-env フェーズ 1。決定 0006 で「bash 3.2 を切らない」に確定。計画: `docs/plans/active/cross-env.md`） |
| 4 | GitHub からの `curl \| bash` init を実機で未確認（`file://` のみ） | 配布 | 2026-09-17 | 未着手 |
| 5 | このリポジトリに導入コピー（`.agents/` 等）とペイロード（`harness/`）が同居して二重に見える | 可読性 | 2026-09-17 | 受容（dogfood のため。`docs/architecture.md` に境界を明記） |
| 6 | `tests/doctor.sh` の下限が `doctor` 呼び出し 1 回 ≒ 3 秒（外部コマンドを多数呼ぶ）。T13 でフィクスチャ共有により 6m51s → 2m10s まで縮めたが、目標の 20〜40 秒には `harness/scripts/doctor.sh` 側の最適化が要る | テスト時間 | 2026-09-18 | 未着手（「外部コマンド数を減らせばさらに 3〜4 倍」は未検証の推定） |
| 7 | `source` の解決順のテストが `tests/doctor.sh` に同居している（本来は `tests/source.sh` に分けて `checks.sh` に登録するのが素直）。T09 の `files_scope` の制約による | テスト構成 | 2026-09-18 | 未着手（低優先。分けるなら別タスク） |
