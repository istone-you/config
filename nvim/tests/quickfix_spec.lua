local T = dofile(TESTS_DIR .. '/helpers.lua')
-- keymap は require 時に <leader> を解決するので、モジュールより先に設定する
vim.g.mapleader = ' '
local quickfix = require('config.quickfix')
local win_util = require('config.util.win_util')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function reset()
  quickfix.close()
  vim.fn.setqflist({}, 'r', { title = '', items = {} })
end

local function fill(n)
  local items = {}
  for i = 1, n do
    items[i] = { filename = vim.fn.tempname(), lnum = i, col = 1, text = 'item ' .. i }
  end
  vim.fn.setqflist({}, ' ', { title = 'test', items = items })
end

T.describe('quickfix.lua', function()
  T.it('reports whether the quickfix window is open', function()
    reset()
    T.eq(quickfix.is_open(), false)
    fill(2)
    quickfix.open()
    T.eq(quickfix.is_open(), true)
    T.ok(quickfix.win(), 'ウィンドウが取れる')
    reset()
    T.eq(quickfix.is_open(), false)
  end)

  T.it('keeps the cursor in place when opened without focus', function()
    reset()
    fill(2)
    local before = vim.api.nvim_get_current_win()
    quickfix.open({ focus = false })
    T.eq(vim.api.nvim_get_current_win(), before, 'カーソルは元のウィンドウに残る')
    T.eq(quickfix.is_open(), true)
    reset()
  end)

  T.it('moves the cursor into the panel when opened with focus', function()
    reset()
    fill(2)
    quickfix.open({ focus = true })
    T.eq(vim.bo[vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())].buftype, 'quickfix')
    reset()
  end)

  T.it('does not stack windows when opened twice', function()
    reset()
    fill(2)
    quickfix.open()
    local first = quickfix.win()
    quickfix.open()
    T.eq(quickfix.win(), first, '2 回開いても 1 枚のまま')
    local count = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'quickfix' then count = count + 1 end
    end
    T.eq(count, 1)
    reset()
  end)

  T.it('closes and reopens through the toggle', function()
    reset()
    fill(3)
    -- 閉じられること・開き直せることが要件そのもの
    T.eq(quickfix.toggle(), true, '閉じているので開く')
    T.eq(quickfix.is_open(), true)
    T.eq(quickfix.toggle(), false, '開いているので閉じる')
    T.eq(quickfix.is_open(), false)
    T.eq(quickfix.toggle(), true, 'もう一度開ける')
    T.eq(quickfix.is_open(), true)
    reset()
  end)

  T.it('closes an auto-opened list too (AI が開いたものを閉じられる)', function()
    reset()
    fill(2)
    quickfix.open({ focus = false }) -- nvim_api/qflist.set と同じ開き方
    T.eq(quickfix.is_open(), true)
    T.eq(quickfix.toggle(), false)
    T.eq(quickfix.is_open(), false)
    reset()
  end)

  T.it('does not count as an editor window (Space Q が止まらないこと)', function()
    reset()
    fill(2)
    local w = quickfix.open({ focus = false })
    -- ここが true だと auto_quit の「実編集ウィンドウが残っていない」判定が成立せず、
    -- quickfix を開いている間だけ Space Q での全部閉じが効かなくなる
    T.eq(win_util.is_editor(w), false, 'quickfix は実編集ウィンドウではない')
    T.eq(win_util.is_sidebar(w), true, 'サイドバー扱い')
    reset()
  end)

  T.it('is registered by filetype as well as by window mark', function()
    -- 窓の印(mark_sidebar)と filetype の両方で効くこと。片方だけだと、
    -- :copen や :vimgrep など config.quickfix を経由しない開き方で漏れる
    T.eq(win_util.SIDEBAR_FT.qf, true)
    reset()
    fill(1)
    vim.cmd('botright copen')
    local w = quickfix.win()
    T.eq(win_util.is_editor(w), false, '素の :copen で開いても非エディタ扱い')
    reset()
  end)

  T.it('explains itself instead of opening an empty panel', function()
    reset()
    T.eq(quickfix.size(), 0)
    T.eq(quickfix.toggle(), false, '空なら開かない')
    T.eq(quickfix.is_open(), false)
  end)

  T.it('ignores a location list window', function()
    reset()
    -- location list も buftype は quickfix。取り違えると別窓を閉じてしまう
    vim.fn.setloclist(0, { { filename = vim.fn.tempname(), lnum = 1, text = 'loc' } })
    vim.cmd('lopen')
    T.eq(quickfix.is_open(), false, 'location list は quickfix ではない')
    T.eq(quickfix.close(), false)
    vim.cmd('lclose')
    reset()
  end)

  T.it('is reachable from the Space l mapping', function()
    reset()
    fill(2)
    feed(' l')
    T.eq(quickfix.is_open(), true, 'Space l で開く')
    feed(' l')
    T.eq(quickfix.is_open(), false, 'Space l で閉じる')
    reset()
  end)
end)

T.summary()
