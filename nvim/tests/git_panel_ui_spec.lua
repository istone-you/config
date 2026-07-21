local T = dofile(TESTS_DIR .. '/helpers.lua')
local ui = require('config.git_panel.ui')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

T.describe('git_panel.ui', function()
  T.it('menu window widens to fit a long title, not just the item labels', function()
    vim.o.columns = 120
    vim.o.lines = 40
    local long_title = '破棄: ' .. string.rep('very/long/nested/path/', 2) .. 'file.txt'
    ui.menu(long_title, {
      { key = 'x', label = 'a', value = 'a' },
    }, {}, function() end)

    local win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= '' then win = w end
    end
    T.ok(win ~= nil)
    local cfg = vim.api.nvim_win_get_config(win)
    T.ok(cfg.width >= vim.fn.strdisplaywidth(long_title),
      'menu width (' .. cfg.width .. ') should fit the title (' .. vim.fn.strdisplaywidth(long_title) .. ')')
    feed('q') -- close without choosing
  end)

  T.it('confirm() maps y/n/Esc to true/false/false (Esc == decline, not cancel)', function()
    for _, case in ipairs({
      { key = 'y', expect = true },
      { key = 'n', expect = false },
      { key = '<Esc>', expect = false },
    }) do
      local result, called = 'unset', false
      ui.confirm('本当に実行しますか？', {}, function(r) result = r; called = true end)
      feed(case.key)
      T.ok(called, 'callback should have run for key ' .. case.key)
      T.eq(result, case.expect, 'confirm(' .. case.key .. ')')
    end
  end)

  T.it('input() submits typed text on <CR>, nil on <Esc>', function()
    local result
    ui.input('名前', '', {}, function(r) result = r end)
    feed('ihello world')
    feed('<CR>')
    T.eq(result, 'hello world')

    result = 'unset'
    ui.input('名前', 'default', {}, function(r) result = r end)
    feed('<Esc>')
    T.eq(result, nil)
  end)

  T.it('multiline_input: Enter always confirms immediately (no newline insertion), Esc cancels', function()
    local result
    ui.multiline_input({ title = 'コミットメッセージ' }, function(r) result = r end)
    feed('ifirst line')
    feed('<CR>') -- lazygitのcommit message同様、Enterは常に即確定(改行にはならない)
    T.eq(result, { 'first line' })

    result = 'unset'
    ui.multiline_input({ title = 'コミットメッセージ' }, function(r) result = r end)
    feed('i' .. 'typed but cancelled')
    feed('<Esc>')
    T.eq(result, nil)
  end)
end)

T.summary()
