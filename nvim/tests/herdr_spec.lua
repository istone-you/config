local T = dofile(TESTS_DIR .. '/helpers.lua')
local herdr = require('config.herdr')
local P = herdr._private

-- vim.system / vim.notify / vim.fn.executable を差し替えて、実際の herdr 呼び出しを
-- せずに「どんなコマンドを、どの順で発行したか」だけを観測する
local function with_stubs(fn)
  local orig_system = vim.system
  local orig_notify = vim.notify
  local orig_exec = vim.fn.executable
  local calls, notifies = {}, {}
  vim.fn.executable = function() return 1 end
  vim.notify = function(msg, level) notifies[#notifies + 1] = { msg = msg, level = level } end
  vim.system = function(cmd)
    calls[#calls + 1] = cmd
    return {
      wait = function()
        if cmd[2] == 'tab' and cmd[3] == 'create' then
          return {
            code = 0,
            stdout = vim.json.encode({
              result = { root_pane = { pane_id = 'P1' }, tab = { tab_id = 'T1' } },
            }),
          }
        end
        return { code = 0, stdout = '' }
      end,
    }
  end
  local ok, err = pcall(fn, calls, notifies)
  vim.system = orig_system
  vim.notify = orig_notify
  vim.fn.executable = orig_exec
  if not ok then error(err) end
end

T.describe('herdr.lua: agent tab shortcuts', function()
  T.it('creates a tab, runs the command in its pane, then focuses the tab', function()
    local saved = vim.env.HERDR_ENV
    vim.env.HERDR_ENV = '1'
    with_stubs(function(calls)
      P.open_agent_tab('claude', 'claude')
      T.eq(calls[1][1], 'herdr')
      T.eq(calls[1][2], 'tab')
      T.eq(calls[1][3], 'create')
      T.contains(calls[1], 'claude') -- --label claude
      T.eq(calls[2], { 'herdr', 'pane', 'run', 'P1', 'claude' })
      T.eq(calls[3], { 'herdr', 'tab', 'focus', 'T1' })
    end)
    vim.env.HERDR_ENV = saved
  end)

  T.it('warns and does nothing when not inside herdr (HERDR_ENV != 1)', function()
    local saved = vim.env.HERDR_ENV
    vim.env.HERDR_ENV = nil
    with_stubs(function(calls, notifies)
      P.open_agent_tab('claude', 'claude')
      T.eq(#calls, 0, 'must not call herdr outside herdr')
      T.ok(#notifies >= 1, 'should warn the user')
    end)
    vim.env.HERDR_ENV = saved
  end)

  T.it('aborts with an error notify when the tab-create response is unparseable', function()
    local saved = vim.env.HERDR_ENV
    vim.env.HERDR_ENV = '1'
    local orig_system = vim.system
    local orig_notify = vim.notify
    local orig_exec = vim.fn.executable
    local calls, notifies = {}, {}
    vim.fn.executable = function() return 1 end
    vim.notify = function(msg, level) notifies[#notifies + 1] = { msg = msg, level = level } end
    vim.system = function(cmd)
      calls[#calls + 1] = cmd
      return { wait = function() return { code = 0, stdout = 'not json' } end }
    end
    P.open_agent_tab('claude', 'claude')
    vim.system = orig_system
    vim.notify = orig_notify
    vim.fn.executable = orig_exec
    vim.env.HERDR_ENV = saved
    T.eq(#calls, 1, 'only tab create should have run')
    T.ok(#notifies >= 1, 'should notify the parse failure')
  end)

  T.it('binds all three agents under the <leader>a namespace', function()
    T.eq(#P.agents, 3)
    local keys = {}
    for _, a in ipairs(P.agents) do keys[a.cmd] = a.key end
    T.eq(keys.claude, '<leader>ac')
    T.eq(keys.codex, '<leader>ax')
    T.eq(keys.agent, '<leader>aa')
  end)
end)

T.summary()
