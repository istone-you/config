local T = dofile(TESTS_DIR .. '/helpers.lua')
local file_icons = require('config.file_icons')

local function char(code) return vim.fn.nr2char(code) end

T.describe('file_icons', function()
  T.it('returns the folder icon for directories regardless of name', function()
    T.eq(file_icons.get('anything', true), char(file_icons.FOLDER))
    T.eq(file_icons.get('foo.lua', true), char(file_icons.FOLDER))
  end)

  T.it('maps known extensions to their codepoint', function()
    T.eq(file_icons.get('main.lua', false), char(0xe620))
    T.eq(file_icons.get('server.go', false), char(0xe626))
  end)

  T.it('jsx/tsx use the react icon; images/svg/zip/xml/npmrc are mapped', function()
    T.eq(file_icons.get('App.jsx', false), char(0xf0708))
    T.eq(file_icons.get('App.tsx', false), char(0xf0708))
    T.eq(file_icons.get('logo.png', false), char(0xe60d))
    T.eq(file_icons.get('photo.jpeg', false), char(0xe60d))
    T.eq(file_icons.get('icon.svg', false), char(0xe698))
    T.eq(file_icons.get('bundle.zip', false), char(0xe6aa))
    T.eq(file_icons.get('pom.xml', false), char(0xe619))
    T.eq(file_icons.get('.npmrc', false), char(0xe71e))
    -- .sh は seti-shell、bash/zsh は従来のシェルアイコンのまま
    T.eq(file_icons.get('deploy.sh', false), char(0xe691))
    T.eq(file_icons.get('.bashrc.bash', false), char(0xe615))
  end)

  T.it('resolves filename-based special icons (vite/sentry/yarn/node/readme/ignore files)', function()
    T.eq(file_icons.get('vite.config.mts', false), char(0xe8d7))
    T.eq(file_icons.get('vite.config.ts', false), char(0xe8d7))
    T.eq(file_icons.get('playwright.config.ts', false), char(0xe863))
    T.eq(file_icons.get('sentry.properties', false), char(0xe89f))
    T.eq(file_icons.get('yarn.lock', false), char(0xe6a7)) -- 汎用 *.lock より優先
    T.eq(file_icons.get('package.json', false), char(0xf0399)) -- 汎用 json より優先
    T.eq(file_icons.get('README.md', false), char(0xeda4)) -- 汎用 md より優先
    T.eq(file_icons.get('CLAUDE.md', false), char(0xf0bf1)) -- 汎用 md より優先
    T.eq(file_icons.get('config.hcl', false), char(0xf0c01))
    T.eq(file_icons.get('go.mod', false), char(0xe626)) -- .go と同じ Gopher
    T.eq(file_icons.get('go.sum', false), char(0xf0565)) -- md-shield_check（整合性）
    T.eq(file_icons.get('.dockerignore', false), char(0xe650)) -- Dockerと同じ
    T.eq(file_icons.get('.gitattributes', false), char(0xe65d)) -- gitignoreと同じ
    T.eq(file_icons.get('.cursorignore', false), char(0xe65d)) -- gitignoreと同じ
    T.eq(file_icons.get('.editorconfig', false), char(0xe652))
    T.eq(file_icons.get('tsconfig.json', false), char(0xe69d)) -- 汎用 json より優先
    T.eq(file_icons.get('tsconfig.app.json', false), char(0xe69d))
    -- 通常の json/md/lock、tsconfig.jsonc は据え置き
    T.eq(file_icons.get('settings.json', false), char(0xe60b))
    T.eq(file_icons.get('tsconfig.jsonc', false), char(0xe60b))
    T.eq(file_icons.get('notes.md', false), char(0xe73e))
    T.eq(file_icons.get('Cargo.lock', false), char(0xf023))
  end)

  T.it('treats mts like ts and jsonc like json', function()
    T.eq(file_icons.get('mod.mts', false), file_icons.get('mod.ts', false))
    T.eq(file_icons.get('mod.mts', false), char(0xe628))
    T.eq(file_icons.get('tsconfig.jsonc', false), file_icons.get('data.json', false))
    T.eq(file_icons.get('tsconfig.jsonc', false), char(0xe60b))
  end)

  T.it('shows docker-compose.yml/.yaml with the Docker icon, not the yaml icon', function()
    T.eq(file_icons.get('docker-compose.yml', false), char(0xe650))
    T.eq(file_icons.get('docker-compose.yaml', false), char(0xe650))
    T.eq(file_icons.get('docker-compose.override.yml', false), char(0xe650))
    -- 通常の yaml は従来どおり yaml アイコン
    T.eq(file_icons.get('config.yml', false), char(0xe6a8))
  end)

  -- 以前は explorer/tabline に yaml が無く、git_panel に tf が無いという食い違いが
  -- あった。共通化後はどちらもマッピングを持つことを保証する（リグレッション防止）。
  T.it('has both yaml/yml and tf/tfvars (the previously-missing entries)', function()
    T.eq(file_icons.get('config.yaml', false), char(0xe6a8))
    T.eq(file_icons.get('config.yml', false), char(0xe6a8))
    T.eq(file_icons.get('main.tf', false), char(0xe69a))
    T.eq(file_icons.get('vars.tfvars', false), char(0xe69a))
  end)

  T.it('handles special filenames by name, not extension', function()
    T.eq(file_icons.get('Dockerfile', false), char(0xe650))
    T.eq(file_icons.get('dockerfile', false), char(0xe650))
    T.eq(file_icons.get('.gitignore', false), char(0xe65d))
    T.eq(file_icons.get('.env', false), char(0xf462))
    T.eq(file_icons.get('.env.local', false), char(0xf462))
    T.eq(file_icons.get('package-lock.json.lock', false), char(0xf023))
  end)

  T.it('falls back to the default icon for unknown extensions and no extension', function()
    T.eq(file_icons.get('mystery.xyz', false), char(file_icons.DEFAULT))
    T.eq(file_icons.get('LICENSE', false), char(file_icons.DEFAULT))
  end)

  T.it('color() returns a brand color for known icons and nil for the default', function()
    T.eq(file_icons.color('main.lua', false), '#51a0cf')
    T.eq(file_icons.color('main.go', false), file_icons.color('go.mod', false)) -- 同じGopher色
    T.eq(file_icons.color('mystery.xyz', false), nil) -- デフォルトは色なし（文字色にフォールバック）
  end)

  T.it('color() makes test/spec files orange (VSCode風)', function()
    local orange = '#ff9e64'
    -- *.test./*.spec. + js,ts,jsx,tsx,mjs,cjs,mts,cts
    T.eq(file_icons.color('foo.test.ts', false), orange)
    T.eq(file_icons.color('foo.test.tsx', false), orange)
    T.eq(file_icons.color('foo.test.mts', false), orange)
    T.eq(file_icons.color('foo.test.cjs', false), orange)
    T.eq(file_icons.color('bar.spec.js', false), orange)
    T.eq(file_icons.color('bar.spec.jsx', false), orange)
    T.eq(file_icons.color('flow.e2e.ts', false), orange) -- *.e2e.ts
    T.eq(file_icons.color('handler_test.go', false), orange) -- *_test.go
    -- Rust: tests/ 配下（パス基準）
    T.eq(file_icons.color('foo.rs', false, '/proj/tests/foo.rs'), orange)
    T.eq(file_icons.color('foo.rs', false, 'tests/foo.rs'), orange)
    -- tests/外の .rs や *_test.rs は対象外（Rustでは一般的でない）
    T.eq(file_icons.color('lib_test.rs', false, '/proj/src/lib_test.rs'), '#dea584')
    T.eq(file_icons.color('main.rs', false, '/proj/src/main.rs'), '#dea584')
    -- 通常ファイルは従来の色、"test.ts" 単体はテスト扱いしない
    T.eq(file_icons.color('main.ts', false), '#519aba')
    T.eq(file_icons.color('test.ts', false), '#519aba')
  end)

  T.it('icon_hl() returns a highlight group for colored icons and nil otherwise', function()
    local grp = file_icons.icon_hl('main.lua', false)
    T.ok(grp ~= nil and grp:find('FileIcon_', 1, true) == 1, 'colored icon should get a FileIcon_* group')
    T.eq(vim.fn.hlexists(grp), 1) -- グループが実際に定義されている
    T.eq(file_icons.icon_hl('mystery.xyz', false), nil)
  end)

  T.it('exposes code() returning the raw codepoint', function()
    T.eq(file_icons.code('main.lua', false), 0xe620)
    T.eq(file_icons.code('dir', true), file_icons.FOLDER)
  end)
end)

T.summary()
