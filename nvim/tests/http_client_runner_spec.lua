local T = dofile(TESTS_DIR .. '/helpers.lua')
local runner = require('config.http_client.runner')

local function args_string(args)
  return table.concat(args, ' ')
end

local function index_of(args, value)
  for i, a in ipairs(args) do
    if a == value then return i end
  end
  return nil
end

T.describe('http_client curl 引数', function()
  T.it('GET は -i -X GET と URL を最後に置く', function()
    local args = runner.build_curl({ method = 'GET', url = 'https://example.com/a', headers = {} })
    T.eq(args[1], 'curl')
    T.contains(args, '-i')
    T.eq(args[index_of(args, '-X') + 1], 'GET')
    T.eq(args[#args], 'https://example.com/a')
    T.contains(args_string(args), '--max-time 30')
  end)

  T.it('ヘッダを -H で渡す', function()
    local args = runner.build_curl({
      method = 'GET',
      url = 'https://example.com',
      headers = { { 'Accept', 'application/json' }, { 'X-A', '1' } },
    })
    T.eq(args[index_of(args, 'Accept: application/json') - 1], '-H')
    T.contains(args, 'X-A: 1')
  end)

  T.it('ボディは標準入力（@-）で渡し、JSON なら Content-Type を補う', function()
    local args = runner.build_curl({
      method = 'POST', url = 'https://example.com', headers = {}, body = '{"a":1}',
    })
    T.eq(args[index_of(args, '--data-binary') + 1], '@-')
    T.contains(args, 'Content-Type: application/json')
  end)

  T.it('Content-Type が指定済みなら補わない', function()
    local args = runner.build_curl({
      method = 'POST',
      url = 'https://example.com',
      headers = { { 'content-type', 'text/plain' } },
      body = '{"a":1}',
    })
    T.eq(index_of(args, 'Content-Type: application/json'), nil)
  end)

  T.it('ディレクティブが -L / -k / --max-time になる', function()
    local args = runner.build_curl({
      method = 'GET', url = 'https://example.com', headers = {},
      directives = { follow = true, insecure = true, timeout = 5 },
    })
    T.contains(args, '-L')
    T.contains(args, '-k')
    T.contains(args_string(args), '--max-time 5')
  end)

  T.it('HEAD は -X HEAD ではなく -I を使う', function()
    local args = runner.build_curl({ method = 'HEAD', url = 'https://example.com', headers = {} })
    T.contains(args, '-I')
    T.eq(index_of(args, '-i'), nil)
  end)

  T.it('curl_command はそのまま貼れる文字列にする', function()
    local cmd = runner.curl_command({
      method = 'POST',
      url = 'https://example.com/a b',
      headers = { { 'X-A', 'v 1' } },
      body = '{"a":1}',
    })
    T.contains(cmd, "'X-A: v 1'")
    T.contains(cmd, "'https://example.com/a b'")
    T.contains(cmd, "--data-binary '{\"a\":1}'")
    T.eq(cmd:find('__NVIM_HTTP_STATS__'), nil)
  end)
end)

T.describe('http_client レスポンス解析', function()
  T.it('ヘッダとボディを分ける', function()
    local res = runner.parse_response(
      'HTTP/1.1 201 Created\r\ncontent-type: application/json\r\nx-a: 1\r\n\r\n{"id":1}')
    T.eq(res.status_code, 201)
    T.eq(res.status_text, 'Created')
    T.eq(res.headers, { { 'content-type', 'application/json' }, { 'x-a', '1' } })
    T.eq(res.body, '{"id":1}')
  end)

  T.it('リダイレクト時は最後のヘッダブロックを採用する', function()
    local res = runner.parse_response(table.concat({
      'HTTP/1.1 301 Moved Permanently\r',
      'location: https://example.com/next\r',
      '\r',
      'HTTP/1.1 200 OK\r',
      'content-type: text/plain\r',
      '\r',
      'done',
    }, '\n'))
    T.eq(res.status_code, 200)
    T.eq(runner.header(res, 'Content-Type'), 'text/plain')
    T.eq(res.body, 'done')
  end)

  T.it('ボディが無くても解析できる', function()
    local res = runner.parse_response('HTTP/1.1 204 No Content\r\n\r\n')
    T.eq(res.status_code, 204)
    T.eq(res.body, '')
  end)

  T.it('-w の統計行を stderr から取り出す', function()
    local stats, rest = runner.parse_stats('\n__NVIM_HTTP_STATS__ 200 0.2314 1234\n')
    T.eq(stats.status_code, 200)
    T.eq(stats.time_ms, 231)
    T.eq(stats.size, 1234)
    T.eq(rest, '')
  end)

  T.it('curl のエラー文は統計行と分けて残す', function()
    local stats, rest = runner.parse_stats('curl: (6) Could not resolve host\n__NVIM_HTTP_STATS__ 000 0.001 0\n')
    T.eq(stats.status_code, 0)
    T.eq(rest, 'curl: (6) Could not resolve host')
  end)
end)

T.describe('http_client ボディのファイル参照', function()
  T.it('< ./file.json を読み込む（ファイルの中身をそのまま送る）', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/body.json', { '{', '  "a": 1', '}' })
    local body, err = runner.resolve_body('< ./body.json', dir)
    T.eq(err, nil)
    T.eq(body, '{\n  "a": 1\n}\n') -- 末尾の改行もファイルどおり
    T.rmrf(dir)
  end)

  T.it('読めないファイルはエラーを返す', function()
    local body, err = runner.resolve_body('< ./missing.json', vim.fn.tempname())
    T.eq(body, nil)
    T.ok(err ~= nil and err:find('読めません') ~= nil, 'エラーメッセージ: ' .. tostring(err))
  end)

  T.it('通常のボディはそのまま返す', function()
    T.eq(runner.resolve_body('{"a":1}', '/tmp'), '{"a":1}')
  end)
end)

-- ══════════════════════════════════════════════
-- 実際に curl を動かす（テスト内に小さな HTTP サーバを立てる）
-- ══════════════════════════════════════════════

local start_server = T.http_server

T.describe('http_client 実行(E2E)', function()
  T.it('GET でステータス・ヘッダ・ボディ・統計を取得する', function()
    local received
    local server, port = start_server(function(req)
      received = req
      local body = '{"id":1,"name":"taro"}'
      return table.concat({
        'HTTP/1.1 200 OK',
        'Content-Type: application/json',
        'Content-Length: ' .. #body,
        '', body,
      }, '\r\n')
    end)

    local result
    runner.run({
      method = 'GET',
      url = 'http://127.0.0.1:' .. port .. '/users/1',
      headers = { { 'X-Test', 'yes' } },
    }, {}, function(r) result = r end)

    T.wait_until(function() return result ~= nil end, 5000)
    server:close()

    T.ok(result ~= nil, 'レスポンスが返る')
    T.eq(result.ok, true)
    T.eq(result.status_code, 200)
    T.eq(result.content_type, 'application/json')
    T.eq(result.body, '{"id":1,"name":"taro"}')
    T.ok(result.time_ms ~= nil, '所要時間が取れる')
    T.eq(result.size, 22)
    T.contains(received, 'GET /users/1 HTTP/1.1')
    T.contains(received, 'X-Test: yes')
  end)

  T.it('POST のボディを標準入力経由で送る', function()
    local received
    local server, port = start_server(function(req)
      received = req
      return 'HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n'
    end)

    local result
    runner.run({
      method = 'POST',
      url = 'http://127.0.0.1:' .. port .. '/users',
      headers = { { 'Content-Type', 'application/json' } },
      body = '{"name":"taro"}',
    }, {}, function(r) result = r end)

    T.wait_until(function() return result ~= nil end, 5000)
    server:close()

    T.eq(result.status_code, 201)
    T.contains(received, 'POST /users HTTP/1.1')
    T.contains(received, '{"name":"taro"}')
    T.contains(received, 'Content-Type: application/json')
  end)

  T.it('接続できないときは失敗として返す', function()
    local result
    -- ポート1はまず開いていない
    runner.run({ method = 'GET', url = 'http://127.0.0.1:1/', headers = {} }, {}, function(r)
      result = r
    end)
    T.wait_until(function() return result ~= nil end, 5000)
    T.eq(result.ok, false)
    T.ok(result.error ~= nil and result.error ~= '', 'エラーメッセージが入る')
  end)
end)

T.summary()
