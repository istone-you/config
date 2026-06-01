-- ~/.config/nvim/lua/config/lazygit.lua
-- lazygit integration (no plugins required)

local M = {}

function M.open()
  local width  = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines   * 0.9)
  local col    = math.floor((vim.o.columns - width)  / 2)
  local row    = math.floor((vim.o.lines   - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width    = width,
    height   = height,
    col      = col,
    row      = row,
    style    = 'minimal',
    border   = 'single',
  })

  vim.fn.termopen('lazygit', {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end)
    end,
  })

  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.cmd('startinsert')
    end
  end)
end

vim.keymap.set('n', '<leader>g', function() M.open() end, { desc = 'Open lazygit' })

return M
