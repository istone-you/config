-- バッファ全内容をクリップボードへコピー

local function copy_all()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, '\n')
  vim.fn.setreg('"', text)
  if vim.g.clipboard ~= nil then
    vim.fn.setreg('+', text)
  end
  vim.notify(string.format('ファイル全体をコピー（%d 行）', #lines), vim.log.levels.INFO)
end

vim.keymap.set('n', '<leader>A', copy_all, { desc = 'ファイル全体をコピー' })

return { copy_all = copy_all }
