-- 非同期docker操作レイヤー（vim.system + on_exitコールバック、UIをブロックしない）。
-- git_panel/git.lua と同じ作りにしてあり、コマンドの選択は lazydocker
-- (pkg/commands/docker.go, container.go, image.go...) を参照して合わせている。
--
-- 一覧系は `--format '{{json .}}'` で1行1JSONを受け取り、vim.json.decodeでテーブルにする
-- （lazydocker は Docker API を直接叩くが、ここは追加依存を増やさないため docker CLI のみ）。

local M = {}

--- テストや特殊環境から差し替えられるようにフィールドで持つ（既定は PATH 上の docker）
M.bin = 'docker'

M.command_log = {}
local MAX_LOG = 200
--- パネル側がrender_cmdlog相当を差し込むためのフック（コマンドログに変化があるたびに呼ぶ）
M.on_log_update = function() end

--- lazydocker(command_log)と同じく、古い→新しいの順で末尾に追記する
--- （表示側でビューを一番下へスクロールすることで最新行を見せる）
local function push_log(text)
  table.insert(M.command_log, text)
  if #M.command_log > MAX_LOG then
    table.remove(M.command_log, 1)
  end
  vim.schedule(M.on_log_update)
end

--- git.lua と同じ方針: 状態を変えないコマンド(ps/images/logs/inspect等)はコマンドログに
--- 出さない。状態を変えるコマンド(start/stop/rm/prune等)は出す。opts.dont_log=trueで前者を指定する
function M.run(args, cb, opts)
  local cmd = vim.list_extend({ M.bin }, args)
  if not (opts and opts.dont_log) then
    push_log('docker ' .. table.concat(args, ' '))
  end
  -- dockerコマンドはカレントディレクトリに依存しない（gitと違いリポジトリの概念が無い）ので
  -- cwdは渡さない。渡すと、削除済みディレクトリにいる時にENOENTで起動自体が失敗してしまう
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      if cb then cb(res) end
    end)
  end)
end

--- 読み取り専用コマンドの糖衣（stdoutをそのまま返す。失敗時は空文字）
local function read(args, cb)
  M.run(args, function(res)
    cb(res.code == 0 and (res.stdout or '') or '', res)
  end, { dont_log = true })
end
M.read = read

--- `--format '{{json .}}'` の出力（1行1JSON）をテーブル配列にする
local function parse_json_lines(text)
  local out = {}
  for _, line in ipairs(vim.split(text or '', '\n', { plain = true })) do
    line = vim.trim(line)
    if line ~= '' then
      local ok, obj = pcall(vim.json.decode, line)
      if ok and type(obj) == 'table' then table.insert(out, obj) end
    end
  end
  return out
end
M.parse_json_lines = parse_json_lines

-- ══════════════════════════════════════════════
-- 前提チェック
-- ══════════════════════════════════════════════

--- dockerコマンドの有無とデーモンへの接続可否をまとめて確認する。
--- cb(ok, message) … okがfalseならmessageに理由（CLIが無い/デーモンが起動していない）
function M.check(cb)
  if vim.fn.executable(M.bin) ~= 1 then
    cb(false, 'docker コマンドが見つかりません')
    return
  end
  M.run({ 'version', '--format', '{{.Server.Version}}' }, function(res)
    if res.code ~= 0 then
      cb(false, 'docker デーモンに接続できません（起動していますか？）')
      return
    end
    cb(true, vim.trim(res.stdout or ''))
  end, { dont_log = true })
end

-- ══════════════════════════════════════════════
-- 一覧取得
-- ══════════════════════════════════════════════

--- Statusの文字列から状態を推定する。docker 23未満の `{{json .}}` には .State が
--- 含まれないため、"Up 3 minutes" / "Exited (0) 2 days ago" / "Paused" から補う
local function state_from_status(status)
  status = status or ''
  if status:find('^Up') then
    if status:find('Paused') then return 'paused' end
    return 'running'
  end
  if status:find('^Exited') then return 'exited' end
  if status:find('^Created') then return 'created' end
  if status:find('^Restarting') then return 'restarting' end
  if status:find('^Dead') then return 'dead' end
  return (status ~= '' and status:lower():match('^(%a+)')) or 'unknown'
end
M.state_from_status = state_from_status

--- コンテナ一覧（停止中も含む＝lazydockerのContainersパネルと同じ）
function M.containers(cb)
  read({ 'ps', '-a', '--no-trunc', '--format', '{{json .}}' }, function(text)
    local list = {}
    for _, c in ipairs(parse_json_lines(text)) do
      local state = c.State
      if not state or state == '' then state = state_from_status(c.Status) end
      table.insert(list, {
        id = c.ID or '',
        name = (c.Names or ''):match('^[^,]+') or '',
        image = c.Image or '',
        status = c.Status or '',
        state = state,
        ports = c.Ports or '',
        created = c.CreatedAt or c.RunningFor or '',
        -- docker compose のプロジェクト名（compose以外は空）。lazydockerのProjectパネル相当の
        -- グルーピングに使う
        project = (c.Labels or ''):match('com%.docker%.compose%.project=([^,]+)') or '',
        service = (c.Labels or ''):match('com%.docker%.compose%.service=([^,]+)') or '',
      })
    end
    -- 実行中を上に、その中は名前順（lazydockerも実行中を優先して見せる）
    table.sort(list, function(a, b)
      local ar, br = a.state == 'running', b.state == 'running'
      if ar ~= br then return ar end
      return a.name:lower() < b.name:lower()
    end)
    cb(list)
  end)
end

--- --no-trunc で ID を `sha256:...` のフル表記にする。コンテナ側が参照している
--- イメージID(used_image_ids)と突き合わせて「使用中/未使用」を出すため、切り詰めない方が確実
function M.images(cb)
  read({ 'images', '--no-trunc', '--format', '{{json .}}' }, function(text)
    local list = {}
    for _, i in ipairs(parse_json_lines(text)) do
      table.insert(list, {
        id = i.ID or '',
        repository = i.Repository or '<none>',
        tag = i.Tag or '<none>',
        size = i.Size or '',
        created = i.CreatedSince or '',
      })
    end
    table.sort(list, function(a, b)
      if a.repository ~= b.repository then return a.repository:lower() < b.repository:lower() end
      return (a.tag or '') < (b.tag or '')
    end)
    cb(list)
  end)
end

function M.volumes(cb)
  read({ 'volume', 'ls', '--format', '{{json .}}' }, function(text)
    local list = {}
    for _, v in ipairs(parse_json_lines(text)) do
      table.insert(list, {
        name = v.Name or '',
        driver = v.Driver or '',
        mountpoint = v.Mountpoint or '',
      })
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    cb(list)
  end)
end

function M.networks(cb)
  read({ 'network', 'ls', '--format', '{{json .}}' }, function(text)
    local list = {}
    for _, n in ipairs(parse_json_lines(text)) do
      table.insert(list, {
        id = n.ID or '',
        name = n.Name or '',
        driver = n.Driver or '',
        scope = n.Scope or '',
      })
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    cb(list)
  end)
end

--- `docker stats --no-stream` の1回分。全コンテナ分をまとめて取り、名前で引けるようにする
function M.stats(cb)
  read({ 'stats', '--no-stream', '--format', '{{json .}}' }, function(text)
    local by_name = {}
    for _, s in ipairs(parse_json_lines(text)) do
      by_name[s.Name or ''] = {
        name = s.Name or '',
        cpu = s.CPUPerc or '',
        mem = s.MemUsage or '',
        mem_perc = s.MemPerc or '',
        net = s.NetIO or '',
        block = s.BlockIO or '',
        pids = s.PIDs or '',
      }
    end
    cb(by_name)
  end)
end

--- 全コンテナ（停止中も含む）が参照しているイメージIDの集合。
--- docker には「未使用イメージだけ出すフィルタ」が無いので、`docker image prune --all` と
--- 同じ定義（どのコンテナからも参照されていない＝未使用）を自前で求める。
--- コンテナ一覧の .Image はタグ名だったりIDだったりして突き合わせが不正確なので、
--- 全コンテナIDをまとめて1回の `docker inspect --format '{{.Image}}'` に渡してImageIDを取る
function M.used_image_ids(cb)
  read({ 'ps', '-a', '--no-trunc', '--format', '{{.ID}}' }, function(text)
    local ids = {}
    for _, line in ipairs(vim.split(vim.trim(text), '\n', { plain = true })) do
      line = vim.trim(line)
      if line ~= '' then table.insert(ids, line) end
    end
    if #ids == 0 then cb({}) return end
    local args = { 'inspect', '--format', '{{.Image}}' }
    vim.list_extend(args, ids)
    read(args, function(out)
      local set = {}
      for _, line in ipairs(vim.split(vim.trim(out), '\n', { plain = true })) do
        line = vim.trim(line)
        if line ~= '' then set[line] = true end
      end
      cb(set)
    end)
  end)
end

--- どのコンテナからも参照されていないボリューム名の集合（`docker volume prune` の対象）。
--- dangling=true フィルタはdocker側が判定してくれるので軽い
function M.unused_volumes(cb)
  read({ 'volume', 'ls', '--filter', 'dangling=true', '--format', '{{.Name}}' }, function(text)
    local set = {}
    for _, line in ipairs(vim.split(vim.trim(text), '\n', { plain = true })) do
      line = vim.trim(line)
      if line ~= '' then set[line] = true end
    end
    cb(set)
  end)
end

--- ボリューム名→サイズ表記("1.2GB"等)。`docker system df -v` の
--- "Local Volumes space usage:" セクションを読む。
--- 注意: これは全ボリュームの実サイズを計測するため重い（データ量次第で数秒かかる）。
--- 2秒ごとの自動更新では絶対に呼ばず、パネルを開いた時と R の明示更新時だけ使うこと
function M.volume_sizes(cb)
  read({ 'system', 'df', '-v' }, function(text)
    local sizes = {}
    local in_section = false
    for _, line in ipairs(vim.split(text or '', '\n', { plain = true })) do
      if line:find('Local Volumes space usage', 1, true) then
        in_section = true
      elseif in_section then
        if line:match('^%s*$') then
          if next(sizes) ~= nil then break end -- 空行でセクション終わり
        elseif not line:find('^VOLUME NAME') then
          -- 「名前  リンク数  サイズ」の3列（ボリューム名に空白は使えないので2つ以上の空白で分割できる）
          local name, _, size = line:match('^(%S+)%s%s+(%S+)%s%s+(.+)$')
          if name then sizes[name] = vim.trim(size) end
        end
      end
    end
    cb(sizes)
  end)
end

--- 1コンテナ分だけのstats（全件取得は遅いので、右ペインのStatsタブではこちらを使う）
function M.stats_one(name, cb)
  read({ 'stats', '--no-stream', '--format', '{{json .}}', name }, function(text)
    local list = parse_json_lines(text)
    local s = list[1]
    if not s then cb(nil) return end
    cb({
      name = s.Name or name,
      cpu = s.CPUPerc or '',
      mem = s.MemUsage or '',
      mem_perc = s.MemPerc or '',
      net = s.NetIO or '',
      block = s.BlockIO or '',
      pids = s.PIDs or '',
    })
  end)
end

-- ══════════════════════════════════════════════
-- 詳細表示（右ペイン）
-- ══════════════════════════════════════════════

--- コンテナのログ。lazydocker(container.go Logs)と同じく直近だけを取る。
--- docker logs は標準出力と標準エラーの両方に出すため、両方を結合して返す
function M.logs(id, tail, cb)
  M.run({ 'logs', '--tail', tostring(tail or 300), id }, function(res)
    local out = (res.stdout or '') .. (res.stderr or '')
    cb(out, res)
  end, { dont_log = true })
end

function M.inspect(kind, id, cb)
  local args = { 'inspect', id }
  if kind == 'volume' then args = { 'volume', 'inspect', id }
  elseif kind == 'network' then args = { 'network', 'inspect', id }
  elseif kind == 'image' then args = { 'image', 'inspect', id }
  end
  read(args, cb)
end

function M.top(id, cb)
  read({ 'top', id }, cb)
end

function M.image_history(id, cb)
  read({ 'history', '--format', 'table {{.CreatedSince}}\t{{.Size}}\t{{.CreatedBy}}', id }, cb)
end

function M.system_df(cb)
  read({ 'system', 'df' }, cb)
end

--- 接続先dockerの素性（バージョン・APIバージョン・どのcontextに繋がっているか）。
--- 「何がどれだけあるか」は Disk タブの `docker system df` が受け持つので、ここでは扱わない
function M.info(cb)
  read({ 'version', '--format',
    'Client   {{.Client.Version}}\nServer   {{.Server.Version}}\nAPI      {{.Server.ApiVersion}}\n'
    .. 'OS/Arch  {{.Server.Os}}/{{.Server.Arch}}\nContext  {{.Client.Context}}' }, cb)
end

-- ══════════════════════════════════════════════
-- 操作（コマンドログに残す）
-- ══════════════════════════════════════════════

function M.start(id, cb)         M.run({ 'start', id }, cb) end
function M.stop(id, cb)          M.run({ 'stop', id }, cb) end
function M.restart(id, cb)       M.run({ 'restart', id }, cb) end
function M.pause(id, cb)         M.run({ 'pause', id }, cb) end
function M.unpause(id, cb)       M.run({ 'unpause', id }, cb) end
function M.kill(id, cb)          M.run({ 'kill', id }, cb) end

--- opts.force=true で実行中でも削除、opts.volumes=true で紐づく匿名ボリュームも削除
function M.remove_container(id, opts, cb)
  local args = { 'rm' }
  if opts and opts.force then table.insert(args, '--force') end
  if opts and opts.volumes then table.insert(args, '--volumes') end
  table.insert(args, id)
  M.run(args, cb)
end

function M.remove_image(id, force, cb)
  local args = { 'rmi' }
  if force then table.insert(args, '--force') end
  table.insert(args, id)
  M.run(args, cb)
end

function M.remove_volume(name, force, cb)
  local args = { 'volume', 'rm' }
  if force then table.insert(args, '--force') end
  table.insert(args, name)
  M.run(args, cb)
end

function M.remove_network(name, cb)
  M.run({ 'network', 'rm', name }, cb)
end

--- lazydocker の bulk command (b) 相当の prune 群
function M.prune(kind, cb)
  if kind == 'containers' then M.run({ 'container', 'prune', '--force' }, cb)
  elseif kind == 'images' then M.run({ 'image', 'prune', '--all', '--force' }, cb)
  elseif kind == 'volumes' then M.run({ 'volume', 'prune', '--force' }, cb)
  elseif kind == 'networks' then M.run({ 'network', 'prune', '--force' }, cb)
  elseif kind == 'builder' then M.run({ 'builder', 'prune', '--force' }, cb)
  elseif kind == 'system' then M.run({ 'system', 'prune', '--force' }, cb)
  end
end

return M
