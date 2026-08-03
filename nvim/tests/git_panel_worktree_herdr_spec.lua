-- worktree.luaのherdr連携(w): カーソル行のworktreeをherdrワークスペースとして開く。
-- 実際のherdrは起動せず、判定(_has_herdr)と実行(_run_herdr)を差し替えて引数だけ検証する。

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local WT = require('config.git_panel.worktree')

-- 各テストの前後で必ず元へ戻すため、オリジナルを退避しておく
local orig_has, orig_run = WT._has_herdr, WT._run_herdr

local function restore()
  WT._has_herdr, WT._run_herdr = orig_has, orig_run
end

T.describe('git_panel Worktree panel: herdr workspace (w)', function()
  T.it('w on a worktree confirms then runs `herdr workspace create --cwd <path> --label <branch>`', function()
    local dir = T.tmp_git_repo()
    local wt_path = vim.fn.tempname()
    GP.git(dir, { 'worktree', 'add', '-q', '-b', 'wt-branch', wt_path })

    local captured = nil
    WT._has_herdr = function() return true end
    WT._run_herdr = function(hargs, cb)
      captured = hargs
      cb({ code = 0, stdout = '', stderr = '' })
    end

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.find_row(GP.left_win(), 'wt-branch') ~= nil end, 3000)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'wt-branch'))
    GP.press('w')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    T.contains(table.concat(GP.lines(vim.api.nvim_get_current_win()), '\n'), 'herdr')
    GP.press_modal('y')
    T.wait_until(function() return captured ~= nil end, 2000)

    T.eq(captured[1], 'workspace')
    T.eq(captured[2], 'create')
    -- --cwd <path> がカーソル行のworktreeを指す（symlink差を吸収してから比較）
    local cwd_idx
    for i, a in ipairs(captured) do if a == '--cwd' then cwd_idx = i end end
    T.ok(cwd_idx ~= nil, '--cwd should be present')
    T.eq(vim.fn.resolve(captured[cwd_idx + 1]), vim.fn.resolve(wt_path))
    -- --label <branch> がブランチ名
    local label_idx
    for i, a in ipairs(captured) do if a == '--label' then label_idx = i end end
    T.ok(label_idx ~= nil, '--label should be present')
    T.eq(captured[label_idx + 1], 'wt-branch')

    restore()
    GP.close()
    T.rmrf(dir); T.rmrf(wt_path)
  end)

  T.it('w does nothing (no herdr call) when the confirmation is declined', function()
    local dir = T.tmp_git_repo()
    local wt_path = vim.fn.tempname()
    GP.git(dir, { 'worktree', 'add', '-q', '-b', 'wt-cancel', wt_path })

    local called = false
    WT._has_herdr = function() return true end
    WT._run_herdr = function(_, _) called = true end

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.find_row(GP.left_win(), 'wt-cancel') ~= nil end, 3000)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'wt-cancel'))
    GP.press('w')
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 2000)
    GP.press_modal('n')
    T.wait_until(function() return GP.win_by_title('確認') == nil end, 2000)
    vim.wait(100)
    T.ok(not called, 'declining should not invoke herdr')

    restore()
    GP.close()
    T.rmrf(dir); T.rmrf(wt_path)
  end)

  T.it('w warns and does not run herdr when herdr is unavailable', function()
    local dir = T.tmp_git_repo()
    local wt_path = vim.fn.tempname()
    GP.git(dir, { 'worktree', 'add', '-q', '-b', 'wt-nohardr', wt_path })

    local called = false
    WT._has_herdr = function() return false end
    WT._run_herdr = function(_, _) called = true end

    GP.open(dir, false)
    GP.press('5')
    T.wait_until(function() return GP.find_row(GP.left_win(), 'wt-nohardr') ~= nil end, 3000)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'wt-nohardr'))
    GP.press('w')
    -- herdrが無いので確認モーダルは開かず、そのまま何も起きない
    vim.wait(200)
    T.ok(GP.win_by_title('確認') == nil, 'no confirmation should appear')
    T.ok(not called, 'herdr should not be invoked when unavailable')

    restore()
    GP.close()
    T.rmrf(dir); T.rmrf(wt_path)
  end)
end)

T.summary()
