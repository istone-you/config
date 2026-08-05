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

  T.it('<leader>q keeps a modified buffer and notifies instead of showing E89', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/dirty.txt', { 'dirty' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/dirty.txt'))
    local dirty_buf = vim.api.nvim_get_current_buf()
    vim.bo[dirty_buf].modified = true

    local notifications = {}
    local orig_notify = vim.notify
    vim.notify = function(msg) table.insert(notifications, tostring(msg)) end
    feed('<leader>q')
    vim.wait(80)
    vim.notify = orig_notify

    T.eq(vim.fn.buflisted(dirty_buf), 1, 'modified buffer should remain listed')
    T.eq(vim.bo[dirty_buf].modified, true, 'modified buffer should remain modified')
    T.ok(vim.iter(notifications):any(function(msg)
      return msg:find('未保存', 1, true) ~= nil
    end), 'should notify about the unsaved buffer')

    vim.bo[dirty_buf].modified = false
    vim.cmd('bwipeout! ' .. dirty_buf)
    T.rmrf(dir)
  end)

  T.it('<leader>Q closes all tabline buffers, but keeps modified buffers', function()
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

    local notifications = {}
    local orig_notify = vim.notify
    vim.notify = function(msg) table.insert(notifications, tostring(msg)) end
    feed('<leader>Q')
    vim.wait(80)
    vim.notify = orig_notify

    T.eq(vim.fn.buflisted(a_buf), 0, 'clean buffer a should be closed')
    T.eq(vim.fn.buflisted(b_buf), 0, 'clean buffer b should be closed')
    T.eq(vim.fn.buflisted(dirty_buf), 1, 'modified buffer should remain listed')
    T.ok(vim.iter(notifications):any(function(msg)
      return msg:find('未保存', 1, true) ~= nil
    end), 'should notify about kept modified buffers')

    vim.bo[dirty_buf].modified = false
    vim.cmd('bwipeout! ' .. dirty_buf)
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
