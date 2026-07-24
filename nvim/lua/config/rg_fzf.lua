-- rg + fzf による全ファイル文字列検索 / 置換（プラグイン不使用・自作）
-- Requirements: rg, fzf（bat があればプレビューに使う）

local M = {}

local win_util = require('config.util.win_util')

local function has_bat()
  return vim.fn.executable('bat') == 1
end

local function has_cmd(name)
  return vim.fn.executable(name) == 1
end

local function ensure_deps()
  if not has_cmd('rg') then
    vim.notify('rg が見つかりません', vim.log.levels.ERROR)
    return false
  end
  if not has_cmd('fzf') then
    vim.notify('fzf が見つかりません', vim.log.levels.ERROR)
    return false
  end
  return true
end

--- 選択範囲のテキストを返す（visual mode 用）
local function visual_text()
  local mode = vim.fn.mode()
  if not mode:match('[vV\22]') then
    return ''
  end
  local start_pos = vim.fn.getpos('v')
  local end_pos = vim.fn.getpos('.')
  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
  if #lines == 0 then return '' end
  -- 複数行は最初の行だけ（クエリとして扱いやすい）
  return lines[1] or ''
end

function M.open_match(line)
  line = line:gsub('\27%[[0-9;]*m', '')
  -- rg --column 形式: path:line:col:text
  local path, lnum, col = line:match('^([^:]+):(%d+):(%d+):')
  if not path then
    path, lnum = line:match('^([^:]+):(%d+):')
    col = 1
  end
  if not path or path == '' then return end

  lnum = tonumber(lnum) or 1
  col = tonumber(col) or 1

  win_util.focus_editor() -- explorer等にフォーカスがあっても必ず編集窓へ開く
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max(col - 1, 0) })
  vim.cmd('normal! zz')
end

function M.parse_path(line)
  line = line:gsub('\27%[[0-9;]*m', '') -- rg --color の ANSI を除去
  local path = line:match('^([^:]+):%d+:%d+:')
  if not path then
    path = line:match('^([^:]+):%d+:')
  end
  return path
end

--- 固定文字列の置換（パターンではなくリテラル）
function M.replace_literal(text, old, new)
  if old == '' then
    return text, 0
  end
  local out = {}
  local i = 1
  local count = 0
  while true do
    local s, e = text:find(old, i, true)
    if not s then
      table.insert(out, text:sub(i))
      break
    end
    table.insert(out, text:sub(i, s - 1))
    table.insert(out, new)
    i = e + 1
    count = count + 1
  end
  return table.concat(out), count
end

function M.resolve_path(cwd, path)
  if path:sub(1, 1) == '/' then
    return path
  end
  return cwd .. '/' .. path
end

--- 開いているバッファがあればバッファ上で置換、なければファイルを直接書き換え
function M.apply_replace_to_path(abs_path, search, replace)
  local bufnr = vim.fn.bufnr(abs_path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = table.concat(lines, '\n')
    local new_text, count = M.replace_literal(text, search, replace)
    if count == 0 then
      return 0
    end
    local new_lines = vim.split(new_text, '\n', { plain = true })
    if text:sub(-1) ~= '\n' and new_text:sub(-1) == '\n' then
      table.remove(new_lines)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd('silent write')
    end)
    return count
  end

  -- readfile()はNULバイトをNLへ置き換えて返すため(:h readfile()参照)、
  -- そこでNUL判定しても常にfalseになり検出できない。readblob()で生バイトを見る
  local blob_ok, blob = pcall(vim.fn.readblob, abs_path)
  if not blob_ok or type(blob) ~= 'string' or blob:find('\0', 1, true) then
    return 0
  end

  local ok, content = pcall(vim.fn.readfile, abs_path, 'b')
  if not ok or type(content) ~= 'table' then
    return 0
  end
  local text = table.concat(content, '\n')
  local new_text, count = M.replace_literal(text, search, replace)
  if count == 0 then
    return 0
  end
  local new_lines = vim.split(new_text, '\n', { plain = true })
  vim.fn.writefile(new_lines, abs_path, 'b')
  return count
end

local function preview_cmd()
  if has_bat() then
    return [[bat --style=numbers --color=always --highlight-line {2} -- {1} 2>/dev/null || sed -n '1,200p' -- {1}]]
  end
  return [[sed -n '1,200p' -- {1}]]
end

-- 空クエリでは検索しない
local RG_RELOAD = [[test x{q} != x && rg --column --line-number --no-heading --color=always --smart-case --fixed-strings --hidden --glob '!.git/*' -- {q} || true]]

local function open_float_term(title, shell, on_done)
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'single',
    title = title,
    title_pos = 'center',
  })

  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'

  vim.fn.termopen({ 'sh', '-c', shell }, {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
        on_done()
      end)
    end,
  })

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.cmd('startinsert')
    end
  end)
end

-- モード切替（内容検索 / ファイル名検索 / 置換）を1つのピッカーから行うための仕組み。
-- fzfは別プロセスなので、表示中のキーは fzf の --bind で拾い、「相手モードの印」と
-- 現在のクエリを一時ファイルに書いて abort し、Lua側(on_exit)がそれを見て開き直す。

-- targets: { {key='ctrl-f', to='files'}, ... } → fzfの --bind 文字列を返す
local function switch_binds_str(switch_file, qfile, targets)
  local parts = {}
  for _, t in ipairs(targets) do
    local action = string.format(
      'execute-silent(printf %%s %s > %s; printf %%s {q} > %s)+abort',
      t.to, switch_file, qfile
    )
    parts[#parts + 1] = '--bind ' .. vim.fn.shellescape(t.key .. ':' .. action)
  end
  return table.concat(parts, ' ')
end

-- 切替印があれば消費して true を返す（相手モードを開き直す）
local function consume_switch(switch_file, qfile)
  if vim.fn.filereadable(switch_file) == 0 then return false end
  local target = vim.trim((vim.fn.readfile(switch_file))[1] or '')
  local q = ''
  if vim.fn.filereadable(qfile) == 1 then q = (vim.fn.readfile(qfile))[1] or '' end
  vim.fn.delete(switch_file)
  vim.fn.delete(qfile)
  if target == 'content' then
    M.open(q)
  elseif target == 'files' then
    M.open_files(q)
  elseif target == 'replace' then
    M.replace(q)
  else
    return false
  end
  return true
end

local SWITCH_HEADER = 'Ctrl-g:内容  Ctrl-f:ファイル名  Ctrl-r:置換'

---@param initial_query? string
function M.open(initial_query)
  if not ensure_deps() then return end

  initial_query = initial_query or ''
  local out = vim.fn.tempname()
  local switch_file = vim.fn.tempname()
  local qfile = vim.fn.tempname()
  local cwd = vim.fn.getcwd()

  local fzf_cmd = table.concat({
    'fzf',
    '--ansi',
    '--disabled',
    '--delimiter', ':',
    '--prompt', "'rg> '",
    '--header', vim.fn.shellescape('Enter:開く  ' .. SWITCH_HEADER .. '  Esc:閉じる'),
    '--preview-window', "'right,50%,+{2}+3/3,~1'",
    '--preview', vim.fn.shellescape(preview_cmd()),
    '--query', vim.fn.shellescape(initial_query),
    '--bind', vim.fn.shellescape('start:reload:' .. RG_RELOAD),
    '--bind', vim.fn.shellescape('change:reload:' .. RG_RELOAD),
    '--bind', "'ctrl-u:clear-query'",
    switch_binds_str(switch_file, qfile, {
      { key = 'ctrl-f', to = 'files' },
      { key = 'ctrl-r', to = 'replace' },
    }),
  }, ' ')

  local shell = string.format(
    'cd %s && %s > %s',
    vim.fn.shellescape(cwd),
    fzf_cmd,
    vim.fn.shellescape(out)
  )

  open_float_term(' rg + fzf: ' .. cwd .. ' ', shell, function()
    local lines = {}
    if vim.fn.filereadable(out) == 1 then
      lines = vim.tbl_filter(function(l) return l ~= '' end, vim.fn.readfile(out))
      vim.fn.delete(out)
    end
    if #lines > 0 then
      M.open_match(lines[1])
      return
    end
    consume_switch(switch_file, qfile) -- 選択なし: モード切替なら開き直す
  end)
end

local function ensure_file_deps()
  if not has_cmd('fzf') then
    vim.notify('fzf が見つかりません', vim.log.levels.ERROR)
    return false
  end
  if not has_cmd('fd') then
    vim.notify('fd が見つかりません', vim.log.levels.ERROR)
    return false
  end
  return true
end

local function file_preview_cmd()
  if has_bat() then
    return [[bat --style=numbers --color=always -- {} 2>/dev/null || sed -n '1,200p' -- {}]]
  end
  return [[sed -n '1,200p' -- {}]]
end

local FD_CMD = "fd --type f --hidden --strip-cwd-prefix --color=never --exclude .git"

--- ファイル名を fd + fzf で絞り込んで開く（全文検索の M.open のファイル名版）
---@param initial_query? string
function M.open_files(initial_query)
  if not ensure_file_deps() then return end

  initial_query = initial_query or ''
  local out = vim.fn.tempname()
  local switch_file = vim.fn.tempname()
  local qfile = vim.fn.tempname()
  local cwd = vim.fn.getcwd()

  local fzf_cmd = table.concat({
    'fzf',
    '--prompt', "'files> '",
    '--header', vim.fn.shellescape('Enter:開く  ' .. SWITCH_HEADER .. '  Esc:閉じる'),
    '--preview-window', "'right,50%'",
    '--preview', vim.fn.shellescape(file_preview_cmd()),
    '--query', vim.fn.shellescape(initial_query),
    '--bind', "'ctrl-u:clear-query'",
    switch_binds_str(switch_file, qfile, {
      { key = 'ctrl-g', to = 'content' },
      { key = 'ctrl-r', to = 'replace' },
    }),
  }, ' ')

  local shell = string.format(
    'cd %s && %s | %s > %s',
    vim.fn.shellescape(cwd),
    FD_CMD,
    fzf_cmd,
    vim.fn.shellescape(out)
  )

  open_float_term(' files + fzf: ' .. cwd .. ' ', shell, function()
    local lines = {}
    if vim.fn.filereadable(out) == 1 then
      lines = vim.tbl_filter(function(l) return l ~= '' end, vim.fn.readfile(out))
      vim.fn.delete(out)
    end
    if #lines > 0 then
      win_util.focus_editor() -- explorer等にフォーカスがあっても必ず編集窓へ開く
      vim.cmd('edit ' .. vim.fn.fnameescape(M.resolve_path(cwd, lines[1])))
      return
    end
    consume_switch(switch_file, qfile) -- 選択なし: モード切替なら開き直す
  end)
end

--- 選択されたマッチ行のファイルに対して、検索文字列をすべて置換する
---@return integer file_count
---@return integer replace_count
function M.replace_selected(cwd, selected_lines, search, replace)
  local paths = {}
  for _, line in ipairs(selected_lines) do
    local path = M.parse_path(line)
    if path and path ~= '' then
      paths[M.resolve_path(cwd, path)] = true
    end
  end

  local file_count = 0
  local replace_count = 0
  for abs_path in pairs(paths) do
    local n = M.apply_replace_to_path(abs_path, search, replace)
    if n > 0 then
      file_count = file_count + 1
      replace_count = replace_count + n
    end
  end

  vim.cmd('checktime')
  return file_count, replace_count
end

--- 検索は今までどおり fzf ライブ表示。下に置換入力欄を追加し Tab で行き来する
---@param initial_query? string
---@param initial_replace? string
function M.replace(initial_query, initial_replace)
  if not ensure_deps() then return end

  initial_query = initial_query or ''
  initial_replace = initial_replace or ''
  local out = vim.fn.tempname()
  local switch_file = vim.fn.tempname()
  local qfile = vim.fn.tempname()
  local cwd = vim.fn.getcwd()
  local closing = false
  local job_id = nil

  local width = math.floor(vim.o.columns * 0.9)
  local total_h = math.floor(vim.o.lines * 0.85)
  local replace_h = 1
  local gap = 1
  local fzf_h = total_h - replace_h - gap - 2 -- ボーダー分の余裕
  if fzf_h < 10 then fzf_h = 10 end
  local col = math.floor((vim.o.columns - width) / 2)
  local fzf_row = math.floor((vim.o.lines - total_h) / 2)
  local replace_row = fzf_row + fzf_h + 2 + gap

  -- fzf（検索）— Space / と同じライブ検索 + multi-select
  -- Tab は置換欄切替に使うため、選択は Ctrl-Space
  -- --print-query で先頭行に検索文字列を出す
  local fzf_cmd = table.concat({
    'fzf',
    '--ansi',
    '--disabled',
    '--multi',
    '--print-query',
    '--delimiter', ':',
    '--prompt', "'rg> '",
    '--header', vim.fn.shellescape('Tab:置換欄  Ctrl-t:選択  Enter:置換実行  Ctrl-g:内容  Ctrl-f:ファイル名  Esc:閉じる'),
    '--preview-window', "'right,50%,+{2}+3/3,~1'",
    '--preview', vim.fn.shellescape(preview_cmd()),
    '--query', vim.fn.shellescape(initial_query),
    '--bind', vim.fn.shellescape('start:reload:' .. RG_RELOAD),
    '--bind', vim.fn.shellescape('change:reload:' .. RG_RELOAD),
    '--bind', "'ctrl-u:clear-query'",
    '--bind', "'ctrl-t:toggle+down'",
    switch_binds_str(switch_file, qfile, {
      { key = 'ctrl-g', to = 'content' },
      { key = 'ctrl-f', to = 'files' },
    }),
  }, ' ')

  local shell = string.format(
    'cd %s && %s > %s',
    vim.fn.shellescape(cwd),
    fzf_cmd,
    vim.fn.shellescape(out)
  )

  local fzf_buf = vim.api.nvim_create_buf(false, true)
  local fzf_win = vim.api.nvim_open_win(fzf_buf, true, {
    relative = 'editor',
    width = width,
    height = fzf_h,
    col = col,
    row = fzf_row,
    style = 'minimal',
    border = 'single',
    title = ' rg + fzf replace: ' .. cwd .. ' ',
    title_pos = 'center',
  })
  vim.wo[fzf_win].number = false
  vim.wo[fzf_win].relativenumber = false
  vim.wo[fzf_win].signcolumn = 'no'

  -- 置換入力欄（下）
  -- buftype=prompt だと IME の未確定文字が表示されないことがあるため、
  -- namu と同様に通常の nofile バッファで受け取る
  local replace_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[replace_buf].buftype = 'nofile'
  vim.bo[replace_buf].bufhidden = 'wipe'
  vim.bo[replace_buf].swapfile = false
  vim.bo[replace_buf].modifiable = true
  vim.api.nvim_buf_set_lines(replace_buf, 0, -1, false, { initial_replace })

  local replace_win = vim.api.nvim_open_win(replace_buf, false, {
    relative = 'editor',
    width = width,
    height = replace_h,
    col = col,
    row = replace_row,
    style = 'minimal',
    border = 'single',
    title = ' 置換: ',
    title_pos = 'left',
  })
  vim.wo[replace_win].number = false
  vim.wo[replace_win].relativenumber = false
  vim.wo[replace_win].signcolumn = 'no'
  vim.wo[replace_win].wrap = false

  local function cleanup_wins()
    for _, win in ipairs({ fzf_win, replace_win }) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    for _, buf in ipairs({ fzf_buf, replace_buf }) do
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end

  local function focus_fzf()
    if vim.api.nvim_win_is_valid(fzf_win) then
      vim.api.nvim_set_current_win(fzf_win)
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(fzf_win) then
          vim.cmd('startinsert')
        end
      end)
    end
  end

  local function focus_replace()
    if not vim.api.nvim_win_is_valid(replace_win) then
      return
    end
    vim.api.nvim_set_current_win(replace_win)
    -- ターミナル離脱と同じティックだと startinsert が効かないことがある
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(replace_win) then
        return
      end
      local line = vim.api.nvim_buf_get_lines(replace_buf, 0, 1, false)[1] or ''
      vim.api.nvim_win_set_cursor(replace_win, { 1, #line })
      vim.cmd('startinsert!')
    end)
  end

  local function cancel()
    if closing then return end
    closing = true
    if job_id then
      pcall(vim.fn.jobstop, job_id)
    end
    cleanup_wins()
    pcall(vim.fn.delete, out)
  end

  -- Tab: fzf ↔ 置換欄（ターミナルからは一旦ノーマルへ抜けてから切替）
  vim.keymap.set('t', '<Tab>', function()
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true),
      'n',
      false
    )
    vim.schedule(focus_replace)
  end, { buffer = fzf_buf, nowait = true })

  vim.keymap.set({ 'i', 'n' }, '<Tab>', function()
    focus_fzf()
  end, { buffer = replace_buf, nowait = true })

  vim.keymap.set({ 'i', 'n' }, '<S-Tab>', function()
    focus_fzf()
  end, { buffer = replace_buf, nowait = true })

  -- Esc in replace: 全体キャンセル
  vim.keymap.set({ 'i', 'n' }, '<Esc>', cancel, { buffer = replace_buf, nowait = true })

  -- Enter in replace: fzf 側で確定（置換実行）させる
  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    if job_id then
      pcall(vim.fn.chansend, job_id, '\r')
    else
      focus_fzf()
    end
  end, { buffer = replace_buf, nowait = true })

  job_id = vim.fn.termopen({ 'sh', '-c', shell }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if closing then
          return
        end
        closing = true

        local replace_text = ''
        if vim.api.nvim_buf_is_valid(replace_buf) then
          replace_text = vim.api.nvim_buf_get_lines(replace_buf, 0, 1, false)[1] or ''
        end

        cleanup_wins()

        -- モード切替（Ctrl-g/Ctrl-f）なら相手モードで開き直す
        if consume_switch(switch_file, qfile) then
          pcall(vim.fn.delete, out)
          return
        end

        -- Esc / abort
        if code ~= 0 and vim.fn.filereadable(out) == 0 then
          return
        end
        if vim.fn.filereadable(out) == 0 then
          return
        end

        local lines = vim.tbl_filter(function(l)
          return l ~= ''
        end, vim.fn.readfile(out))
        vim.fn.delete(out)

        -- --print-query: 1行目が検索文字列、以降が選択行
        if #lines == 0 then
          return
        end
        local search = lines[1]
        local selected = {}
        for i = 2, #lines do
          table.insert(selected, lines[i])
        end

        if search == '' or #selected == 0 then
          -- 置換せず UI を維持
          M.replace(search, replace_text)
          return
        end

        local file_count, replace_count = M.replace_selected(cwd, selected, search, replace_text)
        vim.notify(
          string.format('置換完了: %d ファイル / %d 箇所', file_count, replace_count),
          vim.log.levels.INFO
        )
        -- 閉じずに同じ状態で開き直す（結果がすぐ見える）
        M.replace(search, replace_text)
      end)
    end,
  })

  vim.schedule(function()
    focus_fzf()
  end)
end

-- 入口は検索(内容)のみ。開いた後 Ctrl-f=ファイル名 / Ctrl-r=置換 / Ctrl-g=内容 で切替。
vim.keymap.set('n', '<leader>/', function()
  M.open('')
end, { desc = 'rg+fzf: 検索（Ctrl-fファイル名/Ctrl-r置換に切替可）' })

vim.keymap.set('n', '<leader>*', function()
  M.open(vim.fn.expand('<cword>'))
end, { desc = 'rg+fzf: カーソル単語で検索（Ctrl-f/Ctrl-rで切替可）' })

vim.keymap.set('v', '<leader>/', function()
  local text = visual_text()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  vim.schedule(function()
    M.open(text)
  end)
end, { desc = 'rg+fzf: 選択文字列で検索（Ctrl-f/Ctrl-rで切替可）' })

return M
