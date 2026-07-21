local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

T.describe('git_panel Files panel', function()
  T.it('renders status codes for modified/staged/untracked/nested files', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      T.write_file(d .. '/sub/b.txt', { 'b' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'modified' }) -- unstaged M
    T.write_file(dir .. '/sub/b.txt', { 'b', 'staged' })
    GP.git(dir, { 'add', 'sub/b.txt' }) -- staged M
    T.write_file(dir .. '/new.txt', { 'new' }) -- untracked

    GP.open(dir, false)
    local left = GP.left_win()
    T.ok(left ~= nil, 'left window should exist')
    local lines = GP.lines(left)
    local text = table.concat(lines, '\n')
    T.contains(text, 'a.txt')
    T.contains(text, 'b.txt')
    T.contains(text, 'new.txt')
    T.contains(text, '??') -- untracked: status_str = node.file.x .. node.file.y = '?'+'?'

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Space toggles staging for a single file', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })

    -- パネル自体の表示内容で完了を判定する(別プロセスのgit statusだけを見て
    -- 次のSpaceを押すと、プラグイン内部のrefreshがまだ終わっていない古い状態を
    -- 読んでしまい2回目の操作が不安定になることがあったため)
    local function row_text()
      return GP.lines(GP.left_win())[GP.find_row(GP.left_win(), 'a.txt')]
    end

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'a.txt')
    T.ok(row ~= nil, 'a.txt should be listed')
    GP.goto_row(left, row)
    GP.press('<Space>')
    T.wait_until(function() return row_text():find('M  ', 1, true) ~= nil end)
    -- パネル(内部でgit statusを取り直した結果)がすでに"M  "を表示していても、
    -- こちらから別途起動するgit statusプロセスがごく短い時間だけ古い結果を
    -- 返すことがあった(gitの起動タイミングによる別プロセス間の見え方のズレ)。
    -- 検証側もpollingにして安定させる
    T.wait_until(function() return GP.status(dir):find('M  a.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), 'M  a.txt') -- staged (index column M, worktree column blank)

    -- 再度Spaceでアンステージに戻ることも確認
    GP.press('<Space>')
    T.wait_until(function() return row_text():find(' M ', 1, true) ~= nil end)
    T.wait_until(function() return GP.status(dir):find(' M a.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), ' M a.txt')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discard menu: "all" fully reverts staged+unstaged, batched (no index.lock race with many files)', function()
    local dir = T.tmp_git_repo(function(d)
      for i = 1, 8 do T.write_file(d .. ('/f%d.txt'):format(i), { 'line' .. i }) end
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    for i = 1, 8 do
      T.write_file(dir .. ('/f%d.txt'):format(i), { 'line' .. i, 'staged' .. i })
    end
    GP.git(dir, { 'add', '.' })
    for i = 1, 8 do
      T.write_file(dir .. ('/f%d.txt'):format(i), { 'line' .. i, 'staged' .. i, 'unstaged' .. i })
    end
    T.eq(#vim.split(vim.trim(GP.status(dir)), '\n'), 8, 'all 8 files should show MM status before discard')

    GP.open(dir, false)
    local left = GP.left_win()
    -- デフォルトでカーソルはルートノード("/")に乗っている -> 配下8ファイル全部が対象
    GP.press('d')
    GP.press_modal('x') -- 「すべての変更を破棄」
    T.wait_until(function() return vim.trim(GP.status(dir)) == '' end, 3000)
    T.eq(vim.trim(GP.status(dir)), '', 'all 8 files should be fully discarded with no leftover status')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discard menu: "unstaged only" keeps staged content, discards only working-tree diff', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'line1', 'STAGED' })
    GP.git(dir, { 'add', '.' })
    T.write_file(dir .. '/a.txt', { 'line1', 'STAGED', 'UNSTAGED' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.press('d')
    GP.press_modal('u') -- 「ステージされていない変更を破棄」
    T.wait_until(function() return GP.status(dir):find('^M ') ~= nil end)
    T.contains(GP.status(dir), 'M  a.txt') -- staged残り、unstagedは消えている
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'line1', 'STAGED' })

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discard: newly added (staged) file is removed from disk entirely', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/new.txt', { 'brand new' })
    GP.git(dir, { 'add', 'new.txt' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.press('d')
    GP.press_modal('x')
    T.wait_until(function() return vim.fn.filereadable(dir .. '/new.txt') == 0 end)
    T.eq(vim.fn.filereadable(dir .. '/new.txt'), 0, 'file should be gone')
    T.eq(vim.trim(GP.status(dir)), '')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discard: purely untracked file is removed via clean', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/scratch.txt', { 'scratch' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.press('d')
    GP.press_modal('x')
    T.wait_until(function() return vim.fn.filereadable(dir .. '/scratch.txt') == 0 end)
    T.eq(vim.fn.filereadable(dir .. '/scratch.txt'), 0)

    GP.close()
    T.rmrf(dir)
  end)

  T.it('untracked file preview shows the whole file as added lines (+prefix)', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/note.txt', { 'hello', 'world' })

    GP.open(dir, false)
    local left, right = GP.left_win(), GP.right_win()
    local row = GP.find_row(left, 'note.txt')
    GP.goto_row(left, row)
    T.wait_until(function() return table.concat(GP.lines(right), '\n'):find('hello') ~= nil end)
    local text = table.concat(GP.lines(right), '\n')
    T.contains(text, '+hello')
    T.contains(text, '+world')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('a: stage-all / unstage-all toggle affects every file at once', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      T.write_file(d .. '/b.txt', { 'b' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'x' })
    T.write_file(dir .. '/b.txt', { 'b', 'x' })

    -- 「refreshが終わって画面に反映された」ことを基準に待つ(別プロセスのgit statusを
    -- 見るだけだと、プラグイン内部のキャッシュ更新との競合で次のaが古い状態を
    -- 読んでしまうことがあるため、パネル自体の表示内容で判定する)
    local function staged_rows()
      local n = 0
      for _, l in ipairs(GP.lines(GP.left_win())) do
        if l:find('M  ', 1, true) then n = n + 1 end -- status_str="M "+区切りの空白
      end
      return n
    end

    GP.open(dir, false)
    GP.press('a')
    T.wait_until(function() return staged_rows() == 2 end, 3000)
    T.eq(staged_rows(), 2, 'both files should be staged')
    T.eq(vim.trim(vim.system({ 'git', '-C', dir, 'diff', '--cached', '--name-only' }, { text = true }):wait().stdout),
      'a.txt\nb.txt')

    GP.press('a')
    T.wait_until(function() return staged_rows() == 0 end, 3000)
    T.eq(staged_rows(), 0, 'both files should be unstaged again')
    -- vim.trim()は文字列全体の前後空白を削るため、1行目の先頭スペース(porcelainの
    -- インデックス欄)まで消えてしまう。末尾の改行だけを落として比較する
    T.eq((GP.status(dir):gsub('\n$', '')), ' M a.txt\n M b.txt')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
