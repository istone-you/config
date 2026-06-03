local preview_win = nil
local preview_buf = nil

local function is_open()
  return preview_win ~= nil and vim.api.nvim_win_is_valid(preview_win)
end

local function close()
  if is_open() then
    vim.api.nvim_win_close(preview_win, true)
  end
  preview_win = nil
  preview_buf = nil
end

local function render(filepath)
  local new_buf = vim.api.nvim_create_buf(false, true)

  if is_open() then
    local old_buf = preview_buf
    vim.api.nvim_win_set_buf(preview_win, new_buf)
    if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
      pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
    end
  else
    local from_win = vim.api.nvim_get_current_win()
    local old_splitright = vim.o.splitright
    vim.o.splitright = true
    vim.cmd('vsplit')
    vim.o.splitright = old_splitright
    preview_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(preview_win, new_buf)
    vim.wo[preview_win].number = false
    vim.wo[preview_win].relativenumber = false
    vim.wo[preview_win].wrap = true
    vim.wo[preview_win].signcolumn = 'no'
    vim.api.nvim_set_current_win(from_win)
  end

  preview_buf = new_buf

  vim.api.nvim_win_call(preview_win, function()
    vim.fn.termopen({ 'bun', filepath })
  end)
end

local function toggle()
  if is_open() then
    close()
    return
  end
  local ft = vim.bo.filetype
  if ft ~= 'markdown' then
    vim.notify('markdown ファイルではありません', vim.log.levels.WARN)
    return
  end
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == '' then
    vim.notify('先にファイルを保存してください', vim.log.levels.WARN)
    return
  end
  render(filepath)
end

local function refresh()
  if not is_open() then return end
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == '' then return end
  render(filepath)
end

vim.keymap.set('n', '<leader>md', toggle, { desc = 'Toggle markdown preview' })

vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = { '*.md', '*.markdown' },
  callback = refresh,
})

vim.api.nvim_create_autocmd('WinClosed', {
  callback = function(args)
    if tonumber(args.match) == preview_win then
      preview_win = nil
      preview_buf = nil
    end
  end,
})
