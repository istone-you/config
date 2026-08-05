-- docker_panel系specの共通ヘルパー。git_panel_helpers.luaと同じ方針で、実際に
-- docker_panel.open()でUIを開き、実キー入力で操作して結果を確認する。
--
-- docker本体には依存できない（CIや開発機にdockerが無いこともある）ため、
-- PATH上のdockerではなく「偽docker」シェルスクリプトを作って docker.bin に差し替える。
-- 偽dockerは呼ばれたコマンドをログファイルへ追記し、stop/rm等では手元のJSON状態ファイルを
-- 書き換えるので、「操作 → 一覧が変わる」まで含めて本物と同じ経路で検証できる。

local M = {}

--- 偽dockerを作り、docker.bin を差し替える。戻り値は state（dir/log/bin を持つ）
--- opts.containers / images / volumes / networks は `{{json .}}` 相当のJSON文字列配列
function M.fake_docker(opts)
  opts = opts or {}
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')

  local function write(name, lines)
    vim.fn.writefile(lines or {}, dir .. '/' .. name)
  end
  write('containers.json', opts.containers)
  write('images.json', opts.images)
  write('volumes.json', opts.volumes)
  write('networks.json', opts.networks)
  -- `docker inspect --format '{{.Image}}' <コンテナID...>` の応答（"コンテナID イメージID" の行）
  local container_images = {}
  for id, image in pairs(opts.container_images or {}) do
    table.insert(container_images, id .. ' ' .. image)
  end
  write('container_images.txt', container_images)
  -- `docker volume ls --filter dangling=true` の応答
  write('unused_volumes.txt', opts.unused_volumes)
  -- `docker system df -v` の応答（ボリュームのサイズ表示に使う）
  write('df_verbose.txt', opts.df_verbose or {
    'Images space usage:',
    '',
    'REPOSITORY   TAG      IMAGE ID   CREATED    SIZE',
    '',
    'Local Volumes space usage:',
    '',
    'VOLUME NAME   LINKS     SIZE',
    'shop_pgdata   1         1.2GB',
    'old_cache     0         30MB',
    '',
    'Build cache usage: 0B',
  })
  write('calls.log', {})

  local bin = dir .. '/docker'
  vim.fn.writefile({
    '#!/bin/sh',
    'STATE="' .. dir .. '"',
    'printf "%s\\n" "$*" >> "$STATE/calls.log"',
    'case "$1" in',
    -- 起動チェックは {{.Server.Version}} だけ、Projectパネルの Info タブは Client/Server/... を
    -- 並べたテンプレートを渡してくるので、フォーマット文字列で出し分ける
    '  version)',
    '    case "$3" in',
    '      *Client*) printf "Client   27.1.1\\nServer   27.1.1\\nAPI      1.53\\nOS/Arch  linux/arm64\\nContext  orbstack\\n";;',
    '      *) echo "27.1.1";;',
    '    esac; exit 0;;',
    -- `ps -a --format {{.ID}}`（使用中イメージの判定用）とJSON一覧を出し分ける
    '  ps)',
    '    case "$*" in',
    '      *"{{.ID}}"*) sed -n \'s/.*"ID":"\\([^"]*\\)".*/\\1/p\' "$STATE/containers.json";;',
    '      *) cat "$STATE/containers.json";;',
    '    esac; exit 0;;',
    '  images) cat "$STATE/images.json"; exit 0;;',
    '  logs) echo "log line for $4"; exit 0;;',
    '  top) printf "UID PID CMD\\nroot 1 nginx\\n"; exit 0;;',
    -- `inspect --format {{.Image}} <id...>`（コンテナ→イメージIDの解決）と通常のinspectを出し分ける
    '  inspect)',
    '    if [ "$2" = "--format" ]; then',
    '      shift 3',
    '      for id in "$@"; do awk -v i="$id" \'$1 == i { print $2 }\' "$STATE/container_images.txt"; done',
    '      exit 0',
    '    fi',
    '    printf "[\\n  {\\n    \\"Id\\": \\"%s\\"\\n  }\\n]\\n" "$2"; exit 0;;',
    '  history) echo "2 days ago  10MB  RUN apk add"; exit 0;;',
    '  stats) echo "{\\"Name\\":\\"$5\\",\\"CPUPerc\\":\\"1.50%\\",\\"MemUsage\\":\\"20MiB / 2GiB\\",\\"MemPerc\\":\\"1.00%\\",\\"NetIO\\":\\"1kB / 2kB\\",\\"BlockIO\\":\\"0B / 0B\\",\\"PIDs\\":\\"3\\"}"; exit 0;;',
    '  start) sed -i.bak "/$2/ s/\\"State\\":\\"exited\\"/\\"State\\":\\"running\\"/; /$2/ s/Exited ([0-9]*) [a-z0-9 ]*/Up 1 second/" "$STATE/containers.json"; exit 0;;',
    '  stop|kill) sed -i.bak "/$2/ s/\\"State\\":\\"running\\"/\\"State\\":\\"exited\\"/; /$2/ s/Up [a-z0-9 ]*/Exited (0) 1 second ago/" "$STATE/containers.json"; exit 0;;',
    '  restart) exit 0;;',
    '  pause) sed -i.bak "/$2/ s/\\"State\\":\\"running\\"/\\"State\\":\\"paused\\"/" "$STATE/containers.json"; exit 0;;',
    '  unpause) sed -i.bak "/$2/ s/\\"State\\":\\"paused\\"/\\"State\\":\\"running\\"/" "$STATE/containers.json"; exit 0;;',
    '  rm) id="$2"; while [ "${id#-}" != "$id" ]; do shift; id="$2"; done; sed -i.bak "/$id/d" "$STATE/containers.json"; exit 0;;',
    '  rmi) id="$2"; while [ "${id#-}" != "$id" ]; do shift; id="$2"; done; sed -i.bak "/$id/d" "$STATE/images.json"; exit 0;;',
    '  volume)',
    '    case "$2" in',
    '      ls) case "$*" in',
    '            *dangling=true*) cat "$STATE/unused_volumes.txt";;',
    '            *) cat "$STATE/volumes.json";;',
    '          esac;;',
    '      inspect) printf "[\\n  {\\n    \\"Name\\": \\"%s\\"\\n  }\\n]\\n" "$3";;',
    '      rm) name="$3"; while [ "${name#-}" != "$name" ]; do shift; name="$3"; done; sed -i.bak "/$name/d" "$STATE/volumes.json";;',
    '      prune) echo "Total reclaimed space: 0B";;',
    '    esac; exit 0;;',
    '  network)',
    '    case "$2" in',
    '      ls) cat "$STATE/networks.json";;',
    '      inspect) printf "[\\n  {\\n    \\"Name\\": \\"%s\\"\\n  }\\n]\\n" "$3";;',
    '      rm) sed -i.bak "/$3/d" "$STATE/networks.json";;',
    '      prune) echo "Total reclaimed space: 0B";;',
    '    esac; exit 0;;',
    '  system)',
    '    case "$2" in',
    '      df) case "$*" in',
    '            *-v*) cat "$STATE/df_verbose.txt";;',
    '            *) printf "TYPE  TOTAL  ACTIVE  SIZE\\nImages  1  1  10MB\\n";;',
    '          esac;;',
    '      prune) echo "Total reclaimed space: 0B";;',
    '    esac; exit 0;;',
    '  image)',
    '    case "$2" in',
    '      inspect) printf "[\\n  {\\n    \\"Id\\": \\"%s\\"\\n  }\\n]\\n" "$3";;',
    '      prune) echo "Total reclaimed space: 0B";;',
    '    esac; exit 0;;',
    '  container|builder) echo "Total reclaimed space: 0B"; exit 0;;',
    'esac',
    'exit 0',
  }, bin)
  vim.fn.system({ 'chmod', '+x', bin })

  local docker = require('config.docker_panel.docker')
  docker.bin = bin
  docker.command_log = {}

  return { dir = dir, bin = bin, log = dir .. '/calls.log' }
end

--- 偽dockerが呼ばれたコマンド一覧（引数を空白でつないだ文字列の配列）
function M.calls(state)
  if vim.fn.filereadable(state.log) == 0 then return {} end
  return vim.fn.readfile(state.log)
end

function M.called(state, needle)
  for _, line in ipairs(M.calls(state)) do
    if line:find(needle, 1, true) then return true end
  end
  return false
end

function M.cleanup(state)
  require('config.docker_panel').close()
  vim.wait(200)
  vim.fn.delete(state.dir, 'rf')
  require('config.docker_panel.docker').bin = 'docker'
end

function M.open()
  local dp = require('config.docker_panel')
  pcall(dp.close)
  dp.open(false)
  vim.wait(600)
  return dp
end

function M.win_by_title(title_part)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative ~= '' and cfg.title then
      local text = {}
      for _, chunk in ipairs(cfg.title) do table.insert(text, chunk[1]) end
      if table.concat(text):find(title_part, 1, true) then return w end
    end
  end
  return nil
end

function M.left_win()
  for _, title in ipairs({ 'Project', 'Containers', 'Images', 'Volumes', 'Networks' }) do
    local w = M.win_by_title(title)
    if w then return w end
  end
  return nil
end

function M.right_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local ok, v = pcall(vim.api.nvim_win_get_var, w, 'dockerpanel_right')
    if ok and v then return w end
  end
  return nil
end

function M.lines(win)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

function M.find_row(win, substring)
  for i, l in ipairs(M.lines(win)) do
    if l:find(substring, 1, true) then return i end
  end
  return nil
end

function M.goto_row(win, row)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = vim.api.nvim_win_get_buf(win) })
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

--- 左パネルにフォーカスしてキーを送る（`normal!`ではなくマッピング有効の経路）
function M.press(keys)
  local win = M.left_win()
  vim.api.nvim_set_current_win(win)
  feed(keys)
end

--- モーダル(confirm/menu)はopen_win(...,true,...)で即フォーカスされるので、
--- 現在のカレントウィンドウがそのまま対象になる
function M.press_modal(keys)
  feed(keys)
end

--- 右ペインのサブタブのうち「選択中」のもの（GitPanelTabActiveが付いたチャンク）。
--- タイトル文字列には全タブ名が並ぶので、どれが選択されているかはハイライトで判定する
function M.right_active_tab()
  local w = M.right_win()
  if not w then return nil end
  local title = vim.api.nvim_win_get_config(w).title
  for _, chunk in ipairs(title or {}) do
    if chunk[2] == 'GitPanelTabActive' then return vim.trim(chunk[1]) end
  end
  return nil
end

--- 右ペインのボーダータイトル（サブタブ表示）をプレーン文字列で取り出す
function M.right_title()
  local w = M.right_win()
  if not w then return '' end
  local cfg = vim.api.nvim_win_get_config(w)
  if not cfg.title then return '' end
  local out = {}
  for _, chunk in ipairs(cfg.title) do table.insert(out, chunk[1]) end
  return table.concat(out)
end

--- テスト用のコンテナJSON（docker ps --format '{{json .}}' 相当の1行）
function M.container_json(t)
  return vim.json.encode({
    ID = t.id, Names = t.name, Image = t.image or 'nginx:latest',
    Status = t.status or 'Up 3 minutes', State = t.state or 'running',
    Ports = t.ports or '', CreatedAt = t.created or '2026-08-01 10:00:00 +0900 JST',
    Labels = t.labels or '',
  })
end

return M
