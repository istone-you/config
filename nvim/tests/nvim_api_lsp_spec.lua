local T = dofile(TESTS_DIR .. '/helpers.lua')
local lsp = require('config.nvim_api.lsp')
local util = require('config.nvim_api.util')

-- 実際の言語サーバは headless では起動しないので、LSP から返ってくる生ペイロードを
-- 手で組んで整形部分を検証する。ここが AI に見える形そのものなので、崩れると効き目が落ちる。
local function with_root(fn)
  local root = util.real(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  vim.fn.writefile({ 'local M = {}', 'function M.open() end', 'return M' }, root .. '/a.lua')
  vim.fn.writefile({ 'require("a").open()' }, root .. '/b.lua')
  local ok, err = pcall(fn, root)
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

-- 非同期版を同期的に待つテスト用ラッパー
local function prepare(body, root)
  local bufnr, params, err, done = nil, nil, nil, false
  lsp.prepare_async(body, root, function(b, p, e)
    bufnr, params, err, done = b, p, e, true
  end)
  vim.wait(5000, function() return done end, 10)
  return bufnr, params, err
end

local function request(bufnr, method, params, timeout_ms)
  local results, err, done = nil, nil, false
  lsp.request_async(bufnr, method, params, timeout_ms, function(r, e)
    results, err, done = r, e, true
  end)
  vim.wait(5000, function() return done end, 10)
  return results, err
end

local function range(l1, c1, l2, c2)
  return { start = { line = l1, character = c1 }, ['end'] = { line = l2, character = c2 } }
end

T.describe('nvim_api/lsp.lua', function()
  T.it('converts a byte column to a UTF-16 offset', function()
    -- LSP の character は UTF-16 単位。日本語を含む行でズレると別の場所を指す
    T.eq(lsp.utf_col('abc', 1), 0)          -- 1-based の 1 桁目 -> 0
    T.eq(lsp.utf_col('abc', 3), 2)
    -- 全角は 1 文字 3 バイト。7 バイト目(=「う」の先頭)の手前は 2 文字ぶん
    T.eq(lsp.utf_col('あいう', 7), 2)
    T.eq(lsp.utf_col('あいう', 4), 1)
    T.eq(lsp.utf_col('あいう', 10), 3)         -- 行末(9 バイト)の次
    T.eq(lsp.utf_col('あいう', 7, 'utf-8'), 6) -- utf-8 サーバならバイトのまま
    T.eq(lsp.utf_col(nil, 5), 0)
    T.eq(lsp.utf_col('abc', 0), 0)
  end)

  T.it('builds 0-based position params from 1-based input', function()
    with_root(function(root)
      local bufnr = vim.fn.bufadd(root .. '/a.lua')
      vim.fn.bufload(bufnr)
      local params = lsp.position_params(bufnr, 2, 10)
      T.eq(params.position.line, 1)      -- 2 行目 -> 0-based の 1
      T.eq(params.position.character, 9)
      T.contains(params.textDocument.uri, 'a.lua')
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
  end)

  T.it('normalizes Location and LocationLink into one shape', function()
    with_root(function(root)
      local results = {
        { -- Location[]
          { uri = vim.uri_from_fname(root .. '/a.lua'), range = range(1, 9, 1, 15) },
        },
        { -- LocationLink[]
          {
            targetUri = vim.uri_from_fname(root .. '/b.lua'),
            targetSelectionRange = range(0, 13, 0, 17),
            targetRange = range(0, 0, 0, 20),
          },
        },
      }
      local locs = lsp.format_locations(results, root)
      T.eq(#locs, 2)
      T.eq(locs[1].file, 'a.lua')
      T.eq(locs[1].line, 2)   -- 0-based -> 1-based
      T.eq(locs[1].col, 10)
      T.eq(locs[1].text, 'function M.open() end') -- 行テキストを添える
      T.eq(locs[2].file, 'b.lua')
      T.eq(locs[2].line, 1)
      T.eq(locs[2].col, 14)   -- targetSelectionRange の方を採る
    end)
  end)

  T.it('accepts a bare Location (not wrapped in an array)', function()
    with_root(function(root)
      local locs = lsp.format_locations(
        { { uri = vim.uri_from_fname(root .. '/a.lua'), range = range(0, 0, 0, 5) } }, root)
      T.eq(#locs, 1)
      T.eq(locs[1].line, 1)
    end)
  end)

  T.it('dedupes identical locations from multiple clients and sorts them', function()
    with_root(function(root)
      local one = { uri = vim.uri_from_fname(root .. '/b.lua'), range = range(0, 0, 0, 1) }
      local two = { uri = vim.uri_from_fname(root .. '/a.lua'), range = range(2, 0, 2, 1) }
      -- 2 つのクライアントが同じ定義を返すことがある
      local locs = lsp.format_locations({ { one, two }, { one } }, root)
      T.eq(#locs, 2)
      T.eq(locs[1].file, 'a.lua') -- ファイル名順
      T.eq(locs[2].file, 'b.lua')
    end)
  end)

  T.it('returns an empty list for a null result', function()
    with_root(function(root)
      T.eq(lsp.format_locations({}, root), {})
      T.eq(lsp.format_locations({ vim.NIL }, root), {})
    end)
  end)

  T.it('flattens hierarchical DocumentSymbols with a container path', function()
    with_root(function(root)
      local results = { {
        {
          name = 'M', kind = vim.lsp.protocol.SymbolKind.Module,
          range = range(0, 0, 2, 0), selectionRange = range(0, 6, 0, 7),
          children = {
            {
              name = 'open', kind = vim.lsp.protocol.SymbolKind.Function,
              detail = 'function M.open()',
              range = range(1, 0, 1, 21), selectionRange = range(1, 11, 1, 15),
            },
          },
        },
      } }
      local symbols = lsp.flatten_symbols(results, root)
      T.eq(#symbols, 2)
      T.eq(symbols[1].name, 'M')
      T.eq(symbols[1].kind, 'Module')
      T.eq(symbols[1].container, vim.NIL)
      T.eq(symbols[1].line, 1)
      T.eq(symbols[2].name, 'open')
      T.eq(symbols[2].kind, 'Function')
      T.eq(symbols[2].container, 'M')  -- 親をたどれる
      T.eq(symbols[2].detail, 'function M.open()')
      T.eq(symbols[2].line, 2)
    end)
  end)

  T.it('flattens SymbolInformation (workspace symbols) with a file', function()
    with_root(function(root)
      local results = { {
        {
          name = 'open',
          kind = vim.lsp.protocol.SymbolKind.Function,
          containerName = 'M',
          location = { uri = vim.uri_from_fname(root .. '/a.lua'), range = range(1, 11, 1, 15) },
        },
      } }
      local symbols = lsp.flatten_symbols(results, root)
      T.eq(#symbols, 1)
      T.eq(symbols[1].name, 'open')
      T.eq(symbols[1].file, 'a.lua')
      T.eq(symbols[1].container, 'M')
      T.eq(symbols[1].line, 2)
      T.eq(symbols[1].col, 12)
    end)
  end)

  T.it('renders hover contents as plain markdown', function()
    T.eq(lsp.hover_text({ { contents = { kind = 'markdown', value = '```lua\nfunction M.open()\n```' } } }),
      '```lua\nfunction M.open()\n```')
    T.contains(lsp.hover_text({ { contents = 'ただの文字列' } }), 'ただの文字列')
    T.eq(lsp.hover_text({}), nil)
    T.eq(lsp.hover_text({ vim.NIL }), nil)
    T.eq(lsp.hover_text({ { contents = { kind = 'markdown', value = '' } } }), nil)
  end)

  T.it('lists code actions without applying them', function()
    local actions = lsp.format_code_actions({
      { { title = '未使用の import を削除', kind = 'quickfix', isPreferred = true } },
      { { title = '関数に切り出す', kind = 'refactor.extract' }, { notAnAction = true } },
    })
    T.eq(#actions, 2)
    T.eq(actions[1].title, '未使用の import を削除')
    T.eq(actions[1].kind, 'quickfix')
    T.eq(actions[1].preferred, true)
    T.eq(actions[2].preferred, false)
  end)

  T.it('rejects bad targets before touching the LSP', function()
    with_root(function(root)
      local _, _, err = prepare({ line = 1 }, root)
      T.contains(err, 'file is required')
      local _, _, err2 = prepare({ file = 'a.lua' }, root)
      T.contains(err2, 'line must be a positive integer')
      local _, _, err3 = prepare({ file = 'a.lua', line = 0 }, root)
      T.contains(err3, 'line must be a positive integer')
      local _, _, err4 = prepare({ file = 'missing.lua', line = 1 }, root)
      T.contains(err4, 'file not readable')
    end)
  end)

  T.it('reports a clear error when no language server is attached', function()
    with_root(function(root)
      -- headless では lua_ls は起動しない。空を返すのではなく理由を返すこと
      local bufnr = vim.fn.bufadd(root .. '/a.lua')
      vim.fn.bufload(bufnr)
      local results, err = request(bufnr, 'textDocument/definition', {})
      T.eq(results, nil)
      T.contains(err, 'no LSP client attached')
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
  end)
end)

T.summary()
