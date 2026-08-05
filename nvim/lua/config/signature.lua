-- シグネチャヘルプ（VSCode のパラメータヒント相当）
--
-- 関数呼び出しの `(` を打った瞬間に「引数は何か」をフロートで出す。サーバーが
-- 申告した triggerCharacters（多くは `(` と `,`）を InsertCharPre で拾って発火させる。
--
-- 表示上の注意: options.lua で NormalFloat の背景を透過にしているため、枠なしだと
-- 下のコードと文字が地続きに見えて読めない。border を付けて浮いていることを示す
-- （git パネル等の他フロートと同じ方針）。

local M = {}

M.BORDER = 'rounded'

-- カーソルを動かしたら消す。フロートに焦点を移さない（focus=false）ので入力は止まらない
M.CLOSE_EVENTS = { 'CursorMoved', 'CursorMovedI', 'InsertLeave', 'BufHidden', 'WinScrolled' }

--- シグネチャヘルプを表示する
---@param opts table|nil vim.lsp.buf.signature_help に渡す追加オプション
function M.show(opts)
  -- 補完メニューと重なると両方読めなくなるので、メニューが出ている間は出さない
  if vim.fn.pumvisible() == 1 then return end
  vim.lsp.buf.signature_help(vim.tbl_extend('force', {
    border       = M.BORDER,
    focus        = false,
    silent       = true, -- 対応していない位置で「No signature help available」を出さない
    close_events = M.CLOSE_EVENTS,
  }, opts or {}))
end

--- クライアントが申告するトリガー文字の集合を返す
---@param client table|nil
---@return table<string, boolean>
function M.trigger_chars(client)
  local set = {}
  local provider = client
    and client.server_capabilities
    and client.server_capabilities.signatureHelpProvider
  if not provider then return set end
  for _, list in ipairs({ provider.triggerCharacters, provider.retriggerCharacters }) do
    for _, ch in ipairs(list or {}) do
      set[ch] = true
    end
  end
  return set
end

--- LspAttach 時にそのバッファへ自動表示を仕込む
---@param client_id integer|nil
---@param buf integer
---@return boolean 仕込んだか
function M.attach(client_id, buf)
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  if not client then return false end
  if not client:supports_method('textDocument/signatureHelp') then return false end

  local chars = M.trigger_chars(client)
  if vim.tbl_isempty(chars) then return false end

  vim.api.nvim_create_autocmd('InsertCharPre', {
    group    = vim.api.nvim_create_augroup('user_signature_' .. buf, { clear = true }),
    buffer   = buf,
    callback = function()
      if not chars[vim.v.char] then return end
      -- その文字がバッファに入ってからでないとサーバーが引数位置を判定できないので遅らせる
      vim.schedule(function() M.show() end)
    end,
  })

  vim.keymap.set('n', '<leader>k', function() M.show() end,
    { buffer = buf, desc = 'LSP: シグネチャヘルプ' })
  vim.keymap.set('i', '<C-s>', function() M.show() end,
    { buffer = buf, desc = 'LSP: シグネチャヘルプ' })
  return true
end

vim.api.nvim_create_autocmd('LspAttach', {
  group    = vim.api.nvim_create_augroup('user_signature', { clear = true }),
  callback = function(ev)
    M.attach(ev.data and ev.data.client_id, ev.buf)
  end,
})

return M
