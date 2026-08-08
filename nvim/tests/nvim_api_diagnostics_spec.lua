local T = dofile(TESTS_DIR .. '/helpers.lua')
local diagnostics = require('config.nvim_api.diagnostics')

local S = vim.diagnostic.severity
local ns = vim.api.nvim_create_namespace('nvim_api_diagnostics_spec')

-- root 配下に実ファイルを作ってバッファに載せ、そこへ診断を差し込む。
-- パスは両辺とも同じ作り方(normalize -> :p)で組み立てる(CLAUDE.md のパス規約)。
local function with_files(files, fn)
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  local bufs = {}
  for name, lines in pairs(files) do
    local path = vim.fs.normalize(root .. '/' .. name)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile(lines, path)
    local b = vim.fn.bufadd(path)
    vim.fn.bufload(b)
    bufs[name] = b
  end
  local ok, err = pcall(fn, root, bufs)
  for _, b in pairs(bufs) do
    vim.diagnostic.reset(ns, b)
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

local function diag(lnum, col, severity, message, source)
  return {
    lnum = lnum, col = col, end_lnum = lnum, end_col = col + 1,
    severity = severity, message = message, source = source,
  }
end

T.describe('nvim_api/diagnostics.lua', function()
  T.it('maps severity names to a minimum threshold', function()
    T.eq(diagnostics.min_severity('error'), S.ERROR)
    T.eq(diagnostics.min_severity('WARN'), S.WARN)
    T.eq(diagnostics.min_severity('warning'), S.WARN)
    T.eq(diagnostics.min_severity(nil), S.HINT)   -- 既定はすべて
    T.eq(diagnostics.min_severity(''), S.HINT)
    T.eq(diagnostics.min_severity('nonsense'), S.HINT)
  end)

  T.it('collects diagnostics as 1-based, repo-relative items', function()
    with_files({ ['a.lua'] = { 'local x = 1', 'return x' } }, function(root, bufs)
      vim.diagnostic.set(ns, bufs['a.lua'], {
        diag(0, 6, S.ERROR, 'unused variable', 'lua_ls'),
      })
      local items = diagnostics.collect({ root = root })
      T.eq(#items, 1)
      T.eq(items[1].file, 'a.lua')       -- root 相対
      T.eq(items[1].line, 1)             -- 診断は 0-based なので +1
      T.eq(items[1].col, 7)
      T.eq(items[1].severity, 'error')
      T.eq(items[1].message, 'unused variable')
      T.eq(items[1].source, 'lua_ls')
    end)
  end)

  T.it('flattens multi-line messages onto one line', function()
    with_files({ ['a.lua'] = { 'x' } }, function(root, bufs)
      vim.diagnostic.set(ns, bufs['a.lua'], {
        diag(0, 0, S.WARN, 'first line\n  second line', 'test'),
      })
      local items = diagnostics.collect({ root = root })
      T.eq(items[1].message, 'first line second line')
    end)
  end)

  T.it('filters by severity and by file', function()
    with_files({ ['a.lua'] = { 'x' }, ['b.lua'] = { 'y' } }, function(root, bufs)
      vim.diagnostic.set(ns, bufs['a.lua'], {
        diag(0, 0, S.ERROR, 'boom'),
        diag(0, 1, S.HINT, 'nit'),
      })
      vim.diagnostic.set(ns, bufs['b.lua'], { diag(0, 0, S.WARN, 'careful') })

      T.eq(#diagnostics.collect({ root = root }), 3)
      T.eq(#diagnostics.collect({ root = root, severity = 'warn' }), 2)  -- error + warn
      T.eq(#diagnostics.collect({ root = root, severity = 'error' }), 1)

      local only_a = diagnostics.collect({ root = root, file = 'a.lua' })
      T.eq(#only_a, 2)
      for _, it in ipairs(only_a) do T.eq(it.file, 'a.lua') end

      -- 絶対パスで指定しても同じ結果になること
      local abs = diagnostics.collect({ root = root, file = vim.fs.normalize(root .. '/a.lua') })
      T.eq(#abs, 2)
    end)
  end)

  T.it('sorts by file then line and truncates at max', function()
    with_files({ ['a.lua'] = { 'x', 'y', 'z' }, ['b.lua'] = { 'x' } }, function(root, bufs)
      vim.diagnostic.set(ns, bufs['a.lua'], {
        diag(2, 0, S.ERROR, 'third'),
        diag(0, 0, S.ERROR, 'first'),
      })
      vim.diagnostic.set(ns, bufs['b.lua'], { diag(0, 0, S.ERROR, 'b') })

      local items = diagnostics.collect({ root = root })
      T.eq(items[1].file .. ':' .. items[1].line, 'a.lua:1')
      T.eq(items[2].file .. ':' .. items[2].line, 'a.lua:3')
      T.eq(items[3].file, 'b.lua')

      local cut, truncated = diagnostics.collect({ root = root, max = 2 })
      T.eq(#cut, 2)
      T.eq(truncated, true)
      local all, not_truncated = diagnostics.collect({ root = root, max = 10 })
      T.eq(#all, 3)
      T.eq(not_truncated, false)
    end)
  end)

  T.it('summarizes per file with the worst files first', function()
    with_files({ ['a.lua'] = { 'x' }, ['b.lua'] = { 'y' } }, function(root, bufs)
      vim.diagnostic.set(ns, bufs['a.lua'], { diag(0, 0, S.WARN, 'w') })
      vim.diagnostic.set(ns, bufs['b.lua'], {
        diag(0, 0, S.ERROR, 'e1'),
        diag(0, 1, S.ERROR, 'e2'),
        diag(0, 2, S.HINT, 'h'),
      })
      local summary = diagnostics.summary(diagnostics.collect({ root = root }))
      T.eq(summary.total, 4)
      T.eq(summary.totals.error, 2)
      T.eq(summary.totals.warn, 1)
      T.eq(summary.totals.hint, 1)
      -- error が多いファイルが先頭
      T.eq(summary.files[1].file, 'b.lua')
      T.eq(summary.files[1].error, 2)
      T.eq(summary.files[1].total, 3)
      T.eq(summary.files[2].file, 'a.lua')
    end)
  end)

  T.it('returns an empty list (not an error) when there is nothing', function()
    with_files({ ['a.lua'] = { 'x' } }, function(root)
      local items = diagnostics.collect({ root = root })
      T.eq(items, {})
      local summary = diagnostics.summary(items)
      T.eq(summary.total, 0)
      T.eq(summary.files, {})
    end)
  end)
end)

T.summary()
