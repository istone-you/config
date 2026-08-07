---
name: nvim-diff-review
description: >-
  Read and write inline review comments on a Neovim "Diff Review" session over its
  local HTTP API (curl + jq). Use when the user opened a diff review in their browser
  from Neovim (:DiffReview / <leader>R) and wants to discuss the diff with you — read
  the diff, read their comments, and leave/reply to inline comments on specific lines.
  差分レビュー(nvim の Diff Review)上で AI がコメントを読み書きしたいときに使う。
---

# Neovim Diff Review

Neovim の自作機能「Diff Review」は、作業ツリーの差分をブラウザ(difit 風)で開き、その差分上で
人間と AI が**双方向にコメント**をやりとりするためのもの。実体は nvim が立てるローカル HTTP
サーバで、コメントは JSON API で読み書きできる。ブラウザは自動でポーリングするので、AI が付けた
コメントは人間の画面にすぐ現れる。

The UI (the browser page) is for the human. Your job is to read the diff, read what the human
wrote, and leave focused inline comments through the HTTP API below.

If no session is found, ask the user to open one in Neovim with `:DiffReview` (or `<leader>R`).

## 1. Find the session (repo → port)

Sessions are advertised in a small registry file. Resolve the current repo and look up its port:

```bash
REPO=$(git rev-parse --show-toplevel)
REG="${XDG_CACHE_HOME:-$HOME/.cache}/nvim/diff-review/sessions.json"
PORT=$(jq -r --arg r "$REPO" '.[] | select(.repoRoot==$r) | .port' "$REG" | head -1)
BASE="http://localhost:$PORT"
echo "$BASE"
```

- If `PORT` is empty, list everything and pick by hand: `jq . "$REG"`.
- Confirm the session is live: `curl -s "$BASE/api/session" | jq` → `{repoRoot, source, port, version}`.
- `version` bumps on every diff rebuild and every comment change; poll it if you want to notice
  the human replying.

## 2. Read the diff

```bash
curl -s "$BASE/api/diff" | jq '.files[] | {path, status, added, deleted}'      # overview
curl -s "$BASE/api/diff" | jq '.files[] | select(.path=="web/src/App.tsx")'    # one file, full hunks
```

Structure: `files[] → {path, old_path, new_path, status(A|M|D|R), added, deleted, binary, hunks[]}`,
each hunk `→ {header, old_start, old_lines, new_start, new_lines, lines[]}`, each line
`→ {type: "context"|"add"|"del", content, old_line, new_line}` (the side that doesn't apply is `null`).

Use `new_line` to point at added/changed code, `old_line` to point at removed code.

## 3. Read comments

```bash
curl -s "$BASE/api/comments" | jq '.comments'                         # flat list
curl -s "$BASE/api/comments" | jq '.threads'                          # grouped: top-level + .replies[]
curl -s "$BASE/api/comments?file=web/src/App.tsx" | jq '.threads'     # one file
curl -s "$BASE/api/comments?author=human" | jq '.comments'            # only the human's notes
```

Each comment: `{id, file, side("old"|"new"), line, body, author, created_at, parent_id}`.
Top-level comments have `parent_id: null`; replies carry their thread's `parent_id`.

## 4. Add a comment

`file` is the path as shown in `/api/diff` (repo-relative). Give exactly one target — the convenient
`new_line` / `old_line`, or the explicit `side` + `line`. Use a stable `author` (e.g. `"claude"`) so
the human can tell your notes apart from theirs.

```bash
curl -s -X POST "$BASE/api/comments" -H 'Content-Type: application/json' -d '{
  "file": "web/src/App.tsx",
  "new_line": 128,
  "body": "This effect re-subscribes on every render; the deps array is missing `userId`.",
  "author": "claude"
}' | jq
```

Comment on a removed line instead:

```bash
curl -s -X POST "$BASE/api/comments" -H 'Content-Type: application/json' \
  -d '{"file":"api/handler.go","old_line":40,"body":"Was this guard intentional to drop?","author":"claude"}' | jq
```

Range (multi-line) comment — add `line_end` (must be >= the start line, same side):

```bash
curl -s -X POST "$BASE/api/comments" -H 'Content-Type: application/json' \
  -d '{"file":"web/src/App.tsx","new_line":40,"line_end":52,"body":"This whole block can be extracted into a hook.","author":"claude"}' | jq
```

On success you get `{ "comment": { "id": "c7", ... } }`. On bad input you get `400` with `{ "error": ... }`
(missing `file` / `body`, or no/invalid line target).

## 5. Reply in a thread

Replies inherit the thread's file/side/line — you only pass the `parent_id`:

```bash
curl -s -X POST "$BASE/api/comments/reply" -H 'Content-Type: application/json' \
  -d '{"parent_id":"c3","body":"Good point — I will add the dependency and re-test.","author":"claude"}' | jq
```

## 6. Manage your own notes (optional)

```bash
curl -s -X POST "$BASE/api/comments/delete" -H 'Content-Type: application/json' -d '{"id":"c7"}' | jq
curl -s -X POST "$BASE/api/comments/clear"  -H 'Content-Type: application/json' -d '{"author":"claude"}' | jq   # clear only yours
curl -s -X POST "$BASE/api/comments/clear"  -H 'Content-Type: application/json' -d '{}' | jq                    # clear all
```

## Reviewing well

- Read the whole diff first (`/api/diff`), then read any existing human comments before adding yours.
- Comment on the lines that matter — bugs, risks, unclear intent, missing tests — not every hunk.
- Keep each comment to one concrete point; put the target on the exact line it refers to.
- Prefer `new_line` for added/changed code and `old_line` for something that was removed.
- When the human replies (poll `/api/comments` or `/api/session` `version`), answer in the same thread
  with `reply`, don't open a new top-level comment.

## Troubleshooting

- **Empty `PORT`** — no session for this repo. Ask the user to run `:DiffReview` in that repo's Neovim.
- **`curl: connection refused`** — the session was closed (`:DiffReviewClose` or Neovim quit). The
  registry entry is pruned on quit; re-check `sessions.json`.
- **localhost blocked** — if the agent sandbox blocks localhost, retry with network/sandbox escalation.
- **`400 line must be a positive integer`** — you passed `new_line`/`old_line` as `null` (that side
  doesn't exist for the line). Point at the side that has a real number.
