-- コマンドログを @ で拡大した時に、中身を選択コピーできること（git/docker 共通の
-- panel/shell.lua の挙動）。拡大中はテキストカーソルを表示し、マウスのドラッグ選択を
-- 横取りしない（expr な <LeftMouse> マップ）ことで、キーボード/マウスどちらでも
-- 選択→ヤンクできるようにしている。
local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('git_panel command log copy (@ 拡大時の選択コピー)', function()
  T.it('shows the text cursor while expanded and restores the hidden cursor on collapse', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    local cl = GP.win_by_title('Command Log')
    T.ok(cl ~= nil, 'command log window should exist')
    local clbuf = vim.api.nvim_win_get_buf(cl)
    T.eq(vim.b[clbuf].hide_cursor, true, 'cursor is hidden before expanding')

    GP.press('@')
    T.eq(vim.b[clbuf].hide_cursor, false, 'cursor becomes visible while expanded (selection is visible)')
    T.ok(not vim.o.guicursor:find('HiddenCursor'), 'guicursor is not the hidden one while expanded')
    T.eq(vim.api.nvim_get_current_buf(), clbuf, 'focus moves into the command log')

    GP.press('@')
    T.eq(vim.b[clbuf].hide_cursor, true, 'hidden cursor is restored on collapse')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('lets you select the whole log in visual mode and yank it to a register', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    local cl = GP.win_by_title('Command Log')
    local clbuf = vim.api.nvim_win_get_buf(cl)

    GP.press('@') -- 拡大するとフォーカスが cmdlog へ移る
    vim.api.nvim_set_current_win(cl)
    vim.fn.setreg('"', '')
    feed('ggVGy') -- 全行をビジュアル選択してヤンク

    local expected = table.concat(vim.api.nvim_buf_get_lines(clbuf, 0, -1, false), '\n')
    T.ok(#vim.fn.getreg('"') > 0, 'yank register should not be empty')
    T.contains(vim.fn.getreg('"'), expected, 'visual-mode yank copies the command log content')

    GP.press('@')
    GP.close()
    T.rmrf(dir)
  end)

  T.it('binds a buffer-local expr <LeftMouse> so mouse drag-selection is not hijacked', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    local cl = GP.win_by_title('Command Log')
    vim.api.nvim_set_current_win(cl)

    local m = vim.fn.maparg('<LeftMouse>', 'n', false, true)
    T.eq(m.expr, 1, '<LeftMouse> is an expr map (can defer to native selection while expanded)')
    T.eq(m.buffer, 1, '<LeftMouse> map is buffer-local to the command log')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
