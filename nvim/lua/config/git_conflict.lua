-- コンフリクト解消（VSCode の Merge Conflict / GitHub の衝突エディタと同じ操作感・自作）
--
--   <<<<<<< HEAD          ← 現在の変更（Current / ours）
--   foo()
--   ||||||| base          ← 共通の祖先（diff3 スタイルのときだけ現れる）
--   =======
--   bar()
--   >>>>>>> origin/main   ← 入力側の変更（Incoming / theirs）
--
-- 衝突ブロックごとに背景色を付け、上に採用アクションを浮かせる（VSCode の CodeLens 相当）。
-- キーは Space x 系（c=現在 / i=入力側 / b=両方、大文字はファイル全体）と ]x / [x。

local M = {}

local ns = vim.api.nvim_create_namespace('git_conflict')
local augrp = vim.api.nvim_create_augroup('git_conflict', { clear = true })

local attached = {}   -- [buf] = true（キーマップ設定済み）
local refresh_timer = nil

-- ══════════════════════════════════════════════
-- パース
-- ══════════════════════════════════════════════

local function is_start(l) return l:match('^<<<<<<<') ~= nil end
local function is_base(l) return l:match('^|||||||') ~= nil end
local function is_mid(l) return l:match('^=======%s*$') ~= nil end
local function is_end(l) return l:match('^>>>>>>>') ~= nil end

--- 行リストから衝突ブロックを取り出す。行番号はすべて1始まり。
--- { start, mid, finish, base（あれば）, current_label, incoming_label }
function M.parse(lines)
  local out = {}
  local cur = nil
  for i, line in ipairs(lines) do
    if is_start(line) then
      cur = { start = i, current_label = vim.trim(line:sub(8)) }
    elseif cur and is_base(line) then
      cur.base = i
    elseif cur and is_mid(line) then
      cur.mid = i
    elseif cur and is_end(line) then
      if cur.mid then
        cur.finish = i
        cur.incoming_label = vim.trim(line:sub(8))
        table.insert(out, cur)
      end
      cur = nil
    end
  end
  return out
end

function M.parse_buf(buf)
  return M.parse(vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false))
end

--- 採用結果の行だけを返す。choice = 'current' | 'incoming' | 'both'
--- （diff3 の共通祖先パートはどの選択でも捨てる）
function M.resolved_lines(lines, conflict, choice)
  local current_last = (conflict.base or conflict.mid) - 1
  local current = vim.list_slice(lines, conflict.start + 1, current_last)
  local incoming = vim.list_slice(lines, conflict.mid + 1, conflict.finish - 1)
  if choice == 'current' then return current end
  if choice == 'incoming' then return incoming end
  local both = vim.list_extend({}, current)
  return vim.list_extend(both, incoming)
end

-- ══════════════════════════════════════════════
-- 表示
-- ══════════════════════════════════════════════

local function setup_hl()
  local function hl(name, opts)
    vim.api.nvim_set_hl(0, name, vim.tbl_extend('force', opts, { default = true }))
  end
  -- VSCode と同じ配色イメージ: 現在の変更＝緑、入力側＝青、共通の祖先＝グレー
  hl('GitConflictCurrent', { bg = '#1f3a2a' })
  hl('GitConflictCurrentLabel', { bg = '#2c5a3f', bold = true })
  hl('GitConflictIncoming', { bg = '#1e2f4a' })
  hl('GitConflictIncomingLabel', { bg = '#2c4a7a', bold = true })
  hl('GitConflictBase', { bg = '#2a2a35' })
  hl('GitConflictBaseLabel', { bg = '#3a3a48', bold = true })
  hl('GitConflictHint', { link = 'Comment' })
  hl('GitConflictHintKey', { link = 'Special' })
end

local function line_mark(buf, lnum, group)
  vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, {
    line_hl_group = group,
    priority = 100,
  })
end

--- 衝突ブロックの上に採用アクションを出す（VSCode の CodeLens 相当）
local function hint_mark(buf, conflict)
  vim.api.nvim_buf_set_extmark(buf, ns, conflict.start - 1, 0, {
    virt_lines_above = true,
    virt_lines = { {
      { '  ', 'GitConflictHint' },
      { 'Space x c', 'GitConflictHintKey' },
      { ' 現在の変更を採用  ', 'GitConflictHint' },
      { 'Space x i', 'GitConflictHintKey' },
      { ' 入力側の変更を採用  ', 'GitConflictHint' },
      { 'Space x b', 'GitConflictHintKey' },
      { ' 両方を採用  ', 'GitConflictHint' },
      { 'Space x d', 'GitConflictHintKey' },
      { ' 変更を比較', 'GitConflictHint' },
    } },
    priority = 100,
  })
end

--- 衝突の色付けとヒントを引き直す。戻り値は衝突の数
function M.render(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return 0 end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local conflicts = M.parse_buf(buf)
  for _, c in ipairs(conflicts) do
    line_mark(buf, c.start, 'GitConflictCurrentLabel')
    for i = c.start + 1, (c.base or c.mid) - 1 do
      line_mark(buf, i, 'GitConflictCurrent')
    end
    if c.base then
      line_mark(buf, c.base, 'GitConflictBaseLabel')
      for i = c.base + 1, c.mid - 1 do
        line_mark(buf, i, 'GitConflictBase')
      end
    end
    line_mark(buf, c.mid, 'GitConflictIncomingLabel')
    for i = c.mid + 1, c.finish - 1 do
      line_mark(buf, i, 'GitConflictIncoming')
    end
    line_mark(buf, c.finish, 'GitConflictIncomingLabel')
    hint_mark(buf, c)
  end
  return #conflicts
end

-- ══════════════════════════════════════════════
-- 操作
-- ══════════════════════════════════════════════

--- カーソル行を含む（無ければ次に来る）衝突を返す
function M.conflict_at(buf, lnum)
  local conflicts = M.parse_buf(buf)
  for _, c in ipairs(conflicts) do
    if lnum >= c.start and lnum <= c.finish then return c end
  end
  for _, c in ipairs(conflicts) do
    if c.start > lnum then return c end
  end
  return conflicts[#conflicts]
end

local function apply(buf, conflict, choice)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local kept = M.resolved_lines(lines, conflict, choice)
  vim.api.nvim_buf_set_lines(buf, conflict.start - 1, conflict.finish, false, kept)
end

--- カーソル位置の衝突を解消する。choice = 'current' | 'incoming' | 'both'
function M.choose(choice, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local conflict = M.conflict_at(buf, lnum)
  if not conflict then
    vim.notify('衝突が見つかりません', vim.log.levels.WARN, { title = 'Conflict' })
    return false
  end
  apply(buf, conflict, choice)
  M.after_change(buf)
  return true
end

--- ファイル内のすべての衝突を同じ選択で解消する（VSCode の Accept All 相当）
function M.choose_all(choice, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local conflicts = M.parse_buf(buf)
  -- 行番号がずれないよう後ろから適用する
  for i = #conflicts, 1, -1 do
    apply(buf, conflicts[i], choice)
  end
  M.after_change(buf)
  return #conflicts
end

--- 次 / 前の衝突へカーソルを移す
function M.goto_conflict(delta, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local conflicts = M.parse_buf(buf)
  if #conflicts == 0 then return end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local target
  if delta > 0 then
    for _, c in ipairs(conflicts) do
      if c.start > lnum then target = c.start; break end
    end
    target = target or conflicts[1].start -- 末尾まで来たら先頭へ回る
  else
    for _, c in ipairs(conflicts) do
      if c.start < lnum then target = c.start end
    end
    target = target or conflicts[#conflicts].start
  end
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  vim.cmd('normal! zz')
end

--- 現在の変更と入力側を並べて diff 表示する（VSCode の Compare Changes 相当）。
--- 別タブで開き、どちらかの窓で q を押すとタブごと閉じる
function M.compare(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local conflict = M.conflict_at(buf, lnum)
  if not conflict then
    vim.notify('衝突が見つかりません', vim.log.levels.WARN, { title = 'Conflict' })
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ft = vim.bo[buf].filetype

  local function scratch(name, content)
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, content)
    vim.bo[b].buftype = 'nofile'
    vim.bo[b].bufhidden = 'wipe'
    vim.bo[b].filetype = ft
    vim.bo[b].modifiable = false
    pcall(vim.api.nvim_buf_set_name, b, name)
    vim.keymap.set('n', 'q', '<Cmd>tabclose<CR>', { buffer = b, nowait = true, silent = true })
    return b
  end

  local current = scratch('現在の変更 (' .. (conflict.current_label ~= '' and conflict.current_label or 'HEAD') .. ')',
    M.resolved_lines(lines, conflict, 'current'))
  local incoming = scratch('入力側の変更 (' .. (conflict.incoming_label ~= '' and conflict.incoming_label or 'incoming') .. ')',
    M.resolved_lines(lines, conflict, 'incoming'))

  vim.cmd('tabnew')
  vim.api.nvim_win_set_buf(0, current)
  vim.cmd('diffthis')
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, incoming)
  vim.cmd('diffthis')
end

-- ══════════════════════════════════════════════
-- 有効化 / 無効化
-- ══════════════════════════════════════════════

local function set_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set('n', lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
  map('<leader>xc', function() M.choose('current') end, 'Conflict: 現在の変更を採用')
  map('<leader>xi', function() M.choose('incoming') end, 'Conflict: 入力側の変更を採用')
  map('<leader>xb', function() M.choose('both') end, 'Conflict: 両方を採用')
  map('<leader>xC', function() M.choose_all('current') end, 'Conflict: すべて現在の変更を採用')
  map('<leader>xI', function() M.choose_all('incoming') end, 'Conflict: すべて入力側の変更を採用')
  map('<leader>xB', function() M.choose_all('both') end, 'Conflict: すべて両方を採用')
  map('<leader>xd', function() M.compare() end, 'Conflict: 変更を比較')
  map(']x', function() M.goto_conflict(1) end, 'Conflict: 次の衝突へ')
  map('[x', function() M.goto_conflict(-1) end, 'Conflict: 前の衝突へ')
end

local function del_keymaps(buf)
  for _, lhs in ipairs({ '<leader>xc', '<leader>xi', '<leader>xb', '<leader>xC', '<leader>xI',
    '<leader>xB', '<leader>xd', ']x', '[x' }) do
    pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
  end
end

--- 衝突の有無に応じてキーマップと色付けを合わせる。衝突が無くなった瞬間だけ通知する
function M.after_change(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return 0 end
  local count = M.render(buf)
  if count > 0 then
    if not attached[buf] then
      set_keymaps(buf)
      attached[buf] = true
    end
  elseif attached[buf] then
    del_keymaps(buf)
    attached[buf] = nil
    vim.notify('衝突をすべて解消しました（保存して git パネルの Space でステージ）',
      vim.log.levels.INFO, { title = 'Conflict' })
  end
  return count
end

function M.detach(buf)
  if attached[buf] then
    del_keymaps(buf)
    attached[buf] = nil
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

function M.is_attached(buf)
  return attached[buf or vim.api.nvim_get_current_buf()] == true
end

local function schedule_refresh(buf)
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
  end
  refresh_timer = vim.uv.new_timer()
  refresh_timer:start(120, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(buf) then M.after_change(buf) end
  end))
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { group = augrp, callback = setup_hl })

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
  group = augrp,
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= '' then return end
    M.after_change(ev.buf)
  end,
})

-- 編集中に衝突マーカーを消していったら、色付けとキーマップも追随させる
vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
  group = augrp,
  callback = function(ev)
    if not attached[ev.buf] then return end
    schedule_refresh(ev.buf)
  end,
})

vim.api.nvim_create_autocmd('BufDelete', {
  group = augrp,
  callback = function(ev) attached[ev.buf] = nil end,
})

return M
