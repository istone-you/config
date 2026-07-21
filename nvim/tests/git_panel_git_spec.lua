local T = dofile(TESTS_DIR .. '/helpers.lua')
local git = require('config.git_panel.git')

T.describe('git_panel.git parse_hunks/build_patch', function()
  local diff = table.concat({
    'diff --git a/x.txt b/x.txt',
    'index 111..222 100644',
    '--- a/x.txt',
    '+++ b/x.txt',
    '@@ -1,3 +1,3 @@',
    ' line1',
    '-line2',
    '+CHANGED',
    ' line3',
    '@@ -10,1 +10,2 @@',
    ' line10',
    '+line11',
    '',
  }, '\n')

  T.it('splits header and hunks correctly', function()
    local header, hunks = git.parse_hunks(diff)
    T.eq(#hunks, 2, 'should find 2 hunks')
    T.eq(header[1], 'diff --git a/x.txt b/x.txt')
    T.contains(header, '+++ b/x.txt')
    T.eq(hunks[1].header, '@@ -1,3 +1,3 @@')
    T.eq(#hunks[1].lines, 4)
    T.eq(hunks[2].header, '@@ -10,1 +10,2 @@')
  end)

  T.it('build_patch equivalent round-trips through git apply', function()
    -- parse_hunksで割った1個目のhunkだけを再構成したpatchが、実際にgit applyで
    -- 通ることを確認する(header+hunk.header+hunk.linesの組み立てが正しいか)
    local header, hunks = git.parse_hunks(diff)
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/x.txt', { 'line1', 'line2', 'line3' })
    T.git(dir, { 'add', 'x.txt' })
    T.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'x' })

    local parts = {}
    vim.list_extend(parts, header)
    table.insert(parts, hunks[1].header)
    vim.list_extend(parts, hunks[1].lines)
    local patch = table.concat(parts, '\n') .. '\n'

    local tmp = vim.fn.tempname()
    vim.fn.writefile(vim.split(patch, '\n', { plain = true }), tmp)
    local res = T.git(dir, { 'apply', tmp })
    T.eq(res.code, 0, 'git apply should succeed: ' .. (res.stderr or ''))
    T.eq(vim.fn.readfile(dir .. '/x.txt'), { 'line1', 'CHANGED', 'line3' })

    T.rmrf(dir)
  end)
end)

--- 回帰テスト: バックグラウンド自動更新の`git status`が.git/index.lockを取ろうとして
--- discard等の書き込みコマンドと競合する不具合が実際にあった(ストレステストで
--- 8ファイル一括discardが約1/7の頻度で再現)。lazygit本体(git_cmd_obj_builder.go/
--- git_cmd_obj_runner.go)と同じ対応=①全コマンドにGIT_OPTIONAL_LOCKS=0を付けて
--- 読み取り専用コマンドがそもそもロックを取らないようにする、②それでも競合する
--- 書き込みコマンドはindex.lockエラーを指数バックオフで再試行、の2本立てで直した
T.describe('git_panel.git M.run lock handling (lazygit git_cmd_obj_runner.go相当)', function()
  T.it('a read-only command succeeds immediately even while .git/index.lock exists (GIT_OPTIONAL_LOCKS=0)', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/.git/index.lock', {}) -- 他プロセスが握っている体を模倣
    git.root = dir

    local result
    git.run({ 'rev-parse', '--show-toplevel' }, function(res) result = res end, { dont_log = true })
    T.wait_until(function() return result ~= nil end, 500)
    T.ok(result ~= nil, 'callback should fire')
    T.eq(result.code, 0, 'read-only command must not be blocked by an existing index.lock: ' .. (result.stderr or ''))

    vim.fn.delete(dir .. '/.git/index.lock')
    T.rmrf(dir)
  end)

  T.it('a write command retries with backoff and succeeds once the lock is released', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'a' })
    T.git(dir, { 'add', '.' })
    T.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })
    git.root = dir

    T.write_file(dir .. '/.git/index.lock', {})
    vim.defer_fn(function()
      vim.fn.delete(dir .. '/.git/index.lock') -- 他プロセスがロックを解放した体
    end, 90) -- 初回リトライ(20ms)は失敗し、2回目(20+40=60ms以降)で成功する想定

    local result
    git.run({ 'add', '--', 'a.txt' }, function(res) result = res end)
    T.wait_until(function() return result ~= nil end, 3000)
    T.ok(result ~= nil, 'callback should eventually fire')
    T.eq(result.code, 0, 'should succeed once the lock is released: ' .. (result and result.stderr or ''))
    T.contains(T.git(dir, { 'status', '--porcelain=v1' }).stdout, 'M  a.txt')

    T.rmrf(dir)
  end)

  T.it('a write command gives up and reports failure if the lock never clears', function()
    local dir = T.tmp_git_repo()
    T.write_file(dir .. '/a.txt', { 'a' })
    T.git(dir, { 'add', '.' })
    T.git(dir, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    T.write_file(dir .. '/a.txt', { 'a', 'changed' })
    git.root = dir
    T.write_file(dir .. '/.git/index.lock', {}) -- 解放されない

    local result
    git.run({ 'add', '--', 'a.txt' }, function(res) result = res end)
    T.wait_until(function() return result ~= nil end, 5000)
    T.ok(result ~= nil, 'callback should eventually fire even on permanent failure')
    T.ok(result.code ~= 0, 'should report failure after exhausting retries')
    T.contains(result.stderr or '', 'index.lock')

    vim.fn.delete(dir .. '/.git/index.lock')
    T.rmrf(dir)
  end)
end)

T.summary()
