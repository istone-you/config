local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.git_blame')

local ns = vim.api.nvim_create_namespace('git_blame')

local function virt_text_at(buf, row)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
  for _, m in ipairs(marks) do
    local vt = m[4] and m[4].virt_text
    if vt then return vt[1][1] end
  end
  return nil
end

T.describe('git_blame', function()
  T.it('shows author/date/summary for a committed line', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1', 'line2', 'line3' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=alice@example.com', '-c', 'user.name=Alice', 'commit', '-qm', 'add lines' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
    T.wait_until(function() return virt_text_at(0, 1) ~= nil end, 2000)

    local text = virt_text_at(0, 1)
    T.contains(text, 'Alice')
    T.contains(text, 'add lines')

    T.rmrf(dir)
  end)

  T.it('shows "Uncommitted changes" / "You" for a locally modified line', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1', 'line2' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=alice@example.com', '-c', 'user.name=Alice', 'commit', '-qm', 'seed' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'line1 CHANGED' })
    vim.cmd('write') -- git blameは実プロセスがディスク上のファイルを読むため、保存が必要
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
    T.wait_until(function() return virt_text_at(0, 0) ~= nil end, 2000)

    local text = virt_text_at(0, 0)
    T.contains(text, 'You')
    T.contains(text, 'Uncommitted changes')

    T.rmrf(dir)
  end)

  T.it('clears the blame text on InsertEnter', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'line1' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=alice@example.com', '-c', 'user.name=Alice', 'commit', '-qm', 'seed' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
    T.wait_until(function() return virt_text_at(0, 0) ~= nil end, 2000)

    vim.api.nvim_exec_autocmds('InsertEnter', { buffer = 0 })
    T.eq(virt_text_at(0, 0), nil, 'blame text should be cleared on InsertEnter')

    T.rmrf(dir)
  end)
end)

T.summary()
