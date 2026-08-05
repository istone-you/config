local T = dofile(TESTS_DIR .. '/helpers.lua')
local preview = require('config.browser.html')
local P = preview._private

T.describe('browser/html.lua: http response', function()
  T.it('serves the current HTML buffer at / and relative assets from the same directory', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local html_path = dir .. '/page.html'
    T.write_file(dir .. '/style.css', { 'body { color: red; }' })
    T.write_file(dir .. '/app.js', { 'console.log("ok")' })

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, html_path)
    vim.bo[buf].filetype = 'html'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      '<!doctype html>',
      '<link rel="stylesheet" href="style.css">',
      '<script src="app.js"></script>',
      '<h1>Preview</h1>',
    })

    T.ok(P.set_preview_html(buf), 'html buffer should be accepted')
    T.contains(P.response_for_path('/'), '<h1>Preview</h1>')
    T.contains(P.response_for_path('/page.html'), '<h1>Preview</h1>')

    local css = P.response_for_path('/style.css')
    T.contains(css, 'Content-Type: text/css; charset=utf-8')
    T.contains(css, 'color: red')

    local js = P.response_for_path('/app.js')
    T.contains(js, 'Content-Type: application/javascript; charset=utf-8')
    T.contains(js, 'console.log("ok")')

    T.contains(P.response_for_path('/../secret.txt'), 'HTTP/1.1 403 Forbidden')

    vim.api.nvim_buf_delete(buf, { force = true })
    T.rmrf(dir)
  end)

  T.it('parses explicit ports, treats blank input as cancel, and rejects invalid ports', function()
    T.eq(P.parse_port('7000'), 7000)
    T.eq(P.parse_port(''), nil)

    local port, err = P.parse_port('abc')
    T.eq(port, nil)
    T.contains(err, 'number')

    port, err = P.parse_port('70000')
    T.eq(port, nil)
    T.contains(err, 'between 1 and 65535')
  end)

  T.it('start_server uses the requested port only and reports it when occupied', function()
    local uv = vim.uv or vim.loop
    local blocker = uv.new_tcp()
    local port = 6520
    local bound = false
    for p = 6520, 6530 do
      if pcall(function() assert(blocker:bind('0.0.0.0', p)) end) then
        port = p
        bound = true
        break
      end
    end
    if not bound then
      pcall(function() blocker:close() end)
      return
    end
    assert(blocker:listen(1, function() end))

    local ok, err = P.start_server(port)
    P.stop_server()
    pcall(function() blocker:close() end)

    T.eq(ok, false)
    T.contains(err, 'port ' .. tostring(port) .. ' is already in use')
    T.eq(P.state.port, nil, 'server must not fall through to another port')
  end)
end)

T.describe('browser/html.lua: port input', function()
  T.it('open asks for a port before opening', function()
    local orig_input = vim.ui.input
    local orig_open_on_port = preview.open_on_port
    local opened

    vim.ui.input = function(opts, cb)
      T.eq(opts.prompt, 'HTML preview port: ')
      cb('6311')
    end
    preview.open_on_port = function(port)
      opened = port
    end

    preview.open()

    vim.ui.input = orig_input
    preview.open_on_port = orig_open_on_port

    T.eq(opened, 6311)
  end)
end)

T.describe('browser/html.lua: lifecycle', function()
  T.it('stops the preview server when the source buffer is deleted', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.html')
    local closed = false
    P.state.source_buf = buf
    P.state.server = { close = function() closed = true end }
    P.state.port = 6311
    P.state.host = '0.0.0.0'
    local notifications = {}
    local orig_notify = vim.notify
    vim.notify = function(msg) notifications[#notifications + 1] = tostring(msg) end

    vim.api.nvim_buf_delete(buf, { force = true })
    vim.wait(80)

    vim.notify = orig_notify

    T.eq(closed, true, 'server handle should be closed')
    T.eq(P.state.source_buf, nil, 'source buffer should be cleared')
    T.eq(P.state.server, nil, 'server should be cleared')
    T.eq(P.state.port, nil, 'port should be cleared')
    T.ok(vim.iter(notifications):any(function(msg)
      return msg:find('HTML previewを停止しました', 1, true) ~= nil
        and msg:find('http://localhost:6311/', 1, true) ~= nil
    end), 'should notify that the HTML preview server stopped')
  end)
end)

T.summary()
