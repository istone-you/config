-- yazi.luaは実際のyaziバイナリのTUIをheadlessで駆動できないため、PATHの先頭に
-- --chooser-fileへ即座に選択結果を書き出すだけの偽yaziスクリプトを差し込み、
-- on_exit時のファイルオープン結線(1件目はedit、以降はbadd)を実際に検証する

local T = dofile(TESTS_DIR .. '/helpers.lua')
local yazi = require('config.yazi')

local function with_fake_yazi(script_body, fn)
  local bin_dir = vim.fn.tempname()
  vim.fn.mkdir(bin_dir, 'p')
  local script = bin_dir .. '/yazi'
  T.write_file(script, { '#!/bin/sh', script_body })
  vim.fn.setfperm(script, 'rwxr-xr-x')

  local orig_path = vim.env.PATH
  vim.env.PATH = bin_dir .. ':' .. orig_path
  local ok, err = pcall(fn)
  vim.env.PATH = orig_path
  T.rmrf(bin_dir)
  if not ok then error(err, 0) end
end

local function term_win_count()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'terminal' then n = n + 1 end
  end
  return n
end

T.describe('yazi (--chooser-file integration)', function()
  T.it('opens a right-side terminal split without number/signcolumn clutter', function()
    with_fake_yazi('sleep 5', function()
      local before = term_win_count()
      yazi.open()
      vim.wait(150)
      T.eq(term_win_count(), before + 1, 'a terminal window should have opened')

      local term_win
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'terminal' then term_win = w end
      end
      T.eq(vim.wo[term_win].number, false)
      T.eq(vim.wo[term_win].relativenumber, false)
      T.eq(vim.wo[term_win].signcolumn, 'no')

      local job = vim.b[vim.api.nvim_win_get_buf(term_win)].terminal_job_id
      if job then pcall(vim.fn.jobstop, job) end
      vim.wait(100)
    end)
  end)

  T.it('opens the first chosen file with :edit and adds the rest with :badd', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/first.txt', { 'a' })
    T.write_file(dir .. '/second.txt', { 'b' })

    with_fake_yazi(string.format('printf "%%s\\n%%s\\n" %s %s > "$2"',
      dir .. '/first.txt', dir .. '/second.txt'), function()
      yazi.open(dir)
      T.wait_until(function()
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t') == 'first.txt'
      end, 2000)
      T.eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), 'first.txt',
        'the first chosen file should be :edit-ed into the current window')

      local second_buf = vim.fn.bufnr(dir .. '/second.txt')
      T.ok(second_buf ~= -1, 'the second chosen file should have been :badd-ed')
      T.eq(vim.fn.bufloaded(second_buf), 0, ':badd should not load/display it, just add it to the buffer list')

      vim.cmd('bwipeout! ' .. vim.api.nvim_get_current_buf())
      vim.cmd('bwipeout! ' .. second_buf)
    end)
    T.rmrf(dir)
  end)

  T.it('does nothing extra when the chooser file is empty (user quit without picking anything)', function()
    local before_bufs = #vim.api.nvim_list_bufs()
    with_fake_yazi('true', function() -- 何も選ばず即終了(chooser-fileは空のまま)
      yazi.open()
      vim.wait(200)
      T.eq(#vim.api.nvim_list_bufs(), before_bufs, 'no new buffer should appear when nothing was chosen')
    end)
  end)
end)

T.summary()
