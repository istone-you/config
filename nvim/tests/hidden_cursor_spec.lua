local T = dofile(TESTS_DIR .. '/helpers.lua')
local hc = require('config.hidden_cursor')

T.describe('hidden_cursor', function()
  T.it('mark_buffer hides the cursor while focused, restores it when leaving', function()
    local marked = vim.api.nvim_create_buf(false, true)
    local plain = vim.api.nvim_create_buf(false, true)
    local default_guicursor = vim.o.guicursor

    local marked_win = vim.api.nvim_open_win(marked, true, { relative = 'editor', width = 10, height = 3, row = 0, col = 0 })
    hc.mark_buffer(marked)
    T.contains(vim.o.guicursor, 'HiddenCursor', 'cursor should be hidden while on a marked buffer')

    local plain_win = vim.api.nvim_open_win(plain, true, { relative = 'editor', width = 10, height = 3, row = 5, col = 0 })
    T.eq(vim.o.guicursor, default_guicursor, 'cursor should be restored on an unmarked buffer')

    vim.api.nvim_set_current_win(marked_win)
    T.contains(vim.o.guicursor, 'HiddenCursor', 'cursor should hide again when refocusing the marked buffer')

    vim.api.nvim_win_close(marked_win, true)
    vim.api.nvim_win_close(plain_win, true)
  end)

  T.it('regression: swapping a buffer into a window (nvim_win_set_buf) does not leave the cursor visible', function()
    -- 実際に踏んだバグ: 新しいバッファを先にマークせずにnvim_win_set_bufで
    -- ウィンドウへ差し込むと、フォーカスしていない側のウィンドウでも一瞬
    -- BufEnterが飛び、その時「まだマークされていない」バッファとして判定されて
    -- カーソルが復活してしまっていた。マークを先に行えば再発しない
    local buf1 = vim.api.nvim_create_buf(false, true)
    local win1 = vim.api.nvim_open_win(buf1, true, { relative = 'editor', width = 10, height = 3, row = 0, col = 0 })
    hc.mark_buffer(buf1)
    T.contains(vim.o.guicursor, 'HiddenCursor')

    local buf2 = vim.api.nvim_create_buf(false, true)
    local win2 = vim.api.nvim_open_win(buf2, false, { relative = 'editor', width = 10, height = 3, row = 5, col = 0 })
    hc.mark_buffer(buf2) -- 差し込む前に必ずマーク
    vim.api.nvim_win_set_buf(win2, buf2)
    T.contains(vim.o.guicursor, 'HiddenCursor', 'focus never left win1, cursor must stay hidden')

    vim.api.nvim_win_close(win1, true)
    vim.api.nvim_win_close(win2, true)
  end)
end)

T.summary()
