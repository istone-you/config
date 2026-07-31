local T = dofile(TESTS_DIR .. '/helpers.lua')
local ui = require('config.http_client.ui')

T.describe('http_client JSON 整形', function()
  T.it('入れ子のオブジェクト・配列をインデントする', function()
    T.eq(ui.format_json('{"a":1,"b":[1,2]}'),
      '{\n  "a": 1,\n  "b": [\n    1,\n    2\n  ]\n}')
  end)

  T.it('空のオブジェクト・配列は1行のまま', function()
    T.eq(ui.format_json('{"a":{},"b":[ ]}'), '{\n  "a": {},\n  "b": []\n}')
  end)

  T.it('文字列内の記号やエスケープを壊さない', function()
    T.eq(ui.format_json('{"a":"x, y: {z}","b":"q\\"r"}'),
      '{\n  "a": "x, y: {z}",\n  "b": "q\\"r"\n}')
  end)

  T.it('キーの順序を保つ（vim.json.decode と違い並べ替えない）', function()
    local out = ui.format_json('{"z":1,"a":2,"m":3}')
    T.eq(out, '{\n  "z": 1,\n  "a": 2,\n  "m": 3\n}')
  end)

  T.it('format_body: content-type が JSON のときだけ整形する', function()
    T.eq(ui.format_body('{"a":1}', 'application/json; charset=utf-8'), '{\n  "a": 1\n}')
    T.eq(ui.format_body('{"a":1}', 'text/plain'), '{"a":1}')
    T.eq(ui.format_body('<html></html>', 'text/html'), '<html></html>')
  end)

  T.it('format_body: JSON として壊れていればそのまま返す', function()
    T.eq(ui.format_body('{"a":', 'application/json'), '{"a":')
  end)

  T.it('format_size', function()
    T.eq(ui.format_size(512), '512 B')
    T.eq(ui.format_size(2048), '2.0 KB')
    T.eq(ui.format_size(3 * 1024 * 1024), '3.0 MB')
  end)
end)

T.describe('http_client レスポンス描画', function()
  local function result()
    return {
      ok = true,
      request = { method = 'POST', url = 'https://example.com/users', label = '作成' },
      status_line = 'HTTP/1.1 201 Created',
      status_code = 201,
      status_text = 'Created',
      headers = { { 'content-type', 'application/json' } },
      body = '{"id":1}',
      content_type = 'application/json',
      time_ms = 231,
      size = 8,
    }
  end

  T.it('サマリ・ヘッダ・整形済みボディの順に並べる', function()
    local lines = ui.render(result(), { env = 'dev' })
    T.eq(lines[1], '### 201 Created · 231 ms · 8 B · env: dev')
    T.eq(lines[2], '### POST https://example.com/users')
    T.eq(lines[3], '### 作成')
    T.eq(lines[4], '')
    T.eq(lines[5], 'HTTP/1.1 201 Created')
    T.eq(lines[6], 'content-type: application/json')
    T.eq(lines[7], '')
    T.eq(lines[8], '{')
    T.eq(lines[9], '  "id": 1')
    T.eq(lines[10], '}')
  end)

  T.it('ボディが空なら本文行を出さない', function()
    local r = result()
    r.body = ''
    local lines = ui.render(r, {})
    T.eq(lines[#lines], 'content-type: application/json')
  end)

  T.it('失敗時はエラー内容を出す', function()
    local lines = ui.render({
      ok = false,
      request = { method = 'GET', url = 'http://127.0.0.1:1/' },
      error = 'curl: (7) Failed to connect',
    }, {})
    T.contains(lines[1], '失敗')
    T.eq(lines[2], '### GET http://127.0.0.1:1/')
    T.eq(lines[4], 'curl: (7) Failed to connect')
  end)

  T.it('実行中は待機表示にする', function()
    local lines = ui.render({ loading = true, request = { method = 'GET', url = 'http://x' } }, {})
    T.eq(lines[1], '### 実行中...')
    T.eq(lines[2], '### GET http://x')
    T.eq(#lines, 2)
  end)

  T.it('巨大なボディは切り詰めて注記する', function()
    local r = result()
    r.content_type = 'text/plain'
    r.body = string.rep('a', ui.MAX_BODY_BYTES + 10)
    local lines = ui.render(r, {})
    T.eq(lines[#lines], '### ボディが大きいため以降を省略しました')
  end)
end)

T.describe('http_client レスポンスパネル', function()
  T.it('右に縦分割で開き、編集不可のスクラッチバッファになる', function()
    local before = #vim.api.nvim_tabpage_list_wins(0)
    local buf = ui.show({
      ok = true,
      request = { method = 'GET', url = 'http://x' },
      status_line = 'HTTP/1.1 200 OK',
      status_code = 200,
      headers = {},
      body = 'hello',
    }, {})

    T.eq(#vim.api.nvim_tabpage_list_wins(0), before + 1)
    T.eq(vim.bo[buf].buftype, 'nofile')
    T.eq(vim.bo[buf].filetype, 'httpresult')
    T.eq(vim.bo[buf].modifiable, false)
    T.ok(ui.is_open(), 'パネルが開いている')
    T.contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), 'hello')

    ui.close()
    T.eq(ui.is_open(), false)
    T.eq(#vim.api.nvim_tabpage_list_wins(0), before)
  end)

  T.it('2回目の表示は同じバッファを使い回す', function()
    local buf1 = ui.show({ ok = true, request = { method = 'GET', url = 'http://a' }, headers = {}, body = 'a' }, {})
    local buf2 = ui.show({ ok = true, request = { method = 'GET', url = 'http://b' }, headers = {}, body = 'b' }, {})
    T.eq(buf1, buf2)
    T.contains(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), '### GET http://b')
    ui.close()
  end)

  T.it('q でパネルを閉じ、y でボディをコピーできる', function()
    local buf = ui.show({ ok = true, request = { method = 'GET', url = 'http://a' }, headers = {}, body = 'body-text' }, {})
    vim.api.nvim_set_current_win(ui.state.win)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('y', true, false, true), 'x', false)
    T.eq(vim.fn.getreg('"'), 'body-text')

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('q', true, false, true), 'x', false)
    T.eq(ui.is_open(), false)
    T.ok(vim.api.nvim_buf_is_valid(buf), 'バッファ自体は残る')
  end)
end)

T.summary()
