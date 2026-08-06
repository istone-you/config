-- Listeningパネル: 待ち受け中のポートと、それを掴んでいるプロセス

return require('config.ports_panel.view').new({
  name = 'listening',
  kind = 'listening',
  title = '待ち受けポート',
  empty = '(待ち受け中のポートはありません)',
})
