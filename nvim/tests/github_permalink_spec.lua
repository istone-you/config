local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.github_permalink')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('github_permalink', function()
  T.it('normal mode <leader>G copies a blob URL with #Lline for an SSH-style remote', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/sub/file.lua', { 'a', 'b', 'c', 'd' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
      T.git(d, { 'remote', 'add', 'origin', 'git@github.com:someone/somerepo.git' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/sub/file.lua'))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    local sha = vim.trim(T.git(dir, { 'rev-parse', 'HEAD' }).stdout)

    feed('<leader>G')
    vim.wait(50)
    T.eq(vim.fn.getreg('"'),
      ('https://github.com/someone/somerepo/blob/%s/sub/file.lua#L3'):format(sha))

    T.rmrf(dir)
  end)

  T.it('visual mode <leader>G copies a #Lstart-Lend range, order-independent', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/file.lua', { 'a', 'b', 'c', 'd', 'e' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
      T.git(d, { 'remote', 'add', 'origin', 'https://github.com/someone/somerepo.git' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/file.lua'))
    local sha = vim.trim(T.git(dir, { 'rev-parse', 'HEAD' }).stdout)

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    feed('V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    feed('<leader>G')
    vim.wait(50)
    T.eq(vim.fn.getreg('"'),
      ('https://github.com/someone/somerepo/blob/%s/file.lua#L2-L4'):format(sha))

    T.rmrf(dir)
  end)

  T.it('strips embedded credentials from an HTTPS remote URL', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/file.lua', { 'a' })
      T.git(d, { 'add', '.' })
      T.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
      T.git(d, { 'remote', 'add', 'origin', 'https://user:token@github.com/someone/somerepo.git' })
    end)
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/file.lua'))
    feed('<leader>G')
    vim.wait(50)
    T.contains(vim.fn.getreg('"'), 'https://github.com/someone/somerepo/blob/')
    T.ok(not vim.fn.getreg('"'):find('token', 1, true), 'credentials must not leak into the URL')

    T.rmrf(dir)
  end)

  T.it('does nothing (no notify crash) for an unsaved buffer with no file name', function()
    vim.cmd('enew')
    feed('<leader>G')
    vim.wait(50)
    -- ここでエラーにならず(pcall無しでも)通過することが確認事項。レジスタは変わらない
  end)
end)

T.summary()
