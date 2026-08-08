local T = dofile(TESTS_DIR .. '/helpers.lua')
local editor = require('config.nvim_api.editor')
local util = require('config.nvim_api.util')

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

local function with_root(fn)
  local root = util.real(vim.fn.tempname())
  vim.fn.mkdir(root, 'p')
  vim.fn.writefile({ 'alpha', 'bravo', 'charlie' }, root .. '/a.lua')
  local ok, err = pcall(fn, root)
  if vim.api.nvim_get_mode().mode ~= 'n' then feed('<Esc>') end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name ~= '' and name:sub(1, #root) == root then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  vim.fn.delete(root, 'rf')
  if not ok then error(err) end
end

T.describe('nvim_api/editor.lua', function()
  T.it('returns visual selection text from the live buffer', function()
    with_root(function(root)
      local bufnr = vim.fn.bufadd(root .. '/a.lua')
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'alpha', 'bravo edited', 'charlie' })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      feed('v4l')

      local got = editor.selection(root)
      T.eq(got.file, 'a.lua')
      T.eq(got.mode, 'v')
      T.eq(got.modified, true)
      T.eq(got.selection.active, true)
      T.eq(got.selection.range.start_line, 2)
      T.eq(got.selection.range.start_col, 1)
      T.eq(got.selection.range.end_line, 2)
      T.eq(got.selection.range.end_col, 6)
      T.eq(got.selection.text, 'bravo')
    end)
  end)

  T.it('falls back to cursor context when no selection is active', function()
    with_root(function(root)
      local bufnr = vim.fn.bufadd(root .. '/a.lua')
      vim.fn.bufload(bufnr)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 1 })

      local got = editor.selection(root, { fallback = 'context', context_lines = 1 })
      T.eq(got.selection.active, false)
      T.eq(got.line, 2)
      T.eq(got.col, 2)
      T.eq(got.context.range.start_line, 1)
      T.eq(got.context.range.end_line, 3)
      T.eq(got.context.text, table.concat({ 'alpha', 'bravo', 'charlie' }, '\n'))
    end)
  end)
end)

T.summary()
