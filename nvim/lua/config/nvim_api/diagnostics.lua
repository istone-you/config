-- 診断(LSP/linter)を AI へ返すための収集・整形・集計。
--
-- problems.lua と同じ vim.diagnostic.get(nil) を読むが、あちらはパネル表示用に
-- 「現在のフィルタ」というモジュール状態を持っている。API は毎リクエスト独立であってほしいので
-- ここは引数だけで完結する純粋な収集にしてある。
--
-- 注意: LSP の診断は「サーバーが報告したぶん」しか無い。まだ開いていないファイルの問題は
-- 出ないことがある(gopls / tsserver のようにプロジェクト単位で報告するサーバーは出る)。
-- 特定ファイルを確実に見たいときは先に /api/buffers/load でロードさせること。

local M = {}
local util = require('config.nvim_api.util')

local S = vim.diagnostic.severity

M.SEVERITY_NAME = {
  [S.ERROR] = 'error',
  [S.WARN]  = 'warn',
  [S.INFO]  = 'info',
  [S.HINT]  = 'hint',
}

local NAME_SEVERITY = {
  error = S.ERROR, err = S.ERROR, e = S.ERROR,
  warn = S.WARN, warning = S.WARN, w = S.WARN,
  info = S.INFO, information = S.INFO, i = S.INFO,
  hint = S.HINT, h = S.HINT,
}

--- severity 指定を「これ以上の重要度だけ」の閾値へ。既定は HINT(=すべて)。
function M.min_severity(spec)
  if spec == nil or spec == '' then return S.HINT end
  if type(spec) == 'number' then return spec end
  return NAME_SEVERITY[tostring(spec):lower()] or S.HINT
end

--- 診断を集めて API 用の形へ。
--- opts = { file, severity, root, max }
--- 戻り値: items(配列), truncated(件数を max で切ったか)
function M.collect(opts)
  opts = opts or {}
  local min = M.min_severity(opts.severity)
  local root = util.normalize_root(opts.root)
  local want = (opts.file and opts.file ~= '') and util.abs_path(opts.file, root) or nil

  local items = {}
  for _, d in ipairs(vim.diagnostic.get(nil)) do
    if d.severity <= min and vim.api.nvim_buf_is_valid(d.bufnr) then
      local name = vim.api.nvim_buf_get_name(d.bufnr)
      if name ~= '' then
        local abs = util.real(name)
        if not want or abs == want then
          items[#items + 1] = {
            file     = util.rel_path(abs, root),
            line     = d.lnum + 1, -- 診断は 0-based
            col      = d.col + 1,
            end_line = (d.end_lnum or d.lnum) + 1,
            end_col  = (d.end_col or d.col) + 1,
            severity = M.SEVERITY_NAME[d.severity] or 'hint',
            -- 複数行メッセージは 1 行に潰す(JSON で読みやすくするため)
            message  = (d.message or ''):gsub('%s*\n%s*', ' '),
            source   = util.or_null(d.source),
            code     = d.code ~= nil and tostring(d.code) or vim.NIL,
          }
        end
      end
    end
  end

  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    if a.line ~= b.line then return a.line < b.line end
    return a.col < b.col
  end)

  local truncated = false
  local max = opts.max
  if max and max > 0 and #items > max then
    -- 診断は数千件になることがある。全部返すと AI のコンテキストを食い潰すので上限を設ける。
    local cut = {}
    for i = 1, max do cut[i] = items[i] end
    items = cut
    truncated = true
  end

  return items, truncated
end

--- ファイル別の件数と全体の集計。「どこが燃えているか」だけ知りたいとき用。
--- 生の診断を全部返さずに済むので、まずこちらを見てから file 指定で掘るのが基本。
function M.summary(items)
  local by_file = {}
  local order = {}
  local totals = { error = 0, warn = 0, info = 0, hint = 0 }
  for _, it in ipairs(items or {}) do
    local f = by_file[it.file]
    if not f then
      f = { file = it.file, error = 0, warn = 0, info = 0, hint = 0, total = 0 }
      by_file[it.file] = f
      order[#order + 1] = f
    end
    f[it.severity] = (f[it.severity] or 0) + 1
    f.total = f.total + 1
    totals[it.severity] = (totals[it.severity] or 0) + 1
  end
  -- 問題が多い順(= hotspot)。同数ならパス順で安定させる。
  table.sort(order, function(a, b)
    if a.error ~= b.error then return a.error > b.error end
    if a.total ~= b.total then return a.total > b.total end
    return a.file < b.file
  end)
  return {
    files = order,
    totals = totals,
    total = (totals.error + totals.warn + totals.info + totals.hint),
  }
end

return M
