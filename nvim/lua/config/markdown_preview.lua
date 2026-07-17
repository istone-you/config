-- Markdown プレビュー（lua/config/markview にソースを同梱）
-- 元: https://github.com/OXY2DEV/markview.nvim

require('config.markview.autocmds').setup()
require('config.markview.commands').setup()

require('config.markview').setup({
  preview = {
    enable = false,
    icon_provider = 'internal',
  },
})

-- デフォルトの MarkviewInlineCode は fg が @markup.raw (= Comment グレー) のため
-- 文字色が通常テキストと区別しにくい。
-- 背景色は markview が出したデフォルト値を維持し、fg だけ Identifier 色にする。
local function set_inline_code_fg()
  local inline = vim.api.nvim_get_hl(0, { name = 'MarkviewInlineCode', link = false })
  local ident = vim.api.nvim_get_hl(0, { name = 'Identifier', link = false })
  if not ident.fg or not inline.bg then
    return
  end
  vim.api.nvim_set_hl(0, 'MarkviewInlineCode', {
    fg = ident.fg,
    bg = inline.bg,
  })
end

vim.api.nvim_create_autocmd({ 'VimEnter', 'ColorScheme' }, {
  callback = function()
    -- markview のハンドラ（highlights.setup）より後に実行する
    vim.schedule(set_inline_code_fg)
  end,
})

vim.keymap.set('n', '<leader>md', '<cmd>Markview toggle<cr>', {
  desc = 'Toggle markdown preview',
})
