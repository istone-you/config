-- ターミナルバッファをバッファリストから除外（タブライン・bnext/bprev から隠す）
vim.api.nvim_create_autocmd('TermOpen', {
  callback = function()
    vim.opt_local.buflisted = false
  end,
})

-- ターミナルモードではシェル/TUIでよく使う Ctrl-k/l を奪わず、実用上移動先がある h/j だけ張る
vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w>h', { desc = 'Move to left window from terminal' })
vim.keymap.set('t', '<C-j>', '<C-\\><C-n><C-w>j', { desc = 'Move to lower window from terminal' })
-- ノーマルモードから Ctrl+h/j/k/l で上下左右のウィンドウへ移動（ターミナル・explorerなどマウス無しで切替）
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move to left window' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move to lower window' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move to upper window' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move to right window' })

-- ターミナルウィンドウに入ったとき自動でターミナルモードへ（ジョブ実行中のみ）
vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
  pattern = 'term://*',
  callback = function()
    local job_id = vim.b.terminal_job_id
    if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
      vim.cmd('startinsert')
    end
  end,
})
