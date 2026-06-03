local scrollbar_bufs = {}
local scrollbar_wins = {}
local scrollbar_win_ids = {}
local ns = vim.api.nvim_create_namespace('scrollbar')
local updating = false

local function is_scrollbar_win(win_id)
  return scrollbar_win_ids[win_id] == true
end

local function close_scrollbar(win_id)
  local sb_win = scrollbar_wins[win_id]
  if sb_win then
    scrollbar_win_ids[sb_win] = nil
    if vim.api.nvim_win_is_valid(sb_win) then
      pcall(vim.api.nvim_win_close, sb_win, true)
    end
    scrollbar_wins[win_id] = nil
  end
  local sb_buf = scrollbar_bufs[win_id]
  if sb_buf and vim.api.nvim_buf_is_valid(sb_buf) then
    pcall(vim.api.nvim_buf_delete, sb_buf, { force = true })
    scrollbar_bufs[win_id] = nil
  end
end

local function update_scrollbar(win_id)
  if not vim.api.nvim_win_is_valid(win_id) then return end

  local ok, win_config = pcall(vim.api.nvim_win_get_config, win_id)
  if not ok or win_config.relative ~= '' or is_scrollbar_win(win_id) then
    return
  end

  local buf = vim.api.nvim_win_get_buf(win_id)
  local buf_type = vim.bo[buf].buftype
  if buf_type ~= '' and buf_type ~= 'help' then
    close_scrollbar(win_id)
    return
  end

  local total_lines = vim.api.nvim_buf_line_count(buf)
  local win_height = vim.api.nvim_win_get_height(win_id)

  if win_height <= 0 or total_lines <= win_height then
    close_scrollbar(win_id)
    return
  end

  local topline = vim.api.nvim_win_call(win_id, function()
    return vim.fn.line('w0')
  end)

  local thumb_size = math.max(1, math.floor(win_height * win_height / total_lines))
  local scrollable = total_lines - win_height
  local thumb_start = scrollable > 0
    and math.min(
      math.floor((topline - 1) * (win_height - thumb_size) / scrollable),
      win_height - thumb_size
    )
    or 0

  local content = {}
  for i = 1, win_height do
    content[i] = (i > thumb_start and i <= thumb_start + thumb_size) and '█' or '│'
  end

  local win_pos = vim.api.nvim_win_get_position(win_id)
  local win_width = vim.api.nvim_win_get_width(win_id)
  local row = win_pos[1]
  local col = win_pos[2] + win_width - 1

  local sb_buf = scrollbar_bufs[win_id]
  if not sb_buf or not vim.api.nvim_buf_is_valid(sb_buf) then
    sb_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[sb_buf].bufhidden = 'wipe'
    scrollbar_bufs[win_id] = sb_buf
  end

  vim.bo[sb_buf].modifiable = true
  vim.api.nvim_buf_set_lines(sb_buf, 0, -1, false, content)
  vim.bo[sb_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(sb_buf, ns, 0, -1)
  for i = 0, win_height - 1 do
    local hl = (i >= thumb_start and i < thumb_start + thumb_size) and 'ScrollbarThumb' or 'ScrollbarTrack'
    vim.api.nvim_buf_add_highlight(sb_buf, ns, hl, i, 0, -1)
  end

  local sb_win = scrollbar_wins[win_id]
  if sb_win and vim.api.nvim_win_is_valid(sb_win) then
    pcall(vim.api.nvim_win_set_config, sb_win, {
      relative = 'editor',
      row = row,
      col = col,
      width = 1,
      height = win_height,
    })
  else
    local open_ok, result = pcall(vim.api.nvim_open_win, sb_buf, false, {
      relative = 'editor',
      row = row,
      col = col,
      width = 1,
      height = win_height,
      style = 'minimal',
      focusable = false,
      zindex = 250,
    })
    if open_ok then
      scrollbar_wins[win_id] = result
      scrollbar_win_ids[result] = true
    end
  end
end

local function update_all()
  if updating then return end
  updating = true
  vim.schedule(function()
    updating = false
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      if not is_scrollbar_win(win_id) then
        pcall(update_scrollbar, win_id)
      end
    end
  end)
end

local function set_hl()
  vim.api.nvim_set_hl(0, 'ScrollbarThumb', { fg = '#888888', bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'ScrollbarTrack', { fg = '#3a3a3a', bg = 'NONE' })
end

set_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_hl })

vim.api.nvim_create_autocmd(
  { 'WinScrolled', 'BufEnter', 'WinEnter', 'VimResized', 'TextChanged', 'TextChangedI', 'CursorMoved', 'CursorMovedI' },
  { callback = update_all }
)

vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(args)
    local win_id = tonumber(args.match)
    if not win_id then return end
    if is_scrollbar_win(win_id) then
      scrollbar_win_ids[win_id] = nil
      for w, sw in pairs(scrollbar_wins) do
        if sw == win_id then
          scrollbar_wins[w] = nil
          break
        end
      end
    else
      close_scrollbar(win_id)
    end
  end,
})
