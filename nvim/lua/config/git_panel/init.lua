-- lazygit風のgit管理パネル（中央90%ポップアップ、複数パネル切替、プラグイン不使用・自作）
-- キー/挙動は pkg/config/user_config.go のデフォルトキーバインドに合わせて検証済み

local git = require('config.git_panel.git')
local ui = require('config.git_panel.ui')

local M = {}

local PANELS = {
  { key = '1', name = 'files',    title = 'Files',    mod = 'config.git_panel.files' },
  { key = '2', name = 'commits',  title = 'Commits',  mod = 'config.git_panel.commits' },
  { key = '3', name = 'branches', title = 'Branches', mod = 'config.git_panel.branches' },
  { key = '4', name = 'stash',    title = 'Stash',    mod = 'config.git_panel.stash' },
  { key = '5', name = 'worktree', title = 'Worktree', mod = 'config.git_panel.worktree' },
}

local win = {}
local origin_win
local augrp = vim.api.nvim_create_augroup('git_panel', { clear = true })
local hl_ns = vim.api.nvim_create_namespace('git_panel_hl')
local current_panel_idx = 1
local refresh_timer = nil

-- lazygit本体(pkg/gui/background.go)は10秒ごとのFiles再取得+2秒ごとの外部変更検知(reflog等)
-- を別々のタイマーで走らせているが、こちらは常に1パネルだけを表示する構成なので
-- 「表示中のパネルを2秒おきに再取得」だけに単純化して同じ体感（外部でのgit操作が
-- 自動的に反映される）を再現する
local AUTO_REFRESH_INTERVAL_MS = 2000

--- 「押したから更新する」(R)と「勝手に定期更新する」(auto refresh)の両方から使う共通処理。
--- 各パネルモジュールが持つremember_cursor()（無ければ何もしない）で「今カーソルが
--- 乗っている項目」を記録してからrefresh()する。これをしないと、ユーザーが単に
--- j/kで見ているだけの項目情報が古いまま(あるいは無いまま)再描画されてカーソルが
--- 先頭などに戻ってしまう
local function refresh_current_panel()
  local spec = PANELS[current_panel_idx]
  if not spec then return end
  local panel = require(spec.mod)
  if panel.remember_cursor then panel.remember_cursor() end
  panel.refresh()
end

local function start_auto_refresh()
  if refresh_timer then return end
  refresh_timer = vim.uv.new_timer()
  refresh_timer:start(AUTO_REFRESH_INTERVAL_MS, AUTO_REFRESH_INTERVAL_MS, vim.schedule_wrap(function()
    -- hunkステージング中やモーダル表示中(フォーカスがleft_win以外)は再描画で状態が
    -- 消えてしまうため、左パネルにフォーカスがある時だけ自動更新する
    if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then return end
    if vim.api.nvim_get_current_win() ~= win.left_win then return end
    refresh_current_panel()
  end))
end

local function stop_auto_refresh()
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
    refresh_timer = nil
  end
end

local ctx = {}

-- ══════════════════════════════════════════════
-- コマンドログ
-- ══════════════════════════════════════════════

local function render_cmdlog()
  if not (win.cmdlog_buf and vim.api.nvim_buf_is_valid(win.cmdlog_buf)) then return end
  local lines = {}
  for i = 1, #git.command_log do
    table.insert(lines, git.command_log[i])
  end
  if #lines == 0 then lines = { '(まだ実行なし)' } end
  vim.bo[win.cmdlog_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.cmdlog_buf, 0, -1, false, lines)
  vim.bo[win.cmdlog_buf].modifiable = false
  -- lazygit本体のAutoscroll相当: 末尾に追記していく分、ビューを常に一番下へ追従させる
  if win.cmdlog_win and vim.api.nvim_win_is_valid(win.cmdlog_win) then
    pcall(vim.api.nvim_win_set_cursor, win.cmdlog_win, { #lines, 0 })
  end
end
ctx.render_cmdlog = render_cmdlog
-- stream_output=trueのコマンドが実行中に標準出力/エラーを流し込んでくるたびに
-- 呼ばれる（vim.schedule済み）。パネルが開いていない時にも呼ばれるが、
-- render_cmdlogはcmdlog_bufの有効性チェックを持っているので安全
git.on_log_update = render_cmdlog

-- ══════════════════════════════════════════════
-- 汎用ヘルパー（各パネルモジュールに渡す）
-- ══════════════════════════════════════════════

local function refocus_left()
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    vim.api.nvim_set_current_win(win.left_win)
  end
end
ctx.refocus_left = refocus_left

function ctx.open_file_in_origin(path)
  M.close()
  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    vim.api.nvim_set_current_win(origin_win)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

function ctx.confirm(message, on_result)
  ui.confirm(message, { refocus_win = win.left_win }, on_result)
end

function ctx.input(title, default, on_submit)
  ui.input(title, default, { refocus_win = win.left_win }, on_submit)
end

function ctx.multiline_input(title, on_submit)
  ui.multiline_input({ title = title, refocus_win = win.left_win }, on_submit)
end

--- lazygitのPrompt+FindSuggestionsFunc相当。get_candidates(text)は全候補からの
--- フィルタ済み配列を返す関数（fuzzy検索は呼び出し側でvim.fn.matchfuzzy等を使う）
function ctx.suggest_input(title, get_candidates, on_submit)
  ui.suggest_input(title, { refocus_win = win.left_win }, get_candidates, on_submit)
end

function ctx.menu(title, items, on_choice)
  ui.menu(title, items, { refocus_win = win.left_win }, on_choice)
end

function ctx.set_right_lines(lines, filetype, hl_queue)
  if not (win.right_buf and vim.api.nvim_buf_is_valid(win.right_buf)) then return end
  vim.bo[win.right_buf].modifiable = true
  vim.bo[win.right_buf].filetype = filetype or 'diff'
  vim.api.nvim_buf_set_lines(win.right_buf, 0, -1, false, lines)
  vim.bo[win.right_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.right_buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue or {}) do
    vim.api.nvim_buf_add_highlight(win.right_buf, hl_ns, h[2], h[1], h[3] or 0, h[4] or -1)
  end
end

function ctx.set_left_lines(lines, hl_queue)
  if not (win.left_buf and vim.api.nvim_buf_is_valid(win.left_buf)) then return end
  vim.bo[win.left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.left_buf, 0, -1, false, lines)
  vim.bo[win.left_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.left_buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue or {}) do
    vim.api.nvim_buf_add_highlight(win.left_buf, hl_ns, h[2], h[1], h[3] or 0, h[4] or -1)
  end
  render_cmdlog()
end

function ctx.set_left_cursor(row)
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    pcall(vim.api.nvim_win_set_cursor, win.left_win, { row, 0 })
  end
end

function ctx.get_left_win() return win.left_win end
function ctx.get_left_buf() return win.left_buf end
function ctx.get_right_win() return win.right_win end
function ctx.get_right_buf() return win.right_buf end
function ctx.get_root() return git.root end
--- 表示中のパネル名（'files'/'branches'等）。パネルモジュールがpush/pull/fetch完了時などに
--- 「自分が今表示されているか」を判定し、非表示のパネルが誤って左バッファへ描画するのを防ぐ
function ctx.current_panel_name() return PANELS[current_panel_idx] and PANELS[current_panel_idx].name end

--- カーソルをlist entryのある行にクランプする汎用CursorMoved
function ctx.setup_cursor_clamp(get_line_entries, get_total_rows, on_land)
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = augrp,
    buffer = win.left_buf,
    callback = function()
      if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then return end
      local row = vim.api.nvim_win_get_cursor(win.left_win)[1]
      local entries = get_line_entries()
      if entries[row] then
        on_land(entries[row])
        return
      end
      local total = get_total_rows()
      for r = row, total do
        if entries[r] then
          pcall(vim.api.nvim_win_set_cursor, win.left_win, { r, 0 })
          return
        end
      end
      for r = row, 1, -1 do
        if entries[r] then
          pcall(vim.api.nvim_win_set_cursor, win.left_win, { r, 0 })
          return
        end
      end
    end,
  })
end

-- ══════════════════════════════════════════════
-- パネル切替
-- ══════════════════════════════════════════════

local GLOBAL_KEYS
-- switch_to -> activate_panel -> bind_click -> handle_panel_click -> switch_to と
-- 循環参照になるため、activate_panelを前方宣言しておく（GLOBAL_KEYSと同じ手法）
local activate_panel
-- toggle_cmdlog_focus(GLOBAL_KEYSより前で必要)がlayout(下で定義)を使うための前方宣言
local layout
-- switch_to内でタブ切替時に拡大状態を戻すため、collapse_cmdlog(下で定義)を先に使えるようにする
local cmdlog_focused = false
local collapse_cmdlog

-- render_tabbarで再計算するタブごとのクリック判定用バイト列範囲: { {start_col,end_col,idx}, ... }
local tab_click_ranges = {}

--- 左右パネルの上に全幅で常時表示するタブバー。狭い端末でも左パネルの枠内に
--- 収まらないため、専用の1行ウィンドウにしている
local function render_tabbar(idx)
  if not (win.tabbar_buf and vim.api.nvim_buf_is_valid(win.tabbar_buf)) then return end
  local parts = {}
  for _, p in ipairs(PANELS) do
    table.insert(parts, ' [' .. p.key .. '] ' .. p.title .. ' ')
  end
  vim.bo[win.tabbar_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.tabbar_buf, 0, -1, false, { table.concat(parts) })
  vim.bo[win.tabbar_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.tabbar_buf, hl_ns, 0, -1)
  tab_click_ranges = {}
  local col = 0
  for i, part in ipairs(parts) do
    local hl = (i == idx) and 'GitPanelTabActive' or 'GitPanelTabInactive'
    vim.api.nvim_buf_add_highlight(win.tabbar_buf, hl_ns, hl, 0, col, col + #part)
    table.insert(tab_click_ranges, { start_col = col, end_col = col + #part, idx = i })
    col = col + #part
  end
end

local function switch_to(idx)
  -- コマンドログを@で拡大したままタブを切り替えると、後から作られたcmdlog_winが
  -- left_win/right_winの上に居座り続けて新しいパネルが見えなくなるため、
  -- 切替時は必ず元の大きさに戻す。同じタブへの切替(idx==current)でも、
  -- 拡大解除とleft_winへのフォーカス復帰は行う（キー/クリックどちらの経路でも
  -- 一貫して「拡大表示から抜けてそのパネルを見る」動きになるようにする）
  collapse_cmdlog()
  if idx ~= current_panel_idx then activate_panel(idx) end
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    vim.api.nvim_set_current_win(win.left_win)
  end
end

local function switch_relative(delta)
  local idx = current_panel_idx + delta
  if idx < 1 then idx = #PANELS end
  if idx > #PANELS then idx = 1 end
  switch_to(idx)
end

--- <LeftMouse>はクリック先ではなく「クリックした瞬間にフォーカスがあった」
--- バッファのキーマップで解決される。パネル内の全バッファに同じハンドラを
--- 仕込むことで、どこにフォーカスがあっても1回目のクリックで判定が走るようにする。
--- タブバーへのクリックはタブ切替、それ以外は<LeftMouse>を上書きしたことで
--- 消えてしまう既定動作(クリック先へフォーカス移動+カーソル位置決め)を自前で再現する
local function handle_panel_click()
  local pos = vim.fn.getmousepos()
  if pos.winid == win.tabbar_win then
    local col = pos.column - 1
    for _, r in ipairs(tab_click_ranges) do
      if col >= r.start_col and col < r.end_col then
        switch_to(r.idx)
        break
      end
    end
    if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
      vim.api.nvim_set_current_win(win.left_win)
    end
    return
  end
  if pos.winid and pos.winid ~= 0 and vim.api.nvim_win_is_valid(pos.winid) then
    vim.api.nvim_set_current_win(pos.winid)
    if pos.line > 0 then
      pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(0, pos.column - 1) })
    end
  end
end

local function bind_click(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.keymap.set('n', '<LeftMouse>', handle_panel_click, { buffer = buf, nowait = true, silent = true })
  end
end

-- lazygit本体(pkg/gui/controllers/helpers/window_arrangement_helper.go getExtrasWindowSize)相当:
-- コマンドログにフォーカスすると、通常の固定行数(CommandLogSize)ではなく利用可能な
-- 領域いっぱいに広がる。ここではFiles/Diffが占めていた領域も含めて丸ごと専有させる

--- 拡大表示を元の大きさに戻す（フォーカスの移動はしない）。switch_toからも呼ぶため、
--- toggle_cmdlog_focusのelse分岐から切り出している
function collapse_cmdlog()
  if not cmdlog_focused then return end
  cmdlog_focused = false
  if not (win.cmdlog_win and vim.api.nvim_win_is_valid(win.cmdlog_win)) then return end
  local L = layout()
  vim.api.nvim_win_set_config(win.cmdlog_win, {
    relative = 'editor', row = L.cmdlog_row, col = L.outer_col,
    width = L.cmdlog_w, height = L.cmdlog_h,
  })
  vim.wo[win.cmdlog_win].cursorline = false
end

local function toggle_cmdlog_focus()
  if not (win.cmdlog_win and vim.api.nvim_win_is_valid(win.cmdlog_win)) then return end
  if not cmdlog_focused then
    local L = layout()
    cmdlog_focused = true
    vim.api.nvim_win_set_config(win.cmdlog_win, {
      relative = 'editor', row = L.top_row, col = L.outer_col,
      width = L.tabbar_w, height = L.box_h + L.cmdlog_h + 2,
    })
    vim.wo[win.cmdlog_win].cursorline = true
    vim.api.nvim_set_current_win(win.cmdlog_win)
    vim.api.nvim_win_set_cursor(win.cmdlog_win, { math.max(1, vim.api.nvim_buf_line_count(win.cmdlog_buf)), 0 })
  else
    collapse_cmdlog()
    if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
      vim.api.nvim_set_current_win(win.left_win)
    end
  end
end

function activate_panel(idx)
  current_panel_idx = idx
  local spec = PANELS[idx]
  local panel = require(spec.mod)

  vim.api.nvim_clear_autocmds({ group = augrp, buffer = win.left_buf })

  win.left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.left_buf].buftype    = 'nofile'
  vim.bo[win.left_buf].buflisted  = false
  vim.bo[win.left_buf].modifiable = false
  vim.bo[win.left_buf].filetype   = 'gitpanel'
  vim.api.nvim_win_set_buf(win.left_win, win.left_buf)
  require('config.hidden_cursor').mark_buffer(win.left_buf)
  bind_click(win.left_buf)
  vim.wo[win.left_win].wrap         = false
  vim.wo[win.left_win].number       = false
  vim.wo[win.left_win].signcolumn   = 'no'
  vim.wo[win.left_win].cursorline   = true
  vim.wo[win.left_win].winhighlight = 'Normal:GitPanelBg,CursorLine:GitPanelCursorLine'
  vim.api.nvim_win_set_config(win.left_win, { title = ' ' .. spec.title .. ' ', title_pos = 'center' })
  render_tabbar(idx)

  local keys = vim.tbl_extend('force', GLOBAL_KEYS, panel.keymaps and panel.keymaps() or {})
  for key, fn in pairs(keys) do
    vim.keymap.set('n', key, fn, { buffer = win.left_buf, nowait = true, silent = true })
  end

  panel.activate(ctx)
end

-- ══════════════════════════════════════════════
-- グローバルキー（push/pull/refresh, パネル切替, 閉じる）
-- ══════════════════════════════════════════════

--- lazygit本体(sync_controller.go pushAux/pullWithLock)と同じく、成功時は
--- 何も通知しない（パネルの再描画自体が結果を表す）。失敗時のみ通知する
local function notify_result(res, fail_prefix)
  if res.code ~= 0 then
    vim.notify(fail_prefix .. ': ' .. (res.stderr or ''), vim.log.levels.ERROR)
  end
end

-- lazygit本体(sync_controller.go)と同じ分岐:
-- ・追跡中でbehindと分かっていれば事前にforce push確認
-- ・そうでなければ通常push→rejectされたら事後にforce push確認（--force-with-lease）
-- lazygit本体(WithInlineStatus/WithWaitingStatus)は実行中のパネルにインラインで
-- "Pushing.../Pulling..."を出す。左パネルのタイトルを一時的に書き換えて同じ役割を持たせる
-- （通信中に何も表示が変わらず「動いているのか分からない」状態を防ぐ）
local function set_loading(label)
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    vim.api.nvim_win_set_config(win.left_win, { title = ' ⏳ ' .. label .. '... ', title_pos = 'center' })
  end
end

local function clear_loading()
  local spec = PANELS[current_panel_idx]
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) and spec then
    vim.api.nvim_win_set_config(win.left_win, { title = ' ' .. spec.title .. ' ', title_pos = 'center' })
  end
end
-- 各パネルモジュール(files.luaのfetch等)からも同じローディング表示を使えるようにする
ctx.set_loading = set_loading
ctx.clear_loading = clear_loading

local function attempt_push(force)
  local function on_done(res)
    clear_loading()
    ctx.render_cmdlog()
    if res.code == 0 then
      refresh_current_panel()
      require('config.git_panel.branches').refresh_prs()
      return
    end
    local err = res.stderr or ''
    if not force and err:find('rejected', 1, true) then
      ctx.confirm('リモートに新しいコミットがあり、通常のpushは拒否されました。\nforce pushしますか？(--force-with-lease)', function(yes)
        if yes then attempt_push(true) end
      end)
      return
    end
    vim.notify('push失敗: ' .. err, vim.log.levels.ERROR)
  end
  set_loading('Pushing')
  if force then
    git.push_force_with_lease(on_done)
  else
    git.push(on_done)
  end
end

local function do_push()
  git.has_upstream(function(ok)
    if not ok then
      git.branch_name(function(branch)
        ctx.confirm('アップストリームが未設定です。\norigin/' .. branch .. ' を設定してpushしますか？', function(yes)
          if not yes then return end
          set_loading('Pushing')
          git.push_set_upstream('origin', branch, function(res)
            clear_loading()
            ctx.render_cmdlog()
            notify_result(res, 'push失敗')
            refresh_current_panel()
            if res.code == 0 then require('config.git_panel.branches').refresh_prs() end
          end)
        end)
      end)
      return
    end
    git.branches(function(list)
      local current
      for _, b in ipairs(list) do
        if b.current then current = b end
      end
      local behind = current and current.track and current.track:match('behind (%d+)')
      if behind then
        ctx.confirm('リモートより ' .. behind .. ' コミット遅れています。\nforce pushしますか？(--force-with-lease)', function(yes)
          if yes then attempt_push(true) end
        end)
        return
      end
      attempt_push(false)
    end)
  end)
end

local function do_pull()
  set_loading('Pulling')
  git.pull(function(res)
    clear_loading()
    ctx.render_cmdlog()
    notify_result(res, 'pull失敗')
    refresh_current_panel()
    if res.code == 0 then require('config.git_panel.branches').refresh_prs() end
  end)
end

-- Undo(z): 直前のコミット1つを取り消す（soft reset）。checkout/rebaseのUndoは対象外
local function do_undo()
  ctx.confirm('直前のコミットを取り消しますか？\n（変更はステージ済みの状態に戻ります）', function(ok)
    if not ok then return end
    git.undo_last_commit(function(res)
      ctx.render_cmdlog()
      if res.code ~= 0 then vim.notify('undoに失敗しました: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
      refresh_current_panel()
    end)
  end)
end

GLOBAL_KEYS = {
  ['1'] = function() switch_to(1) end,
  ['2'] = function() switch_to(2) end,
  ['3'] = function() switch_to(3) end,
  ['4'] = function() switch_to(4) end,
  ['5'] = function() switch_to(5) end,
  ['<Left>'] = function() switch_relative(-1) end,
  ['<Right>'] = function() switch_relative(1) end,
  ['P'] = do_push,
  ['p'] = do_pull,
  ['z'] = do_undo,
  ['R'] = refresh_current_panel,
  ['@'] = toggle_cmdlog_focus,
  ['q'] = function() M.close() end,
  ['<Esc>'] = function() M.close() end,
}

-- ══════════════════════════════════════════════
-- レイアウト（90%x90%センター、左パネル+右diff+下部コマンドログ）
-- ══════════════════════════════════════════════

function layout()
  local total_w = math.floor(vim.o.columns * 0.9)
  local total_h = math.floor(vim.o.lines * 0.9)
  local outer_col = math.floor((vim.o.columns - total_w) / 2)
  local outer_row = math.floor((vim.o.lines - total_h) / 2)

  local hgap, vgap = 0, 0
  -- tabbarもcmdlogと同じ「ボーダー付きで全幅」の作り方に統一する
  -- （ボーダー無し要素とボーダー有り要素を混在させるとcol/row計算がずれるため）
  local tabbar_content_h = 1
  local tabbar_screen_h = tabbar_content_h + 2
  local cmdlog_content_h = 6
  local cmdlog_screen_h = cmdlog_content_h + 2

  local tabbar_row = outer_row
  local top_row = tabbar_row + tabbar_screen_h + vgap
  local top_screen_h = total_h - tabbar_screen_h - vgap - cmdlog_screen_h - vgap
  local top_content_h = top_screen_h - 2

  local left_content_w = math.floor(total_w * 0.38) - 2
  local right_content_w = total_w - (left_content_w + 2) - hgap - 2

  return {
    outer_col = outer_col, outer_row = outer_row,
    tabbar_row = tabbar_row, tabbar_w = total_w - 2, tabbar_h = tabbar_content_h,
    top_row = top_row,
    left_w = left_content_w, right_w = right_content_w, box_h = top_content_h,
    right_col = outer_col + left_content_w + 2 + hgap,
    cmdlog_row = top_row + top_screen_h + vgap,
    cmdlog_w = total_w - 2, cmdlog_h = cmdlog_content_h,
  }
end

-- ══════════════════════════════════════════════
-- 開閉
-- ══════════════════════════════════════════════

local function close_wins()
  stop_auto_refresh()
  cmdlog_focused = false
  for _, key in ipairs({ 'tabbar_win', 'left_win', 'right_win', 'cmdlog_win' }) do
    local w = win[key]
    if w and vim.api.nvim_win_is_valid(w) then
      vim.api.nvim_win_close(w, true)
    end
  end
  for _, key in ipairs({ 'tabbar_buf', 'left_buf', 'right_buf', 'cmdlog_buf' }) do
    local b = win[key]
    if b and vim.api.nvim_buf_is_valid(b) then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
  win = {}
end

function M.close()
  vim.api.nvim_clear_autocmds({ group = augrp })
  close_wins()
end

local function open()
  -- gitコマンドの完了を待たず、ウィンドウは即座に表示する（読み込み中表示→非同期で内容を反映）
  origin_win = vim.api.nvim_get_current_win()
  local L = layout()

  win.tabbar_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.tabbar_buf].buftype    = 'nofile'
  vim.bo[win.tabbar_buf].buflisted  = false
  vim.bo[win.tabbar_buf].modifiable = false
  require('config.hidden_cursor').mark_buffer(win.tabbar_buf)
  win.tabbar_win = vim.api.nvim_open_win(win.tabbar_buf, false, {
    relative = 'editor', width = L.tabbar_w, height = L.tabbar_h, col = L.outer_col, row = L.tabbar_row,
    style = 'minimal', border = 'single',
  })
  vim.wo[win.tabbar_win].winhighlight = 'Normal:GitPanelBg'
  bind_click(win.tabbar_buf)

  win.left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.left_buf].buftype = 'nofile'
  win.left_win = vim.api.nvim_open_win(win.left_buf, true, {
    relative = 'editor', width = L.left_w, height = L.box_h, col = L.outer_col, row = L.top_row,
    style = 'minimal', border = 'single', title = ' Files ', title_pos = 'center',
  })
  require('config.hidden_cursor').mark_buffer(win.left_buf)
  bind_click(win.left_buf)
  vim.bo[win.left_buf].modifiable = true
  vim.api.nvim_buf_set_lines(win.left_buf, 0, -1, false, { '  読み込み中...' })
  vim.bo[win.left_buf].modifiable = false

  win.right_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.right_buf].buftype    = 'nofile'
  vim.bo[win.right_buf].buflisted  = false
  vim.bo[win.right_buf].modifiable = false
  vim.bo[win.right_buf].filetype   = 'diff'
  require('config.hidden_cursor').mark_buffer(win.right_buf)
  win.right_win = vim.api.nvim_open_win(win.right_buf, false, {
    relative = 'editor', width = L.right_w, height = L.box_h, col = L.right_col, row = L.top_row,
    style = 'minimal', border = 'single', title = ' Diff ', title_pos = 'center',
  })
  vim.wo[win.right_win].wrap = false
  vim.wo[win.right_win].signcolumn = 'no'
  vim.wo[win.right_win].winhighlight = 'Normal:GitPanelBg'
  bind_click(win.right_buf)

  win.cmdlog_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.cmdlog_buf].buftype    = 'nofile'
  vim.bo[win.cmdlog_buf].buflisted  = false
  vim.bo[win.cmdlog_buf].modifiable = false
  require('config.hidden_cursor').mark_buffer(win.cmdlog_buf)
  win.cmdlog_win = vim.api.nvim_open_win(win.cmdlog_buf, false, {
    relative = 'editor', width = L.cmdlog_w, height = L.cmdlog_h, col = L.outer_col, row = L.cmdlog_row,
    style = 'minimal', border = 'single', title = ' Command Log ', title_pos = 'center',
  })
  vim.wo[win.cmdlog_win].wrap = false
  bind_click(win.cmdlog_buf)
  vim.wo[win.cmdlog_win].signcolumn = 'no'
  vim.wo[win.cmdlog_win].winhighlight = 'Normal:GitPanelBg'
  -- フォーカス中(@で拡大)は @/q/Escで元の大きさに戻す。フォーカス前ならq/Escはパネル自体を閉じる
  for _, key in ipairs({ '@', 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if cmdlog_focused then toggle_cmdlog_focus() else M.close() end
    end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  end
  -- 拡大表示中もパネル切替キーは効くようにする（left_bufにしかバインドされていないと、
  -- フォーカスがcmdlog_bufにある間は1-5/矢印が反応しなくなってしまう）
  vim.keymap.set('n', '1', function() switch_to(1) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '2', function() switch_to(2) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '3', function() switch_to(3) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '4', function() switch_to(4) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '5', function() switch_to(5) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Left>', function() switch_relative(-1) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Right>', function() switch_relative(1) end, { buffer = win.cmdlog_buf, nowait = true, silent = true })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = augrp,
    pattern = tostring(win.tabbar_win) .. ',' .. tostring(win.left_win) .. ',' .. tostring(win.right_win) .. ',' .. tostring(win.cmdlog_win),
    callback = function() M.close() end,
  })

  git.find_root(function(root)
    if not root then
      vim.notify('gitリポジトリではありません', vim.log.levels.ERROR)
      M.close()
      return
    end
    render_cmdlog()
    activate_panel(1)
    start_auto_refresh()
  end)
end

function M.open()
  if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then
    open()
  end
end

function M.toggle()
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    M.close()
  else
    open()
  end
end

-- ══════════════════════════════════════════════
-- ハイライト
-- ══════════════════════════════════════════════

local function setup_hl()
  vim.api.nvim_set_hl(0, 'GitPanelBg',           { bg = '#1a1b26' })
  vim.api.nvim_set_hl(0, 'GitPanelCursorLine',   { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'GitPanelHeader',       { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelSection',      { fg = '#e0af68', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelModified',     { fg = '#e0af68' })
  vim.api.nvim_set_hl(0, 'GitPanelAdded',        { fg = '#9ece6a' })
  vim.api.nvim_set_hl(0, 'GitPanelDeleted',      { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'GitPanelStatusStaged',   { fg = '#9ece6a' })
  vim.api.nvim_set_hl(0, 'GitPanelStatusUnstaged', { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'GitPanelRenamed',      { fg = '#2ac3de' })
  vim.api.nvim_set_hl(0, 'GitPanelUntracked',    { fg = '#9ece6a', italic = true })
  vim.api.nvim_set_hl(0, 'GitPanelCurrent',      { fg = '#9ece6a', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelUnpushed',     { fg = '#f7768e' })
  vim.api.nvim_set_hl(0, 'GitPanelPushed',       { fg = '#e0af68' })
  vim.api.nvim_set_hl(0, 'GitPanelMerged',       { fg = '#9ece6a' })
  -- lazygit本体(presentation/branches.go WithPrColor)と同じ配色
  vim.api.nvim_set_hl(0, 'GitPanelPrOpen',       { fg = '#438440' })
  vim.api.nvim_set_hl(0, 'GitPanelPrClosed',     { fg = '#C9453C' })
  vim.api.nvim_set_hl(0, 'GitPanelPrMerged',     { fg = '#8259DD' })
  vim.api.nvim_set_hl(0, 'GitPanelPrDraft',      { fg = '#676C75' })
  vim.api.nvim_set_hl(0, 'GitPanelHunkSelected', { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'GitPanelTabActive',    { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelTabInactive',  { fg = '#565f89' })
  ui.setup_hl()
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

-- <leader>gg（ターミナル版lazygit）と接頭辞が被るため、timeoutlen待ちが起きないようnowaitで即時発火させる
vim.keymap.set('n', '<leader>g', function() M.toggle() end, { desc = 'gitパネルを開閉', nowait = true })
vim.api.nvim_create_user_command('Git', function() M.toggle() end, { desc = 'gitパネルを開閉' })

return M
