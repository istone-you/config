local T = dofile(TESTS_DIR .. '/helpers.lua')
local D = dofile(TESTS_DIR .. '/docker_panel_helpers.lua')

--- 標準的な状態（compose配下の実行中1 + compose外の停止1、使用中/未使用/danglingのイメージ、
--- 使用中/未使用のボリューム、組み込み/ユーザー定義のネットワーク）
local function fake()
  return D.fake_docker({
    containers = {
      D.container_json({ id = 'bbb222', name = 'db', image = 'postgres:16',
        status = 'Exited (0) 2 days ago', state = 'exited' }),
      D.container_json({ id = 'aaa111', name = 'web', image = 'nginx:latest',
        status = 'Up 3 minutes', state = 'running',
        labels = 'com.docker.compose.project=shop,com.docker.compose.service=web' }),
    },
    container_images = { aaa111 = 'sha256:img111', bbb222 = 'sha256:img999' },
    images = {
      vim.json.encode({ ID = 'sha256:img111', Repository = 'nginx', Tag = 'latest', Size = '142MB', CreatedSince = '2 days ago' }),
      vim.json.encode({ ID = 'sha256:img222', Repository = '<none>', Tag = '<none>', Size = '10MB', CreatedSince = '3 days ago' }),
      vim.json.encode({ ID = 'sha256:img333', Repository = 'redis', Tag = '7', Size = '120MB', CreatedSince = '5 days ago' }),
    },
    volumes = {
      vim.json.encode({ Name = 'shop_pgdata', Driver = 'local', Mountpoint = '/var/lib/docker/volumes/shop_pgdata/_data' }),
      vim.json.encode({ Name = 'old_cache', Driver = 'local', Mountpoint = '/var/lib/docker/volumes/old_cache/_data' }),
    },
    unused_volumes = { 'old_cache' },
    networks = {
      vim.json.encode({ ID = 'net111', Name = 'bridge', Driver = 'bridge', Scope = 'local' }),
      vim.json.encode({ ID = 'net222', Name = 'shop_default', Driver = 'bridge', Scope = 'local' }),
    },
  })
end

T.describe('docker_panel Containers panel', function()
  T.it('lists containers with running ones first and shows the running/total count in the header', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web', 'db', '(1/2 実行中)' })
    local left = D.left_win()
    local lines = D.lines(left)
    T.contains(lines[1], '(1/2 実行中)')
    local web_row = D.find_row(left, 'web')
    local db_row = D.find_row(left, 'db')
    T.ok(web_row and db_row, 'both containers should be listed')
    T.contains(lines[web_row], '●')
    T.contains(lines[web_row], 'Up 3 minutes')
    D.cleanup(st)
  end)

  T.it('groups containers by their compose project, showing the service name inside a group', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ '▼ shop', '▼ その他', 'web' })
    local left = D.left_win()
    local shop_row = D.find_row(left, '▼ shop')
    local other_row = D.find_row(left, '▼ その他')
    T.ok(shop_row ~= nil, 'composeプロジェクトの見出しが出る')
    T.contains(D.lines(left)[shop_row], '(1/1)')
    T.ok(other_row ~= nil, 'compose以外は「その他」にまとまる')
    T.ok(shop_row < other_row, 'プロジェクトが先、その他が後')
    -- 見出し行は選択対象ではなく、その下のコンテナ行にカーソルが落ちる
    D.goto_row(left, shop_row)
    D.until_ok(function() return vim.api.nvim_win_get_cursor(left)[1] ~= shop_row end)
    local cursor = vim.api.nvim_win_get_cursor(left)[1]
    T.ok(cursor ~= shop_row, '見出し行にはカーソルが止まらない')
    T.contains(D.lines(left)[cursor], 'web')
    D.cleanup(st)
  end)

  T.it('shows container logs in the right pane by default, and [ / ] switch the right-pane tabs', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.wait_right_text('log line for aaa111')
    T.eq(D.right_active_tab(), 'Logs')
    T.contains(table.concat(D.lines(D.right_win()), '\n'), 'log line for aaa111')

    D.press(']') -- Logs -> Stats
    D.wait_tab('Stats')
    D.wait_right_text('1.50%')
    T.eq(D.right_active_tab(), 'Stats')
    T.contains(table.concat(D.lines(D.right_win()), '\n'), '1.50%')

    D.press('[') -- Stats -> Logs へ戻る
    D.wait_tab('Logs')
    T.eq(D.right_active_tab(), 'Logs')
    D.cleanup(st)
  end)

  T.it('Config tab shows docker inspect output, Top tab shows the process list', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.wait_tab('Logs')
    D.press(']]') -- Logs -> Stats -> Config
    D.wait_tab('Config')
    D.wait_call(st, 'inspect aaa111')
    T.eq(D.right_active_tab(), 'Config')
    T.ok(D.called(st, 'inspect aaa111'), 'docker inspect が呼ばれる')

    D.press(']') -- -> Top
    D.wait_tab('Top')
    D.wait_right_text('nginx')
    T.eq(D.right_active_tab(), 'Top')
    T.contains(table.concat(D.lines(D.right_win()), '\n'), 'nginx')
    D.cleanup(st)
  end)

  T.it('<Space> stops a running container and starts a stopped one', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.press('<Space>')
    -- 呼ばれただけでなく、一覧が停止状態に更新されるまで待つ
    D.until_ok(function()
      local w = D.left_win()
      local row = w and D.find_row(w, 'web')
      return row ~= nil and D.lines(w)[row]:find('Exited', 1, true) ~= nil
    end)
    T.ok(D.called(st, 'stop aaa111'), 'docker stop が呼ばれる')
    local web_row = D.find_row(D.left_win(), 'web')
    T.contains(D.lines(D.left_win())[web_row], 'Exited')

    D.goto_row(D.left_win(), web_row)
    D.press('<Space>')
    D.wait_call(st, 'start aaa111')
    T.ok(D.called(st, 'start aaa111'), '停止中のコンテナには docker start が走る')
    D.cleanup(st)
  end)

  T.it('s stops after confirmation, r restarts, p pauses', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))

    D.press('s')
    D.wait_modal()
    D.press_modal('n') -- 拒否したら何もしない
    D.wait_no_modal()  -- モーダルが閉じきってから「呼ばれていない」ことを見る
    T.ok(not D.called(st, 'stop aaa111'), '確認を拒否したら停止しない')

    D.press('r')
    D.wait_call(st, 'restart aaa111')
    T.ok(D.called(st, 'restart aaa111'), 'r で再起動')

    -- 再起動後は一覧が引き直されてウィンドウごと作り直るので、戻ってくるまで待つ
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.press('p')
    D.wait_call(st, 'pause aaa111')
    T.ok(D.called(st, 'pause aaa111'), 'p で一時停止')
    D.cleanup(st)
  end)

  T.it('d opens the remove menu and removing drops the container from the list', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'db' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'db'))
    D.press('d')
    D.wait_modal()
    D.press_modal('d') -- 通常削除
    D.wait_call(st, 'rm bbb222')
    D.wait_no_row('db')
    T.ok(D.called(st, 'rm bbb222'), 'docker rm が呼ばれる')
    T.eq(D.find_row(D.left_win(), 'db'), nil, '削除したコンテナは一覧から消える')
    D.cleanup(st)
  end)

  T.it('E closes the panel and opens a shell inside the container in a terminal window', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.press('E')
    D.until_ok(function()
      return D.left_win() == nil
        and vim.bo[vim.api.nvim_get_current_buf()].buftype == 'terminal'
    end)
    -- ターミナルは即開くが、その中で走る偽dockerがログに書くのは少し後
    D.wait_call(st, 'exec -it aaa111')
    T.eq(D.left_win(), nil, 'パネルは閉じる')
    T.ok(D.called(st, 'exec -it aaa111'), 'docker exec が呼ばれる')
    T.eq(vim.bo[vim.api.nvim_get_current_buf()].buftype, 'terminal', 'ターミナルウィンドウが開く')
    vim.cmd('bwipeout!')
    D.cleanup(st)
  end)

  T.it('K kills a container only after confirmation', function()
    local st = fake()
    D.open()
    D.press('2')
    D.wait_rows({ 'web' })
    D.goto_row(D.left_win(), D.find_row(D.left_win(), 'web'))
    D.press('K')
    D.wait_modal()
    D.press_modal('y')
    D.wait_call(st, 'kill aaa111')
    T.ok(D.called(st, 'kill aaa111'), 'docker kill が呼ばれる')
    D.cleanup(st)
  end)
end)

T.describe('docker_panel Images panel', function()
  T.it('lists images and d removes the selected one', function()
    local st = fake()
    D.open()
    D.press('3')
    D.wait_rows({ 'イメージ  (3)', 'nginx', '<none>' })
    local left = D.left_win()
    T.contains(D.lines(left)[1], 'イメージ  (3)')
    local row = D.find_row(left, 'nginx')
    T.ok(row ~= nil, 'イメージが一覧に出る')
    -- lazydockerと同じく repo / tag / size を別カラムで並べる（repo:tag と繋げない）
    T.eq(D.lines(left)[row], '    nginx   latest  142MB')
    T.eq(D.lines(left)[D.find_row(left, '<none>')], '    <none>  <none>  10MB')

    D.goto_row(left, row)
    D.press('d')
    D.wait_modal()
    D.press_modal('d')
    D.wait_call(st, 'rmi sha256:img111')
    D.wait_no_row('nginx')
    T.ok(D.called(st, 'rmi sha256:img111'), 'docker rmi が呼ばれる')
    T.eq(D.find_row(D.left_win(), 'nginx'), nil, '削除したイメージは一覧から消える')
    D.cleanup(st)
  end)

  T.it('splits images into in-use / unused / dangling', function()
    local st = fake()
    D.open()
    D.press('3')
    D.wait_rows({ '▼ 使用中', '▼ 未使用', '▼ dangling', 'nginx', 'redis', '<none>' })
    local left = D.left_win()
    local in_use = D.find_row(left, '▼ 使用中')
    local unused = D.find_row(left, '▼ 未使用')
    local dangling = D.find_row(left, '▼ dangling')
    T.ok(in_use and unused and dangling, '3つの見出しが出る')
    T.contains(D.lines(left)[in_use], '(1)')
    -- コンテナが参照しているイメージ(sha256:img111 = nginx)だけが「使用中」
    T.ok(D.find_row(left, 'nginx') > in_use and D.find_row(left, 'nginx') < unused, 'nginx は使用中')
    T.ok(D.find_row(left, 'redis') > unused and D.find_row(left, 'redis') < dangling, 'redis は未使用')
    T.ok(D.find_row(left, '<none>') > dangling, 'タグ無しは dangling')
    T.ok(D.called(st, 'inspect --format {{.Image}} '), 'コンテナのイメージIDをまとめて1回で解決する')
    D.cleanup(st)
  end)

  T.it('] switches the right pane to the image History tab', function()
    local st = fake()
    D.open()
    D.press('3')
    D.wait_tab('Config')
    T.eq(D.right_active_tab(), 'Config')
    D.press(']')
    D.wait_tab('History')
    D.wait_right_text('RUN apk add')
    T.eq(D.right_active_tab(), 'History')
    T.contains(table.concat(D.lines(D.right_win()), '\n'), 'RUN apk add')
    D.cleanup(st)
  end)
end)

T.describe('docker_panel Volumes / Networks panels', function()
  T.it('volumes: splits in-use / unused and shows the size from docker system df -v', function()
    local st = fake()
    D.open()
    D.press('4')
    -- サイズは docker system df -v の応答が返ってから行に載るので、そこまで待つ
    D.wait_rows({ '▼ 使用中', '▼ 未使用', 'shop_pgdata', 'old_cache', '1.2GB', '30MB' })
    local left = D.left_win()
    local in_use = D.find_row(left, '▼ 使用中')
    local unused = D.find_row(left, '▼ 未使用')
    T.ok(in_use and unused, '使用中 / 未使用の見出しが出る')
    T.ok(D.find_row(left, 'shop_pgdata') > in_use and D.find_row(left, 'shop_pgdata') < unused,
      'コンテナが使っているボリュームは使用中')
    T.ok(D.find_row(left, 'old_cache') > unused, 'どこからも参照されていないボリュームは未使用')
    T.contains(D.lines(left)[D.find_row(left, 'shop_pgdata')], '1.2GB')
    T.contains(D.lines(left)[D.find_row(left, 'old_cache')], '30MB')
    D.cleanup(st)
  end)

  T.it('volumes: the heavy size query runs on open and on R, but never on the 2s auto-refresh', function()
    local st = fake()
    D.open()
    D.press('4')
    D.wait_rows({ 'shop_pgdata', '1.2GB' })
    local function count(needle)
      local n = 0
      for _, line in ipairs(D.calls(st)) do
        if line:find(needle, 1, true) then n = n + 1 end
      end
      return n
    end
    T.eq(count('system df -v'), 1, '開いた時に1回だけ取る')
    local list_calls = count('volume ls --format')
    -- 左パネルにフォーカスを置いたまま自動更新(2秒)を跨ぐ。周期そのものを待つので
    -- ここだけは秒単位かかるが、更新が観測できた時点で抜ける
    vim.api.nvim_set_current_win(D.left_win())
    D.until_ok(function() return count('volume ls --format') > list_calls end, 5000)
    T.ok(count('volume ls --format') > list_calls, '一覧自体は自動更新される')
    T.eq(count('system df -v'), 1, '重いサイズ取得は自動更新では走らせない')

    D.press('R')
    D.until_ok(function() return count('system df -v') == 2 end)
    T.eq(count('system df -v'), 2, 'R を押した時は取り直す')
    D.cleanup(st)
  end)

  T.it('volumes: d removes after confirmation', function()
    local st = fake()
    D.open()
    D.press('4')
    D.wait_rows({ 'shop_pgdata' })
    local left = D.left_win()
    T.ok(D.find_row(left, 'shop_pgdata') ~= nil, 'ボリュームが一覧に出る')
    D.goto_row(left, D.find_row(left, 'shop_pgdata'))
    D.press('d')
    D.wait_modal()
    D.press_modal('y')
    D.wait_call(st, 'volume rm shop_pgdata')
    D.wait_no_row('shop_pgdata')
    T.ok(D.called(st, 'volume rm shop_pgdata'), 'docker volume rm が呼ばれる')
    T.eq(D.find_row(D.left_win(), 'shop_pgdata'), nil, '削除したボリュームは一覧から消える')
    D.cleanup(st)
  end)

  T.it('networks: built-in bridge is refused, a user network is removed', function()
    local st = fake()
    D.open()
    D.press('5')
    D.wait_rows({ 'bridge  ', 'shop_default' })
    local left = D.left_win()
    D.goto_row(left, D.find_row(left, 'bridge  '))
    D.press('d')
    -- 拒否されるので確認モーダルすら出ない。出ないことの確認なので上限まで待つ
    T.ok(not D.wait_modal(300), '組み込みネットワークでは確認を出さない')
    T.ok(not D.called(st, 'network rm bridge'), '組み込みネットワークは削除しない')

    D.goto_row(left, D.find_row(left, 'shop_default'))
    D.press('d')
    D.wait_modal()
    D.press_modal('y')
    D.wait_call(st, 'network rm shop_default')
    T.ok(D.called(st, 'network rm shop_default'), 'ユーザー定義ネットワークは削除できる')
    D.cleanup(st)
  end)
end)

T.describe('docker_panel Project panel', function()
  T.it('summarises the environment and lists compose projects', function()
    local st = fake()
    D.open() -- 開いた直後は Project パネル
    D.wait_rows({ 'コンテナ 1/2 実行中', 'Compose プロジェクト', 'shop' })
    local left = D.left_win()
    local text = table.concat(D.lines(left), '\n')
    T.contains(text, 'コンテナ 1/2 実行中')
    T.contains(text, 'Compose プロジェクト')
    T.contains(text, 'shop')
    D.cleanup(st)
  end)

  T.it('the Info tab shows the docker endpoint and the container state breakdown', function()
    local st = fake()
    D.open()
    D.wait_tab('Info')
    D.wait_right_text('Context  orbstack')
    T.eq(D.right_active_tab(), 'Info')
    local text = table.concat(D.lines(D.right_win()), '\n')
    T.contains(text, 'Context  orbstack')
    T.contains(text, '実行中')
    T.contains(text, '停止中')
    -- 個数の内訳は Disk タブ(system df)と重複させない
    T.ok(not text:find('イメージ', 1, true), 'イメージ数はInfoに出さない（Diskの担当）')
    D.cleanup(st)
  end)

  T.it('the Disk tab shows docker system df (different content from the Info tab)', function()
    local st = fake()
    D.open()
    D.wait_right_text('Context  orbstack')
    local info_text = table.concat(D.lines(D.right_win()), '\n')
    D.press(']')
    D.wait_tab('Disk')
    D.wait_right_text('TYPE')
    T.eq(D.right_active_tab(), 'Disk')
    local disk_text = table.concat(D.lines(D.right_win()), '\n')
    T.contains(disk_text, 'TYPE')
    T.ok(disk_text ~= info_text, 'Info と Disk は別の内容を出す')
    T.ok(D.called(st, 'system df'), 'docker system df が呼ばれる')
    D.cleanup(st)
  end)

  T.it('b prunes after picking an item from the menu and confirming', function()
    local st = fake()
    D.open()
    D.wait_rows({ 'コンテナ 1/2 実行中' })
    D.press('b')
    D.wait_modal()
    local menu_buf = D.current_modal_buf()
    D.press_modal('v') -- 未使用ボリューム
    D.wait_modal(nil, menu_buf) -- メニュー -> 確認 に切り替わるまで
    D.press_modal('y')
    D.wait_call(st, 'volume prune --force')
    T.ok(D.called(st, 'volume prune --force'), 'docker volume prune が呼ばれる')
    D.cleanup(st)
  end)
end)

T.summary()
