local T = dofile(TESTS_DIR .. '/helpers.lua')
local registry = require('config.diff_review.registry')

-- registry.path() を一時ファイルへ差し替えて隔離する(read/write/register は M.path() 経由)。
local function with_tmp_registry(fn)
  local orig = registry.path
  local tmp = vim.fs.normalize(vim.fn.tempname() .. '/sessions.json')
  registry.path = function() return tmp end
  local ok, err = pcall(fn, tmp)
  registry.path = orig
  vim.fn.delete(vim.fn.fnamemodify(tmp, ':h'), 'rf')
  if not ok then error(err) end
end

T.describe('diff_review/registry.lua', function()
  T.it('registers a session and reads it back', function()
    with_tmp_registry(function()
      local entry = registry.register('/app', 7325)
      T.eq(entry.repoRoot, '/app')
      T.eq(entry.port, 7325)
      T.eq(entry.pid, vim.fn.getpid())
      local list = registry.read()
      T.eq(#list, 1)
      T.eq(list[1].repoRoot, '/app')
      T.eq(list[1].port, 7325)
    end)
  end)

  T.it('keeps one entry per nvim process (re-register replaces)', function()
    with_tmp_registry(function()
      -- 1 nvim = 1 レビューサーバなので、同じ pid の再登録は常に置き換え(2件にならない)
      registry.register('/app', 7325)
      registry.register('/app', 7325)
      T.eq(#registry.read(), 1)
      registry.register('/other', 7400)
      local list = registry.read()
      T.eq(#list, 1)
      T.eq(list[1].repoRoot, '/other')
      T.eq(list[1].port, 7400)
    end)
  end)

  T.it('keeps sessions from other live pids', function()
    with_tmp_registry(function()
      -- 別 nvim(生きている別 pid)のエントリは残したまま自分のを足す。
      -- 親プロセス(同一ユーザーなのでシグナル0が通る)を「生きている別 pid」として使う。
      local uv = vim.uv or vim.loop
      local other_pid = uv.os_getppid()
      registry.write({ { repoRoot = '/other', port = 7400, pid = other_pid, startedAt = 1 } })
      registry.register('/app', 7325)
      T.eq(#registry.read(), 2)
    end)
  end)

  T.it('prunes entries whose pid is dead', function()
    with_tmp_registry(function()
      -- 生きている自分の pid と、ほぼ確実に存在しない pid を混在させる
      registry.write({
        { repoRoot = '/app', port = 7325, pid = vim.fn.getpid(), startedAt = 1 },
        { repoRoot = '/dead', port = 7401, pid = 2147480000, startedAt = 1 },
      })
      local pruned = registry.prune(registry.read())
      T.eq(#pruned, 1)
      T.eq(pruned[1].repoRoot, '/app')
    end)
  end)

  T.it('unregisters this session by port', function()
    with_tmp_registry(function()
      registry.register('/app', 7325)
      registry.unregister(7325)
      T.eq(#registry.read(), 0)
    end)
  end)

  T.it('returns an empty list when the file is missing', function()
    with_tmp_registry(function()
      T.eq(registry.read(), {})
    end)
  end)

  T.it('writes an empty array (not object) when no sessions remain', function()
    with_tmp_registry(function(tmp)
      registry.write({})
      local content = table.concat(vim.fn.readfile(tmp), '\n')
      T.eq(content, '[]')
    end)
  end)
end)

T.summary()
