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

  T.it('a directory node shows a combined git diff of everything under it (lazygit files_controller.go GetOnRenderToMain), not a "N files" placeholder', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/sub/a.txt', { 'a' })
      T.write_file(d .. '/sub/b.txt', { 'b' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/sub/a.txt', { 'a', 'CHANGED' })
    T.write_file(dir .. '/sub/b.txt', { 'b', 'CHANGED2' })

    GP.open(dir, false)
    local left, right = GP.left_win(), GP.right_win()
    local row = GP.find_row(left, 'sub')
    T.ok(row ~= nil, 'sub directory should be listed')
    GP.goto_row(left, row)
    T.wait_until(function() return table.concat(GP.lines(right), '\n'):find('CHANGED2', 1, true) ~= nil end)
    local text = table.concat(GP.lines(right), '\n')
    T.contains(text, 'a.txt')
    T.contains(text, 'b.txt')
    T.contains(text, 'CHANGED')
    T.contains(text, 'CHANGED2')
    T.ok(not text:find('個のファイル', 1, true), 'should not show the old "N files" placeholder')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('uses the same tree fold arrows as explorer for directory nodes', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/sub/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/sub/a.txt', { 'a', 'CHANGED' })

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'sub')
    T.ok(row ~= nil, 'sub directory should be listed')
    T.contains(GP.lines(left)[row], '')
    T.contains(GP.lines(left)[row], '')
    local arrow_hl = vim.api.nvim_get_hl(0, { name = 'GitPanelTreeArrow', link = false })
    T.eq(arrow_hl.fg, tonumber('626262', 16), 'tree arrow color should match explorer')

    GP.goto_row(left, row)
    GP.press('<CR>')
    vim.wait(80)
    row = GP.find_row(left, 'sub')
    T.contains(GP.lines(left)[row], '')
    T.ok(not GP.lines(left)[row]:find('', 1, true), 'closed dir should not use the open folder icon')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('compresses a chain of single-directory-child dirs into one "a/b/c" line (lazygit filetree/node.go compressAux)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a/b/c/deep.txt', { 'x' })
      T.write_file(d .. '/onlyfile/single.txt', { 'y' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a/b/c/deep.txt', { 'x', 'CHANGED' })
    T.write_file(dir .. '/onlyfile/single.txt', { 'y', 'CHANGED' })

    GP.open(dir, false)
    local text = table.concat(GP.lines(GP.left_win()), '\n')
    T.contains(text, 'a/b/c', 'a 3-level chain of single-dir-child directories should collapse to one line')
    T.ok(not text:find('  a\n', 1, true), 'the intermediate "a" segment should not appear on its own line')
    -- ディレクトリの唯一の子がファイルの場合は連結しない(onlyfileはsingle.txtだけ
    -- 持つが、子がファイルなので"onlyfile/single.txt"には潰れず2行のまま)
    T.contains(text, 'onlyfile')
    T.contains(text, 'single.txt')
    T.ok(not text:find('onlyfile/single.txt', 1, true), 'a directory whose sole child is a FILE must not compress')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('a directory with two changed children does not compress (only single-child chains do)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/hoge/fuga/a.txt', { 'a' })
      T.write_file(d .. '/hoge/piyo/b.txt', { 'b' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    -- fugaだけ変更 -> hogeの子はfugaだけ(piyoは無変更で木に出てこない) -> 圧縮される
    T.write_file(dir .. '/hoge/fuga/a.txt', { 'a', 'CHANGED' })
    GP.open(dir, false)
    T.contains(table.concat(GP.lines(GP.left_win()), '\n'), 'hoge/fuga')
    GP.close()

    -- 続けてpiyoも変更 -> hogeの子がfuga+piyoの2つになる -> 圧縮されない
    T.write_file(dir .. '/hoge/piyo/b.txt', { 'b', 'CHANGED' })
    GP.open(dir, false)
    local text = table.concat(GP.lines(GP.left_win()), '\n')
    T.ok(not text:find('hoge/fuga', 1, true), 'hoge should stop compressing once it has 2 changed children')
    T.contains(text, 'hoge')
    T.contains(text, 'fuga')
    T.contains(text, 'piyo')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('does not crash on a nested git repo reported by git as a single "dir/" untracked entry', function()
    -- gitはネストしたgitリポジトリ(.gitを含む未追跡ディレクトリ)を展開せず
    -- "?? dir/"の1行で返す。末尾の"/"が名前抽出に失敗してクラッシュしていた回帰テスト
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'init', '-q', 'nestedrepo' })
    T.write_file(dir .. '/nestedrepo/x.txt', { 'x' })

    GP.open(dir, false)
    local left = GP.left_win()
    T.ok(left ~= nil, 'panel should open without crashing')
    T.contains(table.concat(GP.lines(left), '\n'), 'nestedrepo')

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

  T.it('handles quoted paths (spaces/special chars) via -z, not the human-readable quoted porcelain text', function()
    -- 回帰テスト: -z無しの--porcelain=v1はスペースを含むパスを`"a b.txt"`のように
    -- ダブルクォートで返し、内部pathがクォート付きのまま残ると
    -- previewが空になりSpaceでのstageも `pathspec '"a b.txt"' did not match` で失敗していた
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a b.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a b.txt', { 'a', 'changed' })

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'a b.txt')
    T.ok(row ~= nil, '"a b.txt" should be listed')
    GP.goto_row(left, row)
    vim.wait(50)
    local diff_text = table.concat(GP.lines(GP.right_win()), '\n')
    T.contains(diff_text, 'changed', 'preview should show the real diff, not be empty')

    GP.press('<Space>')
    T.wait_until(function() return GP.status(dir):find('M  "?a b%.txt"?', 1) ~= nil end)
    T.contains(GP.status(dir), 'a b.txt', 'staging a space-containing path should succeed, not fail with a pathspec error')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discarding a staged rename restores the original file and removes the new one', function()
    -- 回帰テスト: 旧実装はrename行の旧パスを捨てており、discard allしても
    -- 実際には D old.txt / ?? new.txt が残る不完全な破棄になっていた
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/old.txt', { 'original content' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    vim.uv.fs_rename(dir .. '/old.txt', dir .. '/new.txt')
    GP.git(dir, { 'add', '-A' })
    T.contains(GP.status(dir), 'R  old.txt -> new.txt', 'sanity check: git should detect this as a rename')

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'new.txt')
    T.ok(row ~= nil, 'the renamed file should be listed under its new name')
    GP.goto_row(left, row)
    GP.press('d')
    GP.press_modal('x') -- 「すべての変更を破棄」
    T.wait_until(function() return vim.trim(GP.status(dir)) == '' end, 3000)

    T.eq(vim.trim(GP.status(dir)), '', 'no leftover status (not "D old.txt" / "?? new.txt")')
    T.eq(vim.fn.filereadable(dir .. '/old.txt'), 1, 'old.txt should be restored')
    T.eq(vim.fn.filereadable(dir .. '/new.txt'), 0, 'new.txt should be gone')
    T.eq(vim.fn.readfile(dir .. '/old.txt'), { 'original content' })

    GP.close()
    T.rmrf(dir)
  end)

  T.it('discarding a nested git repo shown as a single untracked "dir/" entry removes it entirely', function()
    -- 回帰テスト: remove_from_diskがvim.fn.delete()を非再帰(flags無し)で呼んでおり、
    -- 非空ディレクトリ(nested git repo等)を削除できず残ってしまっていた
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'init', '-q', 'nestedrepo' })
    T.write_file(dir .. '/nestedrepo/x.txt', { 'x' })
    T.contains(GP.status(dir), '?? nestedrepo/')

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'nestedrepo')
    T.ok(row ~= nil)
    GP.goto_row(left, row)
    GP.press('d')
    GP.press_modal('x') -- 未追跡のみなのでメニューの選択肢は「すべての変更を破棄」1つだけ
    T.wait_until(function() return vim.fn.isdirectory(dir .. '/nestedrepo') == 0 end, 3000)
    T.eq(vim.fn.isdirectory(dir .. '/nestedrepo'), 0, 'the nested repo directory should be fully removed')

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

  T.it('Space on / stages the other files even when a staged deletion is present (lazygit toggleStaged: stage only unstaged nodes; `git add` on a deleted path would otherwise abort the whole batch)', function()
    -- 回帰テスト: 以前は配下の全パスをまとめて`git add -- <all>`していたため、
    -- ステージ済み削除(working treeに存在しない)が1つでも混ざると
    -- `fatal: pathspec did not match any files`でコマンド全体が失敗し、
    -- 他のファイルも一切ステージされなかった
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/gone.txt', { 'x' })
      T.write_file(d .. '/keep.txt', { 'y' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    GP.git(dir, { 'rm', 'gone.txt' })                     -- staged deletion: 'D '
    T.write_file(dir .. '/keep.txt', { 'y', 'changed' })  -- unstaged modify: ' M'

    GP.open(dir, false)
    -- デフォルトでカーソルはルート"/"に乗っている -> 配下(gone.txt/keep.txt)全部が対象
    GP.press('<Space>')
    T.wait_until(function() return GP.status(dir):find('M  keep.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), 'M  keep.txt', 'the modified file must get staged despite the deleted sibling')
    T.contains(GP.status(dir), 'D  gone.txt', 'the already-staged deletion stays staged, untouched')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Space on a directory unstages everything under it INCLUDING a staged deletion (lazygit pressWithLock: unstage a dir via `git reset HEAD -- <dir>`, not by enumerating displayed rows)', function()
    -- 回帰テスト: 以前は表示ツリーのファイル行を列挙して個別にreset/rmしていたため、
    -- 何らかの理由でツリーに出ていないステージ済み削除が取りこぼされ
    -- 「親ディレクトリをSpaceしてもDだけアンステージされない」状態になっていた。
    -- ディレクトリはパスごとgit reset に渡し、配下の再帰をgitに任せることで確実に外す
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/sub/gone.txt', { 'x' })
      T.write_file(d .. '/sub/keep.txt', { 'y' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    GP.git(dir, { 'rm', 'sub/gone.txt' })                 -- staged deletion: 'D '
    T.write_file(dir .. '/sub/keep.txt', { 'y', 'ch' })
    GP.git(dir, { 'add', 'sub/keep.txt' })                -- staged modify: 'M '
    -- sanity: すべてステージ済み
    T.contains(GP.status(dir), 'D  sub/gone.txt')
    T.contains(GP.status(dir), 'M  sub/keep.txt')

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'sub')
    T.ok(row ~= nil, 'the sub directory should be listed')
    GP.goto_row(left, row)
    GP.press('<Space>') -- unstage all under sub/
    T.wait_until(function() return GP.status(dir):find(' D sub/gone.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), ' D sub/gone.txt', 'the staged deletion must be unstaged too, not left staged')
    T.contains(GP.status(dir), ' M sub/keep.txt', 'the staged modification is unstaged as well')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Space toggles a deleted file between staged (D ) and unstaged ( D)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/gone.txt', { 'x' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    GP.git(dir, { 'rm', 'gone.txt' }) -- 'D '
    T.contains(GP.status(dir), 'D  gone.txt')

    GP.open(dir, false)
    local left = GP.left_win()
    local row = GP.find_row(left, 'gone.txt')
    T.ok(row ~= nil, 'the deleted file should be listed')
    GP.goto_row(left, row)
    GP.press('<Space>') -- unstage: git reset HEAD -- gone.txt -> ' D'
    T.wait_until(function() return GP.status(dir):find(' D gone.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), ' D gone.txt')

    -- 内部refreshが済んでカーソルがgone.txtに乗り直すのを待ってから2回目を押す
    vim.wait(200)
    GP.press('<Space>') -- re-stage: 素の`git add -- gone.txt`(未ステージ削除にはマッチする)
    T.wait_until(function() return GP.status(dir):find('D  gone.txt', 1, true) ~= nil end)
    T.contains(GP.status(dir), 'D  gone.txt')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Tab multi-select: Space stages all selected files', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      T.write_file(d .. '/b.txt', { 'b' })
      T.write_file(d .. '/c.txt', { 'c' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })
    T.write_file(dir .. '/b.txt', { 'b', 'changed' })
    T.write_file(dir .. '/c.txt', { 'c', 'changed' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'a.txt'))
    GP.press('<Tab>') -- select a.txt, move down
    GP.goto_row(left, GP.find_row(left, 'b.txt'))
    GP.press('<Tab>') -- select b.txt (c.txt stays unselected)
    GP.press('<Space>')
    T.wait_until(function()
      local s = GP.status(dir)
      return s:find('M  a.txt', 1, true) ~= nil and s:find('M  b.txt', 1, true) ~= nil
    end)
    local s = GP.status(dir)
    T.contains(s, 'M  a.txt')
    T.contains(s, 'M  b.txt')
    T.contains(s, ' M c.txt', 'unselected c.txt should remain unstaged')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Tab multi-select: d discards all selected files', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      T.write_file(d .. '/b.txt', { 'b' })
      T.write_file(d .. '/c.txt', { 'c' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })
    T.write_file(dir .. '/b.txt', { 'b', 'changed' })
    T.write_file(dir .. '/c.txt', { 'c', 'changed' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'a.txt'))
    GP.press('<Tab>')
    GP.goto_row(left, GP.find_row(left, 'b.txt'))
    GP.press('<Tab>')
    GP.press('d')
    GP.press_modal('x')
    T.wait_until(function()
      local s = GP.status(dir)
      return s:find('a.txt', 1, true) == nil and s:find('b.txt', 1, true) == nil
        and s:find(' M c.txt', 1, true) ~= nil
    end)
    local s = GP.status(dir)
    T.ok(s:find('a.txt', 1, true) == nil, 'a.txt should be discarded')
    T.ok(s:find('b.txt', 1, true) == nil, 'b.txt should be discarded')
    T.contains(s, ' M c.txt', 'unselected c.txt should remain modified')

    GP.close()
    T.rmrf(dir)
  end)

  T.it('Esc clears multi-select first, then closes the panel', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'a' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })

    GP.open(dir, false)
    local left = GP.left_win()
    GP.goto_row(left, GP.find_row(left, 'a.txt'))
    GP.press('<Tab>')
    GP.press('<Esc>')
    T.ok(GP.left_win() ~= nil and vim.api.nvim_win_is_valid(GP.left_win()),
      'first Esc should clear selection without closing')
    GP.press('<Esc>')
    T.ok(GP.left_win() == nil or not vim.api.nvim_win_is_valid(GP.left_win()),
      'second Esc should close the panel')

    T.rmrf(dir)
  end)
end)

T.summary()
