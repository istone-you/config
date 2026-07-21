-- 非同期git操作レイヤー（vim.system + on_exitコールバック、UIをブロックしない）
-- コマンドの実選択は lazygit(pkg/commands/git_commands) を参照して合わせている

local M = {}

M.root = nil
M.command_log = {}
local MAX_LOG = 200
--- init.luaがrender_cmdlog相当を差し込むためのフック（コマンドログに変化があるたびに呼ぶ）
M.on_log_update = function() end

--- lazygitは独自のpager設定(git.pagers、core.pagerとは別物)でdeltaを呼ぶが、ここでは
--- 単純化してdeltaコマンドが存在する時だけ自動的に使う。gitはstdoutがTTYでないとpagerを
--- 一切起動しないため、素のgit diff等をそのままキャプチャしてもdeltaは通らない。
--- なので生のdiffテキストを自分でdeltaの標準入力へ渡し、色付きANSI出力を受け取る
M.delta_available = vim.fn.executable('delta') == 1

--- deltaのside-by-side表示(--side-by-side)のオン/オフ
M.side_by_side = false

function M.toggle_side_by_side()
  M.side_by_side = not M.side_by_side
  return M.side_by_side
end

--- diff_text(生のunified diff)をdeltaに通して色付きANSI出力を返す。
--- deltaが無い/失敗した場合はcb(nil)（呼び出し側は素のテキスト表示にフォールバックする）
function M.run_delta(diff_text, width, cb)
  if not M.delta_available or not diff_text or diff_text == '' then
    cb(nil)
    return
  end
  local args = {
    'delta', '--paging=never', '--width=' .. tostring(width or 80),
    '--line-numbers', '--keep-plus-minus-markers',
  }
  if M.side_by_side then table.insert(args, '--side-by-side') end
  vim.system(
    args,
    { stdin = diff_text, text = true },
    function(res)
      vim.schedule(function() cb(res.code == 0 and res.stdout or nil) end)
    end
  )
end

--- lazygit(command_log_panel.go)と同じく、古い→新しいの順で末尾に追記する
--- （表示側でビューを一番下へスクロールすることで最新行を見せる。Autoscroll相当）
local function push_log(text)
  table.insert(M.command_log, text)
  if #M.command_log > MAX_LOG then
    table.remove(M.command_log, 1)
  end
  -- push_logはvim.system側のstdout/stderrコールバック(fast event context)からも
  -- 呼ばれるため、vim.api経由の再描画は必ずscheduleする
  vim.schedule(M.on_log_update)
end

local function log_command(args)
  push_log('git ' .. table.concat(args, ' '))
end

--- lazygitのStreamOutput()相当。標準出力/エラーを完了を待たず1行ずつコマンドログへ
--- 流し込む（lefthook/hk等のpre-commitフックの出力や、push/pullの進捗メッセージが
--- 見えるようにする）。vim.systemはstdout/stderrにコールバックを渡すと最終res.stdout/
--- res.stderrをnilにしてしまうため、ここで全文も別途累積して呼び出し元に渡せるようにする
local function make_streamer()
  local pending, full = '', {}
  local function feed(_, data)
    if not data then
      if pending ~= '' then push_log('  ' .. pending); table.insert(full, pending); pending = '' end
      return
    end
    table.insert(full, data)
    pending = pending .. data
    while true do
      local nl = pending:find('\n')
      if not nl then break end
      push_log('  ' .. pending:sub(1, nl - 1))
      pending = pending:sub(nl + 1)
    end
  end
  return feed, function() return table.concat(full) end
end

function M.find_root(cb)
  local args = { 'rev-parse', '--show-toplevel' }
  vim.system(vim.list_extend({ 'git' }, args), { cwd = vim.fn.getcwd(), text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        M.root = vim.trim(res.stdout or '')
        cb(M.root)
      else
        cb(nil)
      end
    end)
  end)
end

--- lazygit(pkg/commands/oscommands/cmd_obj.go DontLog)と同じ方針:
--- git状態を変えないコマンド(status/diff/logなど)はコマンドログに出さない。
--- 状態を変えるコマンド(add/commit/checkoutなど)は出す。opts.dont_log=trueで前者を指定する。
--- opts.stream_output=trueなら、そのコマンドの標準出力/エラーもコマンドログへ流し込む
--- （lazygitがcommit/push/pull/merge/rebase等でStreamOutput()するのと同じ対象）
function M.run(args, cb, opts)
  local cmd = vim.list_extend({ 'git' }, args)
  if not (opts and opts.dont_log) then log_command(args) end
  local sys_opts = { cwd = M.root, text = true }
  local get_stdout, get_stderr
  if opts and opts.stream_output then
    local stdout_feed, stdout_get = make_streamer()
    local stderr_feed, stderr_get = make_streamer()
    sys_opts.stdout, sys_opts.stderr = stdout_feed, stderr_feed
    get_stdout, get_stderr = stdout_get, stderr_get
  end
  vim.system(cmd, sys_opts, function(res)
    if get_stdout then res.stdout = get_stdout() end
    if get_stderr then res.stderr = get_stderr() end
    vim.schedule(function() cb(res) end)
  end)
end

-- ══════════════════════════════════════════════
-- status / diff / stage（working_tree.goのStageFiles/UnStageFileに合わせる）
-- ══════════════════════════════════════════════

function M.status(cb)
  -- --untracked-files=all: 未追跡ディレクトリを1行にまとめず配下ファイルを個別に列挙する
  M.run({ 'status', '--porcelain=v1', '--untracked-files=all' }, function(res) cb(res.stdout or '') end, { dont_log = true })
end

function M.branch_name(cb)
  M.run({ 'rev-parse', '--abbrev-ref', 'HEAD' }, function(res) cb(vim.trim(res.stdout or '')) end, { dont_log = true })
end

function M.diff_file(entry, cb)
  local args = (entry.section == 'staged')
    and { 'diff', '--cached', '--', entry.path }
    or { 'diff', '--', entry.path }
  M.run(args, function(res) cb(res.stdout or '') end, { dont_log = true })
end

function M.stage(path, cb) M.run({ 'add', '--', path }, cb) end
function M.unstage(path, cb) M.run({ 'reset', 'HEAD', '--', path }, cb) end
function M.stage_all(cb) M.run({ 'add', '-A' }, cb) end
function M.unstage_all(cb) M.run({ 'reset', 'HEAD' }, cb) end
function M.ignore_file(path, cb)
  local ok = pcall(function()
    vim.fn.writefile({ path }, M.root .. '/.gitignore', 'a')
  end)
  cb({ code = ok and 0 or 1 })
end

function M.commit(msg_lines, no_verify, cb)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(msg_lines, tmp)
  local args = { 'commit', '-F', tmp }
  if no_verify then table.insert(args, '--no-verify') end
  M.run(args, function(res)
    vim.fn.delete(tmp)
    cb(res)
  end, { stream_output = true })
end

function M.amend(cb)
  M.run({ 'commit', '--amend', '--no-edit' }, cb, { stream_output = true })
end

-- ══════════════════════════════════════════════
-- hunk単位のステージ（pkg/commands/git_commands/patch.go ApplyPatchと同じフラグ運用）
-- stage: {cached=true}  unstage: {cached=true, reverse=true}  discard: {reverse=true}
-- ══════════════════════════════════════════════

function M.parse_hunks(diff_text)
  local lines = vim.split(diff_text, '\n', { plain = true })
  local header = {}
  local hunks = {}
  local current = nil
  for _, l in ipairs(lines) do
    if l:match('^@@') then
      current = { header = l, lines = {} }
      table.insert(hunks, current)
    elseif current then
      table.insert(current.lines, l)
    else
      table.insert(header, l)
    end
  end
  return header, hunks
end

local function build_patch(header, hunk)
  local parts = {}
  vim.list_extend(parts, header)
  table.insert(parts, hunk.header)
  vim.list_extend(parts, hunk.lines)
  return table.concat(parts, '\n') .. '\n'
end

--- opts = { cached = bool, reverse = bool }
function M.apply_hunk(header, hunk, opts, cb)
  local patch = build_patch(header, hunk)
  local tmp = vim.fn.tempname()
  vim.fn.writefile(vim.split(patch, '\n', { plain = true }), tmp)
  local args = { 'apply' }
  if opts.cached then table.insert(args, '--cached') end
  if opts.reverse then table.insert(args, '--reverse') end
  table.insert(args, tmp)
  M.run(args, function(res)
    vim.fn.delete(tmp)
    cb(res)
  end)
end

-- ══════════════════════════════════════════════
-- ブランチ
-- ══════════════════════════════════════════════

function M.branches(cb)
  M.run({
    'for-each-ref', 'refs/heads/',
    '--format=%(HEAD)%09%(refname:short)%09%(upstream:short)%09%(upstream:track)',
    '--sort=-committerdate',
  }, function(res)
    local list = {}
    local head_idx = nil
    for _, line in ipairs(vim.split(res.stdout or '', '\n', { plain = true })) do
      if line ~= '' then
        local head, name, upstream, track = line:match('^(.-)\t(.-)\t(.-)\t(.*)$')
        if name then
          table.insert(list, { name = name, current = head == '*', upstream = upstream, track = track })
          if head == '*' then head_idx = #list end
        end
      end
    end
    -- branch_loader.go Load(): ソート順設定に関わらずHEADブランチを常に先頭へ移動する
    if head_idx and head_idx ~= 1 then
      table.insert(list, 1, table.remove(list, head_idx))
    end
    cb(list)
  end, { dont_log = true })
end

function M.checkout_branch(name, cb) M.run({ 'checkout', name }, cb) end
function M.checkout_by_name(name, cb) M.run({ 'checkout', name }, cb) end
function M.checkout_previous(cb) M.run({ 'checkout', '-' }, cb) end
function M.create_branch(name, cb) M.run({ 'checkout', '-b', name }, cb) end
function M.delete_branch(name, force, cb) M.run({ 'branch', force and '-D' or '-d', name }, cb) end
function M.force_checkout(name, cb) M.run({ 'checkout', '-f', name }, cb) end
function M.merge_branch(name, cb) M.run({ 'merge', name }, cb, { stream_output = true }) end
function M.rebase_branch(name, cb) M.run({ 'rebase', name }, cb, { stream_output = true }) end
function M.rename_branch(old, new, cb) M.run({ 'branch', '-m', old, new }, cb) end
function M.fast_forward(name, cb) M.run({ 'fetch', 'origin', name .. ':' .. name }, cb) end
function M.set_upstream(remote, branch_name, cb) M.run({ 'branch', '-u', remote .. '/' .. branch_name }, cb) end

-- ══════════════════════════════════════════════
-- ログ / コミット操作
-- ══════════════════════════════════════════════

local LOG_SEP = '\x1f'
local LOG_FMT = table.concat({ '%H', '%h', '%s', '%an', '%ar' }, LOG_SEP)

function M.log(cb)
  M.run({ 'log', '--pretty=format:' .. LOG_FMT, '-n', '300' }, function(res)
    local list = {}
    for _, line in ipairs(vim.split(res.stdout or '', '\n', { plain = true })) do
      if line ~= '' then
        local parts = vim.split(line, LOG_SEP, { plain = true })
        table.insert(list, {
          hash = parts[1], short = parts[2], subject = parts[3],
          author = parts[4], rel = parts[5],
        })
      end
    end
    cb(list)
  end, { dont_log = true })
end

function M.show_commit(hash, cb) M.run({ 'show', hash }, function(res) cb(res.stdout or '') end, { dont_log = true }) end
function M.reset(hash, mode, cb) M.run({ 'reset', '--' .. mode, hash }, cb) end
function M.revert_commit(hash, cb) M.run({ 'revert', '--no-edit', hash }, cb, { stream_output = true }) end
function M.new_branch_from_commit(hash, name, cb) M.run({ 'checkout', '-b', name, hash }, cb) end

--- Undo(z): 直前のコミット1つだけをsoft resetで取り消す（lazygitのreflog Undoの
--- 「直前の操作がコミットだった」場合の挙動を再現。checkout/rebaseのUndoは対象外）
function M.undo_last_commit(cb) M.run({ 'reset', '--soft', 'HEAD@{1}' }, cb) end
function M.checkout_commit(hash, cb) M.run({ 'checkout', hash }, cb) end

--- lazygitのGit.MainBranches既定値("master","main")に合わせ、
--- pkg/commands/git_commands/main_branches.go の determineMainBranches と同じ優先順位で解決する:
--- 1. ローカルブランチのアップストリーム（<name>@{u}。例: main@{u} -> origin/main）
--- 2. アップストリーム未設定ならorigin配下のリモート追跡ブランチ（refs/remotes/origin/<name>）
--- 3. それも無ければローカルブランチ自体（refs/heads/<name>）
--- ※ 1を最優先するのが重要: mainブランチにチェックアウトしている状態でmain自身を使うと
---   git rev-list HEAD ^main が常に空になり、未pushコミットまで緑(Merged)になってしまう
function M.resolve_main_branches(cb)
  local candidates = { 'master', 'main' }
  local refs = {}
  local pending = #candidates
  local function done()
    pending = pending - 1
    if pending == 0 then cb(refs) end
  end
  for _, name in ipairs(candidates) do
    M.run({ 'rev-parse', '--symbolic-full-name', name .. '@{u}' }, function(res)
      if res.code == 0 then
        table.insert(refs, vim.trim(res.stdout or ''))
        done()
        return
      end
      M.run({ 'rev-parse', '--verify', '--quiet', 'refs/remotes/origin/' .. name }, function(res2)
        if res2.code == 0 then
          table.insert(refs, 'refs/remotes/origin/' .. name)
          done()
          return
        end
        M.run({ 'rev-parse', '--verify', '--quiet', 'refs/heads/' .. name }, function(res3)
          if res3.code == 0 then table.insert(refs, 'refs/heads/' .. name) end
          done()
        end, { dont_log = true })
      end, { dont_log = true })
    end, { dont_log = true })
  end
end

-- ══════════════════════════════════════════════
-- スタッシュ
-- ══════════════════════════════════════════════

local STASH_FMT = table.concat({ '%gd', '%s' }, LOG_SEP)

function M.stash_list(cb)
  M.run({ 'stash', 'list', '--pretty=format:' .. STASH_FMT }, function(res)
    local list = {}
    for _, line in ipairs(vim.split(res.stdout or '', '\n', { plain = true })) do
      if line ~= '' then
        local parts = vim.split(line, LOG_SEP, { plain = true })
        table.insert(list, { ref = parts[1], message = parts[2] })
      end
    end
    cb(list)
  end, { dont_log = true })
end

function M.stash_show(ref, cb) M.run({ 'stash', 'show', '-p', ref }, function(res) cb(res.stdout or '') end, { dont_log = true }) end
function M.stash_apply(ref, cb) M.run({ 'stash', 'apply', ref }, cb, { stream_output = true }) end
function M.stash_pop(ref, cb) M.run({ 'stash', 'pop', ref }, cb, { stream_output = true }) end
function M.stash_drop(ref, cb) M.run({ 'stash', 'drop', ref }, cb) end
function M.stash_branch(ref, name, cb) M.run({ 'stash', 'branch', name, ref }, cb) end

function M.stash_save(msg, cb)
  local args = { 'stash', 'push' }
  if msg and msg ~= '' then
    table.insert(args, '-m')
    table.insert(args, msg)
  end
  M.run(args, cb)
end

-- ══════════════════════════════════════════════
-- push / pull / fetch
-- ══════════════════════════════════════════════

function M.has_upstream(cb)
  M.run({ 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' }, function(res)
    cb(res.code == 0, vim.trim(res.stdout or ''))
  end, { dont_log = true })
end

function M.push(cb) M.run({ 'push' }, cb, { stream_output = true }) end
function M.push_force_with_lease(cb) M.run({ 'push', '--force-with-lease' }, cb, { stream_output = true }) end
function M.push_set_upstream(remote, branch_name, cb) M.run({ 'push', '-u', remote, branch_name }, cb, { stream_output = true }) end
function M.pull(cb) M.run({ 'pull' }, cb, { stream_output = true }) end
function M.fetch(cb) M.run({ 'fetch' }, cb, { stream_output = true }) end
function M.remote_names(cb)
  M.run({ 'remote' }, function(res)
    cb(vim.tbl_filter(function(l) return l ~= '' end, vim.split(res.stdout or '', '\n', { plain = true })))
  end, { dont_log = true })
end

--- suggestions_helper.go GetRefsSuggestionsFuncと同じ材料を集める:
--- リモート追跡ブランチ("remote/branch"形式) + ローカルブランチ + タグ + HEAD系の特殊ref
function M.ref_candidates(cb)
  local function lines(res)
    local out = {}
    for l in (res.stdout or ''):gmatch('[^\r\n]+') do table.insert(out, l) end
    return out
  end
  M.run({ 'for-each-ref', 'refs/remotes/', '--format=%(refname:short)' }, function(r1)
    local remotes = vim.tbl_filter(function(l) return not l:match('/HEAD$') end, lines(r1))
    M.run({ 'for-each-ref', 'refs/heads/', '--format=%(refname:short)' }, function(r2)
      local locals = lines(r2)
      M.run({ 'for-each-ref', 'refs/tags/', '--format=%(refname:short)' }, function(r3)
        local tags = lines(r3)
        local all = {}
        vim.list_extend(all, remotes)
        vim.list_extend(all, locals)
        vim.list_extend(all, tags)
        vim.list_extend(all, { 'HEAD', 'FETCH_HEAD', 'MERGE_HEAD', 'ORIG_HEAD' })
        cb(all)
      end, { dont_log = true })
    end, { dont_log = true })
  end, { dont_log = true })
end

-- ══════════════════════════════════════════════
-- GitHub PR (pkg/commands/git_commands/github.go相当。GitHub以外のホスティングは未対応、
-- forkからのPR判定(headRepositoryOwnerの突き合わせ)も自分のリポジトリ運用を想定して省略)
-- ══════════════════════════════════════════════

--- originのURLからgithub.com上のowner/repoを判定する。github.com以外は非対応でnilを返す
function M.github_repo_info(cb)
  M.run({ 'remote', 'get-url', 'origin' }, function(res)
    if res.code ~= 0 then cb(nil); return end
    local url = vim.trim(res.stdout or '')
    local owner, repo = url:match('github%.com[:/]([^/]+)/([^/]+)')
    if not owner then cb(nil); return end
    cb({ owner = owner, repo = (repo:gsub('%.git$', '')) })
  end, { dont_log = true })
end

--- 自前でトークンを保存/管理せず、gh CLIが保持している認証情報をそのまま使う。
--- ghが未インストール/未認証なら黒く失敗してnilを返す（PR表示機能が黙って無効になる）
function M.gh_auth_token(cb)
  vim.system({ 'gh', 'auth', 'token' }, { text = true }, function(res)
    vim.schedule(function() cb(res.code == 0 and vim.trim(res.stdout or '') or nil) end)
  end)
end

--- pkg/commands/git_commands/github.go fetchPullRequestsQueryと同じ形
--- (ブランチ1つにつきheadRefNameで絞ったサブクエリを1本、まとめて1リクエストにする)
--- でGitHub GraphQL APIに問い合わせ、node一覧を返す。isDraftはsetCommitStatuses同様に
--- state側へ畳み込む(state=DRAFT)。取得失敗時は空配列を返すだけで、エラー通知はしない
--- （PR表示はlazygitでも失敗時にログだけでUIを止めない補助情報という位置づけ）
function M.fetch_prs(owner, repo, token, branch_names, cb)
  if #branch_names == 0 then cb({}); return end
  local var_decls = { '$owner: String!', '$repo: String!' }
  local variables = { owner = owner, repo = repo }
  local queries = {}
  for i, name in ipairs(branch_names) do
    local field, var = 'a' .. i, 'branch' .. i
    variables[var] = name
    table.insert(var_decls, '$' .. var .. ': String!')
    table.insert(queries, string.format(
      '%s: pullRequests(first: 5, headRefName: $%s, orderBy: {field: CREATED_AT, direction: DESC}) '
        .. '{ edges { node { title headRefName state number url isDraft headRepositoryOwner { login } } } }',
      field, var))
  end
  local query = string.format('query(%s) { repository(owner: $owner, name: $repo) { %s } }',
    table.concat(var_decls, ', '), table.concat(queries, ' '))

  local tmp = vim.fn.tempname()
  vim.fn.writefile({ vim.json.encode({ query = query, variables = variables }) }, tmp)
  vim.system({
    'curl', '-s', '-X', 'POST', 'https://api.github.com/graphql',
    '-H', 'Authorization: token ' .. token,
    '-H', 'Content-Type: application/json',
    '--max-time', '10',
    '-d', '@' .. tmp,
  }, { text = true }, function(res)
    vim.schedule(function()
      vim.fn.delete(tmp)
      if res.code ~= 0 or not res.stdout or res.stdout == '' then cb({}); return end
      local ok, decoded = pcall(vim.json.decode, res.stdout)
      local repository = ok and decoded and decoded.data and decoded.data.repository
      if not repository then cb({}); return end
      local prs = {}
      for i = 1, #branch_names do
        local pr_list = repository['a' .. i]
        for _, edge in ipairs((pr_list and pr_list.edges) or {}) do
          local node = edge.node
          node.state = (node.isDraft and node.state ~= 'CLOSED') and 'DRAFT' or node.state
          table.insert(prs, node)
        end
      end
      cb(prs)
    end)
  end)
end

-- ══════════════════════════════════════════════
-- ワークツリー
-- ══════════════════════════════════════════════

function M.worktrees(cb)
  M.run({ 'worktree', 'list', '--porcelain' }, function(res)
    local list = {}
    local current = nil
    for _, line in ipairs(vim.split(res.stdout or '', '\n', { plain = true })) do
      if line == '' then
        current = nil
      else
        local key, val = line:match('^(%S+)%s*(.*)$')
        if key == 'worktree' then
          current = { path = val }
          table.insert(list, current)
        elseif current then
          if key == 'branch' then
            current.branch = val:gsub('^refs/heads/', '')
          elseif key == 'bare' then
            current.bare = true
          elseif key == 'detached' then
            current.detached = true
          elseif key == 'HEAD' then
            current.head = val:sub(1, 7)
          end
        end
      end
    end
    cb(list)
  end, { dont_log = true })
end

function M.worktree_add(path, branch_name, as_new_branch, cb)
  local args = { 'worktree', 'add' }
  if as_new_branch then
    table.insert(args, '-b')
    table.insert(args, branch_name)
    table.insert(args, path)
  else
    table.insert(args, path)
    if branch_name and branch_name ~= '' then table.insert(args, branch_name) end
  end
  M.run(args, cb)
end

function M.worktree_remove(path, force, cb)
  local args = { 'worktree', 'remove' }
  if force then table.insert(args, '--force') end
  table.insert(args, path)
  M.run(args, cb)
end

return M
