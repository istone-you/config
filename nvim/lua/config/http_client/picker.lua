-- リクエスト / 環境を選ぶポップアップ（namu と同じ prompt + results の2窓構成）。
-- 入力で絞り込み、Ctrl-j/k（↓/↑）で移動、Enter で決定、Esc / Ctrl-c で閉じる。

local M = {}

local hl_ns = vim.api.nvim_create_namespace('http_picker')
local augrp = vim.api.nvim_create_augroup('http_picker', { clear = true })

local state = {
  prompt_win = nil,
  prompt_buf = nil,
  results_win = nil,
  results_buf = nil,
  origin_win = nil,
  items = {},
  filtered = {},
  sel = 1,
  width = 60,
  format = nil,
  on_select = nil,
}

M.state = state

-- メソッドごとに色を変えて一覧を見分けやすくする
local METHOD_HL = {
  GET = 'HttpPickerGet',
  HEAD = 'HttpPickerGet',
  OPTIONS = 'HttpPickerGet',
  POST = 'HttpPickerWrite',
  PUT = 'HttpPickerWrite',
  PATCH = 'HttpPickerWrite',
  DELETE = 'HttpPickerDelete',
}

function M.close()
  vim.api.nvim_clear_autocmds({ group = augrp })
  for _, w in ipairs({ state.prompt_win, state.results_win }) do
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_close(w, true)
    end
  end
  for _, b in ipairs({ state.prompt_buf, state.results_buf }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
  state.prompt_win, state.prompt_buf = nil, nil
  state.results_win, state.results_buf = nil, nil
  state.origin_win = nil
  state.items, state.filtered = {}, {}
  state.sel = 1
end

function M.is_open()
  return state.results_buf ~= nil and vim.api.nvim_buf_is_valid(state.results_buf)
end

--- 表示行を作る。左にメソッド等のタグ、右端に行番号（あれば）
local function line_for(item)
  local f = state.format(item)
  local tag = f.tag or ''
  local text = f.text or ''
  local right = f.right or ''
  local content_w = state.width - 2
  local avail = content_w - #tag - 1 - #right - 1
  if vim.fn.strdisplaywidth(text) > avail then
    while vim.fn.strdisplaywidth(text) > avail - 1 and #text > 0 do
      text = text:sub(1, -2)
    end
    text = text .. '…'
  end
  local pad = math.max(0, avail - vim.fn.strdisplaywidth(text))
  return string.format('%s %s%s %s', tag, text, string.rep(' ', pad), right), #tag
end

local function render()
  if not M.is_open() then return end

  local lines, tag_widths = {}, {}
  for _, item in ipairs(state.filtered) do
    local line, tag_w = line_for(item)
    table.insert(lines, line)
    table.insert(tag_widths, tag_w)
  end
  if #lines == 0 then
    lines = { ' 一致するものがありません' }
  end

  vim.bo[state.results_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.results_buf, 0, -1, false, lines)
  vim.bo[state.results_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.results_buf, hl_ns, 0, -1)
  for i, item in ipairs(state.filtered) do
    local hl = state.format(item).tag_hl
    if hl and tag_widths[i] > 0 then
      vim.api.nvim_buf_set_extmark(state.results_buf, hl_ns, i - 1, 0, {
        end_col = tag_widths[i],
        hl_group = hl,
      })
    end
  end
  if state.sel >= 1 and state.sel <= #state.filtered then
    vim.api.nvim_buf_set_extmark(state.results_buf, hl_ns, state.sel - 1, 0, {
      end_row = state.sel,
      end_col = 0,
      hl_group = 'HttpPickerSel',
      hl_eol = true,
      priority = 200,
    })
    if state.results_win and vim.api.nvim_win_is_valid(state.results_win) then
      vim.fn.win_execute(state.results_win, 'normal! ' .. state.sel .. 'gg')
    end
  end
end

function M.filter(query)
  local q = (query or ''):lower()
  state.filtered = {}
  for _, item in ipairs(state.items) do
    local f = state.format(item)
    local hay = ((f.tag or '') .. ' ' .. (f.text or '')):lower()
    if q == '' or hay:find(q, 1, true) then
      table.insert(state.filtered, item)
    end
  end
  state.sel = math.max(1, math.min(state.sel, math.max(1, #state.filtered)))
  render()
end

function M.move(delta)
  if #state.filtered == 0 then return end
  state.sel = math.max(1, math.min(state.sel + delta, #state.filtered))
  render()
end

function M.confirm()
  local item = state.filtered[state.sel]
  local on_select, origin = state.on_select, state.origin_win
  M.close()
  if not item then return end
  if origin and vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
  if on_select then on_select(item) end
end

--- opts = {
---   title     = ポップアップのタイトル,
---   items     = 選択肢のリスト,
---   format    = function(item) -> { tag, tag_hl, text, right },
---   on_select = function(item),
--- }
function M.open(opts)
  if #opts.items == 0 then return end
  M.close()

  state.items = opts.items
  state.filtered = vim.deepcopy(opts.items)
  state.sel = 1
  state.format = opts.format
  state.on_select = opts.on_select
  state.origin_win = vim.api.nvim_get_current_win()

  local sw = vim.o.columns
  local sh = vim.o.lines - vim.o.cmdheight - 2
  local width = math.min(72, sw - 4)
  local list_h = math.max(1, math.min(#opts.items, math.floor(sh * 0.6)))
  local total_h = list_h + 3
  local row = math.floor((sh - total_h) / 2)
  local col = math.floor((sw - width) / 2)
  state.width = width

  state.prompt_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.prompt_buf].buftype = 'nofile'
  vim.bo[state.prompt_buf].buflisted = false

  state.results_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.results_buf].buftype = 'nofile'
  vim.bo[state.results_buf].buflisted = false
  vim.bo[state.results_buf].modifiable = false
  vim.bo[state.results_buf].filetype = 'httppicker'

  state.prompt_win = vim.api.nvim_open_win(state.prompt_buf, true, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = 1,
    style = 'minimal',
    border = { '╭', '─', '╮', '│', '┤', '─', '├', '│' },
    title = opts.title,
    title_pos = 'center',
    zindex = 51,
  })

  state.results_win = vim.api.nvim_open_win(state.results_buf, false, {
    relative = 'editor',
    row = row + 3,
    col = col,
    width = width,
    height = list_h,
    style = 'minimal',
    border = { '', '', '', '│', '╯', '─', '╰', '│' },
    zindex = 50,
    focusable = false,
  })
  vim.wo[state.results_win].cursorline = false
  vim.wo[state.results_win].number = false
  vim.wo[state.results_win].relativenumber = false
  vim.wo[state.results_win].signcolumn = 'no'
  vim.wo[state.results_win].wrap = false

  vim.api.nvim_buf_set_lines(state.prompt_buf, 0, -1, false, { '' })
  render()
  vim.cmd('startinsert')

  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    group = augrp,
    buffer = state.prompt_buf,
    callback = function()
      M.filter(vim.api.nvim_buf_get_lines(state.prompt_buf, 0, 1, false)[1] or '')
    end,
  })

  local map_opts = { buffer = state.prompt_buf, nowait = true, silent = true }
  local function imap(lhs, fn)
    vim.keymap.set('i', lhs, fn, map_opts)
  end
  imap('<C-j>', function() M.move(1) end)
  imap('<C-k>', function() M.move(-1) end)
  imap('<Down>', function() M.move(1) end)
  imap('<Up>', function() M.move(-1) end)
  imap('<CR>', function()
    vim.cmd('stopinsert')
    M.confirm()
  end)
  imap('<Esc>', function()
    vim.cmd('stopinsert')
    M.close()
  end)
  imap('<C-c>', function()
    vim.cmd('stopinsert')
    M.close()
  end)

  -- ポップアップ外へフォーカスが移ったら閉じる
  vim.api.nvim_create_autocmd('WinLeave', {
    group = augrp,
    callback = function()
      if vim.api.nvim_get_current_win() ~= state.prompt_win then return end
      vim.schedule(function()
        local cur = vim.api.nvim_get_current_win()
        if cur ~= state.prompt_win and cur ~= state.results_win then M.close() end
      end)
    end,
  })
end

function M.method_hl(method)
  return METHOD_HL[(method or ''):upper()] or 'HttpPickerGet'
end

local function setup_hl()
  local function link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  link('HttpPickerSel', 'PmenuSel')
  link('HttpPickerGet', 'DiagnosticOk')
  link('HttpPickerWrite', 'DiagnosticWarn')
  link('HttpPickerDelete', 'DiagnosticError')
end

setup_hl()
-- augrp は close() でまとめて消すので、配色の再設定は別グループに置く
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('http_picker_hl', { clear = true }),
  callback = setup_hl,
})

return M
