local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local git = require('config.git_panel.git')

T.describe('git_panel Branches panel', function()
  T.it('shows ahead/behind/gone markers based on upstream tracking', function()
    local dir = T.tmp_git_repo()
    -- --set-upstream-toはoriginが実在のremoteとして登録されていないと失敗するため
    -- (update-refでrefs/remotes/以下を直接作るだけでは駄目)、まずfake remoteを張る
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'branch', 'synced' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/synced', 'main' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/synced', 'synced' })

    GP.git(dir, { 'branch', 'ahead' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/ahead', 'main' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/ahead', 'ahead' })
    GP.git(dir, { 'checkout', '-q', 'ahead' })
    T.write_file(dir .. '/x.txt', { 'x' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'extra' })
    GP.git(dir, { 'checkout', '-q', 'main' })

    GP.open(dir, false)
    GP.press('3') -- Branchesパネルへ切替
    vim.wait(300)
    local left = GP.left_win()
    local text = table.concat(GP.lines(left), '\n')
    T.contains(text, 'synced')
    T.contains(text, '✓')
    T.contains(text, 'ahead')
    T.contains(text, '↑1')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Space checks out the branch under the cursor', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)
    local left = GP.left_win()
    local row = GP.find_row(left, 'feature')
    T.ok(row ~= nil)
    GP.goto_row(left, row)
    GP.press('<Space>')
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout) == 'feature'
    end)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout), 'feature')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('n creates a new branch, d deletes it', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('3')
    vim.wait(200)

    GP.press('n')
    vim.wait(80)
    GP.press_modal('ifresh-branch')
    GP.press_modal('<CR>')
    T.wait_until(function() return GP.git(dir, { 'rev-parse', '--verify', 'fresh-branch' }).code == 0 end)
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'fresh-branch' }).code, 0, 'branch should be created')

    -- 作成すると新規ブランチへチェックアウトされる想定(checkout -b)。mainへ戻ってから削除する
    GP.git(dir, { 'checkout', '-q', 'main' })
    GP.press('R')
    vim.wait(150)
    local left = GP.left_win()
    local row = GP.find_row(left, 'fresh-branch')
    T.ok(row ~= nil, 'fresh-branch should be listed')
    GP.goto_row(left, row)
    GP.press('d')
    vim.wait(80)
    GP.press_modal('y') -- 確認モーダル
    T.wait_until(function() return GP.git(dir, { 'rev-parse', '--verify', 'fresh-branch' }).code ~= 0 end)
    T.ok(GP.git(dir, { 'rev-parse', '--verify', 'fresh-branch' }).code ~= 0, 'branch should be gone')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('D bulk-deletes only branches whose PR is MERGED (force delete for squash-merged)', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature-merged' })
    GP.git(dir, { 'branch', 'feature-open' })
    -- squash merge相当: ブランチのコミットがmainの履行に含まれない状態を再現
    GP.git(dir, { 'checkout', '-q', 'feature-merged' })
    T.write_file(dir .. '/m.txt', { 'm' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'squash source' })
    GP.git(dir, { 'checkout', '-q', 'main' })
    T.eq(GP.git(dir, { 'branch', '-d', 'feature-merged' }).code ~= 0, true,
      'sanity check: safe delete should fail (not merged locally, like a real squash-merge)')
    -- gitのブランチ状態を戻すため再作成(上のdは失敗するはずだが保険)
    if GP.git(dir, { 'rev-parse', '--verify', 'feature-merged' }).code ~= 0 then
      GP.git(dir, { 'branch', 'feature-merged' })
    end

    -- GitHub PR取得は本物のgh/networkに依存するため、git.luaの取得関数だけ
    -- テスト用のfakeに差し替える(このnvimプロセス内だけの一時的な差し替え)
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
        if name == 'feature-merged' then
          table.insert(prs, { headRefName = name, state = 'MERGED', title = 'x', number = 1,
            headRepositoryOwner = { login = 'me' } })
        elseif name == 'feature-open' then
          table.insert(prs, { headRefName = name, state = 'OPEN', title = 'y', number = 2,
            headRepositoryOwner = { login = 'me' } })
        end
      end
      cb(prs)
    end
    -- upstreamが無いとbranch_namesが空になりfetch_prsが呼ばれないため、fake upstreamを張る
    -- (--set-upstream-toはoriginが実在のremoteとして登録されていないと失敗する)
    GP.git(dir, { 'remote', 'add', 'origin', 'https://example.invalid/repo.git' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/feature-merged', 'feature-merged' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/feature-merged', 'feature-merged' })
    GP.git(dir, { 'update-ref', 'refs/remotes/origin/feature-open', 'feature-open' })
    GP.git(dir, { 'branch', '--set-upstream-to=origin/feature-open', 'feature-open' })

    GP.open(dir, false)
    GP.press('3')
    vim.wait(300)
    local branches = require('config.git_panel.branches')
    branches.refresh_prs()
    T.wait_until(function()
      return table.concat(GP.lines(GP.left_win()), '\n'):find('●') ~= nil
    end, 2000)

    GP.press('D')
    vim.wait(80)
    GP.press_modal('y') -- 確認モーダル
    T.wait_until(function() return GP.git(dir, { 'rev-parse', '--verify', 'feature-merged' }).code ~= 0 end, 2000)
    T.ok(GP.git(dir, { 'rev-parse', '--verify', 'feature-merged' }).code ~= 0, 'feature-merged should be deleted')
    T.eq(GP.git(dir, { 'rev-parse', '--verify', 'feature-open' }).code, 0, 'feature-open (PR still open) should remain')

    git.github_repo_info, git.gh_auth_token, git.fetch_prs =
      orig.github_repo_info, orig.gh_auth_token, orig.fetch_prs
    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
