-- dockerパネルとgitパネルが config/panel/shell.lua を共有していること＝
-- 「見た目が全く同じ」であることを、実際に両方開いてウィンドウ構成を突き合わせて確認する。
-- （どちらかのレイアウト計算だけを変えてしまった時にここで落ちる）

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local D = dofile(TESTS_DIR .. '/docker_panel_helpers.lua')

local function fake()
  return D.fake_docker({
    containers = {
      D.container_json({ id = 'aaa111', name = 'web', status = 'Up 3 minutes', state = 'running' }),
    },
    images = { vim.json.encode({ ID = 'img111', Repository = 'nginx', Tag = 'latest', Size = '142MB' }) },
    volumes = { vim.json.encode({ Name = 'vol1', Driver = 'local' }) },
    networks = { vim.json.encode({ ID = 'net1', Name = 'bridge', Driver = 'bridge' }) },
  })
end

--- パネルを構成する4つのfloatの位置とサイズ（=見た目そのもの）を取り出す。
--- 左ペインのタイトルはパネルごとに違う（Files / Project）ので比較対象に含めない
local function geometry(left_win, right_win, cmdlog_win)
  local function g(w)
    local c = vim.api.nvim_win_get_config(w)
    return { row = c.row, col = c.col, width = c.width, height = c.height, border = c.border and c.border[1] }
  end
  -- タブバーは「4つのfloatのうち左/右/コマンドログ以外」で特定する（タイトルを持たないため）
  local tabbar
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= ''
      and w ~= left_win and w ~= right_win and w ~= cmdlog_win then
      tabbar = w
    end
  end
  return {
    tabbar = tabbar and g(tabbar) or nil,
    left = g(left_win),
    right = g(right_win),
    cmdlog = g(cmdlog_win),
    left_hl = vim.wo[left_win].winhighlight,
    right_hl = vim.wo[right_win].winhighlight,
    cmdlog_hl = vim.wo[cmdlog_win].winhighlight,
    left_cursorline = vim.wo[left_win].cursorline,
  }
end

T.describe('docker_panel shares the git panel UI', function()
  T.it('has exactly the same window layout (tabbar / left / right / command log) as the git panel', function()
    local dir = T.tmp_git_repo()
    GP.open(dir, false)
    local git_geo = geometry(GP.left_win(), GP.right_win(), GP.win_by_title('Command Log'))
    GP.close()
    -- gitパネルはリポジトリへchdirするため、削除する前にカレントを戻しておく
    vim.fn.chdir(vim.fn.tempname():match('^(.*)/[^/]+$') or '/')
    T.rmrf(dir)

    local st = fake()
    D.open()
    local docker_geo = geometry(D.left_win(), D.right_win(), D.win_by_title('Command Log'))
    D.cleanup(st)

    T.eq(docker_geo, git_geo, 'gitパネルとdockerパネルのレイアウト/配色設定は完全に一致する')
  end)

  T.it('renders the tab bar in the same format and with the same highlight groups', function()
    local st = fake()
    D.open()
    vim.wait(500)
    -- タブバーはタイトルを持たない1行のfloat。行の内容と色付けを見る
    local tabbar_buf
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local c = vim.api.nvim_win_get_config(w)
      if c.relative ~= '' and c.height == 1 and (not c.title) then
        tabbar_buf = vim.api.nvim_win_get_buf(w)
      end
    end
    T.ok(tabbar_buf ~= nil, 'タブバーのウィンドウが見つかる')
    local line = vim.api.nvim_buf_get_lines(tabbar_buf, 0, 1, false)[1]
    T.eq(line, ' [1] Project  [2] Containers  [3] Images  [4] Volumes  [5] Networks ')

    local ns = vim.api.nvim_create_namespace('docker_panel_hl')
    local marks = vim.api.nvim_buf_get_extmarks(tabbar_buf, ns, 0, -1, { details = true })
    local groups = {}
    for _, m in ipairs(marks) do groups[m[4].hl_group] = true end
    T.ok(groups['GitPanelTabActive'], '選択中タブは gitパネルと同じ GitPanelTabActive')
    T.ok(groups['GitPanelTabInactive'], '非選択タブは gitパネルと同じ GitPanelTabInactive')
    D.cleanup(st)
  end)

  T.it('1-5 and the arrow keys switch panels, updating the left pane title', function()
    local st = fake()
    D.open()
    vim.wait(500)
    T.contains(T.win_title_text(D.left_win()), 'Project')
    D.press('3')
    vim.wait(400)
    T.contains(T.win_title_text(D.left_win()), 'Images')
    D.press('<Right>')
    vim.wait(400)
    T.contains(T.win_title_text(D.left_win()), 'Volumes')
    D.press('<Left>')
    vim.wait(400)
    T.contains(T.win_title_text(D.left_win()), 'Images')
    D.cleanup(st)
  end)

  T.it('@ expands the command log and shows the docker commands that were run (read-only ones are not logged)', function()
    local st = fake()
    D.open()
    D.press('2')
    vim.wait(500)
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.press('r') -- restart（状態を変えるのでログに残る）
    vim.wait(600)

    local cmdlog_win = D.win_by_title('Command Log')
    local before = vim.api.nvim_win_get_config(cmdlog_win).height
    D.press('@')
    vim.wait(200)
    local after = vim.api.nvim_win_get_config(cmdlog_win).height
    T.ok(after > before, '@ でコマンドログが拡大する')
    local text = table.concat(D.lines(cmdlog_win), '\n')
    T.contains(text, 'docker restart aaa111')
    T.ok(not text:find('docker ps', 1, true), '一覧取得(ps)のような読み取り専用コマンドはログに出さない')

    D.press_modal('@') -- 拡大中はコマンドログ側にフォーカスがある
    vim.wait(200)
    T.eq(vim.api.nvim_win_get_config(cmdlog_win).height, before, '@ で元の大きさに戻る')
    D.cleanup(st)
  end)

  T.it('+ expands the right pane over the whole panel area and collapses back', function()
    local st = fake()
    D.open()
    D.press('2')
    vim.wait(500)
    local right = D.right_win()
    local before = vim.api.nvim_win_get_config(right)
    D.press('+')
    vim.wait(200)
    local after = vim.api.nvim_win_get_config(right)
    T.ok(after.width > before.width and after.height > before.height, '+ で右ペインが拡大する')

    D.press_modal('+') -- 拡大中は右ペインにフォーカスが移っている
    vim.wait(200)
    local collapsed = vim.api.nvim_win_get_config(right)
    T.eq({ collapsed.width, collapsed.height }, { before.width, before.height }, '+ で元の大きさに戻る')
    D.cleanup(st)
  end)

  -- 右ペインのタブは <LeftMouse> のハンドラが画面座標から当たり判定するため、
  -- ここでは「パネルの各バッファにクリックハンドラが割り当たっていること」だけを見る。
  -- 実際にクリックして切り替わるかは、実UIを張って画面から座標を読む
  -- docker_panel_click_spec.lua が担当する（座標計算のズレはそちらでしか検出できない）
  T.it('every panel buffer has the click handler bound', function()
    local st = fake()
    D.open()
    D.press('2')
    vim.wait(600)
    for _, win in ipairs({ D.left_win(), D.right_win(), D.win_by_title('Command Log') }) do
      local found = false
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(win), 'n')) do
        if map.lhs == '<LeftMouse>' then found = true end
      end
      T.ok(found, 'パネルのバッファに <LeftMouse> が割り当たっている')
    end
    D.cleanup(st)
  end)

  T.it('q closes the panel', function()
    local st = fake()
    D.open()
    vim.wait(400)
    T.ok(D.left_win() ~= nil, 'パネルが開いている')
    D.press('q')
    vim.wait(300)
    T.eq(D.left_win(), nil, 'q でパネルが閉じる')
    D.cleanup(st)
  end)
end)

T.summary()
