local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.surround')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function fresh(text, cursor)
  vim.cmd('stopinsert')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
  return buf
end

local function line()
  return vim.api.nvim_get_current_line()
end

-- <leader>s は getchar で囲み文字を待つので、feed では <leader>s の直後に文字を続けて送る
T.describe('surround', function()
  T.it('ノーマル: 閉じ括弧キーで単語をスペース無しで囲む', function()
    fresh('foo', { 1, 0 })
    feed('<leader>s)')
    T.eq(line(), '(foo)')
  end)

  T.it('ノーマル: 開き括弧キーはスペース付きで囲む', function()
    fresh('foo', { 1, 0 })
    feed('<leader>s(')
    T.eq(line(), '( foo )')
  end)

  T.it('ノーマル: クォートで囲む', function()
    fresh('foo', { 1, 0 })
    feed('<leader>s"')
    T.eq(line(), '"foo"')
  end)

  T.it('ノーマル: 既に囲まれていれば外す（トグル）', function()
    fresh('(foo)', { 1, 2 })
    feed('<leader>s)')
    T.eq(line(), 'foo')
  end)

  T.it('ノーマル: スペース付きの囲みも外せる', function()
    fresh('( foo )', { 1, 3 })
    feed('<leader>s(')
    T.eq(line(), 'foo')
  end)

  T.it('ノーマル: Esc で受付を抜けると何もしない', function()
    fresh('foo', { 1, 0 })
    feed('<leader>s<Esc>')
    T.eq(line(), 'foo')
  end)

  T.it('ビジュアル: 選択範囲を囲む', function()
    fresh('bar', { 1, 0 })
    feed('vll<leader>s)')
    T.eq(line(), '(bar)')
  end)

  T.it('ビジュアル: 既に囲まれた選択を外す（トグル）', function()
    fresh('(bar)', { 1, 1 })
    feed('vll<leader>s)')
    T.eq(line(), 'bar')
  end)

  T.it('ビジュアル: 日本語(マルチバイト)を含む選択でもバイトが壊れない', function()
    fresh('群。', { 1, 0 })
    feed('vl<leader>s"') -- 群。 を選択して "" で囲む
    T.eq(line(), '"群。"')
  end)

  T.it('ビジュアル: 日本語の囲みを外す（トグル）', function()
    fresh('"群。"', { 1, 1 }) -- 群 から
    feed('vl<leader>s"')
    T.eq(line(), '群。')
  end)
end)

T.summary()
