-- Stashパネル: 一覧・apply・pop・drop・このスタッシュから新規ブランチ
-- 注: スタッシュの新規作成はFilesパネルの s (StashAllChanges) が正しい操作場所。
--     本パネルの n は KeybindingStashConfig 相当で「選択したスタッシュから新規ブランチ作成」

local git = require('config.git_panel.git')

local M = {}

local ctx
local stashes = {}
local line_entries = {}
local total_rows = 0

local function current_entry()
  local win = ctx.get_left_win()
  if not win then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return line_entries[row]
end

local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  git.stash_show(entry.ref, function(text)
    ctx.set_right_lines(vim.split(text, '\n', { plain = true }), 'diff')
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

  push('  スタッシュ', nil, 'GitPanelHeader')
  push('', nil)
  for _, s in ipairs(stashes) do
    push('  ' .. s.ref .. '  ' .. s.message, s)
  end
  if #stashes == 0 then push('  (スタッシュなし)', nil) end

  total_rows = #lines
  ctx.set_left_lines(lines, hl_queue)

  local target = nil
  for i = 1, total_rows do
    if line_entries[i] then target = i; break end
  end
  if target then
    ctx.set_left_cursor(target)
    show_detail(line_entries[target])
  else
    show_detail(nil)
  end
end

function M.refresh()
  git.stash_list(function(list)
    stashes = list
    render()
  end)
end

local function apply()
  local entry = current_entry()
  if not entry then return end
  git.stash_apply(entry.ref, function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then vim.notify('適用に失敗しました（コンフリクトの可能性）: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
    M.refresh()
  end)
end

local function pop()
  local entry = current_entry()
  if not entry then return end
  git.stash_pop(entry.ref, function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then vim.notify('popに失敗しました（コンフリクトの可能性）: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
    M.refresh()
  end)
end

local function drop()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('削除しますか？\n' .. entry.ref .. '  ' .. entry.message, function(ok)
    if not ok then return end
    git.stash_drop(entry.ref, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('削除に失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      M.refresh()
    end)
  end)
end

local function new_branch_from_stash()
  local entry = current_entry()
  if not entry then return end
  ctx.input('新規ブランチ名 (from ' .. entry.ref .. ')', '', function(name)
    if not name or name == '' then return end
    git.stash_branch(entry.ref, name, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('作成失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      M.refresh()
    end)
  end)
end

function M.keymaps()
  return {
    ['<Space>'] = apply,
    g = pop,
    d = drop,
    n = new_branch_from_stash,
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
