local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.copy_with_path')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('copy_with_path', function()
  T.it('normal mode <leader>P copies "path:line" + a fenced code block using the mapped language tag', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/sub/main.lua', { 'local a = 1', 'local b = 2', 'local c = 3' })
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/sub/main.lua'))
    vim.bo.filetype = 'lua' -- -u NONEではfiletype検出が無効なため明示する
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    feed('<leader>P')
    vim.wait(50)
    T.eq(vim.fn.getreg('+'), 'sub/main.lua:2\n```lua\nlocal b = 2\n```')

    T.rmrf(dir)
  end)

  T.it('visual mode copies a "path:start-end" range spanning the whole selection', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/main.ts', { 'const a = 1', 'const b = 2', 'const c = 3' })
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/main.ts'))
    vim.bo.filetype = 'typescript' -- -u NONEではfiletype検出が無効なため明示する

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed('V')
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    feed('<leader>P')
    vim.wait(50)
    T.eq(vim.fn.getreg('+'), 'main.ts:1-3\n```ts\nconst a = 1\nconst b = 2\nconst c = 3\n```')

    T.rmrf(dir)
  end)

  T.it('falls back to the raw filetype when there is no ft_to_lang mapping', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/Makefile', { 'build:', '\ttrue' })
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/Makefile'))
    vim.bo.filetype = 'make' -- ft_to_langに'make'は無い

    feed('<leader>P')
    vim.wait(50)
    T.contains(vim.fn.getreg('+'), '```make\n')

    T.rmrf(dir)
  end)

  T.it('uses the absolute path (no crash) outside a git repo', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/plain.txt', { 'hello' })
    vim.fn.chdir(dir)
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/plain.txt'))
    feed('<leader>P')
    vim.wait(50)
    T.contains(vim.fn.getreg('+'), dir .. '/plain.txt:1')

    T.rmrf(dir)
  end)
end)

T.summary()
