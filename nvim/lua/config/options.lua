vim.g.mapleader = " "

vim.cmd.colorscheme('retrobox')

vim.api.nvim_set_hl(0, 'Normal',      { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
vim.api.nvim_set_hl(0, 'NormalNC',    { bg = 'NONE' })

-- カラースキームを変えても透過を維持
vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function()
    vim.api.nvim_set_hl(0, 'Normal',      { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = 'NONE' })
    vim.api.nvim_set_hl(0, 'NormalNC',    { bg = 'NONE' })
  end,
})

vim.opt.showtabline = 2

vim.keymap.set('n', '<Tab>',   '<cmd>bnext<cr>',  { desc = 'Next buffer' })
vim.keymap.set('n', '<S-Tab>', '<cmd>bprev<cr>',  { desc = 'Prev buffer' })

-- 空文字だとマウス無効。以前は options が init から読まれておらず実質オフだった
vim.opt.mouse = "nv"

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
