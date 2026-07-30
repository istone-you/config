# .config

Neovim 等の設定ファイル群。

## nvim の機能

プラグインは使わず、すべて Lua で自作している（`nvim/lua/config/` 配下）。キーマップの全一覧は Neovim 上で `Space ?` を押すと開くパネルで確認できる。

### エディタ / UI

| 機能 | 説明 | 主なキー |
|---|---|---|
| `start_screen` | 起動時（ファイル未指定）に表示する編集不可のスタート画面。空の `[No Name]` バッファを置き換える | — |
| `tabline` | VSCode 風のバッファタブライン（Nerd Font アイコン付き） | `Tab` / `Shift-Tab` で切替、`Space q` で閉じる |
| `winbar` | 各ウィンドウ上端に開いているファイルの cwd 相対パスをパンくず表示 | — |
| `scrollbar` | 各ウィンドウにスクロールバーを表示 | — |
| `hidden_cursor` | 一覧選択系パネル（explorer / git パネル等）でテキストカーソルを隠し、カーソル行の強調だけで現在地を示す | — |
| `panel_focus` | 非フォーカスのパネルでは選択強調を沈め、どこにフォーカスがあるか分かるようにする | — |
| `hlchunk` | 現在カーソルがあるコードチャンク（囲みブロック）を縦線でハイライト | — |
| `autopairs` | 括弧・クォートを自動でペア補完（閉じの上でスキップ、空ペアの `<BS>` で両削除、括弧内 `<CR>` でインデント展開）。直前が `\` やクォートが単語隣接なら補完しない | 入力時に自動 |
| `surround` | 単語（`iw`）や選択範囲を括弧・クォートでトグル的に囲む/外す（開き括弧キー `( [ {` はスペース付き `( x )`、閉じキー `) ] }` はスペース無し `(x)`） | `Space s{文字}` |
| `context` | スクロールアウトした親スコープ行をスティッキーに表示 | — |
| `quit_confirm` | `:q` などで Neovim を終了する直前に確認ポップアップを出す（`:q!` など `!` 付きは即終了） | `:q` / `:qa` 等 |
| `auto_quit` | 実編集ウィンドウが無くなり、explorer や git パネル等のユーティリティ窓だけ残ったら自動終了 | — |

### ファイル / 検索 / ナビゲーション

| 機能 | 説明 | 主なキー |
|---|---|---|
| `explorer` | yazi 風のファイルエクスプローラ（右パネル・単一カラム）。作成 / リネーム / 削除 / コピー / 再帰検索など | `Space e` |
| `rg_fzf` | rg + fzf による全ファイル文字列検索 / ファイル名検索 / 置換 | `Space /`、`Space *` |

### Git

| 機能 | 説明 | 主なキー |
|---|---|---|
| `git_panel` | lazygit 風の git 管理パネル（中央ポップアップ）。Files / Commits / Branches / Stash / Worktree / PR を切替 | `Space g` |
| `git_blame` | GitLens 風のインライン git blame 表示 | — |
| `git_gutter` | VSCode 風にエディタ余白（ガター）へ git 差分を表示 | — |
| `github_permalink` | 現在行 / 選択行の GitHub パーマリンクを生成してコピー | `Space G` |

### LSP

| 機能 | 説明 | 主なキー |
|---|---|---|
| `lsp` | LSP の設定。ホバー / リネーム / コードアクション / フォーマット / 診断ジャンプ | `K`、`Space r n`、`Space c a`、`Space f`、`[d` / `]d`、`Space E` |
| `glance` | 定義元 / 参照元 / 型定義 / 実装をプレビューパネルで表示 | `g d` / `g r` / `g y` / `g i` |
| `namu` | LSP シンボル検索 | `Space s s` |

### ターミナル

| 機能 | 説明 | 主なキー |
|---|---|---|
| `terminal` | git リポジトリのルートで右側にターミナルを開く | `Space t` |
| `term_utils` | ターミナルバッファをタブライン / バッファ一覧から隠す。ターミナルモードから `Ctrl-h` でエディタへ戻る | `Ctrl-h` |

### その他

| 機能 | 説明 | 主なキー |
|---|---|---|
| `browser_markdown_preview` | マークダウンを既定ブラウザでプレビュー（保存時に自動リフレッシュ） | `Space m d` |
| `copy_with_path` | 選択コードをファイルパス（行番号付き）とともにコピー | `Space P` |
| `copy_all` | バッファ全内容をコピー | `Space A` |
| `shortcuts` | Neovim のショートカット一覧パネル | `Space ?` |

## nvim が依存する CLI ツール

`nvim/` 配下の自作機能が内部で呼び出しているツール。

| ツール | 用途 |
|---|---|
| `git` | git_panel, github_permalink, terminal など git 操作全般 |
| `gh` | `git_panel` の GitHub PR 取得・認証（branches.lua の PR 表示、pr.lua の PRパネル: 一覧/詳細/diff/checkout/ブラウザ表示） |
| `curl` | `git_panel/git.lua` の GitHub GraphQL API 呼び出し（PR情報取得） |
| `xdg-open` | `browser_markdown_preview.lua` のプレビューURLを既定ブラウザで開く（無くてもURLは通知される） |
| `delta` | `git_panel` の diff 色付き表示（任意、無くても素のテキストにフォールバック） |
| `rg` (ripgrep) | `rg_fzf.lua` の全文検索・置換 |
| `fzf` | `rg_fzf.lua`（検索UI）、`explorer.lua`（ファイル検索） |
| `fd` | `rg_fzf.lua` / `explorer.lua` のファイル検索（`fd`/`fzf` の両方が必要） |

## ローカル設定

`nvim/local.lua` はマシン固有の設定を書くファイルで、`.gitignore` に登録済み。存在する場合のみ読み込まれる。

現在サポートしているキー：

| キー | 説明 |
|------|------|
| `tsserver_path` | `typescript-language-server` が使う `tsserver.js` の絶対パス |
| `browser_markdown_preview.opener` | opener 実行ファイル名または絶対パス（未指定時は `xdg-open`） |
| `browser_markdown_preview.host` | プレビューサーバの bind host（未指定時は Dev Container から見やすい `0.0.0.0`） |

```lua
-- nvim/local.lua
return {
  tsserver_path = '/app/web/node_modules/typescript/lib/tsserver.js',
  browser_markdown_preview = {
    opener = 'xdg-open',
    host = '0.0.0.0',
  },
}
```
