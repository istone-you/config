local T = dofile(TESTS_DIR .. '/helpers.lua')
vim.g.mapleader = ' ' -- keymap 登録前に設定する必要がある（-u NONE では既定の \ のままのため）
local http = require('config.http_client')
local ui = require('config.http_client.ui')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

--- tmp ディレクトリに .http ファイルを作って開く。戻り値は buf, dir
local function open_http(lines, env_json)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/api.http'
  T.write_file(path, lines)
  if env_json then
    T.write_file(dir .. '/http-client.env.json', vim.split(env_json, '\n'))
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = 'http' -- -u NONE では filetype 検出が無効なので明示的に発火させる
  return buf, dir
end

T.describe('http_client セットアップ', function()
  T.it('.rest も http ファイルタイプとして扱う', function()
    T.eq(vim.filetype.match({ filename = '/tmp/sample.rest' }), 'http')
  end)

  T.it('http バッファに Space h 系のキーマップが付く', function()
    local buf = open_http({ 'GET http://127.0.0.1/ping' })
    local lhs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      lhs[m.lhs] = true
    end
    T.ok(lhs[' hr'], 'Space h r がある')
    T.ok(lhs[' he'], 'Space h e がある')
    T.ok(lhs[' hj'], 'Space h j がある')
    T.ok(lhs[' hc'], 'Space h c がある')
    T.ok(lhs[']]'] and lhs['[['], ']] / [[ がある')
    T.eq(vim.bo[buf].commentstring, '# %s')
  end)

  T.it('コマンドが登録されている', function()
    local cmds = vim.api.nvim_get_commands({})
    T.ok(cmds.HttpRun ~= nil, ':HttpRun')
    T.ok(cmds.HttpEnv ~= nil, ':HttpEnv')
    T.ok(cmds.HttpList ~= nil, ':HttpList')
  end)
end)

T.describe('http_client prepare', function()
  T.it('カーソル位置のリクエストをファイル変数込みで組み立てる', function()
    local buf = open_http({
      '@base = http://127.0.0.1:9999',
      '',
      '### 一覧',
      'GET {{base}}/users',
      '',
      '### 作成',
      'POST {{base}}/users',
      'Content-Type: application/json',
      '',
      '{ "name": "taro" }',
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    local req = http.prepare(buf)
    T.eq(req.url, 'http://127.0.0.1:9999/users')
    T.eq(req.method, 'GET')

    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    local req2 = http.prepare(buf)
    T.eq(req2.method, 'POST')
    T.eq(req2.body, '{ "name": "taro" }')
    T.eq(req2.label, '作成')
  end)

  T.it('環境が1つだけなら自動で使い、変数を解決する', function()
    local buf, dir = open_http({ 'GET {{base}}/ping' },
      '{ "dev": { "base": "http://127.0.0.1:8080" } }')
    T.eq(http.current_env(dir), 'dev')
    local req, err = http.prepare(buf)
    T.eq(err, nil)
    T.eq(req.url, 'http://127.0.0.1:8080/ping')
  end)

  T.it('環境が複数あるときは選択するまで未解決エラーになる', function()
    local buf, dir = open_http({ 'GET {{base}}/ping' },
      '{ "dev": { "base": "http://dev" }, "prod": { "base": "http://prod" } }')
    local req, err = http.prepare(buf)
    T.eq(req, nil)
    T.contains(err, '未解決の変数: base')
    T.contains(err, 'Space h e')

    -- 環境を選べば解決する
    http.state.env_by_dir[http.parser.find_env_dir(dir)] = 'prod'
    local req2, err2 = http.prepare(buf)
    T.eq(err2, nil)
    T.eq(req2.url, 'http://prod/ping')
  end)

  T.it('リクエストが無ければエラーを返す', function()
    local buf = open_http({ '# メモだけ' })
    local req, err = http.prepare(buf)
    T.eq(req, nil)
    T.contains(err, 'リクエストが見つかりません')
  end)

  T.it('ボディのファイル参照は .http からの相対パスで解決する', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/body.json', { '{ "a": 1 }' })
    T.write_file(dir .. '/api.http', {
      'POST http://127.0.0.1:9999/x',
      'Content-Type: application/json',
      '',
      '< ./body.json',
    })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/api.http'))
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'http'
    local req = http.prepare(buf)
    T.eq(req.body, '{ "a": 1 }\n')
    T.rmrf(dir)
  end)
end)

T.describe('http_client ナビゲーション / コピー', function()
  T.it(']] / [[ でリクエスト間を移動する', function()
    local buf = open_http({
      '### 1つめ',
      'GET http://127.0.0.1/a',
      '',
      '### 2つめ',
      'GET http://127.0.0.1/b',
      '',
      '### 3つめ',
      'GET http://127.0.0.1/c',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed(']]')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 4)
    feed(']]')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 7)
    feed(']]') -- 最後では動かない
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 7)
    feed('[[')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 4)
    T.ok(buf ~= nil)
  end)

  T.it('curl コマンドとしてコピーする', function()
    local buf = open_http({
      '@base = http://127.0.0.1:9999',
      'POST {{base}}/users',
      'Content-Type: application/json',
      '',
      '{"name":"taro"}',
    })
    vim.fn.setreg('"', '')
    http.copy_as_curl(buf, 2)
    local cmd = vim.fn.getreg('"')
    T.contains(cmd, 'curl')
    T.contains(cmd, "'Content-Type: application/json'")
    T.contains(cmd, 'http://127.0.0.1:9999/users')
    T.contains(cmd, '--data-binary')
  end)
end)

T.describe('http_client 実行(E2E)', function()
  T.it('Space h r でリクエストを投げ、右のパネルに結果を出す', function()
    local received
    local server, port = T.http_server(function(req)
      received = req
      local body = '{"id":1,"name":"taro"}'
      return table.concat({
        'HTTP/1.1 200 OK',
        'Content-Type: application/json',
        'Content-Length: ' .. #body,
        '', body,
      }, '\r\n')
    end)

    local buf = open_http({
      '@base = http://127.0.0.1:' .. port,
      '',
      '### ユーザー取得',
      'GET {{base}}/users/1',
      'X-Test: yes',
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    feed(' hr')

    T.wait_until(function()
      local b = ui.state.buf
      if not b or not vim.api.nvim_buf_is_valid(b) then return false end
      return vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]:find('実行中') == nil
    end, 5000)
    server:close()

    local lines = vim.api.nvim_buf_get_lines(ui.state.buf, 0, -1, false)
    T.contains(lines[1], '### 200 OK')
    T.eq(lines[2], '### GET http://127.0.0.1:' .. port .. '/users/1')
    T.contains(lines, '  "name": "taro"')
    T.contains(received, 'X-Test: yes')
    T.eq(vim.api.nvim_get_current_buf(), buf) -- フォーカスは .http 側に残る

    ui.close()
  end)

  T.it('R で直前のリクエストを再実行できる', function()
    local hits = 0
    local server, port = T.http_server(function()
      hits = hits + 1
      return 'HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n'
    end)

    open_http({ 'DELETE http://127.0.0.1:' .. port .. '/users/1' })
    http.run()
    T.wait_until(function() return hits >= 1 end, 5000)

    http.rerun()
    T.wait_until(function() return hits >= 2 end, 5000)
    server:close()

    T.eq(hits, 2)
    T.contains(vim.api.nvim_buf_get_lines(ui.state.buf, 0, -1, false)[1], '204')
    ui.close()
  end)
end)

T.summary()
