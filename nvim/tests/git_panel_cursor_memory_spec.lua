local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local function current_line(win)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return GP.lines(win)[row] or ''
end

local function goto_row_containing(win, needle)
  local row = GP.find_row(win, needle)
  T.ok(row ~= nil, 'row for ' .. needle)
  GP.goto_row(win, row)
end

local function assert_cursor_line_contains(win, needle, msg)
  T.contains(current_line(win), needle, msg)
end

T.describe('git_panel cursor memory', function()
  T.it('Files: a later refresh does not snap back after the user moves the cursor', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })

    GP.open(dir, false)
    local left = GP.left_win()
    T.wait_until(function() return GP.find_row(left, 'b.txt') ~= nil end)

    goto_row_containing(left, 'b.txt')
    require('config.git_panel.files').refresh()
    T.wait_until(function() return current_line(left):find('b.txt', 1, true) ~= nil end)
    assert_cursor_line_contains(left, 'b.txt', 'Files refresh should keep b.txt selected')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Branches: a later refresh does not snap back after the user moves the cursor', function()
    local dir = T.tmp_git_repo()
    T.git(dir, { 'branch', 'cursor-memory-a' })
    T.git(dir, { 'branch', 'cursor-memory-b' })

    GP.open(dir, false)
    GP.press('3')
    local left = GP.left_win()
    T.wait_until(function() return GP.find_row(left, 'cursor-memory-b') ~= nil end)

    goto_row_containing(left, 'cursor-memory-b')
    require('config.git_panel.branches').refresh()
    T.wait_until(function() return current_line(left):find('cursor-memory-b', 1, true) ~= nil end)
    assert_cursor_line_contains(left, 'cursor-memory-b', 'Branches refresh should keep the moved-to branch selected')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Commits: a later refresh does not snap back after the user moves the cursor', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/one.txt', { 'one' })
    T.git(dir, { 'add', 'one.txt' })
    T.git(dir, { '-c', 'user.email=test@test', '-c', 'user.name=test', 'commit', '-qm', 'first cursor commit' })
    T.write_file(dir .. '/two.txt', { 'two' })
    T.git(dir, { 'add', 'two.txt' })
    T.git(dir, { '-c', 'user.email=test@test', '-c', 'user.name=test', 'commit', '-qm', 'second cursor commit' })

    GP.open(dir, false)
    GP.press('2')
    local left = GP.left_win()
    T.wait_until(function() return GP.find_row(left, 'first cursor commit') ~= nil end)

    goto_row_containing(left, 'first cursor commit')
    require('config.git_panel.commits').refresh()
    T.wait_until(function() return current_line(left):find('first cursor commit', 1, true) ~= nil end)
    assert_cursor_line_contains(left, 'first cursor commit', 'Commits refresh should keep the moved-to commit selected')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Stash: a later refresh does not snap back after the user moves the cursor', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/file.txt', { 'one' })
    T.git(dir, { 'stash', 'push', '-u', '-m', 'stash one' })
    T.write_file(dir .. '/file.txt', { 'two' })
    T.git(dir, { 'stash', 'push', '-u', '-m', 'stash two' })

    GP.open(dir, false)
    GP.press('4')
    local left = GP.left_win()
    T.wait_until(function() return GP.find_row(left, 'stash one') ~= nil end)

    goto_row_containing(left, 'stash one')
    require('config.git_panel.stash').refresh()
    T.wait_until(function() return current_line(left):find('stash one', 1, true) ~= nil end)
    assert_cursor_line_contains(left, 'stash one', 'Stash refresh should keep the moved-to stash selected')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Worktree: a later refresh does not snap back after the user moves the cursor', function()
    local dir = T.tmp_git_repo()
    local wt = vim.fn.tempname()
    T.git(dir, { 'worktree', 'add', '-q', '-b', 'cursor-memory-worktree', wt })

    GP.open(dir, false)
    GP.press('5')
    local left = GP.left_win()
    T.wait_until(function() return GP.find_row(left, wt) ~= nil end)

    goto_row_containing(left, wt)
    require('config.git_panel.worktree').refresh()
    T.wait_until(function() return current_line(left):find(wt, 1, true) ~= nil end)
    assert_cursor_line_contains(left, wt, 'Worktree refresh should keep the moved-to worktree selected')

    GP.close()
    T.rmrf(dir)
    T.rmrf(wt)
  end)
end)

T.summary()
