local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.scrollbar')

--- update_allはWinScrolled等の実イベントでしか起動しないので、CursorMovedを
--- 実際に発火させてからスケジュールされたコールバックが片付くまで待つ
local function trigger(buf)
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  vim.wait(100)
end

local function find_scrollbar_win(near_col)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative == 'editor' and cfg.width == 1 and cfg.zindex == 45 then
      if not near_col or cfg.col == near_col then return w end
    end
  end
end

T.describe('scrollbar', function()
  T.it('shows a 1-col floating scrollbar on a real split when content exceeds the window height', function()
    vim.cmd('only')
    local buf = vim.api.nvim_create_buf(true, false)
    local lines = {}
    for i = 1, 200 do lines[i] = 'line ' .. i end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    vim.cmd('resize 10') -- 200行 > 高さ10なのでスクロール可能
    local win = vim.api.nvim_get_current_win()

    trigger(buf)
    local win_pos = vim.api.nvim_win_get_position(win)
    local win_width = vim.api.nvim_win_get_width(win)
    local sb = find_scrollbar_win(win_pos[2] + win_width - 1)
    T.ok(sb ~= nil, 'a scrollbar window should appear')
    T.eq(vim.api.nvim_win_get_config(sb).height, vim.api.nvim_win_get_height(win))
  end)

  T.it('shows no scrollbar when the whole buffer fits in the window', function()
    vim.cmd('only')
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b', 'c' })
    vim.api.nvim_set_current_buf(buf)
    local win = vim.api.nvim_get_current_win()
    trigger(buf)
    local win_pos = vim.api.nvim_win_get_position(win)
    local win_width = vim.api.nvim_win_get_width(win)
    T.ok(find_scrollbar_win(win_pos[2] + win_width - 1) == nil, 'no scrollbar expected when content fits')
  end)

  T.it('the thumb moves toward the bottom as you scroll down', function()
    vim.cmd('only')
    local buf = vim.api.nvim_create_buf(true, false)
    local lines = {}
    for i = 1, 200 do lines[i] = 'line ' .. i end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    vim.cmd('resize 10')
    local win = vim.api.nvim_get_current_win()

    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    trigger(buf)
    local win_pos = vim.api.nvim_win_get_position(win)
    local win_width = vim.api.nvim_win_get_width(win)
    local sb = find_scrollbar_win(win_pos[2] + win_width - 1)
    local top_content = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sb), 0, -1, false)
    local top_thumb_row = nil
    for i, l in ipairs(top_content) do if l == '█' then top_thumb_row = i; break end end

    vim.api.nvim_win_set_cursor(win, { 200, 0 })
    vim.cmd('normal! zb')
    trigger(buf)
    local bottom_content = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sb), 0, -1, false)
    local bottom_thumb_row = nil
    for i, l in ipairs(bottom_content) do if l == '█' then bottom_thumb_row = i; break end end

    T.ok(top_thumb_row ~= nil and bottom_thumb_row ~= nil, 'thumb should be found in both cases')
    T.ok(bottom_thumb_row > top_thumb_row, 'thumb should move down as the view scrolls down')
  end)
end)

T.summary()
