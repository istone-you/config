-- ファイルアイコンの共通定義（Nerd Fonts・プラグイン不使用）
--
-- explorer / git_panel / tabline がそれぞれ自前に持っていた拡張子→アイコンの
-- マッピングを一本化するモジュール。以前は3箇所に重複していて内容が食い違い、
-- 「explorerでyamlが出ない」「gitパネルでtfが出ない」等の抜けが発生していた。
-- 追加・変更はこのファイルだけで行うこと。

local M = {}

local function char(code) return vim.fn.nr2char(code) end

M.FOLDER  = 0xe5ff
M.DEFAULT = 0xf15b

-- 拡張子 → コードポイント
M.by_ext = {
  lua     = 0xe620,
  ts      = 0xe628,
  mts     = 0xe628,
  js      = 0xe74e,
  jsx     = 0xf0708,
  tsx     = 0xf0708,
  go      = 0xe626,
  py      = 0xe606,
  rs      = 0xe7a8,
  rb      = 0xe739,
  java    = 0xe738,
  kt      = 0xe634,
  swift   = 0xe755,
  html    = 0xe736,
  css     = 0xe749,
  scss    = 0xe603,
  json    = 0xe60b,
  jsonc   = 0xe60b,
  toml    = 0xe6b2,
  md      = 0xe73e,
  sh      = 0xe691,
  bash    = 0xe615,
  zsh     = 0xe615,
  vim     = 0xe62b,
  tf      = 0xe69a,
  tfvars  = 0xe69a,
  graphql = 0xe662,
  sql     = 0xe706,
  php     = 0xe73d,
  c       = 0xe61e,
  cpp     = 0xe61d,
  cs      = 0xe648,
  yaml    = 0xe6a8,
  yml     = 0xe6a8,
  xml     = 0xe619,
  png     = 0xe60d,
  jpeg    = 0xe60d,
  svg     = 0xe698,
  zip     = 0xe6aa,
  npmrc   = 0xe71e,
  hcl     = 0xf0c01,
}

-- 拡張子ではなくファイル名で判定する特殊ファイル
local SPECIAL = {
  dockerfile = 0xe650,
  gitignore  = 0xe65d,
  env        = 0xf462,
  lock       = 0xf023,
  vite       = 0xe8d7,
  sentry     = 0xe89f,
  yarn       = 0xe6a7,
  nodejs     = 0xf0399,
  readme     = 0xeda4,
  editorconfig = 0xe652,
  tsconfig     = 0xe69d,
  playwright   = 0xe863,
  claude       = 0xf0bf1,
  gomod        = 0xe626,
  gosum        = 0xf0565,
}

-- ファイル名（+ ディレクトリか否か）からアイコンのコードポイントを返す
function M.code(name, isdir)
  if isdir then return M.FOLDER end
  local lower = name:lower()
  -- Docker（Dockerfile / .dockerignore / docker-compose.*.yml）
  if lower == 'dockerfile' or lower == '.dockerignore' then return SPECIAL.dockerfile end
  -- docker-compose.yml / docker-compose.yaml（および *.override.yml 等）は
  -- yaml ではなく Docker アイコンで表示する
  if lower:match('docker%-compose.*%.ya?ml$') then return SPECIAL.dockerfile end
  -- .gitignore / .gitattributes / .cursorignore は同じアイコン
  if lower:match('gitignore') or lower == '.gitattributes' or lower == '.cursorignore' then
    return SPECIAL.gitignore
  end
  -- vite.config.ts / .mts / .js など
  if lower:match('^vite%.config%.') then return SPECIAL.vite end
  if lower:match('^playwright%.config%.') then return SPECIAL.playwright end
  if lower:match('sentry%.properties$') then return SPECIAL.sentry end
  if lower == '.editorconfig' then return SPECIAL.editorconfig end
  -- tsconfig.json / tsconfig.app.json など（.jsonc は対象外）
  if lower:match('^tsconfig.*%.json$') then return SPECIAL.tsconfig end
  if lower == 'package.json' then return SPECIAL.nodejs end
  if lower == 'claude.md' then return SPECIAL.claude end
  if lower == 'go.mod' then return SPECIAL.gomod end
  if lower == 'go.sum' then return SPECIAL.gosum end
  if lower:match('^readme') then return SPECIAL.readme end
  if lower == 'yarn.lock' then return SPECIAL.yarn end
  if lower:match('%.env') then return SPECIAL.env end
  if lower:match('%.lock$') then return SPECIAL.lock end
  local ext = name:match('%.([^%.]+)$')
  return (ext and M.by_ext[ext]) or M.DEFAULT
end

-- コードポイント → 文字
function M.char(code) return char(code) end

-- コードポイント → ブランドカラー（未定義はデフォルト文字色にフォールバック）
M.color_by_code = {
  [0xe620] = '#51a0cf',
  [0xe628] = '#519aba',
  [0xe74e] = '#cbcb41',
  [0xf0708] = '#61dafb',
  [0xe626] = '#519aba',
  [0xf0565] = '#9ece6a',
  [0xe606] = '#ffbc03',
  [0xe7a8] = '#dea584',
  [0xe739] = '#cc342d',
  [0xe738] = '#cc3e44',
  [0xe634] = '#a97bff',
  [0xe755] = '#f05138',
  [0xe736] = '#e34c26',
  [0xe749] = '#563d7c',
  [0xe603] = '#cd6799',
  [0xe60b] = '#cbcb41',
  [0xe6b2] = '#9c4221',
  [0xe73e] = '#dddddd',
  [0xe691] = '#89e051',
  [0xe615] = '#89e051',
  [0xe62b] = '#019833',
  [0xe69a] = '#7b42bc',
  [0xe662] = '#e535ab',
  [0xe706] = '#dad8d8',
  [0xe73d] = '#a074c4',
  [0xe61e] = '#599eff',
  [0xe61d] = '#f34b7d',
  [0xe648] = '#178600',
  [0xe6a8] = '#cb171e',
  [0xe619] = '#e37933',
  [0xe60d] = '#a074c4',
  [0xe698] = '#ffb13b',
  [0xe6aa] = '#eca517',
  [0xe71e] = '#cb3837',
  [0xf0c01] = '#ffffff',
  [0xe650] = '#2496ed',
  [0xe65d] = '#f54d27',
  [0xf462] = '#dfd545',
  [0xf023] = '#9c9c9c',
  [0xe8d7] = '#646cff',
  [0xe89f] = '#e1567c',
  [0xe6a7] = '#2c8ebb',
  [0xf0399] = '#8cc84b',
  [0xeda4] = '#519aba',
  [0xe652] = '#e0e0e0',
  [0xe69d] = '#519aba',
  [0xe863] = '#45ba4b',
  [0xf0bf1] = '#d97757',
  [0xe5ff] = '#7aa2f7',
}

-- ファイル名（+ ディレクトリか否か）からブランドカラーを返す
function M.color(name, isdir)
  return M.color_by_code[M.code(name, isdir)]
end

local hl_defined = {}

-- アイコンの色に対応するハイライトグループ名を返す（無ければnil）。
-- グループは遅延生成し、ColorScheme変更時に作り直す。
function M.icon_hl(name, isdir)
  local hex = M.color(name, isdir)
  if not hex then return nil end
  local grp = 'FileIcon_' .. hex:sub(2)
  if not hl_defined[grp] then
    vim.api.nvim_set_hl(0, grp, { fg = hex, default = true })
    hl_defined[grp] = true
  end
  return grp
end

vim.api.nvim_create_autocmd('ColorScheme', {
  callback = function() hl_defined = {} end,
})

-- ファイル名（+ ディレクトリか否か）からアイコン文字を返す
function M.get(name, isdir)
  return char(M.code(name, isdir))
end

return M
