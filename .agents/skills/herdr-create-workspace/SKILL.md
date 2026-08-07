---
name: herdr-create-workspace
description: "Herdr で作業用の独立ワークスペースと Git worktree を作成するだけのスキル。ユーザーが『ワークスペースとワークツリーを作成』『作成のみ』などと依頼したときに使う。調査・実装・エージェント起動は行わない。herdr worktree create だけだと親リポジトリ配下の子になるため、トップレベルの別ワークスペースにする。Requires HERDR_ENV=1。"
---

# herdr-create-workspace

**Herdr のワークスペース**（サイドバーに並ぶ WS。例: `main` / `config` と同列）と、その cwd となる **Git worktree** を作る **だけの** スキル。
作成と結果報告以外はしない（調査・修正・エージェント起動・追加タブ作成は禁止）。

ここで言うワークスペースは IDE の workspace ではなく、**Herdr の `herdr workspace`** を指す。

## 前提

```bash
test "${HERDR_ENV:-}" = 1
```

失敗したら Herdr 外である旨を伝えて中止する。CLI 詳細は `herdr` スキル、または `herdr workspace` / `herdr worktree` のヘルプを見る。

## 禁止

- **`herdr worktree create` だけで完了扱いにしない**  
  作られる WS が `main` など親リポジトリ WS の **子** としてサイドバーにぶら下がる。
- 作成後に調査・実装・エージェント起動を始める
- 他人のワークスペースを閉じる（自分が作った子 WS の作り直しは可）
- `herdr worktree remove` で checkout を消す

## 手順

ラベルとブランチ名は依頼内容から決める。リポジトリ root は通常 `/app`。

### 1. worktree を作る

```bash
herdr worktree create --cwd /app --branch <branch> --label "<label>" --no-focus --json
```

控えるもの:

- `result.worktree.path`
- `result.workspace.workspace_id`（親の子として付いた一時 WS）

### 2. 子ワークスペースを閉じる

```bash
herdr workspace close <child-workspace-id>
```

### 3. main と同列の Herdr ワークスペースを作る

```bash
herdr workspace create --cwd <worktree-path> --label "<label>" --focus
```

### 4. 検証して報告し、終了する

```bash
herdr workspace list
herdr pane list --workspace <new-workspace-id>
```

成功条件:

- サイドバー / `workspace list` で `main` などと **同列**（親 WS の子としてネストしていない）
- ペインの `cwd` が `<worktree-path>`
- `git -C <worktree-path> branch --show-current` が意図ブランチ

失敗時: 当該 WS を `close` し手順 3 からやり直し。worktree が残っていれば手順 1 は再実行しない。

報告テンプレ（これ以上やらない）:

| 項目 | 値 |
|---|---|
| ワークスペース | `<id>` |
| ラベル | `...` |
| ブランチ | `...` |
| cwd | `<worktree-path>` |

## 既存 worktree がある場合

手順 1–2 を飛ばし、手順 3 だけ実行する。

```bash
herdr workspace create --cwd <existing-worktree-path> --label "<label>" --focus
```
