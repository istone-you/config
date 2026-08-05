-- Volumesパネル: 一覧・削除・prune、右ペインは Config（docker volume inspect）
-- （lazydocker の Volumes パネル相当）

local docker = require('config.docker_panel.docker')
local tabs_mod = require('config.docker_panel.tabs')
local util = require('config.docker_panel.util')

local M = {}

local ctx
local volumes = {}
--- どのコンテナからも参照されていないボリューム名の集合（使用中/未使用の仕分け用）
local unused = {}
--- ボリューム名→サイズ表記。`docker system df -v` は重いので自動更新では取り直さず、
--- パネルを開いた時と R を押した時だけ更新して、その間はこの値を出し続ける
local sizes = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local tabs = tabs_mod.new({ 'Config' })
--- show_detail からタブ描画のコールバックへ渡すため前方宣言する
local show_current

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.name end
end

local function still_current(name)
  if ctx.current_panel_name() ~= 'volumes' then return false end
  local entry = current_entry()
  return entry ~= nil and entry.name == name
end

local function show_detail(entry)
  tabs:render(ctx, function() show_current() end)
  if not entry then
    ctx.set_right_lines({ '  (ボリュームがありません)' }, 'text', nil, 'volumes:none')
    return
  end
  docker.inspect('volume', entry.name, function(text)
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

  push(string.format('  ボリューム  (%d)', #volumes), nil, 'GitPanelHeader')
  push('', nil)

  local name_w, size_w = 0, 0
  for _, v in ipairs(volumes) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(v.name))
    size_w = math.max(size_w, vim.fn.strdisplaywidth(sizes[v.name] or ''))
  end
  name_w = math.min(name_w, 34)

  -- 使用中 / 未使用（= `docker volume prune` の対象）に仕分ける
  local in_use_list, unused_list = {}, {}
  for _, v in ipairs(volumes) do
    table.insert(unused[v.name] and unused_list or in_use_list, v)
  end

  local remembered_row = nil
  local SECTIONS = {
    { list = in_use_list, label = '使用中', dim = false },
    { list = unused_list, label = '未使用', dim = true },
  }
  for _, section in ipairs(SECTIONS) do
    if #section.list > 0 then
      push(string.format('  ▼ %s  (%d)', section.label, #section.list), nil, 'GitPanelSection')
      for _, v in ipairs(section.list) do
        local name = util.pad(v.name, name_w)
        -- サイズは docker system df -v が返した時だけ出す（未取得なら空欄のまま詰めない）
        local size = size_w > 0 and ('  ' .. util.rpad(sizes[v.name] or '-', size_w)) or ''
        push(string.format('    %s%s  %s', name, size, v.driver), v)
        local row = #lines - 1
        local name_end = #('    ' .. name)
        table.insert(hl_queue, { row, section.dim and 'GitPanelDim' or 'GitPanelCheckOk', 4, name_end })
        table.insert(hl_queue, { row, 'GitPanelDim', name_end, -1 })
        if cursor_mem == v.name then remembered_row = #lines end
      end
    end
  end
  if #volumes == 0 then push('  (ボリュームなし)', nil) end

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

--- opts.auto=true は2秒ごとの自動更新から呼ばれた時。サイズ取得(`docker system df -v`)は
--- 全ボリュームの実サイズ計測で重いので、その時だけは前回の値を使い回して叩かない。
--- パネルを開いた時と R を押した時（opts.auto=false）は取り直す
function M.refresh(auto_capture, opts)
  local want_sizes = not (opts and opts.auto)
  local pending = want_sizes and 3 or 2
  local function done()
    pending = pending - 1
    if pending > 0 then return end
    if ctx.current_panel_name() ~= 'volumes' then return end
    if auto_capture then M.remember_cursor() end
    render()
  end
  docker.volumes(function(list) volumes = list; done() end)
  docker.unused_volumes(function(set) unused = set; done() end)
  if want_sizes then
    docker.volume_sizes(function(map) sizes = map; done() end)
  end
end

local function remove()
  local entry = current_entry()
  if not entry then return end
  cursor_mem = entry.name
  ctx.confirm('削除しますか？\n' .. entry.name, function(ok)
    if not ok then return end
    docker.remove_volume(entry.name, false, function(res)
      -- 使用中のボリュームは通常のrmでは消せない。lazygitのworktree削除と同じく、
      -- 失敗した時だけ強制削除を提案する
      if res.code ~= 0 then
        ctx.render_cmdlog()
        ctx.confirm('削除に失敗しました。\n強制削除しますか？(--force)', function(yes)
          if not yes then return end
          docker.remove_volume(entry.name, true, ctx.done_refresh(M.refresh, '強制削除'))
        end)
        return
      end
      ctx.done_refresh(M.refresh, '削除')(res)
    end)
  end)
end

local function prune()
  ctx.confirm('未使用のボリュームを全て削除しますか？\ndocker volume prune', function(ok)
    if not ok then return end
    docker.prune('volumes', ctx.done_refresh(M.refresh, 'prune'))
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
