-- markview 本体は未テスト想定だが、parser_installed の pcall 誤用は実害があるため
-- ここだけ最小限で固定する

local T = dofile(TESTS_DIR .. '/helpers.lua')
local utils = require('config.markview.utils')

T.describe('markview.utils.parser_installed', function()
  T.it('returns false for a parser that is not installed', function()
    T.eq(utils.parser_installed('definitely_missing_parser_xyz_9f3a'), false)
  end)
end)

T.summary()
