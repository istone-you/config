-- 非同期git操作レイヤー（vim.system + on_exitコールバック、UIをブロックしない）
-- コマンドの実選択は lazygit本体(pkg/commands/git_commands) を参照して合わせている

local M = {}

M.root = nil
M.command_log = {}
local MAX_LOG = 200

local function log_command(args)
  table.insert(M.command_log, 1, 'git ' .. table.concat(args, ' '))
  if #M.command_log > MAX_LOG then
    table.remove(M.command_log)
  end
end

function M.find_root(cb)
  local args = { 'rev-parse', '--show-toplevel' }
  log_command(args)
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

function M.run(args, cb)
  local cmd = vim.list_extend({ 'git' }, args)
  log_command(args)
  vim.system(cmd, { cwd = M.root, text = true }, function(res)
    vim.schedule(function() cb(res) end)
  end)
end

-- ══════════════════════════════════════════════
-- status / diff / stage（working_tree.goのStageFiles/UnStageFileに合わせる）
-- ══════════════════════════════════════════════

function M.status(cb)
  -- --untracked-files=all: 未追跡ディレクトリを1行にまとめず配下ファイルを個別に列挙する
  M.run({ 'status', '--porcelain=v1', '--untracked-files=all' }, function(res) cb(res.stdout or '') end)
end

function M.branch_name(cb)
  M.run({ 'rev-parse', '--abbrev-ref', 'HEAD' }, function(res) cb(vim.trim(res.stdout or '')) end)
end

function M.diff_file(entry, cb)
  local args = (entry.section == 'staged')
    and { 'diff', '--cached', '--', entry.path }
    or { 'diff', '--', entry.path }
  M.run(args, function(res) cb(res.stdout or '') end)
end

function M.stage(path, cb) M.run({ 'add', '--', path }, cb) end
function M.unstage(path, cb) M.run({ 'reset', 'HEAD', '--', path }, cb) end
function M.stage_all(cb) M.run({ 'add', '-A' }, cb) end
function M.unstage_all(cb) M.run({ 'reset', 'HEAD' }, cb) end
function M.discard_file(path, cb) M.run({ 'checkout', '--', path }, cb) end
function M.clean_file(path, cb) M.run({ 'clean', '-f', '--', path }, cb) end
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
  end)
end

function M.amend(cb)
  M.run({ 'commit', '--amend', '--no-edit' }, cb)
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
    for _, line in ipairs(vim.split(res.stdout or '', '\n', { plain = true })) do
      if line ~= '' then
        local head, name, upstream, track = line:match('^(.-)\t(.-)\t(.-)\t(.*)$')
        if name then
          table.insert(list, { name = name, current = head == '*', upstream = upstream, track = track })
        end
      end
    end
    cb(list)
  end)
end

function M.checkout_branch(name, cb) M.run({ 'checkout', '--', name }, cb) end
function M.checkout_by_name(name, cb) M.run({ 'checkout', name }, cb) end
function M.checkout_previous(cb) M.run({ 'checkout', '-' }, cb) end
function M.create_branch(name, cb) M.run({ 'checkout', '-b', name }, cb) end
function M.delete_branch(name, force, cb) M.run({ 'branch', force and '-D' or '-d', name }, cb) end
function M.force_checkout(name, cb) M.run({ 'checkout', '-f', name }, cb) end
function M.merge_branch(name, cb) M.run({ 'merge', name }, cb) end
function M.rebase_branch(name, cb) M.run({ 'rebase', name }, cb) end
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
  end)
end

function M.show_commit(hash, cb) M.run({ 'show', hash }, function(res) cb(res.stdout or '') end) end
function M.reset(hash, mode, cb) M.run({ 'reset', '--' .. mode, hash }, cb) end
function M.revert_commit(hash, cb) M.run({ 'revert', '--no-edit', hash }, cb) end
function M.new_branch_from_commit(hash, name, cb) M.run({ 'checkout', '-b', name, hash }, cb) end

--- Undo(z): 直前のコミット1つだけをsoft resetで取り消す（lazygit本体のreflog Undoの
--- 「直前の操作がコミットだった」場合の挙動を再現。checkout/rebaseのUndoは対象外）
function M.undo_last_commit(cb) M.run({ 'reset', '--soft', 'HEAD@{1}' }, cb) end
function M.checkout_commit(hash, cb) M.run({ 'checkout', hash }, cb) end

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
  end)
end

function M.stash_show(ref, cb) M.run({ 'stash', 'show', '-p', ref }, function(res) cb(res.stdout or '') end) end
function M.stash_apply(ref, cb) M.run({ 'stash', 'apply', ref }, cb) end
function M.stash_pop(ref, cb) M.run({ 'stash', 'pop', ref }, cb) end
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
  end)
end

function M.push(cb) M.run({ 'push' }, cb) end
function M.push_set_upstream(remote, branch_name, cb) M.run({ 'push', '-u', remote, branch_name }, cb) end
function M.pull(cb) M.run({ 'pull' }, cb) end
function M.fetch(cb) M.run({ 'fetch' }, cb) end
function M.remote_names(cb)
  M.run({ 'remote' }, function(res)
    cb(vim.tbl_filter(function(l) return l ~= '' end, vim.split(res.stdout or '', '\n', { plain = true })))
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
  end)
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
