-- 右ペインのサブタブ（lazydockerの Logs / Stats / Env / Config / Top 相当）。
-- lazydocker は右側のビューを `[` / `]` で切り替え、今どれを見ているかを枠のタイトルに出す。
-- ここでも同じ操作・同じ見せ方にする（タイトルの配色はタブバーと同じ GitPanelTab* を使うので
-- gitパネルのタブバーと完全に同じ見た目になる）。

local M = {}

local Tabs = {}
Tabs.__index = Tabs

--- names: { 'Logs', 'Stats', 'Config', 'Top' }
function M.new(names)
  return setmetatable({ names = names, idx = 1 }, Tabs)
end

function Tabs:current()
  return self.names[self.idx]
end

function Tabs:move(delta)
  self.idx = self.idx + delta
  if self.idx < 1 then self.idx = #self.names end
  if self.idx > #self.names then self.idx = 1 end
  return self:current()
end

--- 右ペインの枠へタブを描く。クリックされたらそのタブへ切り替えて描き直す
--- （`[`/`]` キーと同じ動作。左のタブバーがクリックで切り替わるのと揃えている）
--- show()は「現在のタブで右ペインを描き直す」関数
function Tabs:render(ctx, show)
  ctx.set_right_tabs(self.names, self.idx, function(i)
    self.idx = i
    show()
  end)
end

--- パネルモジュール共通のキー割り当てを作る。show()は「現在のタブで右ペインを描き直す」関数
function M.keymaps(tabs, show)
  return {
    ['['] = function() tabs:move(-1); show() end,
    [']'] = function() tabs:move(1); show() end,
  }
end

return M
