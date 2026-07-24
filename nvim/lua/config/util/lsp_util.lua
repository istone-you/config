-- LSP 設定の補助（バイナリ有無・VS Code settings 読み込み・保存時フォーマット）

local M = {}

function M.has_cmd(name)
  return vim.fn.executable(name) == 1
end

--- cmd 先頭のバイナリが PATH にあるサーバー名だけ enable する
---@param names string[]
function M.enable_if_available(names)
  local enabled = {}
  for _, name in ipairs(names) do
    local cfg = vim.lsp.config[name]
    local bin = cfg and cfg.cmd and cfg.cmd[1]
    if type(bin) == 'string' and M.has_cmd(bin) then
      table.insert(enabled, name)
    end
  end
  if #enabled > 0 then
    vim.lsp.enable(enabled)
  end
end

--- JSONC（VS Code settings.json）からコメントを除去する
---@param text string
---@return string
local function strip_jsonc(text)
  local out = {}
  local i = 1
  local n = #text
  local in_string = false
  local escape = false
  while i <= n do
    local c = text:sub(i, i)
    local nextc = text:sub(i + 1, i + 1)
    if in_string then
      out[#out + 1] = c
      if escape then
        escape = false
      elseif c == '\\' then
        escape = true
      elseif c == '"' then
        in_string = false
      end
      i = i + 1
    elseif c == '"' then
      in_string = true
      out[#out + 1] = c
      i = i + 1
    elseif c == '/' and nextc == '/' then
      i = i + 2
      while i <= n and text:sub(i, i) ~= '\n' do
        i = i + 1
      end
    elseif c == '/' and nextc == '*' then
      i = i + 2
      while i <= n and text:sub(i, i + 1) ~= '*/' do
        i = i + 1
      end
      i = i + 2
    elseif c == ',' then
      -- VS Code JSONC は末尾カンマを許す。`,` の直後（空白除く）が } / ] なら捨てる
      local j = i + 1
      while j <= n and text:sub(j, j):match('%s') do
        j = j + 1
      end
      local peek = text:sub(j, j)
      if peek == '}' or peek == ']' then
        i = i + 1
      else
        out[#out + 1] = c
        i = i + 1
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- `a.b.c` 形式のキーをネストした table にする
---@param flat table<string, any>
---@param prefix string
---@return table
local function nest_dotted_keys(flat, prefix)
  local nested = {}
  local prefix_dot = prefix .. '.'
  for key, value in pairs(flat) do
    if key == prefix or vim.startswith(key, prefix_dot) then
      local path = key == prefix and {} or vim.split(key:sub(#prefix_dot + 1), '.', { plain = true })
      local cur = nested
      for i, part in ipairs(path) do
        if i == #path then
          cur[part] = value
        else
          cur[part] = cur[part] or {}
          cur = cur[part]
        end
      end
      if key == prefix and type(value) == 'table' then
        nested = vim.tbl_deep_extend('force', nested, value)
      end
    end
  end
  return nested
end

--- レポルートの `.vscode/settings.json` から yaml.* だけ読む。無ければ nil。
---@param root string|nil
---@return table|nil
local function load_vscode_yaml_settings(root)
  if not root or root == '' then
    return nil
  end
  local path = root .. '/.vscode/settings.json'
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  if type(lines) ~= 'table' then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, strip_jsonc(table.concat(lines, '\n')))
  if not ok or type(decoded) ~= 'table' then
    return nil
  end
  local yaml = nest_dotted_keys(decoded, 'yaml')
  if vim.tbl_isempty(yaml) then
    return nil
  end
  return { yaml = yaml }
end

--- yamlls の before_init: レポに `.vscode/settings.json` があれば yaml.* を適用
function M.yamlls_before_init(_, config)
  local from_vscode = load_vscode_yaml_settings(config.root_dir)
  if from_vscode then
    config.settings = vim.tbl_deep_extend('force', config.settings or {}, from_vscode)
  end
end

---@param clients table<string, boolean>
function M.setup_format_on_save(clients)
  vim.api.nvim_create_autocmd('BufWritePre', {
    callback = function()
      vim.lsp.buf.format({
        async = false,
        filter = function(client)
          return clients[client.name] == true
        end,
      })
    end,
  })
end

return M
