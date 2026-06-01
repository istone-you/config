local ns = vim.api.nvim_create_namespace('hlchunk')

local function setup_hl()
  vim.api.nvim_set_hl(0, 'HLChunkLine', { fg = '#3d59a1' })
end

local function get_indent(line)
  if line:match('^%s*$') then return nil end
  return #line:match('^(%s*)')
end

local function update(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if vim.bo[buf].buftype ~= '' then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1

  local total = vim.api.nvim_buf_line_count(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, total, false)

  local cur_indent = get_indent(lines[lnum + 1] or '')
  if not cur_indent or cur_indent == 0 then return end

  local start_lnum = nil
  for i = lnum - 1, 0, -1 do
    local ind = get_indent(lines[i + 1] or '')
    if ind and ind < cur_indent then
      start_lnum = i
      break
    end
  end
  if not start_lnum then return end

  local start_indent = get_indent(lines[start_lnum + 1]) or 0

  local end_lnum = lnum
  for i = lnum + 1, total - 1 do
    local ind = get_indent(lines[i + 1] or '')
    if ind then
      if ind <= start_indent then
        end_lnum = i
        break
      end
      end_lnum = i
    end
  end

  if end_lnum <= start_lnum then return end

  local col = start_indent

  for i = start_lnum, end_lnum do
    local line = lines[i + 1] or ''
    local ind = get_indent(line)
    if (not ind) or col < ind then
      vim.api.nvim_buf_set_extmark(buf, ns, i, 0, {
        virt_text = { { '│', 'HLChunkLine' } },
        virt_text_win_col = col,
      })
    end
  end
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })
vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'BufEnter' }, {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= '' then return end
    update(buf)
  end,
})
