-- lazygit風のgit管理パネル（中央90%ポップアップ、複数パネル切替、プラグイン不使用・自作）
-- キー/挙動は pkg/config/user_config.go のデフォルトキーバインドに合わせて検証済み

local git = require('config.git_panel.git')
local ui = require('config.git_panel.ui')

local M = {}

local PANELS = {
  { key = '1', name = 'files',    title = 'Files',    mod = 'config.git_panel.files' },
  { key = '2', name = 'branches', title = 'Branches', mod = 'config.git_panel.branches' },
  { key = '3', name = 'commits',  title = 'Commits',  mod = 'config.git_panel.commits' },
  { key = '4', name = 'stash',    title = 'Stash',    mod = 'config.git_panel.stash' },
  { key = '5', name = 'worktree', title = 'Worktree', mod = 'config.git_panel.worktree' },
}

local win = {}
local origin_win
local augrp = vim.api.nvim_create_augroup('git_panel', { clear = true })
local hl_ns = vim.api.nvim_create_namespace('git_panel_hl')
local current_panel_idx = 1

local ctx = {}

-- ══════════════════════════════════════════════
-- コマンドログ
-- ══════════════════════════════════════════════

local function render_cmdlog()
  if not (win.cmdlog_buf and vim.api.nvim_buf_is_valid(win.cmdlog_buf)) then return end
  local lines = {}
  for i = 1, math.min(#git.command_log, 30) do
    table.insert(lines, git.command_log[i])
  end
  if #lines == 0 then lines = { '(まだ実行なし)' } end
  vim.bo[win.cmdlog_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.cmdlog_buf, 0, -1, false, lines)
  vim.bo[win.cmdlog_buf].modifiable = false
end
ctx.render_cmdlog = render_cmdlog

-- ══════════════════════════════════════════════
-- 汎用ヘルパー（各パネルモジュールに渡す）
-- ══════════════════════════════════════════════

local function refocus_left()
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    vim.api.nvim_set_current_win(win.left_win)
  end
end
ctx.refocus_left = refocus_left

function ctx.open_file_in_origin(path)
  M.close()
  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

function ctx.confirm(message, on_result)
  ui.confirm(message, { refocus_win = win.left_win }, on_result)
end

function ctx.input(title, default, on_submit)
  ui.input(title, default, { refocus_win = win.left_win }, on_submit)
end

function ctx.multiline_input(title, on_submit)
  ui.multiline_input({ title = title, refocus_win = win.left_win }, on_submit)
end

function ctx.menu(title, items, on_choice)
  ui.menu(title, items, { refocus_win = win.left_win }, on_choice)
end

function ctx.set_right_lines(lines, filetype)
  if not (win.right_buf and vim.api.nvim_buf_is_valid(win.right_buf)) then return end
  vim.bo[win.right_buf].modifiable = true
  vim.bo[win.right_buf].filetype = filetype or 'diff'
  vim.api.nvim_buf_set_lines(win.right_buf, 0, -1, false, lines)
  vim.bo[win.right_buf].modifiable = false
end

function ctx.set_left_lines(lines, hl_queue)
  if not (win.left_buf and vim.api.nvim_buf_is_valid(win.left_buf)) then return end
  vim.bo[win.left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.left_buf, 0, -1, false, lines)
  vim.bo[win.left_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.left_buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue or {}) do
    vim.api.nvim_buf_add_highlight(win.left_buf, hl_ns, h[2], h[1], 0, -1)
  end
  render_cmdlog()
end

function ctx.set_left_cursor(row)
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    pcall(vim.api.nvim_win_set_cursor, win.left_win, { row, 0 })
  end
end

function ctx.get_left_win() return win.left_win end
function ctx.get_left_buf() return win.left_buf end
function ctx.get_right_win() return win.right_win end
function ctx.get_right_buf() return win.right_buf end
function ctx.get_root() return git.root end

--- カーソルをlist entryのある行にクランプする汎用CursorMoved
function ctx.setup_cursor_clamp(get_line_entries, get_total_rows, on_land)
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = augrp,
    buffer = win.left_buf,
    callback = function()
      if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then return end
      local row = vim.api.nvim_win_get_cursor(win.left_win)[1]
      local entries = get_line_entries()
      if entries[row] then
        on_land(entries[row])
        return
      end
      local total = get_total_rows()
      for r = row, total do
        if entries[r] then
          pcall(vim.api.nvim_win_set_cursor, win.left_win, { r, 0 })
          return
        end
      end
      for r = row, 1, -1 do
        if entries[r] then
          pcall(vim.api.nvim_win_set_cursor, win.left_win, { r, 0 })
          return
        end
      end
    end,
  })
end

-- ══════════════════════════════════════════════
-- パネル切替
-- ══════════════════════════════════════════════

local GLOBAL_KEYS

--- 左右パネルの上に全幅で常時表示するタブバー。狭い端末でも左パネルの枠内に
--- 収まらないため、専用の1行ウィンドウにしている
local function render_tabbar(idx)
  if not (win.tabbar_buf and vim.api.nvim_buf_is_valid(win.tabbar_buf)) then return end
  local parts = {}
  for _, p in ipairs(PANELS) do
    table.insert(parts, ' [' .. p.key .. '] ' .. p.title .. ' ')
  end
  vim.bo[win.tabbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.tabbar_buf, 0, -1, false, { table.concat(parts) })
  vim.bo[win.tabbar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.tabbar_buf, hl_ns, 0, -1)
  local col = 0
  for i, part in ipairs(parts) do
    local hl = (i == idx) and 'GitPanelTabActive' or 'GitPanelTabInactive'
    vim.api.nvim_buf_add_highlight(win.tabbar_buf, hl_ns, hl, 0, col, col + #part)
    col = col + #part
  end
end

local function activate_panel(idx)
  current_panel_idx = idx
  local spec = PANELS[idx]
  local panel = require(spec.mod)

  vim.api.nvim_clear_autocmds({ group = augrp, buffer = win.left_buf })

  win.left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.left_buf].buftype    = 'nofile'
  vim.bo[win.left_buf].buflisted  = false
  vim.bo[win.left_buf].modifiable = false
  vim.bo[win.left_buf].filetype   = 'gitpanel'
  vim.api.nvim_win_set_buf(win.left_win, win.left_buf)
  require('config.hidden_cursor').mark_buffer(win.left_buf)
  vim.wo[win.left_win].wrap         = false
  vim.wo[win.left_win].number       = false
  vim.wo[win.left_win].signcolumn   = 'no'
  vim.wo[win.left_win].cursorline   = true
  vim.wo[win.left_win].winhighlight = 'Normal:GitPanelBg,CursorLine:GitPanelCursorLine'
  vim.api.nvim_win_set_config(win.left_win, { title = ' ' .. spec.title .. ' ', title_pos = 'center' })
  render_tabbar(idx)

  local keys = vim.tbl_extend('force', GLOBAL_KEYS, panel.keymaps and panel.keymaps() or {})
  for key, fn in pairs(keys) do
    vim.keymap.set('n', key, fn, { buffer = win.left_buf, nowait = true, silent = true })
  end

  panel.activate(ctx)
end

local function switch_to(idx)
  if idx == current_panel_idx then return end
  activate_panel(idx)
end

-- ══════════════════════════════════════════════
-- グローバルキー（push/pull/refresh, パネル切替, 閉じる）
-- ══════════════════════════════════════════════

local function notify_result(res, ok_msg, fail_prefix)
  if res.code == 0 then
    local detail = vim.trim((res.stdout or '') .. (res.stderr or ''))
    vim.notify(detail ~= '' and (ok_msg .. '\n' .. detail) or ok_msg, vim.log.levels.INFO)
  else
    vim.notify(fail_prefix .. ': ' .. (res.stderr or ''), vim.log.levels.ERROR)
  end
end

local function do_push()
  git.has_upstream(function(ok)
    if ok then
      git.push(function(res)
        ctx.render_cmdlog()
        notify_result(res, 'push完了', 'push失敗')
        require(PANELS[current_panel_idx].mod).refresh()
      end)
      return
    end
    git.branch_name(function(branch)
      ctx.confirm('アップストリームが未設定です。\norigin/' .. branch .. ' を設定してpushしますか？', function(yes)
        if not yes then return end
        git.push_set_upstream('origin', branch, function(res)
          ctx.render_cmdlog()
          notify_result(res, 'push完了（アップストリーム設定済み）', 'push失敗')
          require(PANELS[current_panel_idx].mod).refresh()
        end)
      end)
    end)
  end)
end

local function do_pull()
  git.pull(function(res)
    ctx.render_cmdlog()
    notify_result(res, 'pull完了', 'pull失敗')
    require(PANELS[current_panel_idx].mod).refresh()
  end)
end

-- Undo(z): 直前のコミット1つを取り消す（soft reset）。checkout/rebaseのUndoは対象外
local function do_undo()
  ctx.confirm('直前のコミットを取り消しますか？\n（変更はステージ済みの状態に戻ります）', function(ok)
    if not ok then return end
    git.undo_last_commit(function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('undoに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      require(PANELS[current_panel_idx].mod).refresh()
    end)
  end)
end

GLOBAL_KEYS = {
  ['1'] = function() switch_to(1) end,
  ['2'] = function() switch_to(2) end,
  ['3'] = function() switch_to(3) end,
  ['4'] = function() switch_to(4) end,
  ['5'] = function() switch_to(5) end,
  ['P'] = do_push,
  ['p'] = do_pull,
  ['z'] = do_undo,
  ['R'] = function() require(PANELS[current_panel_idx].mod).refresh() end,
  ['q'] = function() M.close() end,
  ['<Esc>'] = function() M.close() end,
}

-- ══════════════════════════════════════════════
-- レイアウト（90%x90%センター、左パネル+右diff+下部コマンドログ）
-- ══════════════════════════════════════════════

local function layout()
  local total_w = math.floor(vim.o.columns * 0.9)
  local total_h = math.floor(vim.o.lines * 0.9)
  local outer_col = math.floor((vim.o.columns - total_w) / 2)
  local outer_row = math.floor((vim.o.lines - total_h) / 2)

  local hgap, vgap = 0, 0
  -- tabbarもcmdlogと同じ「ボーダー付きで全幅」の作り方に統一する
  -- （ボーダー無し要素とボーダー有り要素を混在させるとcol/row計算がずれるため）
  local tabbar_content_h = 1
  local tabbar_screen_h = tabbar_content_h + 2
  local cmdlog_content_h = 6
  local cmdlog_screen_h = cmdlog_content_h + 2

  local tabbar_row = outer_row
  local top_row = tabbar_row + tabbar_screen_h + vgap
  local top_screen_h = total_h - tabbar_screen_h - vgap - cmdlog_screen_h - vgap
  local top_content_h = top_screen_h - 2

  local left_content_w = math.floor(total_w * 0.38) - 2
  local right_content_w = total_w - (left_content_w + 2) - hgap - 2

  return {
    outer_col = outer_col, outer_row = outer_row,
    tabbar_row = tabbar_row, tabbar_w = total_w - 2, tabbar_h = tabbar_content_h,
    top_row = top_row,
    left_w = left_content_w, right_w = right_content_w, box_h = top_content_h,
    right_col = outer_col + left_content_w + 2 + hgap,
    cmdlog_row = top_row + top_screen_h + vgap,
    cmdlog_w = total_w - 2, cmdlog_h = cmdlog_content_h,
  }
end

-- ══════════════════════════════════════════════
-- 開閉
-- ══════════════════════════════════════════════

local function close_wins()
  for _, key in ipairs({ 'tabbar_win', 'left_win', 'right_win', 'cmdlog_win' }) do
    local w = win[key]
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_close(w, true)
    end
  end
  for _, key in ipairs({ 'tabbar_buf', 'left_buf', 'right_buf', 'cmdlog_buf' }) do
    local b = win[key]
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
  win = {}
end

function M.close()
  vim.api.nvim_clear_autocmds({ group = augrp })
  close_wins()
end

local function open()
  -- gitコマンドの完了を待たず、ウィンドウは即座に表示する（読み込み中表示→非同期で内容を反映）
  origin_win = vim.api.nvim_get_current_win()
  local L = layout()

  win.tabbar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.tabbar_buf].buftype    = 'nofile'
  vim.bo[win.tabbar_buf].buflisted  = false
  vim.bo[win.tabbar_buf].modifiable = false
  require('config.hidden_cursor').mark_buffer(win.tabbar_buf)
  win.tabbar_win = vim.api.nvim_open_win(win.tabbar_buf, false, {
    relative = 'editor', width = L.tabbar_w, height = L.tabbar_h, col = L.outer_col, row = L.tabbar_row,
    style = 'minimal', border = 'single',
  })
  vim.wo[win.tabbar_win].winhighlight = 'Normal:GitPanelBg'

  win.left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.left_buf].buftype = 'nofile'
  win.left_win = vim.api.nvim_open_win(win.left_buf, true, {
    relative = 'editor', width = L.left_w, height = L.box_h, col = L.outer_col, row = L.top_row,
    style = 'minimal', border = 'single', title = ' Files ', title_pos = 'center',
  })
  require('config.hidden_cursor').mark_buffer(win.left_buf)
  vim.bo[win.left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.left_buf, 0, -1, false, { '  読み込み中...' })
  vim.bo[win.left_buf].modifiable = false

  win.right_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.right_buf].buftype    = 'nofile'
  vim.bo[win.right_buf].buflisted  = false
  vim.bo[win.right_buf].modifiable = false
  vim.bo[win.right_buf].filetype   = 'diff'
  require('config.hidden_cursor').mark_buffer(win.right_buf)
  win.right_win = vim.api.nvim_open_win(win.right_buf, false, {
    relative = 'editor', width = L.right_w, height = L.box_h, col = L.right_col, row = L.top_row,
    style = 'minimal', border = 'single', title = ' Diff ', title_pos = 'center',
  })
  vim.wo[win.right_win].wrap = false
  vim.wo[win.right_win].signcolumn = 'no'
  vim.wo[win.right_win].winhighlight = 'Normal:GitPanelBg'

  win.cmdlog_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.cmdlog_buf].buftype    = 'nofile'
  vim.bo[win.cmdlog_buf].buflisted  = false
  vim.bo[win.cmdlog_buf].modifiable = false
  require('config.hidden_cursor').mark_buffer(win.cmdlog_buf)
  win.cmdlog_win = vim.api.nvim_open_win(win.cmdlog_buf, false, {
    relative = 'editor', width = L.cmdlog_w, height = L.cmdlog_h, col = L.outer_col, row = L.cmdlog_row,
    style = 'minimal', border = 'single', title = ' Command Log ', title_pos = 'center',
  })
  vim.wo[win.cmdlog_win].wrap = false
  vim.wo[win.cmdlog_win].signcolumn = 'no'
  vim.wo[win.cmdlog_win].winhighlight = 'Normal:GitPanelBg'

  vim.api.nvim_create_autocmd('WinClosed', {
    group = augrp,
    pattern = tostring(win.tabbar_win) .. ',' .. tostring(win.left_win) .. ',' .. tostring(win.right_win) .. ',' .. tostring(win.cmdlog_win),
    callback = function() M.close() end,
  })

  git.find_root(function(root)
    if not root then
      vim.notify('gitリポジトリではありません', vim.log.levels.ERROR)
      M.close()
      return
    end
    render_cmdlog()
    activate_panel(1)
  end)
end

function M.open()
  if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then
    open()
  end
end

function M.toggle()
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    M.close()
  else
    open()
  end
end

-- ══════════════════════════════════════════════
-- ハイライト
-- ══════════════════════════════════════════════

local function setup_hl()
  vim.api.nvim_set_hl(0, 'GitPanelBg',           { bg = '#1a1b26' })
  vim.api.nvim_set_hl(0, 'GitPanelCursorLine',   { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'GitPanelHeader',       { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelSection',      { fg = '#e0af68', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelModified',     { fg = '#e0af68' })
  vim.api.nvim_set_hl(0, 'GitPanelAdded',        { fg = '#9ece6a' })
  vim.api.nvim_set_hl(0, 'GitPanelDeleted',      { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'GitPanelRenamed',      { fg = '#2ac3de' })
  vim.api.nvim_set_hl(0, 'GitPanelUntracked',    { fg = '#9ece6a', italic = true })
  vim.api.nvim_set_hl(0, 'GitPanelCurrent',      { fg = '#9ece6a', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelHunkSelected', { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'GitPanelTabActive',    { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelTabInactive',  { fg = '#565f89' })
  ui.setup_hl()
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

-- <leader>gg（ターミナル版lazygit）と接頭辞が被るため、timeoutlen待ちが起きないようnowaitで即時発火させる
vim.keymap.set('n', '<leader>g', function() M.toggle() end, { desc = 'gitパネルを開閉', nowait = true })
vim.api.nvim_create_user_command('Git', function() M.toggle() end, { desc = 'gitパネルを開閉' })

return M
