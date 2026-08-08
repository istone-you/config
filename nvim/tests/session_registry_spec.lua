local T = dofile(TESTS_DIR .. '/helpers.lua')
local session_registry = require('config.util.session_registry')

-- R.path() を一時ファイルへ差し替えて隔離する(read/write/register は R.path() 経由)。
local function with_tmp(fn)
  local R = session_registry.new('test-ns')
  local tmp = vim.fs.normalize(vim.fn.tempname() .. '/sessions.json')
  R.path = function() return tmp end
  local ok, err = pcall(fn, R, tmp)
  vim.fn.delete(vim.fn.fnamemodify(tmp, ':h'), 'rf')
  if not ok then error(err) end
end

T.describe('util/session_registry.lua', function()
  T.it('namespaces the registry file under the cache dir', function()
    local R = session_registry.new('nvim-api')
    T.contains(R.path(), '/nvim-api/sessions.json')
    -- diff_review 側は従来のパスのままであること(skill の解決規則を壊さない)
    T.contains(require('config.diff_review.registry').path(), '/diff-review/sessions.json')
  end)

  T.it('keeps sessions from other live pids on the same repo', function()
    with_tmp(function(R)
      -- 同じリポジトリを 2 つの nvim で開くのは普通にある。片方の登録が消えてはいけない
      -- (これが元の diff_review/registry.lua のバグだった)。
      local uv = vim.uv or vim.loop
      local other_pid = uv.os_getppid()
      R.write({ { repoRoot = '/app', port = 45001, pid = other_pid, startedAt = 1 } })
      R.register('/app', 45002)
      local list = R.read()
      T.eq(#list, 2)
      local ports = {}
      for _, e in ipairs(list) do ports[e.port] = e.repoRoot end
      T.eq(ports[45001], '/app')
      T.eq(ports[45002], '/app')
    end)
  end)

  T.it('puts the newest entry first so a naive head -1 gets it', function()
    with_tmp(function(R)
      -- 外部(skill の jq)が素朴に先頭を取っても最新セッションに当たること。
      -- repoRoot で上書きしていた頃の実効挙動を、多重セッションを保ったまま維持する。
      local uv = vim.uv or vim.loop
      R.write({ { repoRoot = '/app', port = 8000, pid = uv.os_getppid(), startedAt = 1 } })
      R.register('/app', 45002)
      local list = R.read()
      T.eq(#list, 2)
      T.eq(list[1].port, 45002, '新しい方が先頭')
      T.eq(list[2].port, 8000)
    end)
  end)

  T.it('replaces this pid entry (1 nvim = 1 server per namespace)', function()
    with_tmp(function(R)
      R.register('/app', 45001)
      R.register('/app', 45002)
      local list = R.read()
      T.eq(#list, 1)
      T.eq(list[1].port, 45002)
    end)
  end)

  T.it('drops a stale entry that squats the same port', function()
    with_tmp(function(R)
      local uv = vim.uv or vim.loop
      R.write({ { repoRoot = '/other', port = 45001, pid = uv.os_getppid(), startedAt = 1 } })
      R.register('/app', 45001)
      local list = R.read()
      T.eq(#list, 1)
      T.eq(list[1].repoRoot, '/app')
    end)
  end)

  T.it('stores extra fields given at register time', function()
    with_tmp(function(R)
      local entry = R.register('/app', 45001, { cwd = '/app/web' })
      T.eq(entry.cwd, '/app/web')
      T.eq(R.read()[1].cwd, '/app/web')
    end)
  end)

  T.it('prunes dead pids and finds by repo, newest first', function()
    with_tmp(function(R)
      local uv = vim.uv or vim.loop
      R.write({
        { repoRoot = '/app', port = 45001, pid = uv.os_getppid(), startedAt = 10 },
        { repoRoot = '/app', port = 45002, pid = vim.fn.getpid(), startedAt = 20 },
        { repoRoot = '/app', port = 45003, pid = 2147480000, startedAt = 30 },
        { repoRoot = '/zzz', port = 45004, pid = vim.fn.getpid(), startedAt = 40 },
      })
      local found = R.find('/app')
      T.eq(#found, 2)
      T.eq(found[1].port, 45002) -- startedAt の新しい順
      T.eq(found[2].port, 45001)
      T.eq(#R.find(), 3) -- repo 指定なしなら死んだ pid を除いた全部
    end)
  end)

  T.it('unregisters this session by port', function()
    with_tmp(function(R)
      R.register('/app', 45001)
      R.unregister(45001)
      T.eq(#R.read(), 0)
    end)
  end)

  T.it('writes an empty array (not object) when no sessions remain', function()
    with_tmp(function(R, tmp)
      R.write({})
      T.eq(table.concat(vim.fn.readfile(tmp), '\n'), '[]')
    end)
  end)
end)

T.summary()
