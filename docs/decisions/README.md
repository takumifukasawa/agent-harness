# decisions — 決定記録

1 決定 = 1 ファイル。`NNNN-kebab-title.md`。書き換えず、覆す時は新しい決定を足して旧決定に「superseded by NNNN」を書く。

| # | タイトル | 状態 | 日付 |
|---|---|---|---|
| [0001](0001-workflow-is-the-main-subject.md) | このリポジトリの主役はワークフロー、配管は最小限 | 採用 | 2026-09-17 |
| [0002](0002-update-repairs-managed-files.md) | update は変更済みの managed / merge を「退避」ではなく「復元」する | 採用 | 2026-09-17 |

配管・ワークフローの個別の決定（配布方式、Windows 対応、再試行の方式 など 11 件）は `../../DESIGN.md` §10 の決定ログにある。新しい決定はここに 1 ファイルずつ足す。

## テンプレート

```markdown
# NNNN: タイトル

- 日付: YYYY-MM-DD
- 状態: 採用 / 廃止（superseded by NNNN）

## 背景
## 採用案
## 落選案と落選理由
## 影響・やり直す条件
```
