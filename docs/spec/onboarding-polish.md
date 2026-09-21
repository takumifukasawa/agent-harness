# onboarding-polish — 導入体験を仕上げる

状態: **最終レビュー中**。2026-09-21 起票、同日に未確定 2 件を合意して 3 タスクに分解し、全 done。観点 4 つのレビューを 1 回回した。

## 目的

2026-09-21 に**実プロジェクト（aesthetic-comparison）へ初めて実地導入**し、穴が 2 つ見えた。次に別のプロジェクトへ入れる人（人間でもエージェントでも）が同じところで止まらないようにする。

| 見えた穴 | 現状 |
|---|---|
| **導入先から「別のプロジェクトへの入れ方」が分からない** | 手順は agent-harness の `README.md` にしかない。配られる `AGENTS.md` の管理ブロックにも `harness` スキルにも init の案内が無く、毎回このリポジトリに戻る必要がある |
| **既存 docs との大文字小文字の衝突が黙って起きる**（tech-debt #13） | case を区別しない FS（macOS / Windows）では、既存の `docs/HANDOFF.md` があると seed の `docs/handoff.md` が配られないのに manifest には載る。`doctor` の存在チェックも同じ判定なので素通りし、**Linux に持っていくと二重になる** |

あわせて、導入した aesthetic-comparison 側の docs を、ハーネスの運用に乗る形へ寄せる。

## 受け入れ条件

### A. 導入先から init の手順が分かる

- A1. `harness` スキル（`/harness ...`）が、**別のプロジェクトへの導入手順**を案内できる。clone 済み / URL 直の 2 経路と、`init` の後にやること（検査の登録・spec・doctor）に触れる
- A2. 既存の案内（status / update / diff / check / doctor / upstream）を削らない
- A3. 正本（`harness/skills/harness/SKILL.md`）を直し、`bash bin/harness update` で導入コピーが同期されている（検査 "installed copies in sync" が pass）

### B. case 衝突を黙って通さない（tech-debt #13）

- B1. **case を区別しないファイルシステムで、seed の配布先と大文字違いの既存ファイルがあることを検出する**
- B2. 検出したとき、何が起きているか（雛形は配っていない / manifest には載る / 別 OS で二重になる）と直し方（`git mv` で寄せる）を出す
- B3. **case を区別するファイルシステムでは誤検知しない**（そこでは別ファイルとして正しく共存する）
- B4. 回帰を止める検査がある。**判定関数の単体テストで代える**（テストから case の区別を切り替えられないため）
- B5. 既存の init / update / doctor の判定と出力を壊さない（`check` 全件 pass、`doctor` の FAIL 0 を維持）

### C. 導入先（aesthetic-comparison）の docs をハーネスの形に寄せる

- C1. `docs/handoff.md` が `session-handoff` の形（現在地 / 状態 / NEXT / 未確定）になっている。**既存の引き継ぎ内容（Windows → Mac、private リポジトリ経由）を失わない**
- C2. **範囲は `docs/handoff.md` だけ**（2026-09-21 合意）。他の doc は索引に「ハーネスでの対応先」を書いてあるので、次にその doc を触るときに寄せる。**今は動かさない**

## 範囲外（やらないこと）

- `AGENTS.md` の管理ブロックに init 手順を書くこと（あのブロックは目次であって百科事典ではない。60 行の上限検査もある）
- case 衝突の**自動修復**（ファイルを勝手にリネームしない。ユーザーの資産なので検出と案内に留める）
- aesthetic-comparison のプロダクト側のコード（`app/` `scripts/`）

## 合意済みの決定（2026-09-21）

- **B の検出は `init` / `update` と `doctor` の両方に出す。** 配る瞬間に気づけるのが一番安く、clone した別 PC や導入後に大文字の doc を足したケースは `doctor` が拾う。落選: `doctor` だけ（init 直後に黙って通る）、`init`/`update` だけ（後から増えた衝突を拾えない）
- **C は `docs/handoff.md` だけ。** 他は索引に対応先を書いてあるので、次にその doc を触るときに寄せる。落選: spec と plans も動かす / 全部寄せる（どちらもユーザーの資産を大きく動かす。今すぐ得るものは「整う」だけで、運用上の必要が出ていない）

## 未確定事項（人間の判断待ち）

- なし。
