local T = dofile(TESTS_DIR .. '/helpers.lua')
vim.g.mapleader = ' '
local http = require('config.http_client')
local picker = require('config.http_client.picker')

local function open_items(items, on_select)
  picker.open({
    title = ' テスト ',
    items = items,
    format = function(item)
      return { tag = item.tag, tag_hl = 'HttpPickerGet', text = item.text, right = item.right }
    end,
    on_select = on_select,
  })
end

local function results_lines()
  return vim.api.nvim_buf_get_lines(picker.state.results_buf, 0, -1, false)
end

local ITEMS = {
  { tag = 'GET   ', text = '一覧', right = '   3' },
  { tag = 'POST  ', text = '作成', right = '   8' },
  { tag = 'DELETE', text = '削除', right = '  14' },
}

T.describe('http_client picker', function()
  T.it('プロンプトと一覧の2つのフロートを開く', function()
    open_items(ITEMS)
    local floats = T.floating_wins()
    T.eq(#floats, 2)
    T.ok(picker.is_open(), '開いている')
    T.eq(vim.api.nvim_get_current_win(), picker.state.prompt_win) -- 入力側にフォーカス
    T.eq(T.win_title_text(picker.state.prompt_win), ' テスト ')
    picker.close()
    T.eq(#T.floating_wins(), 0)
    T.eq(picker.is_open(), false)
  end)

  T.it('タグ・テキスト・右端の情報を並べて表示する', function()
    open_items(ITEMS)
    local lines = results_lines()
    T.eq(#lines, 3)
    T.contains(lines[1], 'GET')
    T.contains(lines[1], '一覧')
    T.contains(lines[1], '3')
    T.contains(lines[3], 'DELETE')
    picker.close()
  end)

  T.it('入力で絞り込む（タグでもテキストでも引ける）', function()
    open_items(ITEMS)
    picker.filter('作成')
    T.eq(#picker.state.filtered, 1)
    T.eq(picker.state.filtered[1].text, '作成')

    picker.filter('delete')
    T.eq(#picker.state.filtered, 1)
    T.eq(picker.state.filtered[1].text, '削除')

    picker.filter('')
    T.eq(#picker.state.filtered, 3)
    picker.close()
  end)

  T.it('一致が無いときは案内を出し、決定しても何も起きない', function()
    local picked = nil
    open_items(ITEMS, function(item) picked = item end)
    picker.filter('zzz')
    T.eq(#picker.state.filtered, 0)
    T.contains(results_lines()[1], '一致するものがありません')
    picker.confirm()
    T.eq(picked, nil)
    T.eq(picker.is_open(), false)
  end)

  T.it('Ctrl-j / Ctrl-k 相当の移動が端で止まる', function()
    open_items(ITEMS)
    T.eq(picker.state.sel, 1)
    picker.move(-1)
    T.eq(picker.state.sel, 1) -- 先頭より上には行かない
    picker.move(1)
    picker.move(1)
    T.eq(picker.state.sel, 3)
    picker.move(1)
    T.eq(picker.state.sel, 3) -- 末尾より下にも行かない
    picker.close()
  end)

  T.it('絞り込み後に選択位置が範囲内へ収まる', function()
    open_items(ITEMS)
    picker.move(2)
    T.eq(picker.state.sel, 3)
    picker.filter('一覧')
    T.eq(picker.state.sel, 1)
    picker.close()
  end)

  T.it('Enter で選択した項目を渡して閉じる', function()
    local picked = nil
    open_items(ITEMS, function(item) picked = item end)
    picker.move(1)
    picker.confirm()
    T.eq(picked.text, '作成')
    T.eq(picker.is_open(), false)
  end)

  T.it('プロンプトに移動・決定・キャンセルのキーが付く', function()
    open_items(ITEMS)
    local lhs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(picker.state.prompt_buf, 'i')) do
      lhs[m.lhs] = true
    end
    T.ok(lhs['<C-J>'] or lhs['<C-j>'], 'Ctrl-j')
    T.ok(lhs['<C-K>'] or lhs['<C-k>'], 'Ctrl-k')
    T.ok(lhs['<Down>'] and lhs['<Up>'], '↓ / ↑')
    T.ok(lhs['<CR>'], 'Enter')
    T.ok(lhs['<Esc>'], 'Esc')
    picker.close()
  end)

  T.it('メソッドごとに色分けする', function()
    T.eq(picker.method_hl('GET'), 'HttpPickerGet')
    T.eq(picker.method_hl('post'), 'HttpPickerWrite')
    T.eq(picker.method_hl('DELETE'), 'HttpPickerDelete')
  end)
end)

T.describe('http_client のリクエスト選択', function()
  local function open_http(lines)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    local path = dir .. '/api.http'
    T.write_file(path, lines)
    vim.cmd('edit ' .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'http'
    return buf
  end

  T.it('Space h j で一覧を出し、選んだリクエストへカーソルが飛ぶ', function()
    open_http({
      '### 一覧',
      'GET http://127.0.0.1/users',
      '',
      '### 作成',
      '# @name createUser',
      'POST http://127.0.0.1/users',
      '',
      '### 削除',
      'DELETE http://127.0.0.1/users/1',
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(' hj', true, false, true), 'x', false)

    T.ok(picker.is_open(), 'ポップアップが開く')
    local lines = results_lines()
    T.eq(#lines, 3)
    T.contains(lines[1], '一覧')
    T.contains(lines[2], 'createUser') -- # @name が名前として出る
    T.contains(lines[3], 'DELETE')

    picker.move(2)
    picker.confirm()
    T.eq(vim.api.nvim_win_get_cursor(0)[1], 8) -- 3つめの ### の行
  end)

  T.it('環境選択では現在の環境に印が付く', function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    T.write_file(dir .. '/http-client.env.json',
      { '{ "dev": { "base": "http://dev" }, "prod": { "base": "http://prod" } }' })
    T.write_file(dir .. '/api.http', { 'GET {{base}}/ping' })
    vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/api.http'))
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].filetype = 'http'

    http.select_env(buf)
    T.eq(#picker.state.filtered, 2)
    T.contains(results_lines()[1], 'dev')

    picker.move(1)
    picker.confirm() -- prod を選ぶ
    T.eq(http.current_env(dir), 'prod')

    http.select_env(buf)
    T.contains(results_lines()[2], '●') -- 選択中の環境に印
    picker.close()
    T.rmrf(dir)
  end)
end)

T.summary()
