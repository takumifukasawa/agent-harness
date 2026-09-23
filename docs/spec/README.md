# spec — 何を作るか（唯一の正）

「何を作るか」はここにだけ書く。会話で合意した変更は、ここに**書き戻す**まで「決まっていない」。
準備フェーズで依頼内容と 1 件ずつ突き合わせ、乖離を潰してから実装に入る。

「どう作るか」の規律は、効かせたいパスの `AGENTS.md` に書く（一覧: `../rules/README.md`）。spec と規律が矛盾したら**規律が勝つ**。

このリポジトリの「何を作るか」の大枠は `DESIGN.md` にある。個別機能の spec はここに 1 ファイルずつ置く。

状態列は手で書くと腐るので、**各 spec の状態欄と計画の置き場所が正**（`harness gc` の項目 11 が食い違いを報告する）。ここは索引なので、行の追加漏れだけを見る。

| ファイル | 範囲 | 状態 |
|---|---|---|
| [harness-doctor.md](harness-doctor.md) | `harness doctor`: 導入先の環境と導入状態の診断 | 完了（0.4.0 で出荷） |
| [cross-env-support.md](cross-env-support.md) | エージェント（Claude / Codex）と OS（Windows / macOS）を問わず同じように動く | 完了（フェーズ 1 / 2 とも。Windows × Codex は範囲外） |
| [check-speed.md](check-speed.md) | `harness check` が遅いことを実測で直す（計測 → 返済 → 並列化の順） | 完了（95s → 50s。B の 3 件目と C は[決定 0008](../decisions/0008-stop-optimizing-check-at-50s.md) で打ち切り） |
| [onboarding-polish.md](onboarding-polish.md) | 実プロジェクトへの初導入で踏んだ穴を塞ぐ | 完了 |
| [no-silent-failures.md](no-silent-failures.md) | 「黙って通る」経路を無くす（エラーの握り潰し、偽の緑） | 完了 |
| [writeback-sensors.md](writeback-sensors.md) | 統括の書き戻し漏れを文章ではなく検査（sensor）に落とす | 完了 |
| [handoff-writeback.md](handoff-writeback.md) | 計画を進めたのに handoff を放置していないか（tech-debt #18） | 合意済み |

## 1 つの spec の書き方

- 目的（誰の何が変わるか）
- 受け入れ条件（検査・テストで確認できる形。曖昧語を使わない）
- 範囲外（やらないこと）
- 未確定事項（人間の判断待ち。決まったら本文に移して消す）
