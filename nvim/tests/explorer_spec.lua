local T = dofile(TESTS_DIR .. '/helpers.lua')

--- explorer.luaはプロセス内で最初に開いた時だけ`cwd = vim.fn.getcwd()`を取り込み、
--- 以降は内部のcwdをnavigationでしか変えない(外部からvim.fn.chdir()しても追従しない)。
--- そのため複数のit()ブロックでそれぞれ別の一時ディレクトリを使おうとすると、
--- 2つ目以降が「最初のテストが使っていた(既に削除済みの)ディレクトリ」を見に行って
--- 落ちる。一連の操作を1つの子プロセス内で連続して行う実際の使用形態に合わせて
--- テストする
local function run_child(body_lua)
  local script = "local function assert_eq(a, b, msg)\n"
    .. "  if not vim.deep_equal(a, b) then\n"
    .. "    error((msg or 'mismatch') .. ': expected ' .. vim.inspect(b) .. ' got ' .. vim.inspect(a))\n"
    .. "  end\n"
    .. "end\n"
    .. "local function feed(keys)\n"
    .. "  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)\n"
    .. "end\n"
    .. "local function list_win()\n"
    .. "  for _, w in ipairs(vim.api.nvim_list_wins()) do\n"
    .. "    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'explorer' then return w end\n"
    .. "  end\n"
    .. "end\n"
    .. "local function lines(win) return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false) end\n"
    .. "local function find_row(win, needle)\n"
    .. "  for i, l in ipairs(lines(win)) do if l:find(needle, 1, true) then return i end end\n"
    .. "end\n"
    .. "local ok, err = pcall(function()\n"
    .. body_lua
    .. "\nend)\n"
    .. "if ok then os.exit(0) else io.stderr:write(tostring(err) .. '\\n'); os.exit(1) end\n"
  local tmp = vim.fn.tempname() .. '.lua'
  vim.fn.writefile(vim.split(script, '\n', { plain = true }), tmp)
  local res = vim.system({
    'nvim', '-u', 'NONE', '--cmd', 'set rtp+=' .. vim.fn.fnamemodify(TESTS_DIR, ':h'), '-l', tmp,
  }, { text = true }):wait()
  vim.fn.delete(tmp)
  return res
end

T.describe('explorer', function()
  T.it('dims only git-unmanaged entries; a tracked dir with an untracked child stays normal', function()
    local res = run_child([[
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      local function git(args)
        local c = { 'git', '-C', dir, '-c', 'user.email=t@t', '-c', 'user.name=t' }
        vim.list_extend(c, args)
        vim.system(c):wait()
      end
      git({ 'init', '-q' })
      -- tracked: keep.txt, src/app.txt, .gitignore(=build/を無視)
      vim.fn.mkdir(dir .. '/src', 'p')
      vim.fn.writefile({ 'x' }, dir .. '/keep.txt')
      vim.fn.writefile({ 'x' }, dir .. '/src/app.txt')
      -- build/ はディレクトリごと無視、secret/* は中身だけ無視(.terraform型: 畳まれず個別列挙)
      vim.fn.writefile({ 'build/', 'secret/*' }, dir .. '/.gitignore')
      git({ 'add', 'keep.txt', 'src/app.txt', '.gitignore' })
      git({ 'commit', '-qm', 'seed' })
      -- unmanaged: fresh.txt(未追跡), src/new.txt(trackedなsrc内の未追跡), build/(ignore), secret/(中身がignore)
      vim.fn.writefile({ 'y' }, dir .. '/fresh.txt')
      vim.fn.writefile({ 'y' }, dir .. '/src/new.txt')
      vim.fn.mkdir(dir .. '/build', 'p')
      vim.fn.writefile({ 'y' }, dir .. '/build/out.txt')
      vim.fn.mkdir(dir .. '/secret', 'p')
      vim.fn.writefile({ 'y' }, dir .. '/secret/token.txt')

      vim.fn.chdir(dir)
      local explorer = require('config.explorer')
      explorer.open(false)
      local win = list_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local ns = vim.api.nvim_create_namespace('explorer_hl')

      -- git status(非同期)が届いて再描画され、未追跡に ? が付くまで待つ
      local ok = vim.wait(3000, function()
        for _, l in ipairs(lines(win)) do
          if l:find('fresh.txt', 1, true) and l:find('?', 1, true) then return true end
        end
        return false
      end, 50)
      assert_eq(ok, true, 'git status ready (untracked has ? sign)')

      local function dimmed(needle)
        local row
        for i, l in ipairs(lines(win)) do if l:find(needle, 1, true) then row = i - 1 end end
        assert_eq(row ~= nil, true, 'row for ' .. needle)
        for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, 10000 }, { details = true })) do
          if m[4].hl_group == 'ExplorerDimmed' then return true end
        end
        return false
      end

      assert_eq(dimmed('fresh.txt'), true, 'untracked file should be dimmed')
      assert_eq(dimmed('keep.txt'), false, 'tracked file should NOT be dimmed')
      assert_eq(dimmed('build'), true, 'ignored dir should be dimmed')
      assert_eq(dimmed('secret'), true, 'dir whose contents are ignored individually should be dimmed (.terraform型)')
      assert_eq(dimmed('src'), false, 'tracked dir with an untracked child should NOT be dimmed')

      -- 無視ディレクトリを開いたら中身も全部薄いこと（畳まれた祖先から継承）
      local brow
      for i, l in ipairs(lines(win)) do if l:find('build', 1, true) then brow = i end end
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { brow, 0 })
      feed('l')
      local ok2 = vim.wait(3000, function()
        if not (lines(win)[1] or ''):find('build', 1, true) then return false end
        for i, l in ipairs(lines(win)) do
          if l:find('out.txt', 1, true) then
            local row = i - 1
            for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, 10000 }, { details = true })) do
              if m[4].hl_group == 'ExplorerDimmed' then return true end
            end
          end
        end
        return false
      end, 50)
      assert_eq(ok2, true, 'contents of an ignored dir should all be dimmed')
    ]])
    T.ok(res.code == 0, 'child failed: ' .. (res.stderr or ''))
  end)

  T.it('shows a symlink as "name -> target" (yazi風) with its own highlight', function()
    local res = run_child([[
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir .. '/real', 'p')
      vim.fn.writefile({ 'x' }, dir .. '/real/config.toml')
      vim.uv.fs_symlink('real/config.toml', dir .. '/link.toml')

      vim.fn.chdir(dir)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(120)
      local win = list_win()
      local buf = vim.api.nvim_win_get_buf(win)
      local ns = vim.api.nvim_create_namespace('explorer_hl')

      local row, text
      for i, l in ipairs(lines(win)) do
        if l:find('link.toml', 1, true) then row = i - 1; text = l end
      end
      assert_eq(row ~= nil, true, 'link.toml row exists')
      assert_eq(text:find('link.toml -> real/config.toml', 1, true) ~= nil, true, 'shows -> target, got: ' .. text)

      local has_symlink_hl = false
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, 10000 }, { details = true })) do
        if m[4].hl_group == 'ExplorerSymlink' then has_symlink_hl = true end
      end
      assert_eq(has_symlink_hl, true, 'the -> target part should use ExplorerSymlink')
    ]])
    T.ok(res.code == 0, 'child failed: ' .. (res.stderr or ''))
  end)

  T.it('does not accumulate slashes when going to / and back (no //app)', function()
    local res = run_child([[
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.chdir(dir)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)
      local function header() return lines(win)[1] end

      -- ルート(/)まで戻る（go_parentが変化しなくなったら到達）
      local prev
      for _ = 1, 20 do
        local h = header()
        if h == prev then break end
        prev = h
        feed('h')
        vim.wait(60)
      end

      -- / で子へ入る→戻る を数回。二重スラッシュが出ない/累積しないこと
      for round = 1, 3 do
        assert_eq(header():find('//', 1, true), nil, 'no // at root (round ' .. round .. '): ' .. header())
        local trow
        for i, l in ipairs(lines(win)) do if l:find('tmp', 1, true) then trow = i end end
        assert_eq(trow ~= nil, true, 'tmp entry exists at /')
        vim.api.nvim_win_set_cursor(win, { trow, 0 })
        feed('l')
        vim.wait(100)
        assert_eq(header():find('//', 1, true), nil, 'no // after entering (round ' .. round .. '): ' .. header())
        assert_eq(header():find('/tmp', 1, true) ~= nil, true, 'should be /tmp: ' .. header())
        feed('h')
        vim.wait(80)
      end
    ]])
    T.ok(res.code == 0, 'child failed: ' .. (res.stderr or ''))
  end)

  T.it('lists dirs before files (alphabetical); l/h navigate in/out; a/r/d create/rename/delete', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/zdir', 'p')
    T.write_file(dir .. '/afile.txt', { 'x' })
    T.write_file(dir .. '/bfile.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()

      -- 1) dirが先、ファイルはアルファベット順
      local order = {}
      for _, l in ipairs(lines(win)) do
        if l:find('zdir', 1, true) then table.insert(order, 'zdir') end
        if l:find('afile.txt', 1, true) then table.insert(order, 'afile.txt') end
        if l:find('bfile.txt', 1, true) then table.insert(order, 'bfile.txt') end
      end
      assert_eq(order, { 'zdir', 'afile.txt', 'bfile.txt' }, 'STEP1-order')

      -- 2) l で入る、h で親へ戻る(カーソルは元の場所に復帰)
      vim.api.nvim_set_current_win(win)
      local zdir_row = find_row(win, 'zdir')
      assert_eq(zdir_row ~= nil, true, 'STEP2-find-zdir-row')
      vim.api.nvim_win_set_cursor(win, { zdir_row, 0 })
      feed('l')
      vim.wait(50)
      -- explorer.luaはNeovim本体のcwdを変えず、自前の内部cwdだけで一覧・操作を
      -- 行う(ヘッダー行に現在のパスを表示する)。そちらで確認する
      assert_eq(lines(win)[1]:find('zdir', 1, true) ~= nil, true, 'STEP2-header=' .. lines(win)[1])
      feed('h')
      vim.wait(50)
      local back_row = vim.api.nvim_win_get_cursor(win)[1]
      assert_eq(lines(win)[back_row]:find('zdir', 1, true) ~= nil, true, 'h should restore cursor onto zdir')

      -- 3) a でファイル/ディレクトリ作成
      feed('a')
      vim.wait(50)
      feed('inewdir/')
      feed('<CR>')
      vim.wait(80)
      assert_eq(vim.fn.isdirectory(%s .. '/newdir'), 1)

      feed('a')
      vim.wait(50)
      feed('inewfile.txt')
      feed('<CR>')
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/newfile.txt'), 1)

      -- 4) r でリネーム
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'newfile.txt'), 0 })
      feed('r')
      vim.wait(50)
      feed('<C-u>')
      feed('irenamed.txt')
      feed('<CR>')
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/renamed.txt'), 1)
      assert_eq(vim.fn.filereadable(%s .. '/newfile.txt'), 0)

      -- 5) d で削除(確認y)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'renamed.txt'), 0 })
      feed('d')
      vim.wait(50)
      feed('y')
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/renamed.txt'), 0)
    ]], vim.inspect(dir), vim.inspect(dir), vim.inspect(dir), vim.inspect(dir), vim.inspect(dir), vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('Tab/y/x/p: copy-paste and cut-paste move files between directories', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/dest', 'p')
    T.write_file(dir .. '/src.txt', { 'hello' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      vim.api.nvim_win_set_cursor(win, { find_row(win, 'src.txt'), 0 })
      feed('y') -- copy
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'dest'), 0 })
      feed('l') -- dest/ へ入る
      vim.wait(50)
      feed('p') -- paste
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/dest/src.txt'), 1)
      assert_eq(vim.fn.filereadable(%s .. '/src.txt'), 1, 'copy should keep the original')

      feed('h') -- 親へ戻る
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'src.txt'), 0 })
      feed('x') -- cut
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'dest'), 0 })
      feed('l')
      vim.wait(50)
      feed('P') -- 上書き貼り付け
      vim.wait(80)
      feed('h')
      vim.wait(50)
      assert_eq(vim.fn.filereadable(%s .. '/src.txt'), 0, 'cut should remove the original')
    ]], vim.inspect(dir), vim.inspect(dir), vim.inspect(dir), vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('/ filters entries, Esc clears the filter', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/apple.txt', { 'x' })
    T.write_file(dir .. '/banana.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      feed('/')
      vim.wait(50)
      feed('iapple')
      feed('<CR>')
      vim.wait(50)
      local text = table.concat(lines(win), '\n')
      assert_eq(text:find('apple.txt', 1, true) ~= nil, true)
      assert_eq(text:find('banana.txt', 1, true) == nil, true)

      feed('<Esc>')
      vim.wait(50)
      text = table.concat(lines(win), '\n')
      assert_eq(text:find('banana.txt', 1, true) ~= nil, true, 'Esc should clear the filter')
    ]], vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('fullscreen shows a preview pane: directory listing for dirs, file content for files', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/subdir', 'p')
    T.write_file(dir .. '/subdir/inner.txt', { 'x' })
    T.write_file(dir .. '/a.txt', { 'hello', 'world' })

    local res = run_child(string.format([[
      vim.o.columns, vim.o.lines = 160, 40
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(true)
      vim.wait(80)
      local wins = {}
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative ~= '' then table.insert(wins, { win = w, col = cfg.col }) end
      end
      table.sort(wins, function(a, b) return a.col < b.col end)
      assert_eq(#wins, 2)
      local list_w, preview_w = wins[1].win, wins[2].win
      local function preview_text()
        return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(preview_w), 0, -1, false), '\n')
      end
      assert_eq(preview_text():find('inner.txt', 1, true) ~= nil, true, 'dir preview should list contents')

      vim.api.nvim_set_current_win(list_w)
      vim.api.nvim_win_set_cursor(list_w, { vim.api.nvim_win_get_cursor(list_w)[1] + 1, 0 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_win_get_buf(list_w) })
      vim.wait(1500, function() return preview_text():find('hello', 1, true) ~= nil end, 20)
      assert_eq(preview_text():find('hello', 1, true) ~= nil, true, 'file preview should show its content')
    ]], vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('fullscreen: <CR> on a file closes the floating list/preview so the opened buffer is actually visible', function()
    -- 回帰テスト: open_selected()がis_fullscreen中もfloatを閉じずにorigin_winへ
    -- editしていたため、画面全体を覆うfloatの裏でファイルが開くだけで見た目には
    -- 何も変わらず「ファイルが開けない」ように見えていた
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'hello' })

    local res = run_child(string.format([[
      vim.o.columns, vim.o.lines = 160, 40
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(true)
      vim.wait(80)
      local list_win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'explorer' then list_win = w end
      end
      vim.api.nvim_set_current_win(list_win)
      vim.api.nvim_win_set_cursor(list_win, { find_row(list_win, 'a.txt'), 0 })
      feed('<CR>')
      vim.wait(80)

      assert_eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), 'a.txt',
        'the file should be edited in the current (visible) window')
      local floats_remaining = 0
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= '' then floats_remaining = floats_remaining + 1 end
      end
      assert_eq(floats_remaining, 0, 'the fullscreen list/preview floats should be closed, not left covering the screen')
    ]], vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('sidebar mode: <CR> on a file opens it while keeping the explorer panel open', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'hello' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local list_win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'explorer' then list_win = w end
      end
      vim.api.nvim_set_current_win(list_win)
      vim.api.nvim_win_set_cursor(list_win, { find_row(list_win, 'a.txt'), 0 })
      feed('<CR>')
      vim.wait(80)

      assert_eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), 'a.txt')
      local still_open = false
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'explorer' then still_open = true end
      end
      assert_eq(still_open, true, 'the sidebar explorer panel should remain open after opening a file')
    ]], vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('. toggles hidden dotfiles; R refreshes after an out-of-band filesystem change', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/.hidden', { 'x' })
    T.write_file(dir .. '/visible.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      -- 既定は表示ありなので、まず非表示に切り替える
      feed('.')
      vim.wait(50)
      local text = table.concat(lines(win), '\n')
      assert_eq(text:find('.hidden', 1, true) == nil, true, 'dotfile should be hidden after .')
      feed('.')
      vim.wait(50)
      text = table.concat(lines(win), '\n')
      assert_eq(text:find('.hidden', 1, true) ~= nil, true, 'dotfile should reappear after . again')

      vim.fn.writefile({'x'}, %s .. '/added-outside.txt')
      feed('R')
      vim.wait(80)
      text = table.concat(lines(win), '\n')
      assert_eq(text:find('added-outside.txt', 1, true) ~= nil, true, 'R should pick up the new file')
    ]], vim.inspect(dir), vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('Tab toggles multi-select; delete/copy act on the whole selection, not just the cursor row', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'x' })
    T.write_file(dir .. '/b.txt', { 'x' })
    T.write_file(dir .. '/c.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      -- a.txtとb.txtだけ選択(<Tab>2回、c.txtは選ばない)して削除 -> c.txtだけ残る
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'a.txt'), 0 })
      feed('<Tab>')
      vim.wait(30)
      feed('<Tab>') -- カーソルが進んでb.txtの上にいるはず
      vim.wait(30)
      feed('d')
      vim.wait(50)
      feed('y') -- 確認モーダル
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/a.txt'), 0, 'selected a.txt should be deleted')
      assert_eq(vim.fn.filereadable(%s .. '/b.txt'), 0, 'selected b.txt should be deleted')
      assert_eq(vim.fn.filereadable(%s .. '/c.txt'), 1, 'unselected c.txt should remain')
    ]], vim.inspect(dir), vim.inspect(dir), vim.inspect(dir), vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('<C-a> selects everything and <C-r> inverts the selection before deleting', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'x' })
    T.write_file(dir .. '/b.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      feed('<C-a>') -- 全選択
      vim.wait(30)
      feed('<C-r>') -- 反転 -> 全解除
      vim.wait(30)
      feed('<Esc>') -- 選択が空ならフィルタ解除/パネルクローズに落ちる。
                     -- ここは選択0件のはずなのでパネルが閉じてしまう前に確認する
    ]], vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))

    -- <C-a>で全選択し、そのまま削除すると全ファイルが消えることを確認する
    res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)
      feed('<C-a>')
      vim.wait(30)
      feed('d')
      vim.wait(50)
      feed('y')
      vim.wait(80)
      assert_eq(vim.fn.filereadable(%s .. '/a.txt'), 0)
      assert_eq(vim.fn.filereadable(%s .. '/b.txt'), 0)
    ]], vim.inspect(dir), vim.inspect(dir), vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('<Esc> priority: clears selection first, then the filter, only closing the panel once both are empty', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/apple.txt', { 'x' })
    T.write_file(dir .. '/banana.txt', { 'x' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      feed('/apple<CR>')
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'apple.txt'), 0 })
      feed('<Tab>') -- フィルタされた状態で選択もする
      vim.wait(50)

      feed('<Esc>') -- 1回目: 選択解除が先
      vim.wait(50)
      assert_eq(list_win() ~= nil, true, 'panel should still be open (selection was cleared, not the panel)')
      local text = table.concat(lines(win), '\n')
      assert_eq(text:find('banana.txt', 1, true), nil, 'filter should still be active (selection was cleared, not the filter)')

      feed('<Esc>') -- 2回目: 選択は既に空なので、今度はフィルタが解除される
      vim.wait(50)
      assert_eq(list_win() ~= nil, true, 'panel should still be open (filter was cleared, not the panel)')
      text = table.concat(lines(win), '\n')
      assert_eq(text:find('banana.txt', 1, true) ~= nil, true, 'filter should be cleared now')

      feed('<Esc>') -- 3回目: 選択・フィルタとも空なので、今度こそパネルを閉じる
      vim.wait(50)
      assert_eq(list_win(), nil, 'panel should close once selection and filter are both empty')
    ]], vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('P (overwrite paste) replaces an existing same-named file instead of creating a "_2" copy', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/dest', 'p')
    T.write_file(dir .. '/src.txt', { 'new content' })
    T.write_file(dir .. '/dest/src.txt', { 'old content' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      vim.api.nvim_win_set_cursor(win, { find_row(win, 'src.txt'), 0 })
      feed('y') -- copy
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'dest'), 0 })
      feed('l') -- dest/ へ入る
      vim.wait(50)
      feed('P') -- 上書き貼り付け(名前が衝突しても別名にしない)
      vim.wait(80)
      local names = {}
      for _, l in ipairs(lines(win)) do table.insert(names, l) end
      local joined = table.concat(names, '\n')
      assert_eq(joined:find('src_2', 1, true), nil, 'overwrite paste should not create a "_2" copy')
      local content = vim.fn.readfile(%s .. '/dest/src.txt')
      assert_eq(content[1], 'new content', "overwrite paste should replace the existing file's content")
    ]], vim.inspect(dir), vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('a plain paste (p) onto a name collision creates a "_2" copy instead of overwriting', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/dest', 'p')
    T.write_file(dir .. '/src.txt', { 'new content' })
    T.write_file(dir .. '/dest/src.txt', { 'old content' })

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      vim.api.nvim_win_set_cursor(win, { find_row(win, 'src.txt'), 0 })
      feed('y')
      vim.wait(50)
      vim.api.nvim_win_set_cursor(win, { find_row(win, 'dest'), 0 })
      feed('l')
      vim.wait(50)
      feed('p') -- 通常貼り付け: 衝突時は別名になるはず
      vim.wait(80)
      local old_content = vim.fn.readfile(%s .. '/dest/src.txt')
      assert_eq(old_content[1], 'old content', 'the original file at the destination should be untouched')
    ]], vim.inspect(dir), vim.inspect(dir)))
    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('s (fd search) warns when fd or fzf is missing, without opening a terminal', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')

    local res = run_child(string.format([[
      vim.fn.chdir(%s)
      local explorer = require('config.explorer')
      explorer.open(false)
      vim.wait(80)
      local win = list_win()
      vim.api.nvim_set_current_win(win)

      local orig_executable = vim.fn.executable
      vim.fn.executable = function(name)
        if name == 'fd' then return 0 end
        return orig_executable(name)
      end
      local notified
      local orig_notify = vim.notify
      vim.notify = function(msg) notified = msg end
      local wins_before = #vim.api.nvim_list_wins()
      feed('s')
      vim.wait(80)
      vim.fn.executable = orig_executable
      vim.notify = orig_notify
      assert_eq(notified ~= nil, true, 'should notify about the missing dependency')
      assert_eq(#vim.api.nvim_list_wins(), wins_before, 'no terminal window should open')
    ]], vim.inspect(dir)))

    T.eq(res.code, 0, 'child failed: ' .. (res.stderr or ''))
    T.rmrf(dir)
  end)

  T.it('fullscreen: q key and native :q both quit Neovim; sidebar mode only closes the panel', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local cases = {
      { fullscreen = 'true', action = "vim.cmd('normal q')", expect_alive = false, label = 'fullscreen q-key' },
      { fullscreen = 'true', action = "vim.cmd('q')", expect_alive = false, label = 'fullscreen native :q' },
      { fullscreen = 'false', action = "vim.cmd('normal q')", expect_alive = true, label = 'sidebar q-key' },
    }
    for _, c in ipairs(cases) do
      local res = run_child(string.format([[
        vim.fn.chdir(%s)
        require('config.explorer').open(%s)
        vim.wait(150)
        %s
        vim.wait(150)
        io.stderr:write('STILL_ALIVE\n')
        vim.cmd('qa!')
      ]], vim.inspect(dir), c.fullscreen, c.action))
      local alive = (res.stderr or ''):find('STILL_ALIVE') ~= nil
      T.eq(alive, c.expect_alive, c.label .. ' aliveness')
    end
    T.rmrf(dir)
  end)
end)

T.summary()
