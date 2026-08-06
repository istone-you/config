-- Connectionsパネル: 確立済みの接続と、その接続元プロセス

return require('config.ports_panel.view').new({
  name = 'connections',
  kind = 'connections',
  title = '確立済み接続',
  empty = '(確立済みの接続はありません)',
})
