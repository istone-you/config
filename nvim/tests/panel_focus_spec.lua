local T = dofile(TESTS_DIR .. '/helpers.lua')
local pf = require('config.panel_focus')

T.describe('panel_focus', function()
  T.it('hides a panel selection when it loses focus and restores it when refocused', function()
    -- explorer/git_panel のようなリストパネル(nofile)を模す: 選択強調=cursorline ON
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].cursorline = true

    pf.on_leave(win)
    T.ok(not vim.wo[win].cursorline, 'an unfocused panel must drop its selection highlight')

    pf.on_enter(win)
    T.ok(vim.wo[win].cursorline, 'a refocused panel must get its selection highlight back')
  end)

  T.it('leaves a freshly-opened panel (no saved value) to its own cursorline setting', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].cursorline = true -- パネルが自分で付けた選択強調

    pf.on_enter(win) -- まだ blur していない（退避値なし）
    T.ok(vim.wo[win].cursorline, 'panel own cursorline should be preserved on first focus')
  end)

  T.it('never touches a normal editor window (no full-line highlight is added)', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.lua', { 'return 1' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.lua'))
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].cursorline = false

    T.ok(not pf.is_panel_win(win), 'an editor window is not a panel window')
    pf.on_enter(win)
    T.ok(not vim.wo[win].cursorline, 'entering an editor window must NOT switch cursorline on')
    pf.on_leave(win)
    T.ok(not vim.wo[win].cursorline, 'leaving an editor window must not change cursorline')

    T.rmrf(dir)
  end)

  T.it('never touches a terminal window', function()
    local tbuf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_open_term(tbuf, {})
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, tbuf)
    T.ok(not pf.is_panel_win(win), 'a terminal window is not a panel window')
    vim.api.nvim_buf_delete(tbuf, { force = true })
  end)
end)

T.summary()
