-- ウィンドウ種別の共通判定。「実編集ウィンドウ」か、explorer/gitパネル等の
-- ユーティリティ窓かを一箇所で判定する（auto_quit / quit_confirm / rg_fzf 等で共用）。

local M = {}

-- サイドバー等、実ファイル編集ではないウィンドウの filetype
M.SIDEBAR_FT = { explorer = true, shortcuts = true }

function M.is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ''
end

-- 実編集ウィンドウか（フロート・explorer/shortcuts は除外。startscreenは主窓なので含む）
function M.is_editor(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  if M.is_float(win) then return false end
  return not M.SIDEBAR_FT[vim.bo[vim.api.nvim_win_get_buf(win)].filetype]
end

-- 実編集ウィンドウへフォーカスを移す（既に実編集窓なら何もしない）。
-- 見つからなければ現在の窓のまま。
function M.focus_editor()
  if M.is_editor(vim.api.nvim_get_current_win()) then return end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if M.is_editor(w) then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
end

return M
