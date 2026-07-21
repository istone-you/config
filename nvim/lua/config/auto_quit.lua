-- 「実際の編集用ウィンドウ」が無くなり、ファイラーやgitパネルなどの
-- ユーティリティ系ウィンドウだけが残った場合は、そのままNeovimを終了する。
-- （:qを2回押さないと閉じられない問題への対処。nvim-treeなどの定番パターン）

-- filetype名で判定する対象（フローティングでない分割ウィンドウ用。右vsplitで開く系）
local UTILITY_FILETYPES = {
  explorer  = true,
  shortcuts = true,
}

local function is_utility_win(win)
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative ~= '' then
    -- フローティングウィンドウ（gitパネルの各パネル、確認/入力モーダル等）は
    -- すべてユーティリティ扱い
    return true
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return UTILITY_FILETYPES[vim.bo[buf].filetype] == true
end

vim.api.nvim_create_autocmd('WinClosed', {
  callback = function()
    vim.schedule(function()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      if #wins == 0 then return end
      for _, w in ipairs(wins) do
        if not is_utility_win(w) then return end
      end
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd('tabclose')
      else
        vim.cmd('quit')
      end
    end)
  end,
})
