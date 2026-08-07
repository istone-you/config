-- Diff Review: 作業ツリーの変更をブラウザ(difit 風)で開き、その差分上で AI と
-- 双方向にコメントをやりとりする機能(hunk 参考)。
--
--   :DiffReview [port]   / <leader>R  … レビューを開く(browser と同じく毎回ポートを選択)
--   :DiffReviewClose                  … サーバを止める
--
-- 表示は browser/*.lua と同じローカル HTTP サーバ方式。AI はセッションレジストリ
-- (registry.lua)から port を引き、localhost:port の JSON API 経由でコメントを読み書きする。
-- ブラウザ画面は /__version ポーリングで、AI が足したコメントを自動反映する。

local M = {}
local server = require('config.diff_review.server')
local diff = require('config.diff_review.diff')
local registry = require('config.diff_review.registry')

local augrp = vim.api.nvim_create_augroup('diff_review', { clear = true })
local exiting = false

local state = { root = nil, port = nil }

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'Diff Review' })
end

-- browser(html/markdown)と同じく、ポートは毎回選択制。既定値は持たない。
local function parse_port(input)
  input = vim.trim(tostring(input or ''))
  if not input:match('^%d+$') then return nil, 'port must be a number' end
  local port = tonumber(input)
  if not port or port < 1 or port > 65535 then
    return nil, 'port must be between 1 and 65535'
  end
  return port
end

-- カレントバッファのファイル(無ければ cwd)から git のトップレベルを解決する。
local function resolve_root(cb)
  local name = vim.api.nvim_buf_get_name(0)
  local dir = name ~= '' and vim.fn.fnamemodify(name, ':p:h') or vim.fn.getcwd()
  vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 or not res.stdout or vim.trim(res.stdout) == '' then
        cb(nil)
        return
      end
      cb(vim.fs.normalize(vim.trim(res.stdout)))
    end)
  end)
end

--- 差分(all/unstaged/staged の 3 ビュー)を作り直してサーバへ反映する(= /__version が進みブラウザが再取得する)。
function M.refresh(opts)
  opts = opts or {}
  if not state.root then return end
  diff.build_views(state.root, function(views)
    server.set_diff(views)
    if not opts.silent then
      notify('差分を更新しました' .. (server.server_url() and (': ' .. server.server_url()) or ''))
    end
  end)
end

function M.open_on_port(port)
  resolve_root(function(root)
    if not root then
      notify('git リポジトリが見つかりません', vim.log.levels.ERROR)
      return
    end
    state.root = root
    server.set_session({ repo_root = root, source = 'worktree' })
    diff.build_views(root, function(views)
      server.set_diff(views)
      local ok, err = server.start(port)
      if not ok then
        notify(err or 'failed to start diff review server', vim.log.levels.ERROR)
        return
      end
      state.port = port
      registry.register(root, port)
      local url = server.server_url()
      require('config.browser.util').open_url(url, {
        fallback_message = 'Diff Review URL: ',
        namespace = 'diff_review',
        title = 'Diff Review',
      })
      notify('Diff Review: ' .. url)
    end)
  end)
end

function M.open()
  if server.is_running() then
    -- 既に起動中なら差分を更新して同じ URL を開き直す
    M.refresh({ silent = true })
    local url = server.server_url()
    if url then
      require('config.browser.util').open_url(url, {
        fallback_message = 'Diff Review URL: ',
        namespace = 'diff_review',
        title = 'Diff Review',
      })
      notify('Diff Review: ' .. url)
    end
    return
  end
  vim.ui.input({ prompt = 'Diff Review port: ' }, function(input)
    if input == nil then return end
    local port, err = parse_port(input)
    if not port then
      notify(err, vim.log.levels.ERROR)
      return
    end
    M.open_on_port(port)
  end)
end

function M.close(opts)
  opts = opts or {}
  local port = state.port
  local was_running = server.is_running()
  server.stop()
  if port then registry.unregister(port) end
  state.port = nil
  if was_running and not opts.silent and not exiting then
    notify('Diff Review を停止しました')
  end
end

-- root 配下のファイルを保存したら差分を作り直す(エディタ外の編集は git 差分に出た時点で
-- 反映される。ブラウザ側ポーリングで拾えるよう version を進める)。
vim.api.nvim_create_autocmd('BufWritePost', {
  group = augrp,
  callback = function(ev)
    if not server.is_running() or not state.root then return end
    local name = vim.api.nvim_buf_get_name(ev.buf)
    if name == '' then return end
    local path = vim.fs.normalize(vim.fn.fnamemodify(name, ':p'))
    if path:sub(1, #state.root) == state.root then
      M.refresh({ silent = true })
    end
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = augrp,
  callback = function()
    exiting = true
    M.close({ silent = true })
  end,
})

vim.api.nvim_create_user_command('DiffReview', function(cmd_opts)
  if cmd_opts.args ~= '' then
    local port, err = parse_port(cmd_opts.args)
    if not port then
      notify(err, vim.log.levels.ERROR)
      return
    end
    M.open_on_port(port)
  else
    M.open()
  end
end, { nargs = '?', desc = '差分レビューをブラウザで開く（AIとコメントでやりとり）' })

vim.api.nvim_create_user_command('DiffReviewClose', function() M.close() end, {
  desc = '差分レビューのサーバを停止する',
})

vim.keymap.set('n', '<leader>R', function() M.open() end, {
  desc = '差分レビューをブラウザで開く（AIとコメントでやりとり）',
})

M._private = {
  parse_port = parse_port,
  resolve_root = resolve_root,
  state = state,
}

return M
