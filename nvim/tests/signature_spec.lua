-- config.signature は関数の引数ヒント（VSCode のパラメータヒント相当）。
-- 実サーバーは立てず、検証するのは: トリガー文字の取り出し、show に渡すオプション
-- （border / focus=false / silent）、補完メニュー表示中は出さないこと、
-- クライアント不在の LspAttach で落ちないこと。
local T = dofile(TESTS_DIR .. '/helpers.lua')
local signature = require('config.signature')

local function fake_client(trigger, retrigger)
  return {
    server_capabilities = {
      signatureHelpProvider = {
        triggerCharacters   = trigger,
        retriggerCharacters = retrigger,
      },
    },
  }
end

T.describe('signature.trigger_chars', function()
  T.it('triggerCharacters と retriggerCharacters を集合にまとめる', function()
    local chars = signature.trigger_chars(fake_client({ '(', ',' }, { ')' }))
    T.eq(chars['('], true)
    T.eq(chars[','], true)
    T.eq(chars[')'], true)
    T.eq(chars['x'], nil)
  end)

  T.it('capability が無いクライアント / nil は空集合', function()
    T.eq(signature.trigger_chars(nil), {})
    T.eq(signature.trigger_chars({ server_capabilities = {} }), {})
    T.eq(signature.trigger_chars(fake_client(nil, nil)), {})
  end)
end)

T.describe('signature.show', function()
  T.it('border 付き・フォーカスを奪わない・静かに呼ぶ', function()
    local captured
    local orig = vim.lsp.buf.signature_help
    vim.lsp.buf.signature_help = function(opts) captured = opts end
    signature.show()
    vim.lsp.buf.signature_help = orig

    T.ok(captured ~= nil, 'signature_help should be called')
    T.eq(captured.border, signature.BORDER) -- 透過フロートなので枠が要る
    T.eq(captured.focus, false)             -- カーソルが飛ぶと入力が止まる
    T.eq(captured.silent, true)             -- 未対応位置で毎回メッセージを出さない
    T.contains(captured.close_events, 'InsertLeave')
  end)

  T.it('呼び出し側のオプションで上書きできる', function()
    local captured
    local orig = vim.lsp.buf.signature_help
    vim.lsp.buf.signature_help = function(opts) captured = opts end
    signature.show({ border = 'single' })
    vim.lsp.buf.signature_help = orig
    T.eq(captured.border, 'single')
  end)

  T.it('補完メニューが出ている間は表示しない（重なって読めなくなるため）', function()
    local called = false
    local orig_sig = vim.lsp.buf.signature_help
    local orig_pum = vim.fn.pumvisible
    vim.lsp.buf.signature_help = function() called = true end
    vim.fn.pumvisible = function() return 1 end

    signature.show()

    vim.lsp.buf.signature_help = orig_sig
    vim.fn.pumvisible = orig_pum
    T.eq(called, false)
  end)
end)

T.describe('signature.attach', function()
  T.it('クライアントが取れなければ false', function()
    local buf = vim.api.nvim_create_buf(false, true)
    T.eq(signature.attach(nil, buf), false)
    T.eq(signature.attach(99999, buf), false)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  T.it('LspAttach が飛んでもエラーにならない', function()
    local buf = vim.api.nvim_create_buf(false, true)
    local ok = pcall(vim.api.nvim_exec_autocmds, 'LspAttach',
      { buffer = buf, data = { client_id = 99999 } })
    T.eq(ok, true)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)

T.summary()
