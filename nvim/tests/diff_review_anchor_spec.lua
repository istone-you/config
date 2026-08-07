local T = dofile(TESTS_DIR .. '/helpers.lua')
local anchor = require('config.diff_review.anchor')
local diff = require('config.diff_review.diff')

-- 新ファイル(全行 add)の unified diff を作るヘルパ。new 側の行番号 = 1..#lines。
local function added_file_model(path, lines)
  local parts = {
    'diff --git a/' .. path .. ' b/' .. path,
    'new file mode 100644',
    '--- /dev/null',
    '+++ b/' .. path,
    '@@ -0,0 +1,' .. #lines .. ' @@',
  }
  for _, l in ipairs(lines) do parts[#parts + 1] = '+' .. l end
  return diff.parse(table.concat(parts, '\n'))
end

T.describe('diff_review/anchor.lua', function()
  T.it('captures the line text plus surrounding context', function()
    local m = added_file_model('a.lua', { 'one', 'two', 'three', 'four', 'five' })
    local a = anchor.capture(m, 'a.lua', 'new', 3)
    T.eq(a.text, 'three')
    T.eq(a.before, { 'one', 'two' })
    T.eq(a.after, { 'four', 'five' })
  end)

  T.it('keeps position when the line is unchanged', function()
    local m = added_file_model('a.lua', { 'one', 'two', 'three' })
    local c = { file = 'a.lua', side = 'new', line = 2, line_end = vim.NIL,
      anchor = anchor.capture(m, 'a.lua', 'new', 2), outdated = false }
    anchor.reanchor(c, m)
    T.eq(c.line, 2)
    T.eq(c.outdated, false)
  end)

  T.it('follows the line when content shifts down (lines inserted above)', function()
    local m0 = added_file_model('a.lua', { 'alpha', 'beta', 'gamma' })
    local c = { file = 'a.lua', side = 'new', line = 2, line_end = vim.NIL,
      anchor = anchor.capture(m0, 'a.lua', 'new', 2), outdated = false } -- anchored to 'beta'
    -- 2 行上に挿入 → 'beta' は 4 行目へ
    local m1 = added_file_model('a.lua', { 'x', 'y', 'alpha', 'beta', 'gamma' })
    anchor.reanchor(c, m1)
    T.eq(c.line, 4, 'comment follows beta to its new line')
    T.eq(c.outdated, false)
  end)

  T.it('disambiguates duplicate lines by surrounding context', function()
    local m0 = added_file_model('a.lua', { 'ctxA', 'dup', 'ctxB', 'filler', 'dup', 'ctxC' })
    -- 2 個ある 'dup' のうち、後ろ(5行目、前後 filler/ctxC)にアンカー
    local c = { file = 'a.lua', side = 'new', line = 5, line_end = vim.NIL,
      anchor = anchor.capture(m0, 'a.lua', 'new', 5), outdated = false }
    -- 先頭に1行挿入 → 後ろの dup は 6 行目へ、前の dup は 3 行目へ
    local m1 = added_file_model('a.lua', { 'head', 'ctxA', 'dup', 'ctxB', 'filler', 'dup', 'ctxC' })
    anchor.reanchor(c, m1)
    T.eq(c.line, 6, 'context picks the correct duplicate (the one next to filler/ctxC)')
  end)

  T.it('marks outdated when the line no longer exists', function()
    local m0 = added_file_model('a.lua', { 'keep', 'removed', 'keep2' })
    local c = { file = 'a.lua', side = 'new', line = 2, line_end = vim.NIL,
      anchor = anchor.capture(m0, 'a.lua', 'new', 2), outdated = false } -- 'removed'
    local m1 = added_file_model('a.lua', { 'keep', 'keep2' }) -- 'removed' が消えた
    anchor.reanchor(c, m1)
    T.eq(c.outdated, true)
    T.eq(c.line, 2, 'outdated comment keeps its last-known line')
  end)

  T.it('marks outdated when the whole file is gone from the diff', function()
    local m0 = added_file_model('a.lua', { 'x' })
    local c = { file = 'a.lua', side = 'new', line = 1, line_end = vim.NIL,
      anchor = anchor.capture(m0, 'a.lua', 'new', 1), outdated = false }
    anchor.reanchor(c, { files = {} })
    T.eq(c.outdated, true)
  end)

  T.it('shifts a range comment as a block', function()
    local m0 = added_file_model('a.lua', { 'p', 'q', 'r', 's' })
    local c = { file = 'a.lua', side = 'new', line = 2, line_end = 3,
      anchor = anchor.capture(m0, 'a.lua', 'new', 2), outdated = false } -- q..r
    local m1 = added_file_model('a.lua', { 'ins', 'p', 'q', 'r', 's' })
    anchor.reanchor(c, m1)
    T.eq(c.line, 3)
    T.eq(c.line_end, 4, 'range end shifts by the same delta')
  end)
end)

T.summary()
