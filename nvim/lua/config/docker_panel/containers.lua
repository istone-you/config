-- Containersパネル: 一覧・start/stop/restart/pause/kill/remove・シェル起動、
-- 右ペインは Logs / Stats / Config / Top のサブタブ（lazydocker の Containers パネル相当）

local docker = require('config.docker_panel.docker')
local tabs_mod = require('config.docker_panel.tabs')
local util = require('config.docker_panel.util')

local M = {}

local ctx
local containers = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil  -- 直前に選択していたコンテナID
local tabs = tabs_mod.new({ 'Logs', 'Stats', 'Config', 'Top' })
--- show_detail からタブ描画のコールバックへ渡すため前方宣言する
local show_current

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する
function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.id end
end

--- 非同期取得の完了時、まだ同じ行が選択されたままかを確認する
--- （選択が動いた後に古い結果で右ペインを上書きしないため）
local function still_current(id, tab)
  if ctx.current_panel_name() ~= 'containers' then return false end
  if tabs:current() ~= tab then return false end
  local entry = current_entry()
  return entry ~= nil and entry.id == id
end

-- ══════════════════════════════════════════════
-- 右ペイン（サブタブ）
-- ══════════════════════════════════════════════

local function show_logs(entry)
  docker.logs(entry.id, 300, function(text, res)
    if not still_current(entry.id, 'Logs') then return end
    if text == '' then
      local err = vim.trim(res.stderr or '')
      ctx.set_right_lines({ err ~= '' and ('  ' .. err) or '  (ログなし)' }, 'text', nil, entry.id .. ':logs:empty')
      return
    end
    -- ログはアプリ側がANSIカラーを吐くことが多いので、色を保ったまま通常バッファへ描く。
    -- lazydockerと同じく末尾（最新行）に追従させる
    ctx.set_right_ansi_text(text, entry.id .. ':logs', { bottom = true })
  end)
end

local function show_stats(entry)
  if entry.state ~= 'running' then
    ctx.set_right_lines({ '  (停止中のためstatsはありません)' }, 'text', nil, entry.id .. ':stats:stopped')
    return
  end
  docker.stats_one(entry.name, function(s)
    if not still_current(entry.id, 'Stats') then return end
    if not s then
      ctx.set_right_lines({ '  (statsを取得できませんでした)' }, 'text', nil, entry.id .. ':stats:none')
      return
    end
    local lines, hl = {}, {}
    local function push(label, value)
      table.insert(lines, string.format('  %-10s %s', label, value))
      table.insert(hl, { #lines - 1, 'GitPanelDim', 2, 12 })
    end
    table.insert(lines, '  ' .. s.name)
    table.insert(hl, { #lines - 1, 'GitPanelHeader' })
    table.insert(lines, '')
    push('CPU', s.cpu)
    push('MEM', s.mem .. '  (' .. s.mem_perc .. ')')
    push('NET I/O', s.net)
    push('BLOCK', s.block)
    push('PIDS', s.pids)
    ctx.set_right_lines(lines, 'text', hl, entry.id .. ':stats')
  end)
end

local function show_config(entry)
  docker.inspect('container', entry.id, function(text)
    if not still_current(entry.id, 'Config') then return end
    ctx.set_right_lines(vim.split(text ~= '' and text or '{}', '\n', { plain = true }), 'json', nil, entry.id .. ':config')
  end)
end

local function show_top(entry)
  if entry.state ~= 'running' then
    ctx.set_right_lines({ '  (停止中のためプロセス一覧はありません)' }, 'text', nil, entry.id .. ':top:stopped')
    return
  end
  docker.top(entry.id, function(text, res)
    if not still_current(entry.id, 'Top') then return end
    local body = text ~= '' and text or vim.trim(res.stderr or '')
    ctx.set_right_lines(vim.split(body, '\n', { plain = true }), 'text', nil, entry.id .. ':top')
  end)
end

local function show_detail(entry)
  tabs:render(ctx, function() show_current() end)
  if not entry then
    ctx.set_right_lines({ '  (コンテナがありません)' }, 'text', nil, 'containers:none')
    return
  end
  local tab = tabs:current()
  if tab == 'Logs' then show_logs(entry)
  elseif tab == 'Stats' then show_stats(entry)
  elseif tab == 'Config' then show_config(entry)
  elseif tab == 'Top' then show_top(entry)
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
  for _, c in ipairs(containers) do
    if c.state == 'running' then running = running + 1 end
  end
  push(string.format('  コンテナ  (%d/%d 実行中)', running, #containers), nil, 'GitPanelHeader')
  push('', nil)

  -- docker compose のプロジェクト単位でまとめる。同じ compose で立ち上げたものが
  -- 散らばらないよう、見出し＋インデントで並べる（プロジェクト外のコンテナは最後に「その他」）
  local groups, order = {}, {}
  for _, c in ipairs(containers) do
    local key = c.project ~= '' and c.project or ''
    if not groups[key] then
      groups[key] = {}
      table.insert(order, key)
    end
    table.insert(groups[key], c)
  end
  table.sort(order, function(a, b)
    if (a == '') ~= (b == '') then return b == '' end -- プロジェクト無しは最後
    return a < b
  end)
  local grouped = #order > 1 or (order[1] and order[1] ~= '')

  -- 名前列の幅はグループ内の表示名（composeならサービス名）で揃える
  local function display_name(c)
    if c.project ~= '' and c.service ~= '' then return c.service end
    return c.name
  end
  local name_w = 0
  for _, c in ipairs(containers) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(display_name(c)))
  end
  name_w = math.min(name_w, 28)

  local remembered_row = nil
  for _, key in ipairs(order) do
    local list = groups[key]
    local indent = ''
    if grouped then
      local label = key ~= '' and key or 'その他'
      local up = 0
      for _, c in ipairs(list) do
        if c.state == 'running' then up = up + 1 end
      end
      push(string.format('  ▼ %s  (%d/%d)', label, up, #list), nil, 'GitPanelSection')
      indent = '  '
    end
    for _, c in ipairs(list) do
      local icon, icon_hl = util.state_icon(c.state)
      local name = util.pad(display_name(c), name_w)
      push(string.format('  %s%s %s  %s', indent, icon, name, c.status), c)
      local row = #lines - 1
      -- アイコン+名前は状態色、statusは補助情報として淡く出す（lazydockerと同じ見せ方）
      local name_end = #('  ' .. indent .. icon .. ' ' .. name)
      table.insert(hl_queue, { row, icon_hl, 2 + #indent, name_end })
      table.insert(hl_queue, { row, 'GitPanelDim', name_end, -1 })
      if cursor_mem == c.id then remembered_row = #lines end
    end
  end
  if #containers == 0 then push('  (コンテナなし)', nil) end

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

--- auto_captureはshell側の自動更新/Rキーから汎用refresh扱いの時だけtrueで渡される。
--- render()の直前で今のカーソル位置を捕捉することで、非同期処理中にユーザーがj/kで
--- 動かした分を取りこぼさないようにする
function M.refresh(auto_capture)
  docker.containers(function(list)
    if ctx.current_panel_name() ~= 'containers' then return end
    containers = list
    if auto_capture then M.remember_cursor() end
    render()
  end)
end

-- ══════════════════════════════════════════════
-- 操作
-- ══════════════════════════════════════════════

local function with_entry(fn)
  return function()
    local entry = current_entry()
    if not entry then return end
    cursor_mem = entry.id
    fn(entry)
  end
end

local toggle_start_stop = with_entry(function(entry)
  if entry.state == 'running' then
    ctx.set_loading('Stopping')
    docker.stop(entry.id, function(res)
      ctx.clear_loading()
      ctx.done_refresh(M.refresh, '停止')(res)
    end)
  else
    ctx.set_loading('Starting')
    docker.start(entry.id, function(res)
      ctx.clear_loading()
      ctx.done_refresh(M.refresh, '起動')(res)
    end)
  end
end)

local stop = with_entry(function(entry)
  ctx.confirm('停止しますか？\n' .. entry.name, function(ok)
    if not ok then return end
    ctx.set_loading('Stopping')
    docker.stop(entry.id, function(res)
      ctx.clear_loading()
      ctx.done_refresh(M.refresh, '停止')(res)
    end)
  end)
end)

local restart = with_entry(function(entry)
  ctx.set_loading('Restarting')
  docker.restart(entry.id, function(res)
    ctx.clear_loading()
    ctx.done_refresh(M.refresh, '再起動')(res)
  end)
end)

local toggle_pause = with_entry(function(entry)
  if entry.state == 'paused' then
    docker.unpause(entry.id, ctx.done_refresh(M.refresh, '再開'))
  else
    docker.pause(entry.id, ctx.done_refresh(M.refresh, '一時停止'))
  end
end)

local kill = with_entry(function(entry)
  ctx.confirm('強制終了(kill)しますか？\n' .. entry.name, function(ok)
    if not ok then return end
    docker.kill(entry.id, ctx.done_refresh(M.refresh, 'kill'))
  end)
end)

--- lazydocker(container.go の remove メニュー)と同じ選択肢
local remove_menu = with_entry(function(entry)
  ctx.menu('削除: ' .. entry.name, {
    { key = 'd', label = '削除 (docker rm)', value = 'rm' },
    { key = 'f', label = '強制削除 (rm --force)', value = 'force' },
    { key = 'v', label = 'ボリュームごと削除 (rm --force --volumes)', value = 'volumes' },
  }, function(choice)
    if not choice then return end
    local opts = { force = choice ~= 'rm', volumes = choice == 'volumes' }
    docker.remove_container(entry.id, opts, ctx.done_refresh(M.refresh, '削除'))
  end)
end)

--- lazydocker の bulk command (b) 相当
local function prune_menu()
  ctx.menu('停止中のコンテナを一括削除', {
    { key = 'p', label = 'docker container prune (停止中を全削除)', value = 'containers' },
  }, function(choice)
    if not choice then return end
    ctx.confirm('停止中のコンテナを全て削除しますか？', function(ok)
      if not ok then return end
      docker.prune('containers', ctx.done_refresh(M.refresh, 'prune'))
    end)
  end)
end

--- lazydocker の E (exec shell) 相当。パネルを閉じて右分割にターミナルを開く。
--- bashがあればbash、無ければshで入る（イメージによってbashが無いため）
local exec_shell = with_entry(function(entry)
  if entry.state ~= 'running' then
    vim.notify('実行中のコンテナではありません', vim.log.levels.WARN)
    return
  end
  local id = entry.id
  -- パネルを閉じた跡地でシェルを使うので、全画面表示でもnvimは終了させない
  require('config.docker_panel').close({ keep_nvim = true })
  vim.cmd('rightbelow vnew')
  vim.fn.termopen({
    docker.bin, 'exec', '-it', id, 'sh', '-c',
    'command -v bash >/dev/null 2>&1 && exec bash || exec sh',
  })
  vim.cmd('startinsert')
end)

function M.keymaps()
  return vim.tbl_extend('force', {
    ['<Space>'] = toggle_start_stop,
    s = stop,
    r = restart,
    p = toggle_pause,
    K = kill,
    d = remove_menu,
    b = prune_menu,
    E = exec_shell,
  }, tabs_mod.keymaps(tabs, show_current))
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    function(entry)
      cursor_mem = entry.id
      show_detail(entry)
    end
  )
  M.refresh()
end

return M
