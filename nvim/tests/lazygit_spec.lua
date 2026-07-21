-- lazygit.luaも実バイナリのTUIはheadlessで駆動できないため、即終了する偽lazygit
-- スクリプトをPATHに差し込み、フローティングウィンドウの寸法とon_exit時の
-- 後始末(ウィンドウ/バッファの破棄)を検証する

local T = dofile(TESTS_DIR .. '/helpers.lua')
local lazygit = require('config.lazygit')

local function with_fake_lazygit(script_body, fn)
  local bin_dir = vim.fn.tempname()
  vim.fn.mkdir(bin_dir, 'p')
  local script = bin_dir .. '/lazygit'
  T.write_file(script, { '#!/bin/sh', script_body })
  vim.fn.setfperm(script, 'rwxr-xr-x')

  local orig_path = vim.env.PATH
  vim.env.PATH = bin_dir .. ':' .. orig_path
  local ok, err = pcall(fn)
  vim.env.PATH = orig_path
  T.rmrf(bin_dir)
  if not ok then error(err, 0) end
end

local function floating_term_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= '' and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'terminal' then
      return w
    end
  end
end

T.describe('lazygit (terminal integration)', function()
  T.it('opens a ~90%x90% centered floating terminal', function()
    vim.o.columns, vim.o.lines = 160, 40
    with_fake_lazygit('sleep 5', function()
      lazygit.open()
      vim.wait(150)
      local win = floating_term_win()
      T.ok(win ~= nil, 'a floating terminal window should have opened')
      local cfg = vim.api.nvim_win_get_config(win)
      T.eq(cfg.width, math.floor(160 * 0.9))
      T.eq(cfg.height, math.floor(40 * 0.9))

      local buf = vim.api.nvim_win_get_buf(win)
      local job = vim.b[buf].terminal_job_id
      if job then pcall(vim.fn.jobstop, job) end
      vim.wait(100)
    end)
  end)

  T.it('closes the window and wipes the buffer once lazygit exits', function()
    with_fake_lazygit('true', function() -- 即終了
      local bufs_before = #vim.api.nvim_list_bufs()
      lazygit.open()
      T.wait_until(function() return floating_term_win() == nil end, 2000)
      T.ok(floating_term_win() == nil, 'the floating window should be closed after exit')
      T.eq(#vim.api.nvim_list_bufs(), bufs_before, 'the terminal buffer should be wiped, not left behind')
    end)
  end)
end)

T.summary()
