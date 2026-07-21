local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.tabline')

T.describe('tabline', function()
  T.it('renders each listed buffer with its extension icon, and marks the modified one', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/main.lua', { 'return 1' })
    T.write_file(dir .. '/readme.md', { '# hi' })

    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/main.lua'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/readme.md'))
    vim.bo.modified = true

    local s = _G._tabline()
    T.contains(s, 'main.lua')
    T.contains(s, 'readme.md')
    T.contains(s, '●', 'modified buffer should show the dot marker')
    T.contains(s, 'TabLineModSel', 'the current+modified buffer should use the ModSel highlight')
    T.contains(s, vim.fn.nr2char(0xe620), 'main.lua should use the lua icon') -- .lua icon codepoint

    T.rmrf(dir)
  end)

  T.it('terminal buffers are excluded from the tabline', function()
    -- buftype='terminal'は直接代入できないため、nvim_open_termで本物のterminal
    -- バッファを作る
    local tbuf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_open_term(tbuf, {})
    local s = _G._tabline()
    -- tabline側は各バッファを"%<bufnr>@v:lua._bufline_click@"というクリック領域として
    -- 出力するので、そのbufnr宛のクリック領域が無い=一覧に含まれていないことの確認になる
    T.ok(not s:find('%' .. tbuf .. '@v:lua._bufline_click@', 1, true),
      'a terminal buffer must not get a tabline entry')
    vim.api.nvim_buf_delete(tbuf, { force = true })
  end)
end)

T.summary()
