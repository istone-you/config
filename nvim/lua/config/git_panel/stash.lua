-- Stashパネル: 一覧・apply・pop・drop・このスタッシュから新規ブランチ
-- 注: スタッシュの新規作成はFilesパネルの s (StashAllChanges) が正しい操作場所。
--     本パネルの n は KeybindingStashConfig 相当で「選択したスタッシュから新規ブランチ作成」

local git = require('config.git_panel.git')

local M = {}

local ctx
local stashes = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil  -- 直前に選択していたスタッシュのref（stash@{N}は位置参照なので目安程度）

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する
function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.ref end
end

local function current_ref_is(ref)
  local entry = current_entry()
  return entry and entry.ref == ref
end

local function still_current(ref)
  return ctx.current_panel_name() == 'stash' and current_ref_is(ref)
end

local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  git.stash_show(entry.ref, function(text)
    if not still_current(entry.ref) then return end
    ctx.set_right_diff(text, entry.ref)
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
  local remembered_row = nil
  for _, s in ipairs(stashes) do
    push('  ' .. s.ref .. '  ' .. s.message, s)
    if cursor_mem == s.ref then remembered_row = #lines end
  end
  if #stashes == 0 then push('  (スタッシュなし)', nil) end

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

--- auto_captureはinit.luaの自動更新/Rキーから汎用refresh扱いの時だけtrueで渡される。
--- render()の直前で今のカーソル位置を捕捉することで、非同期処理中にユーザーがj/kで
--- 動かした分を取りこぼさないようにする
function M.refresh(auto_capture)
  git.stash_list(function(list)
    stashes = list
    if auto_capture then M.remember_cursor() end
    render()
  end)
end

local function apply()
  local entry = current_entry()
  if not entry then return end
  git.stash_apply(entry.ref, ctx.done_refresh(M.refresh, '適用'))
end

local function pop()
  local entry = current_entry()
  if not entry then return end
  git.stash_pop(entry.ref, ctx.done_refresh(M.refresh, 'pop'))
end

local function drop()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('削除しますか？\n' .. entry.ref .. '  ' .. entry.message, function(ok)
    if not ok then return end
    git.stash_drop(entry.ref, ctx.done_refresh(M.refresh, '削除'))
  end)
end

local function new_branch_from_stash()
  local entry = current_entry()
  if not entry then return end
  ctx.input('新規ブランチ名 (from ' .. entry.ref .. ')', '', function(name)
    if not name or name == '' then return end
    git.stash_branch(entry.ref, name, ctx.done_refresh(M.refresh, '作成'))
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
    function(entry)
      cursor_mem = entry.ref
      show_detail(entry)
    end
  )
  M.refresh()
end

return M
