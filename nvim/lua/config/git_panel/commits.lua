-- Commits(ログ)パネル: 一覧・詳細diff・reset・revert・新規ブランチ・detached HEADチェックアウト
-- amendはFilesパネル側(A)が正しい位置（KeybindingFilesConfig.AmendLastCommit）なのでここには置かない
-- 注: squash/fixup/reword/drop/並び替えなどの対話的リベース操作は
--     非対話化スクリプトの失敗時にリベース中断状態で壊れるリスクが高いため未対応

local git = require('config.git_panel.git')

local M = {}

local ctx
local commits = {}
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
  git.show_commit(entry.hash, function(text)
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

  push('  コミットログ', nil, 'GitPanelHeader')
  push('', nil)

  for i, c in ipairs(commits) do
    local marker = (i == 1) and '* ' or '  '
    push(string.format('  %s%s %s', marker, c.short, c.subject), c, (i == 1) and 'GitPanelCurrent' or nil)
  end
  if #commits == 0 then push('  (コミットなし)', nil) end

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
  git.log(function(list)
    commits = list
    render()
  end)
end

local function reset()
  local entry = current_entry()
  if not entry then return end
  ctx.menu('Reset: ' .. entry.short .. ' ' .. entry.subject, {
    { key = 's', label = 'Soft   (変更を保持・ステージ済み)',  value = 'soft' },
    { key = 'm', label = 'Mixed  (変更を保持・未ステージ)',    value = 'mixed' },
    { key = 'h', label = 'Hard   (すべて破棄)',               value = 'hard' },
  }, function(mode)
    if not mode then return end
    ctx.confirm(string.format('%s の %s へ %s リセットしますか？', entry.short, entry.subject, mode), function(ok)
      if not ok then return end
      git.reset(entry.hash, mode, function(res)
        ctx.render_cmdlog()
        if res.code ~= 0 then vim.notify('resetに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
        M.refresh()
      end)
    end)
  end)
end

local function revert()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('このコミットをrevertしますか？\n' .. entry.short .. ' ' .. entry.subject, function(ok)
    if not ok then return end
    git.revert_commit(entry.hash, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('revertに失敗しました（コンフリクトの可能性）: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      M.refresh()
    end)
  end)
end

local function checkout_commit()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('detached HEADとしてチェックアウトしますか？\n' .. entry.short .. ' ' .. entry.subject, function(ok)
    if not ok then return end
    git.checkout_commit(entry.hash, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('チェックアウトに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      M.refresh()
    end)
  end)
end

local function new_branch_from_commit()
  local entry = current_entry()
  if not entry then return end
  ctx.input('新規ブランチ名 (from ' .. entry.short .. ')', '', function(name)
    if not name or name == '' then return end
    git.new_branch_from_commit(entry.hash, name, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('作成失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      M.refresh()
    end)
  end)
end

function M.keymaps()
  return {
    g = reset,
    t = revert,
    n = new_branch_from_commit,
    ['<Space>'] = checkout_commit,
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
