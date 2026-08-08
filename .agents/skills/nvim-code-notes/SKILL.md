---
name: nvim-code-notes
description: >-
  Read and write Code Notes entries on a Neovim browser board over its
  local HTTP API (curl + jq). Use when the user opened Code Notes from
  Neovim (:CodeNotes / <leader>B) and wants AI-visible code-reading notes:
  add entries with file/line/text, read human/AI entries, or jump Neovim to an entry
  location. nvim の Code Notes 上で AI がコードリーディング用 entry を読み書きしたいときに使う。
---

# Neovim Code Notes

Code Notes は、AI / 人間がコードリーディング中のコメントを `file` / `line` / `lineEnd`
/ `col` / `text` の entry として置き、ブラウザ上で一覧・詳細・コード断片を見ながら該当位置へ
ジャンプするための nvim 機能。quickfix のような「場所付きリスト」だが、UI はブラウザで、AI と
人間が同じ HTTP API を通じて読み書きできる。

The browser page is for the human. Your job is to read existing entries, add focused entries,
and update or delete entries through the HTTP API below.

If no session is found, ask the user to open one in Neovim with `:CodeNotes` or `<leader>B`.

## 1. Find the session

Sessions are advertised in the nvim cache registry:

```bash
REPO=$(git rev-parse --show-toplevel)
REG="${XDG_CACHE_HOME:-$HOME/.cache}/nvim/code-notes/sessions.json"
PORT=$(jq -r --arg r "$REPO" '[.[] | select(.repoRoot==$r)] | sort_by(-.startedAt) | .[0].port // empty' "$REG")
BASE="http://localhost:$PORT"
curl -s "$BASE/api/session" | jq
```

- If `PORT` is empty, inspect all sessions with `jq . "$REG"` and pick by `repoRoot`, `cwd`, or `pid`.
- The same repo can be open in more than one nvim; prefer the most recently started session unless
  the user indicates a different window.
- `/api/session` returns `{repoRoot, port, version}`.
- `version` bumps on every entry change. Poll `/__version` to notice human/AI updates cheaply.

## 2. Read entries

```bash
curl -s "$BASE/api/entries" | jq '.entries'
curl -s "$BASE/api/entries?file=nvim/lua/config/foo.lua" | jq '.entries'
```

Each entry:

```json
{
  "id": "f1",
  "file": "nvim/lua/config/foo.lua",
  "line": 12,
  "lineEnd": 14,
  "col": 3,
  "text": "This block builds the browser-side code preview.",
  "author": "codex",
  "createdAt": 1786200000,
  "updatedAt": 1786200000,
  "code": {
    "startLine": 9,
    "endLine": 17,
    "highlightLine": 12,
    "highlightEndLine": 14,
    "text": "..."
  }
}
```

`file`, `line`, and `col` can be null for a general note, but prefer location-backed entries when
the human should be able to jump to code.
Use `lineEnd` for a multi-line range; omit it for a single-line entry. `endLine` and `line_end`
are accepted as aliases, but prefer `lineEnd`.
For location-backed entries, the API includes a small code context around `line`; the browser renders
that code in the detail pane and highlights `line` through `lineEnd`.

## 3. Add an entry

Use repo-relative paths. Keep `text` self-contained; there is no separate title/summary/body split.

```bash
curl -s -X POST "$BASE/api/entries" -H 'Content-Type: application/json' -d '{
  "file": "nvim/lua/config/foo.lua",
  "line": 12,
  "lineEnd": 14,
  "col": 3,
  "text": "This block builds the browser-side code preview.",
  "author": "codex"
}' | jq
```

On success you get `{ "entry": { ... } }`. Bad input returns `400` with `{ "error": "..." }`.

## 4. Replace or clear the board

Use bulk replace only when you are intentionally refreshing the whole investigation set.

```bash
curl -s -X POST "$BASE/api/entries/set" -H 'Content-Type: application/json' -d '{
  "items": [
    {"file":"a.lua","line":1,"text":"First entry","author":"codex"},
    {"file":"b.lua","line":9,"text":"Second entry","author":"codex"}
  ]
}' | jq

curl -s -X POST "$BASE/api/entries/clear" -H 'Content-Type: application/json' -d '{}' | jq
```

## 5. Update or delete

```bash
curl -s -X POST "$BASE/api/entries/update" -H 'Content-Type: application/json' \
  -d '{"id":"f1","text":"Updated explanation.","author":"codex"}' | jq

curl -s -X POST "$BASE/api/entries/delete" -H 'Content-Type: application/json' \
  -d '{"id":"f1"}' | jq
```

## 6. Jump Neovim to an entry

Usually the human clicks `Open in nvim` in the browser. You can also request it:

```bash
curl -s -X POST "$BASE/api/jump" -H 'Content-Type: application/json' \
  -d '{"file":"nvim/lua/config/foo.lua","line":12,"col":3}' | jq
```

Paths outside the repository root are rejected.
The server opens files through `:edit`, so the target file becomes a normal listed buffer and appears
in the user's tabline. If the file is already visible in the current tab, that existing editor window
is focused instead.

## Good usage

- Use this for a short, curated list of code-reading notes, explanations, and investigation results.
- Prefer one concrete point per entry.
- Do not dump long logs or full files into entries. Link them to the relevant file/line and keep
  `text` readable in a list row.
- Read existing entries before adding new ones so you do not duplicate the board.

## Troubleshooting

- **Empty `PORT`** — no board is open for this repo. Ask the user to run `:CodeNotes`.
- **`curl: connection refused`** — the board server was closed (`:CodeNotesClose` or nvim quit).
- **`400 path is outside the repository root`** — use a repo-relative path inside the current repo.
- **Browser not updating** — poll `/__version`; if it changes, re-read `/api/entries`.
