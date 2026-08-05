-- config.indent は「開いたファイルの中身からインデント幅を推測する」モジュール。
-- 検証するのは: 行の分類（タブ/スペース/対象外）、増分の多数決による幅の判定、
-- .editorconfig がある場所では検出しないこと、バッファへの適用結果。
local T = dofile(TESTS_DIR .. '/helpers.lua')
local indent = require('config.indent')

T.describe('indent.classify', function()
  T.it('タブ始まりの行は tab', function()
    local kind = indent.classify('\tlocal a = 1')
    T.eq(kind, 'tab')
  end)

  T.it('スペース始まりの行は space と個数', function()
    local kind, width = indent.classify('    local a = 1')
    T.eq(kind, 'space')
    T.eq(width, 4)
  end)

  T.it('空行・空白のみの行・インデント無しの行は対象外', function()
    T.eq(indent.classify(''), nil)
    T.eq(indent.classify('   '), nil)
    T.eq(indent.classify('local a = 1'), nil)
  end)

  T.it('ブロックコメントの継続行（行頭 *）は対象外', function()
    -- JSDoc の ` * foo` を数えると幅 1 や 3 を誤検出するため除外している
    T.eq(indent.classify(' * @param x'), nil)
  end)
end)

T.describe('indent.detect', function()
  T.it('2 スペースのファイルを width=2 / expandtab で検出する', function()
    local result = indent.detect({
      'local M = {}',
      'function M.f()',
      '  if x then',
      '    return 1',
      '  end',
      'end',
    })
    T.eq(result, { expandtab = true, width = 2 })
  end)

  T.it('4 スペースのファイルを width=4 で検出する', function()
    local result = indent.detect({
      'def f():',
      '    if x:',
      '        return 1',
      '    return 2',
    })
    T.eq(result, { expandtab = true, width = 4 })
  end)

  T.it('タブ優勢なら expandtab=false（幅は既定に任せる）', function()
    local result = indent.detect({
      'func main() {',
      '\tif x {',
      '\t\treturn',
      '\t}',
      '}',
    })
    T.eq(result, { expandtab = false })
  end)

  T.it('JSDoc の継続行に引きずられない', function()
    local result = indent.detect({
      '/**',
      ' * @param a',
      ' * @param b',
      ' */',
      'function f(a, b) {',
      '    return a + b;',
      '}',
    })
    T.eq(result, { expandtab = true, width = 4 })
  end)

  T.it('増分が取れないときは最小の正のインデントを使う', function()
    local result = indent.detect({
      'a = {',
      '   x = 1,',
      '   y = 2,',
      '}',
    })
    T.eq(result, { expandtab = true, width = 3 })
  end)

  T.it('判定材料が無ければ nil', function()
    T.eq(indent.detect({ 'a = 1', 'b = 2', '' }), nil)
    T.eq(indent.detect({}), nil)
  end)

  T.it('MAX_WIDTH を超えるインデントは採用しない', function()
    T.eq(indent.detect({ 'a = 1', string.rep(' ', 12) .. 'b = 2' }), nil)
  end)
end)

T.describe('indent.has_editorconfig', function()
  T.it('上位に .editorconfig があれば true', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/sub', 'p')
    T.write_file(dir .. '/.editorconfig', { 'root = true' })
    T.eq(indent.has_editorconfig(dir .. '/sub/a.lua'), true)
    T.rmrf(dir)
  end)

  T.it('無ければ false / 名前無しバッファは false', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.eq(indent.has_editorconfig(dir .. '/a.lua'), false)
    T.eq(indent.has_editorconfig(''), false)
    T.rmrf(dir)
  end)
end)

T.describe('indent.apply', function()
  T.it('ファイルの中身を見てバッファのインデント設定を上書きする', function()
    local dir  = vim.fn.tempname()
    local path = dir .. '/a.lua'
    T.write_file(path, { 'local M = {}', 'function M.f()', '  if x then', '    return 1', '  end', 'end' })

    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    -- 既定値（options.lua 相当）から始めて、検出が上書きすることを見る
    vim.bo[buf].expandtab  = false
    vim.bo[buf].shiftwidth = 8

    local result = indent.apply(buf)
    T.eq(result, { expandtab = true, width = 2 })
    T.eq(vim.bo[buf].expandtab, true)
    T.eq(vim.bo[buf].shiftwidth, 2)
    T.eq(vim.bo[buf].tabstop, 2)
    T.eq(vim.bo[buf].softtabstop, 2)

    vim.api.nvim_buf_delete(buf, { force = true })
    T.rmrf(dir)
  end)

  T.it('.editorconfig がある場所では何もしない（editorconfig を優先）', function()
    local dir  = vim.fn.tempname()
    local path = dir .. '/a.lua'
    T.write_file(dir .. '/.editorconfig', { 'root = true' })
    T.write_file(path, { 'local a = {', '    x = 1,', '}' })

    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    T.eq(indent.apply(buf), nil)

    vim.api.nvim_buf_delete(buf, { force = true })
    T.rmrf(dir)
  end)

  T.it('特殊バッファ（buftype 非空）や無名バッファは対象外', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    T.eq(indent.apply(buf), nil)
    vim.api.nvim_buf_delete(buf, { force = true })

    local unnamed = vim.api.nvim_create_buf(true, false)
    T.eq(indent.apply(unnamed), nil)
    vim.api.nvim_buf_delete(unnamed, { force = true })
  end)
end)

T.summary()
