-- インデントの自動検出（VSCode の editor.detectIndentation 相当）
--
-- 優先順位:
--   1. .editorconfig  … Neovim 0.9+ に組み込みで既定 ON。あればそちらが正なので何もしない
--   2. 中身からの自動検出（このファイル）… 開いたファイルの行頭空白を数えて推測する
--   3. 既定値（options.lua の expandtab / shiftwidth=2）
--
-- なぜ必要か: 素の Neovim の既定は ts=8 / sw=8 / noexpandtab で、lua や typescript には
-- 幅を設定する ftplugin が無い。そのままだと 2 スペースのファイルで `>>` や
-- autopairs の <CR> 展開がハードタブを挿入してしまう。

local M = {}

M.MAX_LINES = 200 -- 走査する行数の上限（先頭から。大きなファイルでも十分な精度が出る）
M.MAX_WIDTH = 8   -- インデント幅として認める上限

--- 行頭の空白を見て「タブ行か / スペース何個か」を返す。
--- 空行・空白のみの行、および行頭が `*` の行（JSDoc やブロックコメントの継続行は
--- 1 スペースずれるため、幅 1 や 3 を誤検出させる）は対象外として nil を返す。
---@param line string
---@return 'tab'|'space'|nil kind
---@return integer width スペースの個数（kind == 'space' のときのみ意味を持つ）
function M.classify(line)
  local ws, rest = line:match('^([ \t]*)(.*)$')
  if rest == '' then return nil, 0 end         -- 空行 / 空白のみ
  if rest:sub(1, 1) == '*' then return nil, 0 end -- ブロックコメントの継続行
  if ws == '' then return nil, 0 end           -- インデントなし（判定材料にならない）
  if ws:find('\t', 1, true) then return 'tab', 0 end
  return 'space', #ws
end

--- 行の配列からインデント設定を推測する（純粋関数）
---@param lines string[]
---@return { expandtab: boolean, width: integer|nil }|nil 判定できなければ nil
function M.detect(lines)
  local tab_lines = 0
  local indents   = {} -- 出現順のスペースインデント幅
  local scanned   = 0

  for _, line in ipairs(lines) do
    scanned = scanned + 1
    if scanned > M.MAX_LINES then break end
    local kind, width = M.classify(line)
    if kind == 'tab' then
      tab_lines = tab_lines + 1
    elseif kind == 'space' then
      table.insert(indents, width)
    end
  end

  -- タブ優勢ならタブ。幅は既定（tabstop）に任せるので width は返さない
  if tab_lines > #indents and tab_lines > 0 then
    return { expandtab = false }
  end
  if #indents == 0 then return nil end

  -- 隣り合うインデント行の「増分」を多数決する。1 段深くなった量がそのまま
  -- shiftwidth になるので、絶対値の最頻値（4 と 8 が混ざると壊れる）より頑健
  local votes = {}
  local prev  = indents[1]
  for i = 2, #indents do
    local diff = indents[i] - prev
    if diff > 0 and diff <= M.MAX_WIDTH then
      votes[diff] = (votes[diff] or 0) + 1
    end
    prev = indents[i]
  end

  local best, best_votes = nil, 0
  for width, count in pairs(votes) do
    -- 同数なら狭いほうを採る（2 と 4 が同数なら 2 段ぶんの 4 が混ざっているとみなす）
    if count > best_votes or (count == best_votes and best and width < best) then
      best, best_votes = width, count
    end
  end

  if not best then
    -- 増分が取れない（全行が同じ深さ等）ときは最小の正のインデントを採用する
    local min
    for _, w in ipairs(indents) do
      if w > 0 and (not min or w < min) then min = w end
    end
    if not min or min > M.MAX_WIDTH then return nil end
    best = min
  end

  return { expandtab = true, width = best }
end

--- .editorconfig が効く位置のファイルか（効くなら自動検出はしない）
---@param path string
---@return boolean
function M.has_editorconfig(path)
  if path == '' then return false end
  return #vim.fs.find('.editorconfig', { upward = true, path = vim.fs.dirname(path) }) > 0
end

--- バッファに検出結果を適用する
---@param buf integer
---@return { expandtab: boolean, width: integer|nil }|nil 適用した内容（何もしなければ nil）
function M.apply(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  if vim.bo[buf].buftype ~= '' then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return nil end
  if M.has_editorconfig(name) then return nil end

  local lines  = vim.api.nvim_buf_get_lines(buf, 0, M.MAX_LINES, false)
  local result = M.detect(lines)
  if not result then return nil end

  vim.bo[buf].expandtab = result.expandtab
  if result.width then
    vim.bo[buf].shiftwidth  = result.width
    vim.bo[buf].tabstop     = result.width
    vim.bo[buf].softtabstop = result.width
  end
  return result
end

-- FileType（ftplugin）より後に走らせたいので schedule する。
-- editorconfig も BufReadPost 契機なので、順序に依らず apply 側で .editorconfig の
-- 有無を見て降りるようにしてある。
vim.api.nvim_create_autocmd('BufReadPost', {
  group    = vim.api.nvim_create_augroup('user_indent_detect', { clear = true }),
  callback = function(ev)
    vim.schedule(function() M.apply(ev.buf) end)
  end,
})

return M
