local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.auto_quit')

T.describe('auto_quit', function()
  T.it('does nothing when a real editing window still remains after closing one', function()
    vim.cmd('tabnew')
    local real1 = vim.api.nvim_get_current_win()
    vim.cmd('vsplit')
    local real2 = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(real2)
    vim.api.nvim_win_close(real2, true)
    vim.wait(60)
    T.ok(#vim.api.nvim_list_tabpages() >= 1, 'process should still be alive with tabs intact')
    T.ok(vim.api.nvim_win_is_valid(real1), 'the remaining real window must not have been closed')
  end)

  T.it('auto-closes the tab when only utility (explorer-filetype) windows remain in a non-last tab', function()
    local starting_tabs = #vim.api.nvim_list_tabpages()
    vim.cmd('tabnew')
    local real_win = vim.api.nvim_get_current_win()
    vim.cmd('vsplit')
    local explorer_win = vim.api.nvim_get_current_win()
    vim.bo[vim.api.nvim_win_get_buf(explorer_win)].filetype = 'explorer'

    vim.api.nvim_set_current_win(real_win)
    vim.api.nvim_win_close(real_win, true)
    T.wait_until(function() return #vim.api.nvim_list_tabpages() == starting_tabs end, 1000)
    T.eq(#vim.api.nvim_list_tabpages(), starting_tabs, 'the tab left with only an explorer window should auto-close')
  end)

  T.it('floating windows (git panel style) count as utility too', function()
    vim.cmd('tabnew')
    local real_win = vim.api.nvim_get_current_win()
    local fbuf = vim.api.nvim_create_buf(false, true)
    local float_win = vim.api.nvim_open_win(fbuf, false, {
      relative = 'editor', width = 10, height = 3, row = 0, col = 0,
    })
    local starting_tabs = #vim.api.nvim_list_tabpages()

    vim.api.nvim_set_current_win(real_win)
    vim.api.nvim_win_close(real_win, true)
    T.wait_until(function() return #vim.api.nvim_list_tabpages() < starting_tabs end, 1000)
    T.ok(#vim.api.nvim_list_tabpages() < starting_tabs, 'tab with only a floating window left should auto-close')
    if vim.api.nvim_win_is_valid(float_win) then vim.api.nvim_win_close(float_win, true) end
  end)

  T.it('quits Neovim entirely when it happens in the last tab (subprocess check)', function()
    local script = [[
      require('config.auto_quit')
      vim.cmd('vsplit')
      local explorer_win = vim.api.nvim_get_current_win() -- vsplit直後のカレントは新しい方
      vim.bo[vim.api.nvim_win_get_buf(explorer_win)].filetype = 'explorer'
      vim.cmd('wincmd p') -- 元のウィンドウ(実編集用)へ
      local real_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_close(real_win, true)
      vim.wait(200)
      io.stderr:write('STILL_ALIVE\n')
      vim.cmd('qa!')
    ]]
    local tmp = vim.fn.tempname() .. '.lua'
    vim.fn.writefile(vim.split(script, '\n', { plain = true }), tmp)
    local res = vim.system({
      'nvim', '-u', 'NONE', '--cmd', 'set rtp+=' .. vim.fn.fnamemodify(TESTS_DIR, ':h'), '-l', tmp,
    }, { text = true }):wait()
    T.ok(not (res.stderr or ''):find('STILL_ALIVE'),
      'closing the last real window with only a utility window left should quit Neovim. code='
        .. tostring(res.code) .. ' stderr=[' .. (res.stderr or '') .. '] stdout=[' .. (res.stdout or '') .. ']')
    vim.fn.delete(tmp)
  end)
end)

T.summary()
