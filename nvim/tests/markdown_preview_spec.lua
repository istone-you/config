-- markdown_preview.luaはmarkview本体(vendored、テスト対象外)への薄い設定ラッパー。
-- ここではmarkview自体ではなく、このファイル自身が持つロジック
-- (MarkviewInlineCodeの文字色をColorScheme時に上書きする処理)だけを検証する
local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.markdown_preview')

T.describe('markdown_preview.lua: MarkviewInlineCode fg override', function()
  T.it('ColorScheme replaces MarkviewInlineCode fg with Identifier fg, keeping its own bg', function()
    vim.api.nvim_set_hl(0, 'Identifier', { fg = '#ff00ff' })
    vim.api.nvim_set_hl(0, 'MarkviewInlineCode', { fg = '#888888', bg = '#222222' })

    vim.cmd('doautocmd ColorScheme')
    T.wait_until(function()
      return vim.api.nvim_get_hl(0, { name = 'MarkviewInlineCode', link = false }).fg == 0xff00ff
    end)

    local inline = vim.api.nvim_get_hl(0, { name = 'MarkviewInlineCode', link = false })
    T.eq(inline.fg, 0xff00ff, 'fg should be taken from Identifier')
    T.eq(inline.bg, 0x222222, 'bg should be left untouched')
  end)

  T.it('does nothing (no crash) when Identifier has no fg or MarkviewInlineCode has no bg', function()
    vim.api.nvim_set_hl(0, 'Identifier', {}) -- fgなし
    vim.api.nvim_set_hl(0, 'MarkviewInlineCode', { fg = '#888888', bg = '#222222' })

    vim.cmd('doautocmd ColorScheme')
    vim.wait(50)

    local inline = vim.api.nvim_get_hl(0, { name = 'MarkviewInlineCode', link = false })
    T.eq(inline.fg, 0x888888, 'should be left unchanged when Identifier has no fg to copy')
  end)
end)

T.describe('markdown_preview.lua: keymap', function()
  T.it('<leader>md runs :Markview toggle', function()
    -- <cmd>...<cr>マッピングはVimのコマンドライン経由で実行され、vim.cmdの
    -- Lua差し替えでは捕まえられないため、Markviewユーザーコマンド自体を
    -- 一時的に差し替えて引数を確認する
    local received_args
    vim.api.nvim_del_user_command('Markview')
    vim.api.nvim_create_user_command('Markview', function(opts) received_args = opts.args end, { nargs = '*' })

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<leader>md', true, false, true), 'x', false)

    T.eq(received_args, 'toggle')
  end)
end)

T.summary()
