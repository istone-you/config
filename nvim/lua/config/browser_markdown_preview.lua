local M = {}

local state = {
  source_buf = nil,
  html = nil,
  version = 0,
  server = nil,
  port = nil,
  host = nil,
  root_dir = nil,
}

local augrp = vim.api.nvim_create_augroup('browser_markdown_preview', { clear = true })

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Markdown Browser Preview' })
end

local function load_local_config()
  local path = vim.fn.stdpath('config') .. '/local.lua'
  if vim.fn.filereadable(path) ~= 1 then return {} end
  local ok, result = pcall(dofile, path)
  if not ok or type(result) ~= 'table' then return {} end
  return result.browser_markdown_preview or {}
end

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function find_opener()
  local local_cfg = load_local_config()
  if type(local_cfg.opener) == 'string' and local_cfg.opener ~= '' then
    if executable(local_cfg.opener) then return local_cfg.opener end
    return nil
  end
  if executable('xdg-open') then return 'xdg-open' end
end

local function html_escape(s)
  return (s:gsub('&', '&amp;')
    :gsub('<', '&lt;')
    :gsub('>', '&gt;')
    :gsub('"', '&quot;'))
end

local function attr_escape(s)
  return html_escape(s):gsub("'", '&#39;')
end

local SAFE_HTML_TAGS = {
  a = true,
  abbr = true,
  b = true,
  br = true,
  code = true,
  del = true,
  details = true,
  div = true,
  em = true,
  i = true,
  img = true,
  ins = true,
  kbd = true,
  mark = true,
  p = true,
  pre = true,
  s = true,
  small = true,
  span = true,
  strong = true,
  sub = true,
  summary = true,
  sup = true,
  u = true,
}

local HTML_BLOCK_TAGS = {
  article = true,
  aside = true,
  blockquote = true,
  details = true,
  div = true,
  dl = true,
  fieldset = true,
  figcaption = true,
  figure = true,
  footer = true,
  form = true,
  h1 = true,
  h2 = true,
  h3 = true,
  h4 = true,
  h5 = true,
  h6 = true,
  header = true,
  hr = true,
  main = true,
  nav = true,
  ol = true,
  p = true,
  pre = true,
  section = true,
  summary = true,
  table = true,
  ul = true,
}

local function sanitize_attrs(attrs)
  attrs = attrs or ''
  attrs = attrs:gsub('%s+on[%w-]+%s*=%s*"[^"]*"', '')
  attrs = attrs:gsub("%s+on[%w-]+%s*=%s*'[^']*'", '')
  attrs = attrs:gsub('%s+on[%w-]+%s*=%s*[^%s>]+', '')
  attrs = attrs:gsub('%s+style%s*=%s*"[^"]*"', '')
  attrs = attrs:gsub("%s+style%s*=%s*'[^']*'", '')
  attrs = attrs:gsub('%s+style%s*=%s*[^%s>]+', '')
  attrs = attrs:gsub('%s+href%s*=%s*["\']?%s*javascript:[^%s>]*["\']?', '')
  attrs = attrs:gsub('%s+src%s*=%s*["\']?%s*javascript:[^%s>]*["\']?', '')
  return attrs
end

local function sanitize_html_tag(tag)
  local closing, name, attrs, self_close = tag:match('^<%s*(/?)%s*([%a][%w:-]*)(.-)(/?)%s*>$')
  if not name then return html_escape(tag) end
  name = name:lower()
  if not SAFE_HTML_TAGS[name] then return html_escape(tag) end
  if closing == '/' then return '</' .. name .. '>' end
  return '<' .. name .. sanitize_attrs(attrs) .. (self_close == '/' and ' />' or '>')
end

local function escape_markdown_text_keep_safe_html(s)
  local protected = {}
  s = s:gsub('</?[%a][^>]*>', function(tag)
    protected[#protected + 1] = sanitize_html_tag(tag)
    return '\0HTML' .. tostring(#protected) .. '\0'
  end)
  s = html_escape(s)
  s = s:gsub('%zHTML(%d+)%z', function(n)
    return protected[tonumber(n)] or ''
  end)
  return s
end

local function url_decode(s)
  s = s:gsub('+', ' ')
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function url_encode_path(s)
  return (s:gsub('[^%w%-%._~/%#:%?&=]', function(c)
    return string.format('%%%02X', c:byte())
  end))
end

local function is_external_url(url)
  return url:match('^[%a][%w+.-]*:') ~= nil or url:sub(1, 2) == '//' or url:sub(1, 1) == '#'
end

local slugify_heading

local function preview_asset_url(url)
  if is_external_url(url) then return url end
  return '/__asset/' .. url_encode_path(url:gsub('^%./', ''))
end

local function normalize_fragment(fragment)
  local decoded = url_decode(fragment:gsub('^#', ''))
  return '#' .. slugify_heading(decoded)
end

local function inline_markdown(s)
  s = escape_markdown_text_keep_safe_html(s)
  s = s:gsub('&lt;([%w._%%+%-]+@[%w._%-]+%.[%a][%w._%-]*)&gt;', function(email)
    return string.format('<a href="mailto:%s">%s</a>', attr_escape(email), email)
  end)
  s = s:gsub('&lt;(https?://[^%s&]+)&gt;', function(url)
    return string.format('<a href="%s">%s</a>', attr_escape(url), url)
  end)
  s = s:gsub('!%[([^%]]*)%]%(([^%)]+)%)', function(alt, url)
    return string.format('<img alt="%s" src="%s">', attr_escape(alt), attr_escape(preview_asset_url(url)))
  end)
  s = s:gsub('%[([^%]]+)%]%(([^%)]+)%)', function(label, url)
    if url:sub(1, 1) == '#' then
      return string.format('<a href="%s">%s</a>', attr_escape(normalize_fragment(url)), label)
    end
    return string.format('<a href="%s">%s</a>', attr_escape(preview_asset_url(url)), label)
  end)
  s = s:gsub('`([^`]+)`', '<code>%1</code>')
  s = s:gsub('%*%*([^%*]+)%*%*', '<strong>%1</strong>')
  s = s:gsub('__([^_]+)__', '<strong>%1</strong>')
  s = s:gsub('%*([^%*]+)%*', '<em>%1</em>')
  s = s:gsub('_([^_]+)_', '<em>%1</em>')
  return s
end

local function strip_inline_markup(s)
  return (s:gsub('!%[([^%]]*)%]%([^%)]+%)', '%1')
    :gsub('%[([^%]]+)%]%([^%)]+%)', '%1')
    :gsub('`([^`]+)`', '%1')
    :gsub('%*%*([^%*]+)%*%*', '%1')
    :gsub('__([^_]+)__', '%1')
    :gsub('%*([^%*]+)%*', '%1')
    :gsub('_([^_]+)_', '%1'))
end

slugify_heading = function(heading)
  local slug = strip_inline_markup(heading):lower()
  slug = slug:gsub('[%z\1-\31\127]', '')
  slug = slug:gsub('[!"#$%%&\'()*+,./:;<=>?@%[%]\\^`{|}~]', '')
  slug = slug:gsub('%s+', '-')
  slug = slug:gsub('%-+', '-')
  slug = slug:gsub('^%-', ''):gsub('%-$', '')
  if slug == '' then slug = 'section' end
  return slug
end

local function is_blank(s)
  return s:match('^%s*$') ~= nil
end

local function split_table_row(line)
  line = vim.trim(line)
  if line:sub(1, 1) == '|' then line = line:sub(2) end
  if line:sub(-1) == '|' then line = line:sub(1, -2) end
  local cells = {}
  local cur = {}
  local escaped = false
  for i = 1, #line do
    local c = line:sub(i, i)
    if c == '|' and not escaped then
      cells[#cells + 1] = vim.trim(table.concat(cur))
      cur = {}
    else
      cur[#cur + 1] = c
    end
    escaped = (c == '\\' and not escaped)
    if c ~= '\\' then escaped = false end
  end
  cells[#cells + 1] = vim.trim(table.concat(cur))
  return cells
end

local function parse_table_separator(line)
  if not line or not line:find('|', 1, true) then return nil end
  local cells = split_table_row(line)
  if #cells == 0 then return nil end
  local aligns = {}
  for _, cell in ipairs(cells) do
    local compact = cell:gsub('%s+', '')
    if not compact:match('^:?-+:?$') then return nil end
    local left = compact:sub(1, 1) == ':'
    local right = compact:sub(-1) == ':'
    aligns[#aligns + 1] = (left and right and 'center') or (right and 'right') or (left and 'left') or ''
  end
  return aligns
end

local function render_table(lines, start_i)
  local header = split_table_row(lines[start_i] or '')
  local aligns = parse_table_separator(lines[start_i + 1])
  if not aligns then return nil end

  local out = { '<table>', '<thead>', '<tr>' }
  for idx, cell in ipairs(header) do
    local align = aligns[idx] and aligns[idx] ~= '' and (' style="text-align:' .. aligns[idx] .. '"') or ''
    out[#out + 1] = '<th' .. align .. '>' .. inline_markdown(cell) .. '</th>'
  end
  out[#out + 1] = '</tr>'
  out[#out + 1] = '</thead>'
  out[#out + 1] = '<tbody>'

  local i = start_i + 2
  while i <= #lines and (lines[i] or ''):find('|', 1, true) and not is_blank(lines[i] or '') do
    local cells = split_table_row(lines[i] or '')
    out[#out + 1] = '<tr>'
    for idx, cell in ipairs(cells) do
      local align = aligns[idx] and aligns[idx] ~= '' and (' style="text-align:' .. aligns[idx] .. '"') or ''
      out[#out + 1] = '<td' .. align .. '>' .. inline_markdown(cell) .. '</td>'
    end
    out[#out + 1] = '</tr>'
    i = i + 1
  end

  out[#out + 1] = '</tbody>'
  out[#out + 1] = '</table>'
  return table.concat(out, '\n'), i
end

local function parse_list_marker(line)
  local indent, marker, text = line:match('^(%s*)([-*+])%s+(.+)$')
  if indent then return #indent, 'ul', text end
  indent, marker, text = line:match('^(%s*)(%d+[.)])%s+(.+)$')
  if indent then return #indent, 'ol', text end
end

local function render_list(lines, start_i)
  local root_indent, root_tag = parse_list_marker(lines[start_i] or '')
  if not root_indent then return nil end
  local out = {}
  local stack = {}
  local open_li = {}
  local i = start_i

  local function close_to(depth)
    while #stack > depth do
      if open_li[#stack] then
        out[#out] = (out[#out] or '') .. '</li>'
        open_li[#stack] = false
      end
      out[#out + 1] = '</' .. stack[#stack].tag .. '>'
      stack[#stack] = nil
      open_li[#stack + 1] = nil
    end
  end

  while i <= #lines do
    local indent, tag, text = parse_list_marker(lines[i] or '')
    if not indent then break end
    if indent < root_indent then break end

    local depth = 1
    while stack[depth] and indent > stack[depth].indent do depth = depth + 1 end
    while stack[depth] and indent < stack[depth].indent do
      close_to(#stack - 1)
      depth = depth - 1
    end
    if stack[depth] and indent == stack[depth].indent and #stack > depth then
      close_to(depth)
    end
    if not stack[depth] or stack[depth].indent ~= indent or stack[depth].tag ~= tag then
      if stack[depth] then close_to(depth - 1) end
      out[#out + 1] = '<' .. tag .. '>'
      stack[#stack + 1] = { indent = indent, tag = tag }
      depth = #stack
    elseif open_li[depth] then
      out[#out] = (out[#out] or '') .. '</li>'
      open_li[depth] = false
    end

    out[#out + 1] = '<li>' .. inline_markdown(text)
    open_li[depth] = true
    i = i + 1
  end

  close_to(0)
  return table.concat(out, ''), i
end

local function is_html_block_line(s)
  local closing, name = s:match('^%s*<%s*(/?)%s*([%a][%w:-]*)')
  if not name then return false end
  name = name:lower()
  return closing == '/' or HTML_BLOCK_TAGS[name] == true
end

local function is_block_start(s)
  return is_blank(s)
    or s:match('^%s*```') ~= nil
    or s:match('^%s*#+%s+') ~= nil
    or is_html_block_line(s)
    or s:match('^%s*>') ~= nil
    or s:match('^%s*[-*+]%s+') ~= nil
    or s:match('^%s*%d+[.)]%s+') ~= nil
    or s:match('^%s*[-*_][%s%-*_]*$') ~= nil
end

local function markdown_to_body(lines)
  local out = {}
  local slugs = {}
  local i = 1

  while i <= #lines do
    local line = lines[i] or ''

    if is_blank(line) then
      i = i + 1
    elseif line:match('^%s*```') then
      local lang = line:match('^%s*```%s*([^%s`]*)') or ''
      local code = {}
      i = i + 1
      while i <= #lines and not (lines[i] or ''):match('^%s*```') do
        code[#code + 1] = html_escape(lines[i] or '')
        i = i + 1
      end
      if i <= #lines then i = i + 1 end
      local class = lang ~= '' and string.format(' class="language-%s"', attr_escape(lang)) or ''
      out[#out + 1] = string.format('<pre><code%s>%s</code></pre>', class, table.concat(code, '\n'))
    elseif is_html_block_line(line) then
      out[#out + 1] = escape_markdown_text_keep_safe_html(line)
      i = i + 1
    else
      local hashes, heading = line:match('^%s*(#+)%s+(.+)$')
      if hashes and #hashes <= 6 then
        local level = #hashes
        local base_slug = slugify_heading(heading)
        local slug = base_slug
        slugs[base_slug] = (slugs[base_slug] or 0) + 1
        if slugs[base_slug] > 1 then slug = base_slug .. '-' .. tostring(slugs[base_slug] - 1) end
        out[#out + 1] = string.format('<h%d id="%s">%s</h%d>', level, attr_escape(slug), inline_markdown(heading), level)
        i = i + 1
      elseif line:match('^%s*[-*_][%s%-*_]*$') then
        out[#out + 1] = '<hr>'
        i = i + 1
      elseif line:match('^%s*>') then
        local parts = {}
        while i <= #lines and (lines[i] or ''):match('^%s*>') do
          parts[#parts + 1] = inline_markdown((lines[i] or ''):gsub('^%s*>%s?', ''))
          i = i + 1
        end
        out[#out + 1] = '<blockquote><p>' .. table.concat(parts, '<br>') .. '</p></blockquote>'
      elseif line:find('|', 1, true) and parse_table_separator(lines[i + 1]) then
        local html, next_i = render_table(lines, i)
        out[#out + 1] = html
        i = next_i
      elseif line:match('^%s*[-*+]%s+') or line:match('^%s*%d+[.)]%s+') then
        local html, next_i = render_list(lines, i)
        out[#out + 1] = html
        i = next_i
      else
        local parts = { inline_markdown(line) }
        i = i + 1
        while i <= #lines and not is_block_start(lines[i] or '') do
          parts[#parts + 1] = inline_markdown(lines[i] or '')
          i = i + 1
        end
        out[#out + 1] = '<p>' .. table.concat(parts, '<br>') .. '</p>'
      end
    end
  end

  return table.concat(out, '\n')
end

local function document_html(lines, title, base_dir, version)
  local _ = base_dir
  return table.concat({
    '<!doctype html>',
    '<html>',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta name="markdown-preview-version" content="' .. tostring(version or 0) .. '">',
    '<title>' .. html_escape(title or 'Markdown Preview') .. '</title>',
    '<style>',
    'body{margin:0;background:#111827;color:#e5e7eb;font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;}',
    'main{box-sizing:border-box;max-width:920px;margin:0 auto;padding:40px 48px 80px;}',
    'h1,h2,h3,h4,h5,h6{color:#f9fafb;line-height:1.25;margin:1.6em 0 .55em;font-weight:700;}',
    'h1{font-size:2.1rem;border-bottom:1px solid #374151;padding-bottom:.35em;} h2{font-size:1.55rem;border-bottom:1px solid #253044;padding-bottom:.25em;}',
    'p,ul,ol,blockquote,pre,table{margin:1em 0;} a{color:#93c5fd;}',
    'li>ul,li>ol{margin:.25em 0 .25em 1.4em;} li{margin:.2em 0;}',
    'blockquote{border-left:4px solid #4b5563;color:#cbd5e1;padding:.1rem 1rem;background:#172033;}',
    'code{background:#243044;color:#f8fafc;border-radius:4px;padding:.15em .35em;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.92em;}',
    'pre{background:#0b1220;border:1px solid #253044;border-radius:8px;padding:16px;overflow:auto;} pre code{background:transparent;padding:0;}',
    'table{border-collapse:collapse;width:100%;display:block;overflow:auto;} th,td{border:1px solid #374151;padding:6px 13px;} th{background:#1f2937;font-weight:600;} tr:nth-child(2n) td{background:#172033;}',
    'img{max-width:100%;height:auto;border-radius:6px;} hr{border:0;border-top:1px solid #374151;margin:2rem 0;}',
    '</style>',
    '<script>',
    'const v=document.querySelector("meta[name=markdown-preview-version]").content;',
    'setInterval(()=>fetch("/__version").then(r=>r.text()).then(n=>{if(n.trim()!==v)location.reload();}).catch(()=>{}),1000);',
    '</script>',
    '</head>',
    '<body><main>',
    markdown_to_body(lines),
    '</main></body>',
    '</html>',
  }, '\n')
end

local function update_preview_html(source_buf)
  local name = vim.api.nvim_buf_get_name(source_buf)
  local title = name ~= '' and vim.fn.fnamemodify(name, ':t') or 'Markdown Preview'
  local base_dir = name ~= '' and vim.fn.fnamemodify(name, ':p:h') or vim.fn.getcwd()
  state.root_dir = base_dir
  state.version = state.version + 1
  state.html = document_html(vim.api.nvim_buf_get_lines(source_buf, 0, -1, false), title, base_dir, state.version)
  return state.html
end

local function server_url()
  if not state.port then return nil end
  return 'http://localhost:' .. tostring(state.port) .. '/'
end

local function build_opener_cmd(opener, url)
  return { opener, url }
end

local function parse_port(input)
  input = vim.trim(tostring(input or ''))
  if input == '' then return nil, nil end
  if not input:match('^%d+$') then return nil, 'port must be a number' end
  local port = tonumber(input)
  if not port or port < 1 or port > 65535 then
    return nil, 'port must be between 1 and 65535'
  end
  return port
end

local function http_response(status, content_type, body)
  body = body or ''
  return table.concat({
    'HTTP/1.1 ' .. status,
    'Content-Type: ' .. content_type .. '; charset=utf-8',
    'Content-Length: ' .. tostring(#body),
    'Cache-Control: no-store',
    'Connection: close',
    '',
    body,
  }, '\r\n')
end

local CONTENT_TYPES = {
  png = 'image/png',
  jpg = 'image/jpeg',
  jpeg = 'image/jpeg',
  gif = 'image/gif',
  webp = 'image/webp',
  svg = 'image/svg+xml',
  css = 'text/css',
  js = 'application/javascript',
  txt = 'text/plain',
}

local function content_type_for(path)
  local ext = path:match('%.([%w]+)$')
  return (ext and CONTENT_TYPES[ext:lower()]) or 'application/octet-stream'
end

local function asset_response(asset_path)
  if not state.root_dir then return http_response('404 Not Found', 'text/plain', 'not found') end
  asset_path = url_decode(asset_path or ''):gsub('%?.*$', ''):gsub('#.*$', '')
  if asset_path == '' or asset_path:find('%z') or asset_path:match('^/') or asset_path:match('%.%.') then
    return http_response('403 Forbidden', 'text/plain', 'forbidden')
  end

  local full = vim.fn.fnamemodify(state.root_dir .. '/' .. asset_path, ':p')
  local root = vim.fn.fnamemodify(state.root_dir, ':p')
  if full:sub(1, #root) ~= root then
    return http_response('403 Forbidden', 'text/plain', 'forbidden')
  end
  if vim.fn.filereadable(full) ~= 1 then
    return http_response('404 Not Found', 'text/plain', 'not found')
  end

  local f = io.open(full, 'rb')
  if not f then return http_response('404 Not Found', 'text/plain', 'not found') end
  local body = f:read('*a')
  f:close()
  return http_response('200 OK', content_type_for(full), body)
end

local function response_for_path(path)
  if path == '/__version' then
    return http_response('200 OK', 'text/plain', tostring(state.version))
  end
  if path == '/' or path == '/index.html' then
    return http_response('200 OK', 'text/html', state.html or '<!doctype html><title>Markdown Preview</title>')
  end
  local asset_path = path:match('^/__asset/(.*)$')
  if asset_path then
    return asset_response(asset_path)
  end
  return http_response('404 Not Found', 'text/plain', 'not found')
end

local function stop_server()
  if state.server then
    pcall(function() state.server:close() end)
  end
  state.server = nil
  state.port = nil
  state.host = nil
end

local function start_server(port)
  if state.server and state.port == port then return true end
  if state.server and state.port ~= port then stop_server() end

  local local_cfg = load_local_config()
  local bind_host = local_cfg.host or '0.0.0.0'
  local uv = vim.uv or vim.loop

  local server = uv.new_tcp()
  local ok = pcall(function()
    assert(server:bind(bind_host, port))
  end)
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
        if not req:find('\r\n\r\n', 1, true) then return end
        local path = req:match('^GET%s+([^%s]+)') or '/'
        path = path:gsub('%?.*$', '')
        client:write(response_for_path(path), function()
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

local function open_with_default_browser(url)
  local opener = find_opener()
  if not opener then
    notify('Markdown preview URL: ' .. url .. ' (xdg-open not found)', vim.log.levels.WARN)
    return false
  end

  local job = vim.fn.jobstart(build_opener_cmd(opener, url), { detach = true })
  if job <= 0 then
    notify('Markdown preview URL: ' .. url .. ' (failed to start xdg-open)', vim.log.levels.WARN)
    return false
  end
  return url
end

function M.open_on_port(port)
  local source_buf = vim.api.nvim_get_current_buf()
  state.source_buf = source_buf
  update_preview_html(source_buf)
  local ok, err = start_server(port)
  if not ok then
    notify(err or 'failed to start markdown preview server', vim.log.levels.ERROR)
    return
  end
  local url = server_url()
  open_with_default_browser(url)
  notify('Markdown preview URL: ' .. url)
end

function M.open()
  vim.ui.input({
    prompt = 'Markdown preview port: ',
  }, function(input)
    if input == nil then return end
    local port, err = parse_port(input)
    if not port then
      notify(err, vim.log.levels.ERROR)
      return
    end
    M.open_on_port(port)
  end)
end

function M.refresh(opts)
  opts = opts or {}
  local source_buf = state.source_buf
  if not source_buf or not vim.api.nvim_buf_is_valid(source_buf) then
    source_buf = vim.api.nvim_get_current_buf()
    state.source_buf = source_buf
  end
  update_preview_html(source_buf)
  if not opts.silent then
    local url = server_url()
    notify(url and ('Updated markdown preview: ' .. url) or 'Updated markdown preview')
  end
end

function M.toggle()
  M.open()
end

vim.api.nvim_create_user_command('BrowserMarkdownPreview', function() M.open() end, {
  desc = 'Open markdown preview in default browser',
})
vim.api.nvim_create_user_command('BrowserMarkdownPreviewRefresh', function() M.refresh() end, {
  desc = 'Refresh browser markdown preview HTML',
})

vim.keymap.set('n', '<leader>mc', M.open, {
  desc = 'Open markdown preview in default browser',
})

vim.api.nvim_create_autocmd('BufWritePost', {
  group = augrp,
  pattern = { '*.md', '*.markdown' },
  callback = function(ev)
    if state.source_buf == ev.buf and state.server then M.refresh({ silent = true }) end
  end,
})

M._private = {
  build_opener_cmd = build_opener_cmd,
  document_html = document_html,
  find_opener = find_opener,
  http_response = http_response,
  inline_markdown = inline_markdown,
  markdown_to_body = markdown_to_body,
  asset_response = asset_response,
  preview_asset_url = preview_asset_url,
  response_for_path = response_for_path,
  server_url = server_url,
  state = state,
  parse_port = parse_port,
  start_server = start_server,
  stop_server = stop_server,
  slugify_heading = slugify_heading,
  url_decode = url_decode,
  url_encode_path = url_encode_path,
}

return M
