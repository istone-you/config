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
    T.eq(list[1].status, 'open')
    T.eq(#list[1].comments, 0)
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

  T.it('sets status and manages comments on an entry', function()
    entries.clear()
    local a = assert(entries.add({ text = 'needs follow-up', file = 'a.lua', line = 1 }))

    local closed = assert(entries.set_status(a.id, 'closed'))
    T.eq(closed.status, 'closed')

    local reopened = assert(entries.set_status(a.id, 'unexpected value becomes open'))
    T.eq(reopened.status, 'open')

    local with_comment, comment = entries.add_comment({ id = a.id, text = 'checked this', author = 'human' })
    with_comment = assert(with_comment)
    comment = assert(comment)
    T.eq(comment.author, 'human')
    T.eq(#with_comment.comments, 1)
    T.eq(with_comment.comments[1].text, 'checked this')

    local after_delete = assert(entries.remove_comment(a.id, comment.id))
    T.eq(#after_delete.comments, 0)
  end)

  T.it('normalizes comments when setting entries in bulk', function()
    entries.clear()
    entries.set({
      {
        id = 'f9',
        text = 'bulk with comments',
        status = 'closed',
        comments = {
          { id = 'c7', text = 'kept', author = 'human' },
          { text = '' },
        },
      },
    })
    local list = entries.list()
    T.eq(list[1].status, 'closed')
    T.eq(#list[1].comments, 1)
    T.eq(list[1].comments[1].id, 'c7')

    local entry, comment = entries.add_comment({ id = 'f9', text = 'next comment' })
    entry = assert(entry)
    comment = assert(comment)
    T.eq(comment.id, 'c8')
    T.eq(#entry.comments, 2)
  end)
end)

T.summary()
