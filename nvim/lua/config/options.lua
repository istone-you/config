vim.g.mapleader = " "

-- markview 等の guifg/guibg を端末で有効にする（これがないとインラインコード等の色が付かない）
vim.opt.termguicolors = true

vim.cmd.colorscheme('retrobox')

vim.api.nvim_set_hl(0, 'Normal',      { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'NormalNC',    { bg = 'NONE' })
-- サイン列(git gutter等)の背景も透明にする（editorが透過なので浮いて見えるのを防ぐ）
vim.api.nvim_set_hl(0, 'SignColumn',  { bg = 'NONE' })
-- ウィンドウ区切り線も背景を透明に（線色だけ残す）
vim.api.nvim_set_hl(0, 'WinSeparator', { bg = 'NONE', fg = '#565f89' })

-- カラースキームを変えても透過を維持
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function()
    vim.api.nvim_set_hl(0, 'Normal',       { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalFloat',  { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalNC',     { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'SignColumn',   { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'WinSeparator', { bg = 'NONE', fg = '#565f89' })
  end,
})

vim.opt.statusline = '%F%h%m%r%=%-14.(%l,%c%V%) %P'
vim.opt.showtabline = 2
vim.opt.number = true
vim.opt.relativenumber = true

vim.keymap.set('n', '<Tab>',   '<cmd>bnext<cr>',  { desc = 'Next buffer' })
vim.keymap.set('n', '<S-Tab>', '<cmd>bprev<cr>',  { desc = 'Prev buffer' })
vim.keymap.set('n', '<leader>q', function()
  local cur = vim.api.nvim_get_current_buf()
  if not vim.bo[cur].buflisted then return end -- スタート画面等の非listedバッファは対象外
  local bufs = vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b)
  end, vim.api.nvim_list_bufs())
  if #bufs > 1 then
    vim.cmd('bprev')
    vim.cmd('bd ' .. cur)
  else
    -- 最後の1つ: 閉じるとBufDeleteでスタート画面に戻る
    vim.cmd('bdelete ' .. cur)
  end
end, { desc = 'Close buffer' })

-- 空文字だとマウス無効。以前は options が init から読まれておらず実質オフだった
vim.opt.mouse = "nv"
vim.opt.mousescroll = "ver:1,hor:6"

-- コンテナ内に xclip 等がないため、ターミナル経由でホストのクリップボードへ送る（Cursor/VS Code 統合ターミナル向け）
vim.g.clipboard = {
    name = "OSC 52",
    copy = {
        ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
        ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
        ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
        ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
}
vim.opt.clipboard = "unnamedplus"

-- 外部変更の自動反映
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  command = "checktime",
})
