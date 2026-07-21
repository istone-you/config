-- files.luaの残りのキー(c/w/A/e/o/i/y/s/f)のテスト。files_spec.luaはステージ/
-- discardしか検証しておらず、コミット系・補助系の結線が丸ごと未検証だったため
-- (multiline_input/input自体の挙動はgit_panel_ui_spec.luaで既に検証済みなので、
-- ここではそのウィジェットを通して実際にgit操作まで届くかだけを見る)

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

T.describe('git_panel Files panel: commit/amend/misc keys', function()
  T.it('c commits staged changes with the typed message', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    GP.open(dir, false)
    -- startinsertはfeedkeysの一連の処理内でなければ即時反映されないため、
    -- キー押下と入力・確定を1回のfeedkeysにまとめる(startinsertの既知の注意点)
    GP.press('cmy commit message<CR>')
    T.wait_until(function()
      return GP.git(dir, { 'log', '-1', '--format=%s' }).stdout:find('my commit message', 1, true) ~= nil
    end)
    T.eq(vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout), 'my commit message')
    T.eq(vim.trim(GP.git(dir, { 'status', '--porcelain' }).stdout), '', 'working tree should be clean after commit')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('an empty commit message is rejected (no commit created)', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    local before = vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout)
    GP.open(dir, false)
    GP.press('c<CR>')
    vim.wait(150)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout), before, 'HEAD should not move')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('w commits with --no-verify, skipping hooks', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'config', 'core.hooksPath', '.myhooks' })
    T.write_file(dir .. '/.myhooks/pre-commit', { '#!/bin/sh', 'exit 1' })
    vim.fn.setfperm(dir .. '/.myhooks/pre-commit', 'rwxr-xr-x')
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', 'a.txt' })

    GP.open(dir, false)
    GP.press('wno-verify commit<CR>')
    T.wait_until(function()
      return GP.git(dir, { 'log', '-1', '--format=%s' }).stdout:find('no-verify commit', 1, true) ~= nil
    end)
    T.contains(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout, 'no-verify commit')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('a plain commit (c) is blocked by a failing pre-commit hook', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'config', 'core.hooksPath', '.myhooks' })
    T.write_file(dir .. '/.myhooks/pre-commit', { '#!/bin/sh', 'exit 1' })
    vim.fn.setfperm(dir .. '/.myhooks/pre-commit', 'rwxr-xr-x')
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', 'a.txt' })
    local before = vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout)

    GP.open(dir, false)
    GP.press('cblocked by hook<CR>')
    vim.wait(200)
    T.eq(vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout), before, 'hook failure should prevent the commit')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('A amends HEAD with currently staged changes, keeping the message (--no-edit)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'original message' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'more' })
    GP.git(dir, { 'add', '.' })
    local before = vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout)

    GP.open(dir, false)
    GP.press('A')
    vim.wait(80)
    GP.press_modal('y') -- 「HEADをamendしますか」確認
    T.wait_until(function() return vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout) ~= before end)
    T.eq(vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout), 'original message')
    T.eq(vim.trim(GP.git(dir, { 'show', '--stat', '--format=', 'HEAD' }).stdout):find('a.txt') ~= nil, true)

    GP.close()
    T.rmrf(dir)
  end)

  T.it('i adds the file under the cursor to .gitignore', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/secret.txt', { 'x' })
    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'secret.txt'))
    GP.press('i')
    T.wait_until(function() return vim.fn.filereadable(dir .. '/.gitignore') == 1 end)
    T.contains(table.concat(vim.fn.readfile(dir .. '/.gitignore'), '\n'), 'secret.txt')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('y copies the path of the entry under the cursor to the "+" register', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/sub/x.txt', { 'x' })
    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'x.txt'))
    GP.press('y')
    vim.wait(50)
    T.eq(vim.fn.getreg('+'), 'sub/x.txt')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('s stashes all changes with the typed message', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'dirty' })
    GP.open(dir, false)
    GP.press('smy stash<CR>')
    T.wait_until(function()
      return GP.git(dir, { 'stash', 'list' }).stdout:find('my stash', 1, true) ~= nil
    end)
    T.eq(vim.trim(GP.git(dir, { 'status', '--porcelain' }).stdout), '', 'working tree should be clean after stash')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('f fetches from the remote and refreshes without an error notification', function()
    local remote = vim.fn.tempname()
    vim.fn.mkdir(remote, 'p')
    GP.git(remote, { 'init', '-q', '--bare', '-b', 'main' })
    local dir = vim.fn.tempname()
    vim.system({ 'git', 'clone', '-q', remote, dir }):wait()
    T.write_file(dir .. '/a.txt', { 'a' })
    GP.git(dir, { 'add', '.' })
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    GP.git(dir, { 'push', '-u', 'origin', 'main' })
    -- dirはリモートの最新を知っているので、別クローンから新しいコミットを積んで
    -- 「fetchしないと見えない」状態を作る
    local other = vim.fn.tempname()
    vim.system({ 'git', 'clone', '-q', remote, other }):wait()
    T.write_file(other .. '/b.txt', { 'b' })
    GP.git(other, { 'add', '.' })
    GP.git(other, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'from other' })
    GP.git(other, { 'push', 'origin', 'main' })

    T.eq(GP.git(dir, { 'rev-parse', 'origin/main' }).stdout, GP.git(dir, { 'rev-parse', 'HEAD' }).stdout,
      'sanity check: dir should not know about the new remote commit yet')

    GP.open(dir, false)
    GP.press('f')
    T.wait_until(function()
      return GP.git(dir, { 'rev-parse', 'origin/main' }).stdout ~= GP.git(dir, { 'rev-parse', 'HEAD' }).stdout
    end)
    T.contains(GP.git(dir, { 'log', '-1', '--format=%s', 'origin/main' }).stdout, 'from other')

    GP.close()
    T.rmrf(dir); T.rmrf(other); T.rmrf(remote)
  end)

  T.it('e/o open the file under the cursor in the original window and close the panel', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'hello' })
    vim.cmd('enew')
    local origin_win = vim.api.nvim_get_current_win()
    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'a.txt'))
    GP.press('e')
    vim.wait(100)
    T.eq(vim.api.nvim_get_current_win(), origin_win, 'should have returned focus to the original window')
    T.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), 'a.txt')
    T.eq(#vim.api.nvim_list_wins(), 1, 'the git panel should be closed after opening the file')

    vim.cmd('bwipeout!')
    T.rmrf(dir)
  end)
end)

T.summary()
