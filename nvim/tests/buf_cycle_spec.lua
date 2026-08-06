local T = dofile(TESTS_DIR .. '/helpers.lua')
local cycle = require('config.util.buf_cycle')
require('config.options')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('buf_cycle', function()
  T.it('skips unnamed listed buffers that the tabline also hides', function()
    vim.cmd('silent! only')
    vim.cmd('%bwipeout!')
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    vim.cmd('enew') -- listed [No Name] を残す
    local unnamed = vim.api.nvim_get_current_buf()
    vim.cmd('edit ' .. dir .. '/a.txt')
    vim.cmd('edit ' .. dir .. '/b.txt')
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')
    T.eq(vim.fn.buflisted(unnamed), 1)

    T.eq(vim.api.nvim_get_current_buf(), b_buf)
    feed('<Tab>')
    T.eq(vim.api.nvim_get_current_buf(), a_buf)
    feed('<Tab>')
    T.eq(vim.api.nvim_get_current_buf(), b_buf, 'must not land on the empty [No Name]')

    local listed = cycle.list()
    for _, b in ipairs(listed) do
      T.ok(vim.api.nvim_buf_get_name(b) ~= '', 'cycle list has no unnamed buffers')
    end

    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)
end)

T.describe('buf_cycle.delete_keep_windows', function()
  T.it('deletes the buffer but keeps its window (falls back to an empty buffer)', function()
    vim.cmd('silent! only')
    vim.cmd('%bwipeout!')
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/only.txt', { 'x' })
    vim.cmd('edit ' .. dir .. '/only.txt')
    local buf = vim.fn.bufnr(dir .. '/only.txt')
    local win = vim.api.nvim_get_current_win()

    local closed = 0
    local grp = vim.api.nvim_create_augroup('bufcycle_test', { clear = true })
    vim.api.nvim_create_autocmd('WinClosed', { group = grp, callback = function() closed = closed + 1 end })

    local ok = cycle.delete_keep_windows(buf)
    T.ok(ok, 'delete succeeded')
    T.eq(vim.api.nvim_buf_is_valid(buf), false)
    T.ok(vim.api.nvim_win_is_valid(win), 'window survives')
    T.eq(closed, 0, 'no WinClosed fired (auto_quit would not trigger)')
    T.eq(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), '', 'window shows an empty buffer')

    vim.api.nvim_del_augroup_by_id(grp)
    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)

  T.it('switches the window to another open file when one exists', function()
    vim.cmd('silent! only')
    vim.cmd('%bwipeout!')
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    vim.cmd('edit ' .. dir .. '/a.txt')
    vim.cmd('edit ' .. dir .. '/b.txt')
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')
    local win = vim.api.nvim_get_current_win()
    T.eq(vim.api.nvim_win_get_buf(win), b_buf)

    local ok = cycle.delete_keep_windows(b_buf)
    T.ok(ok)
    T.eq(vim.api.nvim_buf_is_valid(b_buf), false)
    T.ok(vim.api.nvim_win_is_valid(win))
    T.eq(vim.api.nvim_win_get_buf(win), a_buf, 'window falls back to the other open file')

    vim.cmd('%bwipeout!')
    T.rmrf(dir)
  end)
end)

T.summary()
