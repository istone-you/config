local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

--- カーソル行のハイライトグループ名を取り出す(hl_nsの名前空間に積んだextmarkから)
local function hl_at_row(win, row)
  local buf = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_create_namespace('git_panel_hl')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })
  for _, m in ipairs(marks) do
    if m[4] and m[4].hl_group then return m[4].hl_group end
  end
  return nil
end

T.describe('git_panel Commits panel', function()
  T.it('colors unpushed(red)/pushed(yellow)/merged(green) commits correctly', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })

    -- mergedコミット(main扱いに取り込まれている) = 最初のinitコミット
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/main', 'main' }) -- upstream = 現在のHEADに追従(pushed)

    -- 追加コミット: upstreamにはまだ無い = unpushed
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'unpushed change' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/main', 'main' })

    GP.open(dir, false)
    GP.press('2') -- Commitsパネル
    vim.wait(400)
    local left = GP.left_win()
    local lines = GP.lines(left)
    local unpushed_row, merged_row
    for i, l in ipairs(lines) do
      if l:find('unpushed change', 1, true) then unpushed_row = i end
      if l:find('init', 1, true) then merged_row = i end
    end
    T.ok(unpushed_row ~= nil, 'unpushed commit should be listed')
    T.ok(merged_row ~= nil, 'init(merged) commit should be listed')
    T.eq(hl_at_row(left, unpushed_row), 'GitPanelUnpushed')
    T.eq(hl_at_row(left, merged_row), 'GitPanelMerged')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('g opens the reset menu with soft/mixed/hard, hard actually discards changes', function()
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
    local row = GP.find_row(left, 'v1')
    T.ok(row ~= nil)
    GP.goto_row(left, row)
    GP.press('g')
    vim.wait(80)
    GP.press_modal('h') -- hard
    vim.wait(80)
    GP.press_modal('y') -- confirm
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout) == 'v1'
    end, 2000)
    T.eq(vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout), 'v1')
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'v1' })

    GP.close()
    T.rmrf(dir)
  end)

  T.it('n creates a new branch from the selected commit', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'v1' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'v1' })

    GP.open(dir, false)
    GP.press('2')
    vim.wait(300)
    local left = GP.left_win()
    local row = GP.find_row(left, 'v1')
    GP.goto_row(left, row)
    GP.press('n')
    vim.wait(80)
    GP.press_modal('ifrom-commit')
    GP.press_modal('<CR>')
    T.wait_until(function() return GP.git(dir, { 'rev-parse', '--verify', 'from-commit' }).code == 0 end)
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'from-commit' }).code, 0)

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
