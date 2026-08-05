-- 右ペインのサブタブ（枠のタイトルとして描かれる）を「実際にクリックして」切り替わることを確認する。
--
-- headless(nvim -l)ではUIが無く、nvim_input_mouse を送っても <LeftMouse> のマッピングが
-- 発火しない（実測済み）。そこで子プロセスとして `nvim --embed` を起動し、nvim_ui_attach で
-- 本物のUIを張ってからマウスイベントを送る。
--
-- 重要: クリック位置は「画面を読んで実際にタブ文字が描かれている場所」を使う。
-- ウィンドウ位置からの計算値を使ってしまうと、実装と同じ式でクリックすることになり
-- 座標のズレ（nvim_win_get_position が枠を含む箱の左上を返す、等）を検出できない。

local T = dofile(TESTS_DIR .. '/helpers.lua')

local NVIM_DIR = TESTS_DIR:gsub('/tests$', '')

--- 実UIを張った子nvimを起動して、dockerパネルのContainersを開いた状態にする
local function start_child()
  local chan = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless' }, { rpc = true })
  assert(chan > 0, 'failed to start child nvim')
  local function lua(code, args) return vim.rpcrequest(chan, 'nvim_exec_lua', code, args or {}) end

  vim.rpcrequest(chan, 'nvim_ui_attach', 120, 40, { rgb = true, ext_multigrid = false })
  lua([[
    vim.opt.rtp:append(...)
    vim.o.mouse = 'nv'
    vim.o.lines, vim.o.columns = 40, 120
  ]], { NVIM_DIR })
  lua([[
    TESTS_DIR = ...
    D = dofile(TESTS_DIR .. '/docker_panel_helpers.lua')
    ST = D.fake_docker({
      containers = { D.container_json({ id = 'aaa111', name = 'web', state = 'running' }) },
      images = {}, volumes = {}, networks = {},
    })
    D.open()
  ]], { NVIM_DIR .. '/tests' })
  vim.wait(1500)
  lua([[ D.press('2') ]])
  vim.wait(1500)
  return chan, lua
end

--- 画面を走査して、タブ文字列が実際に描かれている行(1始まり)と、
--- 指定タブ名の開始桁(1始まり)を返す。
--- 注意: screenstring() の結果を連結して find すると「バイト位置」が返り、罫線などの
--- マルチバイト文字があるぶん桁とズレる。必ずセル単位で1桁ずつ突き合わせること
local function find_tab_on_screen(lua, name)
  return lua([[
    local name = ...
    local function col_of(row, needle)
      for c = 1, vim.o.columns do
        local ok = true
        for i = 1, #needle do
          if vim.fn.screenstring(row, c + i - 1) ~= needle:sub(i, i) then ok = false; break end
        end
        if ok then return c end
      end
    end
    for row = 1, vim.o.lines do
      -- タブが並んでいる行（Logs と Stats が同じ行にある）を探す
      if col_of(row, 'Logs') and col_of(row, 'Stats') then
        return { row = row, col = col_of(row, name) }
      end
    end
    return nil
  ]], { name })
end

T.describe('docker_panel right-pane tabs are clickable', function()
  T.it('clicking the tab text drawn on the border switches to that tab', function()
    local chan, lua = start_child()

    T.eq(lua([[ return D.right_active_tab() ]]), 'Logs', '最初はLogsタブ')

    local stats = find_tab_on_screen(lua, 'Stats')
    T.ok(stats ~= nil and stats.col ~= nil, 'タブが画面に描かれている')

    -- 実際に描かれている "Stats" の上をクリックする（nvim_input_mouse は0始まり）
    vim.rpcrequest(chan, 'nvim_input_mouse', 'left', 'press', '', 0, stats.row - 1, stats.col - 1)
    vim.wait(1000)
    T.eq(lua([[ return D.right_active_tab() ]]), 'Stats', 'クリックしたタブに切り替わる')
    T.contains(table.concat(lua([[ return D.lines(D.right_win()) ]]), '\n'), '1.50%',
      '右ペインの中身もそのタブのものに変わる')

    local top = find_tab_on_screen(lua, 'Top')
    vim.rpcrequest(chan, 'nvim_input_mouse', 'left', 'press', '', 0, top.row - 1, top.col - 1)
    vim.wait(1000)
    T.eq(lua([[ return D.right_active_tab() ]]), 'Top', '別のタブもクリックで切り替わる')

    vim.fn.jobstop(chan)
  end)

  T.it('clicking the border away from the tabs does not change the tab', function()
    local chan, lua = start_child()
    local logs = find_tab_on_screen(lua, 'Logs')
    T.eq(lua([[ return D.right_active_tab() ]]), 'Logs')

    -- タブ列の左端よりさらに左（枠線だけの部分）をクリックしても切り替わらない
    vim.rpcrequest(chan, 'nvim_input_mouse', 'left', 'press', '', 0, logs.row - 1, math.max(0, logs.col - 6))
    vim.wait(600)
    T.eq(lua([[ return D.right_active_tab() ]]), 'Logs', 'タブ以外のボーダーは無反応')

    vim.fn.jobstop(chan)
  end)
end)

T.summary()
