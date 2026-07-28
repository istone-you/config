# .config

Neovim・yazi・lazygit の設定ファイル群。

## nvim が依存する CLI ツール

`nvim/` 配下の自作機能が内部で呼び出しているツール。

| ツール | 用途 |
|---|---|
| `git` | git_panel, github_permalink, terminal など git 操作全般 |
| `gh` | `git_panel` の GitHub PR 取得・認証（branches.lua の PR 表示、pr.lua の PRパネル: 一覧/詳細/diff/checkout/ブラウザ表示） |
| `curl` | `git_panel/git.lua` の GitHub GraphQL API 呼び出し（PR情報取得） |
| `delta` | `git_panel` の diff 色付き表示（任意、無くても素のテキストにフォールバック） |
| `rg` (ripgrep) | `rg_fzf.lua` の全文検索・置換 |
| `fzf` | `rg_fzf.lua`（検索UI）、`explorer.lua`（ファイル検索） |
| `fd` | `rg_fzf.lua` / `explorer.lua` のファイル検索（`fd`/`fzf` の両方が必要） |
| `lazygit` | `lazygit.lua`（`<leader>lg` でターミナル起動） |
| `yazi` (>= 0.2.5) | `yazi.lua`（`--chooser-file` 利用、`<leader>y` / `<leader>cw`） |

## ローカル設定

`nvim/local.lua` はマシン固有の設定を書くファイルで、`.gitignore` に登録済み。存在する場合のみ読み込まれる。

現在サポートしているキー：

| キー | 説明 |
|------|------|
| `tsserver_path` | `typescript-language-server` が使う `tsserver.js` の絶対パス |

```lua
-- nvim/local.lua
return {
  tsserver_path = '/app/web/node_modules/typescript/lib/tsserver.js',
}
```
