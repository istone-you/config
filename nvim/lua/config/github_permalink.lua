-- GitHub パーマリンク生成・コピー

local function get_github_permalink(start_line, end_line)
  local buf  = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)

  if file == '' then
    vim.notify('未保存のファイルです', vim.log.levels.WARN)
    return nil
  end

  local remote_out = vim.fn.systemlist('git remote get-url origin 2>/dev/null')
  if vim.v.shell_error ~= 0 or #remote_out == 0 then
    vim.notify('git remote origin が見つかりません', vim.log.levels.WARN)
    return nil
  end

  local remote = remote_out[1]
  -- 認証情報を除去: https://user:token@github.com/... → https://github.com/...
  remote = remote:gsub('^(https?://)([^@]+@)', '%1')
  -- SSH → HTTPS 変換: git@github.com:owner/repo.git → https://github.com/owner/repo
  local owner_repo = remote:match('^git@github%.com:(.-)%.git$')
                  or remote:match('^git@github%.com:(.+)$')
  local base_url
  if owner_repo then
    base_url = 'https://github.com/' .. owner_repo
  else
    base_url = remote:gsub('%.git$', '')
  end

  local sha_out = vim.fn.systemlist('git rev-parse HEAD 2>/dev/null')
  if vim.v.shell_error ~= 0 or #sha_out == 0 then
    vim.notify('コミット SHA の取得に失敗しました', vim.log.levels.WARN)
    return nil
  end
  local sha = sha_out[1]

  local root_out = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error ~= 0 or #root_out == 0 then
    vim.notify('git ルートの取得に失敗しました', vim.log.levels.WARN)
    return nil
  end
  local root = root_out[1]

  local rel_path = file:sub(#root + 2)
  local anchor = start_line == end_line
    and ('#L' .. start_line)
    or  ('#L' .. start_line .. '-L' .. end_line)

  return base_url .. '/blob/' .. sha .. '/' .. rel_path .. anchor
end

-- ノーマルモード: 現在行のパーマリンク
vim.keymap.set('n', '<leader>G', function()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local url = get_github_permalink(line, line)
  if url then
    vim.fn.setreg('+', url)
    vim.notify(url, vim.log.levels.INFO)
  end
end, { desc = 'GitHubパーマリンクをコピー（現在行）' })

-- ビジュアルモード: 選択行範囲のパーマリンク
vim.keymap.set('v', '<leader>G', function()
  local s = vim.fn.line('v')
  local e = vim.fn.line('.')
  if s > e then s, e = e, s end
  local url = get_github_permalink(s, e)
  if url then
    vim.fn.setreg('+', url)
    vim.schedule(function()
      vim.notify(url, vim.log.levels.INFO)
    end)
  end
end, { desc = 'GitHubパーマリンクをコピー（選択行）' })
