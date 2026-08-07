local T = dofile(TESTS_DIR .. '/helpers.lua')
local ports = require('config.ports_panel.ports')

-- lsof -nP -i -F pcLPnTf 相当のフィールド出力（f がソケット境界）。
-- node は同じポートを2つのfdで持ち(dedupe対象)、確立済み接続も1本持っている。
-- postgres は TCP LISTEN と UDP バインドの両方、Chrome は IPv6 の接続と SYN_SENT を持つ。
local FIXTURE = table.concat({
  'p111', 'cnode', 'Listone',
  'f20', 'PTCP', 'n*:3000', 'TST=LISTEN', 'TQR=0', 'TQS=0',
  'f21', 'PTCP', 'n*:3000', 'TST=LISTEN',
  'f22', 'PTCP', 'n127.0.0.1:3000->127.0.0.1:54321', 'TST=ESTABLISHED',
  'p222', 'cpostgres', 'Lpostgres',
  'f5', 'PTCP', 'n127.0.0.1:5432', 'TST=LISTEN',
  'f6', 'PUDP', 'n*:5353',
  'p333', 'cGoogle Chrome', 'Listone',
  'f9', 'PTCP', 'n[fe80::1]:8080->[fe80::2]:443', 'TST=ESTABLISHED',
  'f10', 'PTCP', 'n*:1024', 'TST=SYN_SENT',
}, '\n')

T.describe('ports.split_name', function()
  T.it('splits address, port and peer for v4 / v6 / wildcard', function()
    local addr, port, peer = ports.split_name('*:8000')
    T.eq({ addr, port, peer }, { '*', '8000', nil })

    addr, port, peer = ports.split_name('127.0.0.1:5432')
    T.eq({ addr, port, peer }, { '127.0.0.1', '5432', nil })

    addr, port, peer = ports.split_name('127.0.0.1:5432->127.0.0.1:1234')
    T.eq({ addr, port, peer }, { '127.0.0.1', '5432', '127.0.0.1:1234' })
  end)

  T.it('strips brackets from IPv6 addresses without eating the port', function()
    local addr, port, peer = ports.split_name('[fe80::1]:59500')
    T.eq({ addr, port, peer }, { 'fe80::1', '59500', nil })

    addr, port, peer = ports.split_name('[fe80::1]:59500->[fe80::2]:59470')
    T.eq({ addr, port, peer }, { 'fe80::1', '59500', '[fe80::2]:59470' })
  end)

  T.it('keeps an unbound UDP port as *', function()
    local addr, port = ports.split_name('*:*')
    T.eq({ addr, port }, { '*', '*' })
  end)
end)

T.describe('ports.parse', function()
  T.it('reads process fields and carries them onto every socket of that process', function()
    local entries = ports.parse(FIXTURE)
    T.eq(#entries, 7)

    local first = entries[1]
    T.eq(first.pid, 111)
    T.eq(first.command, 'node')
    T.eq(first.user, 'istone')
    T.eq(first.fd, '20')
    T.eq(first.proto, 'TCP')
    T.eq(first.state, 'LISTEN')
    T.eq(first.port, '3000')
  end)

  T.it('keeps command names containing spaces intact', function()
    local entries = ports.parse(FIXTURE)
    local chrome = entries[#entries]
    T.eq(chrome.command, 'Google Chrome')
    T.eq(chrome.pid, 333)
  end)

  T.it('leaves state nil for UDP sockets and ignores TQR/TQS lines', function()
    local udp
    for _, e in ipairs(ports.parse(FIXTURE)) do
      if e.proto == 'UDP' then udp = e end
    end
    T.ok(udp ~= nil, 'fixture should contain a UDP socket')
    T.eq(udp.state, nil)
    T.eq(udp.port, '5353')
  end)

  T.it('returns an empty list for empty or garbage input', function()
    T.eq(ports.parse(''), {})
    T.eq(ports.parse(nil), {})
    -- n(名前)が無いブロックは行として成立しないので落とす
    T.eq(ports.parse('p1\ncfoo\nf3\nPTCP'), {})
  end)

  T.it('yields nothing when f (fd) lines are missing — lsof -F must request f', function()
    -- -F に f が無い実出力に相当。ソケット境界が立たず P/n/T を取りこぼす
    local without_f = table.concat({
      'p111', 'cnode', 'Listone',
      'PTCP', 'n*:3000', 'TST=LISTEN',
    }, '\n')
    T.eq(ports.parse(without_f), {})
  end)
end)

T.describe('ports.sockets', function()
  T.it('asks lsof for the f field so parse can see socket boundaries', function()
    local seen
    local orig = ports.run
    ports.run = function(cmd, cb, opts)
      seen = cmd
      if cb then cb({ stdout = FIXTURE, code = 0 }) end
    end
    local entries
    ports.sockets(function(e) entries = e end)
    ports.run = orig

    local f_arg
    for i, a in ipairs(seen) do
      if a == '-F' then f_arg = seen[i + 1]; break end
    end
    T.ok(f_arg ~= nil, '-F must be present')
    T.ok(f_arg:find('f', 1, true) ~= nil, '-F must include f (got ' .. tostring(f_arg) .. ')')
    T.eq(#entries, 7)
  end)
end)

T.describe('ports.listening', function()
  local list = ports.listening(ports.parse(FIXTURE))

  T.it('collapses the same port held by multiple fds into one row', function()
    local count = 0
    for _, e in ipairs(list) do
      if e.pid == 111 and e.port == '3000' then count = count + 1 end
    end
    T.eq(count, 1, 'node:3000 should appear once even though lsof lists fd 20 and 21')
  end)

  T.it('includes TCP LISTEN and bound UDP, sorted by port number', function()
    local got = {}
    for _, e in ipairs(list) do
      table.insert(got, e.port .. '/' .. e.proto .. ' ' .. e.command)
    end
    T.eq(got, {
      '3000/TCP node',
      '5353/UDP postgres',
      '5432/TCP postgres',
    })
  end)

  T.it('excludes established connections and transient states', function()
    for _, e in ipairs(list) do
      T.ok(e.state ~= 'ESTABLISHED', 'established sockets must not be listed as listening')
      T.ok(e.state ~= 'SYN_SENT', 'SYN_SENT must not be listed as listening')
    end
  end)
end)

T.describe('ports.established', function()
  local list = ports.established(ports.parse(FIXTURE))

  T.it('lists only ESTABLISHED sockets with their peer, sorted by port', function()
    T.eq(#list, 2)
    T.eq(list[1].port, '3000')
    T.eq(list[1].command, 'node')
    T.eq(list[1].peer, '127.0.0.1:54321')
    T.eq(list[2].port, '8080')
    T.eq(list[2].command, 'Google Chrome')
    T.eq(list[2].peer, '[fe80::2]:443')
  end)
end)

T.describe('ports.dedupe / sort_by_port', function()
  T.it('dedupes on the given key fields only', function()
    local input = {
      { pid = 1, port = '80' }, { pid = 1, port = '80' }, { pid = 2, port = '80' },
    }
    T.eq(#ports.dedupe(input, { 'pid', 'port' }), 2)
    T.eq(#ports.dedupe(input, { 'port' }), 1)
  end)

  T.it('sorts numerically, not lexically, and pushes non-numeric ports last', function()
    local input = {
      { port = '8080', proto = 'TCP', command = 'a', pid = 1 },
      { port = '80', proto = 'TCP', command = 'b', pid = 2 },
      { port = '*', proto = 'UDP', command = 'c', pid = 3 },
      { port = '443', proto = 'TCP', command = 'd', pid = 4 },
    }
    local got = vim.tbl_map(function(e) return e.port end, ports.sort_by_port(input))
    T.eq(got, { '80', '443', '8080', '*' })
  end)
end)

T.describe('ports.check', function()
  T.it('fails with a message when lsof is not installed', function()
    local orig = ports.bin
    ports.bin = 'definitely-not-a-real-binary-xyz'
    local ok, msg
    ports.check(function(o, m) ok, msg = o, m end)
    ports.bin = orig
    T.eq(ok, false)
    T.contains(msg, 'lsof')
  end)
end)

T.summary()
