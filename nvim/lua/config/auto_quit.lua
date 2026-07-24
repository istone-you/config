-- 「実際の編集用ウィンドウ」が無くなり、explorerやgitパネルなどの
-- ユーティリティ系ウィンドウだけが残った場合は、そのままNeovimを終了する。
-- （:qを2回押さないと閉じられない問題への対処。nvim-treeなどの定番パターン）

-- ユーティリティ窓/実編集窓の判定は win_util に集約（explorer/gitパネル/フロート等）
local win_util = require('config.util.win_util')

vim.api.nvim_create_autocmd('WinClosed', {
  callback = function()
    vim.schedule(function()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      if #wins == 0 then return end
      -- 実編集ウィンドウが1つでも残っていれば終了しない
      for _, w in ipairs(wins) do
        if win_util.is_editor(w) then return end
      end
      if #vim.api.nvim_list_tabpages() > 1 then
        vim.cmd('tabclose')
      else
        -- 未保存があるとquitはE37で失敗する。quit_confirm経由で「保存/破棄/キャンセル」を促す
        local ok, qc = pcall(require, 'config.quit_confirm')
        if ok then qc.exit_or_prompt() else vim.cmd('quit') end
      end
    end)
  end,
})
