-- タブラインと同じ対象（listed・名前付き・非 terminal）だけを巡回する。
-- 空の[No Name]はタブに出ないのに :bnext では挟まるため、ここ経由に揃える。

local M = {}

function M.list()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buflisted
      and vim.api.nvim_buf_is_valid(b)
      and vim.bo[b].buftype ~= 'terminal'
      and vim.api.nvim_buf_get_name(b) ~= ''
  end, vim.api.nvim_list_bufs())
end

local function cycle(dir)
  local bufs = M.list()
  if #bufs == 0 then return end
  local cur = vim.api.nvim_get_current_buf()
  local idx
  for i, b in ipairs(bufs) do
    if b == cur then
      idx = i
      break
    end
  end
  local win_util = require('config.util.win_util')
  if not idx then
    win_util.open_buf(dir > 0 and bufs[1] or bufs[#bufs])
    return
  end
  local next_idx = ((idx - 1 + dir) % #bufs) + 1
  win_util.open_buf(bufs[next_idx])
end

function M.next() cycle(1) end
function M.prev() cycle(-1) end

return M
