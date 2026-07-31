local T = dofile(TESTS_DIR .. '/helpers.lua')
local parser = require('config.http_client.parser')

local function parse(text)
  return parser.parse(vim.split(text, '\n'))
end

T.describe('http_client parser', function()
  T.it('### でリクエストを分割し、名前・メソッド・URL を取る', function()
    local doc = parse(table.concat({
      '### ユーザー取得',
      'GET https://example.com/users/1',
      '',
      '### 作成',
      'POST https://example.com/users',
    }, '\n'))
    T.eq(#doc.requests, 2)
    T.eq(doc.requests[1].name, 'ユーザー取得')
    T.eq(doc.requests[1].method, 'GET')
    T.eq(doc.requests[1].url, 'https://example.com/users/1')
    T.eq(doc.requests[2].method, 'POST')
    T.eq(doc.requests[2].start_line, 4)
  end)

  T.it('ヘッダとボディを空行で分ける', function()
    local doc = parse(table.concat({
      'POST https://example.com/users HTTP/1.1',
      'Content-Type: application/json',
      'X-Token:  abc  ',
      '',
      '{',
      '  "name": "taro"',
      '}',
      '',
    }, '\n'))
    local req = doc.requests[1]
    T.eq(req.url, 'https://example.com/users')
    T.eq(req.headers, { { 'Content-Type', 'application/json' }, { 'X-Token', 'abc' } })
    T.eq(req.body, '{\n  "name": "taro"\n}')
  end)

  T.it('メソッド省略は GET 扱い', function()
    local doc = parse('https://example.com/ping')
    T.eq(doc.requests[1].method, 'GET')
    T.eq(doc.requests[1].url, 'https://example.com/ping')
  end)

  T.it('URL が無いブロックはリクエストにしない', function()
    local doc = parse('### メモだけのブロック\n# 何も書いていない')
    T.eq(#doc.requests, 0)
  end)

  T.it('クエリ文字列の折り返し行を URL に連結する', function()
    local doc = parse(table.concat({
      'GET https://example.com/search',
      '  ?q=neovim',
      '  &page=2',
      'Accept: application/json',
    }, '\n'))
    T.eq(doc.requests[1].url, 'https://example.com/search?q=neovim&page=2')
    T.eq(doc.requests[1].headers, { { 'Accept', 'application/json' } })
  end)

  T.it('コメント行のディレクティブを読む', function()
    local doc = parse(table.concat({
      '###',
      '# @name createUser',
      '# @follow',
      '# @insecure',
      '# @timeout 60',
      'POST https://example.com/users',
    }, '\n'))
    local d = doc.requests[1].directives
    T.eq(d.name, 'createUser')
    T.eq(d.follow, true)
    T.eq(d.insecure, true)
    T.eq(d.timeout, 60)
    T.eq(parser.request_label(doc.requests[1]), 'createUser')
  end)

  T.it('ボディ内の # 始まりの行はコメント扱いしない', function()
    local doc = parse(table.concat({
      'POST https://example.com/gql',
      'Content-Type: application/json',
      '',
      '# これはボディの一部',
      '{ "a": 1 }',
    }, '\n'))
    T.eq(doc.requests[1].body, '# これはボディの一部\n{ "a": 1 }')
  end)

  T.it('@name = value をファイル変数として集める', function()
    local doc = parse(table.concat({
      '@base = https://example.com',
      '@ver  = v1',
      '',
      'GET {{base}}/{{ver}}/users',
    }, '\n'))
    T.eq(#doc.variables, 2)
    local vars = parser.vars_for(doc, doc.requests[1])
    T.eq(vars, { base = 'https://example.com', ver = 'v1' })
  end)

  T.it('後から再定義した変数は、それ以降のリクエストにだけ効く', function()
    local doc = parse(table.concat({
      '@base = https://one.example',
      '### 1つめ',
      'GET {{base}}/a',
      '',
      '@base = https://two.example',
      '### 2つめ',
      'GET {{base}}/b',
    }, '\n'))
    T.eq(parser.vars_for(doc, doc.requests[1]).base, 'https://one.example')
    T.eq(parser.vars_for(doc, doc.requests[2]).base, 'https://two.example')
  end)

  T.it('request_at: ブロック内・ブロック外の行を解決する', function()
    local doc = parse(table.concat({
      '@base = https://example.com',
      '### 1つめ',
      'GET {{base}}/a',
      '',
      '### 2つめ',
      'GET {{base}}/b',
    }, '\n'))
    T.eq(parser.request_at(doc, 3).url, '{{base}}/a')
    T.eq(parser.request_at(doc, 6).url, '{{base}}/b')
    T.eq(parser.request_at(doc, 1).url, '{{base}}/a') -- 変数定義部は先頭リクエスト扱い
  end)
end)

T.describe('http_client 変数展開', function()
  T.it('入れ子の変数を再帰的に展開する', function()
    local out, errs = parser.resolve('{{url}}/users', {
      vars = { url = '{{scheme}}://{{host}}', scheme = 'https', host = 'example.com' },
    })
    T.eq(out, 'https://example.com/users')
    T.eq(errs, {})
  end)

  T.it('ファイル変数が環境変数より優先される', function()
    local out = parser.resolve('{{base}}', { vars = { base = 'file' }, env = { base = 'env' } })
    T.eq(out, 'file')
  end)

  T.it('環境ファイルの変数も引ける', function()
    local out = parser.resolve('{{base}}/x', { vars = {}, env = { base = 'https://env.example' } })
    T.eq(out, 'https://env.example/x')
  end)

  T.it('未解決の変数は名前を返し、本文はそのまま残す', function()
    local out, errs = parser.resolve('{{a}}/{{b}}', { vars = { a = '1' } })
    T.eq(out, '1/{{b}}')
    T.eq(errs, { 'b' })
  end)

  T.it('循環参照でも無限ループせず未解決として返す', function()
    local _, errs = parser.resolve('{{a}}', { vars = { a = '{{b}}', b = '{{a}}' } })
    T.eq(errs, { 'a' })
  end)

  T.it('$env.NAME を環境変数から解決する', function()
    vim.env.NVIM_HTTP_TEST_TOKEN = 'secret-token'
    local out, errs = parser.resolve('Bearer {{$env.NVIM_HTTP_TEST_TOKEN}}', {})
    T.eq(out, 'Bearer secret-token')
    T.eq(errs, {})
    vim.env.NVIM_HTTP_TEST_TOKEN = nil
  end)

  T.it('存在しない $env は未解決として報告する', function()
    local _, errs = parser.resolve('{{$env.NVIM_HTTP_NOT_SET}}', {})
    T.eq(errs, { '$env.NVIM_HTTP_NOT_SET' })
  end)

  T.it('$uuid / $timestamp / $randomInt を展開する', function()
    local uuid = parser.resolve('{{$uuid}}', {})
    T.ok(uuid:match('^%x8-%x4-4%x3-%x4-%x12$') ~= nil
      or uuid:match('^%x+%-%x+%-4%x+%-%x+%-%x+$') ~= nil, 'uuid 形式: ' .. uuid)
    T.ok(tonumber((parser.resolve('{{$timestamp}}', {}))) ~= nil)
    local n = tonumber((parser.resolve('{{$randomInt 5 5}}', {})))
    T.eq(n, 5)
  end)

  T.it('build: URL・ヘッダ・ボディをまとめて展開する', function()
    local doc = parse(table.concat({
      '@base = https://example.com',
      '@token = abc',
      '',
      '### 作成',
      'POST {{base}}/users',
      'Authorization: Bearer {{token}}',
      '',
      '{ "id": "{{missing}}" }',
    }, '\n'))
    local req, errs = parser.build(doc.requests[1], { vars = parser.vars_for(doc, doc.requests[1]) })
    T.eq(req.method, 'POST')
    T.eq(req.url, 'https://example.com/users')
    T.eq(req.headers, { { 'Authorization', 'Bearer abc' } })
    T.eq(req.body, '{ "id": "{{missing}}" }')
    T.eq(errs, { 'missing' })
    T.eq(req.label, '作成')
  end)
end)

T.describe('http_client 環境ファイル', function()
  local dir

  local function setup(env_json, private_json)
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. '/sub', 'p')
    T.write_file(dir .. '/http-client.env.json', vim.split(env_json, '\n'))
    if private_json then
      T.write_file(dir .. '/http-client.private.env.json', vim.split(private_json, '\n'))
    end
  end

  T.it('親ディレクトリの環境ファイルを見つける', function()
    setup('{ "dev": { "base": "http://localhost:3000" } }')
    -- 返り値はシンボリックリンクを解決した絶対パス
    T.eq(parser.find_env_dir(dir .. '/sub'), (vim.fn.resolve(vim.fn.fnamemodify(dir, ':p')):gsub('/+$', '')))
    T.rmrf(dir)
  end)

  T.it('$shared をマージし、環境名は $shared を除いて並べる', function()
    setup('{ "$shared": { "ver": "v1" }, "dev": { "base": "http://localhost" }, "prod": { "base": "https://api" } }')
    T.eq(parser.env_names(dir), { 'dev', 'prod' })
    T.eq(parser.env_vars(dir, 'dev'), { ver = 'v1', base = 'http://localhost' })
    T.eq(parser.env_vars(dir, 'prod'), { ver = 'v1', base = 'https://api' })
    T.rmrf(dir)
  end)

  T.it('private 側の値が上書きする', function()
    setup('{ "dev": { "base": "http://localhost", "token": "dummy" } }',
      '{ "dev": { "token": "real-token" } }')
    T.eq(parser.env_vars(dir, 'dev'), { base = 'http://localhost', token = 'real-token' })
    T.rmrf(dir)
  end)

  T.it('壊れた JSON はエラーを返す', function()
    setup('{ "dev": ')
    local vars, err = parser.env_vars(dir, 'dev')
    T.eq(vars, {})
    T.ok(err ~= nil and err:find('JSON') ~= nil, 'JSON エラーが返る')
    T.rmrf(dir)
  end)

  T.it('環境ファイルが無ければ空を返す', function()
    local empty = vim.fn.tempname()
    vim.fn.mkdir(empty, 'p')
    T.eq(parser.env_names(empty), {})
    T.rmrf(empty)
  end)
end)

T.summary()
