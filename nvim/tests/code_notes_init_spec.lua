local T = dofile(TESTS_DIR .. '/helpers.lua')
local ib = require('config.code_notes')

T.describe('code_notes/init.lua', function()
  T.it('registers commands and the Space B mapping', function()
    T.ok(vim.fn.exists(':CodeNotes') == 2, ':CodeNotes exists')
    T.ok(vim.fn.exists(':CodeNotesClose') == 2, ':CodeNotesClose exists')
    local map = vim.fn.maparg('<leader>B', 'n', false, true)
    T.eq(map.desc, 'Code Notes をブラウザで開く')
  end)

  T.it('parses explicit ports', function()
    local parse = ib._private.parse_port
    T.eq(parse('45678'), 45678)
    local bad, err = parse('x')
    T.eq(bad, nil)
    T.contains(err, 'port must be a number')
  end)
end)

T.summary()
