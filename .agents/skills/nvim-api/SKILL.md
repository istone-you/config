---
name: nvim-api
description: >-
  Query the user's running Neovim over its local HTTP API (curl + jq). Three independent uses:
  (a) resolve symbols through the already-indexed LSP — definition, references, hover, document
  and workspace symbols, code actions — instead of guessing with grep; (b) read live diagnostics
  instead of re-running a type-checker to find out what is currently broken; (c) push a list of
  findings into the quickfix list for the human to browse and batch-edit with :cdo. Pick only the
  one you need. 起動中の nvim の LSP・診断・quickfix を HTTP API 経由で使う（3 つは独立）。
---

# Neovim API

起動中の nvim が既に持っている情報を AI へ開く読み取り口。実体はローカル HTTP サーバで、
nvim 起動時に 127.0.0.1 の空きポートで自動的に立ち上がる。

**用途は 3 つあり、互いに独立している。必要なものだけ使えばよい。**

| やりたいこと | 読む節 | 代表的な入口 |
|---|---|---|
| シンボルの定義・参照・型を正確に知る | [コードを追う](#コードを追う-lsp) | `POST /api/lsp/references` |
| いま何が壊れているか知る | [診断を読む](#診断を読む) | `GET /api/diagnostics/summary` |
| 人間がいま選択/表示している文脈を読む | [現在の選択範囲を読む](#現在の選択範囲を読む) | `GET /api/editor/selection?fallback=context` |
| 調べた結果を人間に渡す | [quickfix に置く](#quickfix-に置く) | `POST /api/qflist` |

なぜ nvim 経由なのか:

- **LSP はスコープで解決する。grep は文字列でしか照合できない。** このリポジトリだけでも
  `function M.open` は 19 個ある。grep では `M.open()` の呼び出しがどのモジュールのものか
  区別できず、そのたびにファイルを開いて確認する羽目になる。`/api/lsp/references` なら
  正解だけが 1 回で返る。TypeScript の `import { open as openPanel }` のようなエイリアスは
  grep では原理的に追えないが、LSP は追える。
- **言語サーバはもう温まっている。** tsserver や gopls のインデックスを自前で立て直すと
  数十秒〜数分かかる。nvim に常駐しているものへ相乗りすれば初手から速い。
- **診断は再実行しなくても読める。** `tsc` や `eslint` を回し直さずに、いま何が赤いかが分かる。

---

## まず（全機能に共通）

### セッションを見つける（repo → port）

```bash
REPO=$(git rev-parse --show-toplevel)
REG="${XDG_CACHE_HOME:-$HOME/.cache}/nvim/nvim-api/sessions.json"
PORT=$(jq -r --arg r "$REPO" '[.[] | select(.repoRoot==$r)] | sort_by(-.startedAt) | .[0].port // empty' "$REG")
BASE="http://localhost:$PORT"
curl -s "$BASE/api/session" | jq
```

- 同じリポジトリを複数の nvim で開いている場合、エントリは複数出る（上の jq は最後に起動した
  ものを選ぶ）。狙いを外していそうなら `jq . "$REG"` で全部見て `pid` や `cwd` で選び直す。
- `PORT` が空なら、そのリポジトリで nvim が動いていないか自動起動が切られている。
  ユーザーに `:NvimApiStart` を実行してもらうこと。
- `/api/session` は `{root, port, pid, nvim, startedAt, capabilities}` を返す。

### パスと位置の決まり

- `file` はリポジトリ root からの相対パス（root 内を指す絶対パスでも可）。
- 位置はすべて **1-based**（`line` は 1 行目が 1、`col` はバイト桁で 1 桁目が 1）。
- **root の外は既定で拒否**（`400 path is outside the repository root`）。絶対パスでも `../`
  でも同じ。nvim にリポジトリ外のファイルを読ませる抜け道を作らないため。
  LSP が**返してくる**パス（Go の stdlib や GOPATH 内の定義元など）は制限の対象外で、
  `locations` にそのまま絶対パスで出る。制限がかかるのは投げる入力パスだけ。

---

## コードを追う (LSP)

**使う場面**: 「この関数を消していいか」「シグネチャを変えたら何が壊れるか」「この値は何型か」。
grep で当たりを付ける前にここへ来る。grep の「見つからなかった」を「使われていない」と読むのが
最も危険な誤りで、それを避けるための節。

```bash
# 参照（本命。grep の代わりに使う）
curl -s -X POST "$BASE/api/lsp/references" -H 'Content-Type: application/json' \
  -d '{"file":"lua/config/diff_review/init.lua","line":143,"col":11}' | jq '.locations'

# 定義へ
curl -s -X POST "$BASE/api/lsp/definition" -H 'Content-Type: application/json' \
  -d '{"file":"lua/config/diff_review/init.lua","line":143,"col":11}' | jq

# 型・シグネチャ・ドキュメント
curl -s -X POST "$BASE/api/lsp/hover" -H 'Content-Type: application/json' \
  -d '{"file":"web/src/App.tsx","line":128,"col":9}' | jq -r '.hover'
```

`definition` / `references` は `{locations: [{file, line, col, end_line, end_col, text}], count}`
を返す。`text` はその行の中身なので、位置を見てからファイルを開き直す必要はたいてい無い。
`references` は既定で宣言自身も含む（`"includeDeclaration": false` で外せる）。

ファイル構造とプロジェクト全体のシンボル検索:

```bash
# 大きいファイルは全部読む前にこれで構造だけ取る
curl -s -X POST "$BASE/api/lsp/document_symbols" -H 'Content-Type: application/json' \
  -d '{"file":"lua/config/problems.lua"}' | jq '.symbols[] | {name, kind, container, line}'

curl -s -X POST "$BASE/api/lsp/workspace_symbols" -H 'Content-Type: application/json' \
  -d '{"query":"DiffReview"}' | jq '.symbols'
```

`document_symbols` は階層を平坦化して返し、親を `container`（`M.open` なら `"M"`）で示す。

いま直せるものを一覧する（適用はしない。実際の修正は通常の編集で行い、差分に出すこと）:

```bash
curl -s -X POST "$BASE/api/lsp/code_actions" -H 'Content-Type: application/json' \
  -d '{"file":"web/src/App.tsx","line":40,"col":1}' | jq '.actions'
```

**未ロードのファイルについて**: `/api/lsp/*` は指定された `file` を自動でロードして LSP の
アタッチを待つので、通常は事前準備は要らない。ただし `workspace_symbols` はプロジェクト全体を
見るため、先にその言語のファイルを開かせておくと結果が安定する。

```bash
curl -s -X POST "$BASE/api/buffers/load" -H 'Content-Type: application/json' \
  -d '{"files":["web/src/App.tsx","web/src/api.ts"]}' | jq
```

---

## 診断を読む

**使う場面**: 自分が編集した直後、テストを回す前。型エラーや未定義参照はここで潰せる。

```bash
curl -s "$BASE/api/diagnostics/summary" | jq                      # まずこれ。ファイル別の件数
curl -s "$BASE/api/diagnostics?severity=error" | jq '.diagnostics'
curl -s "$BASE/api/diagnostics?file=web/src/App.tsx" | jq '.diagnostics'
```

- `summary` は `{files: [{file, error, warn, info, hint, total}], totals, total}`。問題の多い
  ファイル順に並ぶ。**生の診断を全部引く前にこちらを見ること**（数千件になることがある）。
- `/api/diagnostics` は既定で 200 件まで。切られたときは `truncated: true` が立つので、
  `file=` や `severity=` で絞る。`max=` で上限を変えられる。
- `severity` は `error` / `warn` / `info` / `hint`。指定した重要度**以上**が返る。

**自分でファイルを編集した直後に読むときの注意**: nvim のバッファはまだディスクの変更を
知らず、LSP も診断を出し直していない。`refresh=1` を付けると読み直したうえで少し待つ。

```bash
curl -s "$BASE/api/diagnostics?refresh=1&wait_ms=800&severity=error" | jq
```

診断は「サーバーが報告したぶん」しか無い。特定ファイルを確実に見たいときは先に
`/api/buffers/load` でロードさせること。手動で取り込み直したいだけなら
`curl -s -X POST "$BASE/api/refresh" -d '{}'`。

---

## quickfix に置く

**使う場面**: 調べた結果を人間に渡したいとき。**修正そのものを代行せず、直す判断を人間に
残したいときに使う。** 3 件以下ならチャットに書いたほうが速い。

```bash
curl -s -X POST "$BASE/api/qflist" -H 'Content-Type: application/json' -d '{
  "title": "旧 API の残り 3 件",
  "items": [
    {"file":"web/src/App.tsx","line":128,"col":9,"text":"openPanel の旧シグネチャ","severity":"warn"},
    {"file":"web/src/api.ts","line":40,"text":"移行漏れ","severity":"error"}
  ]
}' | jq
```

`severity`（`error`/`warn`/`info`/`hint`）は quickfix の type 欄になり、表示に色が付く。
既定で quickfix ウィンドウを開くが、カーソルは人間のいたウィンドウに残る（`"open": false` で
開かないようにもできる）。

人間側は `Space l` でパネルを開閉し、中を j/k + Enter で辿る。`:cdo {cmd}` を使えば
**あなたが絞り込んだ集合にだけ**一括編集をかけられる。grep 由来の全件ではなく、判断を通した
集合に対して機械的な編集ができるのがこの口の価値。

```bash
curl -s "$BASE/api/qflist" | jq                          # いま入っているもの（別の AI も読める）
curl -s -X POST "$BASE/api/qflist/clear" -d '{}' | jq    # 空にして閉じる
```

`GET` があるので、エージェント間の受け渡しにも使える（調査役が置き、実装役が読む）。

---

## 現在の選択範囲を読む

**使う場面**: ユーザーが「このへん」「選択しているところ」と言っているとき。ディスクではなく
nvim のバッファから読むので、未保存の編集内容も含まれる。

```bash
curl -s "$BASE/api/editor/selection?fallback=context&context=5" | jq
```

返り値は現在バッファの `file`、カーソル `line` / `col`、`mode`、`modified` と、
選択範囲またはカーソル周辺の本文。

- Visual / Select mode 中なら `selection.active: true` になり、`selection.range` と
  `selection.text` を返す。
- 選択がないときに `fallback=context` を付けると、カーソル前後 `context` 行を
  `context.text` として返す（既定 5 行）。
- `range.end_col` は 1-based の終端位置（exclusive）。`start_col` から `end_col` の手前までが範囲。

---

## その他の口

```bash
curl -s "$BASE/api/buffers" | jq '.buffers[] | {file, filetype, modified, lsp}'  # 今開いているもの
```

`modified: true` のファイルは人間が未保存で編集中。ディスクの内容と食い違うので、その前提で話すこと。

---

## つまずいたとき（全機能に共通）

- **`PORT` が空** — そのリポジトリで nvim が動いていない。`:NvimApiStart` を頼む。
- **`curl: connection refused`** — nvim が終了済み。レジストリのエントリは終了時に消えるが、
  強制終了だと残ることがある。`/api/session` が返らなければ死んでいる。
- **`409 no LSP client attached`** — その言語のサーバが無いか初期化中。**空の結果と混同しない。**
  「参照 0 件」ではない。`timeout_ms` を上げて再試行する。
- **`409 LSP request timed out`** — 既定 5 秒で打ち切った。大きなファイルの `document_symbols` や、
  インデックス中の `workspace_symbols` で起きる。`"timeout_ms": 20000` などに上げる。
- **`400 line must be a positive integer (1-based)`** — 0-based のまま渡している。
- **`400 path is outside the repository root`** — リポジトリ外を指している。root 相対に直す。
  意図的に外を見たい場合はユーザーに `vim.g.nvim_api_allow_outside_root = true` を頼む。
- **`504 request timed out inside nvim`** — nvim 側が 15 秒応答しなかった保険。通常は出ない。
- **参照が明らかに少ない** — 対象ファイルがロードされた直後で、サーバーがまだプロジェクト全体を
  見ていない可能性がある。`/api/buffers/load` で関係ファイルを温めてから再試行する。
- **localhost がブロックされる** — サンドボックスが localhost を塞いでいる場合はネットワーク
  許可を上げて再試行する。
