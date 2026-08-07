local T = dofile(TESTS_DIR .. '/helpers.lua')
local diff = require('config.diff_review.diff')

local function find_line(lines, pred)
  for _, l in ipairs(lines) do
    if pred(l) then return l end
  end
end

T.describe('diff_review/diff.lua parse', function()
  T.it('parses a modified file with old/new line numbers', function()
    local text = table.concat({
      'diff --git a/foo.txt b/foo.txt',
      'index 111..222 100644',
      '--- a/foo.txt',
      '+++ b/foo.txt',
      '@@ -1,3 +1,4 @@',
      ' line1',
      '-line2',
      '+line2 changed',
      '+line2b',
      ' line3',
    }, '\n')
    local m = diff.parse(text)
    T.eq(#m.files, 1)
    local f = m.files[1]
    T.eq(f.path, 'foo.txt')
    T.eq(f.status, 'M')
    T.eq(f.added, 2)
    T.eq(f.deleted, 1)
    T.eq(f.binary, false)
    T.eq(#f.hunks, 1)
    local h = f.hunks[1]
    T.eq({ h.old_start, h.old_lines, h.new_start, h.new_lines }, { 1, 3, 1, 4 })
    T.eq(#h.lines, 5)

    local ctx = h.lines[1]
    T.eq({ ctx.type, ctx.old_line, ctx.new_line, ctx.content }, { 'context', 1, 1, 'line1' })
    local del = h.lines[2]
    T.eq({ del.type, del.old_line, del.new_line }, { 'del', 2, vim.NIL })
    local add1 = h.lines[3]
    T.eq({ add1.type, add1.old_line, add1.new_line, add1.content }, { 'add', vim.NIL, 2, 'line2 changed' })
    local last = h.lines[5]
    T.eq({ last.type, last.old_line, last.new_line }, { 'context', 3, 4 })
  end)

  T.it('detects an added file', function()
    local text = table.concat({
      'diff --git a/new.txt b/new.txt',
      'new file mode 100644',
      'index 0000..2222',
      '--- /dev/null',
      '+++ b/new.txt',
      '@@ -0,0 +1,2 @@',
      '+alpha',
      '+beta',
    }, '\n')
    local f = diff.parse(text).files[1]
    T.eq(f.status, 'A')
    T.eq(f.added, 2)
    T.eq(f.deleted, 0)
    T.eq(f.path, 'new.txt')
  end)

  T.it('detects a deleted file', function()
    local text = table.concat({
      'diff --git a/gone.txt b/gone.txt',
      'deleted file mode 100644',
      'index 2222..0000',
      '--- a/gone.txt',
      '+++ /dev/null',
      '@@ -1,2 +0,0 @@',
      '-alpha',
      '-beta',
    }, '\n')
    local f = diff.parse(text).files[1]
    T.eq(f.status, 'D')
    T.eq(f.deleted, 2)
    T.eq(f.path, 'gone.txt')
  end)

  T.it('flags binary files and skips line parsing', function()
    local text = table.concat({
      'diff --git a/img.png b/img.png',
      'index 111..222 100644',
      'Binary files a/img.png and b/img.png differ',
    }, '\n')
    local f = diff.parse(text).files[1]
    T.eq(f.binary, true)
    T.eq(#f.hunks, 0)
  end)

  T.it('parses multiple files in one stream', function()
    local text = table.concat({
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1 +1 @@',
      '-old',
      '+new',
      'diff --git a/b.txt b/b.txt',
      '--- a/b.txt',
      '+++ b/b.txt',
      '@@ -1 +1,2 @@',
      ' keep',
      '+added',
    }, '\n')
    local m = diff.parse(text)
    T.eq(#m.files, 2)
    T.eq(m.files[1].path, 'a.txt')
    T.eq(m.files[2].path, 'b.txt')
  end)

  T.it('does not mistake content lines starting with --/++ for file headers', function()
    -- 中身が "--" / "++" で始まる行は、diff 上では "---"/"+++" に見えるが
    -- ファイルヘッダではなく削除/追加行。行番号がずれないことを確かめる。
    local text = table.concat({
      'diff --git a/c.md b/c.md',
      '--- a/c.md',
      '+++ b/c.md',
      '@@ -1,3 +1,3 @@',
      ' keep',
      '--- old heading',
      '+++ new heading',
      ' tail',
    }, '\n')
    local f = diff.parse(text).files[1]
    T.eq(f.path, 'c.md')
    T.eq(f.added, 1)
    T.eq(f.deleted, 1)
    local h = f.hunks[1]
    T.eq(#h.lines, 4)
    T.eq({ h.lines[1].type, h.lines[1].old_line, h.lines[1].new_line }, { 'context', 1, 1 })
    T.eq({ h.lines[2].type, h.lines[2].content, h.lines[2].old_line }, { 'del', '-- old heading', 2 })
    T.eq({ h.lines[3].type, h.lines[3].content, h.lines[3].new_line }, { 'add', '++ new heading', 2 })
    T.eq({ h.lines[4].type, h.lines[4].old_line, h.lines[4].new_line }, { 'context', 3, 3 })
  end)

  T.it('treats an omitted hunk count as 1', function()
    local h = diff._private.parse_hunk_header('@@ -5 +7 @@ ctx')
    T.eq({ h.old_start, h.old_lines, h.new_start, h.new_lines }, { 5, 1, 7, 1 })
  end)
end)

T.describe('diff_review/diff.lua build (git)', function()
  T.it('collects tracked changes and untracked files from a real repo', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/tracked.txt', { 'one', 'two', 'three' })
      T.git(d, { '-C', d, 'add', '-A' })
      T.git(d, { '-C', d, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'add tracked' })
    end)
    -- modify tracked (unstaged) and add an untracked file
    T.write_file(dir .. '/tracked.txt', { 'one', 'TWO', 'three' })
    T.write_file(dir .. '/fresh.txt', { 'brand new' })

    local model
    diff.build(vim.fs.normalize(dir), function(m) model = m end)
    T.wait_until(function() return model ~= nil end)

    local paths = {}
    for _, f in ipairs(model.files) do paths[f.path] = f end
    T.ok(paths['tracked.txt'], 'tracked change should appear')
    T.ok(paths['fresh.txt'], 'untracked file should appear')
    T.eq(paths['fresh.txt'].status, 'A')

    T.rmrf(dir)
  end)

  T.it('build_views separates all / staged / unstaged', function()
    local dir = T.tmp_git_repo(function(d)
      T.write_file(d .. '/f.txt', { 'a', 'b', 'c' })
      T.git(d, { '-C', d, 'add', '-A' })
      T.git(d, { '-C', d, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'base' })
    end)
    -- 2行目をステージ、3行目は未ステージ、さらに未追跡ファイルを1つ
    T.write_file(dir .. '/f.txt', { 'a', 'B', 'c' })
    T.git(dir, { '-C', dir, 'add', 'f.txt' })
    T.write_file(dir .. '/f.txt', { 'a', 'B', 'cc' })
    T.write_file(dir .. '/fresh.txt', { 'new' })

    local views
    diff.build_views(vim.fs.normalize(dir), function(v) views = v end)
    T.wait_until(function() return views ~= nil end)

    local function paths(model)
      local out = {}
      for _, f in ipairs(model.files) do out[f.path] = true end
      return out
    end
    local all, staged, unstaged = paths(views.all), paths(views.staged), paths(views.unstaged)

    T.ok(all['f.txt'] and all['fresh.txt'], 'all should contain both the change and the untracked file')
    T.ok(staged['f.txt'], 'staged should contain the staged change')
    T.ok(not staged['fresh.txt'], 'staged must NOT contain the untracked file')
    T.ok(unstaged['fresh.txt'], 'unstaged should contain the untracked file')

    T.rmrf(dir)
  end)
end)

T.summary()
