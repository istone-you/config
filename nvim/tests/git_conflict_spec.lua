local T = dofile(TESTS_DIR .. '/helpers.lua')
vim.g.mapleader = ' '
local conflict = require('config.git_conflict')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local SAMPLE = {
  'top',
  '<<<<<<< HEAD',
  'current-1',
  'current-2',
  '=======',
  'incoming-1',
  '>>>>>>> origin/main',
  'bottom',
}

local DIFF3 = {
  '<<<<<<< HEAD',
  'current',
  '||||||| merged common ancestors',
  'base',
  '=======',
  'incoming',
  '>>>>>>> origin/main',
}

--- 衝突入りのバッファを作って開く（BufReadPost 相当は after_change で明示的に起こす）
local function fresh(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  conflict.after_change(buf)
  return buf
end

local function lines_of(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

T.describe('git_conflict パース', function()
  T.it('衝突ブロックの行番号とラベルを取る', function()
    local list = conflict.parse(SAMPLE)
    T.eq(#list, 1)
    T.eq(list[1].start, 2)
    T.eq(list[1].mid, 5)
    T.eq(list[1].finish, 7)
    T.eq(list[1].current_label, 'HEAD')
    T.eq(list[1].incoming_label, 'origin/main')
    T.eq(list[1].base, nil)
  end)

  T.it('diff3 スタイルの共通祖先も拾う', function()
    local list = conflict.parse(DIFF3)
    T.eq(list[1].base, 3)
    T.eq(list[1].mid, 5)
  end)

  T.it('複数の衝突を順に返す', function()
    local lines = vim.list_extend(vim.list_slice(SAMPLE, 1, 8), SAMPLE)
    local list = conflict.parse(lines)
    T.eq(#list, 2)
    T.eq(list[1].start, 2)
    T.eq(list[2].start, 10)
  end)

  T.it('閉じていないマーカーは衝突として扱わない', function()
    T.eq(#conflict.parse({ '<<<<<<< HEAD', 'x', '=======', 'y' }), 0)
    T.eq(#conflict.parse({ '<<<<<<< HEAD', 'x', '>>>>>>> other' }), 0) -- ======= が無い
  end)

  T.it('マーカーに似た本文（=== や <<< 3個）は誤検知しない', function()
    T.eq(#conflict.parse({ '<<< not a marker', '===', '>>> nope' }), 0)
  end)
end)

T.describe('git_conflict 採用', function()
  T.it('resolved_lines: current / incoming / both', function()
    local c = conflict.parse(SAMPLE)[1]
    T.eq(conflict.resolved_lines(SAMPLE, c, 'current'), { 'current-1', 'current-2' })
    T.eq(conflict.resolved_lines(SAMPLE, c, 'incoming'), { 'incoming-1' })
    T.eq(conflict.resolved_lines(SAMPLE, c, 'both'), { 'current-1', 'current-2', 'incoming-1' })
  end)

  T.it('diff3 の共通祖先はどの選択でも捨てる', function()
    local c = conflict.parse(DIFF3)[1]
    T.eq(conflict.resolved_lines(DIFF3, c, 'current'), { 'current' })
    T.eq(conflict.resolved_lines(DIFF3, c, 'both'), { 'current', 'incoming' })
  end)

  T.it('Space x c で現在の変更を採用する', function()
    local buf = fresh(SAMPLE)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    feed(' xc')
    T.eq(lines_of(buf), { 'top', 'current-1', 'current-2', 'bottom' })
  end)

  T.it('Space x i で入力側の変更を採用する', function()
    local buf = fresh(SAMPLE)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    feed(' xi')
    T.eq(lines_of(buf), { 'top', 'incoming-1', 'bottom' })
  end)

  T.it('Space x b で両方を残す', function()
    local buf = fresh(SAMPLE)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    feed(' xb')
    T.eq(lines_of(buf), { 'top', 'current-1', 'current-2', 'incoming-1', 'bottom' })
  end)

  T.it('ブロックの外にカーソルがあっても次の衝突を対象にする', function()
    local buf = fresh(SAMPLE)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    conflict.choose('current', buf)
    T.eq(lines_of(buf), { 'top', 'current-1', 'current-2', 'bottom' })
  end)

  T.it('Space x C はファイル内すべてを現在の変更で解消する', function()
    local buf = fresh(vim.list_extend(vim.list_slice(SAMPLE, 1, 8), SAMPLE))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed(' xC')
    T.eq(lines_of(buf), { 'top', 'current-1', 'current-2', 'bottom',
      'top', 'current-1', 'current-2', 'bottom' })
    T.eq(#conflict.parse_buf(buf), 0)
  end)

  T.it('片側が空の衝突も潰せる', function()
    local buf = fresh({ '<<<<<<< HEAD', '=======', 'incoming', '>>>>>>> other' })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    conflict.choose('current', buf)
    T.eq(lines_of(buf), { '' }) -- 空バッファ相当
  end)
end)

T.describe('git_conflict 移動と表示', function()
  T.it(']x / [x で衝突の間を移動する（端では回り込む）', function()
    fresh(vim.list_extend(vim.list_slice(SAMPLE, 1, 8), SAMPLE))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed(']x')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 2)
    feed(']x')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 10)
    feed(']x')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 2) -- 末尾の次は先頭へ
    feed('[x')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 10)
  end)

  T.it('衝突ブロックに色を付け、上に採用アクションを浮かべる', function()
    local buf = fresh(SAMPLE)
    local ns = vim.api.nvim_get_namespaces()['git_conflict']
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local groups, hints = {}, 0
    for _, m in ipairs(marks) do
      local d = m[4]
      if d.line_hl_group then groups[d.line_hl_group] = (groups[d.line_hl_group] or 0) + 1 end
      if d.virt_lines then hints = hints + 1 end
    end
    T.eq(groups.GitConflictCurrent, 2)   -- current-1 / current-2
    T.eq(groups.GitConflictIncoming, 1)  -- incoming-1
    T.eq(groups.GitConflictCurrentLabel, 1)
    T.eq(groups.GitConflictIncomingLabel, 2) -- ======= と >>>>>>>
    T.eq(hints, 1)
  end)

  T.it('衝突が無いバッファには何もしない（キーマップも付けない）', function()
    local buf = fresh({ 'just', 'text' })
    T.eq(conflict.is_attached(buf), false)
    local lhs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do lhs[m.lhs] = true end
    T.eq(lhs[']x'], nil)
  end)

  T.it('衝突を全部解消するとキーマップと色付けが外れる', function()
    local buf = fresh(SAMPLE)
    T.eq(conflict.is_attached(buf), true)
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    conflict.choose('current', buf)
    T.eq(conflict.is_attached(buf), false)
    local ns = vim.api.nvim_get_namespaces()['git_conflict']
    T.eq(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 0)
  end)
end)

T.summary()
