local T = dofile(TESTS_DIR .. '/helpers.lua')
local q = require('config.quit_confirm')

local function float_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= '' then return w end
  end
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'x', false)
end

-- 各テストは同一プロセス内で走るので、必ず「通常バッファ1枚・未変更」から始める
local function clean()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then pcall(function() vim.bo[b].modified = false end) end
  end
  vim.cmd('silent! only')
  vim.cmd('enew') -- filetype '' の新規バッファにして前テストの汚染を消す
end

T.describe('quit_confirm', function()
  T.it('defines the -bang commands and abbreviations', function()
    T.eq(vim.fn.exists(':Q'), 2)
    T.eq(vim.fn.exists(':Qa'), 2)
    T.eq(vim.fn.exists(':Wq'), 2)
    T.eq(vim.fn.exists(':X'), 2)
  end)

  T.it('exits_nvim is true for a single window, false when split', function()
    clean()
    T.eq(q._exits_nvim(), true)
    vim.cmd('split') -- 同じ(通常)バッファの2枚 → 実編集ウィンドウが残る
    T.eq(q._exits_nvim(), false)
    clean()
    T.eq(q._exits_nvim(), true)
  end)

  T.it('exits_nvim is true when only utility windows (explorer) remain besides the editor', function()
    clean()
    vim.cmd('vnew') -- 新規バッファのウィンドウを作る（バッファ共有しない）
    local util = vim.api.nvim_get_current_win()
    vim.bo[vim.api.nvim_win_get_buf(util)].filetype = 'explorer'
    local editor
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= util then editor = w end
    end
    vim.api.nvim_set_current_win(editor)
    T.eq(q._exits_nvim(), true) -- editorを閉じると explorer だけ→終了扱い→確認すべき
    vim.api.nvim_set_current_win(util)
    T.eq(q._exits_nvim(), false) -- explorer側から見れば実編集ウィンドウが残る
    vim.api.nvim_set_current_win(editor)
    clean()
  end)

  T.it('q() on the last window shows a confirm popup and cancels with n (no quit)', function()
    clean()
    T.ok(float_win() == nil, 'no float before')
    q.q(false)
    vim.wait(50)
    local fw = float_win()
    T.ok(fw ~= nil, 'confirm popup appears')
    vim.api.nvim_set_current_win(fw)
    feed('n')
    vim.wait(50)
    T.ok(float_win() == nil, 'popup closed after n')
    T.ok(#vim.api.nvim_list_wins() >= 1, 'neovim still alive')
  end)

  T.it('q() with unsaved changes shows the unsaved dialog (save/discard/cancel), not a plain confirm', function()
    clean()
    local b = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'unsaved' })
    vim.bo[b].modified = true
    T.ok(#q._unsaved_names() >= 1, 'unsaved buffer detected')

    q.q(false)
    vim.wait(50)
    local fw = float_win()
    T.ok(fw ~= nil, 'dialog appears')
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(fw), 0, -1, false), '\n')
    T.ok(text:find('未保存', 1, true) ~= nil, 'shows the unsaved-changes dialog: ' .. text)
    T.ok(text:find('保存して終了', 1, true) ~= nil, 'offers save & quit')

    -- キャンセル（保存も破棄もしない）
    vim.api.nvim_set_current_win(fw)
    feed('n')
    vim.wait(30)
    T.ok(float_win() == nil, 'dialog closed on cancel')
    vim.bo[b].modified = false -- 後続テストへ影響させない
  end)

  T.it('q() with a split just closes the window (no popup)', function()
    clean()
    vim.cmd('split')
    T.eq(#vim.api.nvim_list_wins(), 2)
    q.q(false)
    vim.wait(50)
    T.ok(float_win() == nil, 'no confirm popup when only closing a split')
    T.eq(#vim.api.nvim_list_wins(), 1)
  end)

  T.it(':q abbreviation routes through the confirm popup on the last window', function()
    clean()
    feed(':q<CR>')
    vim.wait(60)
    T.ok(float_win() ~= nil, ':q shows the confirm popup')
    vim.api.nvim_set_current_win(float_win())
    feed('n')
    vim.wait(30)
  end)

  T.it(':q! (force) bypasses the popup and closes the window directly', function()
    clean()
    vim.cmd('split')
    T.eq(#vim.api.nvim_list_wins(), 2)
    feed(':q!<CR>')
    vim.wait(50)
    T.ok(float_win() == nil, 'no popup for force quit')
    T.eq(#vim.api.nvim_list_wins(), 1)
  end)
end)

T.summary()
