-- Worktreeパネル: 一覧・新規作成・チェックアウト(cd)・削除

local git = require('config.git_panel.git')

local M = {}

local ctx
local worktrees = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil  -- 直前に選択していたワークツリーのpath

local function current_entry()
  local win = ctx.get_left_win()
  if not win then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return line_entries[row]
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する
function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.path end
end

local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  local lines = { 'path:   ' .. entry.path }
  if entry.branch then table.insert(lines, 'branch: ' .. entry.branch) end
  if entry.detached then table.insert(lines, '(detached HEAD)') end
  if entry.head then table.insert(lines, 'HEAD:   ' .. entry.head) end
  ctx.set_right_lines(lines, '')
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  push('  ワークツリー', nil, 'GitPanelHeader')
  push('', nil)
  local remembered_row = nil
  for _, w in ipairs(worktrees) do
    local is_current = (w.path == git.root)
    local marker = is_current and '* ' or '  '
    local label = w.branch or (w.detached and '(detached)' or '')
    push('  ' .. marker .. w.path .. '  ' .. label, w, is_current and 'GitPanelCurrent' or nil)
    if cursor_mem == w.path then remembered_row = #lines end
  end
  if #worktrees == 0 then push('  (ワークツリーなし)', nil) end

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
  git.worktrees(function(list)
    worktrees = list
    render()
  end)
end

local function checkout()
  local entry = current_entry()
  if not entry then return end
  local path = entry.path
  ctx.confirm('このワークツリーに移動しますか？\n' .. path, function(ok)
    if not ok then return end
    vim.cmd('cd ' .. vim.fn.fnameescape(path))
    vim.notify('cwdを変更しました: ' .. path, vim.log.levels.INFO)
    git.root = path
    M.refresh()
  end)
end

local function create()
  ctx.input('新規ワークツリーのブランチ名', '', function(branch_name)
    if not branch_name or branch_name == '' then return end
    local suggested = git.root .. '-' .. branch_name:gsub('[/\\]', '-')
    ctx.input('作成先パス', suggested, function(path)
      if not path or path == '' then return end
      git.worktree_add(path, branch_name, true, function(res)
        ctx.render_cmdlog()
        if res.code ~= 0 then vim.notify('作成失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
        M.refresh()
      end)
    end)
  end)
end

local function delete()
  local entry = current_entry()
  if not entry then return end
  if entry.path == git.root then
    vim.notify('現在使用中のワークツリーは削除できません', vim.log.levels.WARN)
    return
  end
  ctx.confirm('削除しますか？\n' .. entry.path, function(ok)
    if not ok then return end
    git.worktree_remove(entry.path, false, function(res)
      ctx.render_cmdlog()
      if res.code == 0 then M.refresh(); return end
      ctx.confirm('未コミットの変更がある可能性があります。強制削除しますか？', function(force_ok)
        if not force_ok then return end
        git.worktree_remove(entry.path, true, function(res2)
          ctx.render_cmdlog()
          if res2.code ~= 0 then vim.notify('削除失敗: ' .. (res2.stderr or ''), vim.log.levels.ERROR) end
          M.refresh()
        end)
      end)
    end)
  end)
end

function M.keymaps()
  return {
    ['<Space>'] = checkout,
    n = create,
    d = delete,
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
