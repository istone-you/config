local T = dofile(TESTS_DIR .. '/helpers.lua')
local winbar = require('config.winbar')

T.describe('winbar', function()
  T.it('shows the cwd-relative path for a normal file window', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/src', 'p')
    T.write_file(dir .. '/src/main.lua', { 'return 1' })

    vim.cmd('cd ' .. vim.fn.fnameescape(dir))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/src/main.lua'))

    local win = vim.api.nvim_get_current_win()
    T.ok(winbar.should_show(win), 'a normal file window should get a winbar')

    local s = winbar.build(vim.api.nvim_get_current_buf())
    T.contains(s, 'src › main.lua', 'winbar should show the cwd-relative path as breadcrumbs')
    T.ok(not s:find(dir, 1, true), 'winbar path should be relative (no leading cwd)')

    T.rmrf(dir)
  end)

  T.it('is empty for non-file (nofile) windows like explorer/start-screen', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    T.ok(not winbar.should_show(win), 'a nofile window must not show a winbar')
    T.eq(winbar.winbar_for(win), '', 'nofile window winbar value should be empty')
  end)

  T.it('is empty for an unnamed buffer', function()
    vim.cmd('enew')
    local win = vim.api.nvim_get_current_win()
    T.ok(not winbar.should_show(win), 'an unnamed buffer must not show a winbar')
    T.eq(winbar.winbar_for(win), '', 'unnamed buffer winbar value should be empty')
  end)

  T.it('escapes percent signs in the path so they are not read as statusline items', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/a%b.lua'
    T.write_file(path, { 'return 1' })
    vim.cmd('edit ' .. vim.fn.fnameescape(path))

    local s = winbar.build(vim.api.nvim_get_current_buf())
    T.contains(s, 'a%%b.lua', 'a literal % in the path must be escaped as %%')

    T.rmrf(dir)
  end)
end)

T.summary()
