-- グローバルキー P(push)/p(pull)/z(undo)のテスト。実在のbare remoteとclone
-- を使い、モックなしで実際のgit通信(ローカルパス経由)として検証する
-- (init.luaのdo_push/do_pull/do_undoはlazygitのsync_controller.goを踏襲した
-- 分岐を持つため、それぞれ実際に踏ませて確認する)

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')

local function bare_remote()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  GP.git(dir, { 'init', '-q', '--bare', '-b', 'main' })
  return dir
end

local function clone(remote)
  local dest = vim.fn.tempname()
  vim.system({ 'git', 'clone', '-q', remote, dest }):wait()
  GP.git(dest, { '-c', 'user.email=test@test', '-c', 'user.name=test', 'config', 'user.email', 'test@test' })
  GP.git(dest, { 'config', 'user.name', 'test' })
  return dest
end

local function head(dir) return vim.trim(GP.git(dir, { 'rev-parse', 'HEAD' }).stdout) end

local function commit_file(dir, name, content)
  T.write_file(dir .. '/' .. name, { content })
  GP.git(dir, { 'add', '.' })
  GP.git(dir, { '-c', 'user.email=test@test', '-c', 'user.name=test', 'commit', '-qm', content })
end

T.describe('git_panel sync (push/pull/undo)', function()
  T.it('P pushes a new commit straight to a clean, up-to-date remote', function()
    local remote = bare_remote()
    local dir = clone(remote)
    -- clone直後は空リポジトリでHEADが無いため、まず1つコミットして土台を作る
    commit_file(dir, 'a.txt', 'a')
    GP.git(dir, { 'push', '-u', 'origin', 'main' })

    commit_file(dir, 'b.txt', 'b')
    GP.open(dir, false)
    GP.press('P')
    T.wait_until(function() return head(remote) == head(dir) end)
    T.eq(head(remote), head(dir), 'remote should now match local HEAD')

    GP.close()
    T.rmrf(dir); T.rmrf(remote)
  end)

  T.it('P prompts to set upstream when the branch has none, and pushes after confirming', function()
    local remote = bare_remote()
    local dir = clone(remote)
    commit_file(dir, 'a.txt', 'a')
    -- あえて -u を付けずにpushし、リモートには内容があるがupstream追跡は未設定のままにする
    GP.git(dir, { 'push', 'origin', 'main' })
    GP.git(dir, { 'branch', '--unset-upstream' })
    T.eq(GP.git(dir, { 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }).code ~= 0, true,
      'sanity check: upstream should be unset')

    commit_file(dir, 'b.txt', 'b')
    GP.open(dir, false)
    GP.press('P')
    vim.wait(150)
    GP.press_modal('y') -- 「アップストリームが未設定です」確認
    T.wait_until(function() return head(remote) == head(dir) end)
    T.eq(head(remote), head(dir))
    T.eq(GP.git(dir, { 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }).code, 0,
      'upstream should now be set')

    GP.close()
    T.rmrf(dir); T.rmrf(remote)
  end)

  T.it('P detects a known-behind branch ahead of time and force-pushes after confirming', function()
    local remote = bare_remote()
    local dirA = clone(remote)
    commit_file(dirA, 'a.txt', 'a')
    GP.git(dirA, { 'push', '-u', 'origin', 'main' })
    local dirB = clone(remote)

    -- dirBがリモートを進める
    commit_file(dirB, 'from-b.txt', 'b')
    GP.git(dirB, { 'push', 'origin', 'main' })

    -- dirAはfetchして「behind」を認識しつつ、自分も別のコミットを積んで分岐させる
    GP.git(dirA, { 'fetch', 'origin' })
    commit_file(dirA, 'from-a.txt', 'a2')

    GP.open(dirA, false)
    GP.press('P')
    vim.wait(150)
    GP.press_modal('y') -- 「force pushしますか」(事前検知)
    T.wait_until(function() return head(remote) == head(dirA) end)
    T.eq(head(remote), head(dirA), 'force push should overwrite remote with dirA history')

    GP.close()
    T.rmrf(dirA); T.rmrf(dirB); T.rmrf(remote)
  end)

  T.it('P discovers a rejected push only after attempting it, and force-pushes with plain --force (not --force-with-lease, which would fail with "stale info")', function()
    local remote = bare_remote()
    local dirA = clone(remote)
    commit_file(dirA, 'a.txt', 'a')
    GP.git(dirA, { 'push', '-u', 'origin', 'main' })
    local dirB = clone(remote)

    -- dirBがリモートを進めるが、dirAはfetchしないため事前チェック(track列)では
    -- 気付けない。実際にpushしてrejectされて初めて発覚する経路を踏む
    commit_file(dirB, 'from-b.txt', 'b')
    GP.git(dirB, { 'push', 'origin', 'main' })

    commit_file(dirA, 'from-a.txt', 'a2')
    GP.open(dirA, false)
    GP.press('P')
    -- rejected後に出る「確認 (y/N)」force pushモーダルを待つ(実push自体が
    -- 非同期なので、left_winのタイトル変化ではなくモーダル自体の出現で判定する)
    T.wait_until(function() return GP.win_by_title('確認') ~= nil end, 3000)
    GP.press_modal('y')
    T.wait_until(function() return head(remote) == head(dirA) end)
    T.eq(head(remote), head(dirA), 'force push should overwrite remote with dirA history')

    GP.close()
    T.rmrf(dirA); T.rmrf(dirB); T.rmrf(remote)
  end)

  T.it('p pulls new commits from the remote', function()
    local remote = bare_remote()
    local dirA = clone(remote)
    commit_file(dirA, 'a.txt', 'a')
    GP.git(dirA, { 'push', '-u', 'origin', 'main' })
    local dirB = clone(remote)

    commit_file(dirA, 'b.txt', 'b')
    GP.git(dirA, { 'push', 'origin', 'main' })

    GP.open(dirB, false)
    GP.press('p')
    T.wait_until(function() return head(dirB) == head(remote) end)
    T.eq(head(dirB), head(remote))
    T.ok(vim.fn.filereadable(dirB .. '/b.txt') == 1, 'pulled file should exist locally')

    GP.close()
    T.rmrf(dirA); T.rmrf(dirB); T.rmrf(remote)
  end)

  T.it('z undoes the last commit (soft reset), keeping its changes staged', function()
    local dir = T.tmp_git_repo()
    commit_file(dir, 'a.txt', 'a')
    local before = vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout)

    GP.open(dir, false)
    GP.press('z')
    vim.wait(80)
    GP.press_modal('y') -- 「直前のコミットを取り消しますか」確認
    T.wait_until(function()
      return vim.trim(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout) ~= before
    end)
    T.ok(GP.git(dir, { 'log', '-1', '--format=%s' }).stdout:find('init', 1, true) ~= nil,
      'HEAD should be back at the previous commit')
    local staged = GP.git(dir, { 'diff', '--cached', '--name-only' }).stdout
    T.contains(staged, 'a.txt')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
