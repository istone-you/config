-- lsp.luaは実LSPサーバーの起動確認まではしない(gopls/typescript-language-server等
-- が居ない環境でも通す)。検証するのは: 静的なサーバー設定が正しく登録されるか、
-- LspAttach時にバッファローカルキーマップが張られるか、保存時フォーマットの
-- フィルタが意図したクライアントだけを通すか、の3点
local T = dofile(TESTS_DIR .. '/helpers.lua')
require('config.lsp')

T.describe('lsp.lua: server config registration', function()
  T.it('registers gopls/ts_ls/tofu_ls/taplo with the right cmd/filetypes/root_markers', function()
    local gopls = vim.lsp.config.gopls
    T.eq(gopls.cmd, { 'gopls' })
    T.contains(table.concat(gopls.filetypes, ','), 'go')
    T.contains(table.concat(gopls.root_markers, ','), 'go.mod')
    T.eq(gopls.settings.gopls.staticcheck, true)

    local ts_ls = vim.lsp.config.ts_ls
    T.eq(ts_ls.cmd, { 'typescript-language-server', '--stdio' })
    T.contains(table.concat(ts_ls.filetypes, ','), 'typescript')

    local tofu_ls = vim.lsp.config.tofu_ls
    T.eq(tofu_ls.cmd, { 'tofu-ls', 'serve' })
    T.contains(table.concat(tofu_ls.filetypes, ','), 'terraform')

    local taplo = vim.lsp.config.taplo
    T.eq(taplo.cmd, { 'taplo', 'lsp', 'stdio' })
    T.eq(taplo.filetypes, { 'toml' })
  end)
end)

T.describe('lsp.lua: LspAttach keymaps', function()
  T.it('binds K/<leader>rn/<leader>ca/<leader>f/[d/]d/<leader>E buffer-locally on attach', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_exec_autocmds('LspAttach', { buffer = buf, data = { client_id = 1 } })

    for _, key in ipairs({ 'K', '<leader>rn', '<leader>ca', '<leader>f', '[d', ']d', '<leader>E' }) do
      local maps = vim.api.nvim_buf_get_keymap(buf, 'n')
      local found = false
      for _, m in ipairs(maps) do
        if vim.api.nvim_replace_termcodes(m.lhs, true, false, true)
            == vim.api.nvim_replace_termcodes(key, true, false, true) then
          found = true
        end
      end
      T.ok(found, key .. ' should be bound buffer-locally after LspAttach')
    end

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

T.describe('lsp.lua: format-on-save filter', function()
  T.it('BufWritePre triggers vim.lsp.buf.format with a filter that allows only gopls/tofu_ls/taplo', function()
    local captured_filter
    local orig_format = vim.lsp.buf.format
    vim.lsp.buf.format = function(opts) captured_filter = opts and opts.filter end

    vim.api.nvim_exec_autocmds('BufWritePre', {})
    vim.lsp.buf.format = orig_format

    T.ok(captured_filter ~= nil, 'BufWritePre should call vim.lsp.buf.format with a filter')
    T.eq(captured_filter({ name = 'gopls' }), true)
    T.eq(captured_filter({ name = 'tofu_ls' }), true)
    T.eq(captured_filter({ name = 'taplo' }), true)
    T.eq(captured_filter({ name = 'ts_ls' }), false, 'ts_ls should not be auto-formatted on save')
  end)
end)

T.summary()
