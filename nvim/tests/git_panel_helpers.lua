-- git_panel系specの共通ヘルパー。実際にgit_panel.open()でUIを開き、実キー入力
-- (:normal、バング無し=マッピング有効)で操作して結果を確認する方式に統一する
-- (手作りのctxモックは本物のinit.luaの配線とズレるリスクがあるため使わない)
--
-- 重要な注意: fullscreen(true)で開いた後にM.open()/M.close()を呼ぶと、
-- init.luaの仕様で内部的にvim.cmd('qall')が実行され「このテストプロセス自体」が
-- 終了する(git_panel_init_spec.luaで実際にこれにハマり、テストが1文字も出力せず
-- 無言で終了するように見えた)。fullscreenを開いたら、そのプロセス内でclose()や
-- 次のopen()を呼ばないこと。fullscreenの検証は必ず別プロセス(vim.system + nvim -l)
-- で行い、そのプロセス自体はos.exit()で直接終了させる(closeを経由しない)

local M = {}

function M.open(dir, fullscreen)
  -- 前のitがassertion失敗で中断し、後始末(close)まで到達できなかった場合でも
  -- 次のテストへ汚染が伝播しないよう、開く前に必ず一度閉じておく(冪等)
  local gp = require('config.git_panel')
  pcall(gp.close)
  vim.fn.chdir(dir)
  gp.open(fullscreen)
  vim.wait(400)
  return gp
end

--- タイトル文字列(部分一致)からfloatウィンドウを探す
function M.win_by_title(title_part)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= '' then
      local title = cfg.title
      if title then
        local text = {}
        for _, chunk in ipairs(title) do table.insert(text, chunk[1]) end
        if table.concat(text):find(title_part, 1, true) then return w end
      end
    end
  end
  return nil
end

function M.left_win() return M.win_by_title('Files') or M.win_by_title('Commits')
  or M.win_by_title('Branches') or M.win_by_title('Stash') or M.win_by_title('Worktree')
  or M.win_by_title('PR') end

function M.right_win() return M.win_by_title('Diff') or M.win_by_title('プレビュー') end

function M.lines(win)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

--- 部分文字列に一致する最初の行(1-indexed)を返す。無ければnil
function M.find_row(win, substring)
  for i, l in ipairs(M.lines(win)) do
    if l:find(substring, 1, true) then return i end
  end
  return nil
end

--- カーソルを指定行へ移動し(CursorMovedも発火させて右パネル連動も反映させる)
function M.goto_row(win, row)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_win_get_buf(win) })
end

--- <Space>や<CR>等のキー表記を実際のバイト列に変換してnvim_feedkeysで送る。
--- :normalだと引数が空白1文字だけの時にE471になったり表記変換もされないため、
--- feedkeys(mode='x'=同期実行、マッピングは有効)の方が安定する
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

--- 左パネルにフォーカスして {cmds} をノーマルモードのキー入力として実行する
--- (`normal!`ではなく`normal`=マッピング有効。bangを付けると自作キーマップが
--- 一切発火しなくなる点に注意)
function M.press(keys)
  local win = M.left_win()
  vim.api.nvim_set_current_win(win)
  feed(keys)
end

--- モーダル(confirm/menu/input)のバッファにフォーカスしてキーを送る。
--- モーダルはopen_win(...,true,...)で開かれ即フォーカスされるので、
--- 現在のカレントウィンドウがそのまま対象になる
function M.press_modal(keys)
  feed(keys)
end

function M.status(dir)
  return vim.system({ 'git', 'status', '--porcelain=v1' }, { cwd = dir, text = true }):wait().stdout or ''
end

function M.git(dir, args)
  local name, email = 'test', 'test@test'
  local i = 1
  while i <= #args do
    if args[i] == '-c' and args[i + 1] then
      local n = args[i + 1]:match('^user%.name=(.+)$')
      local e = args[i + 1]:match('^user%.email=(.+)$')
      if n then name = n end
      if e then email = e end
    end
    i = i + 1
  end
  local env = vim.fn.environ()
  env.GIT_AUTHOR_NAME = name
  env.GIT_AUTHOR_EMAIL = email
  env.GIT_COMMITTER_NAME = name
  env.GIT_COMMITTER_EMAIL = email
  return vim.system(vim.list_extend({ 'git' }, args), { cwd = dir, text = true, env = env }):wait()
end

function M.close()
  require('config.git_panel').close()
  -- 操作後のrefresh連鎖(resolve_main_branches等、複数段の非同期git呼び出し)が
  -- 完全に片付く前に呼び出し元がtmpディレクトリをrmrfすると、後から発火した
  -- コールバックが削除済みcwdへgitを起動しようとしてENOENTを吐く。ここで少し
  -- 長めに待つことでその残存を減らす(根本的な直列化保証ではないので目安)
  vim.wait(300)
end

return M
