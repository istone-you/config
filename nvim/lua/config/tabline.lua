-- VSCode風バッファタブライン（Nerd Fontsアイコン付き）

-- アイコン定義は config.util.file_icons に集約（explorer/git_panel/tabline で共有）。
-- タブラインはアイコンの後ろに空白を1つ付けて表示する。
local file_icons = require('config.util.file_icons')

local function get_icon(filename, path)
  return file_icons.get(filename, false, path) .. ' '
end

local function set_highlights()
  vim.api.nvim_set_hl(0, 'TabLineFill',     { bg = 'NONE' }) -- タブが無い所は透明
  vim.api.nvim_set_hl(0, 'TabLine',         { fg = '#8b8b8b', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineSel',      { fg = '#ffffff', bg = '#1e1e1e', underline = true, sp = '#007acc' })
  vim.api.nvim_set_hl(0, 'TabLineMod',      { fg = '#e8a44a', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineModSel',   { fg = '#e8a44a', bg = '#1e1e1e', underline = true, sp = '#007acc' })
  vim.api.nvim_set_hl(0, 'TabLineClose',    { fg = '#555555', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineCloseSel', { fg = '#aaaaaa', bg = '#1e1e1e' })
end

_G._bufline_click = function(bufnr, _, button)
  if button == 'l' then
    require('config.util.win_util').open_buf(bufnr)
  end
end

_G._bufline_close = function(bufnr, _, button)
  if button == 'l' then
    local cycle = require('config.util.buf_cycle')
    local bufs = cycle.list()
    if #bufs > 1 then
      if vim.api.nvim_get_current_buf() == bufnr then
        cycle.prev()
      end
      vim.cmd('bd ' .. bufnr)
    end
  end
end

local function tabline()
  local s = ''
  local current = vim.api.nvim_get_current_buf()

  -- 左サイドバー(explorer)の上にはタブを出さず、エディタの上から始める
  local ok, explorer = pcall(require, 'config.explorer')
  local pad = (ok and explorer.sidebar_pad) and explorer.sidebar_pad() or 0
  if pad > 0 then
    s = s .. '%#TabLineFill#' .. string.rep(' ', pad)
  end

  local buffers = vim.tbl_filter(function(b)
    if not (vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype ~= 'terminal') then
      return false
    end
    -- 無名バッファ（[No Name]）はタブに出さない
    if vim.api.nvim_buf_get_name(b) == '' then
      return false
    end
    return true
  end, vim.api.nvim_list_bufs())

  for _, bufnr in ipairs(buffers) do
    local fullpath = vim.api.nvim_buf_get_name(bufnr)
    local name     = fullpath ~= '' and vim.fn.fnamemodify(fullpath, ':t') or '[No Name]'
    local icon     = get_icon(name, fullpath)
    local modified = vim.bo[bufnr].modified
    local is_cur   = bufnr == current

    s = s .. '%' .. bufnr .. '@v:lua._bufline_click@'

    if is_cur then
      s = s .. (modified and '%#TabLineModSel#' or '%#TabLineSel#')
    else
      s = s .. (modified and '%#TabLineMod#' or '%#TabLine#')
    end

    s = s .. '  ' .. icon .. name .. (modified and ' ●' or '') .. '  '
    s = s .. '%X'

    -- × ボタン
    s = s .. '%' .. bufnr .. '@v:lua._bufline_close@'
    s = s .. (is_cur and '%#TabLineCloseSel#' or '%#TabLineClose#')
    s = s .. '×  '
    s = s .. '%X'
  end

  s = s .. '%#TabLineFill#'
  return s
end

set_highlights()

vim.api.nvim_create_autocmd('ColorScheme', { callback = set_highlights })

_G._tabline = tabline
vim.opt.tabline = '%!v:lua._tabline()'
