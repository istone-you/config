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

--- lazygit(pkg/gui/presentation/branches.go BranchStatus)と同じマーカー。
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

local PR_HL = {
  OPEN = 'GitPanelPrOpen', CLOSED = 'GitPanelPrClosed',
  MERGED = 'GitPanelPrMerged', DRAFT = 'GitPanelPrDraft',
}

--- lazygit(presentation/branches.go ShouldShowPrForBranch)と同じ:
--- main/master自身に紐づくPRは、CLOSED/MERGEDなら表示しない（もう関係ないとみなす）
local function visible_pr(name)
  local pr = prs_by_branch[name]
  if not pr then return nil end
  if MAIN_BRANCH_NAMES[name] and (pr.state == 'CLOSED' or pr.state == 'MERGED') then return nil end
  return pr
end

--- presentation/branches.go getBranchDisplayStrings相当: PRアイコンは名前の後ろではなく
--- 名前より前の固定幅カラムに置く（名前が長くても切れて見えなくなることがない）
local function pr_dot(name)
  local pr = visible_pr(name)
  if not pr then return nil end
  return { text = '●', hl = PR_HL[pr.state] }
end

--- 同じくgetBranchDisplayStrings相当: パネル幅から逆算して、右側のステータス表示
--- (branch_status)が常に見えるよう名前の方を省略記号(…)で切り詰める
local function truncate_name(name, max_width)
  if max_width < 1 then max_width = 1 end
  if vim.fn.strdisplaywidth(name) <= max_width then return name end
  local truncated = name
  while vim.fn.strchars(truncated) > 0 and vim.fn.strdisplaywidth(truncated) > max_width - 1 do
    truncated = vim.fn.strcharpart(truncated, 0, vim.fn.strchars(truncated) - 1)
  end
  return truncated .. '…'
end

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する
function M.remember_cursor()
  local entry = current_entry()
  if entry then cursor_mem = entry.name end
end

local PR_STATE_LABEL = { OPEN = 'Open', CLOSED = 'Closed', MERGED = 'Merged', DRAFT = 'Draft' }

--- branches_controller.go GetOnRenderToMain相当: 選択中のブランチにPRがあれば、
--- ログの前に「状態  タイトル  #番号」のヘッダー+区切り線を差し込む
local function show_detail(entry)
  if not entry then ctx.set_right_lines({}); return end
  local pr = visible_pr(entry.name)
  git.run({ 'log', '-n', '20', '--pretty=format:%h %s (%ar)', entry.name }, function(res)
    local lines = vim.split(res.stdout or '', '\n', { plain = true })
    local hl_queue = nil
    if pr then
      local header = (PR_STATE_LABEL[pr.state] or pr.state) .. '  ' .. pr.title .. '  #' .. pr.number
      local win_id = ctx.get_right_win()
      local width = (win_id and vim.api.nvim_win_is_valid(win_id)) and vim.api.nvim_win_get_width(win_id) or 40
      table.insert(lines, 1, string.rep('─', width))
      table.insert(lines, 1, header)
      hl_queue = { { 0, PR_HL[pr.state], 0, #(PR_STATE_LABEL[pr.state] or pr.state) } }
    end
    ctx.set_right_lines(lines, '', hl_queue, entry.name)
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

  -- getBranchDisplayStrings相当: [current marker][PRドット(固定幅)][名前(省略可)+状態]
  -- の順。PRドットは名前より前に置くことで、名前が長くても絶対に見えるようにする
  local win_id = ctx.get_left_win()
  local win_width = (win_id and vim.api.nvim_win_is_valid(win_id)) and vim.api.nvim_win_get_width(win_id) or 80

  local remembered_row = nil
  for _, b in ipairs(branches) do
    local marker = b.current and '* ' or '  '
    local dot = pr_dot(b.name)
    local lead = '  ' .. marker .. (dot and (dot.text .. ' ') or '  ')
    local status = branch_status(b)
    local status_w = status and vim.fn.strdisplaywidth(status.text) or 0
    local max_name_w = math.max(3, win_width - vim.fn.strdisplaywidth(lead) - status_w - 1)
    local display_name = truncate_name(b.name, max_name_w)
    local prefix = lead .. display_name
    push(prefix .. (status and status.text or ''), b, b.current and 'GitPanelCurrent' or nil)
    if dot then
      local dot_start = #('  ' .. marker)
      table.insert(hl_queue, { #lines - 1, dot.hl, dot_start, dot_start + #dot.text })
    end
    if status then
      -- current行のGitPanelCurrent(全体緑)より後に積むことで、乖離時の黄/赤マーカーを
      -- ステータス部分だけ確実に上書き表示する
      table.insert(hl_queue, { #lines - 1, status.hl, #prefix, #prefix + #status.text })
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

--- auto_capture: 自動更新(2秒おき)/Rキーからの汎用refreshの時だけtrueで渡される。
--- render()の直前というできるだけ遅いタイミングで今のカーソル位置を捕捉することで、
--- 非同期処理中にユーザーがj/kで動かした分を取りこぼさないようにする
function M.refresh(auto_capture)
  git.branches(function(list)
    branches = list
    if auto_capture then M.remember_cursor() end
    render()
  end)
end

--- GitHub PR取得(pkg/commands/git_commands/github.go相当)。gh CLI未認証やGitHub以外の
--- リモートなら黒く諦めて何も表示しない。lazygitはfetch完了時(PostFetchRefresh)に
--- これを行うので、Branchesパネルに入った時(activate)に加えてfiles.luaのfetch()完了時にも
--- 外部から呼べるよう公開関数にしている。branchesは呼び出し時点でのものを取り直す
--- （外部から呼ばれる場合、モジュール内のbranchesがまだ古い/空のことがあるため）
function M.refresh_prs()
  git.github_repo_info(function(repo_info)
    if not repo_info then return end
    git.gh_auth_token(function(token)
      if not token then return end
      git.branches(function(list)
        branches = list
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
          -- push/pull/fetch完了時などBranchesパネル外から呼ばれることがあるため、
          -- ctxが未設定(一度もactivateされていない)、または今表示中のパネルが
          -- branchesでない場合はrenderしない（今見えている別パネルのバッファを
          -- 壊してしまうのを防ぐ）。データ自体(prs_by_branch)は更新済みなので、
          -- 次にBranchesパネルへ入った時には反映される
          if ctx and ctx.current_panel_name() == 'branches' then render() end
        end)
      end)
    end)
  end)
end

local function checkout()
  local entry = current_entry()
  if not entry then return end
  cursor_mem = entry.name
  git.checkout_branch(entry.name, ctx.done_refresh(M.refresh, 'チェックアウト'))
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

--- branches_controller.go checkoutByName相当。lazygitはPrompt+FindSuggestionsFunc
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
          git.checkout_branch(branch_part, ctx.done_refresh(M.refresh, 'チェックアウト'))
        else
          cursor_mem = branch_part
          git.run({ 'checkout', '-b', branch_part, '--track', text }, ctx.done_refresh(M.refresh, 'チェックアウト'))
        end
      end)
    end)
  end)
end

local function checkout_previous()
  git.checkout_previous(ctx.done_refresh(M.refresh, 'チェックアウト'))
end

local function create()
  ctx.input('新規ブランチ名', '', function(name)
    if not name or name == '' then return end
    cursor_mem = name
    git.create_branch(name, ctx.done_refresh(M.refresh, '作成'))
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
        git.delete_branch(entry.name, true, ctx.done_refresh(M.refresh, '削除'))
      end)
    end)
  end)
end

--- GitHub PRステータスがMergedになっているローカルブランチをまとめて削除する。
--- squash/rebase mergeだとローカルの履歴からはマージ済みと判定できず
--- `git branch -d`が失敗するため、PRステータスを根拠に最初からforce delete(-D)する
local function delete_merged_prs()
  local targets = {}
  for _, b in ipairs(branches) do
    if not b.current then
      local pr = visible_pr(b.name)
      if pr and pr.state == 'MERGED' then table.insert(targets, b.name) end
    end
  end
  if #targets == 0 then
    vim.notify('PRがMergedのブランチはありません', vim.log.levels.INFO)
    return
  end
  ctx.confirm(
    '次の' .. #targets .. '件を削除しますか？(PRがMerged, force delete)\n' .. table.concat(targets, '\n'),
    function(ok)
      if not ok then return end
      cursor_mem = nil
      local pending = #targets
      local failed = {}
      local function done()
        pending = pending - 1
        if pending == 0 then
          ctx.render_cmdlog()
          if #failed > 0 then
            vim.notify('削除に失敗: ' .. table.concat(failed, ', '), vim.log.levels.ERROR)
          end
          M.refresh()
        end
      end
      for _, name in ipairs(targets) do
        git.delete_branch(name, true, function(res)
          if res.code ~= 0 then table.insert(failed, name) end
          done()
        end)
      end
    end
  )
end

local function force_checkout()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('作業ツリーの変更をすべて破棄して "' .. entry.name .. '" を強制チェックアウトしますか？', function(ok)
    if not ok then return end
    cursor_mem = entry.name
    git.force_checkout(entry.name, ctx.done_refresh(M.refresh, '強制チェックアウト'))
  end)
end

local function merge()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチに "' .. entry.name .. '" をマージしますか？', function(ok)
    if not ok then return end
    git.merge_branch(entry.name, ctx.done_refresh(M.refresh, 'マージ'))
  end)
end

local function rebase()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('現在のブランチを "' .. entry.name .. '" にリベースしますか？', function(ok)
    if not ok then return end
    git.rebase_branch(entry.name, ctx.done_refresh(M.refresh, 'リベース'))
  end)
end

local function rename()
  local entry = current_entry()
  if not entry then return end
  ctx.input('リネーム', entry.name, function(new_name)
    if not new_name or new_name == '' or new_name == entry.name then return end
    cursor_mem = new_name
    git.rename_branch(entry.name, new_name, ctx.done_refresh(M.refresh, 'リネーム'))
  end)
end

local function fast_forward()
  local entry = current_entry()
  if not entry then return end
  if entry.upstream == '' then
    vim.notify('アップストリームが設定されていません', vim.log.levels.WARN)
    return
  end
  git.fast_forward(entry.name, ctx.done_refresh(M.refresh, 'fast-forward'))
end

local function set_upstream()
  local entry = current_entry()
  if not entry then return end
  ctx.input('アップストリームに設定 (remote)', 'origin', function(remote)
    if not remote or remote == '' then return end
    git.set_upstream(remote, entry.name, ctx.done_refresh(M.refresh, 'アップストリーム設定'))
  end)
end

local function copy_branch_name()
  local entry = current_entry()
  if not entry then return end
  vim.fn.setreg('"', entry.name)
  pcall(vim.fn.setreg, '+', entry.name)
  vim.notify('コピーしました: ' .. entry.name, vim.log.levels.INFO)
end

function M.keymaps()
  return {
    ['<Space>'] = checkout,
    c = checkout_by_name,
    ['-'] = checkout_previous,
    n = create,
    d = delete,
    D = delete_merged_prs,
    F = force_checkout,
    M = merge,
    r = rebase,
    R = rename,
    f = fast_forward,
    u = set_upstream,
    y = copy_branch_name,
  }
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    show_detail
  )
  M.refresh()
  M.refresh_prs()
end

return M
