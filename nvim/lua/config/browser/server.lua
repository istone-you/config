-- ブラウザ表示系(html / markdown / diff_review)で共有する最小 HTTP サーバ(libuv TCP)。
--
-- もともと html.lua と markdown.lua が同じ TCP listen/accept ループをそれぞれ重複して
-- 持っていた。diff_review でも同じものが要るので、ここへ 1 箇所に切り出して 3 モジュールで
-- 使い回す。GET 専用ではなく、リクエストを {method, path, query, body} までパースして
-- handler に渡すので、diff_review の POST + JSON API もそのまま扱える。
--
-- サーバのソケットは呼び出し側が持つ state テーブル(.server/.port/.host)に載せる。
-- 既存モジュールのテストが state.server / state.port を直接触るため、この置き場所は変えない。

local M = {}
local browser = require('config.browser.util')

-- raw な HTTP リクエスト文字列を {method, path, query, body} へ。
-- ヘッダ終端(\r\n\r\n)が来る前、または Content-Length 分のボディが揃う前は nil(=継続待ち)。
-- GET など Content-Length 無しのリクエストはヘッダを受け切った時点で body='' として確定する。
function M.parse_request(raw)
  local head_end = raw:find('\r\n\r\n', 1, true)
  if not head_end then return nil end
  local head = raw:sub(1, head_end - 1)
  local request_line = head:match('^(.-)\r\n') or head
  local method, target = request_line:match('^(%u+)%s+(%S+)')
  if not method then return nil end
  local content_length = tonumber(head:match('\r\n[Cc]ontent%-[Ll]ength:%s*(%d+)')) or 0
  local body_start = head_end + 4
  local have = #raw - body_start + 1
  if have < content_length then return nil end
  local body = raw:sub(body_start, body_start + content_length - 1)
  local path, query = target:match('^([^?]*)%??(.*)$')
  return { method = method, path = path or '/', query = query or '', body = body }
end

--- port で listen を開始し、接続ごとに opts.handler(req) の返す文字列をレスポンスとして書き戻す。
--- ソケットは state.server / state.port / state.host に載せる(呼び出し側が所有)。
--- 既存の start_server と同じ契約: 成功で true、bind/listen 失敗で false, "port N is already in use"。
--- 呼び出し側は「既に起動中なら止める / 同じポートなら短絡する」といった判断を先に済ませておくこと。
--- opts = { handler = function(req) -> response string, namespace, default_host }
function M.start(state, port, opts)
  opts = opts or {}
  local bind_host = browser.config(opts.namespace).host or opts.default_host or '0.0.0.0'
  local uv = vim.uv or vim.loop

  local server = uv.new_tcp()
  local ok = pcall(function() assert(server:bind(bind_host, port)) end)
  if not ok then
    pcall(function() server:close() end)
    return false, string.format('port %d is already in use', port)
  end

  local listen_ok = pcall(function()
    assert(server:listen(128, function(err)
      if err then return end
      local client = uv.new_tcp()
      server:accept(client)
      local req = ''
      client:read_start(function(read_err, chunk)
        if read_err or not chunk then
          pcall(function() client:close() end)
          return
        end
        req = req .. chunk
        local parsed = M.parse_request(req)
        if not parsed then return end
        local resp
        local resp_ok, resp_err = pcall(function() resp = opts.handler(parsed) end)
        if not resp_ok then
          resp = browser.http_response('500 Internal Server Error', 'text/plain', tostring(resp_err))
        end
        client:write(resp, function()
          pcall(function() client:shutdown() end)
          pcall(function() client:close() end)
        end)
      end)
    end))
  end)
  if not listen_ok then
    pcall(function() server:close() end)
    return false, string.format('port %d is already in use', port)
  end

  state.server = server
  state.port = port
  state.host = bind_host
  return true
end

--- ソケットを閉じて state.server / state.port / state.host をクリアする。
--- source_buf の後始末や通知など、モジュール固有の停止処理は呼び出し側で行うこと。
function M.stop(state)
  if state.server then
    pcall(function() state.server:close() end)
  end
  state.server = nil
  state.port = nil
  state.host = nil
end

return M
