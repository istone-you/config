-- worktree.luaのさらに残っていた機能単位の穴(codexの独立調査で指摘):
-- detached HEAD表示、dirtyなworktree削除失敗後のforce remove経路、
-- 新規作成時のブランチ名/パス空入力キャンセル

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

T.describe('git_panel Worktree panel: detached HEAD display', function()
  T.it('shows "(detached)" and the short HEAD hash for a detached worktree', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    local head = vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout)
    local wt_path = vim.fn.tempname()
    GP.git(dir, { 'worktree', 'add', '-q', '--detach', wt_path, head })

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.find_row(GP.left_win(), vim.fn.fnamemodify(wt_path, ':t')) ~= nil end, 3000)
    local left = GP.left_win()
    local row = GP.find_row(left, vim.fn.fnamemodify(wt_path, ':t'))
    T.ok(row ~= nil)
    T.contains(GP.lines(left)[row], '(detached)')

    GP.goto_row(left, row)
    T.wait_until(function()
      return table.concat(GP.lines(GP.right_win()), '\n'):find('detached HEAD', 1, true) ~= nil
    end, 3000)
    local detail = table.concat(GP.lines(GP.right_win()), '\n')
    T.contains(detail, '(detached HEAD)')
    T.contains(detail, head:sub(1, 7))

    GP.close()
    T.rmrf(dir); T.rmrf(wt_path)
  end)
end)

T.describe('git_panel Worktree panel: dirty removal -> force remove', function()
  T.it('d on a worktree with uncommitted changes offers to force-remove after the safe removal fails', function()
    local dir = T.tmp_git_repo()
    local wt_path = vim.fn.tempname()
    GP.git(dir, { 'worktree', 'add', '-q', '-b', 'wt-branch', wt_path })
    T.write_file(wt_path .. '/dirty.txt', { 'uncommitted' })
    GP.git(wt_path, { 'add', '.' }) -- indexに変更があるとplainなworktree removeが拒否される

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.find_row(GP.left_win(), 'wt-branch') ~= nil end, 3000)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'wt-branch'))
    GP.press('d')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000) -- 1段目: 削除確認
    GP.press_modal('y')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000) -- 2段目: force確認
    T.contains(table.concat(GP.lines(vim.api.nvim_get_current_win()), '\n'), '未コミット')
    GP.press_modal('n') -- 拒否
    T.wait_until(function() return GP.win_by_title('確認') == nil end, 2000) -- モーダルが閉じるのを待つ
    T.ok(vim.fn.isdirectory(wt_path) == 1, 'declining force-remove should keep the worktree')

    GP.press('d')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    GP.press_modal('y')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    GP.press_modal('y') -- 今度は承認
    T.wait_until(function()
      return not GP.git(dir, { 'worktree', 'list' }).stdout:find(wt_path, 1, true)
    end, 2000)
    T.ok(not GP.git(dir, { 'worktree', 'list' }).stdout:find(wt_path, 1, true), 'force-remove should succeed')

    GP.close()
    T.rmrf(dir); T.rmrf(wt_path)
  end)
end)

T.describe('git_panel Worktree panel: create cancel', function()
  T.it('n does nothing when the branch name is left empty (<Esc>)', function()
    local dir = T.tmp_git_repo()
    local before = GP.git(dir, { 'worktree', 'list' }).stdout

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.left_win() ~= nil end, 3000)
    GP.press('n')
    T.wait_until(function() return vim.api.nvim_get_current_win() ~= GP.left_win() end, 2000) -- 入力モーダルへ移った
    GP.press_modal('<Esc>')
    T.wait_until(function() return vim.api.nvim_get_current_win() == GP.left_win() end, 2000) -- 閉じて左パネルへ戻る
    T.eq(GP.git(dir, { 'worktree', 'list' }).stdout, before, 'no worktree should have been created')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('n does nothing when the branch name is given but the path prompt is cancelled', function()
    local dir = T.tmp_git_repo()
    local before = GP.git(dir, { 'worktree', 'list' }).stdout

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.left_win() ~= nil end, 3000)
    GP.press('nsome-branch<CR>')
    T.wait_until(function() return vim.api.nvim_get_current_win() ~= GP.left_win() end, 2000) -- 2段目のパス入力欄
    GP.press_modal('<Esc>') -- 2段目のパス入力をキャンセル
    T.wait_until(function() return vim.api.nvim_get_current_win() == GP.left_win() end, 2000)
    T.eq(GP.git(dir, { 'worktree', 'list' }).stdout, before, 'no worktree should have been created')
    T.ok(GP.git(dir, { 'rev-parse', '--verify', 'some-branch' }).code ~= 0,
      'the branch itself should not have been created either')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
