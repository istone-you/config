-- ansi_view.lua（deltaのANSI出力を通常バッファ＋extmarkへ忠実に写す変換器）の単体テスト。
-- ここが delta の見た目（色・ブロック背景・行番号・side-by-side）を再現する要。

local T = dofile(TESTS_DIR .. '/helpers.lua')
local GP = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local AV = require('config.git_panel.ansi_view')

local ESC = '\27'

local function render(ansi)
  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace('av_test_' .. tostring(buf))
  AV.render(buf, ns, ansi)
  return buf, ns
end

-- グループ名→実際のfg/bg(数値)を引く
local function hl_of(group)
  return vim.api.nvim_get_hl(0, { name = group, link = false })
end

T.describe('git_panel ansi_view (delta ANSI -> normal buffer)', function()
  T.it('strips escape codes, leaving only the visible text', function()
    local buf = render(ESC .. '[38;2;255;0;0mhello' .. ESC .. '[0m world')
    T.eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], 'hello world')
  end)

  T.it('maps a truecolor SGR to an extmark highlight with that exact color', function()
    local buf, ns = render(ESC .. '[38;2;255;0;0mRED' .. ESC .. '[0m')
    local ms = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local found = false
    for _, m in ipairs(ms) do
      local d = m[4]
      if d.hl_group then
        local h = hl_of(d.hl_group)
        if h.fg == tonumber('ff0000', 16) then found = true end
      end
    end
    T.ok(found, 'a highlight with fg #ff0000 should be applied over "RED"')
  end)

  T.it('maps a 256-color SGR (38;5;n) via the xterm cube', function()
    -- 196 = 6x6x6 cube の (5,0,0) = #ff0000
    local buf, ns = render(ESC .. '[38;5;196mX' .. ESC .. '[0m')
    local ms = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local ok = false
    for _, m in ipairs(ms) do
      local h = m[4].hl_group and hl_of(m[4].hl_group)
      if h and h.fg == tonumber('ff0000', 16) then ok = true end
    end
    T.ok(ok, '38;5;196 should resolve to #ff0000')
  end)

  T.it('EL (ESC[K) after a background paints the WHOLE line (line-level block background)', function()
    -- 背景赤 + 文字 + EL → 行全体を端まで塗る（line_hl_group）。文字の後ろだけでなく行単位。
    local buf, ns = render(ESC .. '[48;2;63;0;1m-code' .. ESC .. '[0K' .. ESC .. '[0m')
    local ms = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local has_line_bg = false
    for _, m in ipairs(ms) do
      local d = m[4]
      if d.line_hl_group then
        local h = hl_of(d.line_hl_group)
        if h.bg == tonumber('3f0001', 16) then has_line_bg = true end
      end
    end
    T.ok(has_line_bg, 'EL should set line_hl_group with the current background (#3f0001) = full-line band')
  end)

  T.it('the diff pane is a normal (non-terminal) buffer with cursorline, showing delta content', function()
    local git = require('config.git_panel.git')
    if not git.delta_available then print('  (skipped: delta not installed)'); return end
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/a.txt', { 'one', 'two' })
      GP.git(d, { 'add', '.' })
      GP.git(d, { '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'seed' })
    end)
    T.write_file(dir .. '/a.txt', { 'one', 'CHANGED' })

    GP.open(dir, false)
    local left, right = GP.left_win(), GP.right_win()
    GP.goto_row(left, GP.find_row(left, 'a.txt'))
    T.wait_until(function()
      return table.concat(GP.lines(right), '\n'):find('CHANGED', 1, true) ~= nil
    end)
    local rbuf = vim.api.nvim_win_get_buf(right)
    T.ok(vim.bo[rbuf].buftype ~= 'terminal', 'diff pane must be a normal buffer (so selection highlight works)')
    T.eq(vim.wo[right].cursorline, true, 'cursorline (selection highlight) should be on for diffs')
    local ns_marks = vim.api.nvim_buf_get_extmarks(rbuf, -1, 0, -1, {})
    T.ok(#ns_marks > 0, 'delta colors should be carried over as extmarks')

    GP.close()
    T.rmrf(dir)
  end)
end)

T.summary()
