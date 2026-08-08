-- バッファのロードと外部編集の取り込み。
--
-- ここは「LSP API のための前処理」がほぼ全部。自作していて必ず踏む罠が 2 つあり、
-- どちらもこのファイルで吸収している:
--
-- 1. LSP はまだ開いていないファイルのことを知らない。AI が任意のパスについて references を
--    聞いてきたら、先にバッファへ載せて(= FileType/BufReadPost が走って LSP がアタッチして)
--    初期化が終わるのを待つ必要がある。これを飛ばすと「空の結果が返る」という一番
--    デバッグしづらい失敗になる。
-- 2. AI がディスクを直接書き換えた直後、nvim のバッファも診断も古いまま。checktime で
--    読み直さないと、AI は自分が消したはずのエラーを見続けることになる。

local M = {}
local util = require('config.nvim_api.util')

M.ATTACH_TIMEOUT_MS = 3000
M.ATTACH_POLL_MS = 30

--- ファイルをバッファへ載せ、LSP クライアントが付いてから cb(bufnr, err) を呼ぶ。
--- LSP が設定されていない言語でも失敗にはせず、タイムアウトで抜けて bufnr を返す。
---
--- 待ちは uv タイマーのポーリングで行う。vim.wait は打鍵を処理しないままメインループを
--- 占有するため、AI のリクエスト中に人間のエディタが固まって見える。この経路では使わない。
function M.ensure_loaded_async(file, root, timeout_ms, cb)
  local abs, path_err = util.client_path(file, root)
  if not abs then return cb(nil, path_err) end
  if vim.fn.filereadable(abs) ~= 1 then
    return cb(nil, 'file not readable: ' .. abs)
  end

  local bufnr = vim.fn.bufadd(abs)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    -- bufload で FileType / BufReadPost が走り、lsp.lua の設定に従ってサーバがアタッチする。
    -- bufadd は unlisted のまま作るので、AI が読んだファイルが人間のタブラインには出ない。
    vim.fn.bufload(bufnr)
  else
    -- 既に載っている場合は外部編集を取り込む(未変更バッファだけが対象)
    M.checktime(bufnr)
  end

  if #vim.lsp.get_clients({ bufnr = bufnr }) > 0 then return cb(bufnr) end

  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()
  if not timer then return cb(bufnr) end
  local limit = util.timeout_ms(timeout_ms, M.ATTACH_TIMEOUT_MS)
  local waited = 0
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    pcall(function() timer:stop() end)
    pcall(function() timer:close() end)
    cb(bufnr)
  end
  timer:start(M.ATTACH_POLL_MS, M.ATTACH_POLL_MS, function()
    vim.schedule(function()
      if finished then return end
      -- ポーリング中の想定外エラーで抜け出せなくなると、30ms ごとにエラーを吐き続ける
      -- ループになる(タイマーも閉じない)。何が起きても必ず finish() へ落とす。
      local ok = pcall(function()
        waited = waited + M.ATTACH_POLL_MS
        if #vim.lsp.get_clients({ bufnr = bufnr }) > 0 or waited >= limit then finish() end
      end)
      if not ok then finish() end
    end)
  end)
end

--- 未変更のバッファだけディスクから読み直す。変更中のバッファは触らない(プロンプトを避ける)。
--- bufnr を省略すると読み込み済みの全バッファが対象。
function M.checktime(bufnr)
  local targets = {}
  if bufnr then
    targets = { bufnr }
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) then targets[#targets + 1] = b end
    end
  end
  local reloaded = 0
  for _, b in ipairs(targets) do
    if vim.api.nvim_buf_is_valid(b)
      and vim.api.nvim_buf_is_loaded(b)
      and not vim.bo[b].modified
      and vim.api.nvim_buf_get_name(b) ~= ''
    then
      local ok = pcall(vim.api.nvim_buf_call, b, function()
        vim.cmd('silent! checktime')
      end)
      if ok then reloaded = reloaded + 1 end
    end
  end
  return reloaded
end

--- そのバッファに付いているクライアント名。
local function client_names(bufnr)
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do names[#names + 1] = c.name end
  return names
end

--- 開いているバッファの一覧(AI が「今どのファイルが見えているか」を知るため)。
function M.list(root)
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if vim.api.nvim_buf_is_loaded(b) and name ~= '' and vim.bo[b].buftype == '' then
      out[#out + 1] = {
        file = util.rel_path(name, root),
        bufnr = b,
        filetype = vim.bo[b].filetype,
        modified = vim.bo[b].modified,
        lines = vim.api.nvim_buf_line_count(b),
        lsp = client_names(b),
      }
    end
  end
  table.sort(out, function(a, b) return a.file < b.file end)
  return out
end

--- 複数ファイルを順にロードして cb(loaded, failed) を呼ぶ。/api/buffers/load 用。
--- 並列に走らせても言語サーバ側が詰まるだけなので逐次でよい。
function M.load_many_async(files, root, timeout_ms, cb)
  local list = files or {}
  local loaded, failed = {}, {}
  local i = 0
  local function step()
    i = i + 1
    if i > #list then return cb(loaded, failed) end
    local target = list[i]
    M.ensure_loaded_async(target, root, timeout_ms, function(bufnr, err)
      if bufnr then
        loaded[#loaded + 1] = {
          file = util.rel_path(vim.api.nvim_buf_get_name(bufnr), root),
          bufnr = bufnr,
          lsp = client_names(bufnr),
        }
      else
        failed[#failed + 1] = { file = target, error = err }
      end
      step()
    end)
  end
  step()
end

return M
