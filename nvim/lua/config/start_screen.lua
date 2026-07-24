-- 起動時（ファイル未指定）に表示する編集不可のスタート画面。
-- 空の[No Name]編集バッファの代わりに、buftype=nofile・nomodifiable のスクラッチを
-- 出すことで「うっかり入力して未保存扱いになる」問題を無くす。中身は空。

local M = {}

-- 現在のウィンドウにスタート画面を表示する（起動時の[No Name]窓を差し替える想定）
function M.show()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = 'startscreen'
  require('config.hidden_cursor').mark_buffer(buf) -- カーソルを隠す
  vim.api.nvim_win_set_buf(win, buf)
  -- window-localオプションは触らない。ここで number/statusline 等を変えると、この窓に
  -- ファイルを開いた後もその設定が残ってしまう（行番号が消える等）。空バッファなので既定表示で問題ない。

  return buf
end

-- listed かつ名前付き（＝実ファイル）バッファの数
local function file_buffer_count()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.api.nvim_buf_get_name(b) ~= '' then n = n + 1 end
  end
  return n
end

local UTILITY_FT = { explorer = true, shortcuts = true, startscreen = true }

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    if vim.fn.argc() > 0 then return end -- ファイル指定ありなら出さない
    for _, a in ipairs(vim.v.argv) do
      if a == '-c' or a == '--cmd' or a:sub(1, 1) == '+' then return end
    end
    M.show()
  end,
})

-- ファイルを閉じて実ファイルが1つも無くなったら、空の編集画面ではなくスタート画面へ戻す
vim.api.nvim_create_autocmd('BufDelete', {
  callback = function()
    vim.schedule(function()
      if file_buffer_count() > 0 then return end
      local win = vim.api.nvim_get_current_win()
      if not vim.api.nvim_win_is_valid(win) then return end
      if vim.api.nvim_win_get_config(win).relative ~= '' then return end -- フロートは対象外
      local old = vim.api.nvim_win_get_buf(win)
      if UTILITY_FT[vim.bo[old].filetype] then return end -- 既にstartscreen/explorer等なら何もしない
      M.show()
      -- 差し替え前の空[No Name]バッファが残るので掃除する
      if vim.api.nvim_buf_is_valid(old) and vim.bo[old].buftype == ''
        and vim.api.nvim_buf_get_name(old) == '' and not vim.bo[old].modified then
        pcall(vim.api.nvim_buf_delete, old, { force = true })
      end
    end)
  end,
})

return M
