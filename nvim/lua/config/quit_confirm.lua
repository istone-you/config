-- :q などで Neovim 自体を終了するとき、確認ポップアップを出す。
--
-- 仕組み: 組み込みの :q は上書きできないため、-bang 付きユーザーコマンド
-- (Q/Qa/Wq/Wqa/X/Xa) を定義し、コマンド略語(cnoreabbrev)で q→Q 等へ差し替える。
--   - `:q!` のような force はそのまま実行（確認なし）。
--   - 実際に Neovim を終了する場合のみ確認する（分割ウィンドウを閉じるだけなら確認しない）。

local M = {}

local win_util = require('config.util.win_util')
local hidden_cursor = require('config.hidden_cursor')

-- 現在のウィンドウを閉じたら Neovim 自体が終了するか。
-- = 現在の窓以外に実編集ウィンドウが1つも無い（かつタブが1つ）。
--   explorerやgitパネルだけが残る場合も終了扱い。
local function exits_nvim()
  if #vim.api.nvim_list_tabpages() > 1 then return false end
  local cur = vim.api.nvim_get_current_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur and win_util.is_editor(w) then return false end
  end
  return true
end

-- 未保存（変更あり・listed）バッファの表示名一覧
local function unsaved_names()
  local names = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buflisted then
      local n = vim.api.nvim_buf_get_name(b)
      names[#names + 1] = (n ~= '') and vim.fn.fnamemodify(n, ':~:.') or '[No Name]'
    end
  end
  return names
end

-- 中央ポップアップを開く。mappings = { {key, action|nil}, ... }（actionがnilはキャンセル=閉じるだけ）
local function popup(lines, mappings)
  -- 背景は透明にせず実色にする（Normalがbg=NONEなので専用グループを当てる）
  vim.api.nvim_set_hl(0, 'QuitConfirmBg', { bg = '#282828', fg = '#c0caf5' })
  vim.api.nvim_set_hl(0, 'QuitConfirmBorder', { bg = '#282828', fg = '#7aa2f7' })

  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  hidden_cursor.mark_buffer(buf)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = #lines,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - #lines) / 2) - 1,
    style = 'minimal',
    border = 'rounded',
    title = ' 確認 ',
    title_pos = 'center',
  })
  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = 'Normal:QuitConfirmBg,FloatBorder:QuitConfirmBorder'

  local done = false
  local function finish(action)
    if done then return end
    done = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if action then vim.schedule(action) end
  end
  for _, m in ipairs(mappings) do
    vim.keymap.set('n', m[1], function() finish(m[2]) end, { buffer = buf, nowait = true, silent = true })
  end
end

-- クリーンな状態での終了確認（y/n）
local function confirm(on_yes)
  popup({ '  Neovim を終了しますか？  ', '  y: 終了    n / Esc: キャンセル  ' }, {
    { 'y', on_yes }, { 'Y', on_yes }, { '<CR>', on_yes },
    { 'n' }, { 'N' }, { 'q' }, { '<Esc>' },
  })
end

-- 未保存がある状態での終了ダイアログ（保存して終了 / 保存せず終了 / キャンセル）
local function confirm_unsaved(names)
  local lines = { '  未保存の変更があります:  ' }
  for _, n in ipairs(names) do
    lines[#lines + 1] = '    ● ' .. n .. '  '
  end
  lines[#lines + 1] = '  s: 保存して終了   d: 保存せず終了   n / Esc: キャンセル  '
  popup(lines, {
    { 's', function()
      local ok = pcall(vim.cmd, 'wall')
      if ok then ok = pcall(vim.cmd, 'quitall') end
      if not ok then
        vim.notify('保存できないバッファがあります（名前なし等）。手動で保存してください', vim.log.levels.WARN)
      end
    end },
    { 'd', function() vim.cmd('quitall!') end },
    { 'n' }, { 'N' }, { 'q' }, { '<Esc>' },
  })
end

-- 実際に終了する場面の入口。未保存があればダイアログ、無ければそのまま終了。
-- quit_cmd: 未保存が無いときに実行する終了コマンド（'quit' / 'quitall' 等）
local function exit_now(quit_cmd)
  local names = unsaved_names()
  if #names > 0 then
    confirm_unsaved(names)
  else
    vim.cmd(quit_cmd)
  end
end

-- quit_cmd: 確認OK時に実行する実コマンド（'quit' / 'wq' など、force無し）
-- force_cmd: bang時にそのまま実行するコマンド（'quit!' など）
-- always: true なら「終了するか」に関係なく常に確認（:qa 系）
local function handle(bang, quit_cmd, force_cmd, always)
  if bang then
    vim.cmd(force_cmd)
    return
  end
  if always or exits_nvim() then
    local names = unsaved_names()
    if #names > 0 then
      confirm_unsaved(names)
    else
      confirm(function() vim.cmd(quit_cmd) end)
    end
  else
    vim.cmd(quit_cmd)
  end
end

-- テスト用/外部（auto_quit）用に公開
M._exits_nvim = exits_nvim
M._unsaved_names = unsaved_names
-- auto_quit から: 実編集ウィンドウが無くなり終了する場面。未保存があればダイアログを出す。
function M.exit_or_prompt() exit_now('quit') end
function M.q(bang) handle(bang, 'quit', 'quit!', false) end
function M.qa(bang) handle(bang, 'quitall', 'quitall!', true) end
function M.wq(bang) handle(bang, 'wq', 'wq!', false) end
function M.wqa(bang) handle(bang, 'wqall', 'wqall!', true) end
function M.x(bang) handle(bang, 'xit', 'xit!', false) end
function M.xa(bang) handle(bang, 'xall', 'xall!', true) end

local function defcmd(name, fn)
  vim.api.nvim_create_user_command(name, function(o) fn(o.bang) end, { bang = true })
end
defcmd('Q', M.q)
defcmd('Qa', M.qa)
defcmd('Wq', M.wq)
defcmd('Wqa', M.wqa)
defcmd('X', M.x)
defcmd('Xa', M.xa)

-- cmdline がちょうど lhs のときだけ target へ展開する（:q! や :q file 等は素通り）
local function cabbrev(lhs, target)
  vim.cmd(string.format(
    'cnoreabbrev <expr> %s (getcmdtype()==%s && getcmdline()==%s) ? %s : %s',
    lhs, vim.fn.string(':'), vim.fn.string(lhs), vim.fn.string(target), vim.fn.string(lhs)
  ))
end

cabbrev('q', 'Q')
cabbrev('quit', 'Q')
cabbrev('qa', 'Qa')
cabbrev('qall', 'Qa')
cabbrev('quita', 'Qa')
cabbrev('quitall', 'Qa')
cabbrev('wq', 'Wq')
cabbrev('wqa', 'Wqa')
cabbrev('wqall', 'Wqa')
cabbrev('x', 'X')
cabbrev('xa', 'Xa')
cabbrev('xall', 'Xa')

return M
