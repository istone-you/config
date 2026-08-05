local T = dofile(TESTS_DIR .. '/helpers.lua')
local open = require('config.browser')
local html = require('config.browser.html')
local markdown = require('config.browser.markdown')

T.describe('browser/init.lua', function()
  T.it('registers BrowserOpen and <leader>o', function()
    T.ok(vim.api.nvim_get_commands({}).BrowserOpen ~= nil, 'BrowserOpen command should exist')
    local map = vim.fn.maparg('<leader>o', 'n', false, true)
    T.eq(map.desc, 'Open current HTML/Markdown file in default browser')
  end)

  T.it('detects HTML and Markdown by extension or filetype', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)

    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/page.html')
    vim.bo[buf].filetype = ''
    T.eq(open._private.current_kind(), 'html')

    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/page.txt')
    vim.bo[buf].filetype = 'html'
    T.eq(open._private.current_kind(), 'html')

    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/doc.md')
    vim.bo[buf].filetype = ''
    T.eq(open._private.current_kind(), 'markdown')

    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/doc.txt')
    vim.bo[buf].filetype = 'markdown'
    T.eq(open._private.current_kind(), 'markdown')

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  T.it('<leader>o dispatches to the HTML preview for HTML files', function()
    local orig_html_open = html.open
    local orig_markdown_open = markdown.open
    local called = {}
    html.open = function() called[#called + 1] = 'html' end
    markdown.open = function() called[#called + 1] = 'markdown' end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/page.html')
    vim.api.nvim_set_current_buf(buf)
    open.open()

    html.open = orig_html_open
    markdown.open = orig_markdown_open
    vim.api.nvim_buf_delete(buf, { force = true })

    T.eq(called, { 'html' })
  end)

  T.it('<leader>o dispatches to the Markdown preview for Markdown files', function()
    local orig_html_open = html.open
    local orig_markdown_open = markdown.open
    local called = {}
    html.open = function() called[#called + 1] = 'html' end
    markdown.open = function() called[#called + 1] = 'markdown' end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/doc.md')
    vim.api.nvim_set_current_buf(buf)
    open.open()

    html.open = orig_html_open
    markdown.open = orig_markdown_open
    vim.api.nvim_buf_delete(buf, { force = true })

    T.eq(called, { 'markdown' })
  end)

  T.it('<leader>o notifies on unsupported files', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '/notes.txt')
    vim.api.nvim_set_current_buf(buf)

    local notifications = {}
    local orig_notify = vim.notify
    vim.notify = function(msg) notifications[#notifications + 1] = tostring(msg) end
    open.open()
    vim.notify = orig_notify
    vim.api.nvim_buf_delete(buf, { force = true })

    T.ok(vim.iter(notifications):any(function(msg)
      return msg:find('HTML / Markdown', 1, true) ~= nil
    end), 'should notify that the file is unsupported')
  end)
end)

T.summary()
