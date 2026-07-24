local T = dofile(TESTS_DIR .. '/helpers.lua')
local wu = require('config.util.win_util')
require('config.tabline')

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

  T.it('open_buf focuses the editor before showing a file buffer', function()
    reset()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'hello' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    local editor = vim.api.nvim_get_current_win()
    local file_buf = vim.api.nvim_get_current_buf()

    vim.cmd('vnew')
    local side = vim.api.nvim_get_current_win()
    local side_buf = vim.api.nvim_get_current_buf()
    vim.bo[side_buf].filetype = 'explorer'
    wu.mark_sidebar(side, side_buf)

    vim.api.nvim_set_current_win(side)
    wu.open_buf(file_buf)
    T.eq(vim.api.nvim_get_current_win(), editor)
    T.eq(vim.api.nvim_win_get_buf(editor), file_buf)
    T.eq(vim.api.nvim_win_get_buf(side), side_buf)

    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)

  T.it('sidebar guard moves a file buffer out of a marked sidebar window', function()
    reset()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'hello' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    local editor = vim.api.nvim_get_current_win()
    local file_buf = vim.api.nvim_get_current_buf()

    vim.cmd('vnew')
    local side = vim.api.nvim_get_current_win()
    local side_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[side_buf].buftype = 'nofile'
    vim.bo[side_buf].filetype = 'explorer'
    vim.api.nvim_win_set_buf(side, side_buf)
    wu.mark_sidebar(side, side_buf)

    -- タブクリック相当: サイドバーにフォーカスしたまま set_current_buf
    vim.api.nvim_set_current_win(side)
    vim.api.nvim_set_current_buf(file_buf)
    vim.wait(50)

    T.eq(vim.api.nvim_win_get_buf(side), side_buf, 'sidebar keeps its own buffer')
    T.eq(vim.api.nvim_win_get_buf(editor), file_buf, 'file is shown in the editor')
    T.eq(vim.api.nvim_get_current_win(), editor)

    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)

  T.it('tabline click opens the buffer in the editor, not the sidebar', function()
    reset()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'hello' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    local editor = vim.api.nvim_get_current_win()
    local file_buf = vim.api.nvim_get_current_buf()

    vim.cmd('vnew')
    local side = vim.api.nvim_get_current_win()
    local side_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[side_buf].buftype = 'nofile'
    vim.bo[side_buf].filetype = 'shortcuts'
    vim.api.nvim_win_set_buf(side, side_buf)
    wu.mark_sidebar(side, side_buf)

    vim.api.nvim_set_current_win(side)
    _G._bufline_click(file_buf, 0, 'l')
    vim.wait(50)

    T.eq(vim.api.nvim_get_current_win(), editor)
    T.eq(vim.api.nvim_win_get_buf(editor), file_buf)
    T.eq(vim.api.nvim_win_get_buf(side), side_buf)

    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)
end)

T.summary()
