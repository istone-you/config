-- 差分レビューの HTTP サーバ(libuv TCP、プラグイン不使用)。
--
-- 既存の browser(html.lua/markdown.lua)は GET 専用の静的サーバだが、こちらは AI が
-- コメントを書き込むため POST + JSON ボディまで扱う。HTTP レスポンス生成・content-type・
-- open_url・config は browser.util をそのまま使い回す(= 「既存のブラウザ表示機能の使い回し」)。
--
-- ルーティング(response_for_request)は state と comments/web を参照するだけの関数に切り出し、
-- ソケット無しでテストできるようにしている。

local M = {}
local browser = require('config.browser.util')
local http = require('config.browser.server')
local comments = require('config.diff_review.comments')
local web = require('config.diff_review.web')

local state = {
  server = nil,
  port = nil,
  host = nil,
  repo_root = nil,
  source = 'worktree',
  diff_models = { all = { files = {} }, unstaged = { files = {} }, staged = { files = {} } },
  diff_version = 0,
}

M.state = state

local EMPTY = { files = {} }

--- /__version 用。diff の再構築とコメント変更のどちらでも値が変わる。
function M.version()
  return state.diff_version + comments.version()
end

--- init 側が git から作り直した diff モデルを差し込む。
--- diffs は { all=, unstaged=, staged= } の 3 ビュー。後方互換で単一モデル({files=..})も受ける(all 扱い)。
function M.set_diff(diffs)
  if diffs and diffs.files and not diffs.all then diffs = { all = diffs } end
  state.diff_models = {
    all = (diffs and diffs.all) or EMPTY,
    unstaged = (diffs and diffs.unstaged) or EMPTY,
    staged = (diffs and diffs.staged) or EMPTY,
  }
  state.diff_version = state.diff_version + 1
end

function M.set_session(opts)
  opts = opts or {}
  if opts.repo_root ~= nil then state.repo_root = opts.repo_root end
  if opts.source ~= nil then state.source = opts.source end
end

local function json_response(status, tbl)
  return browser.http_response(status, 'application/json', vim.json.encode(tbl))
end

-- "a=1&b=hi%20there" -> { a='1', b='hi there' }
local function parse_query(query)
  local out = {}
  for pair in tostring(query or ''):gmatch('[^&]+') do
    local k, v = pair:match('^([^=]+)=?(.*)$')
    if k then out[browser.url_decode(k)] = browser.url_decode(v) end
  end
  return out
end

local function decode_body(body)
  if not body or body == '' then return {} end
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok or type(decoded) ~= 'table' then return nil end
  return decoded
end

-- /__vendor で配信を許可する同梱アセット(シンタックスハイライト用)。パストラバーサル防止。
local VENDOR_FILES = {
  ['highlight.min.js'] = true,
  ['highlight-theme.css'] = true,
}

local function handle_get(req)
  local path = req.path
  if path == '/' or path == '/index.html' then
    return browser.http_response('200 OK', 'text/html', web.render({ repo_root = state.repo_root }))
  end
  local vf = path:match('^/__vendor/([%w._-]+)$')
  if vf and VENDOR_FILES[vf] then
    return browser.vendor_response(vf)
  end
  if path == '/__version' then
    return browser.http_response('200 OK', 'text/plain', tostring(M.version()))
  end
  if path == '/api/session' then
    return json_response('200 OK', {
      repoRoot = state.repo_root,
      source = state.source,
      port = state.port,
      views = { 'all', 'unstaged', 'staged' },
      version = M.version(),
    })
  end
  if path == '/api/diff' then
    local view = parse_query(req.query).view or 'all'
    return json_response('200 OK', state.diff_models[view] or state.diff_models.all)
  end
  if path == '/api/comments' then
    local q = parse_query(req.query)
    local filter = {}
    if q.file and q.file ~= '' then filter.file = q.file end
    if q.author and q.author ~= '' then filter.author = q.author end
    return json_response('200 OK', {
      comments = comments.list(filter),
      threads = comments.threads(filter),
      version = M.version(),
    })
  end
  return browser.http_response('404 Not Found', 'application/json', vim.json.encode({ error = 'not found' }))
end

local function handle_post(req)
  local path = req.path
  local body = decode_body(req.body)
  if body == nil then
    return json_response('400 Bad Request', { error = 'invalid JSON body' })
  end

  if path == '/api/comments' then
    local comment, err = comments.add(body)
    if not comment then return json_response('400 Bad Request', { error = err }) end
    return json_response('200 OK', { comment = comment })
  end
  if path == '/api/comments/reply' then
    local comment, err = comments.reply(body)
    if not comment then return json_response('400 Bad Request', { error = err }) end
    return json_response('200 OK', { comment = comment })
  end
  if path == '/api/comments/delete' then
    local ok = comments.remove(body.id)
    if not ok then return json_response('404 Not Found', { error = 'comment not found' }) end
    return json_response('200 OK', { ok = true })
  end
  if path == '/api/comments/clear' then
    local filter = {}
    if body.file and body.file ~= '' then filter.file = body.file end
    if body.author and body.author ~= '' then filter.author = body.author end
    comments.clear(next(filter) and filter or nil)
    return json_response('200 OK', { ok = true })
  end
  return json_response('404 Not Found', { error = 'not found' })
end

--- ソケット非依存のルーティング本体。req = {method, path, query, body}
function M.response_for_request(req)
  if req.method == 'GET' then return handle_get(req) end
  if req.method == 'POST' then return handle_post(req) end
  if req.method == 'OPTIONS' then
    return browser.http_response('204 No Content', 'text/plain', '')
  end
  return json_response('405 Method Not Allowed', { error = 'method not allowed' })
end

function M.is_running()
  return state.server ~= nil
end

function M.server_url()
  if not state.port then return nil end
  return 'http://localhost:' .. tostring(state.port) .. '/'
end

function M.stop()
  http.stop(state)
end

--- port で listen 開始。成功で true、失敗で false, err。共通サーバ(browser/server.lua)を使う。
function M.start(port)
  if state.server and state.port == port then return true end
  if state.server then M.stop() end
  return http.start(state, port, {
    namespace = 'diff_review',
    default_host = '0.0.0.0', -- 既存 browser と同じ。Dev Container のポート転送で 127.0.0.1 だと届かないことがある
    handler = function(req) return M.response_for_request(req) end,
  })
end

M._private = {
  parse_request = http.parse_request,
  parse_query = parse_query,
  decode_body = decode_body,
  json_response = json_response,
}

return M
