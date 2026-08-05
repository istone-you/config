local M = {}

local function current_kind()
  local path = vim.api.nvim_buf_get_name(0)
  local ext = vim.fn.fnamemodify(path, ':e'):lower()
  local ft = vim.bo.filetype

  if ext == 'html' or ext == 'htm' or ft == 'html' then
    return 'html'
  end
  if ext == 'md' or ext == 'markdown' or ft == 'markdown' then
    return 'markdown'
  end
end

function M.open()
  local kind = current_kind()
  if kind == 'html' then
    require('config.browser.html').open()
    return
  end
  if kind == 'markdown' then
    require('config.browser.markdown').open()
    return
  end
  vim.notify('HTML / Markdown ファイルではありません', vim.log.levels.WARN, { title = 'Browser Preview' })
end

vim.api.nvim_create_user_command('BrowserOpen', function() M.open() end, {
  desc = 'Open current HTML or Markdown file in default browser',
})

vim.keymap.set('n', '<leader>o', M.open, {
  desc = 'Open current HTML/Markdown file in default browser',
})

M._private = {
  current_kind = current_kind,
}

return M
