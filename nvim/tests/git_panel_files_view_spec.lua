-- Filesパネルの表示モード切替(t): ツリー ⇄ VSCode風のセクション別フラット一覧
-- view_modeはモジュール内に保持され続けるので、各itは必ずtree表示に戻してから終わること
local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

--- セクション行(" ▾ Changes  (2)")の行番号。'Changes' は 'Staged Changes' の部分文字列
--- なので単純な部分一致では区別できず、矢印の後ろのラベル全体で突き合わせる
local function section_row(win, label)
  for i, l in ipairs(GP.lines(win)) do
    if l:match('^%s*%S+%s+(.-)%s*%(%d+%)$') == label then return i end
  end
  return nil
end

local function any_section(win)
  return section_row(win, 'Changes') or section_row(win, 'Staged Changes')
    or section_row(win, 'Merge Changes')
end

--- view_mode はモジュール内に残り続けるため、前の it が失敗して戻し損ねていても
--- 確実に狙ったモードから始められるようにする（tを盲目的に押すと反転してしまう）
local function enter_list(win)
  if not any_section(win) then GP.press('t'); vim.wait(80) end
end

local function leave_list(win)
  if any_section(win) then GP.press('t'); vim.wait(80) end
end

local function seed(d)
  T.write_file(d .. '/a.txt', { 'a' })
  T.write_file(d .. '/sub/b.txt', { 'b' })
  GP.git(d, { 'add', '.' })
  GP.git(d, { 'commit', '-qm', 'seed' })
end

T.describe('git_panel Files panel: list/tree view toggle (t)', function()
  T.it('t splits files into Staged Changes / Changes sections and back into a tree', function()
    local dir = T.tmp_git_repo(seed)
    T.write_file(dir .. '/a.txt', { 'a', 'unstaged' })   -- 未ステージ
    T.write_file(dir .. '/sub/b.txt', { 'b', 'staged' })
    GP.git(dir, { 'add', 'sub/b.txt' })                  -- ステージ済み
    T.write_file(dir .. '/new.txt', { 'new' })           -- 未追跡

    GP.open(dir, false)
    local left = GP.left_win()
    -- tree表示: セクション行は無く、ディレクトリ行がある
    T.ok(section_row(left, 'Staged Changes') == nil, 'tree view has no section headers')
    T.ok(GP.find_row(left, 'sub') ~= nil, 'tree view lists the directory node')

    enter_list(left)
    local lines = GP.lines(left)
    local text = table.concat(lines, '\n')
    T.contains(text, 'Staged Changes')
    T.contains(text, 'Changes')
    -- ステージ済みのb.txtはStaged Changes配下、未ステージのa.txt/new.txtはChanges配下
    local staged_row = section_row(left, 'Staged Changes')
    local changes_row = section_row(left, 'Changes') -- a.txt と new.txt の2件
    T.ok(staged_row ~= nil and changes_row ~= nil, 'both sections are rendered')
    T.ok(GP.find_row(left, 'b.txt') > staged_row, 'staged file is under Staged Changes')
    T.ok(GP.find_row(left, 'b.txt') < changes_row, 'staged file is above the Changes section')
    T.ok(GP.find_row(left, 'a.txt') > changes_row, 'unstaged file is under Changes')
    T.contains(lines[staged_row], '(1)', 'section header shows the file count')
    -- list表示はファイル名のみ + ディレクトリを後ろへ添える（フルパス1本ではない）
    T.contains(lines[GP.find_row(left, 'b.txt')], 'b.txt  sub')

    GP.press('t')
    vim.wait(80)
    T.ok(any_section(left) == nil, 't toggles back to the tree view')
    T.ok(GP.find_row(left, 'sub') ~= nil, 'tree view is restored')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('a file with both staged and unstaged changes appears in both sections', function()
    local dir = T.tmp_git_repo(seed)
    T.write_file(dir .. '/a.txt', { 'a', 'staged' })
    GP.git(dir, { 'add', 'a.txt' })
    T.write_file(dir .. '/a.txt', { 'a', 'staged', 'then unstaged' })

    GP.open(dir, false)
    local left = GP.left_win()
    enter_list(left)
    local rows = {}
    for i, l in ipairs(GP.lines(left)) do
      if l:find('a.txt', 1, true) then table.insert(rows, i) end
    end
    T.eq(#rows, 2, 'a.txt is listed once per section')

    -- Staged Changes 側の行で Space → その行はアンステージされ、Changes 側だけが残る
    GP.goto_row(left, rows[1])
    GP.press('<Space>')
    T.wait_until(function() return GP.status(dir):find('^ M a.txt') ~= nil end)
    T.contains(GP.status(dir), ' M a.txt', 'the staged side was unstaged')
    -- パネルの再描画は git 実行の後に非同期で来るので、行が消えるまで待つ
    T.wait_until(function() return section_row(left, 'Staged Changes') == nil end)
    T.ok(section_row(left, 'Staged Changes') == nil, 'the emptied section disappears')

    leave_list(left)
    GP.close()
    T.rmrf(dir)
  end)

  T.it('Space on a section header stages/unstages every file in that section', function()
    local dir = T.tmp_git_repo(seed)
    T.write_file(dir .. '/a.txt', { 'a', 'x' })
    T.write_file(dir .. '/sub/b.txt', { 'b', 'x' })

    GP.open(dir, false)
    local left = GP.left_win()
    enter_list(left)
    local row = section_row(left, 'Changes')
    T.ok(row ~= nil, 'Changes section exists')
    GP.goto_row(left, row)
    GP.press('<Space>')
    T.wait_until(function()
      local st = GP.status(dir)
      return st:find('M  a.txt', 1, true) and st:find('M  sub/b.txt', 1, true)
    end)
    local st = GP.status(dir)
    T.contains(st, 'M  a.txt', 'section staging staged every file')
    T.contains(st, 'M  sub/b.txt', 'section staging staged every file')

    -- 全部ステージ済みになったので Staged Changes 側で Space → 全部アンステージ
    T.wait_until(function() return section_row(left, 'Staged Changes') ~= nil end)
    local staged_row = section_row(left, 'Staged Changes')
    T.ok(staged_row ~= nil, 'Staged Changes section exists after staging')
    GP.goto_row(left, staged_row)
    GP.press('<Space>')
    T.wait_until(function() return GP.status(dir):find(' M a.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), ' M a.txt', 'section unstaging unstaged every file')

    leave_list(left)
    GP.close()
    T.rmrf(dir)
  end)

  T.it('conflicts are collected in a Merge Changes section', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/c.txt', { 'base' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { 'commit', '-qm', 'seed' })
      GP.git(d, { 'checkout', '-q', '-b', 'other' })
      T.write_file(d .. '/c.txt', { 'other' })
      GP.git(d, { 'commit', '-qam', 'other' })
      GP.git(d, { 'checkout', '-q', 'main' })
      T.write_file(d .. '/c.txt', { 'main' })
      GP.git(d, { 'commit', '-qam', 'main' })
      GP.git(d, { 'merge', 'other' }) -- 衝突させる
    end)

    GP.open(dir, false)
    local left = GP.left_win()
    enter_list(left)
    local merge_row = section_row(left, 'Merge Changes')
    T.ok(merge_row ~= nil, 'conflicted file gets its own section')
    T.ok(GP.find_row(left, 'c.txt') > merge_row, 'the conflicted file is under Merge Changes')
    T.ok(section_row(left, 'Staged Changes') == nil, 'a conflict is not counted as staged')

    leave_list(left)
    GP.close()
    T.rmrf(dir)
  end)

  T.it('the right pane follows the section: staged row shows the staged diff', function()
    local dir = T.tmp_git_repo(seed)
    T.write_file(dir .. '/a.txt', { 'a', 'STAGEDLINE' })
    GP.git(dir, { 'add', 'a.txt' })
    T.write_file(dir .. '/a.txt', { 'a', 'STAGEDLINE', 'WORKTREELINE' })

    GP.open(dir, false)
    local left, right = GP.left_win(), GP.right_win()
    enter_list(left)
    local staged_row = section_row(left, 'Staged Changes')
    GP.goto_row(left, staged_row + 1)
    T.wait_until(function() return table.concat(GP.lines(right), '\n'):find('STAGEDLINE', 1, true) ~= nil end)
    local staged_text = table.concat(GP.lines(right), '\n')
    T.contains(staged_text, 'STAGEDLINE')
    T.ok(not staged_text:find('WORKTREELINE', 1, true), 'staged row must not show the worktree-only diff')

    local changes_row = section_row(left, 'Changes')
    GP.goto_row(left, changes_row + 1)
    T.wait_until(function() return table.concat(GP.lines(right), '\n'):find('WORKTREELINE', 1, true) ~= nil end)
    T.contains(table.concat(GP.lines(right), '\n'), 'WORKTREELINE')

    leave_list(left)
    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
