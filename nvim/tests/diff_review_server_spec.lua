local T = dofile(TESTS_DIR .. '/helpers.lua')
local server = require('config.diff_review.server')
local comments = require('config.diff_review.comments')

local P = server._private

T.describe('diff_review/server.lua request parsing', function()
  T.it('returns nil until headers are complete', function()
    T.eq(P.parse_request('GET /api/diff HTTP/1.1\r\nHost: x'), nil)
  end)

  T.it('parses a GET with query string', function()
    local req = P.parse_request('GET /api/comments?file=a.txt&author=claude HTTP/1.1\r\nHost: x\r\n\r\n')
    T.eq(req.method, 'GET')
    T.eq(req.path, '/api/comments')
    T.eq(req.query, 'file=a.txt&author=claude')
  end)

  T.it('waits for the full body per Content-Length', function()
    local raw = 'POST /api/comments HTTP/1.1\r\nContent-Length: 10\r\n\r\n{"a":1}'
    T.eq(P.parse_request(raw), nil) -- only 7 of 10 bytes
    local full = 'POST /api/comments HTTP/1.1\r\nContent-Length: 7\r\n\r\n{"a":1}'
    local req = P.parse_request(full)
    T.eq(req.method, 'POST')
    T.eq(req.body, '{"a":1}')
  end)

  T.it('parses query pairs with url-decoding', function()
    T.eq(P.parse_query('file=src%2Fa.txt&x=hi%20there'), { file = 'src/a.txt', x = 'hi there' })
  end)

  T.it('decodes JSON bodies and rejects garbage', function()
    T.eq(P.decode_body('{"x":1}'), { x = 1 })
    T.eq(P.decode_body(''), {})
    T.eq(P.decode_body('not json'), nil)
  end)
end)

T.describe('diff_review/server.lua routing', function()
  T.it('serves the web page at /', function()
    local resp = server.response_for_request({ method = 'GET', path = '/', query = '', body = '' })
    T.contains(resp, '200 OK')
    T.contains(resp, 'Diff Review')
  end)

  T.it('serves diff and session JSON', function()
    server.set_session({ repo_root = '/app', source = 'worktree' })
    server.set_diff({ files = {} })
    local resp = server.response_for_request({ method = 'GET', path = '/api/session', query = '', body = '' })
    T.contains(resp, 'application/json')
    T.contains(resp, '"repoRoot":"/app"')
  end)

  T.it('serves per-view diffs via ?view=', function()
    server.set_diff({
      all = { files = { { path = 'a.txt' } } },
      unstaged = { files = { { path = 'u.txt' } } },
      staged = { files = { { path = 's.txt' } } },
    })
    local all = server.response_for_request({ method = 'GET', path = '/api/diff', query = 'view=all', body = '' })
    T.contains(all, 'a.txt')
    local staged = server.response_for_request({ method = 'GET', path = '/api/diff', query = 'view=staged', body = '' })
    T.contains(staged, 's.txt')
    local unstaged = server.response_for_request({ method = 'GET', path = '/api/diff', query = 'view=unstaged', body = '' })
    T.contains(unstaged, 'u.txt')
    -- 未知/無指定ビューは all にフォールバック
    local dflt = server.response_for_request({ method = 'GET', path = '/api/diff', query = '', body = '' })
    T.contains(dflt, 'a.txt')
  end)

  T.it('adds a comment via POST and lists it back', function()
    comments.reset()
    local before = server.version()
    local post = server.response_for_request({
      method = 'POST', path = '/api/comments', query = '',
      body = '{"file":"foo.txt","new_line":3,"body":"note","author":"claude"}',
    })
    T.contains(post, '200 OK')
    T.contains(post, '"author":"claude"')
    T.ok(server.version() > before, 'version should bump after adding a comment')

    local list = server.response_for_request({ method = 'GET', path = '/api/comments', query = '', body = '' })
    T.contains(list, '"body":"note"')
    T.contains(list, '"threads"')
  end)

  T.it('rejects an invalid comment with 400', function()
    comments.reset()
    local resp = server.response_for_request({
      method = 'POST', path = '/api/comments', query = '', body = '{"body":"no target or file"}',
    })
    T.contains(resp, '400 Bad Request')
    T.contains(resp, '"error"')
  end)

  T.it('rejects a malformed JSON body', function()
    local resp = server.response_for_request({
      method = 'POST', path = '/api/comments', query = '', body = 'not json',
    })
    T.contains(resp, '400 Bad Request')
  end)

  T.it('404s unknown paths and 405s unknown methods', function()
    T.contains(server.response_for_request({ method = 'GET', path = '/nope', query = '', body = '' }), '404')
    T.contains(server.response_for_request({ method = 'DELETE', path = '/', query = '', body = '' }), '405')
  end)
end)

T.describe('diff_review/server.lua live socket', function()
  T.it('round-trips a comment over a real TCP connection', function()
    comments.reset()
    server.set_session({ repo_root = '/app', source = 'worktree' })
    server.set_diff({ files = {} })

    local port
    for p = 27100, 27200 do
      if server.start(p) then port = p break end
    end
    T.ok(port, 'server should start on some port')
    local base = 'http://127.0.0.1:' .. port

    local function curl(args)
      local res = vim.system(vim.list_extend({ 'curl', '-s' }, args), { text = true }):wait()
      return res.stdout or ''
    end

    local post = curl({ '-X', 'POST', base .. '/api/comments',
      '-H', 'Content-Type: application/json',
      '-d', '{"file":"foo.txt","new_line":5,"body":"live note","author":"claude"}' })
    T.contains(post, '"body":"live note"')

    local list = curl({ base .. '/api/comments' })
    T.contains(list, 'live note')

    server.stop()
    T.ok(server.is_running() == false, 'server should be stopped')
  end)
end)

T.summary()
