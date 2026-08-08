-- Code Notes の entry 管理。
-- AI / 人間が API やブラウザで共有する、場所付きコードリーディングコメント。

local M = {}

local seq = 0
local version = 0
local items = {}

local function now()
  return os.time()
end

local function bump()
  version = version + 1
end

local function next_id()
  seq = seq + 1
  return 'f' .. tostring(seq)
end

local function clean_text(v)
  return tostring(v or ''):gsub('\r\n', '\n')
end

local function input_line_end(input, defaults)
  return tonumber(input.lineEnd) or tonumber(input.endLine) or tonumber(input.line_end) or defaults.lineEnd
end

local function public(f)
  return {
    id = f.id,
    file = f.file or vim.NIL,
    line = f.line or vim.NIL,
    lineEnd = f.lineEnd or vim.NIL,
    col = f.col or vim.NIL,
    text = f.text,
    author = f.author,
    createdAt = f.createdAt,
    updatedAt = f.updatedAt,
  }
end

local function normalize(input, defaults)
  input = type(input) == 'table' and input or {}
  defaults = defaults or {}
  local line = tonumber(input.line) or defaults.line
  local line_end = input_line_end(input, defaults)
  if line and line_end and line_end < line then line_end = line end
  return {
    id = input.id or defaults.id or next_id(),
    file = input.file and tostring(input.file) or defaults.file,
    line = line,
    lineEnd = line_end,
    col = tonumber(input.col) or defaults.col,
    text = clean_text(input.text or defaults.text),
    author = tostring(input.author or defaults.author or 'ai'),
    createdAt = defaults.createdAt or now(),
    updatedAt = now(),
  }
end

function M.version()
  return version
end

function M.list(filter)
  filter = filter or {}
  local out = {}
  for _, f in ipairs(items) do
    if not filter.file or filter.file == '' or f.file == filter.file then
      out[#out + 1] = public(f)
    end
  end
  return out
end

function M.add(input)
  local f = normalize(input)
  if f.text == '' then return nil, 'text is required' end
  items[#items + 1] = f
  bump()
  return public(f)
end

function M.set(list)
  items = {}
  seq = 0
  for _, input in ipairs(list or {}) do
    local f = normalize(input)
    if f.text ~= '' then
      items[#items + 1] = f
      local n = tostring(f.id):match('^f(%d+)$')
      if n then seq = math.max(seq, tonumber(n) or 0) end
    end
  end
  bump()
  return #items
end

function M.update(input)
  input = type(input) == 'table' and input or {}
  if not input.id or input.id == '' then return nil, 'id is required' end
  for i, f in ipairs(items) do
    if f.id == input.id then
      local next_f = normalize(input, f)
      items[i] = next_f
      bump()
      return public(next_f)
    end
  end
  return nil, 'entry not found'
end

function M.remove(id)
  for i, f in ipairs(items) do
    if f.id == id then
      table.remove(items, i)
      bump()
      return true
    end
  end
  return false
end

function M.clear()
  items = {}
  seq = 0
  bump()
end

M._private = {
  normalize = normalize,
  public = public,
}

return M
