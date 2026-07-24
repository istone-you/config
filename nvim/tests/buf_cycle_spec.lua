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

T.summary()
