-- VS Code 風のエディタ余白（ガター）に git 差分を表示する
-- 差分取得は airblade/vim-gitgutter の思路に合わせる:
--   git show --textconv <base>:<path> をそのまま一時ファイルへ
--   バッファ内容も fileformat / endofline を尊重して書き出し
--   拡張子を残して git diff（.gitattributes の EOL 変換を壊さない）

local M = {}

local ns = vim.api.nvim_create_namespace('git_gutter')
local timers = {}
local generation = {}

-- VS Code に近い色（追加=緑 / 変更=青 / 削除=赤）
local SIGN = {
  add = { text = '┃', hl = 'GitGutterAdd' },
  change = { text = '┃', hl = 'GitGutterChange' },
  delete = { text = '▁', hl = 'GitGutterDelete' },
  change_delete = { text = '┃', hl = 'GitGutterChangeDelete' },
}

local function setup_hl()
  vim.api.nvim_set_hl(0, 'GitGutterAdd', { fg = '#9ece6a', bold = true })
  vim.api.nvim_set_hl(0, 'GitGutterChange', { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'GitGutterDelete', { fg = '#f7768e', bold = true })
  vim.api.nvim_set_hl(0, 'GitGutterChangeDelete', { fg = '#e0af68', bold = true })
end

local function git_root(cwd)
  if type(cwd) ~= 'string' or cwd == '' or vim.fn.isdirectory(cwd) == 0 then
    return nil
  end
  -- node_modules 等が別マウント（FS境界）でも上位の .git を探せるようにする
  local ok, res = pcall(vim.system, { 'git', 'rev-parse', '--show-toplevel' },
    { cwd = cwd, text = true, env = { GIT_DISCOVERY_ACROSS_FILESYSTEM = '1' } })
  if not ok or not res then
    return nil
  end
  res = res:wait()
  if res.code ~= 0 then
    return nil
  end
  return vim.trim(res.stdout or '')
end

local function rel_path(root, abs)
  abs = vim.fs.normalize(vim.fn.resolve(abs))
  root = vim.fs.normalize(root)
  if vim.startswith(abs, root .. '/') then
    return abs:sub(#root + 2)
  end
  return nil
end

local function with_extension(base, path)
  local ext = path:match('(%.[^./\\]+)$')
  if ext then
    return base .. ext
  end
  return base
end

--- vim-gitgutter の write_buffer 相当
local function write_buffer(buf, file)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- 完全に空のバッファ
  if #lines == 1 and lines[1] == '' and vim.api.nvim_buf_line_count(buf) == 1 then
    if vim.fn.line2byte(1) == -1 then
      vim.fn.writefile({}, file, 'b')
      return
    end
  end

  if vim.bo[buf].fileformat == 'dos' then
    if vim.bo[buf].endofline then
      for i, l in ipairs(lines) do
        lines[i] = l .. '\r'
      end
    else
      for i = 1, #lines - 1 do
        lines[i] = lines[i] .. '\r'
      end
    end
  end

  if vim.bo[buf].endofline then
    table.insert(lines, '')
  end

  local fenc = vim.bo[buf].fileencoding
  if fenc ~= '' and fenc ~= vim.o.encoding then
    for i, l in ipairs(lines) do
      lines[i] = vim.fn.iconv(l, vim.o.encoding, fenc)
    end
  end

  if vim.bo[buf].bomb and #lines > 0 then
    lines[1] = '\239\187\191' .. lines[1]
  end

  vim.fn.writefile(lines, file, 'b')
end

--- unified diff (-U0) の @@ 行を vim-gitgutter と同じ規則で行マークへ展開
---@param diff_text string
---@return { lnum: integer, type: string }[]
function M.parse_diff(diff_text)
  local marks = {}

  local function add_range(lnum, count, typ)
    for i = 0, count - 1 do
      table.insert(marks, { lnum = lnum + i, type = typ })
    end
  end

  for line in vim.gsplit(diff_text or '', '\n', { plain = true }) do
    local old_start, old_count, new_start, new_count =
      line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
    if old_start then
      local from_line = tonumber(old_start)
      local from_count = old_count == '' and 1 or tonumber(old_count)
      local to_line = tonumber(new_start)
      local to_count = new_count == '' and 1 or tonumber(new_count)

      if from_count == 0 and to_count > 0 then
        add_range(to_line, to_count, 'add')
      elseif from_count > 0 and to_count == 0 then
        if to_line == 0 then
          table.insert(marks, { lnum = 1, type = 'delete' })
        else
          table.insert(marks, { lnum = to_line, type = 'delete' })
        end
      elseif from_count > 0 and to_count > 0 and from_count == to_count then
        add_range(to_line, to_count, 'change')
      elseif from_count > 0 and to_count > 0 and from_count < to_count then
        add_range(to_line, from_count, 'change')
        add_range(to_line + from_count, to_count - from_count, 'add')
      elseif from_count > 0 and to_count > 0 and from_count > to_count then
        add_range(to_line, to_count, 'change')
        if to_count > 0 then
          marks[#marks].type = 'change_delete'
        else
          table.insert(marks, { lnum = to_line, type = 'delete' })
        end
      end
    end
  end

  return marks
end

local function clear_buf(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function place_marks(buf, marks)
  clear_buf(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, m in ipairs(marks) do
    local sign = SIGN[m.type]
    if sign then
      local row = math.min(math.max(m.lnum, 1), line_count) - 1
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
        sign_text = sign.text,
        sign_hl_group = sign.hl,
        priority = 6,
      })
    end
  end
end

--- バッファと HEAD の差分テキストを返す（vim-gitgutter 相当）
---@param buf integer
---@return string|nil
---@return string|nil
function M.diff_for_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == '' or vim.bo[buf].buftype ~= '' then
    return nil, 'skip'
  end

  local cwd = vim.fn.fnamemodify(path, ':h')
  local root = git_root(cwd)
  if not root then
    return nil, 'not a git repo'
  end

  local rel = rel_path(root, path)
  if not rel or rel == '' then
    return nil, 'outside repo'
  end

  -- git 管理外（未追跡・ignore）のファイルはガター表示しない
  local tracked = vim.system(
    { 'git', 'ls-files', '--error-unmatch', '--', rel },
    { cwd = root }
  ):wait()
  if tracked.code ~= 0 then
    return '', nil
  end

  local stamp = tostring(buf) .. '.' .. tostring(generation[buf] or 0)
  local from_file = with_extension(vim.fn.tempname() .. '.from.' .. stamp, path)
  local buff_file = with_extension(vim.fn.tempname() .. '.buf.' .. stamp, path)

  -- index/HEAD 側: git show の生出力をそのまま書く（行分割しない）
  local show = vim.system(
    { 'git', '--no-pager', 'show', '--textconv', 'HEAD:' .. rel },
    { cwd = root }
  ):wait()

  if show.code == 0 then
    local f = assert(io.open(from_file, 'wb'))
    f:write(show.stdout or '')
    f:close()
  else
    -- 未追跡: 空ファイルとの差分
    vim.fn.writefile({}, from_file, 'b')
  end

  write_buffer(buf, buff_file)

  local diff = vim.system({
    'git',
    '--no-pager',
    '-c', 'diff.autorefreshindex=0',
    '-c', 'diff.noprefix=false',
    '-c', 'core.safecrlf=false',
    'diff',
    '--no-ext-diff',
    '--no-color',
    '-U0',
    '--',
    from_file,
    buff_file,
  }, { cwd = root, text = true }):wait()

  vim.fn.delete(from_file)
  vim.fn.delete(buff_file)

  -- 差分ありは 1。警告等でそれ以外なら失敗扱い
  if diff.code ~= 0 and diff.code ~= 1 then
    return nil, diff.stderr
  end
  return diff.stdout or '', nil
end

---@param buf integer|nil
function M.refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].buftype ~= '' then
    clear_buf(buf)
    return
  end

  generation[buf] = (generation[buf] or 0) + 1
  local gen = generation[buf]

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) or generation[buf] ~= gen then
      return
    end
    local diff_text = M.diff_for_buf(buf)
    if generation[buf] ~= gen then
      return
    end
    if not diff_text then
      clear_buf(buf)
      return
    end
    if diff_text == '' then
      clear_buf(buf)
      return
    end
    place_marks(buf, M.parse_diff(diff_text))
  end)
end

local function schedule_refresh(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if timers[buf] then
    timers[buf]:stop()
    timers[buf] = nil
  end
  timers[buf] = vim.defer_fn(function()
    timers[buf] = nil
    M.refresh(buf)
  end, 150)
end

function M.setup()
  setup_hl()
  vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'FocusGained' }, {
    callback = function(ev)
      schedule_refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    callback = function(ev)
      schedule_refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    callback = function(ev)
      if timers[ev.buf] then
        timers[ev.buf]:stop()
        timers[ev.buf] = nil
      end
      generation[ev.buf] = nil
    end,
  })
end

M.setup()

return M
