# .config

Neovim・yazi・lazygit の設定ファイル群。

## nvim が依存する CLI ツール

`nvim/` 配下の自作機能が内部で呼び出しているツール。

| ツール | 用途 |
|---|---|
| `git` | git_panel, github_permalink, terminal など git 操作全般 |
| `rg` (ripgrep) | `rg_fzf.lua` の全文検索・置換 |
| `fzf` | `rg_fzf.lua`（検索UI）、`explorer.lua`（ファイル検索） |
| `fd` | `explorer.lua` のファイル検索（`fd`/`fzf` の両方が必要） |
| `lazygit` | `lazygit.lua`（`<leader>lg` でターミナル起動） |
| `yazi` (>= 0.2.5) | `yazi.lua`（`--chooser-file` 利用、`<leader>y` / `<leader>cw`） |
| `bat` | `rg_fzf.lua` のプレビュー表示（任意、無くても動作する） |

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

## 動作確認

Neovim で対象ファイルを開いて `:LspInfo` を実行し、LSP が接続されているか確認する。
