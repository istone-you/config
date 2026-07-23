-- PRパネル: gh CLI でオープンなPRを一覧し、右に詳細を表示。ブラウザで開く/diff/checkout。

local git = require('config.git_panel.git')

local M = {}

-- ネットワーク取得(gh)なので定期自動更新の対象外。更新は R / パネル表示時のみ。
M.auto_refresh = false

local ctx
local prs = {}
local line_entries = {}
local total_rows = 0
local cursor_mem = nil -- 直前に選択していたPR番号
local shown_detail = nil -- 右に詳細表示中のPR番号（カーソル移動での再取得を抑制）
local detail_cache = {} -- [number] = 詳細のlines（再訪時に「読み込み中」を出さない）
local right_mode = 'detail' -- 右ペインの表示モード: 'detail' | 'diff'（dで切替、vはdiff時に効く）
-- 既定は「自分が作成 or 自分がレビュワー」のPRに絞る。fで変更。
local filter = { mode = 'mine', value = nil } -- mode: 'mine' | 'all' | 'author' | 'search'

local function filter_label()
  if filter.mode == 'all' then return '全て' end
  if filter.mode == 'author' then return '作者: ' .. (filter.value or '') end
  if filter.mode == 'search' then return '検索: ' .. (filter.value or '') end
  return '作成 / レビュー依頼'
end

local STATE_LABEL = { OPEN = 'Open', CLOSED = 'Closed', MERGED = 'Merged', DRAFT = 'Draft' }
local STATE_HL = {
  OPEN = 'GitPanelPrOpen', CLOSED = 'GitPanelPrClosed',
  MERGED = 'GitPanelPrMerged', DRAFT = 'GitPanelPrDraft',
}

local function current_entry()
  return ctx.current_entry(function() return line_entries end)
end

function M.remember_cursor()
  local e = current_entry()
  if e then cursor_mem = e.number end
end

local function show_detail(entry)
  if not entry then
    shown_detail = nil
    ctx.set_right_lines({ '  PRを選択してください' }, '', nil, 'pr:none')
    return
  end
  if shown_detail == entry.number then return end -- 同じPRなら再取得しない
  shown_detail = entry.number
  if detail_cache[entry.number] then -- 取得済みなら即表示（読み込み中を出さない）
    ctx.set_right_ansi(detail_cache[entry.number], 'pr:' .. entry.number)
    return
  end
  ctx.set_right_lines({ '  読み込み中...' }, '', nil, 'pr:loading:' .. entry.number)
  -- gh pr view の出力を整形せずそのまま（色・コメント込み）表示する
  git.gh_pr_view(entry.number, ctx.right_width(), function(text)
    -- 取得中に別のPRへ移っていたら破棄
    if shown_detail ~= entry.number then return end
    detail_cache[entry.number] = text
    ctx.set_right_ansi(text, 'pr:' .. entry.number)
  end)
end

-- diff表示。Filesと同じ ctx.set_right_diff を使う（deltaのside-by-side=vトグルもそのまま効く）
local function show_diff(entry)
  if not entry then ctx.set_right_lines({ '  PRを選択してください' }, '', nil, 'pr:none'); return end
  git.gh_pr_diff(entry.number, function(diff)
    if right_mode ~= 'diff' then return end -- 取得中にモードが変わっていたら破棄
    if diff == '' then
      ctx.set_right_lines({ '  diffを取得できませんでした' }, '', nil, 'pr:diff:none')
    else
      ctx.set_right_diff(diff, 'pr:diff:' .. entry.number)
    end
  end)
end

-- 現在のモードに応じて右ペインを描く（カーソル移動・refresh・vトグルから共通で呼ぶ）
local function show_right(entry)
  if right_mode == 'diff' then show_diff(entry) else show_detail(entry) end
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}
  local function push(text, entry, hlgroup)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup }) end
  end

  push('  Pull Requests  [' .. filter_label() .. ']  (f:フィルタ)', nil, 'GitPanelHeader')
  push('', nil)
  local remembered_row = nil
  for _, pr in ipairs(prs) do
    local label = STATE_LABEL[pr.state] or pr.state
    local author = (pr.author and pr.author.login) or '?'
    local prefix = string.format('  #%d [', pr.number)
    local line = prefix .. label .. '] ' .. pr.title .. '  (' .. author .. ') ← ' .. pr.headRefName
    push(line, pr)
    local hl = STATE_HL[pr.state]
    if hl then
      table.insert(hl_queue, { #lines - 1, hl, #prefix, #prefix + #label })
    end
    if cursor_mem == pr.number then remembered_row = #lines end
  end
  if #prs == 0 then push('  (該当PRなし / gh未認証・GitHub以外)', nil) end

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
    show_right(line_entries[target])
  else
    show_right(nil)
  end
end

-- 「自分が作成」と「自分がレビュワー」の2クエリを取得して番号でマージ（重複排除）
local function fetch_mine(cb)
  local merged, seen, pending = {}, {}, 2
  local function collect(list)
    for _, pr in ipairs(list or {}) do
      if not seen[pr.number] then
        seen[pr.number] = true
        merged[#merged + 1] = pr
      end
    end
    pending = pending - 1
    if pending == 0 then
      table.sort(merged, function(a, b) return a.number > b.number end)
      cb(merged)
    end
  end
  git.gh_pr_list({ '--author', '@me' }, collect)
  git.gh_pr_list({ '--search', 'review-requested:@me' }, collect)
end

function M.refresh(auto_capture)
  local function apply(list)
    prs = list or {}
    shown_detail = nil -- 一覧更新時は詳細も取り直す
    detail_cache = {}
    if auto_capture then M.remember_cursor() end
    render()
  end
  if filter.mode == 'mine' then
    fetch_mine(apply)
  elseif filter.mode == 'author' then
    git.gh_pr_list({ '--author', filter.value }, apply)
  elseif filter.mode == 'search' then
    git.gh_pr_list({ '--search', filter.value }, apply)
  else
    git.gh_pr_list({}, apply)
  end
end

local function open_web()
  local entry = current_entry()
  if not entry then return end
  git.gh_pr_web(entry.number, function(res)
    -- 失敗時（ブリッジ未起動・エラー等どんな理由でも）はURLをクリップボードにコピー
    if res.code ~= 0 then
      local url = entry.url or ''
      if url ~= '' then
        vim.fn.setreg('+', url)
        vim.fn.setreg('"', url)
        vim.notify('URLをコピーしました: ' .. url, vim.log.levels.INFO)
      else
        vim.notify('ブラウザで開けませんでした: ' .. (res.stderr or ''), vim.log.levels.WARN)
      end
    end
  end)
end

-- f: フィルタを選ぶ
local function choose_filter()
  ctx.menu('PRフィルタ', {
    { key = 'm', label = '作成 or レビュー依頼', value = 'mine' },
    { key = 'a', label = '全て（open）', value = 'all' },
    { key = 'u', label = '作者で絞る…', value = 'author' },
    { key = 's', label = '検索で絞る…（GitHub検索構文）', value = 'search' },
  }, function(choice)
    if not choice then return end
    if choice == 'author' then
      ctx.input('作者（@me / username）', filter.value or '@me', function(v)
        if v and v ~= '' then filter = { mode = 'author', value = v }; M.refresh() end
      end)
    elseif choice == 'search' then
      ctx.input('gh検索（例: label:bug draft:false）', filter.value or '', function(v)
        if v and v ~= '' then filter = { mode = 'search', value = v }; M.refresh() end
      end)
    else
      filter = { mode = choice }
      M.refresh()
    end
  end)
end

-- d: 詳細 ⇄ diff を切り替える
local function toggle_diff()
  right_mode = (right_mode == 'diff') and 'detail' or 'diff'
  shown_detail = nil -- 詳細の再取得抑制状態をリセット
  show_right(current_entry())
end

local function checkout()
  local entry = current_entry()
  if not entry then return end
  ctx.confirm('このPRのブランチをcheckoutしますか？\n#' .. entry.number .. ' ' .. entry.title, function(ok)
    if not ok then return end
    git.gh_pr_checkout(entry.number, function(res)
      ctx.render_cmdlog()
      if res.code == 0 then
        vim.notify('checkout: #' .. entry.number .. ' (' .. entry.headRefName .. ')', vim.log.levels.INFO)
        M.refresh()
      else
        vim.notify('checkoutに失敗: ' .. (res.stderr or ''), vim.log.levels.WARN)
      end
    end)
  end)
end

function M.keymaps()
  return {
    ['<CR>'] = open_web,
    o = open_web,
    d = toggle_diff,
    c = checkout,
    f = choose_filter,
  }
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    show_right
  )
  M.refresh()
end

return M
