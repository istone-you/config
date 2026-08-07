-- 起動中のレビューセッションを外部(AI skill / CLI)から見つけるためのディスカバリ。
--
-- hunk の `session list` に相当する仕組みを、デーモンではなく単純な JSON ファイルで実現する。
-- nvim がセッションを開始すると { repoRoot, port, pid, startedAt } を追記し、終了時に消す。
-- skill 側は cwd(リポジトリ root)からこのファイルを引いて port を得て、localhost:port の
-- HTTP API を叩く。
--
-- 置き場所は nvim の cache 配下(stdpath('cache')/diff-review/sessions.json)。skill にも
-- 同じ解決規則(${XDG_CACHE_HOME:-$HOME/.cache}/nvim/diff-review/sessions.json)を書いておく。

local M = {}

local function uv()
  return vim.uv or vim.loop
end

function M.path()
  return vim.fs.normalize(vim.fn.stdpath('cache') .. '/diff-review/sessions.json')
end

function M.read()
  local path = M.path()
  if vim.fn.filereadable(path) ~= 1 then return {} end
  local ok, content = pcall(function()
    return table.concat(vim.fn.readfile(path), '\n')
  end)
  if not ok or not content or content == '' then return {} end
  local decoded_ok, decoded = pcall(vim.json.decode, content)
  if not decoded_ok or type(decoded) ~= 'table' then return {} end
  -- vim.json.decode は空配列を {} にする。ここでは配列として扱えれば十分。
  return decoded
end

function M.write(list)
  local path = M.path()
  local dir = vim.fn.fnamemodify(path, ':h')
  pcall(function() vim.fn.mkdir(dir, 'p') end)
  -- 空配列でも "[]" を書きたいので array 化を明示する。
  local payload = vim.json.encode(vim.list_extend({}, list))
  pcall(function() vim.fn.writefile({ payload }, path) end)
end

-- 同一マシン上の pid が生きているか(シグナル0)。判定不能なら「生存」に倒して誤削除を避ける。
local function pid_alive(pid)
  if type(pid) ~= 'number' then return true end
  if pid == vim.fn.getpid() then return true end
  local ok, r = pcall(function() return uv().kill(pid, 0) end)
  if not ok then return true end
  return r == 0
end

--- 死んだ pid のエントリを除いた配列を返す。
function M.prune(list)
  local kept = {}
  for _, e in ipairs(list or {}) do
    if type(e) == 'table' and pid_alive(e.pid) then
      kept[#kept + 1] = e
    end
  end
  return kept
end

--- 自分のセッションを登録する。死んだエントリと、同じ repo / port の残骸を掃除してから追記。
function M.register(repo_root, port)
  local list = M.prune(M.read())
  local mine = vim.fn.getpid()
  local kept = {}
  for _, e in ipairs(list) do
    if not (e.repoRoot == repo_root or e.port == port or e.pid == mine) then
      kept[#kept + 1] = e
    end
  end
  local entry = {
    repoRoot = repo_root,
    port = port,
    pid = mine,
    startedAt = os.time(),
  }
  kept[#kept + 1] = entry
  M.write(kept)
  return entry
end

--- 自分の(このポートの)エントリを取り除く。
function M.unregister(port)
  local mine = vim.fn.getpid()
  local list = M.prune(M.read())
  local kept = {}
  for _, e in ipairs(list) do
    if not (e.pid == mine and e.port == port) then
      kept[#kept + 1] = e
    end
  end
  M.write(kept)
end

M._private = {
  pid_alive = pid_alive,
}

return M
