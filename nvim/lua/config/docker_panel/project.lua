-- Projectパネル: 環境全体のサマリと docker compose プロジェクト一覧
-- （lazydocker の一番上の Project パネル相当。右ペインは Info / Disk のサブタブ）

local docker = require('config.docker_panel.docker')
local tabs_mod = require('config.panel.tabs')
local util = require('config.panel.text')

local M = {}

local ctx
local summary = { containers = {} }
local projects = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local tabs = tabs_mod.new({ 'Info', 'Disk' })
--- show_detail からタブ描画のコールバックへ渡すため前方宣言する
local show_current

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.key end
end

local function still_current(key, tab)
  if ctx.current_panel_name() ~= 'project' then return false end
  if tabs:current() ~= tab then return false end
  local entry = current_entry()
  return entry ~= nil and entry.key == key
end

-- ══════════════════════════════════════════════
-- 右ペイン
-- ══════════════════════════════════════════════

--- Infoタブは「今どのdockerに繋がっているか」＋「コンテナが今どういう状態か」を出す。
--- イメージ/ボリュームの個数やサイズは Disk タブ(`docker system df`)の担当で、
--- 両方に同じ数字を並べても意味が無いためここには出さない
local function show_info_summary(entry)
  docker.info(function(text)
    if not still_current(entry.key, 'Info') then return end
    local lines, hl = {}, {}
    local function head(t)
      table.insert(lines, '  ' .. t)
      table.insert(hl, { #lines - 1, 'GitPanelHeader' })
      table.insert(lines, '')
    end
    head('接続先')
    for _, l in ipairs(vim.split(vim.trim(text), '\n', { plain = true })) do
      table.insert(lines, '  ' .. l)
      -- 行頭のラベル列だけ淡くして、値を主役に見せる（Statsタブと同じ見せ方）
      table.insert(hl, { #lines - 1, 'GitPanelDim', 2, 2 + 8 })
    end
    table.insert(lines, '')

    head('コンテナ')
    local counts, order = {}, { 'running', 'paused', 'restarting', 'created', 'exited', 'dead' }
    for _, c in ipairs(summary.containers) do
      counts[c.state] = (counts[c.state] or 0) + 1
    end
    local LABEL = {
      running = '実行中', paused = '一時停止', restarting = '再起動中',
      created = '作成済み', exited = '停止中', dead = '異常終了',
    }
    for _, state in ipairs(order) do
      if counts[state] then
        local icon, icon_hl = util.state_icon(state)
        table.insert(lines, string.format('  %s %s %s', icon, util.pad(LABEL[state], 10), counts[state]))
        table.insert(hl, { #lines - 1, icon_hl, 2, 5 })
      end
    end
    if #summary.containers == 0 then table.insert(lines, '  (コンテナなし)') end
    ctx.set_right_lines(lines, 'text', hl, entry.key .. ':info')
  end)
end

local function show_info_project(entry)
  local lines, hl = {}, {}
  table.insert(lines, '  ' .. entry.name)
  table.insert(hl, { #lines - 1, 'GitPanelHeader' })
  table.insert(lines, '')
  for _, c in ipairs(summary.containers) do
    if c.project == entry.name then
      local icon, icon_hl = util.state_icon(c.state)
      local label = c.service ~= '' and c.service or c.name
      table.insert(lines, string.format('  %s %s  %s', icon, util.pad(label, 20), c.status))
      table.insert(hl, { #lines - 1, icon_hl, 2, 3 })
    end
  end
  ctx.set_right_lines(lines, 'text', hl, entry.key .. ':info')
end

local function show_detail(entry)
  tabs:render(ctx, function() show_current() end)
  if not entry then
    ctx.set_right_lines({ '  (情報なし)' }, 'text', nil, 'project:none')
    return
  end
  if tabs:current() == 'Disk' then
    docker.system_df(function(text)
      if not still_current(entry.key, 'Disk') then return end
      ctx.set_right_lines(vim.split(vim.trim(text), '\n', { plain = true }), 'text', nil, 'project:disk')
    end)
    return
  end
  if entry.kind == 'project' then
    show_info_project(entry)
  else
    show_info_summary(entry)
  end
end

show_current = function()
  show_detail(current_entry())
end

-- ══════════════════════════════════════════════
-- 左ペイン
-- ══════════════════════════════════════════════

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  local running = 0
  for _, c in ipairs(summary.containers) do
    if c.state == 'running' then running = running + 1 end
  end

  push('  ' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':t'), nil, 'GitPanelHeader')
  push('', nil)
  push(string.format('  ● 全体  コンテナ %d/%d 実行中', running, #summary.containers),
    { kind = 'summary', key = 'summary' })
  table.insert(hl_queue, { #lines - 1, running > 0 and 'GitPanelCheckOk' or 'GitPanelDim', 2, 5 })
  local remembered_row = (cursor_mem == 'summary') and #lines or nil

  if #projects > 0 then
    push('', nil)
    push('  Compose プロジェクト', nil, 'GitPanelSection')
    for _, p in ipairs(projects) do
      local icon, icon_hl = util.state_icon(p.running > 0 and 'running' or 'exited')
      push(string.format('  %s %s  %d/%d 実行中', icon, util.pad(p.name, 20), p.running, p.total),
        { kind = 'project', key = 'project:' .. p.name, name = p.name })
      table.insert(hl_queue, { #lines - 1, icon_hl, 2, 5 })
      if cursor_mem == 'project:' .. p.name then remembered_row = #lines end
    end
  end

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

--- 2秒ごとに回るので、取得は `docker ps` の1回だけに抑える
--- （イメージ/ボリューム/ネットワークの規模は Disk タブの `docker system df` に任せる）
function M.refresh(auto_capture)
  docker.containers(function(list)
    if ctx.current_panel_name() ~= 'project' then return end
    summary.containers = list
    -- compose のラベルからプロジェクト単位に集計する
    local by_project, order = {}, {}
    for _, c in ipairs(summary.containers) do
      if c.project ~= '' then
        if not by_project[c.project] then
          by_project[c.project] = { name = c.project, running = 0, total = 0 }
          table.insert(order, c.project)
        end
        local p = by_project[c.project]
        p.total = p.total + 1
        if c.state == 'running' then p.running = p.running + 1 end
      end
    end
    table.sort(order)
    projects = {}
    for _, name in ipairs(order) do table.insert(projects, by_project[name]) end
    if auto_capture then M.remember_cursor() end
    render()
  end)
end

--- 確認ダイアログで実際に走るコマンドをそのまま見せるための対応表
local PRUNE_CMD = {
  containers = 'docker container prune',
  images     = 'docker image prune --all',
  volumes    = 'docker volume prune',
  networks   = 'docker network prune',
  builder    = 'docker builder prune',
  system     = 'docker system prune',
}

--- lazydocker の bulk command (b) 相当。環境全体の掃除をまとめて置く
local function prune_menu()
  ctx.menu('一括削除 (prune)', {
    { key = 'c', label = '停止中のコンテナ (container prune)', value = 'containers' },
    { key = 'i', label = '未使用イメージ (image prune --all)', value = 'images' },
    { key = 'v', label = '未使用ボリューム (volume prune)', value = 'volumes' },
    { key = 'n', label = '未使用ネットワーク (network prune)', value = 'networks' },
    { key = 'b', label = 'ビルドキャッシュ (builder prune)', value = 'builder' },
    { key = 'a', label = 'まとめて (system prune)', value = 'system' },
  }, function(choice)
    if not choice then return end
    ctx.confirm('実行しますか？\n' .. (PRUNE_CMD[choice] or choice), function(ok)
      if not ok then return end
      docker.prune(choice, ctx.done_refresh(M.refresh, 'prune'))
    end)
  end)
end

function M.keymaps()
  return vim.tbl_extend('force', {
    b = prune_menu,
  }, tabs_mod.keymaps(tabs, show_current))
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    function(entry)
      cursor_mem = entry.key
      show_detail(entry)
    end
  )
  M.refresh()
end

return M
