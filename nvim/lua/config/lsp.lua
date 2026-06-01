vim.lsp.config('gopls', {
  cmd         = { 'gopls' },
  filetypes   = { 'go', 'gomod', 'gowork', 'gotmpl' },
  root_markers = { 'go.work', 'go.mod', '.git' },
  settings    = {
    gopls = {
      analyses  = { unusedparams = true },
      staticcheck = true,
      gofumpt   = true,
    },
  },
})

vim.lsp.config('ts_ls', {
  cmd         = { 'typescript-language-server', '--stdio' },
  filetypes   = { 'typescript', 'typescriptreact', 'javascript', 'javascriptreact' },
  root_markers = { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' },
})

vim.lsp.enable({ 'gopls', 'ts_ls' })

-- 診断表示の設定
vim.diagnostic.config({
  virtual_text  = { prefix = '●' },
  signs         = true,
  underline     = true,
  update_in_insert = false,
  severity_sort = true,
})

-- ノーマルモードのキーマップ（LSP接続時のみ有効）
vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(ev)
    local function map(key, fn, desc)
      vim.keymap.set('n', key, fn, { buffer = ev.buf, desc = desc })
    end
    map('K',          vim.lsp.buf.hover,           'LSP: ホバー')
    map('<leader>rn', vim.lsp.buf.rename,           'LSP: リネーム')
    map('<leader>ca', vim.lsp.buf.code_action,      'LSP: コードアクション')
    map('<leader>f',  vim.lsp.buf.format,           'LSP: フォーマット')
    map('[d',         vim.diagnostic.goto_prev,     'LSP: 前の診断へ')
    map(']d',         vim.diagnostic.goto_next,     'LSP: 次の診断へ')
    map('<leader>e',  vim.diagnostic.open_float,    'LSP: 診断の詳細')
  end,
})
