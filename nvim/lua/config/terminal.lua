vim.keymap.set('n', '<leader>t', function()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  local cwd = (git_root and git_root ~= '' and not git_root:match('^fatal')) and git_root or vim.fn.getcwd()
  vim.cmd('rightbelow vnew')
  vim.fn.termopen(os.getenv('SHELL') or 'sh', { cwd = cwd })
  vim.cmd('startinsert')
end, { desc = 'Open terminal on right' })

