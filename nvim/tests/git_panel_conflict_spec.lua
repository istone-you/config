local T = dofile(TESTS_DIR .. '/helpers.lua')
local H = dofile(TESTS_DIR .. '/git_panel_helpers.lua')
local git = require('config.git_panel.git')
local files = require('config.git_panel.files')

--- main と feature で同じ行を書き換えてマージ衝突を起こしたリポジトリを作る。
--- 戻り値は dir（衝突が発生した状態で main に居る）
local function conflicted_repo()
  local dir = T.tmp_git_repo(function(d)
    T.write_file(d .. '/target.txt', { 'base' })
    T.write_file(d .. '/other.txt', { 'other' })
    H.git(d, { 'add', '-A' })
    H.git(d, { 'commit', '-qm', 'init files' })

    H.git(d, { 'checkout', '-q', '-b', 'feature' })
    T.write_file(d .. '/target.txt', { 'from-feature' })
    H.git(d, { 'commit', '-qam', 'feature change' })

    H.git(d, { 'checkout', '-q', 'main' })
    T.write_file(d .. '/target.txt', { 'from-main' })
    H.git(d, { 'commit', '-qam', 'main change' })
    H.git(d, { 'merge', 'feature' }) -- ここで衝突する
  end)
  return dir
end

T.describe('git_panel コンフリクト', function()
  T.it('未マージのステータスコードを衝突として判定する', function()
    for _, code in ipairs({ 'UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD' }) do
      T.eq(files.is_conflicted({ x = code:sub(1, 1), y = code:sub(2, 2) }), true, code)
    end
    T.eq(files.is_conflicted({ x = 'M', y = ' ' }), false)
    T.eq(files.is_conflicted({ x = '?', y = '?' }), false)
    T.eq(files.is_conflicted({ x = 'A', y = 'M' }), false)
  end)

  T.it('pullの出力からコンフリクトを見分ける', function()
    T.eq(git.is_conflict_result({ code = 1, stdout = 'CONFLICT (content): Merge conflict in a.txt', stderr = '' }), true)
    T.eq(git.is_conflict_result({ code = 1, stdout = '', stderr = 'Automatic merge failed; fix conflicts' }), true)
    T.eq(git.is_conflict_result({ code = 1, stdout = '', stderr = 'could not apply a1b2c3' }), true)
    T.eq(git.is_conflict_result({ code = 1, stdout = '', stderr = 'fatal: couldn\'t find remote ref main' }), false)
    T.eq(git.is_conflict_result({ code = 0, stdout = 'Already up to date.', stderr = '' }), false)
  end)

  T.it('Filesパネルが衝突ファイルを UU で赤く出す', function()
    local dir = conflicted_repo()
    H.open(dir)
    local win = H.left_win()
    local row = H.find_row(win, 'target.txt')
    T.ok(row ~= nil, 'target.txt が並ぶ')
    T.contains(H.lines(win)[row], 'UU')

    -- 衝突していない other.txt は赤くならない
    local buf = vim.api.nvim_win_get_buf(win)
    local ns = vim.api.nvim_get_namespaces()['git_panel_hl'] or -1
    local reds = 0
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if m[4] and m[4].hl_group == 'GitPanelConflict' then reds = reds + 1 end
    end
    T.ok(reds > 0, '衝突行に GitPanelConflict が付く')

    H.close()
    T.rmrf(dir)
  end)

  T.it('マージ中であることを検出する', function()
    local dir = conflicted_repo()
    H.open(dir)
    local state
    git.merge_state(function(s) state = s end)
    T.wait_until(function() return state ~= nil end, 3000)
    T.eq(state, 'merge')
    H.close()
    T.rmrf(dir)
  end)

  T.it('m メニューから ours を採ると解消済み(add済み)になる', function()
    local dir = conflicted_repo()
    H.open(dir)
    local win = H.left_win()
    H.goto_row(win, H.find_row(win, 'target.txt'))
    H.press('m')
    vim.wait(300)
    H.press_modal('c') -- 現在の変更を採用（ours）
    vim.wait(600)

    T.eq(vim.fn.readfile(dir .. '/target.txt'), { 'from-main' })
    T.eq(H.status(dir):find('UU target.txt', 1, true), nil) -- 未マージが解消
    -- ours は HEAD と同じ内容なので status には出ない。インデックスの未マージ
    -- エントリ（ls-files -u）が消えていることで add まで済んだことを確認する
    T.eq(H.git(dir, { 'ls-files', '-u' }).stdout, '')

    H.close()
    T.rmrf(dir)
  end)

  T.it('m メニューの e で衝突ファイルをエディタで開く', function()
    local dir = conflicted_repo()
    H.open(dir)
    local win = H.left_win()
    H.goto_row(win, H.find_row(win, 'target.txt'))
    H.press('m')
    vim.wait(300)
    H.press_modal('e') -- エディタで開いて1つずつ解消する
    vim.wait(400)

    local buf = vim.api.nvim_get_current_buf()
    T.contains(vim.api.nvim_buf_get_name(buf), 'target.txt')
    T.eq(vim.bo[buf].buftype, '') -- hunkビューのスクラッチではなく実ファイル
    -- 開いた先で衝突解消のキーマップが効く状態になっている
    T.eq(require('config.git_conflict').is_attached(buf), true)

    T.rmrf(dir)
  end)

  T.it('m メニューから theirs を採ると相手側の内容になる', function()
    local dir = conflicted_repo()
    H.open(dir)
    local win = H.left_win()
    H.goto_row(win, H.find_row(win, 'target.txt'))
    H.press('m')
    vim.wait(300)
    H.press_modal('i') -- 入力側の変更を採用（theirs）
    vim.wait(600)

    T.eq(vim.fn.readfile(dir .. '/target.txt'), { 'from-feature' })
    H.close()
    T.rmrf(dir)
  end)

  T.it('m メニューからマージを中断できる', function()
    local dir = conflicted_repo()
    H.open(dir)
    local win = H.left_win()
    H.goto_row(win, H.find_row(win, 'target.txt'))
    H.press('m')
    vim.wait(300)
    H.press_modal('a') -- 中断
    vim.wait(200)
    H.press_modal('y') -- 確認ダイアログ
    vim.wait(800)

    T.eq(H.status(dir), '') -- 衝突前の状態に戻る
    T.eq(vim.fn.readfile(dir .. '/target.txt'), { 'from-main' })

    local state
    git.merge_state(function(s) state = s or 'none' end)
    T.wait_until(function() return state ~= nil end, 3000)
    T.eq(state, 'none')

    H.close()
    T.rmrf(dir)
  end)

  T.it('衝突ファイルには実際のマーカーが入っている（バッファ側の解消につながる）', function()
    local dir = conflicted_repo()
    local text = table.concat(vim.fn.readfile(dir .. '/target.txt'), '\n')
    T.contains(text, '<<<<<<<')
    T.contains(text, '=======')
    T.contains(text, '>>>>>>>')
    local conflict = require('config.git_conflict')
    T.eq(#conflict.parse(vim.fn.readfile(dir .. '/target.txt')), 1)
    T.rmrf(dir)
  end)
end)

T.summary()
