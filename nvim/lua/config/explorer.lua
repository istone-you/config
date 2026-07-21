-- yazi風ファイラー（右パネル・単一カラム・プラグイン不使用・自作）

local M = {}

local win, buf
local origin_win
local cwd
local initialized = false
local rows = {}
local cursor_mem = {}
local selection = {}
local clipboard = nil
local show_hidden = true
local filter = ''

-- 全画面表示(:Explorer!)の時だけ有効になるプレビューパネル。通常のサイドパネル表示は
-- 幅が狭く単一カラムのままにする（トップのコメント通り）
local preview_win, preview_buf
local last_preview_path = nil
local BAT_AVAILABLE = vim.fn.executable('bat') == 1
local is_fullscreen = false

local git_status = {}      -- [リポジトリルート相対path] = GIT_CODES（git statusは常にルート相対で返るため）
local git_status_cwd = nil -- git_statusがどのcwdのものか
local git_repo_root = nil  -- git_statusに対応するリポジトリルート（絶対path）
local git_status_dirty = false
local render -- 前方宣言（gitステータス取得の非同期コールバックから参照するため）
local render_preview -- 前方宣言（render()の末尾から参照するため）

local hl_ns = vim.api.nvim_create_namespace('explorer_hl')
local augrp = vim.api.nvim_create_augroup('explorer', { clear = true })

local ENTRY_OFFSET = 2
local PANEL_WIDTH = 48

-- ヘッダー行（パス表示・空行）には行番号を出さない
_G.__explorer_statuscolumn = function()
  if vim.v.lnum <= ENTRY_OFFSET then
    return ''
  end
  -- カーソル行はヘッダー分を引いた「一覧内での番号」を表示（他行は相対距離のまま）
  local num = vim.v.relnum == 0 and (vim.v.lnum - ENTRY_OFFSET) or vim.v.relnum
  return string.format('%3d ', num)
end

-- ══════════════════════════════════════════════
-- アイコン（拡張子ごと・Nerd Fonts）
-- ══════════════════════════════════════════════

local function icon_char(code) return vim.fn.nr2char(code) end

local FOLDER_ICON       = 0xe5ff
local DEFAULT_FILE_ICON = 0xf15b
local ENV_ICON          = 0xf462
local LOCK_ICON         = 0xf023

local FILE_ICONS = {
  lua = 0xe620, ts = 0xe628, tsx = 0xe628, js = 0xe74e, jsx = 0xe74e,
  go = 0xe626, py = 0xe606, rs = 0xe7a8, rb = 0xe739, java = 0xe738,
  kt = 0xe634, swift = 0xe755, html = 0xe736, css = 0xe749, scss = 0xe603,
  json = 0xe60b, toml = 0xe6b2, md = 0xe73e, sh = 0xe615, bash = 0xe615,
  zsh = 0xe615, vim = 0xe62b, tf = 0xe69a, tfvars = 0xe69a, graphql = 0xe662,
  sql = 0xe706, php = 0xe73d, c = 0xe61e, cpp = 0xe61d, cs = 0xe648,
}

local SPECIAL_ICONS = {
  dockerfile = 0xe650,
  gitignore  = 0xe65d,
}

local function get_icon(name, isdir)
  if isdir then return icon_char(FOLDER_ICON) end
  local lower = name:lower()
  if lower == 'dockerfile' then return icon_char(SPECIAL_ICONS.dockerfile) end
  if lower:match('gitignore') then return icon_char(SPECIAL_ICONS.gitignore) end
  if lower:match('%.env') then return icon_char(ENV_ICON) end
  if lower:match('%.lock$') then return icon_char(LOCK_ICON) end
  local ext = name:match('%.([^%.]+)$')
  local code = ext and FILE_ICONS[ext]
  return icon_char(code or DEFAULT_FILE_ICON)
end

-- ══════════════════════════════════════════════
-- gitステータス（yazi/plugins/git.yazi と同じ判定・表示ロジック）
-- ══════════════════════════════════════════════

local GIT_CODES = {
  ignored = 6, untracked = 5, modified = 4, added = 3, deleted = 2, updated = 1, clean = 0,
}
local GIT_PATTERNS = {
  { '!$', GIT_CODES.ignored },
  { '?$', GIT_CODES.untracked },
  { '[MT]', GIT_CODES.modified },
  { '[AC]', GIT_CODES.added },
  { 'D', GIT_CODES.deleted },
  { 'U', GIT_CODES.updated },
  { '[AD][AD]', GIT_CODES.updated },
}
local GIT_SIGNS = {
  [GIT_CODES.ignored] = '  ', [GIT_CODES.untracked] = '? ', [GIT_CODES.modified] = 'M ',
  [GIT_CODES.added] = 'A ', [GIT_CODES.deleted] = 'D ', [GIT_CODES.updated] = 'U ',
}
local GIT_HL = {
  [GIT_CODES.ignored] = 'ExplorerGitIgnored', [GIT_CODES.untracked] = 'ExplorerGitUntracked',
  [GIT_CODES.modified] = 'ExplorerGitModified', [GIT_CODES.added] = 'ExplorerGitAdded',
  [GIT_CODES.deleted] = 'ExplorerGitDeleted', [GIT_CODES.updated] = 'ExplorerGitUpdated',
}

local function match_status_line(line)
  local signs = line:sub(1, 2)
  for _, p in ipairs(GIT_PATTERNS) do
    if signs:find(p[1]) then
      local path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
      return p[2], path
    end
  end
  return nil, nil
end

--- git statusは常にリポジトリルート相対パスで返るため、entry.pathをルート相対に
--- 変換してから比較する。ファイルは完全一致、ディレクトリは配下(prefix一致)の
--- 最悪ステータスを継承する
local function entry_git_code(entry)
  if not git_repo_root then return nil end
  local rel = entry.path:sub(#git_repo_root + 2)
  if not entry.isdir then return git_status[rel] end
  local prefix = rel .. '/'
  local best = nil
  for path, code in pairs(git_status) do
    if path == prefix or path:sub(1, #prefix) == prefix then
      if not best or code > best then best = code end
    end
  end
  return best
end

local function refresh_git_status(target_cwd)
  vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { cwd = target_cwd, text = true }, function(root_res)
    vim.schedule(function()
      if root_res.code ~= 0 then
        git_status, git_status_cwd, git_repo_root = {}, target_cwd, nil
        if cwd == target_cwd then render() end
        return
      end
      local repo_root = vim.trim(root_res.stdout or '')
      vim.system({
        'git', '--no-optional-locks', '-c', 'core.quotePath=', 'status',
        '--porcelain', '-unormal', '--no-renames', '--ignored=matching', '.',
      }, { cwd = target_cwd, text = true }, function(res)
        vim.schedule(function()
          local map = {}
          for line in (res.stdout or ''):gmatch('[^\r\n]+') do
            local code, path = match_status_line(line)
            if code and path then map[path] = code end
          end
          git_status, git_status_cwd, git_repo_root = map, target_cwd, repo_root
          if cwd == target_cwd then render() end
        end)
      end)
    end)
  end)
end

-- ══════════════════════════════════════════════
-- 一覧取得・表示
-- ══════════════════════════════════════════════

local function build_display_path(path)
  local home = vim.fn.expand('~')
  if path == home then return '~' end
  if path:sub(1, #home + 1) == home .. '/' then
    return '~' .. path:sub(#home + 1)
  end
  return path
end

local function list_dir(path)
  local names = vim.fn.readdir(path) or {}
  local list = {}
  for _, name in ipairs(names) do
    if show_hidden or name:sub(1, 1) ~= '.' then
      if filter == '' or name:lower():find(filter:lower(), 1, true) then
        local full = path .. '/' .. name
        table.insert(list, { name = name, path = full, isdir = vim.fn.isdirectory(full) == 1 })
      end
    end
  end
  table.sort(list, function(a, b)
    if a.isdir ~= b.isdir then return a.isdir end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

local function status_text()
  local parts = {}
  local sel_count = vim.tbl_count(selection)
  if sel_count > 0 then table.insert(parts, sel_count .. '選択') end
  if clipboard then
    table.insert(parts, (clipboard.mode == 'copy' and 'コピー' or 'カット') .. ':' .. #clipboard.paths)
  end
  if not show_hidden then table.insert(parts, '隠しファイル非表示') end
  if filter ~= '' then table.insert(parts, 'filter:' .. filter) end
  if #parts == 0 then return '' end
  return '  [' .. table.concat(parts, ' | ') .. ']'
end

function render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  rows = list_dir(cwd)

  if git_status_cwd ~= cwd or git_status_dirty then
    git_status_dirty = false
    refresh_git_status(cwd)
  end
  local git_ready = git_status_cwd == cwd

  local lines = {}
  local hl_queue = {}
  local function hl(lnum, group, cs, ce)
    table.insert(hl_queue, { lnum, group, cs or 0, ce or -1 })
  end

  table.insert(lines, ' ' .. icon_char(FOLDER_ICON) .. ' ' .. build_display_path(cwd) .. status_text())
  hl(0, 'ExplorerHeader')
  table.insert(lines, '')

  for _, entry in ipairs(rows) do
    local icon = get_icon(entry.name, entry.isdir)
    local line = '  ' .. icon .. '  ' .. entry.name
    local git_code = git_ready and entry_git_code(entry) or nil
    local sign = git_code and GIT_SIGNS[git_code]
    if sign and sign ~= '' then
      line = line .. '  ' .. sign
    end
    table.insert(lines, line)
    local lnum = #lines - 1
    if selection[entry.path] then
      hl(lnum, 'ExplorerSelected')
    elseif entry.isdir then
      hl(lnum, 'ExplorerDir')
    else
      hl(lnum, 'ExplorerFile')
    end
    if clipboard and clipboard.mode == 'cut' then
      for _, p in ipairs(clipboard.paths) do
        if p == entry.path then hl(lnum, 'ExplorerCut') end
      end
    end
    if sign and sign ~= '' and GIT_HL[git_code] then
      hl(lnum, GIT_HL[git_code], #line - #sign, #line)
    end
  end

  if #rows == 0 then
    table.insert(lines, '  (空)')
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue) do
    vim.api.nvim_buf_add_highlight(buf, hl_ns, h[2], h[1], h[3], h[4])
  end

  if win and vim.api.nvim_win_is_valid(win) and #rows > 0 then
    local target_row = ENTRY_OFFSET + 1
    local remembered = cursor_mem[cwd]
    if remembered then
      for i, entry in ipairs(rows) do
        if entry.name == remembered then
          target_row = ENTRY_OFFSET + i
          break
        end
      end
    end
    target_row = math.min(target_row, ENTRY_OFFSET + #rows)
    pcall(vim.api.nvim_win_set_cursor, win, { target_row, 0 })
  end

  render_preview()
end

local function entry_at_cursor()
  if not win or not vim.api.nvim_win_is_valid(win) then return nil end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  return rows[row - ENTRY_OFFSET]
end

-- ══════════════════════════════════════════════
-- プレビュー（全画面表示のみ）
-- ══════════════════════════════════════════════

--- bat(ANSI付きカラー出力)はterminalバッファ(nvim_open_term)でしか描画できず、
--- 通常のディレクトリ一覧/cat結果は普通のバッファで済むため、切り替わる時だけ
--- バッファを作り直す。新規作成→ウィンドウへ差し込み→旧バッファ削除の順にする
--- (逆順だと表示中のterminalバッファ削除でウィンドウ自体が閉じることがある)
local function recreate_preview_buf(as_terminal)
  local old = preview_buf
  preview_buf = vim.api.nvim_create_buf(false, true)
  if not as_terminal then
    vim.bo[preview_buf].buftype = 'nofile'
    vim.bo[preview_buf].buflisted = false
  end
  -- nvim_win_set_bufは対象ウィンドウがフォーカスされていなくてもBufEnterを発火し、
  -- その一瞬だけ「カレントバッファ」がこのバッファとして扱われる。hidden_cursorの
  -- 判定(vim.b.hide_cursor)がその瞬間に走るため、差し込む前に必ずマークしておく
  -- （後からmark_bufferすると一瞬フラグが立っていない状態でBufEnterが飛び、
  -- 実際にフォーカスしている一覧側のカーソルが復活して見えるちらつきが起きていた）
  require('config.hidden_cursor').mark_buffer(preview_buf)
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_set_buf(preview_win, preview_buf)
  end
  if old and vim.api.nvim_buf_is_valid(old) then
    pcall(vim.api.nvim_buf_delete, old, { force = true })
  end
end

local function set_preview_title(text)
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_set_config(preview_win, { title = ' ' .. text .. ' ', title_pos = 'center' })
  end
end

local function set_preview_lines(lines, filetype)
  if not (preview_buf and vim.api.nvim_buf_is_valid(preview_buf)) then return end
  if vim.bo[preview_buf].buftype == 'terminal' then recreate_preview_buf(false) end
  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].filetype = filetype or ''
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  vim.bo[preview_buf].modifiable = false
end

local function set_preview_ansi(ansi_text)
  if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then return end
  recreate_preview_buf(true)
  local chan = vim.api.nvim_open_term(preview_buf, {})
  vim.api.nvim_chan_send(chan, ansi_text)
end

local function preview_dir_lines(path)
  local names = vim.fn.readdir(path) or {}
  local list = {}
  for _, name in ipairs(names) do
    if show_hidden or name:sub(1, 1) ~= '.' then table.insert(list, name) end
  end
  table.sort(list, function(a, b) return a:lower() < b:lower() end)
  if #list == 0 then return { '  (空)' } end
  local lines = {}
  for _, name in ipairs(list) do
    local isdir = vim.fn.isdirectory(path .. '/' .. name) == 1
    table.insert(lines, '  ' .. get_icon(name, isdir) .. '  ' .. name)
  end
  return lines
end

--- batが無い/失敗した時のフォールバック。実際にcatを起動する代わりに直接読むが、
--- 得られる見た目(生テキストをそのまま表示)はcatと同じ
local function preview_file_plain(path)
  local ok, content = pcall(vim.fn.readfile, path, '', 2000)
  if not ok then
    set_preview_lines({ '  (読み込み不可)' })
    return
  end
  set_preview_lines(content, '')
end

--- 1000行/画面幅分だけ取得すれば十分なので、巨大ファイルでも固まらないよう
--- --line-rangeで上限を切る
local function preview_file(path)
  if not BAT_AVAILABLE then
    preview_file_plain(path)
    return
  end
  local width = (preview_win and vim.api.nvim_win_is_valid(preview_win))
    and vim.api.nvim_win_get_width(preview_win) or 80
  vim.system(
    {
      'bat', '--color=always', '--paging=never', '--style=numbers',
      '--terminal-width=' .. tostring(width), '--line-range=:1000', '--', path,
    },
    { text = true },
    function(res)
      vim.schedule(function()
        if res.code == 0 and res.stdout and res.stdout ~= '' then
          set_preview_ansi(res.stdout)
        else
          preview_file_plain(path)
        end
      end)
    end
  )
end

--- 一覧のCursorMoved、render()末尾、ディレクトリ移動後などから呼ばれる。
--- 同じ対象への連続呼び出しは無視して再描画/再実行を省く
function render_preview()
  if not (preview_win and vim.api.nvim_win_is_valid(preview_win)) then return end
  local entry = entry_at_cursor()
  local path = entry and entry.path or nil
  if path == last_preview_path then return end
  last_preview_path = path
  if not entry then
    set_preview_title('プレビュー')
    set_preview_lines({})
    return
  end
  set_preview_title(entry.name)
  if entry.isdir then
    set_preview_lines(preview_dir_lines(entry.path), '')
  else
    preview_file(entry.path)
  end
end

-- ══════════════════════════════════════════════
-- ナビゲーション
-- ══════════════════════════════════════════════

local function enter_dir()
  local entry = entry_at_cursor()
  if not entry or not entry.isdir then return end
  cwd = entry.path
  selection = {}
  render()
end

local function open_selected()
  local entry = entry_at_cursor()
  if not entry then return end
  if entry.isdir then
    cwd = entry.path
    selection = {}
    render()
  else
    if origin_win and vim.api.nvim_win_is_valid(origin_win) then
      vim.api.nvim_set_current_win(origin_win)
    end
    vim.cmd('edit ' .. vim.fn.fnameescape(entry.path))
  end
end

local function go_parent()
  local parent = vim.fn.fnamemodify(cwd, ':h')
  if parent == cwd then return end
  cursor_mem[parent] = vim.fn.fnamemodify(cwd, ':t')
  cwd = parent
  selection = {}
  render()
end

local function toggle_hidden()
  show_hidden = not show_hidden
  render()
end

local function refresh()
  render()
end

local function refocus_panel()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

local function input_modal(title, default, on_submit)
  default = default or ''
  local width = math.max(30, math.min(60, math.floor(vim.o.columns * 0.5)))
  local height = 1
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1

  local ibuf = vim.api.nvim_create_buf(false, true)
  vim.bo[ibuf].buftype = 'nofile'
  vim.bo[ibuf].bufhidden = 'wipe'
  vim.bo[ibuf].swapfile = false
  vim.bo[ibuf].modifiable = true
  vim.api.nvim_buf_set_lines(ibuf, 0, -1, false, { default })

  local iwin = vim.api.nvim_open_win(ibuf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })
  vim.wo[iwin].winhighlight = 'Normal:ExplorerInputBg,FloatBorder:ExplorerInputBorder'

  local done = false
  local function finish(value)
    if done then return end
    done = true
    -- インサートモードのまま閉じるとフォーカス移動後もインサートモードが引き継がれるため先に抜ける
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(iwin) then vim.api.nvim_win_close(iwin, true) end
    refocus_panel()
    on_submit(value)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    local line = vim.api.nvim_buf_get_lines(ibuf, 0, 1, false)[1] or ''
    finish(line)
  end, { buffer = ibuf, nowait = true, silent = true })

  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    finish(nil)
  end, { buffer = ibuf, nowait = true, silent = true })

  vim.keymap.set({ 'i', 'n' }, '<C-u>', function()
    vim.api.nvim_buf_set_lines(ibuf, 0, 1, false, { '' })
    if vim.api.nvim_win_is_valid(iwin) then
      vim.api.nvim_win_set_cursor(iwin, { 1, 0 })
    end
  end, { buffer = ibuf, nowait = true, silent = true })

  vim.api.nvim_win_set_cursor(iwin, { 1, #default })
  vim.cmd('startinsert!')
end

-- ══════════════════════════════════════════════
-- 選択
-- ══════════════════════════════════════════════

local function toggle_select_at_cursor(step)
  step = step or 1
  local entry = entry_at_cursor()
  if not entry then return end
  if selection[entry.path] then
    selection[entry.path] = nil
  else
    selection[entry.path] = true
  end
  cursor_mem[cwd] = entry.name
  render()
  if win and vim.api.nvim_win_is_valid(win) then
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local target = row + step
    if target >= ENTRY_OFFSET + 1 and target <= ENTRY_OFFSET + #rows then
      pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
    end
  end
end

local function select_all()
  for _, entry in ipairs(rows) do selection[entry.path] = true end
  render()
end

local function invert_selection()
  for _, entry in ipairs(rows) do
    if selection[entry.path] then
      selection[entry.path] = nil
    else
      selection[entry.path] = true
    end
  end
  render()
end

local function clear_selection_or_close()
  if vim.tbl_count(selection) > 0 then
    selection = {}
    render()
  elseif filter ~= '' then
    filter = ''
    render()
  else
    M.close()
  end
end

local function targets()
  if vim.tbl_count(selection) > 0 then
    local list = {}
    for _, entry in ipairs(rows) do
      if selection[entry.path] then table.insert(list, entry) end
    end
    return list
  end
  local entry = entry_at_cursor()
  return entry and { entry } or {}
end

-- ══════════════════════════════════════════════
-- ファイル操作
-- ══════════════════════════════════════════════

local function create()
  input_modal('作成 (末尾/でディレクトリ)', '', function(input)
    if not input or input == '' then return end
    local is_dir = input:sub(-1) == '/'
    local name = is_dir and input:sub(1, -2) or input
    if name == '' then return end
    local full = cwd .. '/' .. name
    if is_dir then
      vim.fn.mkdir(full, 'p')
    else
      vim.fn.mkdir(vim.fn.fnamemodify(full, ':h'), 'p')
      if vim.fn.filereadable(full) == 0 then
        vim.fn.writefile({}, full)
      end
    end
    cursor_mem[cwd] = name:match('^([^/]+)') or name
    git_status_dirty = true
    render()
    refocus_panel()
  end)
end

local function rename()
  local list = targets()
  if #list == 0 then return end
  if #list > 1 then
    vim.notify('複数選択時はリネームできません', vim.log.levels.WARN)
    return
  end
  local entry = list[1]
  input_modal('リネーム', entry.name, function(input)
    if not input or input == '' or input == entry.name then return end
    local new_path = cwd .. '/' .. input
    if vim.fn.filereadable(new_path) == 1 or vim.fn.isdirectory(new_path) == 1 then
      vim.notify('既に存在します: ' .. input, vim.log.levels.ERROR)
      return
    end
    local ok = vim.uv.fs_rename(entry.path, new_path)
    if not ok then
      vim.notify('リネームに失敗しました', vim.log.levels.ERROR)
      return
    end
    selection[entry.path] = nil
    local bufnr = vim.fn.bufnr(entry.path)
    if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_set_name(bufnr, new_path)
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent! write!') end)
    end
    cursor_mem[cwd] = input
    git_status_dirty = true
    render()
    refocus_panel()
  end)
end

local function confirm(message, on_result)
  local lines = vim.split(message, '\n', { plain = true })
  local width = 10
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 4, math.floor(vim.o.columns * 0.8))
  local height = #lines
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1

  local cbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[cbuf].buftype = 'nofile'
  vim.bo[cbuf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, lines)
  vim.bo[cbuf].modifiable = false

  local cwin = vim.api.nvim_open_win(cbuf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' 確認 (y/N) ',
    title_pos = 'center',
  })
  vim.wo[cwin].winhighlight = 'Normal:ExplorerConfirmBg,FloatBorder:ExplorerConfirmBorder'

  local done = false
  local function finish(result)
    if done then return end
    done = true
    if vim.api.nvim_win_is_valid(cwin) then vim.api.nvim_win_close(cwin, true) end
    refocus_panel()
    on_result(result)
  end

  local function map(key, result)
    vim.keymap.set('n', key, function() finish(result) end, { buffer = cbuf, nowait = true, silent = true })
  end
  map('y', true)
  map('Y', true)
  map('<CR>', true)
  map('n', false)
  map('N', false)
  map('q', false)
  map('<Esc>', false)
end

local function delete()
  local list = targets()
  if #list == 0 then return end
  local names = {}
  for i, e in ipairs(list) do
    if i > 5 then break end
    table.insert(names, e.name)
  end
  local label = table.concat(names, ', ')
  if #list > 5 then label = label .. ' 他' .. (#list - 5) .. '件' end

  confirm(string.format('%d件を完全削除しますか？\n%s', #list, label), function(ok)
    if not ok then return end
    for _, e in ipairs(list) do
      vim.fn.delete(e.path, 'rf')
      selection[e.path] = nil
      local bufnr = vim.fn.bufnr(e.path)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
    git_status_dirty = true
    render()
    refocus_panel()
  end)
end

local function copy_selection()
  local list = targets()
  if #list == 0 then return end
  local paths = {}
  for _, e in ipairs(list) do table.insert(paths, e.path) end
  clipboard = { mode = 'copy', paths = paths }
  render()
end

local function cut_selection()
  local list = targets()
  if #list == 0 then return end
  local paths = {}
  for _, e in ipairs(list) do table.insert(paths, e.path) end
  clipboard = { mode = 'cut', paths = paths }
  render()
end

local function unique_dest(dest_dir, name)
  local base, ext = name:match('^(.*)(%.[^%.]+)$')
  if not base then
    base, ext = name, ''
  end
  local candidate = dest_dir .. '/' .. name
  local n = 1
  while vim.fn.filereadable(candidate) == 1 or vim.fn.isdirectory(candidate) == 1 do
    candidate = string.format('%s/%s_copy%d%s', dest_dir, base, n, ext)
    n = n + 1
  end
  return candidate
end

local function paste(overwrite)
  if not clipboard or #clipboard.paths == 0 then
    vim.notify('クリップボードが空です', vim.log.levels.WARN)
    return
  end
  for _, src in ipairs(clipboard.paths) do
    local name = vim.fn.fnamemodify(src, ':t')
    local dest = cwd .. '/' .. name
    if not overwrite and (vim.fn.filereadable(dest) == 1 or vim.fn.isdirectory(dest) == 1) then
      dest = unique_dest(cwd, name)
    end
    if clipboard.mode == 'copy' then
      vim.system({ 'cp', '-r', src, dest }):wait()
    else
      local ok = vim.uv.fs_rename(src, dest)
      if not ok then
        vim.system({ 'cp', '-r', src, dest }):wait()
        vim.fn.delete(src, 'rf')
      end
    end
  end
  if clipboard.mode == 'cut' then clipboard = nil end
  selection = {}
  git_status_dirty = true
  render()
end

local function set_filter()
  input_modal('フィルタ (Esc でクリア)', filter, function(input)
    -- Esc(input=nil)もクリアとして扱う（yaziと同じ挙動）
    filter = input or ''
    render()
    refocus_panel()
  end)
end

-- ══════════════════════════════════════════════
-- fd + fzf 再帰検索
-- ══════════════════════════════════════════════

local function fd_search()
  if vim.fn.executable('fd') == 0 or vim.fn.executable('fzf') == 0 then
    vim.notify('fd または fzf が見つかりません', vim.log.levels.ERROR)
    return
  end

  local out = vim.fn.tempname()
  local shell = string.format(
    "fd --hidden --exclude .git . %s | fzf --prompt 'fd> ' --header 'Enter: 移動/開く  Esc: 閉じる' > %s",
    vim.fn.shellescape(cwd),
    vim.fn.shellescape(out)
  )

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local term_buf = vim.api.nvim_create_buf(false, true)
  local term_win = vim.api.nvim_open_win(term_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'single',
    title = ' fd + fzf ',
    title_pos = 'center',
  })
  vim.wo[term_win].number = false
  vim.wo[term_win].relativenumber = false
  vim.wo[term_win].signcolumn = 'no'

  vim.fn.termopen({ 'sh', '-c', shell }, {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(term_win) then
          vim.api.nvim_win_close(term_win, true)
        end
        if vim.api.nvim_buf_is_valid(term_buf) then
          vim.api.nvim_buf_delete(term_buf, { force = true })
        end
        refocus_panel()

        if vim.fn.filereadable(out) == 0 then return end
        local lines = vim.tbl_filter(function(l) return l ~= '' end, vim.fn.readfile(out))
        vim.fn.delete(out)
        if #lines == 0 then return end

        local selected = lines[1]
        if vim.fn.isdirectory(selected) == 1 then
          cwd = selected
          selection = {}
        else
          cwd = vim.fn.fnamemodify(selected, ':h')
          cursor_mem[cwd] = vim.fn.fnamemodify(selected, ':t')
        end
        render()
      end)
    end,
  })

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(term_win) then
      vim.cmd('startinsert')
    end
  end)
end

-- ══════════════════════════════════════════════
-- 開閉
-- ══════════════════════════════════════════════

--- 全画面表示は「これがこのnvimプロセスの用件そのもの」という前提(herdrの
--- popupから nvim +Explorer! で直接立ち上げる運用等)なので、閉じる操作(q/Esc/:q
--- どれでも最終的にここを通る)がそのまま裏側の元バッファへ戻るのではなく、
--- nvim自体を終了させる。通常のサイドパネル表示ではこれまで通り単に閉じるだけ
local function close()
  local was_fullscreen = is_fullscreen
  vim.api.nvim_clear_autocmds({ group = augrp })
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if preview_win and vim.api.nvim_win_is_valid(preview_win) then
    vim.api.nvim_win_close(preview_win, true)
  end
  if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
    vim.api.nvim_buf_delete(preview_buf, { force = true })
  end
  win, buf, preview_win, preview_buf = nil, nil, nil, nil
  last_preview_path = nil
  is_fullscreen = false
  if was_fullscreen then
    vim.cmd('qall')
  end
end

local function open(fullscreen)
  is_fullscreen = fullscreen or false
  origin_win = vim.api.nvim_get_current_win()
  if not initialized then
    cwd = vim.fn.getcwd()
    initialized = true
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].buflisted  = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype   = 'explorer'

  if fullscreen then
    local total_w = vim.o.columns
    local total_h = vim.o.lines - 2
    -- 一覧は幅32%程度、残りをプレビューに割く。ボーダー分(左右1桁ずつ)を差し引いて
    -- 隙間無く並べる
    local list_w = math.max(24, math.floor(total_w * 0.32) - 2)
    local list_screen_w = list_w + 2
    local preview_w = total_w - list_screen_w - 2

    win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width    = list_w,
      height   = total_h,
      col      = 0,
      row      = 0,
      style    = 'minimal',
      border   = 'single',
    })

    preview_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[preview_buf].buftype   = 'nofile'
    vim.bo[preview_buf].buflisted = false
    -- ウィンドウへ差し込む前に必ずマークする（recreate_preview_bufと同じ理由:
    -- nvim_open_win/nvim_win_set_bufはフォーカスしていなくてもBufEnterを発火するため）
    require('config.hidden_cursor').mark_buffer(preview_buf)
    preview_win = vim.api.nvim_open_win(preview_buf, false, {
      relative = 'editor',
      width    = preview_w,
      height   = total_h,
      col      = list_screen_w,
      row      = 0,
      style    = 'minimal',
      border   = 'single',
      title    = ' プレビュー ',
      title_pos = 'center',
    })
    vim.wo[preview_win].wrap         = false
    vim.wo[preview_win].signcolumn   = 'no'
    vim.wo[preview_win].winhighlight = 'Normal:ExplorerBg'
  else
    vim.cmd('botright ' .. PANEL_WIDTH .. 'vsplit')
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].winfixwidth = true
  end

  require('config.hidden_cursor').mark_buffer(buf)

  vim.wo[win].wrap           = false
  vim.wo[win].number         = true
  vim.wo[win].relativenumber = true
  vim.wo[win].statuscolumn   = '%!v:lua.__explorer_statuscolumn()'
  vim.wo[win].signcolumn     = 'no'
  vim.wo[win].cursorline     = true
  vim.wo[win].winhighlight   = 'Normal:ExplorerBg,CursorLine:ExplorerCursorLine'

  render()

  -- ヘッダー行（パス表示・空行）にはカーソルを乗せない
  vim.api.nvim_create_autocmd('CursorMoved', {
    group    = augrp,
    buffer   = buf,
    callback = function()
      if not (win and vim.api.nvim_win_is_valid(win)) then return end
      local pos = vim.api.nvim_win_get_cursor(win)
      local min_row = ENTRY_OFFSET + 1
      if pos[1] < min_row then
        pcall(vim.api.nvim_win_set_cursor, win, { min_row, pos[2] })
      end
      render_preview()
    end,
  })

  local function map(key, fn)
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('l',       enter_dir)
  map('<Right>', enter_dir)
  map('<CR>',    open_selected)
  map('h',       go_parent)
  map('<Left>',  go_parent)
  map('.',       toggle_hidden)
  map('R',       refresh)
  map('<Tab>',   function() toggle_select_at_cursor(1) end)
  map('<S-Tab>', function() toggle_select_at_cursor(-1) end)
  map('<C-a>',   select_all)
  map('<C-r>',   invert_selection)
  map('<Esc>',   clear_selection_or_close)
  map('q',       close)
  map('a',       create)
  map('r',       rename)
  map('d',       delete)
  map('y',       copy_selection)
  map('x',       cut_selection)
  map('p',       function() paste(false) end)
  map('P',       function() paste(true) end)
  map('/',       set_filter)
  map('s',       fd_search)

  local watched = tostring(win)
  if preview_win then watched = watched .. ',' .. tostring(preview_win) end
  -- :q等でウィンドウが閉じられた時もclose()と同じ後始末(+全画面ならqall)を通す
  vim.api.nvim_create_autocmd('WinClosed', {
    group    = augrp,
    pattern  = watched,
    once     = true,
    callback = close,
  })
end

function M.open(fullscreen)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    open(fullscreen)
  end
end

function M.close()
  close()
end

function M.toggle(fullscreen)
  if win and vim.api.nvim_win_is_valid(win) then
    close()
  else
    open(fullscreen)
  end
end

-- ══════════════════════════════════════════════
-- ハイライト
-- ══════════════════════════════════════════════

local function setup_hl()
  vim.api.nvim_set_hl(0, 'ExplorerBg',         { bg = '#1a1b26' })
  vim.api.nvim_set_hl(0, 'ExplorerCursorLine', { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'ExplorerHeader',     { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'ExplorerDir',        { fg = '#7aa2f7' })
  vim.api.nvim_set_hl(0, 'ExplorerFile',       { fg = '#c0caf5' })
  vim.api.nvim_set_hl(0, 'ExplorerSelected',   { fg = '#e0af68', bold = true })
  vim.api.nvim_set_hl(0, 'ExplorerCut',        { fg = '#565f89', italic = true })
  vim.api.nvim_set_hl(0, 'ExplorerConfirmBg',     { bg = '#1a1b26', fg = '#f7768e', bold = true })
  vim.api.nvim_set_hl(0, 'ExplorerConfirmBorder', { bg = '#1a1b26', fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'ExplorerInputBg',       { bg = '#1a1b26', fg = '#c0caf5' })
  vim.api.nvim_set_hl(0, 'ExplorerInputBorder',   { bg = '#1a1b26', fg = '#7aa2f7' })
  vim.api.nvim_set_hl(0, 'ExplorerGitIgnored',    { fg = '#565f89' })
  vim.api.nvim_set_hl(0, 'ExplorerGitUntracked',  { fg = '#bb9af7' })
  vim.api.nvim_set_hl(0, 'ExplorerGitModified',   { fg = '#e0af68' })
  vim.api.nvim_set_hl(0, 'ExplorerGitAdded',      { fg = '#9ece6a' })
  vim.api.nvim_set_hl(0, 'ExplorerGitDeleted',    { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'ExplorerGitUpdated',    { fg = '#e0af68' })
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

vim.keymap.set('n', '<leader>e', function() M.toggle() end, { desc = 'ファイラーを開閉' })

vim.api.nvim_create_user_command('Explorer', function(cmd_opts)
  M.toggle(cmd_opts.bang)
end, { bang = true, desc = 'ファイラーを開閉（!で全画面表示）' })

--- 起動時に -c/--cmd/+cmd で明示的なコマンドが指定されていた場合は、
--- そちらを優先してexplorerの自動起動をしない（例: nvim +Git でGitパネルを
--- 開いたのに、VimEnterの自動起動が後からフォーカスを奪ってしまうのを防ぐ）
local function has_explicit_startup_command()
  for _, arg in ipairs(vim.v.argv) do
    if arg == '-c' or arg == '--cmd' or arg:sub(1, 1) == '+' then
      return true
    end
  end
  return false
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    if has_explicit_startup_command() then return end
    M.open()
  end,
})

return M
