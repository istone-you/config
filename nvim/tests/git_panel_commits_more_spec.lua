-- commits.luaのさらに残っていた機能単位の穴(codexの独立調査で指摘):
-- resetのsoft/mixed(hardしか実操作を検証していなかった)、upstream無し/main未検出
-- 時の表示色分岐、t(revert)/Space(checkout_commit、他specで別途カバー済み)以外の
-- remember_cursor()、コミット詳細(右ペインのgit show表示)

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local function hl_at_row(win, row)
  local buf = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_create_namespace('git_panel_hl')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })
  for _, m in ipairs(marks) do
    if m[4] and m[4].hl_group then return m[4].hl_group end
  end
  return nil
end

T.describe('git_panel Commits panel: reset soft/mixed', function()
  T.it('g -> s (soft) keeps the change staged in the index', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'v1' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'v1' })
    T.write_file(dir .. '/a.txt', { 'v2' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'v2' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'v1'))
    GP.press('g')
    vim.wait(80)
    GP.press_modal('s') -- soft
    vim.wait(80)
    GP.press_modal('y')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout) == 'v1'
    end, 2000)
    T.eq(vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout), 'v1')
    T.contains(GP.git(dir, { 'diff', '--cached', '--name-only' }).stdout, 'a.txt',
      "soft reset should leave v2's change staged")
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'v2' }, "working tree should still have v2's content")

    GP.close()
    T.rmrf(dir)
  end)

  T.it('g -> m (mixed) unstages the change but keeps it in the working tree', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'v1' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'v1' })
    T.write_file(dir .. '/a.txt', { 'v2' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'v2' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'v1'))
    GP.press('g')
    vim.wait(80)
    GP.press_modal('m') -- mixed
    vim.wait(80)
    GP.press_modal('y')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout) == 'v1'
    end, 2000)
    T.eq(vim.trim(GP.git(dir, { 'diff', '--cached', '--name-only' }).stdout), '', 'mixed reset should unstage the change')
    T.contains(GP.git(dir, { 'diff', '--name-only' }).stdout, 'a.txt', 'the change should remain unstaged')
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'v2' })

    GP.close()
    T.rmrf(dir)
  end)
end)

T.describe('git_panel Commits panel: color display branches', function()
  T.it('shows no push-status color when there is no upstream and no main/master branch to resolve', function()
    -- resolve_main_branchesはmain/masterという名のローカルブランチがあれば
    -- upstream無しでも最終手段(優先順位3)でそれ自体を採用してしまうため、
    -- 本当に無色になるのはmain/masterという名前のブランチ自体が存在しない場合だけ
    local dir = T.tmp_git_repo(function(d)
      GP.git(d, { 'branch', '-m', 'main', 'trunk' })
    end)
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'no upstream commit' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    local row = GP.find_row(left, 'no upstream commit')
    T.ok(row ~= nil)
    T.eq(hl_at_row(left, row), nil, 'without an upstream, commits should not get red/yellow/green coloring')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('falls back to upstream-based coloring when neither main nor master exists', function()
    -- resolve_main_branchesの優先順位3番目(ローカルブランチ自体)まで解決できない
    -- (mainという名のブランチが存在しない)ケース。masterやmainブランチを一切
    -- 作らない独立リポジトリで確認する
    local dir = T.tmp_git_repo(function(d)
      GP.git(d, { 'branch', '-m', 'main', 'trunk' }) -- main/master以外の名前にリネーム
    end)
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/trunk', 'trunk' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/trunk', 'trunk' })
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'unpushed on trunk' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    local row = GP.find_row(left, 'unpushed on trunk')
    T.ok(row ~= nil)
    T.eq(hl_at_row(left, row), 'GitPanelUnpushed',
      'with no main/master resolvable, coloring should still fall back to plain upstream ahead/behind')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.describe('git_panel Commits panel: detail pane + cursor memory', function()
  T.it('right pane shows the full "git show" output (message, stat, diff) for the selected commit', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'line1', 'line2' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'add line2' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'add line2'))
    vim.wait(150)

    local detail = table.concat(GP.lines(GP.right_win()), '\n')
    T.contains(detail, 'add line2', 'commit message should be shown')
    T.contains(detail, 'a.txt', 'changed file should be shown')
    T.contains(detail, '+line2', 'the actual diff hunk should be shown')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('remember_cursor() keeps the selected commit highlighted across an auto-refresh', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'first' })
      T.write_file(d .. '/b.txt', { 'b' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'second' })
    end)

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    local row = GP.find_row(left, 'first')
    GP.goto_row(left, row)

    require('config.git_panel.commits').remember_cursor()
    require('config.git_panel.commits').refresh(true) -- 自動リフレッシュを模す(auto_capture=true)
    vim.wait(300)

    -- 再描画後もカーソルが"first"の行に残っていること(cursor_memによる復元)
    local cursor_row = vim.api.nvim_win_get_cursor(GP.left_win())[1]
    local restored_line = GP.lines(GP.left_win())[cursor_row]
    T.contains(restored_line, 'first', 'cursor should stay on the remembered commit after a refresh')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
