-- git.luaの低レイヤ部分でcodexの独立調査が指摘していた機能単位の穴:
-- コマンドログ(dont_log/ストリーミングの部分行flush/MAX_LOG切り詰め)、
-- run_delta(delta不在時のフォールバック/空diff/side-by-side)、
-- github_repo_info(URL形式ごとの判定)、fetch_prs(空branch_names/DRAFT変換/API失敗)、
-- ref_candidates(remote HEADの除外)

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local git = require('config.git_panel.git')

T.describe('git.lua: command log', function()
  T.it('dont_log=true suppresses the "git ..." entry, but the command still runs', function()
    local dir = T.tmp_git_repo()
    git.root = dir
    local before = #git.command_log
    local done = false
    git.run({ 'status' }, function() done = true end, { dont_log = true })
    T.wait_until(function() return done end)
    T.eq(#git.command_log, before, 'a dont_log command should not add a log entry')
  end)

  T.it('without dont_log, the command is logged as "git <args>"', function()
    local dir = T.tmp_git_repo()
    git.root = dir
    local done = false
    git.run({ 'branch', '--list' }, function() done = true end)
    T.wait_until(function() return done end)
    T.eq(git.command_log[#git.command_log], 'git branch --list')
  end)

  T.it('stream_output=true flushes partial (non-newline-terminated) output as its own log line on completion', function()
    local dir = T.tmp_git_repo()
    git.root = dir
    local done = false
    -- 改行無しでstdoutへ何か出すコマンド(printf経由でgit名を騙るのは無理なので、
    -- M.runの引数をgit以外に変えられないため、改行が入らないstderrを出すコマンドで代用)
    git.run({ 'rev-parse', 'not-a-real-ref' }, function() done = true end, { stream_output = true })
    T.wait_until(function() return done end)
    local found = false
    for _, l in ipairs(git.command_log) do
      if l:find('not-a-real-ref', 1, true) or l:find('unknown revision', 1, true) or l:find('bad revision', 1, true) then
        found = true
      end
    end
    T.ok(found, 'the error output (no trailing newline) should still be flushed into the command log')
  end)

  T.it('keeps at most 200 entries, dropping the oldest first (FIFO)', function()
    local dir = T.tmp_git_repo()
    git.root = dir
    for i = 1, 210 do
      local done = false
      git.run({ 'branch', '--list', 'nonexistent-' .. i }, function() done = true end)
      T.wait_until(function() return done end)
    end
    T.eq(#git.command_log, 200)
    T.contains(git.command_log[#git.command_log], 'nonexistent-210', 'the most recent entry should be present')
    for _, l in ipairs(git.command_log) do
      T.ok(not l:find('nonexistent%-1$'), 'the oldest entry (1) should have been dropped')
    end
  end)
end)

T.describe('git.lua: run_delta', function()
  T.it('calls cb(nil) immediately for an empty diff, without spawning delta', function()
    local result, called = 'unset', false
    git.run_delta('', 80, function(r) result = r; called = true end)
    T.ok(called, 'callback should run synchronously for empty input')
    T.eq(result, nil)
  end)

  T.it('calls cb(nil) when delta is not available, regardless of diff content', function()
    local orig = git.delta_available
    git.delta_available = false
    local result, called = 'unset', false
    git.run_delta('some diff text', 80, function(r) result = r; called = true end)
    git.delta_available = orig
    T.ok(called)
    T.eq(result, nil)
  end)

  T.it('runs delta and returns ANSI-colored output when available', function()
    if vim.fn.executable('delta') == 0 then
      print('  (skipped: delta not installed)')
      return
    end
    local diff = table.concat({
      'diff --git a/f.txt b/f.txt', '--- a/f.txt', '+++ b/f.txt',
      '@@ -1 +1 @@', '-old', '+new',
    }, '\n')
    local result
    T.wait_until(function()
      git.run_delta(diff, 80, function(r) result = r end)
      return result ~= nil
    end, 2000)
    T.contains(result, '\27[', 'delta output should contain ANSI escape sequences')
  end)

  T.it('toggle_side_by_side flips the flag that gets passed to delta', function()
    local orig = git.side_by_side
    git.side_by_side = false
    T.eq(git.toggle_side_by_side(), true)
    T.eq(git.side_by_side, true)
    T.eq(git.toggle_side_by_side(), false)
    git.side_by_side = orig
  end)
end)

T.describe('git.lua: github_repo_info URL variants', function()
  local function with_origin(url, fn)
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'remote', 'add', 'origin', url })
    git.root = dir
    local result, called = 'unset', false
    git.github_repo_info(function(r) result = r; called = true end)
    T.wait_until(function() return called end)
    fn(result)
    T.rmrf(dir)
  end

  T.it('parses an SSH-style URL (git@github.com:owner/repo.git)', function()
    with_origin('git@github.com:my-org/my-repo.git', function(r)
      T.eq(r, { owner = 'my-org', repo = 'my-repo' })
    end)
  end)

  T.it('parses an HTTPS URL with a .git suffix', function()
    with_origin('https://github.com/my-org/my-repo.git', function(r)
      T.eq(r, { owner = 'my-org', repo = 'my-repo' })
    end)
  end)

  T.it('parses an HTTPS URL without a .git suffix', function()
    with_origin('https://github.com/my-org/my-repo', function(r)
      T.eq(r, { owner = 'my-org', repo = 'my-repo' })
    end)
  end)

  T.it('strips embedded credentials from an HTTPS URL', function()
    with_origin('https://user:token@github.com/my-org/my-repo.git', function(r)
      T.eq(r, { owner = 'my-org', repo = 'my-repo' })
    end)
  end)

  T.it('returns nil for a non-GitHub remote', function()
    with_origin('https://gitlab.com/my-org/my-repo.git', function(r)
      T.eq(r, nil)
    end)
  end)

  T.it('returns nil when there is no origin remote at all', function()
    local dir = T.tmp_git_repo()
    git.root = dir
    local result, called = 'unset', false
    git.github_repo_info(function(r) result = r; called = true end)
    T.wait_until(function() return called end)
    T.eq(result, nil)
    T.rmrf(dir)
  end)
end)

T.describe('git.lua: fetch_prs', function()
  T.it('returns an empty list synchronously when branch_names is empty (no network call)', function()
    local orig_system = vim.system
    local called = false
    vim.system = function(...) called = true; return orig_system(...) end
    local result, cb_called = 'unset', false
    git.fetch_prs('o', 'r', 't', {}, function(r) result = r; cb_called = true end)
    vim.system = orig_system
    T.ok(cb_called)
    T.eq(result, {})
    T.ok(not called, 'no curl/network call should happen for an empty branch list')
  end)

  T.it('converts isDraft:true (and not CLOSED) into state=DRAFT', function()
    local orig_system = vim.system
    vim.system = function(_, _, cb)
      cb({ code = 0, stdout = vim.json.encode({
        data = { repository = { a1 = { edges = {
          { node = { title = 'x', headRefName = 'f', state = 'OPEN', number = 1, isDraft = true,
            headRepositoryOwner = { login = 'me' } } },
        } } } } }),
      })
    end
    local prs
    git.fetch_prs('me', 'repo', 'tok', { 'f' }, function(r) prs = r end)
    vim.system = orig_system
    T.wait_until(function() return prs ~= nil end)
    T.eq(#prs, 1)
    T.eq(prs[1].state, 'DRAFT')
  end)

  T.it('keeps state=CLOSED even if isDraft:true (closed drafts are not shown as drafts)', function()
    local orig_system = vim.system
    vim.system = function(_, _, cb)
      cb({ code = 0, stdout = vim.json.encode({
        data = { repository = { a1 = { edges = {
          { node = { title = 'x', headRefName = 'f', state = 'CLOSED', number = 1, isDraft = true,
            headRepositoryOwner = { login = 'me' } } },
        } } } } }),
      })
    end
    local prs
    git.fetch_prs('me', 'repo', 'tok', { 'f' }, function(r) prs = r end)
    vim.system = orig_system
    T.wait_until(function() return prs ~= nil end)
    T.eq(prs[1].state, 'CLOSED')
  end)

  T.it('returns an empty list (no crash) when curl fails', function()
    local orig_system = vim.system
    vim.system = function(_, _, cb) cb({ code = 1, stdout = '', stderr = 'connection failed' }) end
    local prs
    git.fetch_prs('me', 'repo', 'tok', { 'f' }, function(r) prs = r end)
    vim.system = orig_system
    T.wait_until(function() return prs ~= nil end)
    T.eq(prs, {})
  end)

  T.it('returns an empty list (no crash) when curl succeeds but the response is not valid JSON', function()
    local orig_system = vim.system
    vim.system = function(_, _, cb) cb({ code = 0, stdout = 'not json at all' }) end
    local prs
    git.fetch_prs('me', 'repo', 'tok', { 'f' }, function(r) prs = r end)
    vim.system = orig_system
    T.wait_until(function() return prs ~= nil end)
    T.eq(prs, {})
  end)
end)

T.describe('git.lua: ref_candidates', function()
  T.it('excludes the symbolic "origin/HEAD" ref from remote-tracking candidates', function()
    local remote = vim.fn.tempname()
    vim.fn.mkdir(remote, 'p')
    GP.git(remote, { 'init', '-q', '--bare', '-b', 'main' })
    local dir = vim.fn.tempname()
    vim.system({ 'git', 'clone', '-q', remote, dir }):wait()
    GP.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed', '--allow-empty' })
    GP.git(dir, { 'push', '-u', 'origin', 'main' })
    -- git cloneはorigin/HEADを自動設定する。念のため明示的にも張っておく
    GP.git(dir, { 'remote', 'set-head', 'origin', 'main' })
    T.contains(GP.git(dir, { 'for-each-ref', 'refs/remotes/' }).stdout, 'origin/HEAD',
      'sanity check: origin/HEAD should exist as a ref')

    git.root = dir
    local candidates
    git.ref_candidates(function(c) candidates = c end)
    T.wait_until(function() return candidates ~= nil end)
    T.ok(not vim.tbl_contains(candidates, 'origin/HEAD'), 'origin/HEAD should be excluded from suggestions')
    T.ok(vim.tbl_contains(candidates, 'origin/main'), 'the real remote branch should still be included')

    T.rmrf(dir); T.rmrf(remote)
  end)

  T.it('includes local branches, tags, and the special HEAD-ish refs', function()
    local dir = T.tmp_git_repo()
    GP.git(dir, { 'branch', 'feature' })
    GP.git(dir, { 'tag', 'v1.0' })
    git.root = dir

    local candidates
    git.ref_candidates(function(c) candidates = c end)
    T.wait_until(function() return candidates ~= nil end)
    T.ok(vim.tbl_contains(candidates, 'feature'))
    T.ok(vim.tbl_contains(candidates, 'v1.0'))
    T.ok(vim.tbl_contains(candidates, 'HEAD'))
    T.ok(vim.tbl_contains(candidates, 'FETCH_HEAD'))

    T.rmrf(dir)
  end)
end)

T.summary()
