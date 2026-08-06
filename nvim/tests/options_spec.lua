-- options.luaはほとんどが宣言的な設定(colorscheme/statusline文字列等)で挙動テストの
-- 価値が薄いため、実際に振る舞いのある部分(バッファ操作キー・ColorScheme時の透過
-- 再適用・外部変更の自動反映)だけを対象にする
local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.options')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('options.lua behavior', function()
  T.it('<Tab>/<S-Tab> cycle to the next/previous listed buffer', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    vim.cmd('edit ' .. dir .. '/a.txt')
    vim.cmd('edit ' .. dir .. '/b.txt')
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')

    T.eq(vim.api.nvim_get_current_buf(), b_buf)
    feed('<Tab>') -- bnext: bからaへ折り返す(リストされたバッファが2件なので)
    T.eq(vim.api.nvim_get_current_buf(), a_buf)
    feed('<S-Tab>') -- bprev: aからbへ戻る
    T.eq(vim.api.nvim_get_current_buf(), b_buf)

    vim.cmd('bwipeout! ' .. a_buf)
    vim.cmd('bwipeout! ' .. b_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>q closes the current buffer and switches to the previous one, when more than one is listed', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    vim.cmd('edit ' .. dir .. '/a.txt')
    vim.cmd('edit ' .. dir .. '/b.txt')
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')

    feed('<leader>q')
    T.eq(vim.api.nvim_get_current_buf(), a_buf, 'should have switched to the previous buffer')
    -- :bdeleteはバッファオブジェクト自体は残す(nvim_buf_is_validはtrueのまま)ので、
    -- unload+unlistedになったことで判定する
    T.eq(vim.fn.bufloaded(b_buf), 0, 'the closed buffer should be unloaded')
    T.eq(vim.fn.buflisted(b_buf), 0, 'the closed buffer should be unlisted')

    vim.cmd('bwipeout! ' .. a_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>q closes the last listed buffer too (start_screen が受け止める)', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/only.txt', { 'x' })
    vim.cmd('edit ' .. dir .. '/only.txt')
    -- 他にリストされたバッファが残らないようにする(前のテストの後始末漏れも含め)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= vim.api.nvim_get_current_buf() and vim.bo[b].buflisted then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    local only_buf = vim.api.nvim_get_current_buf()

    feed('<leader>q')
    vim.wait(50)
    -- 最後の1つでも閉じる（delistされ、カーソルは別バッファへ移る）
    T.ok(vim.api.nvim_get_current_buf() ~= only_buf, 'moved off the closed buffer')
    T.eq(vim.fn.buflisted(only_buf), 0, 'the last buffer is closed (delisted)')

    pcall(vim.cmd, 'bwipeout! ' .. only_buf)
    T.rmrf(dir)
  end)

  local function float_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= '' then return w end
    end
  end

  T.it('<leader>q on a modified buffer shows the unsaved dialog; cancel keeps it', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))
    local dirty_buf = vim.api.nvim_get_current_buf()
    vim.bo[dirty_buf].modified = true

    feed('<leader>q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(fw), 0, -1, false), '\n')
    T.ok(text:find('未保存', 1, true) ~= nil, 'shows unsaved dialog: ' .. text)
    T.ok(text:find('保存して終了', 1, true) ~= nil, 'offers save & close')
    T.ok(text:find('保存せず終了', 1, true) ~= nil, 'offers discard & close')

    vim.api.nvim_set_current_win(fw)
    feed('n')
    vim.wait(50)
    T.ok(float_win() == nil, 'popup closed on cancel')
    T.eq(vim.fn.buflisted(dirty_buf), 1, 'modified buffer should remain listed')
    T.eq(vim.bo[dirty_buf].modified, true, 'modified buffer should remain modified')

    vim.bo[dirty_buf].modified = false
    vim.cmd('bwipeout! ' .. dirty_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>q discard (d) force-closes a modified buffer', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local dirty_buf = vim.fn.bufnr(dir .. '/dirty.txt')
    vim.bo[dirty_buf].modified = true

    feed('<leader>q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    vim.api.nvim_set_current_win(fw)
    feed('d')
    vim.wait(80)

    T.ok(float_win() == nil, 'popup closed after discard')
    T.eq(vim.fn.buflisted(dirty_buf), 0, 'dirty buffer should be closed')
    T.eq(vim.api.nvim_get_current_buf(), a_buf, 'should switch to the previous buffer')

    vim.cmd('bwipeout! ' .. a_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>q save (s) writes and closes a modified buffer', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))
    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local dirty_buf = vim.fn.bufnr(dir .. '/dirty.txt')
    vim.api.nvim_buf_set_lines(dirty_buf, 0, -1, false, { 'saved content' })
    vim.bo[dirty_buf].modified = true

    feed('<leader>q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    vim.api.nvim_set_current_win(fw)
    feed('s')
    vim.wait(80)

    T.ok(float_win() == nil, 'popup closed after save')
    T.eq(vim.fn.buflisted(dirty_buf), 0, 'dirty buffer should be closed after save')
    T.eq(vim.api.nvim_get_current_buf(), a_buf, 'should switch to the previous buffer')
    T.eq(vim.fn.readfile(dir .. '/dirty.txt')[1], 'saved content', 'file should be written')

    vim.cmd('bwipeout! ' .. a_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>Q with modified buffers shows the unsaved dialog; cancel closes nothing', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/b.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))

    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')
    local dirty_buf = vim.fn.bufnr(dir .. '/dirty.txt')
    vim.bo[dirty_buf].modified = true

    feed('<leader>Q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(fw), 0, -1, false), '\n')
    T.ok(text:find('未保存', 1, true) ~= nil, 'shows unsaved dialog: ' .. text)

    vim.api.nvim_set_current_win(fw)
    feed('n')
    vim.wait(50)
    T.ok(float_win() == nil, 'popup closed on cancel')
    T.eq(vim.fn.buflisted(a_buf), 1, 'clean buffer a should remain on cancel')
    T.eq(vim.fn.buflisted(b_buf), 1, 'clean buffer b should remain on cancel')
    T.eq(vim.fn.buflisted(dirty_buf), 1, 'modified buffer should remain on cancel')
    T.eq(vim.bo[dirty_buf].modified, true, 'modified buffer should remain modified')

    vim.bo[dirty_buf].modified = false
    vim.cmd('bwipeout! ' .. a_buf)
    vim.cmd('bwipeout! ' .. b_buf)
    vim.cmd('bwipeout! ' .. dirty_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>Q discard (d) force-closes all tabline buffers including modified', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))

    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local dirty_buf = vim.fn.bufnr(dir .. '/dirty.txt')
    vim.bo[dirty_buf].modified = true

    feed('<leader>Q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    vim.api.nvim_set_current_win(fw)
    feed('d')
    vim.wait(80)

    T.ok(float_win() == nil, 'popup closed after discard')
    T.eq(vim.fn.buflisted(a_buf), 0, 'clean buffer should be closed')
    T.eq(vim.fn.buflisted(dirty_buf), 0, 'modified buffer should be closed')
    T.rmrf(dir)
  end)

  T.it('<leader>Q save (s) writes modified buffers then closes all', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))

    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local dirty_buf = vim.fn.bufnr(dir .. '/dirty.txt')
    vim.api.nvim_buf_set_lines(dirty_buf, 0, -1, false, { 'saved all' })
    vim.bo[dirty_buf].modified = true

    feed('<leader>Q')
    vim.wait(80)
    local fw = float_win()
    T.ok(fw ~= nil, 'unsaved confirm popup appears')
    vim.api.nvim_set_current_win(fw)
    feed('s')
    vim.wait(80)

    T.ok(float_win() == nil, 'popup closed after save')
    T.eq(vim.fn.buflisted(a_buf), 0, 'clean buffer should be closed')
    T.eq(vim.fn.buflisted(dirty_buf), 0, 'modified buffer should be closed after save')
    T.eq(vim.fn.readfile(dir .. '/dirty.txt')[1], 'saved all', 'file should be written')
    T.rmrf(dir)
  end)

  T.it('<leader>Q closes all clean tabline buffers without a popup', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/a.txt', { 'a' })
    T.write_file(dir .. '/b.txt', { 'b' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/a.txt'))
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/b.txt'))

    local a_buf = vim.fn.bufnr(dir .. '/a.txt')
    local b_buf = vim.fn.bufnr(dir .. '/b.txt')

    feed('<leader>Q')
    vim.wait(50)
    T.ok(float_win() == nil, 'no popup when all buffers are clean')
    T.eq(vim.fn.buflisted(a_buf), 0, 'buffer a should be closed')
    T.eq(vim.fn.buflisted(b_buf), 0, 'buffer b should be closed')
    T.rmrf(dir)
  end)

  T.it('ColorScheme re-applies transparent backgrounds for Normal/NormalFloat/NormalNC', function()
    vim.api.nvim_set_hl(0, 'Normal', { bg = '#123456' }) -- 一旦不透明にしてから発火させる
    vim.cmd('doautocmd ColorScheme')
    for _, group in ipairs({ 'Normal', 'NormalFloat', 'NormalNC' }) do
      local hl = vim.api.nvim_get_hl(0, { name = group })
      T.eq(hl.bg, nil, group .. ' should have no background after ColorScheme fires')
    end
  end)

  T.it('autoread + auto-checktime picks up an out-of-band file change on BufEnter', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/f.txt', { 'original' })
    vim.cmd('edit ' .. dir .. '/f.txt')
    local buf = vim.api.nvim_get_current_buf()
    T.eq(vim.opt.autoread:get(), true)

    -- ファイルのmtime分解能を跨いでから書き換える(同一秒内だとchecktimeが
    -- 変化を検知できないことがある)
    vim.wait(1100)
    T.write_file(dir .. '/f.txt', { 'changed on disk' })
    -- synthetic nvim_exec_autocmds('FocusGained')はheadlessでのフォーカス概念が
    -- 薄くcheckが素通りすることがあるため、実際のバッファ切替(BufEnter)で検証する
    vim.cmd('enew')
    vim.cmd('buffer ' .. buf)
    T.wait_until(function()
      return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'changed on disk'
    end)
    T.eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], 'changed on disk')

    vim.cmd('bwipeout! ' .. buf)
    T.rmrf(dir)
  end)
end)

T.summary()
