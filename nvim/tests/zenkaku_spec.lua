local T = dofile(TESTS_DIR .. '/helpers.lua')
local z = require('config.zenkaku')

local function has_zenkaku_match(win)
  win = win or 0
  for _, m in ipairs(vim.fn.getmatches(win)) do
    if m.group == 'ZenkakuSpace' and m.pattern == z._zenkaku then
      return true
    end
  end
  return false
end

T.describe('zenkaku', function()
  T.it('defines the ZenkakuSpace highlight group', function()
    local hl = vim.api.nvim_get_hl(0, { name = 'ZenkakuSpace' })
    T.ok(hl.bg ~= nil, 'ZenkakuSpace should have a background color')
  end)

  T.it('applies a match for full-width spaces on a normal buffer', function()
    vim.cmd('enew')
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hello' .. z._zenkaku .. 'world' })
    vim.bo[buf].buftype = ''

    z._apply(win)
    T.ok(has_zenkaku_match(win), 'window should have a ZenkakuSpace match')
    T.ok(vim.w[win][z._match_var] ~= nil, 'match id should be stored on the window')

    vim.cmd('bwipeout!')
  end)

  T.it('does not apply the match on special buftype buffers (e.g. terminal prompt)', function()
    vim.cmd('enew')
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = 'nofile'
    z._apply(win)
    T.ok(not has_zenkaku_match(win), 'special buftype should not get the match')
    T.eq(vim.w[win][z._match_var], nil, 'match id should be cleared')
    vim.cmd('bwipeout!')
  end)

  T.it('re-applying replaces the previous match id without duplicating', function()
    vim.cmd('enew')
    local win = vim.api.nvim_get_current_win()
    vim.bo[vim.api.nvim_get_current_buf()].buftype = ''
    z._apply(win)
    local first = vim.w[win][z._match_var]
    z._apply(win)
    local second = vim.w[win][z._match_var]
    T.ok(first ~= nil and second ~= nil, 'match ids exist')
    local count = 0
    for _, m in ipairs(vim.fn.getmatches(win)) do
      if m.group == 'ZenkakuSpace' then count = count + 1 end
    end
    T.eq(count, 1, 'should keep exactly one ZenkakuSpace match')
    vim.cmd('bwipeout!')
  end)
end)

T.summary()
