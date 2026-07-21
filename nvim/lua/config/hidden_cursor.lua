-- 一覧選択系パネル（ファイラー/gitパネルなど）ではテキストカーソルを非表示にする。
-- yazi/lazygitと同様、カーソル行のハイライトだけで現在地を示す。
-- guicursorはグローバルオプションのため、対象バッファへの出入りで退避/復元する。

local M = {}

local default_guicursor = vim.o.guicursor
local hidden = false

local function setup_hl()
  vim.api.nvim_set_hl(0, 'HiddenCursor', { blend = 100, nocombine = true })
end
setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

local function apply()
  local want_hidden = vim.b.hide_cursor == true
  if want_hidden and not hidden then
    hidden = true
    vim.o.guicursor = 'a:HiddenCursor'
  elseif not want_hidden and hidden then
    hidden = false
    vim.o.guicursor = default_guicursor
  end
end

vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, { callback = apply })

function M.mark_buffer(buf)
  vim.b[buf].hide_cursor = true
  -- VimEnterなど他のautocmd内で開かれた場合、ネストしたBufEnter/WinEnterが
  -- 発火しないことがあるため、既にカレントバッファなら即時反映する
  if buf == vim.api.nvim_get_current_buf() then
    apply()
  end
end

return M
