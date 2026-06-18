-- パス付きコードコピー: 選択コードをファイルパス(行番号付き)とともにクリップボードへ

local ft_to_lang = {
  typescript      = 'ts',
  javascript      = 'js',
  typescriptreact = 'tsx',
  javascriptreact = 'jsx',
  go              = 'go',
  python          = 'python',
  lua             = 'lua',
  sh              = 'sh',
  bash            = 'bash',
  json            = 'json',
  yaml            = 'yaml',
  toml            = 'toml',
  markdown        = 'md',
  html            = 'html',
  css             = 'css',
  rust            = 'rs',
  ruby            = 'rb',
}

local function copy_code_with_path(start_line, end_line)
  local buf  = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)

  if file == '' then
    vim.notify('未保存のファイルです', vim.log.levels.WARN)
    return
  end

  local rel_path = file
  local root_out = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error == 0 and #root_out > 0 then
    rel_path = file:sub(#root_out[1] + 2)
  end

  local location = start_line == end_line
    and (rel_path .. ':' .. start_line)
    or  (rel_path .. ':' .. start_line .. '-' .. end_line)

  local code  = table.concat(vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false), '\n')
  local lang  = ft_to_lang[vim.bo[buf].filetype] or vim.bo[buf].filetype
  local result = location .. '\n```' .. lang .. '\n' .. code .. '\n```'

  vim.fn.setreg('+', result)
  vim.notify('コピー: ' .. location, vim.log.levels.INFO)
end

vim.keymap.set('n', '<leader>P', function()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  copy_code_with_path(line, line)
end, { desc = 'パス付きコードをコピー（現在行）' })

vim.keymap.set('v', '<leader>P', function()
  local s = vim.fn.line('v')
  local e = vim.fn.line('.')
  if s > e then s, e = e, s end
  copy_code_with_path(s, e)
  vim.schedule(function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  end)
end, { desc = 'パス付きコードをコピー（選択範囲）' })
