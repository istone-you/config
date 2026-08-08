-- エディタ上の現在地と選択範囲を、AI がそのまま読める JSON へ整形する。
-- ファイルをディスクから読み直すのではなく、nvim のバッファ内容を読むので未保存変更も見える。

local M = {}
local util = require('config.nvim_api.util')

local VISUAL_MODES = {
  v = true,
  V = true,
  ['\022'] = true, -- CTRL-V blockwise visual
  s = true,
  S = true,
  ['\019'] = true, -- CTRL-S blockwise select
}

local function current_buf_info(root)
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' or vim.bo[bufnr].buftype ~= '' then
    return nil, 'current buffer is not a file buffer'
  end
  local abs = util.real(name)
  if not abs then return nil, 'current buffer has no readable path' end
  if not util.allow_outside_root() then
    local base = util.normalize_root(root)
    if abs ~= base and abs:sub(1, #base + 1) ~= base .. '/' then
      return nil, 'path is outside the repository root: ' .. abs
    end
  end
  return bufnr, abs
end

local function line_count(bufnr)
  return vim.api.nvim_buf_line_count(bufnr)
end

local function line_len(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  return #line
end

local function char_end_col_exclusive(line, col1)
  local start0 = math.max((col1 or 1) - 1, 0)
  if start0 >= #line then return #line end
  local first = line:byte(start0 + 1)
  if not first then return start0 end
  local width = 1
  if first >= 0xF0 then
    width = 4
  elseif first >= 0xE0 then
    width = 3
  elseif first >= 0xC0 then
    width = 2
  end
  return math.min(start0 + width, #line)
end

local function normalize_range(bufnr, a_line, a_col, b_line, b_col, mode)
  local start_line, start_col = a_line, a_col
  local end_line, end_col = b_line, b_col
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  start_line = math.max(math.min(start_line, line_count(bufnr)), 1)
  end_line = math.max(math.min(end_line, line_count(bufnr)), 1)

  if mode == 'V' then
    return {
      start_line = start_line,
      start_col = 1,
      end_line = end_line,
      end_col = line_len(bufnr, end_line) + 1,
    }
  end

  local end_text = vim.api.nvim_buf_get_lines(bufnr, end_line - 1, end_line, false)[1] or ''
  return {
    start_line = start_line,
    start_col = math.max(start_col, 1),
    end_line = end_line,
    end_col = char_end_col_exclusive(end_text, math.max(end_col, 1)) + 1,
  }
end

local function text_for_range(bufnr, range)
  return table.concat(vim.api.nvim_buf_get_text(
    bufnr,
    range.start_line - 1,
    range.start_col - 1,
    range.end_line - 1,
    range.end_col - 1,
    {}
  ), '\n')
end

local function context_range(bufnr, context_lines)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local before_after = math.max(tonumber(context_lines) or 5, 0)
  local start_line = math.max(cursor_line - before_after, 1)
  local end_line = math.min(cursor_line + before_after, line_count(bufnr))
  return {
    start_line = start_line,
    start_col = 1,
    end_line = end_line,
    end_col = line_len(bufnr, end_line) + 1,
  }
end

function M.selection(root, opts)
  opts = opts or {}
  local bufnr, abs_or_err = current_buf_info(root)
  if not bufnr then return nil, abs_or_err end

  local mode = vim.api.nvim_get_mode().mode
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local cursor_col = cursor[2] + 1
  local out = {
    file = util.rel_path(abs_or_err, root),
    bufnr = bufnr,
    mode = mode,
    line = cursor_line,
    col = cursor_col,
    modified = vim.bo[bufnr].modified,
    selection = { active = false },
  }

  if VISUAL_MODES[mode] then
    local visual = vim.fn.getpos('v')
    local range = normalize_range(bufnr, visual[2], visual[3], cursor_line, cursor_col, mode)
    out.selection = {
      active = true,
      type = mode,
      range = range,
      text = text_for_range(bufnr, range),
    }
    return out
  end

  if opts.fallback == 'context' then
    local range = context_range(bufnr, opts.context_lines)
    out.context = {
      range = range,
      text = text_for_range(bufnr, range),
    }
  end
  return out
end

return M
