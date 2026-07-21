-- Branchesパネル: 一覧・チェックアウト・作成・削除・マージ・リベース・リネーム・fast-forward
-- キーはpkg/config/user_config.go デフォルト(KeybindingBranchesConfig)に合わせている

local git = require('config.git_panel.git')

local M = {}

local ctx
local branches = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local prs_by_branch = {}  -- [branch_name] = { number, state, url, ... }
local MAIN_BRANCH_NAMES = { master = true, main = true }

--- lazygit本体(pkg/gui/presentation/branches.go BranchStatus)と同じマーカー。
--- 本物にはアップストリーム名自体を表示する機能は無く、状態マーカーのみが表示される。
--- 同期済み=緑✓ / 乖離あり=黄↓behind↑ahead / アップストリーム削除済み=赤(upstream gone)
--- ※ RemoteBranchNotStoredLocally（設定はあるがfetch未実施で追跡refが無い）の判定は
---   git config側を見る必要があり、for-each-refベースの現在のデータ取得方法では
---   「アップストリーム未設定」と区別できないため未実装
local function branch_status(b)
  if not b.upstream or b.upstream == '' then return nil end
  if b.track == '[gone]' then return { text = ' (upstream gone)', hl = 'GitPanelUnpushed' } end
  local ahead = b.track and b.track:match('ahead (%d+)')
  local behind = b.track and b.track:match('behind (%d+)')
  if not ahead and not behind then return { text = ' ✓', hl = 'GitPanelMerged' } end
  local parts = {}
  if behind then table.insert(parts, '↓' .. behind) end
  if ahead then table.insert(parts, '↑' .. ahead) end
  return { text = ' ' .. table.concat(parts), hl = 'GitPanelPushed' }
end

--- lazygit本体(presentation/branches.go ShouldShowPrForBranch)と同じ:
--- main/master自身に紐づくPRは、CLOSED/MERGEDなら表示しない（もう関係ないとみなす）
local function pr_marker(name)
  local pr = prs_by_branch[name]
  if not pr then return nil end
  if MAIN_BRANCH_NAMES[name] and (pr.state == 'CLOSED' or pr.state == 'MERGED') then return nil end
  local hl = ({
    OPEN = 'GitPanelPrOpen', CLOSED = 'GitPanelPrClosed',
    MERGED = 'GitPanelPrMerged', DRAFT = 'GitPanelPrDraft',
  })[pr.state]
  return { text = ' ● #' .. pr.number, hl = hl }
end

local function current_entry()
  local win = ctx.get_left_win()
  if not win then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return line_entries[row]
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する
function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.name end
end

local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  git.run({ 'log', '-n', '20', '--pretty=format:%h %s (%ar)', entry.name }, function(res)
    ctx.set_right_lines(vim.split(res.stdout or '', '\n', { plain = true }), '')
  end, { dont_log = true })
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  push('  ローカルブランチ', nil, 'GitPanelHeader')
  push('', nil)

  local remembered_row = nil
  for _, b in ipairs(branches) do
    local marker = b.current and '* ' or '  '
    local prefix = '  ' .. marker .. b.name
    local status = branch_status(b)
    local pr = pr_marker(b.name)
    push(prefix .. (status and status.text or '') .. (pr and pr.text or ''), b, b.current and 'GitPanelCurrent' or nil)
    if status then
      -- current行のGitPanelCurrent(全体緑)より後に積むことで、乖離時の黄/赤マーカーを
      -- ステータス部分だけ確実に上書き表示する
      table.insert(hl_queue, { #lines - 1, status.hl, #prefix, #prefix + #status.text })
    end
    if pr then
      local pr_base = #prefix + (status and #status.text or 0)
      table.insert(hl_queue, { #lines - 1, pr.hl, pr_base, pr_base + #pr.text })
    end
    if cursor_mem == b.name then remembered_row = #lines end
  end
  if #branches == 0 then push('  (ブランチなし)', nil) end

  total_rows = #lines
  ctx.set_left_lines(lines, hl_queue)

  local target = remembered_row
  if not target then
    for i = 1, total_rows do
      if line_entries[i] then target = i; break end
    end
  end
  if target then
    ctx.set_left_cursor(target)
    show_detail(line_entries[target])
  else
    show_detail(nil)
  end
end

--- after: branchesデータが実際に届いた後に呼ぶコールバック（PR取得はactivate時だけ
--- 続けて行いたいが、branches取得自体は非同期なので完了を待たないとリストが空/古いままになる）
local function do_refresh(after)
  git.branches(function(list)
    branches = list
    render()
    if after then after() end
  end)
end

function M.refresh() do_refresh() end

--- GitHub PR取得(pkg/commands/git_commands/github.go相当)。gh CLI未認証やGitHub以外の
--- リモートなら黒く諦めて何も表示しない。API呼び出しを毎回の自動更新(2秒おき)で叩くのは
--- 負荷/レート制限的に良くないので、Branchesパネルに入った時(activate)だけ取得する
local function refresh_prs()
  git.github_repo_info(function(repo_info)
    if not repo_info then return end
    git.gh_auth_token(function(token)
      if not token then return end
      local branch_names = {}
      for _, b in ipairs(branches) do
        if b.upstream and b.upstream ~= '' then
          local short = b.upstream:match('^[^/]+/(.+)$')
          if short then table.insert(branch_names, short) end
        end
      end
      git.fetch_prs(repo_info.owner, repo_info.repo, token, branch_names, function(prs)
        -- prByKey相当: owner(大小無視)+headRefNameで最新の1件のみ採用（forkは非対応、
        -- 同オーナーのリポジトリへの直接PRのみ扱う）
        local by_ref = {}
        for _, pr in ipairs(prs) do
          if pr.headRepositoryOwner and pr.headRepositoryOwner.login
            and pr.headRepositoryOwner.login:lower() == repo_info.owner:lower()
            and not by_ref[pr.headRefName]
          then
            by_ref[pr.headRefName] = pr
          end
        end
        local map = {}
        for _, b in ipairs(branches) do
          if b.upstream and b.upstream ~= '' then
            local short = b.upstream:match('^[^/]+/(.+)$')
            if short and by_ref[short] then map[b.name] = by_ref[short] end
          end
        end
        prs_by_branch = map
        render()
      end)
    end)
  end)
end

local function done_refresh(label)
  return function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then vim.notify(label .. '失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
    M.refresh()
  end
end

local function checkout()
  local entry = current_entry()
  if not entry then return end
  cursor_mem = entry.name
  git.checkout_branch(entry.name, done_refresh('チェックアウト'))
end

--- refs_helper.go CheckoutRef の OnRefNotFound 相当:
--- 指定したref/名前が存在しなければ、パネルでカーソルが乗っていたブランチを起点に
--- 新規ブランチとして作成するか確認する
local function checkout_ref_or_create(ref, base_entry)
  git.checkout_by_name(ref, function(res)
    ctx.render_cmdlog()
    if res.code == 0 then
      cursor_mem = ref
      M.refresh()
      return
    end
    local base_name = base_entry and base_entry.name or 'HEAD'
    ctx.confirm(
      'ブランチ/refが見つかりません。\n"' .. ref .. '" を ' .. base_name .. ' から新規ブランチとして作成しますか？',
      function(ok)
        if not ok then return end
        git.run({ 'checkout', '-b', ref, base_name }, function(res2)
          ctx.render_cmdlog()
          if res2.code ~= 0 then
            vim.notify('作成失敗: ' .. (res2.stderr or ''), vim.log.levels.ERROR)
            return
          end
          cursor_mem = ref
          M.refresh()
        end)
      end
    )
  end)
end

--- branches_controller.go checkoutByName相当。lazygit本体はPrompt+FindSuggestionsFunc
--- (GetRefsSuggestionsFunc: リモート追跡ブランチ+ローカルブランチ+タグ+HEAD系ref)で
--- 入力中にリアルタイム候補を出す。"remote/branch"形式で選んだ場合はParseRemoteBranchName+
--- CheckoutRemoteBranch相当（ローカルに同名ブランチが既にあればそれをチェックアウト、
--- 無ければ--trackで新規作成）
local function checkout_by_name()
  local base_entry = current_entry()
  git.ref_candidates(function(candidates)
    ctx.suggest_input('チェックアウト (ref名)', function(input)
      if input == '' then return candidates end
      return vim.fn.matchfuzzy(candidates, input)
    end, function(text)
      if not text or text == '' then return end
      local remote, branch_part = text:match('^([^/]+)/(.+)$')
      if not remote then
        checkout_ref_or_create(text, base_entry)
        return
      end
      git.remote_names(function(remotes)
        if not vim.tbl_contains(remotes, remote) then
          checkout_ref_or_create(text, base_entry)
          return
        end
        local has_local = false
        for _, b in ipairs(branches) do
          if b.name == branch_part then has_local = true end
        end
        if has_local then
          cursor_mem = branch_part
          git.checkout_branch(branch_part, done_refresh('チェックアウト'))
        else
          cursor_mem = branch_part
          git.run({ 'checkout', '-b', branch_part, '--track', text }, done_refresh('チェックアウト'))
        end
      end)
    end)
  end)
end

local function checkout_previous()
  git.checkout_previous(done_refresh('チェックアウト'))
end

local function create()
  ctx.input('新規ブランチ名', '', function(name)
    if not name or name == '' then return end
    cursor_mem = name
    git.create_branch(name, done_refresh('作成'))
  end)
end

local function delete()
  local entry = current_entry()
  if not entry then return end
  if entry.current then
    vim.notify('現在のブランチは削除できません', vim.log.levels.WARN)
    return
  end
  ctx.confirm('ブランチ "' .. entry.name .. '" を削除しますか？', function(ok)
    if not ok then return end
    git.delete_branch(entry.name, false, function(res)
      ctx.render_cmdlog()
      if res.code == 0 then cursor_mem = nil; M.refresh(); return end
      ctx.confirm('マージされていません。強制削除しますか？\n' .. entry.name, function(force_ok)
        if not force_ok then return end
        cursor_mem = nil
        git.delete_branch(entry.name, true, done_refresh('削除'))
      end)
    end)
  end)
end

local function force_checkout()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('作業ツリーの変更をすべて破棄して "' .. entry.name .. '" を強制チェックアウトしますか？', function(ok)
    if not ok then return end
    cursor_mem = entry.name
    git.force_checkout(entry.name, done_refresh('強制チェックアウト'))
  end)
end

local function merge()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチに "' .. entry.name .. '" をマージしますか？', function(ok)
    if not ok then return end
    git.merge_branch(entry.name, done_refresh('マージ'))
  end)
end

local function rebase()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチを "' .. entry.name .. '" にリベースしますか？', function(ok)
    if not ok then return end
    git.rebase_branch(entry.name, done_refresh('リベース'))
  end)
end

local function rename()
  local entry = current_entry()
  if not entry then return end
  ctx.input('リネーム', entry.name, function(new_name)
    if not new_name or new_name == '' or new_name == entry.name then return end
    cursor_mem = new_name
    git.rename_branch(entry.name, new_name, done_refresh('リネーム'))
  end)
end

local function fast_forward()
  local entry = current_entry()
  if not entry then return end
  if entry.upstream == '' then
    vim.notify('アップストリームが設定されていません', vim.log.levels.WARN)
    return
  end
  git.fast_forward(entry.name, done_refresh('fast-forward'))
end

local function set_upstream()
  local entry = current_entry()
  if not entry then return end
  ctx.input('アップストリームに設定 (remote)', 'origin', function(remote)
    if not remote or remote == '' then return end
    git.set_upstream(remote, entry.name, done_refresh('アップストリーム設定'))
  end)
end

function M.keymaps()
  return {
    ['<Space>'] = checkout,
    c = checkout_by_name,
    ['-'] = checkout_previous,
    n = create,
    d = delete,
    F = force_checkout,
    M = merge,
    r = rebase,
    R = rename,
    f = fast_forward,
    u = set_upstream,
  }
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    show_detail
  )
  do_refresh(refresh_prs)
end

return M
