local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.terminal')
require('config.term_utils')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('terminal (<leader>t)', function()
  T.it('binds Ctrl-h/j/k/l in normal mode and only Ctrl-h/j in terminal mode', function()
    local normal_expected = {
      ['<C-H>'] = '<C-W>h',
      ['<C-J>'] = '<C-W>j',
      ['<C-K>'] = '<C-W>k',
      ['<C-L>'] = '<C-W>l',
    }
    local terminal_expected = {
      ['<C-H>'] = '<C-\\><C-N><C-W>h',
      ['<C-J>'] = '<C-\\><C-N><C-W>j',
    }
    for key, rhs in pairs(normal_expected) do
      T.eq(vim.fn.maparg(key, 'n'), rhs)
    end
    for key, rhs in pairs(terminal_expected) do
      T.eq(vim.fn.maparg(key, 't'), rhs)
    end
    T.eq(vim.fn.maparg('<C-K>', 't'), '')
    T.eq(vim.fn.maparg('<C-L>', 't'), '')
  end)

  T.it('opens a terminal cwd\'d at the git root when inside a repo', function()
    local dir = T.tmp_git_repo(function(d)
      vim.fn.mkdir(d .. '/sub', 'p')
    end)
    vim.fn.chdir(dir .. '/sub') -- リポジトリのサブディレクトリから開く

    feed('<leader>t')
    vim.wait(150)
    local buf = vim.api.nvim_get_current_buf()
    T.eq(vim.bo[buf].buftype, 'terminal')
    T.contains(vim.api.nvim_buf_get_name(buf), vim.loop.fs_realpath(dir),
      'terminal should be rooted at the git top-level, not the subdirectory')
    T.eq(vim.bo[buf].buflisted, false, 'term_utils should hide terminal buffers from the buffer list')

    vim.cmd('bd! ' .. buf)
    T.rmrf(dir)
  end)

  T.it('falls back to the current directory outside a git repo', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    vim.fn.chdir(dir)

    feed('<leader>t')
    vim.wait(150)
    local buf = vim.api.nvim_get_current_buf()
    T.eq(vim.bo[buf].buftype, 'terminal')
    T.contains(vim.api.nvim_buf_get_name(buf), vim.loop.fs_realpath(dir))

    vim.cmd('bd! ' .. buf)
    T.rmrf(dir)
  end)
end)

T.summary()
