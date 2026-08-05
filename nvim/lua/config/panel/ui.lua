-- gitパネル共通のフローティングUIヘルパー（確認モーダル・単一行入力・複数行エディタ・メニュー）

local M = {}
local hidden_cursor = require('config.hidden_cursor')

local function refocus(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

--- message: 表示文字列（改行区切り可）
--- opts.refocus_win: 閉じた後にフォーカスを戻すウィンドウ
--- on_result(bool)
function M.confirm(message, opts, on_result)
  opts = opts or {}
  local lines = vim.split(message, '\n', { plain = true })
  local width = 10
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 4, math.floor(vim.o.columns * 0.8))
  local height = #lines
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  hidden_cursor.mark_buffer(buf)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height, col = col, row = row,
    style = 'minimal', border = 'rounded', title = ' 確認 (y/N) ', title_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:GitPanelConfirmBg,FloatBorder:GitPanelConfirmBorder'

  local done = false
  local function finish(result)
    if done then return end
    done = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    refocus(opts.refocus_win)
    on_result(result)
  end

  local function map(key, result)
    vim.keymap.set('n', key, function() finish(result) end, { buffer = buf, nowait = true, silent = true })
  end
  map('y', true); map('Y', true); map('<CR>', true)
  map('n', false); map('N', false); map('q', false); map('<Esc>', false)
end

--- title: モーダルタイトル
--- default: 初期値
--- opts.refocus_win
--- on_submit(string|nil)  nil=キャンセル
function M.input(title, default, opts, on_submit)
  opts = opts or {}
  default = default or ''
  local width = math.max(30, math.min(60, math.floor(vim.o.columns * 0.5)))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - 1) / 2) - 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = 1, col = col, row = row,
    style = 'minimal', border = 'rounded', title = ' ' .. title .. ' ', title_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:GitPanelInputBg,FloatBorder:GitPanelInputBorder'

  local done = false
  local function finish(value)
    if done then return end
    done = true
    -- インサートモードのまま閉じるとフォーカス移動後もインサートモードが引き継がれる
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    refocus(opts.refocus_win)
    on_submit(value)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    finish(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '')
  end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function() finish(nil) end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<C-u>', function()
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '' })
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_cursor(win, { 1, 0 }) end
  end, { buffer = buf, nowait = true, silent = true })

  vim.api.nvim_win_set_cursor(win, { 1, #default })
  vim.cmd('startinsert!')
end

--- lazygitのPrompt+FindSuggestionsFunc相当: 入力欄+リアルタイム候補リスト。
--- 候補は<Up>/<Down>で選択、<Tab>で入力欄に補完、<CR>で選択中の候補
--- （候補が無い場合は入力中のテキストそのもの）を確定する。
--- title: モーダルタイトル
--- opts.refocus_win, opts.default
--- get_candidates(input_text) -> {string,...}  候補一覧（呼び出し側でフィルタ済み全件を渡す）
--- on_submit(string|nil)  nil=キャンセル
function M.suggest_input(title, opts, get_candidates, on_submit)
  opts = opts or {}
  local default = opts.default or ''
  local width = math.max(40, math.min(70, math.floor(vim.o.columns * 0.6)))
  local list_height = math.min(10, math.floor(vim.o.lines * 0.3))
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - (1 + list_height)) / 2) - 1

  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[input_buf].buftype = 'nofile'
  vim.bo[input_buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { default })

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = 'editor', width = width, height = 1, col = col, row = row,
    style = 'minimal', border = 'rounded', title = ' ' .. title .. ' ', title_pos = 'center',
  })
  vim.wo[input_win].winhighlight = 'Normal:GitPanelInputBg,FloatBorder:GitPanelInputBorder'

  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = 'nofile'
  vim.bo[list_buf].bufhidden = 'wipe'

  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = 'editor', width = width, height = list_height, col = col, row = row + 3,
    style = 'minimal', border = 'rounded',
  })
  vim.wo[list_win].winhighlight =
    'Normal:GitPanelInputBg,FloatBorder:GitPanelInputBorder,CursorLine:GitPanelCurrent'
  vim.wo[list_win].cursorline = true

  local suggestions = {}
  local selected = 1

  local function current_text()
    return vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ''
  end

  local function render_list()
    suggestions = get_candidates(current_text()) or {}
    if selected > #suggestions then selected = #suggestions end
    if selected < 1 and #suggestions > 0 then selected = 1 end
    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, #suggestions > 0 and suggestions or { '(該当なし)' })
    vim.bo[list_buf].modifiable = false
    if #suggestions > 0 and vim.api.nvim_win_is_valid(list_win) then
      pcall(vim.api.nvim_win_set_cursor, list_win, { selected, 0 })
    end
  end
  render_list()

  local done = false
  local function finish(value)
    if done then return end
    done = true
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(input_win) then vim.api.nvim_win_close(input_win, true) end
    if vim.api.nvim_win_is_valid(list_win) then vim.api.nvim_win_close(list_win, true) end
    refocus(opts.refocus_win)
    on_submit(value)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', function()
    if #suggestions > 0 then finish(suggestions[selected]) else finish(current_text()) end
  end, { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function() finish(nil) end, { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<C-u>', function()
    vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { '' })
    vim.api.nvim_win_set_cursor(input_win, { 1, 0 })
    selected = 1
    render_list()
  end, { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Down>', function() selected = selected + 1; render_list() end,
    { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<C-n>', function() selected = selected + 1; render_list() end,
    { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Up>', function() selected = selected - 1; render_list() end,
    { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<C-p>', function() selected = selected - 1; render_list() end,
    { buffer = input_buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Tab>', function()
    if #suggestions == 0 then return end
    local v = suggestions[selected]
    vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { v })
    vim.api.nvim_win_set_cursor(input_win, { 1, #v })
    render_list()
  end, { buffer = input_buf, nowait = true, silent = true })

  vim.api.nvim_create_autocmd('TextChangedI', {
    buffer = input_buf,
    callback = function() selected = 1; render_list() end,
  })

  vim.api.nvim_win_set_cursor(input_win, { 1, #default })
  vim.cmd('startinsert!')
end

--- 複数行編集（コミットメッセージ用）
--- opts.refocus_win, opts.title
--- on_submit(lines|nil)  nil=キャンセル
function M.multiline_input(opts, on_submit)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = 'gitcommit'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '' })

  local width = math.floor(vim.o.columns * 0.5)
  local height = 8
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height, col = col, row = row,
    style = 'minimal', border = 'rounded',
    title = ' ' .. (opts.title or '入力') .. ' (Enter確定 / Esc中止) ',
    title_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:GitPanelInputBg,FloatBorder:GitPanelInputBorder'

  local done = false
  local function finish(save)
    if done then return end
    done = true
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- インサートモードのまま閉じるとフォーカス移動後もインサートモードが引き継がれる
    vim.cmd('stopinsert')
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    refocus(opts.refocus_win)
    on_submit(save and lines or nil)
  end

  -- lazygit(commit_message_controller.go)と同じくEnterは常に確定用キー
  -- （Insert中でも改行にならず即確定。モード遷移を意識させない）
  vim.keymap.set({ 'i', 'n' }, '<CR>', function() finish(true) end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function() finish(false) end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', 'q', function() finish(false) end, { buffer = buf, nowait = true, silent = true })

  vim.cmd('startinsert')
end

--- items = { { key, label, value }, ... }  1キーで即決定するメニュー
--- opts.refocus_win
--- on_choice(value|nil)  nil=キャンセル
function M.menu(title, items, opts, on_choice)
  opts = opts or {}
  local lines = {}
  for _, it in ipairs(items) do
    table.insert(lines, string.format('  %s   %s', it.key, it.label))
  end
  local width = 10
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 4
  -- タイトル(破棄対象のファイルパス等で長くなりうる)がウィンドウ幅を超えると、
  -- Neovimがボーダーのタイトル文字列を変な位置で切り詰めて表示してしまうため、
  -- タイトルも含めて幅を決める。画面幅の90%を上限にして極端に長い場合は
  -- (それでも切られるが)そこで妥協する
  width = math.max(width, math.min(vim.fn.strdisplaywidth(title) + 4, math.floor(vim.o.columns * 0.9)))
  local height = #lines
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2) - 1

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  hidden_cursor.mark_buffer(buf)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height, col = col, row = row,
    style = 'minimal', border = 'rounded', title = ' ' .. title .. ' ', title_pos = 'center',
  })
  vim.wo[win].winhighlight = 'Normal:GitPanelConfirmBg,FloatBorder:GitPanelConfirmBorder'

  local done = false
  local function finish(result)
    if done then return end
    done = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    refocus(opts.refocus_win)
    on_choice(result)
  end

  for _, it in ipairs(items) do
    vim.keymap.set('n', it.key, function() finish(it.value or it.key) end, { buffer = buf, nowait = true, silent = true })
  end
  vim.keymap.set('n', 'q', function() finish(nil) end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', function() finish(nil) end, { buffer = buf, nowait = true, silent = true })
end

function M.setup_hl()
  -- ダイアログはパネル(#282828)より少し明るい実背景にして浮かせる（透明にしない）
  vim.api.nvim_set_hl(0, 'GitPanelConfirmBg',     { bg = '#32302f', fg = '#f7768e', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelConfirmBorder', { bg = '#32302f', fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'GitPanelInputBg',       { bg = '#32302f', fg = '#c0caf5' })
  vim.api.nvim_set_hl(0, 'GitPanelInputBorder',   { bg = '#32302f', fg = '#7aa2f7' })
end

return M
