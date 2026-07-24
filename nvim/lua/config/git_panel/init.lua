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
  { key = '6', name = 'pr',       title = 'PR',       mod = 'config.git_panel.pr' },
}

local win = {}
local origin_win
local fullscreen_mode = false
local augrp = vim.api.nvim_create_augroup('git_panel', { clear = true })
local hl_ns = vim.api.nvim_create_namespace('git_panel_hl')
local current_panel_idx = 1
local refresh_timer = nil
--- 右パネルに今実際に描画されている内容（key+内容）。同じなら再描画自体をスキップして
--- ちらつき/スクロールリセットを防ぐ。パネル切替時にnilへ戻し、必ず最初の1回は描画する
local last_right_key = nil
local last_right_content = nil
--- set_right_diffが「delta実行前のraw diffテキスト」の変化なしを判定するための別キャッシュ
--- （set_right_ansi/set_right_linesのキャッシュとは別に、deltaサブプロセス自体の起動も省く）
local last_right_raw_key = nil
local last_right_raw_text = nil
-- recreate_right_buf(ctx.set_right_lines/set_right_ansiより上で必要)がbind_click/
-- bind_diff_keys(パネル切替セクションで定義)を使うための前方宣言
local bind_click
local bind_diff_keys

-- lazygit(pkg/gui/background.go)は10秒ごとのFiles再取得+2秒ごとの外部変更検知(reflog等)
-- を別々のタイマーで走らせているが、こちらは常に1パネルだけを表示する構成なので
-- 「表示中のパネルを2秒おきに再取得」だけに単純化して同じ体感（外部でのgit操作が
-- 自動的に反映される）を再現する
local AUTO_REFRESH_INTERVAL_MS = 2000

--- 「押したから更新する」(R)と「勝手に定期更新する」(auto refresh)の両方から使う共通処理。
--- 各パネルモジュールが持つremember_cursor()（無ければ何もしない）で「今カーソルが
--- 乗っている項目」を記録してからrefresh()する。これをしないと、ユーザーが単に
--- j/kで見ているだけの項目情報が古いまま(あるいは無いまま)再描画されてカーソルが
--- 先頭などに戻ってしまう
--- refresh(true)を渡すと、各パネルモジュールは非同期取得が完了してrender()する直前という
--- 一番遅いタイミングで現在のカーソル位置を捕捉する。ここ(呼び出し前)で捕捉すると、
--- 非同期のgitコマンドが完了するまでの間にユーザーがj/kで動かした分を取りこぼして
--- カーソルが古い位置に戻ってしまうため、タイミングを意図的に遅らせている
local function refresh_current_panel(is_auto)
  local spec = PANELS[current_panel_idx]
  if not spec then return end
  local mod = require(spec.mod)
  -- ネットワーク取得系(PR等)は自動更新の対象外にする（点滅・負荷防止。手動Rは対象）
  if is_auto and mod.auto_refresh == false then return end
  mod.refresh(true)
end

local function start_auto_refresh()
  if refresh_timer then return end
  refresh_timer = vim.uv.new_timer()
  refresh_timer:start(AUTO_REFRESH_INTERVAL_MS, AUTO_REFRESH_INTERVAL_MS, vim.schedule_wrap(function()
    -- hunkステージング中やモーダル表示中(フォーカスがleft_win以外)は再描画で状態が
    -- 消えてしまうため、左パネルにフォーカスがある時だけ自動更新する
    if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then return end
    if vim.api.nvim_get_current_win() ~= win.left_win then return end
    refresh_current_panel(true)
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

--- vキー(delta side-by-side切替)相当。left_buf(GLOBAL_KEYS経由)と、diffパネルを
--- +で拡大してフォーカスが移った時(bind_diff_keys)の両方から使うため共通化する
local function toggle_side_by_side_key()
  local on = git.toggle_side_by_side()
  ctx.invalidate_right_cache()
  refresh_current_panel()
  vim.notify('delta side-by-side: ' .. (on and 'ON' or 'OFF'), vim.log.levels.INFO)
end

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
  -- lazygitのAutoscroll相当: 末尾に追記していく分、ビューを常に一番下へ追従させる
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

--- delta表示(set_right_ansi)はterminalバッファを使うため、通常のプレーンテキスト表示に
--- 戻す時/ANSI表示に切り替える時はバッファを作り直す必要がある（terminalバッファは
--- nvim_buf_set_linesで書き換えられない・逆にプレーンバッファはchansendを受け付けない）
local function recreate_right_buf(as_terminal)
  local old_buf = win.right_buf
  win.right_buf = vim.api.nvim_create_buf(false, true)
  if not as_terminal then
    vim.bo[win.right_buf].buftype = 'nofile'
    vim.bo[win.right_buf].buflisted = false
  end
  -- nvim_win_set_bufはフォーカスしていなくてもBufEnterを発火し、その一瞬だけ
  -- 「カレントバッファ」がこのバッファとして扱われる。hidden_cursorの判定
  -- (vim.b.hide_cursor)がその瞬間に走るため、ウィンドウへ差し込む前に必ずマークする
  -- (explorer.luaで踏んだのと同じ順序バグ。+でdiffパネルに実際にフォーカスが
  -- 移るようになったことで、今まで気にならなかったこのタイミングのズレが
  -- カーソル復活として表面化した)
  require('config.hidden_cursor').mark_buffer(win.right_buf)
  -- 新しいバッファをウィンドウへ差し込んでから古いバッファを消す。逆順（先に削除）だと、
  -- 特にterminalバッファを表示中に削除した時、Neovimがwin.right_win自体を閉じてしまうことが
  -- あり、そのウィンドウIDを監視しているWinClosedハンドラでgitパネル全体が閉じてしまっていた
  if win.right_win and vim.api.nvim_win_is_valid(win.right_win) then
    vim.api.nvim_win_set_buf(win.right_win, win.right_buf)
  end
  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
  end
  bind_click(win.right_buf)
  bind_diff_keys(win.right_buf)
end

--- 内容が前回と全く同じなら右パネルに一切触れない（プレーンバッファへのnvim_buf_set_lines
--- は同一内容の再設定ならスクロール位置を動かさないので元々問題無いが、
--- set_right_ansi(delta表示)はterminalバッファを毎回作り直すため、内容が同じでも
--- 呼ぶたびに先頭に戻る/自動追従でちらつく。key+内容が変わっていない時は描画自体を
--- スキップすることで、スクロール位置の復元を頑張る必要も無く両方解決する
local function unchanged(key, content_sig)
  if key == nil then return false end
  local same = key == last_right_key and content_sig == last_right_content
  last_right_key, last_right_content = key, content_sig
  return same
end

--- key: 今表示している内容の識別子（ファイルpath/コミットhash等）。省略時(nil)は
--- 変化なし判定の対象外（静的なメッセージ表示などで使う）
function ctx.set_right_lines(lines, filetype, hl_queue, key)
  if not (win.right_buf and vim.api.nvim_buf_is_valid(win.right_buf)) then return end
  if unchanged(key, table.concat(lines, '\n')) then return end
  if vim.bo[win.right_buf].buftype == 'terminal' then recreate_right_buf(false) end
  vim.bo[win.right_buf].modifiable = true
  vim.bo[win.right_buf].filetype = filetype or 'diff'
  vim.api.nvim_buf_set_lines(win.right_buf, 0, -1, false, lines)
  vim.bo[win.right_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(win.right_buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue or {}) do
    vim.api.nvim_buf_add_highlight(win.right_buf, hl_ns, h[2], h[1], h[3] or 0, h[4] or -1)
  end
end

--- delta等が出力する生ANSIテキストをそのまま色付きで表示する（nvim_open_termでlibvtermに
--- 解釈させる。実プロセスは繋がず、静的な色付きテキストの表示器として使うだけ）
function ctx.set_right_ansi(ansi_text, key)
  if not (win.right_win and vim.api.nvim_win_is_valid(win.right_win)) then return end
  if unchanged(key, ansi_text) then return end
  recreate_right_buf(true)
  local chan = vim.api.nvim_open_term(win.right_buf, {})
  vim.api.nvim_chan_send(chan, ansi_text)
end

--- deltaが使えれば自動で通して色付き表示、無ければ素のテキスト表示にフォールバックする。
--- ファイルdiff・commit show・stash show -pなど「diffテキストを右パネルに出す」処理は
--- files.lua/commits.lua/stash.luaで同じ内容だったのでここに一本化した。
--- rawの生diffが前回と同じならdeltaへ渡すことすらしない（無駄なサブプロセス起動も省く）
function ctx.right_width()
  return (win.right_win and vim.api.nvim_win_is_valid(win.right_win))
    and vim.api.nvim_win_get_width(win.right_win) or 80
end

function ctx.set_right_diff(text, key)
  if key ~= nil and key == last_right_raw_key and text == last_right_raw_text then
    return
  end
  last_right_raw_key, last_right_raw_text = key, text
  if not git.delta_available then
    ctx.set_right_lines(vim.split(text, '\n', { plain = true }), 'diff', nil, key)
    return
  end
  local width = (win.right_win and vim.api.nvim_win_is_valid(win.right_win))
    and vim.api.nvim_win_get_width(win.right_win) or 80
  git.run_delta(text, width, function(ansi)
    if ansi then
      ctx.set_right_ansi(ansi, key)
    else
      ctx.set_right_lines(vim.split(text, '\n', { plain = true }), 'diff', nil, key)
    end
  end)
end

--- 各パネルモジュールのcurrent_entry()が全て同じ内容（left_winのカーソル行を
--- line_entriesから引く）だったのでここに一本化した。呼び出し側は自分の
--- line_entriesを返すクロージャを渡す
--- side-by-side切替等、キャッシュ済みの内容と無関係に右パネルを強制再描画したい時に使う
function ctx.invalidate_right_cache()
  last_right_key, last_right_content = nil, nil
  last_right_raw_key, last_right_raw_text = nil, nil
end

function ctx.current_entry(get_line_entries)
  if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then return nil end
  local row = vim.api.nvim_win_get_cursor(win.left_win)[1]
  return get_line_entries()[row]
end

--- git操作後の定型パターン(コマンドログ更新→失敗時のみ通知→再取得)を共通化。
--- refresh_fnは各パネルのM.refresh（呼び出し側が事前にcursor_memを設定していれば
--- そこへ着地する。auto_captureは渡さない＝明示的操作の結果として呼ばれるため）
function ctx.done_refresh(refresh_fn, label)
  return function(res)
    ctx.render_cmdlog()
    if res.code ~= 0 then vim.notify(label .. '失敗: ' .. (res.stderr or ''), vim.log.levels.ERROR) end
    refresh_fn()
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
-- diffパネルの拡大とコマンドログの拡大は同じ領域を専有するため、互いに排他制御する
-- 必要がある。定義順の都合で先に前方宣言しておく
local diff_focused = false
local collapse_diff_focus

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
  collapse_diff_focus()
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

function bind_click(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.keymap.set('n', '<LeftMouse>', handle_panel_click, { buffer = buf, nowait = true, silent = true })
  end
end

-- lazygit(pkg/gui/controllers/helpers/window_arrangement_helper.go getExtrasWindowSize)相当:
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
    collapse_diff_focus() -- 同じ領域を専有するため排他
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

--- Diffパネルの拡大表示。lazygit本体は+/_でNORMAL/HALF/FULLの3段階の画面モードを
--- 切り替え、main(diff)にフォーカスがある時だけ左の一覧が縮む/消えるという仕組み
--- (window_arrangement_helper.go getMidSectionWeights)だが、ここではコマンドログの
--- @トグルと揃えたシンプルな2状態トグルにしている。cmdlog拡大と同じ領域(タブバーの
--- 下、Files/Diff/コマンドログが占めていた範囲全体)を専有する
--- 拡大表示を元の大きさに戻す（フォーカスの移動はしない）。switch_toからも呼ぶため、
--- toggle_diff_focusのelse分岐から切り出している
function collapse_diff_focus()
  if not diff_focused then return end
  diff_focused = false
  if not (win.right_win and vim.api.nvim_win_is_valid(win.right_win)) then return end
  local L = layout()
  vim.api.nvim_win_set_config(win.right_win, {
    relative = 'editor', row = L.top_row, col = L.right_col,
    width = L.right_w, height = L.box_h,
  })
  -- delta出力は生成時の幅で固定されているため、ウィンドウ幅が変わっただけでは
  -- 見た目が追従しない。キャッシュを無効化して同じ内容を新しい幅で再描画させる
  ctx.invalidate_right_cache()
  refresh_current_panel()
end

local function toggle_diff_focus()
  if not (win.right_win and vim.api.nvim_win_is_valid(win.right_win)) then return end
  if not diff_focused then
    collapse_cmdlog() -- 同じ領域を専有するため排他
    local L = layout()
    diff_focused = true
    vim.api.nvim_win_set_config(win.right_win, {
      relative = 'editor', row = L.top_row, col = L.outer_col,
      width = L.tabbar_w, height = L.box_h + L.cmdlog_h + 2,
    })
    vim.api.nvim_set_current_win(win.right_win)
    -- 同じ理由で、拡大した新しい幅でdelta出力を再生成する
    ctx.invalidate_right_cache()
    refresh_current_panel()
  else
    collapse_diff_focus()
    if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
      vim.api.nvim_set_current_win(win.left_win)
    end
  end
end

--- diffパネルはrecreate_right_buf()で内容更新のたびにバッファが作り直されるため、
--- bind_clickと同様、作り直すたびに呼んで再設定する必要がある
function bind_diff_keys(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  vim.keymap.set('n', '+', toggle_diff_focus, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', 'v', toggle_side_by_side_key, { buffer = buf, nowait = true, silent = true })
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if diff_focused then toggle_diff_focus() else M.close() end
    end, { buffer = buf, nowait = true, silent = true })
  end
  for _, k in ipairs({ '1', '2', '3', '4', '5', '6' }) do
    vim.keymap.set('n', k, function() switch_to(tonumber(k)) end, { buffer = buf, nowait = true, silent = true })
  end
  vim.keymap.set('n', '<Left>', function() switch_relative(-1) end, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Right>', function() switch_relative(1) end, { buffer = buf, nowait = true, silent = true })
end

function activate_panel(idx)
  current_panel_idx = idx
  last_right_key, last_right_content = nil, nil
  last_right_raw_key, last_right_raw_text = nil, nil
  local spec = PANELS[idx]
  local panel = require(spec.mod)

  vim.api.nvim_clear_autocmds({ group = augrp, buffer = win.left_buf })

  win.left_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[win.left_buf].buftype    = 'nofile'
  vim.bo[win.left_buf].buflisted  = false
  vim.bo[win.left_buf].modifiable = false
  vim.bo[win.left_buf].filetype   = 'gitpanel'
  -- ウィンドウへ差し込む前に必ずマークする(recreate_right_bufと同じ理由:
  -- nvim_win_set_bufはフォーカスしていなくてもBufEnterを発火するため)
  require('config.hidden_cursor').mark_buffer(win.left_buf)
  vim.api.nvim_win_set_buf(win.left_win, win.left_buf)
  bind_click(win.left_buf)
  vim.wo[win.left_win].wrap         = false
  vim.wo[win.left_win].number       = false
  vim.wo[win.left_win].signcolumn   = 'no'
  vim.wo[win.left_win].cursorline   = true
  vim.wo[win.left_win].winhighlight = 'Normal:GitPanelBg,CursorLine:GitPanelCursorLine,FloatBorder:GitPanelBorder'
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

--- lazygit(sync_controller.go pushAux/pullWithLock)と同じく、成功時は
--- 何も通知しない（パネルの再描画自体が結果を表す）。失敗時のみ通知する
local function notify_result(res, fail_prefix)
  if res.code ~= 0 then
    vim.notify(fail_prefix .. ': ' .. (res.stderr or ''), vim.log.levels.ERROR)
  end
end

-- lazygit(sync_controller.go)と同じ分岐:
-- ・追跡中でbehindと分かっていれば事前にforce push確認
-- ・そうでなければ通常push→rejectされたら事後にforce push確認（--force-with-lease）
-- lazygit(WithInlineStatus/WithWaitingStatus)は実行中のパネルにインラインで
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

-- modeはnil(通常push)|'lease'(behind事前検知からのforce-with-lease)|'force'(reject後の素のforce)。
-- lazygit(sync_controller.go pushAux)と同じく、reject後のリトライには--force-with-leaseではなく
-- 素の--forceを使う: force-with-leaseはローカルが知るリモートの状態が最新であることが前提の安全
-- 機構であり、rejectされる状況(=ローカルがリモートの現在地を知らない)ではその前提自体が崩れていて
-- 「stale info」で再度失敗するため
local function attempt_push(mode)
  local function on_done(res)
    clear_loading()
    ctx.render_cmdlog()
    if res.code == 0 then
      refresh_current_panel()
      require('config.git_panel.branches').refresh_prs()
      return
    end
    local err = res.stderr or ''
    if not mode and err:find('rejected', 1, true) then
      ctx.confirm('リモートに新しいコミットがあり、通常のpushは拒否されました。\nforce pushしますか？(--force)', function(yes)
        if yes then attempt_push('force') end
      end)
      return
    end
    vim.notify('push失敗: ' .. err, vim.log.levels.ERROR)
  end
  set_loading('Pushing')
  if mode == 'lease' then
    git.push_force_with_lease(on_done)
  elseif mode == 'force' then
    git.push_force(on_done)
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
          if yes then attempt_push('lease') end
        end)
        return
      end
      attempt_push()
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
  ['6'] = function() switch_to(6) end,
  ['<Left>'] = function() switch_relative(-1) end,
  ['<Right>'] = function() switch_relative(1) end,
  ['P'] = do_push,
  ['p'] = do_pull,
  ['z'] = do_undo,
  ['R'] = refresh_current_panel,
  ['v'] = toggle_side_by_side_key,
  ['@'] = toggle_cmdlog_focus,
  ['+'] = toggle_diff_focus,
  ['q'] = function() M.close() end,
  ['<Esc>'] = function() M.close() end,
}

-- ══════════════════════════════════════════════
-- レイアウト（90%x90%センター、左パネル+右diff+下部コマンドログ）
-- ══════════════════════════════════════════════

function layout()
  -- explorer.luaの:Explorer!と同じく、全画面表示時は画面いっぱい(コマンドライン分の
  -- 2行だけ残す)を使う。中身のパネル構成・計算は90%表示と全く同じで、total_w/total_h/
  -- outer_col/outer_rowの元になる値だけが変わる
  local total_w, total_h, outer_col, outer_row
  if fullscreen_mode then
    total_w, total_h = vim.o.columns, vim.o.lines - 2
    outer_col, outer_row = 0, 0
  else
    total_w = math.floor(vim.o.columns * 0.9)
    total_h = math.floor(vim.o.lines * 0.9)
    outer_col = math.floor((vim.o.columns - total_w) / 2)
    outer_row = math.floor((vim.o.lines - total_h) / 2)
  end

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
  fullscreen_mode = false
end

--- 全画面表示は「これがこのnvimプロセスの用件そのもの」という前提(herdrの
--- popupから nvim +Git! で直接立ち上げる運用等)なので、閉じる操作(q/Esc/:q
--- どれでも最終的にここを通る)がそのまま裏側の元バッファへ戻るのではなく、
--- nvim自体を終了させる。通常の90%表示ではこれまで通り単に閉じるだけ
function M.close()
  local was_fullscreen = fullscreen_mode
  vim.api.nvim_clear_autocmds({ group = augrp })
  close_wins()
  if was_fullscreen then
    vim.cmd('qall')
  end
end

local function open(fullscreen)
  -- gitコマンドの完了を待たず、ウィンドウは即座に表示する（読み込み中表示→非同期で内容を反映）
  fullscreen_mode = fullscreen or false
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
  vim.wo[win.tabbar_win].winhighlight = 'Normal:GitPanelBg,FloatBorder:GitPanelBorder'
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
  vim.wo[win.right_win].winhighlight = 'Normal:GitPanelBg,FloatBorder:GitPanelBorder'
  bind_click(win.right_buf)
  bind_diff_keys(win.right_buf)

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
  vim.wo[win.cmdlog_win].winhighlight = 'Normal:GitPanelBg,FloatBorder:GitPanelBorder'
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

function M.open(fullscreen)
  if not (win.left_win and vim.api.nvim_win_is_valid(win.left_win)) then
    open(fullscreen)
  end
end

function M.toggle(fullscreen)
  if win.left_win and vim.api.nvim_win_is_valid(win.left_win) then
    M.close()
  else
    open(fullscreen)
  end
end

-- ══════════════════════════════════════════════
-- ハイライト
-- ══════════════════════════════════════════════

local function setup_hl()
  vim.api.nvim_set_hl(0, 'GitPanelBg',           { bg = '#282828' })
  vim.api.nvim_set_hl(0, 'GitPanelBorder',       { bg = '#282828', fg = '#565f89' })
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
  -- lazygit(presentation/branches.go WithPrColor)と同じ配色
  vim.api.nvim_set_hl(0, 'GitPanelPrOpen',       { fg = '#438440' })
  vim.api.nvim_set_hl(0, 'GitPanelPrClosed',     { fg = '#C9453C' })
  vim.api.nvim_set_hl(0, 'GitPanelPrMerged',     { fg = '#8259DD' })
  vim.api.nvim_set_hl(0, 'GitPanelPrDraft',      { fg = '#676C75' })
  vim.api.nvim_set_hl(0, 'GitPanelHunkSelected', { bg = '#2d3250' })
  vim.api.nvim_set_hl(0, 'GitPanelSelected',     { fg = '#e0af68', bg = '#e0af68' })
  vim.api.nvim_set_hl(0, 'GitPanelTabActive',    { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitPanelTabInactive',  { fg = '#565f89' })
  ui.setup_hl()
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

-- <leader>gg（ターミナル版lazygit）と接頭辞が被るため、timeoutlen待ちが起きないようnowaitで即時発火させる
vim.keymap.set('n', '<leader>g', function() M.toggle() end, { desc = 'gitパネルを開閉', nowait = true })
vim.api.nvim_create_user_command('Git', function(cmd_opts) M.toggle(cmd_opts.bang) end, { bang = true, desc = 'gitパネルを開閉（!で全画面表示）' })

return M
