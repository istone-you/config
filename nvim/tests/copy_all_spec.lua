local T = dofile(TESTS_DIR .. '/helpers.lua')
vim.g.mapleader = ' '
require('config.copy_all')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('copy_all', function()
  T.it('<leader>A copies the entire buffer to the clipboard', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'one', 'two', 'three' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/f.txt'))

    feed('<leader>A')
    vim.wait(50)
    T.eq(vim.fn.getreg('"'), 'one\ntwo\nthree')

    vim.cmd('bwipeout!')
    T.rmrf(dir)
  end)
end)

T.summary()
