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

  T.it('shows the CI check icon (GitHub風の緑✓/黄●/赤✗) next to each PR', function()
    local git = require('config.git_panel.git')
    local orig = { list = git.gh_pr_list, view = git.gh_pr_view, diff = git.gh_pr_diff }
    git.gh_pr_list = function(_, cb) vim.schedule(function() cb({
      { number = 1, title = 'green pr', state = 'OPEN', author = { login = 'me' },
        headRefName = 'a', url = 'u1', checks = 'success' },
      { number = 2, title = 'yellow pr', state = 'OPEN', author = { login = 'me' },
        headRefName = 'b', url = 'u2', checks = 'pending' },
      { number = 3, title = 'red pr', state = 'OPEN', author = { login = 'me' },
        headRefName = 'c', url = 'u3', checks = 'failure' },
    }) end) end
    git.gh_pr_view = function(_, _, cb) vim.schedule(function() cb('body') end) end
    git.gh_pr_diff = function(_, cb) vim.schedule(function() cb('') end) end

    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('6')
    T.wait_until(function()
      local left = GP.left_win()
      return left and GP.find_row(left, 'red pr') ~= nil
    end)
    local left = GP.left_win()
    local function line_for(title) return GP.lines(left)[GP.find_row(left, title)] end
    T.contains(line_for('green pr'), '\239\128\140', 'success PR should show the check glyph (U+F00C)')
    T.contains(line_for('yellow pr'), '\239\132\145', 'pending PR should show the circle glyph (U+F111)')
    T.contains(line_for('red pr'), '\239\128\141', 'failure PR should show the times glyph (U+F00D)')

    GP.close()
    git.gh_pr_list, git.gh_pr_view, git.gh_pr_diff = orig.list, orig.view, orig.diff
    T.rmrf(dir)
  end)
  T.it('drops the PR number and the [Open] text label, showing the state icon instead', function()
    local git = require('config.git_panel.git')
    local orig = { list = git.gh_pr_list, view = git.gh_pr_view, diff = git.gh_pr_diff }
    git.gh_pr_list = function(_, cb) vim.schedule(function() cb({
      { number = 42, title = 'plain pr', state = 'OPEN', author = { login = 'me' },
        headRefName = 'feature', url = SAMPLE_URL },
    }) end) end
    git.gh_pr_view = function(_, _, cb) vim.schedule(function() cb('body') end) end
    git.gh_pr_diff = function(_, cb) vim.schedule(function() cb('') end) end

    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('6')
    T.wait_until(function()
      local left = GP.left_win()
      return left and GP.find_row(left, 'plain pr') ~= nil
    end)
    local left = GP.left_win()
    local line = GP.lines(left)[GP.find_row(left, 'plain pr')]
    T.ok(not line:find('#42', 1, true), 'row should not show the PR number')
    T.ok(not line:find('[Open]', 1, true), 'row should not show the [Open] text label')
    T.ok(not line:find('+', 1, true), 'row should not show +/- line counts')
    T.contains(line, '\239\144\135', 'row should show the Open state icon (U+F407)')

    GP.close()
    git.gh_pr_list, git.gh_pr_view, git.gh_pr_diff = orig.list, orig.view, orig.diff
    T.rmrf(dir)
  end)
  T.it('renders a distinct Nerd Font icon per PR state (open/draft/closed/merged)', function()
    local git = require('config.git_panel.git')
    local orig = { list = git.gh_pr_list, view = git.gh_pr_view, diff = git.gh_pr_diff }
    git.gh_pr_list = function(_, cb) vim.schedule(function() cb({
      { number = 1, title = 'open pr',   state = 'OPEN',   author = { login = 'me' }, headRefName = 'a', url = 'u1' },
      { number = 2, title = 'draft pr',  state = 'DRAFT',  author = { login = 'me' }, headRefName = 'b', url = 'u2' },
      { number = 3, title = 'closed pr', state = 'CLOSED', author = { login = 'me' }, headRefName = 'c', url = 'u3' },
      { number = 4, title = 'merged pr', state = 'MERGED', author = { login = 'me' }, headRefName = 'd', url = 'u4' },
    }) end) end
    git.gh_pr_view = function(_, _, cb) vim.schedule(function() cb('body') end) end
    git.gh_pr_diff = function(_, cb) vim.schedule(function() cb('') end) end

    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('6')
    T.wait_until(function()
      local left = GP.left_win()
      return left and GP.find_row(left, 'merged pr') ~= nil
    end)
    local left = GP.left_win()
    local function line_for(title) return GP.lines(left)[GP.find_row(left, title)] end
    T.contains(line_for('open pr'),   '\239\144\135', 'open PR shows U+F407')
    T.contains(line_for('draft pr'),  '\238\175\155', 'draft PR shows U+EBDB')
    T.contains(line_for('closed pr'), '\239\147\156', 'closed PR shows U+F4DC')
    T.contains(line_for('merged pr'), '\239\147\137', 'merged PR shows U+F4C9')

    GP.close()
    git.gh_pr_list, git.gh_pr_view, git.gh_pr_diff = orig.list, orig.view, orig.diff
    T.rmrf(dir)
  end)

  T.it('does not reload the PR detail (no extra gh pr view) when expanding with +', function()
    local git = require('config.git_panel.git')
    local orig = { list = git.gh_pr_list, view = git.gh_pr_view, diff = git.gh_pr_diff }
    git.gh_pr_list = function(_, cb) vim.schedule(function() cb({
      { number = 42, title = 'detail pr', state = 'OPEN', author = { login = 'me' },
        headRefName = 'feature', url = SAMPLE_URL },
    }) end) end
    local view_calls = 0
    git.gh_pr_view = function(_, _, cb)
      view_calls = view_calls + 1
      vim.schedule(function() cb('pr detail body') end)
    end
    git.gh_pr_diff = function(_, cb) vim.schedule(function() cb('') end) end

    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('6')
    T.wait_until(function()
      local left = GP.left_win()
      return left and GP.find_row(left, 'detail pr') ~= nil
    end)
    -- 詳細が一度取得されるまで待つ
    T.wait_until(function() return view_calls >= 1 end)
    local after_open = view_calls

    GP.press('+') -- 拡大（詳細=ANSIなので再取得は走らないはず）
    vim.wait(150)
    GP.press('+') -- 縮小
    vim.wait(150)
    T.eq(view_calls, after_open, 'expanding/collapsing PR detail must not re-fetch gh pr view')

    GP.close()
    git.gh_pr_list, git.gh_pr_view, git.gh_pr_diff = orig.list, orig.view, orig.diff
    T.rmrf(dir)
  end)
end)

T.summary()
