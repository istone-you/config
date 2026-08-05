local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.autopairs')

-- headless の feedkeys には 2 つの癖がある（helpers.lua の注記も参照）:
--   ・feedkeys 完了時に insert→normal へ落ち、カーソルが 1 左へ戻る
--     → カーソル位置は数値で見ず「続けて打った文字がどこに入るか」で検証する
--   ・同一 feedkeys 内では直前に入力した"通常文字"が expr 評価時にまだ反映されない
--     （マップが挿入した結果は反映される）
--     → 直前文字が要る条件（エスケープ・単語隣接）は事前にバッファへ置いてから打つ
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function fresh(lines, cursor)
  vim.cmd('stopinsert')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  if lines then vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines) end
  if cursor then vim.api.nvim_win_set_cursor(0, cursor) end
  return buf
end

local function line()
  return vim.api.nvim_get_current_line()
end

T.describe('autopairs', function()
  T.it('開き括弧でペアを補完し、カーソルは内側に入る', function()
    fresh()
    feed('i(x') -- 内側にカーソルがあれば x は括弧の中に入る
    T.eq(line(), '(x)')
  end)

  T.it('[] {} も同様にペア補完する', function()
    fresh()
    feed('i[x')
    T.eq(line(), '[x]')
    fresh()
    feed('i{x')
    T.eq(line(), '{x}')
  end)

  T.it('閉じ括弧を既存の閉じの上で押すと重複せず飛び越す', function()
    fresh()
    feed('i()x') -- ( で (|)、) で飛び越して ()|、x は外側
    T.eq(line(), '()x')
  end)

  T.it('空ペアの内側で <BS> するとペアごと消える', function()
    fresh()
    feed('i(<BS>x') -- ( で (|)、<BS> でペア削除、x だけ残る
    T.eq(line(), 'x')
  end)

  T.it('クォートをペア補完する', function()
    fresh()
    feed('i"x')
    T.eq(line(), '"x"')
  end)

  T.it('単語に隣接するクォートは補完しない', function()
    fresh({ 'foo' }, { 1, 3 })
    feed("a'x") -- 直前 o は事前にバッファへ。o の後なので単独
    T.eq(line(), "foo'x")
  end)

  T.it('直前が \\（エスケープ）なら補完しない', function()
    fresh({ '\\' }, { 1, 1 })
    feed('a(x') -- 直前 \ の後なので単独
    T.eq(line(), '\\(x')
  end)

  T.it('括弧の内側で <CR> するとインデント展開する', function()
    local buf = fresh()
    vim.bo[buf].expandtab  = true
    vim.bo[buf].shiftwidth = 2
    vim.bo[buf].tabstop    = 2
    feed('i{<CR>x') -- 中間のインデント行にカーソル → x は '  x' の位置に入る
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    T.eq(lines, { '{', '  x', '}' }, '3 行に展開し内側はインデント')
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 2, 'カーソルは中間行')
  end)
end)

-- 補完メニュー（config.completion）が出ている間は <CR> を補完側へ譲る
T.describe('autopairs: 補完メニューとの併存', function()
  local function cr_callback()
    for _, m in ipairs(vim.api.nvim_get_keymap('i')) do
      if m.lhs == '<CR>' then return m.callback end
    end
  end

  local function with_pum(selected, fn)
    local orig_pum  = vim.fn.pumvisible
    local orig_info = vim.fn.complete_info
    vim.fn.pumvisible    = function() return 1 end
    vim.fn.complete_info = function() return { selected = selected } end
    local result = fn()
    vim.fn.pumvisible    = orig_pum
    vim.fn.complete_info = orig_info
    return result
  end

  T.it('候補を選んでいれば <CR> は確定（<C-y>）になる', function()
    fresh({ '' }, { 1, 0 })
    T.eq(with_pum(0, cr_callback()), '<C-y>')
  end)

  T.it('候補未選択ならメニューを閉じて通常の <CR> へ進む', function()
    fresh({ '' }, { 1, 0 })
    T.eq(with_pum(-1, cr_callback()), '<C-e><CR>')
  end)

  T.it('候補未選択かつ括弧の内側なら、メニューを閉じてから展開する', function()
    fresh({ '{}' }, { 1, 1 })
    T.contains(with_pum(-1, cr_callback()), '_expand_cr')
  end)
end)

T.summary()
