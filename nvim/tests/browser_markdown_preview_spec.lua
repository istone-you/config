local T = dofile(TESTS_DIR .. '/helpers.lua')
local preview = require('config.browser_markdown_preview')
local P = preview._private

T.describe('browser_markdown_preview.lua: markdown/html rendering', function()
  T.it('renders common markdown blocks without external markdown tools', function()
    local html = P.document_html({
      '# Title',
      '',
      '[Jump](#second-heading)',
      '',
      'Hello **bold** and `code` with [link](https://example.com).',
      '',
      '![Logo](images/logo.png)',
      '',
      'line<br>break',
      '',
      '<details>',
      '<summary>More</summary>',
      'Hidden **body**',
      '</details>',
      '',
      '<script>alert(1)</script>',
      '<span onclick="alert(1)" style="color:red">safe</span>',
      '',
      '| Name | Count |',
      '| :--- | ---: |',
      '| Apple | 10 |',
      '| Banana | 2 |',
      '',
      '- parent',
      '  - child',
      '    - grandchild',
      '- next',
      '',
      '<https://example.com/path>',
      '<me@example.com>',
      '',
      '- one',
      '- two',
      '',
      '## Second Heading',
      '',
      '[日本語へ](#日本語-heading)',
      '[Encoded](#%E6%97%A5%E6%9C%AC%E8%AA%9E-heading)',
      '',
      '## 日本語 Heading',
      '',
      '```lua',
      '<script>',
      '```',
    }, 'doc.md', '/tmp')

    T.contains(html, '<h1 id="title">Title</h1>')
    T.contains(html, '<h2 id="second-heading">Second Heading</h2>')
    T.contains(html, '<h2 id="日本語-heading">日本語 Heading</h2>')
    T.contains(html, '<a href="#second-heading">Jump</a>')
    T.contains(html, '<a href="#日本語-heading">日本語へ</a>')
    T.contains(html, '<a href="#日本語-heading">Encoded</a>')
    T.contains(html, '<strong>bold</strong>')
    T.contains(html, '<code>code</code>')
    T.contains(html, '<a href="https://example.com">link</a>')
    T.contains(html, '<img alt="Logo" src="/__asset/images/logo.png">')
    T.contains(html, '<p>line<br>break</p>')
    T.contains(html, '<details>')
    T.contains(html, '<summary>More</summary>')
    T.contains(html, '<p>Hidden <strong>body</strong></p>')
    T.contains(html, '</details>')
    T.contains(html, '&lt;script&gt;alert(1)&lt;/script&gt;')
    T.contains(html, '<span>safe</span>')
    T.contains(html, '<table>')
    T.contains(html, '<th style="text-align:left">Name</th>')
    T.contains(html, '<th style="text-align:right">Count</th>')
    T.contains(html, '<td style="text-align:left">Apple</td>')
    T.contains(html, '<td style="text-align:right">10</td>')
    T.contains(html, '<li>parent<ul><li>child<ul><li>grandchild</li></ul></li></ul></li><li>next</li>')
    T.contains(html, '<a href="https://example.com/path">https://example.com/path</a>')
    T.contains(html, '<a href="mailto:me@example.com">me@example.com</a>')
    T.contains(html, '<ul>')
    T.contains(html, '<li>one</li>')
    T.contains(html, '&lt;script&gt;', 'code blocks should be escaped')
  end)

  T.it('makes stable GitHub-like heading slugs', function()
    T.eq(P.slugify_heading('Second Heading'), 'second-heading')
    T.eq(P.slugify_heading('Hello `code` & Things!'), 'hello-code-things')
    T.eq(P.slugify_heading('日本語 Heading'), '日本語-heading')
  end)

  T.it('keeps safe inline HTML but escapes unsafe HTML', function()
    T.eq(P.inline_markdown('a<br>b'), 'a<br>b')
    T.eq(P.inline_markdown('<details>x</details>'), '<details>x</details>')
    T.eq(P.inline_markdown('<script>x</script>'), '&lt;script&gt;x&lt;/script&gt;')
    T.eq(P.inline_markdown('<span onclick="x" style="color:red">x</span>'), '<span>x</span>')
  end)

  T.it('renders GFM-style tables, nested lists, and autolinks', function()
    local body = P.markdown_to_body({
      '| A | B |',
      '| --- | ---: |',
      '| x | 1 |',
      '',
      '- a',
      '  - b',
      '',
      '<https://example.com>',
    })
    T.contains(body, '<table>')
    T.contains(body, '<td style="text-align:right">1</td>')
    T.contains(body, '<li>a<ul><li>b</li></ul></li>')
    T.contains(body, '<a href="https://example.com">https://example.com</a>')
  end)

  T.it('renders the tool/config table shape used in README', function()
    local body = P.markdown_to_body({
      '| ツール | 設定ファイル |',
      '|--------|------------|',
      '| delta | `.devcontainer/.config/delta/config.yaml` |',
      '| ripgrep | `.devcontainer/.config/ripgrep/config.toml` |',
    })
    T.contains(body, '<table>')
    T.contains(body, '<th>ツール</th>')
    T.contains(body, '<th>設定ファイル</th>')
    T.contains(body, '<td>delta</td>')
    T.contains(body, '<td><code>.devcontainer/.config/delta/config.yaml</code></td>')
  end)

end)

T.describe('browser_markdown_preview.lua: opener command', function()
  T.it('opens the preview server URL through xdg-open only', function()
    local cmd = P.build_opener_cmd('xdg-open', 'http://localhost:6275/')
    local joined = table.concat(cmd, ' ')
    T.eq(cmd[1], 'xdg-open')
    T.contains(cmd, 'http://localhost:6275/')
    T.ok(not joined:find('chromium', 1, true), 'preview must not depend on chromium')
    T.ok(not joined:find('google-chrome', 1, true), 'preview must not depend on google-chrome')
    T.ok(not joined:find('mo', 1, true), 'mo must not be a runtime dependency')
    T.ok(not joined:find('chafa', 1, true), 'chafa must not be a runtime dependency')
  end)

  T.it('find_opener returns nil when xdg-open is missing', function()
    local orig = vim.fn.executable
    vim.fn.executable = function() return 0 end
    local found = P.find_opener()
    vim.fn.executable = orig
    T.eq(found, nil)
  end)

  T.it('find_opener ignores browser binaries and uses xdg-open only', function()
    local orig = vim.fn.executable
    vim.fn.executable = function(name)
      return (name == 'chromium' or name == 'google-chrome-stable') and 1 or 0
    end

    local found = P.find_opener()

    vim.fn.executable = orig
    T.eq(found, nil)
  end)
end)

T.describe('browser_markdown_preview.lua: port input', function()
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

  T.it('BrowserMarkdownPreview asks for a port every time before opening', function()
    local orig_input = vim.ui.input
    local orig_open_on_port = preview.open_on_port
    local prompts = 0
    local opened = {}

    vim.ui.input = function(opts, cb)
      prompts = prompts + 1
      T.eq(opts.default, nil)
      cb(tostring(6300 + prompts))
    end
    preview.open_on_port = function(port)
      opened[#opened + 1] = port
    end

    vim.cmd('BrowserMarkdownPreview')
    vim.cmd('BrowserMarkdownPreview')

    vim.ui.input = orig_input
    preview.open_on_port = orig_open_on_port

    T.eq(prompts, 2)
    T.eq(opened, { 6301, 6302 })
  end)

  T.it('start_server uses the requested port only and reports it when occupied', function()
    local uv = vim.uv or vim.loop
    local blocker = uv.new_tcp()
    local port = 6499
    local bound = false
    for p = 6499, 6510 do
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

T.describe('browser_markdown_preview.lua: http response', function()
  T.it('serves HTML over HTTP, not file URLs', function()
    local res = P.http_response('200 OK', 'text/html', '<h1>x</h1>')
    T.contains(res, 'HTTP/1.1 200 OK')
    T.contains(res, 'Content-Type: text/html; charset=utf-8')
    T.contains(res, 'Content-Length: 10')
    T.contains(res, '<h1>x</h1>')
  end)

  T.it('maps relative assets under /__asset and leaves anchors/external URLs alone', function()
    T.eq(P.preview_asset_url('images/logo.png'), '/__asset/images/logo.png')
    T.eq(P.preview_asset_url('./images/logo space.png'), '/__asset/images/logo%20space.png')
    T.eq(P.preview_asset_url('#section'), '#section')
    T.eq(P.preview_asset_url('https://example.com/a.png'), 'https://example.com/a.png')
  end)

  T.it('serves relative image files from the markdown directory and blocks traversal', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/images', 'p')
    vim.fn.writefile({ 'fakepng' }, dir .. '/images/logo.png', 'b')

    local old_root = P.state.root_dir
    P.state.root_dir = dir
    local ok_res = P.asset_response('images/logo.png')
    local blocked = P.asset_response('../secret.png')
    P.state.root_dir = old_root
    vim.fn.delete(dir, 'rf')

    T.contains(ok_res, 'HTTP/1.1 200 OK')
    T.contains(ok_res, 'Content-Type: image/png; charset=utf-8')
    T.contains(ok_res, 'fakepng')
    T.contains(blocked, 'HTTP/1.1 403 Forbidden')
  end)
end)

T.describe('browser_markdown_preview.lua: commands/keymap', function()
  T.it('registers commands and <leader>md', function()
    T.ok(vim.api.nvim_get_commands({}).BrowserMarkdownPreview ~= nil, 'open command should exist')
    T.ok(vim.api.nvim_get_commands({}).BrowserMarkdownPreviewRefresh ~= nil, 'refresh command should exist')

    local maps = vim.api.nvim_get_keymap('n')
    local found = false
    for _, map in ipairs(maps) do
      if map.desc == 'Open markdown preview in default browser' then found = true end
    end
    T.ok(found, '<leader>md should be mapped')
  end)

  T.it('BufWritePost refreshes silently to avoid hit-enter prompts on save', function()
    local orig_refresh = preview.refresh
    local got_opts
    preview.refresh = function(opts)
      got_opts = opts
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '.md')
    P.state.source_buf = buf
    P.state.server = {}
    vim.api.nvim_exec_autocmds('BufWritePost', { buffer = buf, modeline = false })

    preview.refresh = orig_refresh
    P.state.source_buf = nil
    P.state.server = nil

    T.eq(got_opts, { silent = true })
  end)
end)

T.describe('browser_markdown_preview.lua: external edits (e.g. by an AI tool)', function()
  -- nvim 側では一切操作しない(保存も checktime もしない)まま、
  -- ディスク上の変更だけでプレビューが更新されることを見る
  local function watch_and_expect(path, write_fn, needle)
    P.start_watch(path)
    local version_before = P.state.version
    write_fn()
    T.wait_until(function()
      return P.state.html and P.state.html:find(needle, 1, true) ~= nil
    end)
    local html = P.state.html
    local served = P.response_for_path('/')
    local version = P.response_for_path('/__version')
    P.stop_watch()
    return html, served, version, version_before
  end

  T.it('reflects an out-of-band in-place edit, and serves it over HTTP so the browser reloads', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/doc.md'
    T.write_file(path, { '# Original' })

    local html, served, version, version_before = watch_and_expect(path, function()
      vim.fn.writefile({ '# Edited by AI' }, path)
    end, 'Edited by AI')

    T.rmrf(dir)

    T.ok(html:find('Edited by AI', 1, true) ~= nil, 'preview html should reflect the on-disk edit')
    T.ok(html:find('Original', 1, true) == nil, 'stale content should be gone')
    T.contains(served, 'Edited by AI', 'the HTTP handler must serve the updated html')
    T.ok(tonumber(version:match('(%d+)%s*$')) > version_before, '/__version must bump so the page reloads')
  end)

  -- 「一時ファイルに書いて rename」方式で保存するツール対策。ファイル自体ではなく
  -- 親ディレクトリを監視していないと、inode が差し替わって以後反映されなくなる
  T.it('reflects an atomic (write-temp-then-rename) replacement, not just in-place writes', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/doc.md'
    T.write_file(path, { '# Original' })

    local html = watch_and_expect(path, function()
      local tmp = dir .. '/.doc.md.tmp'
      vim.fn.writefile({ '# Replaced by rename' }, tmp)
      vim.uv.fs_rename(tmp, path)
    end, 'Replaced by rename')

    T.rmrf(dir)

    T.ok(html:find('Replaced by rename', 1, true) ~= nil, 'a renamed-over file must still be picked up')
  end)

  T.it('keeps watching across successive external edits, not just the first one', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/doc.md'
    T.write_file(path, { '# v0' })

    P.start_watch(path)
    local seen = {}
    for i = 1, 3 do
      vim.fn.writefile({ '# v' .. i }, path)
      T.wait_until(function()
        return P.state.html and P.state.html:find('v' .. i, 1, true) ~= nil
      end)
      seen[i] = P.state.html:find('v' .. i, 1, true) ~= nil
    end
    P.stop_watch()
    T.rmrf(dir)

    T.eq(seen, { true, true, true }, 'every external edit should be reflected, not only the first')
  end)

  T.it('start_watch is idempotent for the same path and stop_watch tears the handle down', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/doc.md'
    T.write_file(path, { '# X' })

    P.start_watch(path)
    local handle = P.state.watch_handle
    T.ok(handle ~= nil, 'a watch handle should be created')
    P.start_watch(path)
    T.eq(P.state.watch_handle, handle, 're-watching the same path should be a no-op')

    P.stop_watch()
    T.eq(P.state.watch_handle, nil)
    T.eq(P.state.watched_path, nil)

    T.rmrf(dir)
  end)
end)

T.summary()
