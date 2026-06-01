-- VSCode風バッファタブライン（Nerd Fontsアイコン付き）

local function i(code) return vim.fn.nr2char(code) .. ' ' end

local icons = {
  lua        = i(0xe620),
  ts         = i(0xe628),
  tsx        = i(0xe628),
  js         = i(0xe74e),
  jsx        = i(0xe74e),
  go         = i(0xe626),
  py         = i(0xe606),
  rs         = i(0xe7a8),
  rb         = i(0xe739),
  java       = i(0xe738),
  kt         = i(0xe634),
  swift      = i(0xe755),
  html       = i(0xe736),
  css        = i(0xe749),
  scss       = i(0xe603),
  json       = i(0xe60b),
  yaml       = i(0xe6d5),
  yml        = i(0xe6d5),
  toml       = i(0xe6b2),
  md         = i(0xe73e),
  sh         = i(0xe615),
  bash       = i(0xe615),
  zsh        = i(0xe615),
  vim        = i(0xe62b),
  tf         = i(0xe69a),
  tfvars     = i(0xe69a),
  graphql    = i(0xe662),
  sql        = i(0xe706),
  php        = i(0xe73d),
  c          = i(0xe61e),
  cpp        = i(0xe61d),
  cs         = i(0xe648),
  dockerfile = i(0xe650),
  gitignore  = i(0xe65d),
  env        = i(0xf462),
  lock       = i(0xf023),
  default    = i(0xf15b),
}

local function get_icon(filename)
  local ext = filename:match('%.([^%.]+)$')
  if filename:lower() == 'dockerfile' then return icons.dockerfile end
  if filename:lower():match('%.env') then return icons.env end
  if filename:lower():match('gitignore') then return icons.gitignore end
  return icons[ext] or icons.default
end

local function set_highlights()
  vim.api.nvim_set_hl(0, 'TabLineFill',     { bg = '#252526' })
  vim.api.nvim_set_hl(0, 'TabLine',         { fg = '#8b8b8b', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineSel',      { fg = '#ffffff', bg = '#1e1e1e', underline = true, sp = '#007acc' })
  vim.api.nvim_set_hl(0, 'TabLineMod',      { fg = '#e8a44a', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineModSel',   { fg = '#e8a44a', bg = '#1e1e1e', underline = true, sp = '#007acc' })
  vim.api.nvim_set_hl(0, 'TabLineClose',    { fg = '#555555', bg = '#2d2d2d' })
  vim.api.nvim_set_hl(0, 'TabLineCloseSel', { fg = '#aaaaaa', bg = '#1e1e1e' })
end

_G._bufline_click = function(bufnr, _, button)
  if button == 'l' then
    vim.api.nvim_set_current_buf(bufnr)
  end
end

_G._bufline_close = function(bufnr, _, button)
  if button == 'l' then
    local bufs = vim.tbl_filter(function(b)
      return vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b)
    end, vim.api.nvim_list_bufs())
    if #bufs > 1 then
      if vim.api.nvim_get_current_buf() == bufnr then
        vim.cmd('bprev')
      end
      vim.cmd('bd ' .. bufnr)
    end
  end
end

local function tabline()
  local s = ''
  local current = vim.api.nvim_get_current_buf()

  local buffers = vim.tbl_filter(function(b)
    return vim.bo[b].buflisted and vim.api.nvim_buf_is_valid(b)
  end, vim.api.nvim_list_bufs())

  for _, bufnr in ipairs(buffers) do
    local name     = vim.api.nvim_buf_get_name(bufnr)
    name           = name ~= '' and vim.fn.fnamemodify(name, ':t') or '[No Name]'
    local icon     = get_icon(name)
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
