local M = {}

local prompt_win   = nil
local prompt_buf   = nil
local results_win  = nil
local results_buf  = nil
local original_win = nil
local all_symbols  = {}
local filtered     = {}
local sel_idx      = 1
local hl_ns        = vim.api.nvim_create_namespace('namu_hl')
local augrp        = vim.api.nvim_create_augroup('namu', { clear = true })

local KIND_ICONS = {
  [1]='󰈔',[2]='󰆧',[3]='󰅩',[4]='',[5]='󰠱',[6]='󰊕',
  [7]='󰜢',[8]='󰇽',[9]='',[10]='󰕘',[11]='󰜰',[12]='󰊕',
  [13]='󰆦',[14]='󰏿',[15]='󰀬',[16]='󰎠',[17]='◩', [18]='󰅪',
  [19]='󰅩',[20]='󰌋',[21]='󰟢',[22]='󰕘',[23]='󰙅',[24]='󰉁',
  [25]='󰆕',[26]='󰊄',
}

local function close()
  vim.api.nvim_clear_autocmds({ group = augrp })
  for _, w in ipairs({ prompt_win, results_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_close(w, true)
    end
  end
  for _, b in ipairs({ prompt_buf, results_buf }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
  prompt_win, prompt_buf, results_win, results_buf, original_win = nil, nil, nil, nil, nil
  all_symbols, filtered = {}, {}
  sel_idx = 1
end

local function flatten(symbols, depth)
  local result = {}
  for _, sym in ipairs(symbols or {}) do
    local lnum, col
    if sym.location then
      lnum = sym.location.range.start.line + 1
      col  = sym.location.range.start.character
    else
      local r = sym.selectionRange or sym.range
      lnum = r.start.line + 1
      col  = r.start.character
    end
    table.insert(result, {
      name  = sym.name,
      kind  = sym.kind,
      depth = depth or 0,
      lnum  = lnum,
      col   = col,
      uri   = sym.location and sym.location.uri,
    })
    if sym.children and #sym.children > 0 then
      for _, child in ipairs(flatten(sym.children, (depth or 0) + 1)) do
        table.insert(result, child)
      end
    end
  end
  return result
end

local function render(width)
  if not results_buf or not vim.api.nvim_buf_is_valid(results_buf) then return end

  local lines = {}
  local content_w = width - 2  -- 左右ボーダー分を引く

  for _, sym in ipairs(filtered) do
    local icon   = KIND_ICONS[sym.kind] or '?'
    local indent = string.rep('  ', sym.depth)
    local lnum_s = string.format('%4d', sym.lnum)
    local prefix = indent .. icon .. ' '
    local avail  = content_w - vim.fn.strdisplaywidth(prefix) - #lnum_s - 1
    local name   = sym.name
    if vim.fn.strdisplaywidth(name) > avail then
      while vim.fn.strdisplaywidth(name) > avail - 1 and #name > 0 do
        name = name:sub(1, -2)
      end
      name = name .. '…'
    end
    local pad = avail - vim.fn.strdisplaywidth(name)
    table.insert(lines, prefix .. name .. string.rep(' ', math.max(0, pad)) .. ' ' .. lnum_s)
  end

  vim.bo[results_buf].modifiable = true
  vim.api.nvim_buf_set_lines(results_buf, 0, -1, false, lines)
  vim.bo[results_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(results_buf, hl_ns, 0, -1)
  if sel_idx >= 1 and sel_idx <= #filtered then
    vim.api.nvim_buf_add_highlight(results_buf, hl_ns, 'NamuSel', sel_idx - 1, 0, -1)
  end
  if results_win and vim.api.nvim_win_is_valid(results_win) and #filtered > 0 then
    vim.fn.win_execute(results_win, 'normal! ' .. sel_idx .. 'gg')
  end
end

local _width = 70

local function apply_filter(query)
  filtered = {}
  local q = (query or ''):lower()
  for _, sym in ipairs(all_symbols) do
    if q == '' or sym.name:lower():find(q, 1, true) then
      table.insert(filtered, sym)
    end
  end
  sel_idx = math.max(1, math.min(sel_idx, math.max(1, #filtered)))
  render(_width)
end

local function move_sel(delta)
  if #filtered == 0 then return end
  sel_idx = math.max(1, math.min(sel_idx + delta, #filtered))
  render(_width)
end

local function jump()
  if sel_idx < 1 or sel_idx > #filtered then return end
  local sym    = filtered[sel_idx]
  local target = original_win
  close()
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
  end
  if sym.uri then
    vim.cmd('edit ' .. vim.fn.fnameescape(vim.uri_to_fname(sym.uri)))
  end
  vim.api.nvim_win_set_cursor(0, { sym.lnum, sym.col })
  vim.cmd('normal! zz')
end

local function open(symbols)
  if #symbols == 0 then
    vim.notify('[namu] シンボルが見つかりませんでした', vim.log.levels.WARN)
    return
  end

  all_symbols  = flatten(symbols)
  filtered     = vim.deepcopy(all_symbols)
  sel_idx      = 1
  original_win = vim.api.nvim_get_current_win()

  local sw      = vim.o.columns
  local sh      = vim.o.lines - vim.o.cmdheight - 2
  local width   = math.min(70, sw - 4)
  local list_h  = math.min(#all_symbols, math.floor(sh * 0.6))
  local total_h = list_h + 3  -- prompt(1) + 上下ボーダー(2) + セパレーター(1) - 1
  local row     = math.floor((sh - total_h) / 2)
  local col     = math.floor((sw - width) / 2)
  _width = width

  prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buf].buftype   = 'nofile'
  vim.bo[prompt_buf].buflisted = false

  results_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[results_buf].buftype    = 'nofile'
  vim.bo[results_buf].buflisted  = false
  vim.bo[results_buf].modifiable = false

  -- 上半分: prompt（下ボーダーが ├──┤ のセパレーターになる）
  prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    relative  = 'editor',
    row       = row,
    col       = col,
    width     = width,
    height    = 1,
    style     = 'minimal',
    border    = { '╭', '─', '╮', '│', '┤', '─', '├', '│' },
    title     = ' Symbols ',
    title_pos = 'center',
    zindex    = 51,
  })
  vim.wo[prompt_win].winhighlight = 'Normal:NamuPrompt'

  -- 下半分: results（上ボーダーなし、左右と下ボーダーのみ）
  results_win = vim.api.nvim_open_win(results_buf, false, {
    relative  = 'editor',
    row       = row + 3,  -- top_border(1) + prompt_content(1) + separator(1)
    col       = col,
    width     = width,
    height    = list_h,
    style     = 'minimal',
    border    = { '', '', '', '│', '╯', '─', '╰', '│' },
    zindex    = 50,
    focusable = false,
  })
  vim.wo[results_win].cursorline     = true
  vim.wo[results_win].number         = false
  vim.wo[results_win].relativenumber = false
  vim.wo[results_win].signcolumn     = 'no'
  vim.wo[results_win].winhighlight   = 'Normal:NamuResults,CursorLine:NamuSel'

  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { '' })
  render(width)
  vim.cmd('startinsert')

  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    group    = augrp,
    buffer   = prompt_buf,
    callback = function()
      local text = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ''
      apply_filter(text)
    end,
  })

  local opts = { buffer = prompt_buf, nowait = true, silent = true }
  vim.keymap.set('i', '<C-j>',  function() move_sel(1) end,  opts)
  vim.keymap.set('i', '<C-k>',  function() move_sel(-1) end, opts)
  vim.keymap.set('i', '<Down>', function() move_sel(1) end,  opts)
  vim.keymap.set('i', '<Up>',   function() move_sel(-1) end, opts)
  vim.keymap.set('i', '<CR>',   function() vim.cmd('stopinsert'); jump() end,  opts)
  vim.keymap.set('i', '<Esc>',  function() vim.cmd('stopinsert'); close() end, opts)
  vim.keymap.set('i', '<C-c>',  function() vim.cmd('stopinsert'); close() end, opts)

  vim.api.nvim_create_autocmd('WinLeave', {
    group    = augrp,
    callback = function()
      local leaving = vim.api.nvim_get_current_win()
      if leaving ~= prompt_win then return end
      vim.schedule(function()
        local cur = vim.api.nvim_get_current_win()
        if cur ~= prompt_win and cur ~= results_win then
          close()
        end
      end)
    end,
  })
end

function M.symbols()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify('[namu] LSP クライアントが接続されていません', vim.log.levels.WARN)
    return
  end
  local params = { textDocument = { uri = vim.uri_from_bufnr(0) } }
  vim.lsp.buf_request_all(0, 'textDocument/documentSymbol', params, function(results)
    local symbols = {}
    for _, res in pairs(results) do
      if res.result then
        vim.list_extend(symbols, res.result)
      end
    end
    vim.schedule(function() open(symbols) end)
  end)
end

local function setup_hl()
  vim.api.nvim_set_hl(0, 'NamuPrompt',  { bg = '#1e2030' })
  vim.api.nvim_set_hl(0, 'NamuResults', { bg = '#1a1b26' })
  vim.api.nvim_set_hl(0, 'NamuSel',     { bg = '#2d3250' })
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

vim.keymap.set('n', '<leader>ss', M.symbols, { desc = 'Namu: シンボル検索' })

return M
