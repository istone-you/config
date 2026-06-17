# .config

Neovim・yazi・lazygit の設定ファイル群。

## 必要なインストール

LSP サーバーを含むすべてのツールは mise.toml で管理されているため、以下を実行するだけでよい。

```bash
mise install
```

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
