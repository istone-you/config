-- VSCode GitLens風のインラインgit blame表示

local ns    = vim.api.nvim_create_namespace('git_blame')
local timer = nil

local function clear()
  vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

local function show()
  local buf  = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]

  if file == '' or vim.bo[buf].buftype ~= '' then return end

  vim.fn.jobstart(
    { 'git', 'blame', '--porcelain', '-L', line .. ',' .. line, '--', file },
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not data or #data < 2 then return end

        local commit = data[1] and data[1]:match('^(%x+)')
        if not commit then return end

        local author, date, summary = 'Unknown', '', ''

        -- 未コミットの変更（ゼロハッシュ）
        if commit:match('^0+$') then
          author  = 'You'
          summary = 'Uncommitted changes'
        else
          for _, l in ipairs(data) do
            author  = l:match('^author (.+)')  or author
            summary = l:match('^summary (.+)') or summary
            local t = l:match('^author%-time (%d+)')
            if t then date = os.date('%Y/%m/%d', tonumber(t)) end
          end
        end

        local text = string.format('   %s%s • %s',
          author,
          date ~= '' and (', ' .. date) or '',
          summary
        )

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          if vim.api.nvim_get_current_buf() ~= buf then return end
          if vim.api.nvim_win_get_cursor(0)[1] ~= line then return end

          vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
          vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
            virt_text     = { { text, 'Comment' } },
            virt_text_pos = 'eol',
          })
        end)
      end,
    }
  )
end

local function on_moved()
  clear()
  if timer then timer:stop(); timer = nil end
  timer = vim.defer_fn(show, 250)
end

vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, { callback = on_moved })
vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufLeave' }, { callback = clear })
