# .config

Neovim 等の設定ファイル群。

## ルール

カスタムキーマップを追加・変更・削除したときは、必ず以下の両方を合わせて更新すること。

- `shortcuts.html` のカスタムキーマップセクション
- `lua/config/shortcuts.lua` の `🔧 カスタムキーマップ` セクション（`Space ?` で開くパネル）

Neovim の設定はプラグインを使わず、Lua で自作すること。

nvim の自作機能が新たに CLI ツールに依存するようになったときは、必ず `README.md` の「nvim が依存する CLI ツール」セクションに追記すること。

Neovim の自作機能を新規実装・変更したときは、必ず `nvim/tests/` にテスト（`*_spec.lua`）を追加・更新すること。`nvim/tests/run.sh` で実行できる（プラグイン不使用の自作ハーネス）。

## パスの扱い（macOS の /var → /private/var）

macOS では `/var` `/tmp` `/etc` が `/private/...` への symlink で、`vim.fn.tempname()` も `/var/folders/...` を返す。
`vim.fn.fnamemodify(path, ':p')` は **実在するパスかつ `/./` や `/../` を含むときだけ** symlink を解決するため、
同じディレクトリでも書き方次第で `/var/...` と `/private/var/...` の 2 通りが出てきてパス比較が壊れる。

- パスを組み立てるときは `:p` に渡す前に `vim.fs.normalize()` で `~` `./` `../` を畳んでおくこと。
  `vim.fn.fnamemodify(vim.fs.normalize(path), ':p')` の順にすれば symlink は解決されず一貫する。
- テストでパスを比較するときは、両辺を同じ作り方で組み立てること。片側だけ `./` 入りにしない。
- 意図的に実体パスへ寄せたい場合のみ `vim.fn.resolve()` を使い、両辺に等しく適用する。
