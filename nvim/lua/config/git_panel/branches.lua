-- Branchesパネル: 一覧・チェックアウト・作成・削除・マージ・リベース・リネーム・fast-forward
-- キーはpkg/config/user_config.go デフォルト(KeybindingBranchesConfig)に合わせている

local git = require('config.git_panel.git')

local M = {}

local ctx
local branches = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil

local function current_entry()
  local win = ctx.get_left_win()
  if not win then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return line_entries[row]
end

local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  git.run({ 'log', '-n', '20', '--pretty=format:%h %s (%ar)', entry.name }, function(res)
    ctx.set_right_lines(vim.split(res.stdout or '', '\n', { plain = true }), '')
  end)
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  push('  ローカルブランチ', nil, 'GitPanelHeader')
  push('', nil)

  local remembered_row = nil
  for _, b in ipairs(branches) do
    local marker = b.current and '* ' or '  '
    local track = ''
    if b.upstream and b.upstream ~= '' then
      track = '  -> ' .. b.upstream .. (b.track ~= '' and (' ' .. b.track) or '')
    end
    push('  ' .. marker .. b.name .. track, b, b.current and 'GitPanelCurrent' or nil)
    if cursor_mem == b.name then remembered_row = #lines end
  end
  if #branches == 0 then push('  (ブランチなし)', nil) end

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

function M.refresh()
  git.branches(function(list)
    branches = list
    render()
  end)
end

local function done_refresh(label)
  return function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then vim.notify(label .. '失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
    M.refresh()
  end
end

local function checkout()
  local entry = current_entry()
  if not entry then return end
  cursor_mem = entry.name
  git.checkout_branch(entry.name, done_refresh('チェックアウト'))
end

local function checkout_by_name()
  ctx.input('チェックアウト (名前 / "-"で直前)', '', function(name)
    if not name or name == '' then return end
    cursor_mem = name ~= '-' and name or nil
    git.checkout_by_name(name, done_refresh('チェックアウト'))
  end)
end

local function checkout_previous()
  git.checkout_previous(done_refresh('チェックアウト'))
end

local function create()
  ctx.input('新規ブランチ名', '', function(name)
    if not name or name == '' then return end
    cursor_mem = name
    git.create_branch(name, done_refresh('作成'))
  end)
end

local function delete()
  local entry = current_entry()
  if not entry then return end
  if entry.current then
    vim.notify('現在のブランチは削除できません', vim.log.levels.WARN)
    return
  end
  ctx.confirm('ブランチ "' .. entry.name .. '" を削除しますか？', function(ok)
    if not ok then return end
    git.delete_branch(entry.name, false, function(res)
      ctx.render_cmdlog()
      if res.code == 0 then cursor_mem = nil; M.refresh(); return end
      ctx.confirm('マージされていません。強制削除しますか？\n' .. entry.name, function(force_ok)
        if not force_ok then return end
        cursor_mem = nil
        git.delete_branch(entry.name, true, done_refresh('削除'))
      end)
    end)
  end)
end

local function force_checkout()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('作業ツリーの変更をすべて破棄して "' .. entry.name .. '" を強制チェックアウトしますか？', function(ok)
    if not ok then return end
    cursor_mem = entry.name
    git.force_checkout(entry.name, done_refresh('強制チェックアウト'))
  end)
end

local function merge()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチに "' .. entry.name .. '" をマージしますか？', function(ok)
    if not ok then return end
    git.merge_branch(entry.name, done_refresh('マージ'))
  end)
end

local function rebase()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチを "' .. entry.name .. '" にリベースしますか？', function(ok)
    if not ok then return end
    git.rebase_branch(entry.name, done_refresh('リベース'))
  end)
end

local function rename()
  local entry = current_entry()
  if not entry then return end
  ctx.input('リネーム', entry.name, function(new_name)
    if not new_name or new_name == '' or new_name == entry.name then return end
    cursor_mem = new_name
    git.rename_branch(entry.name, new_name, done_refresh('リネーム'))
  end)
end

local function fast_forward()
  local entry = current_entry()
  if not entry then return end
  if entry.upstream == '' then
    vim.notify('アップストリームが設定されていません', vim.log.levels.WARN)
    return
  end
  git.fast_forward(entry.name, done_refresh('fast-forward'))
end

local function set_upstream()
  local entry = current_entry()
  if not entry then return end
  ctx.input('アップストリームに設定 (remote)', 'origin', function(remote)
    if not remote or remote == '' then return end
    git.set_upstream(remote, entry.name, done_refresh('アップストリーム設定'))
  end)
end

function M.keymaps()
  return {
    ['<Space>'] = checkout,
    c = checkout_by_name,
    ['-'] = checkout_previous,
    n = create,
    d = delete,
    F = force_checkout,
    M = merge,
    r = rebase,
    R = rename,
    f = fast_forward,
    u = set_upstream,
  }
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    show_detail
  )
  M.refresh()
end

return M
