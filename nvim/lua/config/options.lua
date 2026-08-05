vim.g.mapleader = " "

-- 素の <Space>（デフォルトは右移動＝l と同じで実質使わない）を無効化する。
-- leader を <Space> にしたので、単独 <Space> には意味を持たせない。<Space>◯ の
-- マッピングやバッファローカルな Space（git パネル等）はこれに影響されない。
vim.keymap.set({ 'n', 'x' }, '<Space>', '<Nop>')

-- guifg/guibg を端末で有効にする（これがないとインラインコード等の色が付かない）
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

-- 下部ステータスラインは廃止（ファイルパスは winbar に出す）。フォーカス表示は
-- config.active_cursorline がアクティブ窓の cursorline で担う。
vim.opt.laststatus = 0
vim.opt.showtabline = 2
vim.opt.number = true
vim.opt.relativenumber = true

-- インデントの既定値。素の Neovim は ts=8 / sw=8 / noexpandtab で、lua や typescript には
-- 幅を設定する ftplugin が無いため、2 スペースのファイルにハードタブが混入していた。
-- ファイルごとの実際の幅は config.indent が中身から検出して上書きする
-- （優先順位: .editorconfig > 自動検出 > ここの既定値）。
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.softtabstop = 2

vim.keymap.set('n', '<Tab>', function()
  require('config.util.buf_cycle').next()
end, { desc = 'Next buffer' })
vim.keymap.set('n', '<S-Tab>', function()
  require('config.util.buf_cycle').prev()
end, { desc = 'Prev buffer' })

local function close_buffer(buf)
  return pcall(vim.api.nvim_buf_delete, buf, {})
end

local function notify_unsaved_buffers(count)
  vim.notify(string.format('%d件の未保存バッファは閉じませんでした', count), vim.log.levels.WARN)
end

vim.keymap.set('n', '<leader>q', function()
  local cur = vim.api.nvim_get_current_buf()
  if not vim.bo[cur].buflisted then return end -- スタート画面等の非listedバッファは対象外
  if vim.bo[cur].modified then
    notify_unsaved_buffers(1)
    return
  end
  local bufs = require('config.util.buf_cycle').list()
  if #bufs > 1 then
    require('config.util.buf_cycle').prev()
    close_buffer(cur)
  else
    -- 最後の1つ: 閉じるとBufDeleteでスタート画面に戻る
    close_buffer(cur)
  end
end, { desc = 'Close buffer' })
vim.keymap.set('n', '<leader>Q', function()
  local bufs = require('config.util.buf_cycle').list()
  local failed = 0
  for _, b in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buflisted then
      if vim.bo[b].modified then
        failed = failed + 1
      elseif not close_buffer(b) then
        failed = failed + 1
      end
    end
  end
  if failed > 0 then
    notify_unsaved_buffers(failed)
  end
end, { desc = 'Close all buffer tabs' })

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
