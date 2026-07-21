-- stash.luaのさらに残っていた機能単位の穴(codexの独立調査で指摘):
-- apply/pop失敗時の通知、詳細diff表示の内容確認、新規ブランチ名の空入力キャンセル

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

T.describe('git_panel Stash panel: failure/cancel/detail', function()
  T.it('Space (apply) notifies failure when it conflicts with the current dirty working tree', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'base' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'stashed-side' })
    GP.git(dir, { 'stash', 'push', '-m', 'conflicting stash' })
    T.write_file(dir .. '/a.txt', { 'dirty-side' }) -- 適用しようとすると同じ行がconflict

    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg, level) notified = { msg = msg, level = level } end

    GP.open(dir, false)
    GP.press('4')
    vim.wait(300)
    GP.press('<Space>')
    T.wait_until(function() return notified ~= nil end, 2000)
    vim.notify = orig_notify

    T.ok(notified ~= nil, 'a conflicting apply should trigger a failure notification')
    T.contains(notified.msg, '適用失敗')
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'dirty-side' }, 'the working tree should be left untouched on failure')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('g (pop) notifies failure on conflict and keeps the stash entry (does not silently drop it)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'base' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'stashed-side' })
    GP.git(dir, { 'stash', 'push', '-m', 'conflicting stash' })
    T.write_file(dir .. '/a.txt', { 'dirty-side' })

    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg, level) notified = { msg = msg, level = level } end

    GP.open(dir, false)
    GP.press('4')
    vim.wait(300)
    GP.press('g')
    T.wait_until(function() return notified ~= nil end, 2000)
    vim.notify = orig_notify

    T.ok(notified ~= nil, 'a conflicting pop should trigger a failure notification')
    T.contains(notified.msg, 'pop失敗')
    T.eq(#vim.split(vim.trim(GP.git(dir, { 'stash', 'list' }).stdout), '\n'), 1,
      'the stash should NOT be dropped when applying it failed')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('n (new branch from stash) does nothing when the typed name is empty (<Esc>)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'x' })
    GP.git(dir, { 'stash', 'push', '-m', 'stash' })
    local branches_before = GP.git(dir, { 'branch', '--list' }).stdout

    GP.open(dir, false)
    GP.press('4')
    vim.wait(300)
    GP.press('n')
    vim.wait(80)
    GP.press_modal('<Esc>')
    vim.wait(100)
    T.eq(GP.git(dir, { 'branch', '--list' }).stdout, branches_before, 'no branch should have been created')

    GP.close()
    T.rmrf(dir)
  end)

  T.it("the right pane shows the stash's actual diff content, not just a static placeholder", function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'unchanged' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'unchanged', 'added by stash' })
    GP.git(dir, { 'stash', 'push', '-m', 'diff check' })

    GP.open(dir, false)
    GP.press('4')
    vim.wait(300)
    T.wait_until(function()
      return table.concat(GP.lines(GP.right_win()), '\n'):find('added by stash', 1, true) ~= nil
    end, 2000)
    local detail = table.concat(GP.lines(GP.right_win()), '\n')
    T.contains(detail, '+added by stash')
    T.contains(detail, 'a.txt')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
