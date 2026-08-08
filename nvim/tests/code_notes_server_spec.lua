local T = dofile(TESTS_DIR .. '/helpers.lua')
local server = require('config.code_notes.server')
local entries = require('config.code_notes.entries')
local util = require('config.nvim_api.util')
local browser_server = require('config.browser.server')

local function parse_response(raw)
  local status = raw:match('^HTTP/1%.1 (%d+)')
  local body = raw:match('\r\n\r\n(.*)$') or ''
  local ok, decoded = pcall(vim.json.decode, body)
  return tonumber(status), (ok and decoded or nil), body
end

local function call(req)
  return parse_response(server.response_for_request(req))
end

local function get(path, query)
  return call({ method = 'GET', path = path, query = query or '', body = '' })
end

local function post(path, tbl)
  return call({
    method = 'POST',
    path = path,
    query = '',
    body = type(tbl) == 'string' and tbl or vim.json.encode(tbl or {}),
  })
end

local function with_root(fn)
  local root = util.real(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  vim.fn.writefile({ 'one', 'two', 'three' }, root .. '/a.lua')
  vim.fn.writefile({ 'root one', 'root two', 'root three' }, root .. '/CLAUDE.md')
  server.set_session({ repo_root = root })
  entries.clear()
  local ok, err = pcall(fn, root)
  server.stop()
  entries.clear()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= '' and name:sub(1, #root) == root then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

local function tcp_request(port, raw, cb)
  local uv = vim.uv or vim.loop
  local client = uv.new_tcp()
  local chunks = {}
  client:connect('127.0.0.1', port, function(err)
    if err then cb(nil, err); return end
    client:read_start(function(read_err, chunk)
      if read_err then cb(nil, read_err); return end
      if chunk then
        chunks[#chunks + 1] = chunk
      else
        pcall(function() client:close() end)
        cb(table.concat(chunks))
      end
    end)
    client:write(raw)
  end)
end

T.describe('code_notes/server.lua routing', function()
  T.it('serves the page, session, version, and entries API', function()
    with_root(function(root)
      local page_status, _, page_body = get('/')
      T.eq(page_status, 200)
      T.contains(page_body, 'Code Notes')
      T.contains(page_body, 'id="showadd"')
      T.contains(page_body, 'id="modal"')
      T.contains(page_body, 'id="newloc"')
      T.contains(page_body, 'parseLocation')
      T.contains(page_body, 'const range=s.match')
      T.contains(page_body, 'const point=s.match')
      T.contains(page_body, '/api/entries/status')
      T.contains(page_body, '/api/entries/comment')
      T.contains(page_body, "a==='human'?'You'")
      T.contains(page_body, '/__vendor/highlight.min.js')
      T.contains(page_body, '/__vendor/highlight-theme.css')
      T.contains(page_body, 'hljs.highlight')
      T.contains(page_body, 'body{margin:0')
      T.contains(page_body, 'overflow:hidden')
      T.contains(page_body, 'height:calc(100vh - var(--header-h))')
      T.contains(page_body, 'grid-template-rows:minmax(180px,40vh) 1fr')

      local vendor_status, _, vendor_body = get('/__vendor/highlight.min.js')
      T.eq(vendor_status, 200)
      T.contains(vendor_body, 'highlight.js')
      T.eq(select(1, get('/__vendor/secret.js')), 404)

      local session_status, session = get('/api/session')
      T.eq(session_status, 200)
      T.eq(session.repoRoot, root)

      local status, json = post('/api/entries', {
        text = '調査結果',
        file = 'a.lua',
        line = 2,
        lineEnd = 3,
        col = 1,
        author = 'test',
      })
      T.eq(status, 200)
      T.eq(json.entry.text, '調査結果')
      T.eq(json.entry.file, 'a.lua')
      T.eq(json.entry.lineEnd, 3)
      T.eq(json.entry.code.highlightLine, 2)
      T.eq(json.entry.code.highlightEndLine, 3)
      T.contains(json.entry.code.text, 'two')

      local _, got = get('/api/entries')
      T.eq(#got.entries, 1)
      T.eq(got.entries[1].author, 'test')
      T.contains(got.entries[1].code.text, 'three')

      local point_status, point = post('/api/entries', {
        text = 'point location',
        file = 'a.lua',
        line = 2,
        col = 4,
        author = 'test',
      })
      T.eq(point_status, 200)
      T.eq(point.entry.line, 2)
      T.eq(point.entry.lineEnd, vim.NIL)
      T.eq(point.entry.col, 4)
      T.eq(point.entry.code.highlightLine, 2)
      T.eq(point.entry.code.highlightEndLine, 2)

      local root_status, root_note = post('/api/entries', {
        text = 'root file location',
        file = 'CLAUDE.md',
        line = 2,
        col = 4,
        author = 'test',
      })
      T.eq(root_status, 200)
      T.eq(root_note.entry.file, 'CLAUDE.md')
      T.eq(root_note.entry.line, 2)
      T.eq(root_note.entry.lineEnd, vim.NIL)
      T.eq(root_note.entry.col, 4)
      T.contains(root_note.entry.code.text, 'root two')

      local update_status, updated = post('/api/entries/update', {
        id = json.entry.id,
        text = '更新した説明',
      })
      T.eq(update_status, 200)
      T.eq(updated.entry.text, '更新した説明')

      local status_status, status_json = post('/api/entries/status', { id = json.entry.id, status = 'closed' })
      T.eq(status_status, 200)
      T.eq(status_json.entry.status, 'closed')

      local comment_status, comment_json = post('/api/entries/comment', {
        id = json.entry.id,
        text = 'human follow-up',
        author = 'human',
      })
      T.eq(comment_status, 200)
      T.eq(comment_json.comment.text, 'human follow-up')
      T.eq(comment_json.entry.comments[1].author, 'human')

      local comment_delete_status, comment_delete_json = post('/api/entries/comment/delete', {
        id = json.entry.id,
        commentId = comment_json.comment.id,
      })
      T.eq(comment_delete_status, 200)
      T.eq(#comment_delete_json.entry.comments, 0)

      local delete_status = post('/api/entries/delete', { id = json.entry.id })
      T.eq(delete_status, 200)
      T.eq(#select(2, get('/api/entries')).entries, 2)
    end)
  end)

  T.it('sets entries in bulk and clears them', function()
    with_root(function()
      local status, json = post('/api/entries/set', {
        items = {
          { text = 'one', file = 'a.lua', line = 1 },
          { text = 'no location' },
        },
      })
      T.eq(status, 200)
      T.eq(json.count, 2)
      T.eq(#select(2, get('/api/entries')).entries, 2)

      local clear_status = post('/api/entries/clear', {})
      T.eq(clear_status, 200)
      T.eq(#select(2, get('/api/entries')).entries, 0)
    end)
  end)

  T.it('validates paths and malformed bodies', function()
    with_root(function()
      local status, json = post('/api/entries', { text = 'bad', file = '/etc/hosts' })
      T.eq(status, 400)
      T.contains(json.error, 'outside the repository root')

      local bad_status, bad = post('/api/entries', '{壊れている')
      T.eq(bad_status, 400)
      T.contains(bad.error, 'invalid JSON body')

      local item_status, item_err = post('/api/entries/set', { items = { 'not an object' } })
      T.eq(item_status, 400)
      T.contains(item_err.error, 'entry item must be an object')

      local range_status, range_err = post('/api/entries', { text = 'bad range', file = 'a.lua', lineEnd = 3 })
      T.eq(range_status, 400)
      T.contains(range_err.error, 'line is required')

      T.eq(select(1, get('/nope')), 404)
      T.eq(select(1, call({ method = 'PUT', path = '/api/session', query = '', body = '' })), 405)
    end)
  end)

  T.it('jumps to a location in nvim', function()
    with_root(function(root)
      local status, json = post('/api/jump', { file = 'a.lua', line = 2, col = 1 })
      T.eq(status, 200)
      T.eq(json.ok, true)
      T.eq(util.real(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())), root .. '/a.lua')
      T.eq(vim.api.nvim_win_get_cursor(0), { 2, 0 })
      T.eq(vim.bo[vim.api.nvim_get_current_buf()].buflisted, true)
    end)
  end)

  T.it('jumps to an existing editor window in the current tab when the file is already visible', function()
    with_root(function(root)
      vim.cmd('edit ' .. vim.fn.fnameescape(root .. '/a.lua'))
      local left = vim.api.nvim_get_current_win()
      vim.cmd('vnew')
      local right = vim.api.nvim_get_current_win()
      vim.cmd('enew')

      local status, json = post('/api/jump', { file = 'a.lua', line = 3, col = 1 })
      T.eq(status, 200)
      T.eq(json.ok, true)
      T.eq(vim.api.nvim_get_current_win(), left)
      T.eq(util.real(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())), root .. '/a.lua')
      T.eq(vim.api.nvim_win_get_cursor(0), { 3, 0 })
      T.eq(vim.bo[vim.api.nvim_get_current_buf()].buflisted, true)
      T.ok(vim.api.nvim_win_is_valid(right), 'other editor window should not be destroyed')
    end)
  end)

  T.it('serves code context over a real TCP connection', function()
    with_root(function()
      local port
      for p = 28700, 28800 do
        if server.start(p) then
          port = p
          break
        end
      end
      T.ok(port, 'server should start on some port')
      local done, raw = false, nil
      tcp_request(port, table.concat({
        'GET /api/entries HTTP/1.1',
        'Host: 127.0.0.1',
        '',
        '',
      }, '\r\n'), function(resp)
        raw = resp
        done = true
      end)
      T.ok(vim.wait(1000, function() return done end), 'tcp response should arrive')
      local status, json = parse_response(raw)
      T.eq(status, 200)
      T.eq(#json.entries, 0)

      local body = vim.json.encode({ text = 'tcp code', file = 'a.lua', line = 1, lineEnd = 2 })
      done, raw = false, nil
      tcp_request(port, table.concat({
        'POST /api/entries HTTP/1.1',
        'Host: 127.0.0.1',
        'Content-Type: application/json',
        'Content-Length: ' .. tostring(#body),
        '',
        body,
      }, '\r\n'), function(resp)
        raw = resp
        done = true
      end)
      T.ok(vim.wait(1000, function() return done end), 'tcp post response should arrive')
      status, json = parse_response(raw)
      T.eq(status, 200)
      T.contains(json.entry.code.text, 'two')
      T.eq(json.entry.code.highlightLine, 1)
      T.eq(json.entry.code.highlightEndLine, 2)
      browser_server.stop(server.state)
    end)
  end)
end)

T.summary()
