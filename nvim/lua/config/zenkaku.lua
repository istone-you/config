-- 全角スペース（U+3000）を可視化する（VS Code の zenkaku 拡張相当）。
-- ウィンドウごとに matchadd でハイライトする。編集バッファのみ対象。

local ZENKAKU = '　' -- U+3000 IDEOGRAPHIC SPACE
local MATCH_VAR = 'zenkaku_match_id'

local function setup_hl()
  -- 灰色の背景で「そこに空白がある」と分かるようにする（文字色はそのまま）
  vim.api.nvim_set_hl(0, 'ZenkakuSpace', { bg = '#555555' })
end

local function clear_win(win)
  win = win or 0
  if not vim.api.nvim_win_is_valid(win) then return end
  local id = vim.w[win][MATCH_VAR]
  if id then
    pcall(vim.fn.matchdelete, id, win)
    vim.w[win][MATCH_VAR] = nil
  end
end

local function apply(win)
  win = win or 0
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- terminal / prompt / パネル類は対象外
  if vim.bo[buf].buftype ~= '' then
    clear_win(win)
    return
  end
  clear_win(win)
  -- matchadd はウィンドウローカル。第3引数で優先度、第4引数で対象窓を指定
  vim.w[win][MATCH_VAR] = vim.fn.matchadd('ZenkakuSpace', ZENKAKU, 10, -1, { window = win })
end

local function on_win()
  apply(vim.api.nvim_get_current_win())
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })
vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'TermOpen' }, {
  callback = on_win,
})
-- 起動直後の最初の窓にも付ける
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      apply(w)
    end
  end,
})

-- テスト用
return {
  _apply = apply,
  _clear = clear_win,
  _zenkaku = ZENKAKU,
  _match_var = MATCH_VAR,
}
