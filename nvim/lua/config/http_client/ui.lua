-- レスポンス表示パネル（.http バッファの右に縦分割で出す）

local win_util = require('config.util.win_util')

local M = {}

M.MAX_BODY_BYTES = 512 * 1024 -- これを超えるボディは切り詰めて表示する

local state = {
  buf = nil,
  win = nil,
  rerun = nil, -- init.lua が設定する再実行コールバック
  body = nil,  -- y でコピーする用の直近ボディ
}

M.state = state

-- ══════════════════════════════════════════════
-- 整形
-- ══════════════════════════════════════════════

--- JSON をキー順を保ったままインデントし直す（vim.json.decode はキー順が失われるため、
--- 文字列を走査して整形する）
function M.format_json(text)
  local res, indent = {}, 0
  local i, n = 1, #text
  local function pad() return string.rep('  ', indent) end

  while i <= n do
    local c = text:sub(i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local ch = text:sub(j, j)
        if ch == '\\' then
          j = j + 2
        elseif ch == '"' then
          break
        else
          j = j + 1
        end
      end
      table.insert(res, text:sub(i, j))
      i = j + 1
    elseif c == '{' or c == '[' then
      local close = (c == '{') and '}' or ']'
      local j = i + 1
      while j <= n and text:sub(j, j):match('%s') do j = j + 1 end
      if text:sub(j, j) == close then -- 空の {} / [] は1行のまま
        table.insert(res, c .. close)
        i = j + 1
      else
        indent = indent + 1
        table.insert(res, c .. '\n' .. pad())
        i = i + 1
      end
    elseif c == '}' or c == ']' then
      indent = math.max(indent - 1, 0)
      table.insert(res, '\n' .. pad() .. c)
      i = i + 1
    elseif c == ',' then
      table.insert(res, ',\n' .. pad())
      i = i + 1
    elseif c == ':' then
      table.insert(res, ': ')
      i = i + 1
    elseif c:match('%s') then
      i = i + 1
    else
      table.insert(res, c)
      i = i + 1
    end
  end
  return table.concat(res)
end

--- content-type が JSON でパースも通るときだけ整形する。それ以外は素通し
function M.format_body(body, content_type)
  if not body or body == '' then return body end
  local ct = (content_type or ''):lower()
  if not (ct:match('json') or (ct == '' and body:match('^%s*[%[{]'))) then
    return body
  end
  if not pcall(vim.json.decode, body) then return body end
  return M.format_json(body)
end

function M.format_size(bytes)
  if not bytes then return nil end
  if bytes < 1024 then return bytes .. ' B' end
  if bytes < 1024 * 1024 then return string.format('%.1f KB', bytes / 1024) end
  return string.format('%.1f MB', bytes / 1024 / 1024)
end

-- ══════════════════════════════════════════════
-- 表示内容の組み立て
-- ══════════════════════════════════════════════

--- 結果をバッファに載せる行リストへ変換する
function M.render(result, opts)
  opts = opts or {}
  local req = result.request or {}
  local lines = {}

  local function summary(text) table.insert(lines, '### ' .. text) end

  if result.loading then
    summary('実行中...')
  elseif result.ok then
    local parts = {}
    local status = result.status_code and tostring(result.status_code) or '?'
    if result.status_text then status = status .. ' ' .. result.status_text end
    table.insert(parts, status)
    if result.time_ms then table.insert(parts, result.time_ms .. ' ms') end
    local size = M.format_size(result.size)
    if size then table.insert(parts, size) end
    if opts.env then table.insert(parts, 'env: ' .. opts.env) end
    summary(table.concat(parts, ' · '))
  else
    summary('失敗: ' .. (result.error or '不明なエラー'):gsub('\n.*', ''))
  end
  summary((req.method or 'GET') .. ' ' .. (req.url or ''))
  if req.label and req.label ~= ((req.method or 'GET') .. ' ' .. (req.url or '')) then
    summary(req.label)
  end

  if not result.ok and result.error then
    table.insert(lines, '')
    vim.list_extend(lines, vim.split(result.error, '\n'))
    return lines
  end
  if result.loading then return lines end

  table.insert(lines, '')
  if result.status_line then table.insert(lines, result.status_line) end
  for _, h in ipairs(result.headers or {}) do
    table.insert(lines, h[1] .. ': ' .. h[2])
  end

  local body = M.format_body(result.body, result.content_type)
  if body and body ~= '' then
    local truncated = false
    if #body > M.MAX_BODY_BYTES then
      body = body:sub(1, M.MAX_BODY_BYTES)
      truncated = true
    end
    table.insert(lines, '')
    vim.list_extend(lines, vim.split(body, '\n'))
    if truncated then
      table.insert(lines, '')
      table.insert(lines, '### ボディが大きいため以降を省略しました')
    end
  end
  return lines
end

-- ══════════════════════════════════════════════
-- ウィンドウ
-- ══════════════════════════════════════════════

local function setup_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map('q', function() M.close() end, 'HTTP: レスポンスを閉じる')
  map('R', function()
    if state.rerun then state.rerun() end
  end, 'HTTP: 直前のリクエストを再実行')
  map('y', function()
    if not state.body or state.body == '' then
      vim.notify('コピーするボディがありません', vim.log.levels.WARN, { title = 'HTTP' })
      return
    end
    vim.fn.setreg('"', state.body)
    if vim.g.clipboard ~= nil then vim.fn.setreg('+', state.body) end
    vim.notify('レスポンスボディをコピーしました', vim.log.levels.INFO, { title = 'HTTP' })
  end, 'HTTP: レスポンスボディをコピー')
end

local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then return state.buf end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'httpresult'
  pcall(vim.api.nvim_buf_set_name, buf, 'HTTP Response')
  setup_keymaps(buf)
  state.buf = buf
  return buf
end

local function ensure_win()
  local buf = ensure_buf()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_buf(state.win, buf)
    return state.win
  end
  -- 既にどこかの窓に載っていればそれを使う
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    state.win = w
    return w
  end

  local cur = vim.api.nvim_get_current_win()
  vim.cmd('rightbelow vsplit') -- 現在の窓（.http）のすぐ右へ
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].wrap = false
  win_util.mark_sidebar(win, buf)
  state.win = win
  vim.api.nvim_set_current_win(cur) -- フォーカスは .http 側に残す
  return win
end

--- 結果（または loading 状態）を表示する
function M.show(result, opts)
  local lines = M.render(result, opts)
  local buf = ensure_buf()
  ensure_win()

  state.body = result.body
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
  end
  return buf
end

function M.show_loading(req, opts)
  return M.show({ loading = true, ok = true, request = req }, opts)
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    -- 最後の1窓なら閉じない（Neovim ごと終わってしまうため）
    if #vim.api.nvim_tabpage_list_wins(0) > 1 then
      vim.api.nvim_win_close(state.win, true)
    end
  end
  state.win = nil
end

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.set_rerun(fn)
  state.rerun = fn
end

return M
