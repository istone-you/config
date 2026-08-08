-- quickfix への書き込み / 読み出し。
--
-- diff review が「人間の書いたコメントを AI に読ませる」方向だったのに対して、こちらは
-- 「AI の調査結果を人間の作業面に置く」方向。移行漏れの一覧のようなものを quickfix へ流し込むと、
-- 人間は ]q で巡回して自分で直せる。チャットに貼られたパスを手で開き直す作業が消える。
--
-- 直接編集させるのではなく quickfix に置くだけにしているのは意図的で、何を直すかの判断を
-- 人間に残すため。

local M = {}
local util = require('config.nvim_api.util')

-- severity 名 -> quickfix の type 欄(E/W/I/N)。ここが埋まっていると :copen の表示で色が付く。
local TYPE_OF = {
  error = 'E', err = 'E', e = 'E',
  warn = 'W', warning = 'W', w = 'W',
  info = 'I', information = 'I', i = 'I',
  hint = 'N', note = 'N', n = 'N',
}

--- API の items を quickfix の items へ。空要素(file 欠落)は捨てる。
function M.build_items(items, root)
  local out = {}
  for _, it in ipairs(items or {}) do
    if type(it) == 'table' and it.file and it.file ~= '' then
      local abs = util.abs_path(it.file, root)
      out[#out + 1] = {
        filename = abs,
        lnum = util.to_number(it.line, 1),
        col = util.to_number(it.col, 1),
        text = tostring(it.text or ''),
        type = TYPE_OF[tostring(it.severity or ''):lower()] or '',
      }
    end
  end
  return out
end

--- quickfix を丸ごと置き換える。open=true なら quickfix ウィンドウも開く。
---@return integer 設定した件数
function M.set(opts, root)
  opts = opts or {}
  local items = M.build_items(opts.items, root)
  vim.fn.setqflist({}, ' ', {
    title = tostring(opts.title or 'AI'),
    items = items,
  })
  if util.truthy(opts.open, true) and #items > 0 then
    -- 人間に見せるのが目的なので既定で開く。カーソルは元のウィンドウに残す。
    -- 邪魔になったら Space l で閉じられる(config.quickfix)。
    pcall(function() require('config.quickfix').open({ focus = false }) end)
  end
  return #items
end

--- いまの quickfix を API 用の形で返す。
function M.get(root)
  local qf = vim.fn.getqflist({ items = 1, title = 1 })
  local items = {}
  for _, it in ipairs(qf.items or {}) do
    local name = ''
    if it.bufnr and it.bufnr > 0 and vim.api.nvim_buf_is_valid(it.bufnr) then
      name = vim.api.nvim_buf_get_name(it.bufnr)
    end
    items[#items + 1] = {
      file = name ~= '' and util.rel_path(name, root) or vim.NIL,
      line = it.lnum,
      col = it.col,
      text = it.text or '',
      type = it.type ~= '' and it.type or vim.NIL,
    }
  end
  return { title = qf.title or '', items = items, size = #items }
end

--- quickfix を空にして、開いていれば閉じる。
function M.clear()
  vim.fn.setqflist({}, 'r', { title = '', items = {} })
  pcall(function() require('config.quickfix').close() end)
end

return M
