local T = dofile(TESTS_DIR .. '/helpers.lua')
local qflist = require('config.nvim_api.qflist')
local util = require('config.nvim_api.util')

local function with_root(fn)
  local root = util.real(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  vim.fn.writefile({ 'line one', 'line two' }, root .. '/a.lua')
  vim.fn.writefile({ 'x' }, root .. '/b.lua')
  local ok, err = pcall(fn, root)
  qflist.clear()
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

T.describe('nvim_api/qflist.lua', function()
  T.it('builds quickfix items from repo-relative paths', function()
    with_root(function(root)
      local items = qflist.build_items({
        { file = 'a.lua', line = 2, col = 3, text = 'ここが移行漏れ', severity = 'error' },
        { file = 'b.lua', text = 'デフォルトは 1 行目 1 桁' },
      }, root)
      T.eq(#items, 2)
      T.eq(items[1].filename, root .. '/a.lua')
      T.eq(items[1].lnum, 2)
      T.eq(items[1].col, 3)
      T.eq(items[1].text, 'ここが移行漏れ')
      T.eq(items[1].type, 'E')
      T.eq(items[2].lnum, 1)
      T.eq(items[2].col, 1)
      T.eq(items[2].type, '')
    end)
  end)

  T.it('drops entries without a file instead of failing the whole request', function()
    with_root(function(root)
      local items = qflist.build_items({
        { file = 'a.lua', line = 1 },
        { line = 5, text = 'file 無し' },
        { file = '', text = '空文字' },
        'ゴミ',
      }, root)
      T.eq(#items, 1)
    end)
  end)

  T.it('maps severity names to quickfix types', function()
    with_root(function(root)
      local items = qflist.build_items({
        { file = 'a.lua', severity = 'error' },
        { file = 'a.lua', severity = 'WARNING' },
        { file = 'a.lua', severity = 'info' },
        { file = 'a.lua', severity = 'hint' },
        { file = 'a.lua', severity = 'なにか' },
      }, root)
      T.eq(items[1].type, 'E')
      T.eq(items[2].type, 'W')
      T.eq(items[3].type, 'I')
      T.eq(items[4].type, 'N')
      T.eq(items[5].type, '')
    end)
  end)

  T.it('sets the list and reads it back repo-relative', function()
    with_root(function(root)
      local n = qflist.set({
        title = '移行漏れ',
        open = false,
        items = {
          { file = 'a.lua', line = 2, col = 1, text = 'ここ', severity = 'warn' },
          { file = 'b.lua', line = 1, col = 1, text = 'あそこ' },
        },
      }, root)
      T.eq(n, 2)
      local got = qflist.get(root)
      T.eq(got.title, '移行漏れ')
      T.eq(got.size, 2)
      T.eq(got.items[1].file, 'a.lua')
      T.eq(got.items[1].line, 2)
      T.eq(got.items[1].text, 'ここ')
      T.eq(got.items[1].type, 'W')
      T.eq(got.items[2].file, 'b.lua')
    end)
  end)

  T.it('opens the quickfix window but leaves the cursor where it was', function()
    with_root(function(root)
      local before = vim.api.nvim_get_current_win()
      qflist.set({ title = 'x', open = true, items = { { file = 'a.lua', line = 1 } } }, root)
      T.eq(vim.api.nvim_get_current_win(), before, 'カーソルは元のウィンドウに残る')
      local has_qf = false
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'quickfix' then has_qf = true end
      end
      T.ok(has_qf, 'quickfix ウィンドウが開いている')
    end)
  end)

  T.it('clears the list', function()
    with_root(function(root)
      qflist.set({ open = false, items = { { file = 'a.lua', line = 1 } } }, root)
      T.eq(qflist.get(root).size, 1)
      qflist.clear()
      local got = qflist.get(root)
      T.eq(got.size, 0)
      T.eq(got.items, {})
    end)
  end)

  T.it('does not open the window for an empty item list', function()
    with_root(function(root)
      local n = qflist.set({ title = 'empty', items = {} }, root)
      T.eq(n, 0)
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        T.ok(vim.bo[vim.api.nvim_win_get_buf(w)].buftype ~= 'quickfix', 'quickfix は開かない')
      end
    end)
  end)
end)

T.describe('nvim_api/util.lua', function()
  T.it('normalizes both sides of a path comparison the same way', function()
    local root = util.real(vim.fn.tempname())
    vim.fn.mkdir(root .. '/sub', 'p')
    vim.fn.writefile({ 'x' }, root .. '/sub/a.lua')
    -- 相対でも絶対でも ./ 入りでも同じ絶対パスに落ちる
    T.eq(util.abs_path('sub/a.lua', root), root .. '/sub/a.lua')
    T.eq(util.abs_path(root .. '/sub/a.lua', root), root .. '/sub/a.lua')
    T.eq(util.abs_path('sub/./a.lua', root), root .. '/sub/a.lua')
    -- 往復して元に戻る
    T.eq(util.rel_path(util.abs_path('sub/a.lua', root), root), 'sub/a.lua')
    -- root の外はそのまま絶対で返す
    T.eq(util.rel_path('/etc/hosts', root), util.real('/etc/hosts'))
    vim.fn.delete(root, 'rf')
  end)

  T.it('parses query strings and JSON bodies', function()
    T.eq(util.parse_query('file=a%2Fb.lua&severity=error'), { file = 'a/b.lua', severity = 'error' })
    T.eq(util.parse_query(''), {})
    T.eq(util.decode_body(''), {})
    T.eq(util.decode_body('{"a":1}'), { a = 1 })
    T.eq(util.decode_body('{壊れてる'), nil)
    T.eq(util.decode_body('[1,2]'), { 1, 2 })
  end)

  T.it('reads a line from disk or from a loaded buffer', function()
    local root = util.real(vim.fn.tempname())
    vim.fn.mkdir(root, 'p')
    local path = root .. '/a.lua'
    vim.fn.writefile({ 'first', '  second  ', 'third' }, path)
    T.eq(util.line_text(path, 2), 'second') -- ディスクから、trim される
    T.eq(util.line_text(path, 99), nil)
    T.eq(util.line_text(root .. '/missing.lua', 1), nil)
    vim.fn.delete(root, 'rf')
  end)

  T.it('treats common truthy spellings as true', function()
    T.eq(util.truthy('1', false), true)
    T.eq(util.truthy('true', false), true)
    T.eq(util.truthy('0', true), false)
    T.eq(util.truthy(nil, true), true)
    T.eq(util.truthy(nil, false), false)
    T.eq(util.truthy(false, true), false)
  end)
end)

T.summary()
