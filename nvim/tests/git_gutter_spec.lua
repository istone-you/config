local T = dofile(TESTS_DIR .. '/helpers.lua')
local gutter = require('config.git_gutter')

local ns = vim.api.nvim_create_namespace('git_gutter')

local function signs_on(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local by_row = {}
  for _, m in ipairs(marks) do
    local row = m[2]
    local d = m[4] or {}
    by_row[row + 1] = {
      text = d.sign_text,
      hl = d.sign_hl_group,
    }
  end
  return by_row
end

T.describe('git_gutter.parse_diff', function()
  T.it('parses added / changed / deleted hunks like vim-gitgutter', function()
    local diff = table.concat({
      'diff --git a/x b/x',
      '--- a/x',
      '+++ b/x',
      '@@ -1,0 +2,2 @@',
      '+a',
      '+b',
      '@@ -5,1 +7,1 @@',
      '-old',
      '+new',
      '@@ -10,2 +11,0 @@',
      '-gone1',
      '-gone2',
    }, '\n')
    local marks = gutter.parse_diff(diff)
    T.eq(marks, {
      { lnum = 2, type = 'add' },
      { lnum = 3, type = 'add' },
      { lnum = 7, type = 'change' },
      { lnum = 11, type = 'delete' },
    })
  end)

  T.it('splits modified+added hunks', function()
    local diff = '@@ -1,1 +1,3 @@\n'
    local marks = gutter.parse_diff(diff)
    T.eq(marks, {
      { lnum = 1, type = 'change' },
      { lnum = 2, type = 'add' },
      { lnum = 3, type = 'add' },
    })
  end)
end)

T.describe('git_gutter.refresh', function()
  T.it('shows no signs in an untracked file (git 管理外は無視)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/new.txt', { 'one', 'two', 'three' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/new.txt'))
    gutter.refresh(0)
    T.wait_until(function()
      return gutter.diff_for_buf(0) == ''
    end, 2000)
    T.eq(signs_on(0), {})

    vim.cmd('bdelete!')
    T.rmrf(dir)
  end)

  T.it('shows added signs once an untracked file is staged', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/added.txt', { 'one', 'two', 'three' })
      T.git(d, { 'add', 'added.txt' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/added.txt'))
    gutter.refresh(0)
    T.wait_until(function()
      return vim.tbl_count(signs_on(0)) >= 3
    end, 2000)

    local s = signs_on(0)
    T.eq(s[1].hl, 'GitGutterAdd')
    T.eq(s[2].hl, 'GitGutterAdd')
    T.eq(s[3].hl, 'GitGutterAdd')

    vim.cmd('bdelete!')
    T.rmrf(dir)
  end)

  T.it('marks modified lines against HEAD (including unsaved buffer)', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1', 'line2', 'line3' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'line2 CHANGED' })
    gutter.refresh(0)
    T.wait_until(function()
      local s = signs_on(0)
      return s[2] ~= nil
    end, 2000)

    local s = signs_on(0)
    T.eq(s[2].hl, 'GitGutterChange')
    T.eq(s[1], nil)
    T.eq(s[3], nil)

    vim.cmd('bdelete!')
    T.rmrf(dir)
  end)

  T.it('shows no signs when buffer matches HEAD', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/clean.txt', { 'aaa', 'bbb', 'ccc' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/clean.txt'))
    gutter.refresh(0)
    T.wait_until(function()
      local diff = gutter.diff_for_buf(0)
      return diff == ''
    end, 2000)
    T.eq(signs_on(0), {})
    vim.cmd('bdelete!')
    T.rmrf(dir)
  end)

  T.it('marks a delete sign when a line is removed', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'keep', 'drop', 'tail' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.api.nvim_buf_set_lines(0, 1, 2, false, {})
    gutter.refresh(0)
    T.wait_until(function()
      return vim.tbl_count(signs_on(0)) >= 1
    end, 2000)

    local s = signs_on(0)
    local found_delete = false
    for _, v in pairs(s) do
      if v.hl == 'GitGutterDelete' then
        found_delete = true
      end
    end
    T.ok(found_delete, 'expected a GitGutterDelete sign')

    vim.cmd('bdelete!')
    T.rmrf(dir)
  end)
end)

T.summary()
