# .config

Neovim・yazi・lazygit などの設定ファイル群。

## ルール

カスタムキーマップを追加・変更・削除したときは、必ず以下の両方を合わせて更新すること。

- `shortcuts.html` のカスタムキーマップセクション
- `lua/config/shortcuts.lua` の `🔧 カスタムキーマップ` セクション（`Space ?` で開くパネル）

Neovim の設定はプラグインを使わず、Lua で自作すること。
