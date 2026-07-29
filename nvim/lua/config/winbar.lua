-- ファイルパス表示バー（winbar）
--
-- winbar はタブライン(showtabline)の直下・各ウィンドウの上端に出る1行。ここに開いて
-- いるファイルの「cwd 相対パス」を ' › ' 区切りのパンくずで出す。
--
-- なぜウィンドウローカル(vim.wo[win])に設定するか:
--   'winbar' はオプション値が非空だと %! の評価結果が空でも winbar 行が確保されてしまう。
--   グローバルに設定すると explorer / git_panel / ターミナル / スタート画面のような特殊
--   ウィンドウにも空バーが1行入り込む。そこで通常のファイルウィンドウだけに文字列を入れ、
--   それ以外は '' にして行ごと消す。

local M = {}

local function set_highlights()
  -- editor が透過なので bg は NONE。current/非current で明るさを変える（淡いグレー）
  vim.api.nvim_set_hl(0, 'WinBar',   { fg = '#8b8b8b', bg = 'NONE' })
  vim.api.nvim_set_hl(0, 'WinBarNC', { fg = '#6d6d6d', bg = 'NONE' })
end

-- winbar を出すウィンドウか（通常のファイルウィンドウのみ）
function M.should_show(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  -- フロートには出さない
  local cfg = vim.api.nvim_win_get_config(win)
  if cfg.relative and cfg.relative ~= '' then return false end
  local buf = vim.api.nvim_win_get_buf(win)
  -- explorer / git_panel / terminal / start画面 等は buftype が空でない
  if vim.bo[buf].buftype ~= '' then return false end
  -- 無名バッファ([No Name])は出さない
  if vim.api.nvim_buf_get_name(buf) == '' then return false end
  return true
end

-- バッファ番号 → winbar 文字列（cwd 相対パスのパンくず）
function M.build(buf)
  local fullpath = vim.api.nvim_buf_get_name(buf)
  local rel      = vim.fn.fnamemodify(fullpath, ':.') -- cwd 相対（cwd 外なら絶対パスのまま）
  -- パス中の % は statusline 書式扱いされるためエスケープ
  local safe = rel:gsub('%%', '%%%%')
  -- '/' を ' › ' に置き換えてパンくず表示にする
  local crumb = safe:gsub('/', ' › ')
  return ' ' .. crumb
end

-- ウィンドウに設定すべき winbar 値（対象外は ''）
function M.winbar_for(win)
  if not M.should_show(win) then return '' end
  return M.build(vim.api.nvim_win_get_buf(win))
end

-- 全ウィンドウの winbar を更新
function M.update_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    pcall(function()
      vim.wo[win].winbar = M.winbar_for(win)
    end)
  end
end

set_highlights()
vim.api.nvim_create_autocmd('ColorScheme', { callback = set_highlights })

local grp = vim.api.nvim_create_augroup('user_winbar', { clear = true })
vim.api.nvim_create_autocmd(
  { 'BufWinEnter', 'WinEnter', 'BufEnter', 'WinNew', 'TabEnter', 'DirChanged', 'TermOpen', 'FileType' },
  {
    group = grp,
    -- buftype/filetype がセットされ切ってから判定したいので schedule
    callback = function() vim.schedule(M.update_all) end,
  }
)

M.update_all()

return M
