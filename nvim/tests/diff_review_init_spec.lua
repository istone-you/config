local T = dofile(TESTS_DIR .. '/helpers.lua')
local init = require('config.diff_review')

T.describe('diff_review/init.lua', function()
  T.it('registers the DiffReview commands', function()
    local cmds = vim.api.nvim_get_commands({})
    T.ok(cmds.DiffReview ~= nil, 'DiffReview command should exist')
    T.ok(cmds.DiffReviewClose ~= nil, 'DiffReviewClose command should exist')
  end)

  T.it('maps <leader>R in normal mode', function()
    local map = vim.fn.maparg('<leader>R', 'n', false, true)
    T.eq(map.desc, '差分レビューをブラウザで開く（AIとコメントでやりとり）')
  end)

  T.it('requires an explicit port (selection-based, no default)', function()
    T.ok(select(1, init._private.parse_port('')) == nil, 'empty port is rejected')
    T.eq(init._private.parse_port('8080'), 8080)
    T.ok(select(1, init._private.parse_port('abc')) == nil)
    T.ok(select(1, init._private.parse_port('99999')) == nil)
  end)

  T.it('resolves the git root of the current buffer', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/x.txt', { 'hi' })
    end)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, dir .. '/x.txt')
    vim.api.nvim_set_current_buf(buf)

    local root
    init._private.resolve_root(function(r) root = r end)
    T.wait_until(function() return root ~= nil end)
    -- macOS の /var→/private/var 揺れを避けるため resolve 済み実体で比較する
    T.eq(vim.fn.resolve(root), vim.fn.resolve(vim.fs.normalize(dir)))

    vim.api.nvim_buf_delete(buf, { force = true })
    T.rmrf(dir)
  end)
end)

T.summary()
