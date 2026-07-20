-- ターミナルバッファをバッファリストから除外（タブライン・bnext/bprev から隠す）
vim.api.nvim_create_autocmd('TermOpen', {
  callback = function()
    vim.opt_local.buflisted = false
  end,
})

-- ターミナルモードから Ctrl+h でエディタ（左ウィンドウ）へ戻る
vim.keymap.set('t', '<C-h>', '<C-\\><C-n><C-w>h', { desc = 'Move to left window from terminal' })
-- ノーマルモードから Ctrl+h / Ctrl+l で左右のウィンドウへ移動（ターミナル・ファイラーなどマウス無しで切替）
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move to left window' })
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
