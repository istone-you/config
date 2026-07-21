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
      T.rmrf(dir)
    end)
    T.ok(notified == nil, 'should not report missing dependencies when rg/fzf are installed')
  end)
end)

T.summary()
