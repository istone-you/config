local T = dofile(TESTS_DIR .. '/helpers.lua')
local entries = require('config.code_notes.entries')

T.describe('code_notes/entries.lua', function()
  T.it('adds, lists, updates, deletes, and clears entries', function()
    entries.clear()
    local a = assert(entries.add({ text = 'first entry', file = 'a.lua', line = 2, lineEnd = 4, col = 3 }))
    local b = assert(entries.add({ text = 'second entry' }))
    T.ok(a.id ~= b.id, 'ids are unique')

    local list = entries.list()
    T.eq(#list, 2)
    T.eq(list[1].text, 'first entry')
    T.eq(list[1].file, 'a.lua')
    T.eq(list[1].lineEnd, 4)
    T.eq(list[2].file, vim.NIL)

    local updated = assert(entries.update({ id = a.id, text = 'updated entry' }))
    T.eq(updated.text, 'updated entry')

    T.eq(entries.remove(b.id), true)
    T.eq(#entries.list(), 1)
    entries.clear()
    T.eq(#entries.list(), 0)
  end)

  T.it('rejects empty text and missing ids', function()
    entries.clear()
    local f, err = entries.add({ text = '' })
    T.eq(f, nil)
    T.contains(err, 'text is required')

    local u, uerr = entries.update({ text = 'x' })
    T.eq(u, nil)
    T.contains(uerr, 'id is required')
  end)

  T.it('normalizes range aliases and clamps reversed ranges', function()
    entries.clear()
    local a = assert(entries.add({ text = 'range', file = 'a.lua', line = 4, endLine = 2 }))
    T.eq(a.line, 4)
    T.eq(a.lineEnd, 4)

    local b = assert(entries.add({ text = 'snake range', file = 'a.lua', line = 1, line_end = 3 }))
    T.eq(b.lineEnd, 3)
  end)
end)

T.summary()
