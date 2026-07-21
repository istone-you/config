-- Filesパネル: ディレクトリツリー表示（lazygit実機のデフォルト gui.showFileTree=true に合わせる）
-- ステージ/アンステージ・hunk単位ステージ・破棄・コミット・amend・stash・ignore

local git = require('config.git_panel.git')

local M = {}

local ctx
local branch = ''
local files = {}       -- { path, x, y }  x=staged状態, y=未ステージ状態（porcelainの生文字）
local tree_root = nil
local collapsed = {}    -- [dir_path] = true
local line_entries = {}
local total_rows = 0
local cursor_mem = nil
local hunk_state = nil
local hunk_hl_ns = vim.api.nvim_create_namespace('git_panel_hunk')

local function is_untracked(f) return f.x == '?' and f.y == '?' end
local function has_staged(f) return f.x ~= ' ' and f.x ~= '?' end
local function has_unstaged(f) return f.y ~= ' ' or is_untracked(f) end

local function parse_status(output)
  local list = {}
  for _, line in ipairs(vim.split(output or '', '\n', { plain = true })) do
    if line ~= '' then
      local x, y, path = line:sub(1, 1), line:sub(2, 2), line:sub(4)
      local arrow_at = path:find(' %-> ')
      if arrow_at then path = path:sub(arrow_at + 4) end
      table.insert(list, { path = path, x = x, y = y })
    end
  end
  return list
end

-- ══════════════════════════════════════════════
-- ツリー構築
-- ══════════════════════════════════════════════

local function build_tree(list)
  local root = { name = '', path = '', is_dir = true, children = {} }
  local dir_index = { [''] = root }

  local function get_or_create_dir(path)
    if dir_index[path] then return dir_index[path] end
    local parent_path = path:match('^(.*)/[^/]+$') or ''
    local parent = get_or_create_dir(parent_path)
    local name = path:match('([^/]+)$')
    local node = { name = name, path = path, is_dir = true, children = {} }
    table.insert(parent.children, node)
    dir_index[path] = node
    return node
  end

  for _, f in ipairs(list) do
    local dir_path = f.path:match('^(.*)/[^/]+$') or ''
    local parent = get_or_create_dir(dir_path)
    local name = f.path:match('([^/]+)$')
    table.insert(parent.children, { name = name, path = f.path, is_dir = false, file = f })
  end

  local function sort_children(node)
    table.sort(node.children, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, c in ipairs(node.children) do
      if c.is_dir then sort_children(c) end
    end
  end
  sort_children(root)
  return root
end

local function node_flags(node)
  if not node.is_dir then
    return has_staged(node.file), has_unstaged(node.file)
  end
  local any_s, any_u = false, false
  for _, c in ipairs(node.children) do
    local s, u = node_flags(c)
    any_s = any_s or s
    any_u = any_u or u
  end
  return any_s, any_u
end

local function collect_files(node, out)
  out = out or {}
  if node.is_dir then
    for _, c in ipairs(node.children) do collect_files(c, out) end
  else
    table.insert(out, node.file)
  end
  return out
end

-- ══════════════════════════════════════════════
-- アイコン（拡張子ごと、tabline.lua/explorer.luaと同方式）
-- ══════════════════════════════════════════════

local function icon_char(code) return vim.fn.nr2char(code) end
local FOLDER_ICON, DEFAULT_ICON = 0xe5ff, 0xf15b
local FILE_ICONS = {
  lua = 0xe620, ts = 0xe628, tsx = 0xe628, js = 0xe74e, jsx = 0xe74e,
  go = 0xe626, py = 0xe606, rs = 0xe7a8, rb = 0xe739, md = 0xe73e,
  json = 0xe60b, toml = 0xe6b2, sh = 0xe615, yml = 0xe6a8, yaml = 0xe6a8,
}
local function get_icon(name, is_dir)
  if is_dir then return icon_char(FOLDER_ICON) end
  local ext = name:match('%.([^%.]+)$')
  return icon_char((ext and FILE_ICONS[ext]) or DEFAULT_ICON)
end

-- ══════════════════════════════════════════════
-- 描画
-- ══════════════════════════════════════════════

local function current_entry()
  local win = ctx.get_left_win()
  if not win then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return line_entries[row]
end

--- 明示的な操作を伴わないrefresh（自動更新・Rキー）の直前に呼ばれ、今カーソルが
--- 乗っている項目をcursor_memに反映する。個別の操作関数が意図的にcursor_mem
--- を設定/nil化した直後にrefresh()する場合はこれを経由しないので上書きされない
function M.remember_cursor()
  local node = current_entry()
  if node then cursor_mem = node.path end
end

local function show_diff_for(node, prefer_staged)
  if not node then ctx.set_right_lines({}); return end
  if node.is_dir then
    ctx.set_right_lines({ '  ' .. #collect_files(node) .. ' 個のファイル' })
    return
  end
  local f = node.file
  if is_untracked(f) then
    local full = ctx.get_root() .. '/' .. f.path
    if vim.fn.isdirectory(full) == 1 then
      ctx.set_right_lines({ '(ディレクトリ: ' .. f.path .. ')' })
      return
    end
    local ok, content = pcall(vim.fn.readfile, full)
    if ok then
      local lines = { '+++ ' .. f.path, '' }
      for _, l in ipairs(content) do table.insert(lines, '+' .. l) end
      ctx.set_right_lines(lines, 'diff')
    else
      ctx.set_right_lines({ '(バイナリまたは読み込み不可)' })
    end
    return
  end
  local section = (prefer_staged and has_staged(f)) and 'staged' or (has_unstaged(f) and 'unstaged' or 'staged')
  git.diff_file({ path = f.path, section = section }, function(diff_text)
    ctx.set_right_lines(vim.split(diff_text, '\n', { plain = true }), 'diff')
  end)
end

--- lazygit本体(pkg/gui/presentation/files.go formatFileStatus)と同じ配色:
--- 1文字目(index=staged側)は緑、ただし'?'(untracked)は赤、空白は無色。
--- 2文字目(worktree=unstaged側)は常に赤、空白は無色。
--- M/A/D等の文字の「意味」では色分けしない。あくまで列の位置だけで決まる
local function status_char_hl(ch, is_staged_col)
  if ch == ' ' then return nil end
  if is_staged_col and ch ~= '?' then return 'GitPanelStatusStaged' end
  return 'GitPanelStatusUnstaged'
end

local function render()
  local lines, hl_queue = {}, {}
  line_entries = {}

  local function push(text, entry, hlgroup, col_start, col_end)
    table.insert(lines, text)
    line_entries[#lines] = entry
    if hlgroup then table.insert(hl_queue, { #lines - 1, hlgroup, col_start, col_end }) end
  end

  push('  ' .. (branch ~= '' and branch or '(no branch)'), nil, 'GitPanelHeader')
  push('', nil)

  -- lazygit本体のShowRootItemInFileTree(デフォルトtrue)に合わせ、ルートを"/"として
  -- 選択可能な1行にする。ここでSpaceを押すと全ファイルがステージ/アンステージされる
  local remembered_row = nil
  local function walk(node, depth)
    local is_root = node.path == ''
    local display_name = is_root and '/' or node.name
    local s, u = node_flags(node)
    -- ファイル名(+アイコン/ディレクトリの矢印)の色: 実物のnameColorと同じ
    -- staged onlyなら緑、staged+unstagedなら黄、それ以外は無色
    local name_color
    if s and not u then name_color = 'GitPanelAdded'
    elseif s then name_color = 'GitPanelModified'
    end
    local indent = string.rep('  ', depth)
    local status_str
    if node.is_dir then
      status_str = collapsed[node.path] and '▶' or '▼'
    else
      status_str = node.file.x .. node.file.y
    end
    local icon = get_icon(display_name, node.is_dir)
    local status_prefix = '  ' .. indent
    local before_name = status_prefix .. status_str .. ' '
    local line = before_name .. icon .. ' ' .. display_name
    -- name_colorはアイコン+ファイル名部分だけに適用する（ステータス文字は別配色）
    push(line, node, name_color, #before_name, #line)
    if cursor_mem == node.path then remembered_row = #lines end

    local status_base = #status_prefix
    if node.is_dir then
      if name_color then
        table.insert(hl_queue, { #lines - 1, name_color, status_base, status_base + #status_str })
      end
    else
      local c1 = status_char_hl(node.file.x, true)
      local c2 = status_char_hl(node.file.y, false)
      if c1 then table.insert(hl_queue, { #lines - 1, c1, status_base, status_base + 1 }) end
      if c2 then table.insert(hl_queue, { #lines - 1, c2, status_base + 1, status_base + 2 }) end
    end

    if node.is_dir and not collapsed[node.path] then
      for _, c in ipairs(node.children) do
        walk(c, depth + 1)
      end
    end
  end
  walk(tree_root, 0)

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
    show_diff_for(line_entries[target])
  else
    show_diff_for(nil)
  end
end

function M.refresh()
  local pending = 2
  local function done()
    pending = pending - 1
    if pending == 0 then
      tree_root = build_tree(files)
      render()
    end
  end
  git.branch_name(function(name) branch = name; done() end)
  git.status(function(out) files = parse_status(out); done() end)
end

-- ══════════════════════════════════════════════
-- hunk単位ステージング
-- ══════════════════════════════════════════════

local function leave_staging_mode()
  hunk_state = nil
  ctx.refocus_left()
  show_diff_for(current_entry())
end

local function render_hunk_view()
  local lines = {}
  vim.list_extend(lines, hunk_state.header)
  local ranges = {}
  for i, hunk in ipairs(hunk_state.hunks) do
    local start = #lines
    table.insert(lines, hunk.header)
    vim.list_extend(lines, hunk.lines)
    ranges[i] = { start, #lines - 1 }
  end
  hunk_state.ranges = ranges
  ctx.set_right_lines(lines, 'diff')

  local rbuf = ctx.get_right_buf()
  if rbuf and vim.api.nvim_buf_is_valid(rbuf) then
    vim.api.nvim_buf_clear_namespace(rbuf, hunk_hl_ns, 0, -1)
    local r = ranges[hunk_state.idx]
    if r then
      for ln = r[1], r[2] do
        vim.api.nvim_buf_add_highlight(rbuf, hunk_hl_ns, 'GitPanelHunkSelected', ln, 0, -1)
      end
    end
  end
end

local function move_hunk(delta)
  hunk_state.idx = math.max(1, math.min(#hunk_state.hunks, hunk_state.idx + delta))
  render_hunk_view()
end

local function stage_current_hunk()
  local hunk = hunk_state.hunks[hunk_state.idx]
  local opts = hunk_state.staged and { cached = true, reverse = true } or { cached = true }
  git.apply_hunk(hunk_state.header, hunk, opts, function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then
      vim.notify('hunk適用に失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    leave_staging_mode()
    M.refresh()
  end)
end

local function discard_current_hunk()
  if hunk_state.staged then
    stage_current_hunk()
    return
  end
  local hunk = hunk_state.hunks[hunk_state.idx]
  local header = hunk_state.header
  ctx.confirm('このhunkを破棄しますか？', function(ok)
    if not ok then return end
    git.apply_hunk(header, hunk, { reverse = true }, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then
        vim.notify('破棄に失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR)
        return
      end
      leave_staging_mode()
      M.refresh()
    end)
  end)
end

local function toggle_hunk_view_side()
  local node = hunk_state.node
  local f = node.file
  if not (has_staged(f) and has_unstaged(f)) then return end
  hunk_state.staged = not hunk_state.staged
  git.diff_file({ path = f.path, section = hunk_state.staged and 'staged' or 'unstaged' }, function(diff_text)
    local header, hunks = git.parse_hunks(diff_text)
    hunk_state.header, hunk_state.hunks, hunk_state.idx = header, hunks, 1
    render_hunk_view()
  end)
end

local function setup_hunk_keymaps()
  local rbuf = ctx.get_right_buf()
  local function map(key, fn) vim.keymap.set('n', key, fn, { buffer = rbuf, nowait = true, silent = true }) end
  map('h', function() move_hunk(-1) end)
  map('<Left>', function() move_hunk(-1) end)
  map('l', function() move_hunk(1) end)
  map('<Right>', function() move_hunk(1) end)
  map('<Space>', stage_current_hunk)
  map('d', discard_current_hunk)
  map('<Tab>', toggle_hunk_view_side)
  map('<Esc>', leave_staging_mode)
  map('q', leave_staging_mode)
end

local function enter_staging_mode()
  local node = current_entry()
  if not node or node.is_dir then return end
  local f = node.file
  if is_untracked(f) then
    vim.notify('新規ファイルはhunk単位のステージに未対応です。Spaceでファイル単位でステージしてください', vim.log.levels.WARN)
    return
  end
  local staged_first = has_staged(f) and not has_unstaged(f)
  git.diff_file({ path = f.path, section = staged_first and 'staged' or 'unstaged' }, function(diff_text)
    local header, hunks = git.parse_hunks(diff_text)
    if #hunks == 0 then return end
    hunk_state = { node = node, header = header, hunks = hunks, idx = 1, staged = staged_first }
    render_hunk_view()
    local rwin = ctx.get_right_win()
    if rwin and vim.api.nvim_win_is_valid(rwin) then
      vim.api.nvim_set_current_win(rwin)
    end
    setup_hunk_keymaps()
  end)
end

-- ══════════════════════════════════════════════
-- 操作（ファイル or ディレクトリ配下すべてに適用）
-- ══════════════════════════════════════════════

local function toggle_collapse()
  local node = current_entry()
  if not node or not node.is_dir then return end
  collapsed[node.path] = not collapsed[node.path]
  cursor_mem = node.path
  render()
end

local function enter_or_toggle()
  local node = current_entry()
  if not node then return end
  if node.is_dir then toggle_collapse() else enter_staging_mode() end
end

local function stage_toggle()
  local node = current_entry()
  if not node then return end
  local targets = collect_files(node)
  if #targets == 0 then return end
  cursor_mem = node.path
  local any_unstaged = false
  for _, f in ipairs(targets) do
    if has_unstaged(f) then any_unstaged = true; break end
  end
  local paths = vim.tbl_map(function(f) return f.path end, targets)
  local function done() ctx.render_cmdlog(); M.refresh() end
  if any_unstaged then
    git.run(vim.list_extend({ 'add', '--' }, paths), done)
  else
    git.run(vim.list_extend({ 'reset', 'HEAD', '--' }, paths), done)
  end
end

local function stage_all_toggle()
  local any_unstaged = false
  for _, f in ipairs(files) do
    if has_unstaged(f) then any_unstaged = true; break end
  end
  cursor_mem = nil
  local function done() ctx.render_cmdlog(); M.refresh() end
  if any_unstaged then git.stage_all(done) else git.unstage_all(done) end
end

local function discard()
  local node = current_entry()
  if not node then return end
  local targets = collect_files(node)
  if #targets == 0 then return end
  local label = node.is_dir and (node.path .. '/ 配下 ' .. #targets .. '件') or node.file.path
  ctx.confirm('破棄しますか？\n' .. label, function(ok)
    if not ok then return end
    cursor_mem = nil
    local pending = #targets
    local function done()
      pending = pending - 1
      if pending == 0 then ctx.render_cmdlog(); M.refresh() end
    end
    for _, f in ipairs(targets) do
      if is_untracked(f) then git.clean_file(f.path, done) else git.discard_file(f.path, done) end
    end
  end)
end

local function ignore_file()
  local node = current_entry()
  if not node or node.is_dir then return end
  git.ignore_file(node.file.path, function() ctx.render_cmdlog(); M.refresh() end)
end

local function copy_path()
  local node = current_entry()
  if not node then return end
  vim.fn.setreg('+', node.path)
  vim.notify('コピーしました: ' .. node.path, vim.log.levels.INFO)
end

local function open_file()
  local node = current_entry()
  if not node or node.is_dir then return end
  ctx.open_file_in_origin(ctx.get_root() .. '/' .. node.file.path)
end

local function commit(no_verify)
  ctx.multiline_input('コミットメッセージ', function(msg_lines)
    if not msg_lines then return end
    local msg = table.concat(msg_lines, '\n')
    if vim.trim(msg) == '' then
      vim.notify('コミットメッセージが空です', vim.log.levels.WARN)
      return
    end
    git.commit(msg_lines, no_verify, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('コミット失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      cursor_mem = nil
      M.refresh()
    end)
  end)
end

local function amend()
  ctx.confirm('ステージ済みの変更でHEADをamendしますか？', function(ok)
    if not ok then return end
    git.amend(function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('amendに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      cursor_mem = nil
      M.refresh()
    end)
  end)
end

--- files_controller.go fetch()相当（KeybindingFilesConfig.Fetch既定"f"）。
--- 成功時は無通知（push/pullと同じくパネル再描画自体が結果を表す）。
--- 本体のPostFetchRefreshと同じく、fetch完了時にBranchesパネルのPR状態も更新する
local function fetch()
  ctx.set_loading('Fetching')
  git.fetch(function(res)
    ctx.clear_loading()
    ctx.render_cmdlog()
    if res.code ~= 0 then
      vim.notify('fetch失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    M.refresh()
    require('config.git_panel.branches').refresh_prs()
  end)
end

--- files_controller.go handleStashSave相当。AllowEmptyInput=trueと同じく、
--- 空メッセージのままEnterしてもキャンセルにはせずスタッシュを実行する
local function stash_all()
  ctx.input('スタッシュメッセージ', '', function(msg)
    if msg == nil then return end
    git.stash_save(msg, function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('スタッシュに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      cursor_mem = nil
      M.refresh()
    end)
  end)
end

function M.keymaps()
  return {
    ['<Space>'] = stage_toggle,
    a = stage_all_toggle,
    d = discard,
    c = function() commit(false) end,
    w = function() commit(true) end,
    A = amend,
    e = open_file,
    o = open_file,
    i = ignore_file,
    y = copy_path,
    s = stash_all,
    f = fetch,
    ['<CR>'] = enter_or_toggle,
  }
end

function M.activate(c)
  ctx = c
  ctx.setup_cursor_clamp(
    function() return line_entries end,
    function() return total_rows end,
    show_diff_for
  )
  M.refresh()
end

return M
