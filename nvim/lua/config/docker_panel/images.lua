-- Imagesパネル: 一覧・削除・prune、右ペインは Config / History のサブタブ
-- （lazydocker の Images パネル相当）

local docker = require('config.docker_panel.docker')
local tabs_mod = require('config.panel.tabs')
local util = require('config.panel.text')

local M = {}

local ctx
local images = {}
--- コンテナに使われているイメージID(sha256:...)の集合。使用中/未使用の仕分けに使う
local used_ids = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local tabs = tabs_mod.new({ 'Config', 'History' })
--- show_detail からタブ描画のコールバックへ渡すため前方宣言する
local show_current

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.id end
end

local function still_current(id, tab)
  if ctx.current_panel_name() ~= 'images' then return false end
  if tabs:current() ~= tab then return false end
  local entry = current_entry()
  return entry ~= nil and entry.id == id
end

local function show_detail(entry)
  tabs:render(ctx, function() show_current() end)
  if not entry then
    ctx.set_right_lines({ '  (イメージがありません)' }, 'text', nil, 'images:none')
    return
  end
  if tabs:current() == 'History' then
    docker.image_history(entry.id, function(text, res)
      if not still_current(entry.id, 'History') then return end
      local body = text ~= '' and text or vim.trim(res.stderr or '')
      ctx.set_right_lines(vim.split(body, '\n', { plain = true }), 'text', nil, entry.id .. ':history')
    end)
    return
  end
  docker.inspect('image', entry.id, function(text)
    if not still_current(entry.id, 'Config') then return end
    ctx.set_right_lines(vim.split(text ~= '' and text or '{}', '\n', { plain = true }), 'json', nil, entry.id .. ':config')
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

  push(string.format('  イメージ  (%d)', #images), nil, 'GitPanelHeader')
  push('', nil)

  -- lazydocker(presentation/images.go GetDisplayStrings)と同じく、リポジトリ名・タグ・サイズを
  -- `repo:tag` と繋げずに独立した列として並べる
  local repo_w, tag_w = 0, 0
  for _, im in ipairs(images) do
    repo_w = math.max(repo_w, vim.fn.strdisplaywidth(im.repository))
    tag_w = math.max(tag_w, vim.fn.strdisplaywidth(im.tag))
  end
  repo_w = math.min(repo_w, 26)
  tag_w = math.min(tag_w, 14)

  -- 使用中 / 未使用 / dangling(タグ無し) に仕分ける。
  -- 未使用 = どのコンテナからも参照されていない = `docker image prune --all` の対象、
  -- dangling = タグが外れた <none> のイメージ = `docker image prune` の対象
  local buckets = { in_use = {}, unused = {}, dangling = {} }
  for _, im in ipairs(images) do
    if used_ids[im.id] then
      table.insert(buckets.in_use, im)
    elseif im.repository == '<none>' then
      table.insert(buckets.dangling, im)
    else
      table.insert(buckets.unused, im)
    end
  end

  local remembered_row = nil
  local SECTIONS = {
    { key = 'in_use',   label = '使用中',   dim = false },
    { key = 'unused',   label = '未使用',   dim = true },
    { key = 'dangling', label = 'dangling', dim = true },
  }
  for _, section in ipairs(SECTIONS) do
    local list = buckets[section.key]
    if #list > 0 then
      push(string.format('  ▼ %s  (%d)', section.label, #list), nil, 'GitPanelSection')
      for _, im in ipairs(list) do
        local repo = util.pad(im.repository, repo_w)
        local tag = util.pad(im.tag, tag_w)
        push(string.format('    %s  %s  %s', repo, tag, im.size), im)
        local row = #lines - 1
        local repo_end = #('    ' .. repo)
        -- 削除候補（未使用・dangling）はリポジトリ名も淡くして、消して良いものが一目で分かるようにする
        table.insert(hl_queue, { row, section.dim and 'GitPanelDim' or 'GitPanelCheckOk', 4, repo_end })
        table.insert(hl_queue, { row, 'GitPanelDim', repo_end, -1 })
        if cursor_mem == im.id then remembered_row = #lines end
      end
    end
  end
  if #images == 0 then push('  (イメージなし)', nil) end

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

--- イメージ一覧と「どのイメージがコンテナに使われているか」を並行して取り、両方揃ってから描画する
function M.refresh(auto_capture)
  local pending = 2
  local function done()
    pending = pending - 1
    if pending > 0 then return end
    if ctx.current_panel_name() ~= 'images' then return end
    if auto_capture then M.remember_cursor() end
    render()
  end
  docker.images(function(list) images = list; done() end)
  docker.used_image_ids(function(set) used_ids = set; done() end)
end

local function remove()
  local entry = current_entry()
  if not entry then return end
  cursor_mem = entry.id
  local label = entry.repository .. ':' .. entry.tag
  ctx.menu('削除: ' .. label, {
    { key = 'd', label = '削除 (docker rmi)', value = 'rmi' },
    { key = 'f', label = '強制削除 (rmi --force)', value = 'force' },
  }, function(choice)
    if not choice then return end
    docker.remove_image(entry.id, choice == 'force', ctx.done_refresh(M.refresh, '削除'))
  end)
end

--- lazydocker の bulk command (b) 相当
local function prune_menu()
  ctx.menu('イメージの一括削除', {
    { key = 'p', label = 'docker image prune --all (未使用を全削除)', value = 'images' },
    { key = 'b', label = 'docker builder prune (ビルドキャッシュ削除)', value = 'builder' },
  }, function(choice)
    if not choice then return end
    ctx.confirm('実行しますか？\ndocker ' .. (choice == 'builder' and 'builder' or 'image') .. ' prune', function(ok)
      if not ok then return end
      docker.prune(choice, ctx.done_refresh(M.refresh, 'prune'))
    end)
  end)
end

function M.keymaps()
  return vim.tbl_extend('force', {
    d = remove,
    b = prune_menu,
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
