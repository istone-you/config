-- Networksパネル: 一覧・削除・prune、右ペインは Config（docker network inspect）
-- （lazydocker の Networks パネル相当）

local docker = require('config.docker_panel.docker')
local tabs_mod = require('config.docker_panel.tabs')
local util = require('config.docker_panel.util')

local M = {}

local ctx
local networks = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local tabs = tabs_mod.new({ 'Config' })
--- show_detail からタブ描画のコールバックへ渡すため前方宣言する
local show_current

--- bridge/host/none は docker が最初から持つ組み込みネットワークで削除できない。
--- 削除操作の対象外だと分かるように淡く表示する
local BUILTIN = { bridge = true, host = true, none = true }

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.name end
end

local function still_current(name)
  if ctx.current_panel_name() ~= 'networks' then return false end
  local entry = current_entry()
  return entry ~= nil and entry.name == name
end

local function show_detail(entry)
  tabs:render(ctx, function() show_current() end)
  if not entry then
    ctx.set_right_lines({ '  (ネットワークがありません)' }, 'text', nil, 'networks:none')
    return
  end
  docker.inspect('network', entry.name, function(text)
    if not still_current(entry.name) then return end
    ctx.set_right_lines(vim.split(text ~= '' and text or '{}', '\n', { plain = true }), 'json', nil, entry.name .. ':config')
  end)
end

show_current = function()
  show_detail(current_entry())
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  push(string.format('  ネットワーク  (%d)', #networks), nil, 'GitPanelHeader')
  push('', nil)

  local name_w = 0
  for _, n in ipairs(networks) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(n.name))
  end
  name_w = math.min(name_w, 30)

  local remembered_row = nil
  for _, n in ipairs(networks) do
    local name = util.pad(n.name, name_w)
    push(string.format('  %s  %s', name, n.driver), n)
    local row = #lines - 1
    local name_end = #('  ' .. name)
    table.insert(hl_queue, { row, BUILTIN[n.name] and 'GitPanelDim' or 'GitPanelSection', 2, name_end })
    table.insert(hl_queue, { row, 'GitPanelDim', name_end, -1 })
    if cursor_mem == n.name then remembered_row = #lines end
  end
  if #networks == 0 then push('  (ネットワークなし)', nil) end

  total_rows = #lines
  ctx.set_left_lines(lines, hl_queue)

  local target = remembered_row
  if not target then
    for i = 1, total_rows do
      if line_entries[i] then target = i; break end
    end
  end
  if target then
    ctx.set_left_cursor(target)
    show_detail(line_entries[target])
  else
    show_detail(nil)
  end
end

function M.refresh(auto_capture)
  docker.networks(function(list)
    if ctx.current_panel_name() ~= 'networks' then return end
    networks = list
    if auto_capture then M.remember_cursor() end
    render()
  end)
end

local function remove()
  local entry = current_entry()
  if not entry then return end
  if BUILTIN[entry.name] then
    vim.notify('組み込みネットワーク（bridge/host/none）は削除できません', vim.log.levels.WARN)
    return
  end
  cursor_mem = entry.name
  ctx.confirm('削除しますか？\n' .. entry.name, function(ok)
    if not ok then return end
    docker.remove_network(entry.name, ctx.done_refresh(M.refresh, '削除'))
  end)
end

local function prune()
  ctx.confirm('未使用のネットワークを全て削除しますか？\ndocker network prune', function(ok)
    if not ok then return end
    docker.prune('networks', ctx.done_refresh(M.refresh, 'prune'))
  end)
end

function M.keymaps()
  return vim.tbl_extend('force', {
    d = remove,
    b = prune,
  }, tabs_mod.keymaps(tabs, show_current))
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    function(entry)
      cursor_mem = entry.name
      show_detail(entry)
    end
  )
  M.refresh()
end

return M
