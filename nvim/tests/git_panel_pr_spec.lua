-- PRパネル: y でURLコピー（ghはスタブしてネットワークに依存しない）

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local SAMPLE_URL = 'https://github.com/example/repo/pull/42'

local function stub_gh()
  local git = require('config.git_panel.git')
  local orig = {
    list = git.gh_pr_list,
    view = git.gh_pr_view,
    diff = git.gh_pr_diff,
  }
  local sample = {
    number = 42,
    title = 'sample pr',
    state = 'OPEN',
    author = { login = 'me' },
    headRefName = 'feature',
    url = SAMPLE_URL,
  }
  git.gh_pr_list = function(_, cb)
    vim.schedule(function() cb({ sample }) end)
  end
  git.gh_pr_view = function(_, _, cb)
    vim.schedule(function() cb('pr detail body') end)
  end
  git.gh_pr_diff = function(_, cb)
    vim.schedule(function() cb('') end)
  end
  return function()
    git.gh_pr_list = orig.list
    git.gh_pr_view = orig.view
    git.gh_pr_diff = orig.diff
  end
end

T.describe('git_panel PR panel', function()
  T.it('y copies the selected PR URL to the unnamed register', function()
    local restore = stub_gh()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('6') -- PRパネル
    T.wait_until(function()
      local left = GP.left_win()
      return left and GP.find_row(left, 'sample pr') ~= nil
    end)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'sample pr'))
    GP.press('y')
    vim.wait(50)
    T.eq(vim.fn.getreg('"'), SAMPLE_URL)

    GP.close()
    restore()
    T.rmrf(dir)
  end)
end)

T.summary()
