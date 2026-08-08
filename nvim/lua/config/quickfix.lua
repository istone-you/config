-- quickfix パネルの開閉。
--
-- quickfix は :copen で開けばそのまま j/k + Enter で辿れる「パネル」なので、移動専用の
-- キー(vim-unimpaired の ]q 相当)は足していない。足りないのは開閉だけなので、
-- problems(Space p) や todo_tree(Space T) と同じ感覚で出し入れできるようにする。
--
-- 動機は nvim_api で、AI が調査結果(移行漏れの一覧など)を書き込むと自動で開く。
-- 開きっぱなしを閉じる手段と、閉じた後に開き直す手段が無いと単に邪魔になる。
-- :vimgrep や :make の結果にも同じキーが効く。

local M = {}
local win_util = require('config.util.win_util')

--- quickfix ウィンドウ(location list ではない方)を探す。
function M.win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == 'quickfix' then
      -- location list も buftype は quickfix。getwininfo でしか区別できない
      local info = vim.fn.getwininfo(w)[1]
      if info and info.quickfix == 1 and info.loclist == 0 then return w end
    end
  end
  return nil
end

function M.is_open()
  return M.win() ~= nil
end

function M.size()
  return vim.fn.getqflist({ size = 1 }).size or 0
end

--- 開く。opts.focus が真ならカーソルも移す(既定は元のウィンドウに残す)。
function M.open(opts)
  opts = opts or {}
  local existing = M.win()
  if existing then
    if opts.focus then vim.api.nvim_set_current_win(existing) end
    return existing
  end
  local cur = vim.api.nvim_get_current_win()
  vim.cmd('botright copen')
  local win = M.win()
  -- 実編集ウィンドウとして数えられないよう明示的に印を付ける(win_util の推奨手順)。
  -- SIDEBAR_FT にも qf を入れてあるが、両方やるのが作法。
  if win then win_util.mark_sidebar(win, vim.api.nvim_win_get_buf(win)) end
  if not opts.focus and vim.api.nvim_win_is_valid(cur) then
    vim.api.nvim_set_current_win(cur)
  end
  return win
end

--- 閉じる。閉じたら true、もともと開いていなければ false。
function M.close()
  if not M.is_open() then return false end
  vim.cmd('cclose')
  return true
end

--- トグル。開いていれば閉じ、閉じていれば開いてフォーカスする。
--- 空の quickfix を開いても何も見えないので、その場合は理由だけ知らせる。
function M.toggle()
  if M.close() then return false end
  if M.size() == 0 then
    vim.notify('quickfix は空です', vim.log.levels.INFO, { title = 'quickfix' })
    return false
  end
  M.open({ focus = true })
  return true
end

vim.keymap.set('n', '<leader>l', function() M.toggle() end, {
  desc = 'quickfix パネルの表示/非表示（AI が書き込んだ調査結果もここに出る）',
})

return M
