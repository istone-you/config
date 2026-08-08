-- 起動中の nvim が公開しているローカル HTTP サーバを、外部の AI / CLI から見つけるための
-- ディスカバリ。namespace ごとに 1 つの JSON ファイルを持つ。
--
-- もともと diff_review 専用(diff_review/registry.lua)だったものを、nvim_api からも
-- 使えるようにここへ切り出した。併せて「同じリポジトリを 2 つの nvim で開くと片方の登録が
-- 消える」問題を直してある: dedupe は pid と port だけで行い、repoRoot の重複は許す
-- (1 つの repo を複数の nvim で開くのは普通にあるため)。外部からは repoRoot で絞ったうえで
-- startedAt の新しい方を選ぶ、あるいは pid で指定する。
--
-- 置き場所: stdpath('cache')/<namespace>/sessions.json
-- 外部からは ${XDG_CACHE_HOME:-$HOME/.cache}/nvim/<namespace>/sessions.json で引ける。

local M = {}

local function uv()
  return vim.uv or vim.loop
end

-- 同一マシン上の pid が生きているか(シグナル0)。判定不能なら「生存」に倒して誤削除を避ける。
local function pid_alive(pid)
  if type(pid) ~= 'number' then return true end
  if pid == vim.fn.getpid() then return true end
  local ok, r = pcall(function() return uv().kill(pid, 0) end)
  if not ok then return true end
  return r == 0
end

--- namespace 付きのレジストリを作る。
--- 内部は必ず R.path() 経由でファイル位置を引くので、テストから R.path を差し替えられる。
function M.new(namespace)
  local R = {}

  function R.path()
    return vim.fs.normalize(vim.fn.stdpath('cache') .. '/' .. namespace .. '/sessions.json')
  end

  function R.read()
    local path = R.path()
    if vim.fn.filereadable(path) ~= 1 then return {} end
    local ok, content = pcall(function()
      return table.concat(vim.fn.readfile(path), '\n')
    end)
    if not ok or not content or content == '' then return {} end
    local decoded_ok, decoded = pcall(vim.json.decode, content)
    if not decoded_ok or type(decoded) ~= 'table' then return {} end
    return decoded
  end

  function R.write(list)
    local path = R.path()
    local dir = vim.fn.fnamemodify(path, ':h')
    pcall(function() vim.fn.mkdir(dir, 'p') end)
    -- 空配列でも "[]" を書きたいので array 化を明示する。
    local payload = vim.json.encode(vim.list_extend({}, list))
    pcall(function() vim.fn.writefile({ payload }, path) end)
  end

  --- 死んだ pid のエントリを除いた配列を返す。
  function R.prune(list)
    local kept = {}
    for _, e in ipairs(list or {}) do
      if type(e) == 'table' and pid_alive(e.pid) then
        kept[#kept + 1] = e
      end
    end
    return kept
  end

  --- 自分のセッションを登録する。
  --- 落とすのは (a) 死んだ pid (b) 自分の古いエントリ (c) 同じ port の残骸 の 3 つだけ。
  --- 別 nvim が同じ repoRoot を開いていても消さない(多重セッションを許す)。
  --- extra で cwd などの追加フィールドを載せられる。
  ---
  --- 新しいエントリは配列の **先頭** に置く。同じ repo に複数セッションがあるとき、
  --- 外部が素朴に `head -1` で選んでも最新のものに当たるようにするため
  --- (repoRoot で上書きしていた頃の実効挙動を、多重セッションを保ったまま維持する)。
  function R.register(repo_root, port, extra)
    local list = R.prune(R.read())
    local mine = vim.fn.getpid()
    local kept = {}
    for _, e in ipairs(list) do
      if not (e.pid == mine or e.port == port) then
        kept[#kept + 1] = e
      end
    end
    local entry = {
      repoRoot = repo_root,
      port = port,
      pid = mine,
      startedAt = os.time(),
    }
    for k, v in pairs(extra or {}) do entry[k] = v end
    table.insert(kept, 1, entry)
    R.write(kept)
    return entry
  end

  --- 自分の(このポートの)エントリを取り除く。
  function R.unregister(port)
    local mine = vim.fn.getpid()
    local list = R.prune(R.read())
    local kept = {}
    for _, e in ipairs(list) do
      if not (e.pid == mine and e.port == port) then
        kept[#kept + 1] = e
      end
    end
    R.write(kept)
  end

  --- repoRoot で絞り込む(生きているものだけ)。新しく登録されたものが先頭。
  function R.find(repo_root)
    local out = {}
    for _, e in ipairs(R.prune(R.read())) do
      if repo_root == nil or e.repoRoot == repo_root then
        out[#out + 1] = e
      end
    end
    table.sort(out, function(a, b) return (a.startedAt or 0) > (b.startedAt or 0) end)
    return out
  end

  R._private = { pid_alive = pid_alive }

  return R
end

M._private = { pid_alive = pid_alive }

return M
