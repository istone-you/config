local T = dofile(TESTS_DIR .. '/helpers.lua')
local file_icons = require('config.util.file_icons')

local function char(code) return vim.fn.nr2char(code) end

T.describe('file_icons', function()
  T.it('returns the folder icon for directories regardless of name', function()
    T.eq(file_icons.get('anything', true), char(file_icons.FOLDER))
    T.eq(file_icons.get('foo.lua', true), char(file_icons.FOLDER))
  end)

  T.it('maps known extensions to their codepoint', function()
    T.eq(file_icons.get('main.lua', false), char(0xe620))
    -- ESM/CJS の派生拡張子も本体と同じアイコンにする
    T.eq(file_icons.get('index.mjs', false), char(0xe74e))
    T.eq(file_icons.get('index.cjs', false), char(0xe74e))
    T.eq(file_icons.get('index.mts', false), char(0xe628))
    T.eq(file_icons.get('index.cts', false), char(0xe628))
    T.eq(file_icons.color('index.mjs', false), '#cbcb41')
    T.eq(file_icons.color('index.cts', false), '#519aba')
    T.eq(file_icons.get('server.go', false), char(0xe65e))
    T.eq(file_icons.get('AppConfig.pkl', false), char(0xf013)) -- Apple Pkl → fa-cog
    T.eq(file_icons.color('AppConfig.pkl', false), '#689f38')
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
    T.eq(file_icons.get('package-lock.json', false), char(0xf0399))
    T.eq(file_icons.color('package-lock.json', false), '#8cc84b')
    T.eq(file_icons.get('README.md', false), char(0xeda4)) -- 汎用 md より優先
    T.eq(file_icons.get('CLAUDE.md', false), char(0xf0bf1)) -- 汎用 md より優先
    T.eq(file_icons.get('AGENTS.md', false), char(0xf0beb))
    T.eq(file_icons.color('AGENTS.md', false), '#a97bff')
    T.eq(file_icons.get('config.hcl', false), char(0xf0c01))
    T.eq(file_icons.color('config.hcl', false), '#eceff1')
    T.eq(file_icons.get('go.mod', false), char(0xe65e))
    T.eq(file_icons.get('go.sum', false), char(0xe65e))
    T.eq(file_icons.get('go.work', false), char(0xe65e))
    T.eq(file_icons.get('go.work.sum', false), char(0xe65e))
    T.eq(file_icons.color('go.mod', false), '#ec407a')
    T.eq(file_icons.color('go.sum', false), '#ec407a')
    T.eq(file_icons.color('main.go', false), '#519aba')
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
    T.eq(file_icons.get('Makefile', false), char(file_icons.DEFAULT))
  end)

  T.it('maps newly-added extensions and special names (mdc/images/txt/crt/rego/dotfiles/license/codeowners)', function()
    -- .mdc は Markdown と同じ
    T.eq(file_icons.get('rules.mdc', false), char(0xe73e))
    T.eq(file_icons.color('rules.mdc', false), '#dddddd')
    -- 画像一式
    for _, name in ipairs({ 'a.jpg', 'a.webp', 'a.avif' }) do
      T.eq(file_icons.get(name, false), char(0xe60d))
      T.eq(file_icons.color(name, false), '#a074c4')
    end
    T.eq(file_icons.get('a.gif', false), char(0xf0d78))
    T.eq(file_icons.color('a.gif', false), '#00bfa5')
    T.eq(file_icons.get('a.ico', false), char(0xe623))
    T.eq(file_icons.color('a.ico', false), '#cbcb41')
    T.eq(file_icons.get('a.jxl', false), char(file_icons.DEFAULT))
    -- テキスト
    T.eq(file_icons.get('notes.txt', false), char(0xf15c))
    T.eq(file_icons.get('notes.text', false), char(0xf15c))
    T.eq(file_icons.color('notes.txt', false), '#6d8086')
    -- 証明書 / OPA
    T.eq(file_icons.get('server.crt', false), char(0xf0124))
    T.eq(file_icons.color('server.crt', false), '#e5c07b')
    T.eq(file_icons.get('policy.rego', false), char(0xf0498))
    T.eq(file_icons.color('policy.rego', false), '#5181b1')
    -- ドット系設定（緑）
    T.eq(file_icons.get('.zshrc', false), char(0xe615))
    T.eq(file_icons.color('.zshrc', false), '#89e051')
    T.eq(file_icons.get('.vimrc', false), char(0xe62b))
    T.eq(file_icons.color('.vimrc', false), '#019833')
    T.eq(file_icons.get('.shellcheckrc', false), char(0xe691))
    T.eq(file_icons.color('.shellcheckrc', false), '#89e051')
    -- .template
    T.eq(file_icons.get('Caddyfile.template', false), char(0xf0613))
    T.eq(file_icons.color('Caddyfile.template', false), '#9c9c9c')
    T.eq(file_icons.get('.cursorrules', false), char(0xf0bf1))
    T.eq(file_icons.color('.cursorrules', false), '#dddddd')
    T.eq(file_icons.get('CODEOWNERS', false), char(0xf09b))
    T.eq(file_icons.color('CODEOWNERS', false), '#dddddd')
    T.eq(file_icons.get('LICENSE', false), char(0xf0fc3))
    T.eq(file_icons.get('LICENCE', false), char(0xf0fc3))
    T.eq(file_icons.color('LICENSE', false), '#e5c07b')
  end)

  T.it('uses GitHub Actions icon for yaml under .github/workflows', function()
    T.eq(file_icons.get('ci.yml', false, '.github/workflows/ci.yml'), char(0xe7e9))
    T.eq(file_icons.get('ci.yaml', false, '/app/.github/workflows/ci.yaml'), char(0xe7e9))
    T.eq(file_icons.color('ci.yml', false, '.github/workflows/ci.yml'), '#2088ff')
    -- 通常の yaml や .github 直下は従来どおり
    T.eq(file_icons.get('config.yml', false, 'config/config.yml'), char(0xe6a8))
    T.eq(file_icons.get('dependabot.yml', false, '.github/dependabot.yml'), char(0xe6a8))
  end)

  T.it('uses VS Code icon for .vscode/settings.json', function()
    T.eq(file_icons.get('settings.json', false, '.vscode/settings.json'), char(0xe8da))
    T.eq(file_icons.get('settings.json', false, '/app/.vscode/settings.json'), char(0xe8da))
    T.eq(file_icons.color('settings.json', false, '.vscode/settings.json'), '#007acc')
    -- 他の settings.json は通常の json
    T.eq(file_icons.get('settings.json', false, 'config/settings.json'), char(0xe60b))
  end)

  T.it('maps codecov.yml and .devcontainer/devcontainer.json', function()
    T.eq(file_icons.get('codecov.yml', false), char(0xe797))
    T.eq(file_icons.get('.codecov.yaml', false), char(0xe797))
    T.eq(file_icons.color('codecov.yml', false), '#ec407a')
    T.eq(file_icons.get('devcontainer.json', false, '.devcontainer/devcontainer.json'), char(0xf4b7))
    T.eq(file_icons.get('devcontainer.json', false, '/app/.devcontainer/devcontainer.json'), char(0xf4b7))
    T.eq(file_icons.color('devcontainer.json', false, '.devcontainer/devcontainer.json'), '#00b0ff')
    T.eq(file_icons.get('devcontainer.json', false, 'other/devcontainer.json'), char(0xe60b))
  end)

  T.it('maps .coderabbit.yaml to md-rabbit', function()
    T.eq(file_icons.get('.coderabbit.yaml', false), char(0xf0907))
    T.eq(file_icons.get('.coderabbit.yml', false), char(0xf0907))
    T.eq(file_icons.color('.coderabbit.yaml', false), '#f4511e')
  end)

  T.it('maps wrangler configs to cloudflare', function()
    T.eq(file_icons.get('wrangler.toml', false), char(0xe792))
    T.eq(file_icons.get('wrangler.json', false), char(0xe792))
    T.eq(file_icons.get('wrangler.jsonc', false), char(0xe792))
    T.eq(file_icons.color('wrangler.toml', false), '#f57f17')
  end)

  T.it('maps pdf / csv / 設定ファイル系', function()
    T.eq(file_icons.get('manual.pdf', false), char(0xf0226))
    T.eq(file_icons.color('manual.pdf', false), '#e5252a')
    T.eq(file_icons.get('users.csv', false), char(0xeefc))
    T.eq(file_icons.color('users.csv', false), '#89e051')
    -- conf / ini / cfg / properties は pkl と同じ歯車
    T.eq(file_icons.get('nginx.conf', false), char(0xf013))
    T.eq(file_icons.get('setup.ini', false), char(0xf013))
    T.eq(file_icons.get('.flake8.cfg', false), char(0xf013))
    T.eq(file_icons.get('gradle.properties', false), char(0xf013))
    T.eq(file_icons.color('setup.ini', false), '#689f38')
    -- sentry.properties は従来どおり Sentry アイコンが優先される
    T.eq(file_icons.get('sentry.properties', false), char(0xe89f))
  end)

  T.it('maps .http / .rest request files to a globe', function()
    T.eq(file_icons.get('api.http', false), char(0xf0ac))
    T.eq(file_icons.get('api.rest', false), char(0xf0ac))
    T.eq(file_icons.color('api.http', false), '#4db6ac')
    -- 環境ファイルは汎用 json / .env より優先して同じアイコンにする
    T.eq(file_icons.get('http-client.env.json', false), char(0xf0ac))
    T.eq(file_icons.get('http-client.private.env.json', false), char(0xf0ac))
  end)

  T.it('maps ghostty configs to a ghost (拡張子でも ghostty/ 配下でも)', function()
    T.eq(file_icons.get('theme.ghostty', false), char(0xf165d))
    T.eq(file_icons.color('theme.ghostty', false), '#3551f3')
    -- 設定本体は拡張子もファイル名の特徴も無いのでパスで判定する
    T.eq(file_icons.get('config', false, '/Users/x/.config/ghostty/config'), char(0xf165d))
    T.eq(file_icons.get('config', false, 'ghostty/config'), char(0xf165d))
    -- ghostty 配下でなければ従来どおり
    T.eq(file_icons.get('config', false, '/Users/x/.config/nvim/config'), char(file_icons.DEFAULT))
  end)

  T.it('color() returns a brand color for known icons and nil for the default', function()
    T.eq(file_icons.color('main.lua', false), '#51a0cf')
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
