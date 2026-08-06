-- パネル各モジュールで共有する小さな表示ヘルパー（docker / ports パネルが使う）

local M = {}

--- 表示幅（全角込み）でwまで右詰めスペース埋めする。wを超える場合は切り詰める
function M.pad(s, w)
  s = s or ''
  local width = vim.fn.strdisplaywidth(s)
  if width > w then
    return M.truncate(s, w)
  end
  return s .. string.rep(' ', w - width)
end

--- 表示幅でwまで左をスペース埋めする（サイズのような数値列を右揃えにするため）
function M.rpad(s, w)
  s = s or ''
  local width = vim.fn.strdisplaywidth(s)
  if width >= w then return s end
  return string.rep(' ', w - width) .. s
end

--- 表示幅でwに収まるよう切り詰める（末尾は…にして省略を明示する）
function M.truncate(s, w)
  s = s or ''
  if vim.fn.strdisplaywidth(s) <= w then return s end
  local out = ''
  for _, ch in ipairs(vim.fn.split(s, '\\zs')) do
    if vim.fn.strdisplaywidth(out .. ch) > w - 1 then break end
    out = out .. ch
  end
  return out .. '…'
end

--- コンテナ状態→アイコンとハイライト。配色はgitパネルのCI状態表示と共有していて、
--- 緑=正常稼働 / 黄=過渡状態 / 赤=停止 という意味付けも揃えている
local STATE = {
  running    = { '●', 'GitPanelCheckOk' },
  paused     = { '◐', 'GitPanelCheckPending' },
  restarting = { '◌', 'GitPanelCheckPending' },
  created    = { '○', 'GitPanelCheckPending' },
  exited     = { '○', 'GitPanelCheckFail' },
  dead       = { '✗', 'GitPanelCheckFail' },
}

function M.state_icon(state)
  local e = STATE[state or ''] or { '○', 'GitPanelDim' }
  return e[1], e[2]
end

return M
