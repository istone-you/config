-- herdr 連携: nvim から新しい herdr タブを開き、コーディングエージェントを起動する。
-- 手順は herdr/config.toml の prefix+h と同じ (tab create → pane run → tab focus)。
local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'herdr' })
end

--- 新しい herdr タブを作り、その root pane で cmd を実行してフォーカスする。
function M.open_agent_tab(cmd, label)
  if vim.env.HERDR_ENV ~= '1' then
    notify('herdr の中で実行してください (HERDR_ENV=1)', vim.log.levels.WARN)
    return
  end
  if vim.fn.executable('herdr') ~= 1 then
    notify('herdr コマンドが見つかりません', vim.log.levels.ERROR)
    return
  end

  local created = vim
    .system({ 'herdr', 'tab', 'create', '--label', label, '--cwd', vim.fn.getcwd(), '--no-focus' }, { text = true })
    :wait()
  if created.code ~= 0 then
    notify('herdr tab create に失敗しました: ' .. (created.stderr or ''), vim.log.levels.ERROR)
    return
  end

  -- 応答 JSON から pane_id / tab_id を防御的に取り出す(想定外なら中断)
  local ok, data = pcall(vim.json.decode, created.stdout or '')
  local result = (ok and type(data) == 'table') and data.result or nil
  local pane_id = result and result.root_pane and result.root_pane.pane_id
  local tab_id = result and result.tab and result.tab.tab_id
  if type(pane_id) ~= 'string' or type(tab_id) ~= 'string' then
    notify('herdr tab create の応答を解釈できませんでした', vim.log.levels.ERROR)
    return
  end

  local ran = vim.system({ 'herdr', 'pane', 'run', pane_id, cmd }, { text = true }):wait()
  if ran.code ~= 0 then
    notify('herdr pane run に失敗しました: ' .. (ran.stderr or ''), vim.log.levels.ERROR)
    return
  end
  vim.system({ 'herdr', 'tab', 'focus', tab_id }):wait()
end

-- 2キー目: c=claude / x=codeX / a=agent(cursor-cli)
local agents = {
  { key = '<leader>ac', cmd = 'claude', label = 'claude' },
  { key = '<leader>ax', cmd = 'codex', label = 'codex' },
  { key = '<leader>aa', cmd = 'agent', label = 'agent' },
}

for _, a in ipairs(agents) do
  vim.keymap.set('n', a.key, function()
    M.open_agent_tab(a.cmd, a.label)
  end, { desc = 'herdr: 新しいタブで ' .. a.cmd .. ' を起動' })
end

M._private = {
  agents = agents,
  open_agent_tab = M.open_agent_tab,
}

return M
