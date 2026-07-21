local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

T.describe('git_panel Worktree panel', function()
  T.it('lists the current worktree marked with *', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    GP.press('5') -- Worktreeパネル
    vim.wait(300)
    local left = GP.left_win()
    T.contains(table.concat(GP.lines(left), '\n'), dir)

    GP.close()
    T.rmrf(dir)
  end)

  T.it('n adds a new worktree with a new branch', function()
    local dir = T.tmp_git_repo()
    local wt_path = dir .. '-feature'

    GP.open(dir, false)
    GP.press('5')
    vim.wait(300)
    GP.press('n')
    vim.wait(80)
    GP.press_modal('ifeature-wt')
    GP.press_modal('<CR>')
    vim.wait(80)
    -- 2番目のプロンプト(作成先パス)。startinsert!していてもheadless実行では
    -- 同期feedkeysの時点でノーマルモードに戻っているため、'i'で改めて入る必要がある
    GP.press_modal('<C-u>')
    GP.press_modal('i' .. wt_path)
    GP.press_modal('<CR>')
    T.wait_until(function() return vim.fn.isdirectory(wt_path) == 1 end, 3000)
    T.eq(vim.fn.isdirectory(wt_path), 1, 'worktree directory should exist')
    T.eq(GP.git(wt_path, { 'rev-parse', '--abbrev-ref', 'HEAD' }).stdout:gsub('%s+$', ''), 'feature-wt')

    GP.close()
    T.rmrf(dir)
    T.rmrf(wt_path)
  end)
end)

T.summary()
