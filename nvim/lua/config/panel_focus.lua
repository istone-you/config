-- パネルのフォーカス表示（非フォーカス時は選択強調を消す）
--
-- explorer / git_panel などリスト選択を持つパネルは cursorline で「今の選択行」を
-- 出している。だがフォーカスが外れても出しっぱなしだと、どのパネル/窓にフォーカスが
-- あるのか分からない（lazygit も非フォーカスのパネルは選択が沈む）。
--
-- そこで「パネル窓はフォーカスを失ったら cursorline を消し、取り戻したら元に戻す」。
--
-- 重要: 通常エディタ窓(buftype=='')には一切触れない。エディタに行全体の帯
-- (cursorline)を足すと、元々の文字単位のカーソル表示と違って違和感が出るため。
-- エディタ窓間のフォーカス差は winbar(WinBar/WinBarNC の明暗)で分かる。
-- グローバルの CursorLine ハイライトも変更しない（各パネルは winhighlight で
-- CursorLine を自前グループへ再マップしているため、ここは option の ON/OFF のみ扱う）。

local M = {}

-- 非フォーカス化する直前の cursorline 値（復元用）。win -> bool
local saved = {}

-- フォーカスで選択を出し入れする「パネル窓」か
--   ・フロート / terminal は対象外（各自が管理・モーダル前提）
--   ・通常エディタ窓(buftype=='')も対象外（行帯を出さない）
--   → 残る buftype(nofile 等: explorer/git_panel/quickfix 等)だけが対象
function M.is_panel_win(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= '' then return false end
  local bt = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
  return bt ~= '' and bt ~= 'terminal'
end

-- パネルがフォーカスを失うとき: 現在の cursorline を退避して消す
function M.on_leave(win)
  win = win or vim.api.nvim_get_current_win()
  if not M.is_panel_win(win) then return end
  saved[win] = vim.wo[win].cursorline
  vim.wo[win].cursorline = false
end

-- パネルがフォーカスを得るとき: 退避してあった値を復元
--   （退避が無い＝開いた直後などはパネル自身の設定に任せる）
function M.on_enter(win)
  win = win or vim.api.nvim_get_current_win()
  if not M.is_panel_win(win) then return end
  if saved[win] ~= nil then
    vim.wo[win].cursorline = saved[win]
    saved[win] = nil
  end
end

local grp = vim.api.nvim_create_augroup('user_panel_focus', { clear = true })
vim.api.nvim_create_autocmd({ 'WinEnter', 'BufWinEnter' }, { group = grp, callback = function() M.on_enter() end })
vim.api.nvim_create_autocmd('WinLeave', { group = grp, callback = function() M.on_leave() end })
vim.api.nvim_create_autocmd('WinClosed', {
  group = grp,
  callback = function(ev) saved[tonumber(ev.match)] = nil end,
})

return M
