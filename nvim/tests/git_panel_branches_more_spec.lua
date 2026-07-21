-- branches.luaのさらに残っていた機能単位の穴(codexの独立調査で指摘):
-- gone/behind-only/ahead+behind表示分岐、PR DRAFT/CLOSED表示、checkout-by-nameの
-- remoteブランチ分岐、delete失敗→force削除、現在ブランチ削除拒否、
-- merge/rebase失敗通知、renameキャンセル/同名入力

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local git = require('config.git_panel.git')

local function fake_prs(map)
  local orig = {
    github_repo_info = git.github_repo_info,
    gh_auth_token = git.gh_auth_token,
    fetch_prs = git.fetch_prs,
  }
  git.github_repo_info = function(cb) cb({ owner = 'me', repo = 'repo' }) end
  git.gh_auth_token = function(cb) cb('fake-token') end
  git.fetch_prs = function(_, _, _, branch_names, cb)
    local prs = {}
    for _, name in ipairs(branch_names) do
      if map[name] then
        prs[#prs + 1] = vim.tbl_extend('force', {
          headRefName = name, title = 'x', number = 1, headRepositoryOwner = { login = 'me' },
        }, map[name])
      end
    end
    cb(prs)
  end
  return orig
end

local function restore_prs(orig)
  git.github_repo_info, git.gh_auth_token, git.fetch_prs = orig.github_repo_info, orig.gh_auth_token, orig.fetch_prs
end

T.describe('git_panel Branches panel: ahead/behind/gone display', function()
  T.it('shows behind-only (no ahead marker) when strictly behind upstream', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'branch', 'b' })
    GP.git(dir, { 'checkout', '-q', 'b' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/b', 'main' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/b', 'b' })
    -- リモートを1コミット進め、fetchして「behind」をローカルに認識させる
    GP.git(dir, { 'checkout', '-q', 'main' })
    T.write_file(dir .. '/x.txt', { 'x' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'extra' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/b', 'main' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    local text = table.concat(GP.lines(GP.left_win()), '\n')
    T.contains(text, '↓1')
    -- 同じ行に↑が出ていないことを確認する(behindのみ)
    local line
    for _, l in ipairs(GP.lines(GP.left_win())) do
      if l:find('↓1', 1, true) then line = l end
    end
    T.ok(line ~= nil and not line:find('↑', 1, true), 'behind-only should not also show an ahead marker')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('shows both ahead and behind markers when diverged', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'branch', 'b' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/b', 'b' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/b', 'b' })
    GP.git(dir, { 'checkout', '-q', 'b' })
    T.write_file(dir .. '/local.txt', { 'x' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'local ahead commit' })
    -- リモート追跡refだけをmainの先へ進めて「behind」を作る(diverge)
    GP.git(dir, { 'checkout', '-q', 'main' })
    T.write_file(dir .. '/remote.txt', { 'y' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'remote-side commit' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/b', 'main' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    local text = table.concat(GP.lines(GP.left_win()), '\n')
    T.contains(text, '↓1↑1')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('shows "(upstream gone)" when the tracked remote branch no longer exists', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'branch', 'b' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/b', 'b' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/b', 'b' })
    GP.git(dir, { 'update-ref', '-d', 'refs/remotes/origin/b' }) -- リモート追跡refを削除(goneを再現)

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    T.contains(table.concat(GP.lines(GP.left_win()), '\n'), 'upstream gone')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.describe('git_panel Branches panel: PR state display', function()
  T.it('shows a colored dot for OPEN/DRAFT/CLOSED PRs on non-main branches', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature-open' })
    GP.git(dir, { 'branch', 'feature-draft' })
    GP.git(dir, { 'branch', 'feature-closed' })
    for _, name in ipairs({ 'feature-open', 'feature-draft', 'feature-closed' }) do
      GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
      GP.git(dir, { 'update-ref', 'refs/remotes/origin/' .. name, name })
      GP.git(dir, { 'branch', '--set-upstream-to=origin/' .. name, name })
    end

    local orig = fake_prs({
      ['feature-open'] = { state = 'OPEN' },
      ['feature-draft'] = { state = 'DRAFT' },
      ['feature-closed'] = { state = 'CLOSED' },
    })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    require('config.git_panel.branches').refresh_prs()
    T.wait_until(function()
      return table.concat(GP.lines(GP.left_win()), '\n'):find('●') ~= nil
    end, 2000)

    local lines = GP.lines(GP.left_win())
    local function dot_before(needle)
      for _, l in ipairs(lines) do
        if l:find(needle, 1, true) then return l:find('●', 1, true) ~= nil end
      end
      return false
    end
    T.ok(dot_before('feature-open'), 'OPEN PR should show a dot')
    T.ok(dot_before('feature-draft'), 'DRAFT PR should show a dot')
    T.ok(dot_before('feature-closed'), 'CLOSED PR on a non-main branch should still show a dot')

    restore_prs(orig)
    GP.close()
    T.rmrf(dir)
  end)

  T.it('hides the PR dot for a CLOSED/MERGED PR attached to main/master itself', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/main', 'main' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/main', 'main' })

    local orig = fake_prs({ main = { state = 'MERGED' } })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    require('config.git_panel.branches').refresh_prs()
    vim.wait(300)

    local lines = GP.lines(GP.left_win())
    local main_line
    for _, l in ipairs(lines) do
      if l:find('main', 1, true) then main_line = l end
    end
    T.ok(main_line ~= nil, 'main should be listed')
    T.ok(not main_line:find('●', 1, true), 'a MERGED PR attached to main itself should not show a dot')

    restore_prs(orig)
    GP.close()
    T.rmrf(dir)
  end)

  T.it('shows the PR title/state header in the right pane detail view for the selected branch', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature' })
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/feature', 'feature' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/feature', 'feature' })

    local orig = fake_prs({ feature = { state = 'OPEN', title = 'My cool feature' } })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    require('config.git_panel.branches').refresh_prs()
    T.wait_until(function()
      return table.concat(GP.lines(GP.left_win()), '\n'):find('●') ~= nil
    end, 2000)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'feature'))
    T.wait_until(function()
      return table.concat(GP.lines(GP.right_win()), '\n'):find('My cool feature', 1, true) ~= nil
    end, 2000)

    local detail = table.concat(GP.lines(GP.right_win()), '\n')
    T.contains(detail, 'My cool feature')
    T.contains(detail, 'Open')

    restore_prs(orig)
    GP.close()
    T.rmrf(dir)
  end)
end)

T.describe('git_panel Branches panel: checkout-by-name remote-branch resolution', function()
  T.it('"origin/name" with no matching local branch creates a new tracking branch (checkout -b --track)', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/feature', 'main' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    GP.press('c')
    T.wait_until(function() return GP.win_by_title('チェックアウト') ~= nil end, 2000)
    GP.press_modal('iorigin/feature')
    vim.api.nvim_exec_autocmds('TextChangedI', { buffer = vim.api.nvim_get_current_buf() })
    GP.press_modal('<CR>')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout) == 'feature'
    end)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout), 'feature')
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'feature@{u}' }).stdout), 'origin/feature')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('"origin/name" with a same-named local branch already existing just checks that one out', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature' }) -- ローカルに同名ブランチが既にある
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/feature', 'feature' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    GP.press('c')
    T.wait_until(function() return GP.win_by_title('チェックアウト') ~= nil end, 2000)
    GP.press_modal('iorigin/feature')
    vim.api.nvim_exec_autocmds('TextChangedI', { buffer = vim.api.nvim_get_current_buf() })
    GP.press_modal('<CR>')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout) == 'feature'
    end)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout), 'feature')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('a "foo/bar"-shaped name where "foo" is not a registered remote falls back to create-new-branch', function()
    local dir = T.tmp_git_repo()

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    GP.press('c')
    T.wait_until(function() return GP.win_by_title('チェックアウト') ~= nil end, 2000)
    GP.press_modal('inotaremote/thing')
    vim.api.nvim_exec_autocmds('TextChangedI', { buffer = vim.api.nvim_get_current_buf() })
    GP.press_modal('<CR>')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    T.contains(table.concat(GP.lines(vim.api.nvim_get_current_win()), '\n'), 'notaremote/thing')
    GP.press_modal('y')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout) == 'notaremote/thing'
    end)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout), 'notaremote/thing',
      '"foo/bar" should be treated as a literal new branch name, not a remote/branch pair')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.describe('git_panel Branches panel: delete/merge/rebase/rename edge cases', function()
  T.it('d on the currently checked-out branch warns and does nothing (no confirm modal)', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'main'))
    GP.press('d')
    vim.wait(100)
    T.ok(GP.win_by_title('確認') == nil, 'no confirm modal should appear for the current branch')
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'main' }).code, 0, 'main should still exist')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('d on an unmerged branch offers to force-delete after the safe delete fails; declining keeps it', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'unmerged' })
    GP.git(dir, { 'checkout', '-q', 'unmerged' })
    T.write_file(dir .. '/x.txt', { 'x' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'unmerged commit' })
    GP.git(dir, { 'checkout', '-q', 'main' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'unmerged'))
    GP.press('d')
    vim.wait(80)
    GP.press_modal('y') -- 最初の確認: 削除しますか
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000) -- 2段目: 強制削除確認
    GP.press_modal('n') -- 拒否
    vim.wait(150)
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'unmerged' }).code, 0, 'declining force-delete should keep the branch')

    GP.press('d')
    vim.wait(80)
    GP.press_modal('y')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    GP.press_modal('y') -- 今度は強制削除を承認
    T.wait_until(function() return GP.git(dir, { 'rev-parse', '--verify', 'unmerged' }).code ~= 0 end, 2000)
    T.ok(GP.git(dir, { 'rev-parse', '--verify', 'unmerged' }).code ~= 0, 'accepting force-delete should remove it')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('M (merge) notifies failure on a real conflict instead of silently refreshing', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/f.txt', { 'base' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    GP.git(dir, { 'branch', 'conflict' })
    GP.git(dir, { 'checkout', '-q', 'conflict' })
    T.write_file(dir .. '/f.txt', { 'conflict-side' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'conflict commit' })
    GP.git(dir, { 'checkout', '-q', 'main' })
    T.write_file(dir .. '/f.txt', { 'main-side' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'main-side commit' })

    local notified
    local orig_notify = vim.notify
    vim.notify = function(msg, level) notified = { msg = msg, level = level } end

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'conflict'))
    GP.press('M')
    vim.wait(80)
    GP.press_modal('y')
    T.wait_until(function() return notified ~= nil end, 2000)
    vim.notify = orig_notify

    T.ok(notified ~= nil, 'a merge conflict should trigger a failure notification')
    T.contains(notified.msg, 'マージ失敗')
    GP.git(dir, { 'merge', '--abort' })

    GP.close()
    T.rmrf(dir)
  end)

  T.it('R (rename) does nothing on <Esc> cancel or when the typed name is unchanged', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'keep-me' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'keep-me'))
    GP.press('R')
    vim.wait(50)
    GP.press_modal('<Esc>')
    vim.wait(80)
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'keep-me' }).code, 0, 'Esc should leave the branch untouched')

    GP.press('R')
    vim.wait(50)
    GP.press_modal('<CR>') -- 名前を変えずにそのままEnter(入力欄の初期値=現在名)
    vim.wait(80)
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'keep-me' }).code, 0, 'submitting the unchanged name should be a no-op')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
