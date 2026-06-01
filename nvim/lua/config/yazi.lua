-- ~/.config/nvim/lua/yazi.lua
-- yazi integration using --chooser-file (no plugins required)
-- Requirements: yazi >= 0.2.5

local M = {}

function M.open(cwd)
  local tmp = vim.fn.tempname()
  cwd = cwd or vim.fn.expand('%:p:h')

  vim.cmd('botright vnew')
  local term_buf = vim.api.nvim_get_current_buf()
  local term_win = vim.api.nvim_get_current_win()

  -- ターミナルバッファの見た目を整える
  vim.wo[term_win].number         = false
  vim.wo[term_win].relativenumber = false
  vim.wo[term_win].signcolumn     = 'no'

  vim.fn.termopen(
    string.format('yazi --chooser-file %s %s', vim.fn.shellescape(tmp), vim.fn.shellescape(cwd)),
    {
      on_exit = function()
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(term_win) then
            vim.api.nvim_win_close(term_win, true)
          end
          if vim.api.nvim_buf_is_valid(term_buf) then
            vim.api.nvim_buf_delete(term_buf, { force = true })
          end

          if vim.fn.filereadable(tmp) == 0 then
            return
          end

          local files = vim.tbl_filter(
            function(f) return f ~= '' end,
            vim.fn.readfile(tmp)
          )
          vim.fn.delete(tmp)

          for i, file in ipairs(files) do
            if i == 1 then
              vim.cmd('edit ' .. vim.fn.fnameescape(file))
            else
              vim.cmd('badd ' .. vim.fn.fnameescape(file))
            end
          end
        end)
      end,
    }
  )

  -- termopen 後にスケジュールしてフォーカスとinsertモードを確実に適用
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(term_win) then
      vim.api.nvim_set_current_win(term_win)
      -- Esc でも閉じられるようにバッファローカルで設定
      vim.keymap.set('t', '<Esc>', function()
        if vim.api.nvim_win_is_valid(term_win) then
          vim.api.nvim_win_close(term_win, true)
        end
      end, { buffer = term_buf })
      vim.cmd('startinsert')
    end
  end)
end

vim.keymap.set('n', '<leader>y',  function() M.open() end,               { desc = 'yazi (current dir)' })
vim.keymap.set('n', '<leader>cw', function() M.open(vim.fn.getcwd()) end, { desc = 'yazi (cwd)' })

return M
