local T = dofile(TESTS_DIR .. '/helpers.lua')
local rg_fzf = require('config.rg_fzf')

--- rg_fzf.M.open()/M.replace()は実際にfzfを対話的に起動する前提のツールで、
--- ヘッドレスにはfzf自身のUI操作までは検証できない(pty無しでは意味のある
--- 入出力ができない)。ここでは依存チェック(rg/fzf不在時のnotify)と、
--- 両方揃っている時にfloatingターミナルが起動することだけを確認する
local function with_fake_executable(missing, fn)
  local orig = vim.fn.executable
  vim.fn.executable = function(name)
    if name == missing then return 0 end
    return orig(name)
  end
  local ok, err = pcall(fn)
  vim.fn.executable = orig
  if not ok then error(err, 0) end
end

local function capture_notify(fn)
  local notified
  local orig_notify = vim.notify
  vim.notify = function(msg, level) notified = { msg = msg, level = level } end
  local ok, err = pcall(fn)
  vim.notify = orig_notify
  if not ok then error(err, 0) end
  return notified
end

T.describe('rg_fzf dependency check', function()
  T.it('M.open() reports an error and does not open anything when rg is missing', function()
    local opened_win_count_before = #vim.api.nvim_list_wins()
    local notified
    with_fake_executable('rg', function()
      notified = capture_notify(function() rg_fzf.open('x') end)
    end)
    T.ok(notified ~= nil, 'should notify')
    T.contains(notified.msg, 'rg')
    T.eq(#vim.api.nvim_list_wins(), opened_win_count_before, 'no window should open')
  end)

  T.it('M.open() reports an error and does not open anything when fzf is missing', function()
    local opened_win_count_before = #vim.api.nvim_list_wins()
    local notified
    with_fake_executable('fzf', function()
      notified = capture_notify(function() rg_fzf.open('x') end)
    end)
    T.ok(notified ~= nil, 'should notify')
    T.contains(notified.msg, 'fzf')
    T.eq(#vim.api.nvim_list_wins(), opened_win_count_before, 'no window should open')
  end)

  T.it('M.replace() is gated by the same dependency check', function()
    local notified
    with_fake_executable('rg', function()
      notified = capture_notify(function() rg_fzf.replace('x', 'y') end)
    end)
    T.ok(notified ~= nil, 'should notify')
    T.contains(notified.msg, 'rg')
  end)

  T.it('M.open() opens a floating terminal running rg|fzf when both are installed', function()
    if vim.fn.executable('rg') == 0 or vim.fn.executable('fzf') == 0 then
      print('  (skipped: rg/fzf not installed on this machine)')
      return
    end
    local prev_cwd = vim.fn.getcwd()
    local notified = capture_notify(function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      T.write_file(dir .. '/a.txt', { 'hello world' })
      vim.fn.chdir(dir)

      rg_fzf.open('hello')
      vim.wait(150)

      local term_win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative ~= '' and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'terminal' then term_win = w end
      end
      T.ok(term_win ~= nil, 'a floating terminal window should have opened')

      local job = vim.b[vim.api.nvim_win_get_buf(term_win)].terminal_job_id
      if job then pcall(vim.fn.jobstop, job) end
      if term_win and vim.api.nvim_win_is_valid(term_win) then vim.api.nvim_win_close(term_win, true) end
      vim.fn.chdir(prev_cwd)
      T.rmrf(dir)
    end)
    T.ok(notified == nil, 'should not report missing dependencies when rg/fzf are installed')
  end)
end)

--- fzf自体はptyが無いヘッドレスでは駆動できないが、その手前(rg出力行の解析・
--- 置換の実適用)は純粋なロジックなので直接呼んで検証する
T.describe('rg_fzf pure logic (parse/replace, no fzf/pty needed)', function()
  T.it('open_match jumps to path:line:col from an rg --column match line, stripping ANSI codes', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'one', 'two needle', 'three' })
    local prev_cwd = vim.fn.getcwd()
    vim.fn.chdir(dir)
    vim.cmd('enew')

    rg_fzf.open_match('\27[1mf.txt\27[0m:2:5:two needle')
    T.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), 'f.txt')
    T.eq(vim.api.nvim_win_get_cursor(0), { 2, 4 })

    vim.cmd('bwipeout!')
    vim.fn.chdir(prev_cwd)
    T.rmrf(dir)
  end)

  T.it('open_match falls back to column 1 for a path:line-only match (no column)', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'one', 'two' })
    local prev_cwd = vim.fn.getcwd()
    vim.fn.chdir(dir)
    vim.cmd('enew')

    rg_fzf.open_match('f.txt:2:')
    T.eq(vim.api.nvim_win_get_cursor(0), { 2, 0 })

    vim.cmd('bwipeout!')
    vim.fn.chdir(prev_cwd)
    T.rmrf(dir)
  end)

  T.it('parse_path extracts the path from a match line, ignoring ANSI color codes', function()
    T.eq(rg_fzf.parse_path('\27[1msrc/a.txt\27[0m:12:3:hello'), 'src/a.txt')
    T.eq(rg_fzf.parse_path('src/a.txt:12:'), 'src/a.txt')
    T.eq(rg_fzf.parse_path('not a match line'), nil)
  end)

  T.it('replace_literal replaces every literal (non-pattern) occurrence and reports the count', function()
    local out, count = rg_fzf.replace_literal('foo.bar(foo, foo)', 'foo', 'baz')
    T.eq(out, 'baz.bar(baz, baz)')
    T.eq(count, 3)

    -- リテラル置換なので、Luaパターン文字は特殊文字として解釈されない
    out, count = rg_fzf.replace_literal('a.b.c', '.', 'X')
    T.eq(out, 'aXbXc')
    T.eq(count, 2)

    out, count = rg_fzf.replace_literal('nothing here', 'zzz', 'q')
    T.eq(out, 'nothing here')
    T.eq(count, 0)
  end)

  T.it('resolve_path passes through absolute paths and joins relative ones onto cwd', function()
    T.eq(rg_fzf.resolve_path('/repo', 'src/a.txt'), '/repo/src/a.txt')
    T.eq(rg_fzf.resolve_path('/repo', '/etc/hosts'), '/etc/hosts')
  end)

  T.it('apply_replace_to_path rewrites an unopened file on disk and returns the replacement count', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'foo one', 'foo two' })

    local count = rg_fzf.apply_replace_to_path(dir .. '/f.txt', 'foo', 'bar')
    T.eq(count, 2)
    T.eq(vim.fn.readfile(dir .. '/f.txt'), { 'bar one', 'bar two' })

    T.rmrf(dir)
  end)

  T.it('apply_replace_to_path rewrites an already-open buffer in place and writes it', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'foo one' })
    vim.cmd('edit ' .. dir .. '/f.txt')
    local bufnr = vim.api.nvim_get_current_buf()

    local count = rg_fzf.apply_replace_to_path(dir .. '/f.txt', 'foo', 'bar')
    T.eq(count, 1)
    T.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'bar one' })
    T.eq(vim.bo[bufnr].modified, false, 'buffer should have been written to disk')
    T.eq(vim.fn.readfile(dir .. '/f.txt'), { 'bar one' }, 'the write should have reached disk too')

    vim.cmd('bwipeout!')
    T.rmrf(dir)
  end)

  T.it('apply_replace_to_path is a no-op (returns 0) on a binary file', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    -- vim.fn.writefileはNUL混じりの文字列をBlobとして扱ってしまい素の文字列
    -- リストと混在できないため、io.openで直接バイナリを書く
    local f = io.open(dir .. '/f.bin', 'wb')
    f:write('foo\0bar')
    f:close()

    local count = rg_fzf.apply_replace_to_path(dir .. '/f.bin', 'foo', 'bar')
    T.eq(count, 0)

    T.rmrf(dir)
  end)

  T.it('replace_selected applies the replacement across every distinct file among the selected match lines', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'foo in a' })
    T.write_file(dir .. '/b.txt', { 'foo in b', 'foo again' })
    T.write_file(dir .. '/c.txt', { 'untouched foo' }) -- 選択行に無いので変更されない

    local file_count, replace_count = rg_fzf.replace_selected(dir, {
      'a.txt:1:1:foo in a',
      'b.txt:1:1:foo in b',
      'b.txt:2:1:foo again', -- 同じファイルが複数行にマッチしても1回だけ処理される
    }, 'foo', 'bar')

    T.eq(file_count, 2)
    T.eq(replace_count, 3)
    T.eq(vim.fn.readfile(dir .. '/a.txt'), { 'bar in a' })
    T.eq(vim.fn.readfile(dir .. '/b.txt'), { 'bar in b', 'bar again' })
    T.eq(vim.fn.readfile(dir .. '/c.txt'), { 'untouched foo' })

    T.rmrf(dir)
  end)
end)

T.summary()
