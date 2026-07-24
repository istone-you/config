local T = dofile(TESTS_DIR .. '/helpers.lua')
local wu = require('config.util.win_util')

local function reset()
  vim.cmd('silent! only')
  vim.cmd('enew')
end

T.describe('win_util', function()
  T.it('is_editor: true for a normal window, false for explorer/shortcuts and floats', function()
    reset()
    local editor = vim.api.nvim_get_current_win()
    T.eq(wu.is_editor(editor), true)

    -- 別バッファのウィンドウを explorer 扱いにする
    vim.cmd('vnew')
    local util = vim.api.nvim_get_current_win()
    vim.bo[vim.api.nvim_win_get_buf(util)].filetype = 'explorer'
    T.eq(wu.is_editor(util), false)

    -- フロートは常に false
    local fbuf = vim.api.nvim_create_buf(false, true)
    local fwin = vim.api.nvim_open_win(fbuf, false, {
      relative = 'editor', width = 5, height = 3, col = 1, row = 1, style = 'minimal',
    })
    T.eq(wu.is_editor(fwin), false)
    vim.api.nvim_win_close(fwin, true)
    reset()
  end)

  T.it('focus_editor moves from a utility window to the editor window', function()
    reset()
    local editor = vim.api.nvim_get_current_win()
    vim.cmd('vnew')
    local util = vim.api.nvim_get_current_win()
    vim.bo[vim.api.nvim_win_get_buf(util)].filetype = 'explorer'

    vim.api.nvim_set_current_win(util)
    wu.focus_editor()
    T.eq(vim.api.nvim_get_current_win(), editor)
    reset()
  end)

  T.it('focus_editor is a no-op when already on an editor window', function()
    reset()
    local editor = vim.api.nvim_get_current_win()
    wu.focus_editor()
    T.eq(vim.api.nvim_get_current_win(), editor)
  end)
end)

T.summary()
