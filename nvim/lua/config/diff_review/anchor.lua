-- コメントの再アンカー(hunk の annotation anchor / fingerprint / stale 相当)。
--
-- 素朴に絶対行番号へ固定すると、差分が更新されるたびにコメントが別の行を指す/消える。
-- hunk はコメントを「行の内容＋前後コンテキスト」でアンカーし、リロード時に新しい差分へ
-- 追従させ、見つからなければ stale(outdated) として残す。ここでも同じ方針を取る。
--
-- capture(): コメント作成時にアンカー行の本文＋前後 CONTEXT 行を控える(fingerprint)。
-- reanchor(): 差分更新のたびに、控えた本文を新しい差分から探して line を貼り直す。
--             見つからなければ c.outdated=true(位置は最後の値のまま保持)。

local M = {}

local CONTEXT = 3

-- 指定ファイル・サイドの (行番号, 本文) を出現順で返す + 行番号→本文のマップ。
-- new 側は new_line、old 側は old_line を使う(反対側が vim.NIL の行はスキップ)。
local function side_lines(model, path, side)
  for _, f in ipairs((model and model.files) or {}) do
    if f.path == path then
      local list, byline = {}, {}
      for _, h in ipairs(f.hunks or {}) do
        for _, ln in ipairs(h.lines or {}) do
          local n = (side == 'new') and ln.new_line or ln.old_line
          if n ~= nil and n ~= vim.NIL then
            list[#list + 1] = { line = n, text = ln.content }
            byline[n] = ln.content
          end
        end
      end
      return list, byline
    end
  end
  return nil, nil
end

--- コメント作成時のアンカー(fingerprint)を作る。{ text, before[], after[] }。
--- 行が現在の差分に無ければ text=nil(=以後は追従できず outdated 扱いになりうる)。
function M.capture(model, path, side, line)
  local list, byline = side_lines(model, path, side)
  if not list then return nil end
  local idx
  for i, e in ipairs(list) do
    if e.line == line then idx = i break end
  end
  local before, after = {}, {}
  if idx then
    for i = math.max(1, idx - CONTEXT), idx - 1 do before[#before + 1] = list[i].text end
    for i = idx + 1, math.min(#list, idx + CONTEXT) do after[#after + 1] = list[i].text end
  end
  return { text = byline[line], before = before, after = after }
end

-- 候補行 index i の前後コンテキストが、控えた before/after とどれだけ一致するか。
local function context_score(list, i, anchor)
  local score = 0
  local before = anchor.before or {}
  for k = 1, #before do
    local li = list[i - k]
    -- before は [遠い..近い] の順。近い(before[#before])を list[i-1] と比べる。
    if li and li.text == before[#before - k + 1] then score = score + 1 end
  end
  local after = anchor.after or {}
  for k = 1, #after do
    local li = list[i + k]
    if li and li.text == after[k] then score = score + 1 end
  end
  return score
end

--- コメント c を新しい差分 model に貼り直す(c.line / c.line_end / c.outdated を書き換える)。
--- 1) 同じ (side,line) に同じ本文が残っていればそのまま
--- 2) 本文が別の行へ動いていれば、コンテキスト最良・距離最小の行へ再アンカー
--- 3) 本文が見つからなければ outdated=true(line は最後の値を保持)
function M.reanchor(c, model)
  local list, byline = side_lines(model, c.file, c.side)
  local anchor = (c.anchor ~= nil and c.anchor ~= vim.NIL) and c.anchor or nil
  local text = anchor and anchor.text or nil

  if not list then
    c.outdated = true
    return
  end

  -- 1) 完全一致(本文未記録なら行の存在だけで可)
  if byline[c.line] ~= nil and (text == nil or byline[c.line] == text) then
    c.outdated = false
    return
  end

  -- 2) 本文で探して再アンカー
  if text ~= nil then
    local best, best_score
    for i, e in ipairs(list) do
      if e.text == text then
        -- コンテキスト一致を優先し(重み大)、同点は元の行に近い方
        local score = context_score(list, i, anchor) * 1000 - math.abs(e.line - c.line)
        if best_score == nil or score > best_score then
          best_score = score; best = e
        end
      end
    end
    if best then
      if c.line_end ~= nil and c.line_end ~= vim.NIL then
        c.line_end = best.line + (c.line_end - c.line)
      end
      c.line = best.line
      c.outdated = false
      return
    end
  end

  -- 3) 見つからない → outdated(位置は最後の値のまま残す)
  c.outdated = true
end

M._private = {
  side_lines = side_lines,
  context_score = context_score,
  CONTEXT = CONTEXT,
}

return M
