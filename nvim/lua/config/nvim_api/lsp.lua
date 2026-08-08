-- LSP プロキシ。nvim に常駐している(= そのリポジトリ用にインデックス済みの)言語サーバへ
-- 問い合わせ、結果を AI が読める JSON へ整形して返す。
--
-- 狙いは AI 側の探索精度。grep は文字列一致なので、同名シンボル(このリポジトリだけでも
-- function M.open が 19 個ある)を区別できず、import のエイリアスは原理的に追えない。
-- LSP はスコープを解決して答えるので、references が一発で正しい件数になる。
--
-- 実装上の注意:
-- * ここは必ずメインループ上(vim.schedule の中)から呼ぶこと(vim.api を触るため)。
-- * 問い合わせは全て非同期。buf_request_sync / vim.wait は打鍵を処理しないままメインループを
--   占有するので、AI が投げている数百ms〜数秒のあいだ人間のエディタが固まって見える。
--   代わりに buf_request_all のコールバックと、タイムアウト用の uv タイマーで組む。
-- * LSP の位置は 0-based、character は UTF-16 単位。API 側は 1-based のバイト桁で受けて
--   ここで変換する(AI にとっては 1-based のほうが自然で、間違いも少ない)。

local M = {}
local util = require('config.nvim_api.util')
local buffers = require('config.nvim_api.buffers')

M.REQUEST_TIMEOUT_MS = 5000

local SYMBOL_KIND = {}
for name, id in pairs(vim.lsp.protocol.SymbolKind) do
  if type(id) == 'number' then SYMBOL_KIND[id] = name end
end

--- 行テキストのバイト桁(1-based)を UTF-16 のオフセット(0-based)へ。
--- nvim 0.11+ は vim.str_utfindex(s, encoding)、それ以前は 2 値返しなので両対応する。
function M.utf_col(line, col1, encoding)
  local col0 = math.max((col1 or 1) - 1, 0)
  if not line or col0 <= 0 then return 0 end
  if encoding == 'utf-8' then return col0 end
  local sub = line:sub(1, col0)
  local ok, a, b = pcall(vim.str_utfindex, sub, encoding or 'utf-16')
  if ok and type(a) == 'number' and b == nil then return a end
  local ok2, u32, u16 = pcall(vim.str_utfindex, sub)
  if ok2 then
    if encoding == 'utf-32' then return u32 end
    return u16 or u32
  end
  return col0
end

--- textDocument/position のパラメータを組み立てる(line/col はどちらも 1-based)。
function M.position_params(bufnr, line, col, encoding)
  local lines = vim.api.nvim_buf_get_lines(bufnr, (line or 1) - 1, line or 1, false)
  return {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = {
      line = math.max((line or 1) - 1, 0),
      character = M.utf_col(lines and lines[1] or '', col or 1, encoding),
    },
  }
end

--- そのバッファに付いている最初のクライアント(offset_encoding を取るため)。
local function primary_client(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  return clients[1], #clients
end

--- 非同期リクエスト。複数クライアントが付いている場合は結果を全部集めて cb(results, err) を呼ぶ。
--- cb は必ず 1 回だけ呼ばれる(応答・エラー・タイムアウトのうち先に来たもの)。
function M.request_async(bufnr, method, params, timeout_ms, cb)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #clients == 0 then
    return cb(nil, 'no LSP client attached (ファイルの言語にサーバが設定されていないか、まだ初期化中)')
  end

  local uv = vim.uv or vim.loop
  local timer = uv.new_timer()
  local cancel
  local done = false

  local function finish(results, err)
    if done then return end
    done = true
    if timer then
      pcall(function() timer:stop() end)
      pcall(function() timer:close() end)
    end
    cb(results, err)
  end

  cancel = vim.lsp.buf_request_all(bufnr, method, params, function(responses)
    local out = {}
    for _, resp in pairs(responses or {}) do
      -- 0.12 は err / error の両方を載せる(error は 0.13 で消える予定)
      local rerr = resp.err or resp.error
      if rerr then
        return finish(nil, tostring(rerr.message or rerr))
      end
      if resp.result ~= nil then out[#out + 1] = resp.result end
    end
    finish(out)
  end)

  if timer then
    timer:start(util.timeout_ms(timeout_ms, M.REQUEST_TIMEOUT_MS), 0, function()
      vim.schedule(function()
        if cancel then pcall(cancel) end
        finish(nil, 'LSP request timed out')
      end)
    end)
  end
end

--- Location / LocationLink / それらの配列 を、共通の {file,line,col,...} 配列へ均す。
function M.format_locations(results, root)
  local out = {}
  local seen = {}

  local function push(loc)
    if type(loc) ~= 'table' then return end
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange or loc.targetRange
    if not uri or not range then return end
    local ok, path = pcall(vim.uri_to_fname, uri)
    if not ok then return end
    local abs = util.real(path)
    local line = (range.start.line or 0) + 1
    local key = abs .. ':' .. line .. ':' .. ((range.start.character or 0) + 1)
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = {
      file     = util.rel_path(abs, root),
      line     = line,
      col      = (range.start.character or 0) + 1,
      end_line = (range['end'].line or 0) + 1,
      end_col  = (range['end'].character or 0) + 1,
      text     = util.or_null(util.line_text(abs, line)),
    }
  end

  local function walk(node)
    if type(node) ~= 'table' then return end
    if node.uri or node.targetUri then
      push(node)
      return
    end
    for _, child in ipairs(node) do walk(child) end
  end

  walk(results)
  table.sort(out, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  return out
end

--- DocumentSymbol(階層) と SymbolInformation(平坦) の両方を、平坦な配列へ均す。
--- 階層は container で表現する(AI が構造を把握できるよう親名を連ねる)。
function M.flatten_symbols(results, root)
  local out = {}

  local function push_document_symbol(sym, container)
    local range = sym.selectionRange or sym.range
    if not range then return end
    out[#out + 1] = {
      name      = sym.name,
      kind      = SYMBOL_KIND[sym.kind] or tostring(sym.kind),
      container = util.or_null(container),
      detail    = util.or_null(sym.detail),
      line      = (range.start.line or 0) + 1,
      col       = (range.start.character or 0) + 1,
      end_line  = ((sym.range or range)['end'].line or 0) + 1,
    }
    local next_container = container and (container .. '.' .. sym.name) or sym.name
    for _, child in ipairs(sym.children or {}) do
      push_document_symbol(child, next_container)
    end
  end

  local function push_symbol_information(sym)
    local loc = sym.location or {}
    local range = loc.range
    if not range then return end
    local ok, path = pcall(vim.uri_to_fname, loc.uri or '')
    local abs = ok and util.real(path) or nil
    out[#out + 1] = {
      name      = sym.name,
      kind      = SYMBOL_KIND[sym.kind] or tostring(sym.kind),
      container = util.or_null(sym.containerName),
      file      = abs and util.rel_path(abs, root) or vim.NIL,
      line      = (range.start.line or 0) + 1,
      col       = (range.start.character or 0) + 1,
      end_line  = (range['end'].line or 0) + 1,
    }
  end

  local function walk(node)
    if type(node) ~= 'table' then return end
    if node.name and (node.selectionRange or node.range) then
      push_document_symbol(node, nil)
      return
    end
    if node.name and node.location then
      push_symbol_information(node)
      return
    end
    for _, child in ipairs(node) do walk(child) end
  end

  walk(results)
  return out
end

--- hover の contents(string / MarkedString / MarkupContent / それらの配列)を素の markdown へ。
function M.hover_text(results)
  local chunks = {}
  for _, result in ipairs(results or {}) do
    if type(result) == 'table' and result.contents ~= nil then
      local ok, lines = pcall(vim.lsp.util.convert_input_to_markdown_lines, result.contents, {})
      if ok and lines and #lines > 0 then
        chunks[#chunks + 1] = table.concat(lines, '\n')
      end
    end
  end
  local text = vim.trim(table.concat(chunks, '\n\n'))
  if text == '' then return nil end
  return text
end

--- code action の一覧(タイトルと種別だけ)。適用はしない。
--- 「何が直せる状態か」を AI に見せるためのもので、実際に直すのは通常の編集でやったほうが
--- 差分が見える。適用まで API でやると、人間の知らないところでバッファが変わってしまう。
function M.format_code_actions(results)
  local out = {}
  for _, result in ipairs(results or {}) do
    for _, action in ipairs(result or {}) do
      if type(action) == 'table' and action.title then
        out[#out + 1] = {
          title = action.title,
          kind = util.or_null(action.kind),
          preferred = action.isPreferred == true,
        }
      end
    end
  end
  return out
end

--- 位置指定のリクエスト(definition/references/hover/code_action)の共通前処理。
--- ファイルをロードして LSP のアタッチを待ち、位置パラメータまで組み立てて cb(bufnr, params, err)。
function M.prepare_async(body, root, cb)
  local file = body.file
  if not file or file == '' then return cb(nil, nil, 'file is required') end
  local line = util.to_number(body.line, nil)
  if not line or line < 1 then return cb(nil, nil, 'line must be a positive integer (1-based)') end
  local col = util.to_number(body.col, 1)

  buffers.ensure_loaded_async(file, root, body.timeout_ms, function(bufnr, err)
    if not bufnr then return cb(nil, nil, err) end
    local client = primary_client(bufnr)
    local encoding = client and client.offset_encoding or 'utf-16'
    cb(bufnr, M.position_params(bufnr, line, col, encoding), nil)
  end)
end

M._private = {
  primary_client = primary_client,
  SYMBOL_KIND = SYMBOL_KIND,
}

return M
