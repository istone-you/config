# .config

Neovim 等の設定ファイル群。

## ルール

カスタムキーマップを追加・変更・削除したときは、必ず以下の両方を合わせて更新すること。

- `shortcuts.html` のカスタムキーマップセクション
- `lua/config/shortcuts.lua` の `🔧 カスタムキーマップ` セクション（`Space ?` で開くパネル）

Neovim の設定はプラグインを使わず、Lua で自作すること。

nvim の自作機能が新たに CLI ツールに依存するようになったときは、必ず `README.md` の「nvim が依存する CLI ツール」セクションに追記すること。

Neovim の自作機能を新規実装・変更したときは、必ず `nvim/tests/` にテスト（`*_spec.lua`）を追加・更新すること。`nvim/tests/run.sh` で実行できる（プラグイン不使用の自作ハーネス）。
