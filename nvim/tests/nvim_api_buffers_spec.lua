local T = dofile(TESTS_DIR .. '/helpers.lua')
local buffers = require('config.nvim_api.buffers')
local util = require('config.nvim_api.util')

-- 非同期版を同期的に待つテスト用ラッパー(本番の経路はメインループを塞がない)
local function ensure_loaded(file, root, timeout_ms)
  local bufnr, err, done = nil, nil, false
  buffers.ensure_loaded_async(file, root, timeout_ms, function(b, e)
    bufnr, err, done = b, e, true
  end)
  vim.wait(5000, function() return done end, 10)
  return bufnr, err
end

local function load_many(files, root, timeout_ms)
  local loaded, failed, done = nil, nil, false
  buffers.load_many_async(files, root, timeout_ms, function(l, f)
    loaded, failed, done = l, f, true
  end)
  vim.wait(5000, function() return done end, 10)
  return loaded, failed
end

local function with_root(fn)
  local root = util.real(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  vim.fn.writefile({ 'local M = {}', 'return M' }, root .. '/a.lua')
  vim.fn.writefile({ 'x = 1' }, root .. '/b.lua')
  local opened = {}
  local ok, err = pcall(fn, root, opened)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= '' and name:sub(1, #root) == root then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

T.describe('nvim_api/buffers.lua', function()
  T.it('loads a file that was never opened', function()
    with_root(function(root)
      -- LSP は「まだ開いていないファイル」を知らない。問い合わせ前に必ずここを通す
      local bufnr, err = ensure_loaded('a.lua', root, 50)
      T.ok(bufnr, err)
      T.ok(vim.api.nvim_buf_is_loaded(bufnr), 'バッファが読み込まれている')
      T.eq(util.real(vim.api.nvim_buf_get_name(bufnr)), root .. '/a.lua')
      T.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { 'local M = {}', 'return M' })
    end)
  end)

  T.it('accepts an absolute path too', function()
    with_root(function(root)
      local bufnr = ensure_loaded(root .. '/b.lua', root, 50)
      T.ok(bufnr)
      T.eq(util.real(vim.api.nvim_buf_get_name(bufnr)), root .. '/b.lua')
    end)
  end)

  T.it('reports a readable error instead of silently returning nothing', function()
    with_root(function(root)
      local bufnr, err = ensure_loaded('missing.lua', root, 50)
      T.eq(bufnr, nil)
      T.contains(err, 'file not readable')
      local bufnr2, err2 = ensure_loaded('', root, 50)
      T.eq(bufnr2, nil)
      T.contains(err2, 'file is required')
    end)
  end)

  T.it('survives a non-numeric timeout instead of spinning forever', function()
    with_root(function(root)
      -- AI が投げてくる JSON はどんな型でも来る。ここを素通しすると、ポーリングの比較が
      -- 毎 tick 例外になり、コールバックにもタイマーの close にも到達しないループになる。
      for _, bad in ipairs({ 'x', -1, {} }) do
        local done, bufnr = false, nil
        buffers.ensure_loaded_async('a.lua', root, bad, function(b) bufnr, done = b, true end)
        vim.wait(5000, function() return done end, 10)
        T.ok(done, 'timeout_ms=' .. vim.inspect(bad) .. ' でもコールバックが来る')
        T.ok(bufnr, 'バッファは返る')
      end
    end)
  end)

  T.it('refuses paths outside the repository root', function()
    with_root(function(root)
      -- ローカルの AI から叩かれる前提なので、リポジトリ外を読ませる抜け道を作らない
      local _, err = ensure_loaded('/etc/hosts', root, 50)
      T.contains(err, 'outside the repository root')
      local _, err2 = ensure_loaded('../../../../etc/hosts', root, 50)
      T.contains(err2, 'outside the repository root')

      -- 明示的に許可したときだけ通る
      vim.g.nvim_api_allow_outside_root = true
      local bufnr = ensure_loaded('/etc/hosts', root, 50)
      vim.g.nvim_api_allow_outside_root = nil
      T.ok(bufnr, '解除すればリポジトリ外も開ける')
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
  end)

  T.it('picks up an external edit via checktime', function()
    with_root(function(root)
      local bufnr = ensure_loaded('a.lua', root, 50)
      -- AI がディスクを直接書き換えた状況。読み直さないと古い内容のままになる
      vim.fn.writefile({ 'local M = {}', 'M.added = true', 'return M' }, root .. '/a.lua')
      buffers.checktime(bufnr)
      T.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
        { 'local M = {}', 'M.added = true', 'return M' })
    end)
  end)

  T.it('never discards unsaved local edits', function()
    with_root(function(root)
      local bufnr = ensure_loaded('b.lua', root, 50)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '編集中の内容' })
      T.eq(vim.bo[bufnr].modified, true)
      vim.fn.writefile({ 'ディスク側が変わった' }, root .. '/b.lua')
      buffers.checktime()
      -- modified なバッファは対象外(勝手に上書きしない)
      T.eq(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { '編集中の内容' })
      vim.bo[bufnr].modified = false
    end)
  end)

  T.it('lists loaded file buffers with their LSP clients', function()
    with_root(function(root)
      ensure_loaded('a.lua', root, 50)
      ensure_loaded('b.lua', root, 50)
      local list = buffers.list(root)
      local files = {}
      for _, b in ipairs(list) do files[b.file] = b end
      T.ok(files['a.lua'], 'a.lua が一覧に出る')
      T.ok(files['b.lua'], 'b.lua が一覧に出る')
      T.eq(files['a.lua'].lines, 2)
      T.eq(files['a.lua'].modified, false)
      T.eq(files['a.lua'].lsp, {}) -- headless では言語サーバは付かない
    end)
  end)

  T.it('loads many files and separates the failures', function()
    with_root(function(root)
      local loaded, failed = load_many({ 'a.lua', 'missing.lua', 'b.lua' }, root, 50)
      T.eq(#loaded, 2)
      T.eq(#failed, 1)
      T.eq(failed[1].file, 'missing.lua')
      T.contains(failed[1].error, 'file not readable')
      T.eq(loaded[1].file, 'a.lua')
    end)
  end)
end)

T.summary()
