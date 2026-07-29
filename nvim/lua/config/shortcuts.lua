local M = {}

local win       = nil
local buf       = nil
local hl_ns     = vim.api.nvim_create_namespace('shortcuts_hl')
local augrp     = vim.api.nvim_create_augroup('shortcuts', { clear = true })
local cur_tab   = 1
local query     = ''

-- ══════════════════════════════════════════════
-- データ定義
-- ══════════════════════════════════════════════

local TABS = { 'Neovim', 'yazi', 'lazygit', 'herdr' }

local DATA = {}

DATA[1] = {
  { header = '🧭 移動（ノーマル）', color = 'ShortcutsNormal', rows = {
    { 'h j k l',         '左・下・上・右' },
    { 'w / W',           '次の単語の先頭へ' },
    { 'b / B',           '前の単語の先頭へ' },
    { 'e / E',           '次の単語の末尾へ' },
    { '0 / ^ / $',       '行頭(列0) / 非空白 / 行末' },
    { 'gg / G',          'ファイル先頭 / 末尾' },
    { '{N}G',            'N行目へジャンプ' },
    { '%',               '対応する括弧へ' },
    { 'Ctrl-d / Ctrl-u', '半画面下 / 上' },
    { 'Ctrl-f / Ctrl-b', '1画面下 / 上' },
    { 'zz / zt / zb',   '現在行を中央/上部/下部に' },
    { 'H / M / L',       '画面上部・中央・下部へ' },
    { "'-",              '最後の変更行へ' },
    { '``',              '直前のカーソル位置へ' },
    { 'gi',              '最後にインサートした位置へ' },
  }},
  { header = '✏️  編集（ノーマル）', color = 'ShortcutsNormal', rows = {
    { 'x / X',           'カーソル下/前の文字を削除' },
    { 'dd / D',          '行削除 / 行末まで削除' },
    { 'yy / Y',          '行をヤンク' },
    { 'p / P',           'カーソル後/前にペースト' },
    { 'u / Ctrl-r',      'アンドゥ / リドゥ' },
    { '.',               '直前の変更を繰り返す' },
    { 'r{c} / R',        '1文字置換 / 置換モード' },
    { '~ / gu / gU',     '大小切替 / 小文字 / 大文字' },
    { 'J',               '次の行を現在行に結合' },
    { 'cc / C / s / S',  '行/行末/1文字/行 削除→挿入' },
    { '>> / <<',         'インデント増やす/減らす' },
    { 'gcc',             '現在行をコメントトグル' },
  }},
  { header = '📝 インサートモード', color = 'ShortcutsInsert', rows = {
    { 'i / I',           'カーソル前 / 行先頭から挿入' },
    { 'a / A',           'カーソル後 / 行末から挿入' },
    { 'o / O',           '下 / 上に新規行を作り挿入' },
    { 'Esc / Ctrl-[',    'ノーマルモードへ戻る' },
    { 'Ctrl-w',          '直前の単語を削除' },
    { 'Ctrl-u',          '行先頭まで削除' },
    { 'Ctrl-n / Ctrl-p', '補完候補を次/前へ' },
    { 'Ctrl-r{reg}',     'レジスタの内容を挿入' },
    { 'Ctrl-o{cmd}',     'ノーマルコマンドを1回実行' },
  }},
  { header = '🔷 ビジュアルモード', color = 'ShortcutsVisual', rows = {
    { 'v / V / Ctrl-v',  '文字 / 行 / 矩形 選択' },
    { 'gv',              '前回の選択を再選択' },
    { 'o',               '選択範囲の反対端へ移動' },
    { 'd / y / c / p',   '削除/コピー/変更/ペースト' },
    { '> / <',           'インデント増やす/減らす' },
    { '~ / u / U',       '大小切替 / 小文字 / 大文字' },
    { 'I / A',           '矩形選択の各行先頭/末尾へ挿入' },
    { 'gc',              '選択範囲をコメントトグル' },
  }},
  { header = '📦 テキストオブジェクト', color = 'ShortcutsText', rows = {
    { 'iw / aw',         '単語の内側 / 外側' },
    { 'ip / ap',         '段落の内側 / 外側' },
    { 'i( / a(',         '() の内側 / 外側' },
    { 'i[ / a[',         '[] の内側 / 外側' },
    { 'i{ / a{',         '{} の内側 / 外側' },
    { 'i" / a"',         '"" の内側 / 外側' },
    { "i' / a'",         "'' の内側 / 外側" },
    { 'it / at',         'HTMLタグの内側 / 外側' },
  }},
  { header = '🔍 検索', color = 'ShortcutsSearch', rows = {
    { '/pattern',        '前方検索' },
    { '?pattern',        '後方検索' },
    { 'n / N',           '次 / 前のマッチへ' },
    { '* / #',           'カーソル下の単語を前/後方検索' },
    { ':noh',            'ハイライトを消去' },
    { 'f{c} / F{c}',     '行内を{c}で前/後方検索' },
    { 't{c} / T{c}',     '{c}の1文字前/後ろへ移動' },
    { '; / ,',           'f/t を繰り返す / 逆方向に' },
  }},
  { header = '🪟 ウィンドウ操作', color = 'ShortcutsWindow', rows = {
    { 'Ctrl-w s / v',    '水平 / 垂直分割' },
    { 'Ctrl-w h/j/k/l',  '左/下/上/右のウィンドウへ' },
    { 'Ctrl-w q / o',    'ウィンドウを閉じる / 他を閉じる' },
    { 'Ctrl-w =',        'すべてのウィンドウを均等に' },
    { 'Ctrl-w +/- >/<',  '高さ増減 / 幅増減' },
    { 'Ctrl-w T',        'ウィンドウを新規タブに移動' },
  }},
  { header = '📑 タブ・バッファ', color = 'ShortcutsBuffer', rows = {
    { ':tabnew / :tabc', '新規タブ / タブを閉じる' },
    { 'gt / gT',         '次 / 前のタブへ' },
    { ':bn / :bp / :bd', '次/前のバッファ / 削除' },
    { 'Ctrl-^',          '直前のバッファへ切り替え' },
  }},
  { header = '💻 コマンドラインモード', color = 'ShortcutsCommand', rows = {
    { ':w / :w!',        '保存 / 強制保存' },
    { ':q / :q!',        '終了 / 強制終了' },
    { ':wq / :x',        '保存して終了' },
    { ':e {file} / :e!', 'ファイルを開く / 再読み込み' },
    { ':%s/old/new/gc',  '確認しながら置換' },
    { ':! {cmd}',        'シェルコマンドを実行' },
  }},
  { header = '📌 マーク・ジャンプ', color = 'ShortcutsSearch', rows = {
    { 'm{a-z} / m{A-Z}', 'ローカル / グローバルマーク' },
    { "'{mark}",         'マークの行先頭へジャンプ' },
    { 'Ctrl-o / Ctrl-i', 'ジャンプリストを前 / 次へ' },
    { 'g; / g,',         '変更リストを前 / 次へ' },
  }},
  { header = '⚙️  マクロ・レジスタ', color = 'ShortcutsMacro', rows = {
    { 'q{a-z} → q',      'マクロの記録 開始 / 終了' },
    { '@{a-z} / @@',     'マクロを実行 / 直前を再実行' },
    { '"+y / "+p',       'クリップボードにコピー / ペースト' },
    { ':reg',            'レジスタ一覧を表示' },
  }},
  { header = '🔧 カスタムキーマップ', color = 'ShortcutsBuffer', rows = {
    { 'Space t',         'ターミナルを右に開く' },
    { 'Ctrl-h / Ctrl-l', '左 / 右のウィンドウへ移動（エディタ↔ターミナル・explorer）' },
    { 'Space e',         'explorerを開閉（右パネル、詳細は下のセクション）' },
    { 'Space g',         'gitパネルを開閉（自作、詳細は下のセクション）' },
    { 'Tab / Shift-Tab', '次 / 前のバッファへ' },
    { 'Space q',         '現在のバッファを閉じる' },
    { ':q / :qa 等',     '通常の終了コマンド。Neovimを閉じる直前に確認が入る（:q! など ! 付きは確認なしで即終了）' },
    { 'g d / g r',       'Glance: 定義元 / 参照元' },
    { 'g y / g i',       'Glance: 型定義 / 実装' },
    { 'K',               'LSP: ホバードキュメント' },
    { 'Space r n',       'LSP: リネーム' },
    { 'Space c a',       'LSP: コードアクション' },
    { 'Space f',         'LSP: フォーマット' },
    { '[d / ]d',         'LSP: 前 / 次の診断へ' },
    { 'Space E',         'LSP: 診断の詳細を表示' },
    { 'Space s s',       'Namu: シンボル検索を開く' },
    { 'Namu Ctrl-j/k',   'Namu(ポップアップ内): 次 / 前の候補へ（↓/↑も可）' },
    { 'Namu Enter/Esc',  'Namu(ポップアップ内): 選択位置へジャンプ / 閉じる（Ctrl-cでも閉じる）' },
    { 'Space /',         'rg+fzf: 検索。開いた後 Ctrl-f:ファイル名 / Ctrl-r:置換 / Ctrl-g:内容 に切替' },
    { 'Space *',         'rg+fzf: カーソル単語で検索（Ctrl-f/Ctrl-r/Ctrl-g で切替）' },
    { 'Space m d',       'Markview: Markdownプレビューをトグル' },
    { 'Space m c',       'Markdownプレビューを既定ブラウザで開く' },
    { 'Space G',         'GitHubパーマリンクをコピー' },
    { 'Space P',         'パス付きコードをコピー' },
    { 'Space A',         'ファイル全体をコピー' },
    { 'Space ?',         'このショートカット一覧を開閉' },
  }},
  { header = '🗂️  explorer（Space e で開閉）', color = 'ShortcutsBuffer', rows = {
    { 'j / k',           'カーソルを下 / 上へ' },
    { 'l / →',           'ディレクトリへ入る（ファイルには無反応）' },
    { 'h / ←',           '親ディレクトリへ（元の位置にカーソル復帰）' },
    { 'Enter',           'ディレクトリへ入る / ファイルを開く' },
    { '.',               '隠しファイルの表示トグル' },
    { 'R',               '一覧を再読み込み' },
    { 'Tab / S-Tab',     '選択トグル（複数選択可）＋1つ下/上へ' },
    { 'Ctrl-a / Ctrl-r', 'すべて選択 / 選択を反転' },
    { 'Esc',             '選択解除→フィルタ解除→（どちらも無ければ）閉じる' },
    { 'a',               'ファイル/ディレクトリを作成（末尾/でディレクトリ）' },
    { 'r',               '名前を変更' },
    { 'd / D',           'ゴミ箱へ移動 / 完全削除（複数選択可）' },
    { 'Ctrl-y / Ctrl-x', 'コピー / カットをクリップボードにセット' },
    { 'Ctrl-p / Ctrl-S-p', '貼り付け（衝突時リネーム） / 上書き貼り付け' },
    { 'y / Y',           'ファイル名 / 絶対パスをコピー' },
    { '/',               '現在フォルダ内をファイル名でフィルタ（Escでクリア）' },
    { 's',               'fd+fzfで再帰検索して移動/開く' },
    { 'v',               'プレビューの表示トグル（エディタ上に浮かべる。Enterで開くと閉じる。全画面は常時右に表示）' },
    { '< / >',           'サイドバーを左 / 右へ移動（位置は以降も維持）' },
    { 'q',               'explorerを閉じる' },
  }},
  { header = '🌱 gitパネル（Space g で開閉、1-6/←→/タブクリックでパネル切替）', color = 'ShortcutsBuffer', rows = {
    { '1-6',             'Files / Commits / Branches / Stash / Worktree / PR へ切替' },
    { '← / →',           '前後のパネルへ切替（タブバーはクリックでも切替可）' },
    { 'P / p',           'push / pull（どのパネルでも共通）' },
    { 'R',               '現在のパネルを再取得' },
    { 'z',               '直前のコミットを取り消す（soft reset、確認あり）' },
    { 'v',               'delta side-by-side表示をトグル（deltaがある場合）' },
    { '@',               'コマンドログを画面いっぱいに拡大 / 再度で元に戻す' },
    { '+',               'Diffを拡大して全体diffストリームを表示 / 再度で元に戻す（@と排他、ファイルツリーは既定OFF）' },
    { '拡大中 t',        '左の変更ファイルツリーを表示 / 非表示' },
    { 'ツリー表示中 j / k','左の変更ファイルツリーで選択を下 / 上へ移動し、右の該当ファイルdiffへスクロール' },
    { 'q / Esc',         '閉じる（Filesで選択中ならEscは選択解除優先）' },
    { '[Files] Tab/S-Tab','選択トグル（複数選択可）＋1つ下/上へ' },
    { '[Files] C-a/C-r', '全選択 / 選択反転' },
    { '[Files] Space',   'ステージ / アンステージ（ディレクトリは配下全て、複数選択可）' },
    { '[Files] Enter',   'ディレクトリの折り畳み / ファイルはhunkステージへ' },
    { '[Files] a',       '全ステージ / 全アンステージ切替' },
    { '[Files] c / w',   'コミット / フックなしコミット' },
    { '[Files] A',       '直前コミットをamend（ステージ済み変更で）' },
    { '[Files] d',       '破棄メニュー（x: すべての変更を破棄 / u: 未ステージのみ破棄、複数選択可）' },
    { '[Files] s',       '全変更をスタッシュ' },
    { '[Files] S',       'スタッシュオプション（a:全て / u:未追跡含む / t:ステージ済み / k:keep-index）' },
    { '[Files] f',       'fetch（成功時はBranchesのPR状態も再取得）' },
    { '[Files] i / y',   'ignoreに追加 / パスをコピー' },
    { '[Files] e / o',   'ファイルを開いて編集（gitパネルを閉じる）' },
    { '[hunk] h/l, Tab', '前後のhunkへ, ステージ済み/未ステージを切替' },
    { '[hunk] Space/d',  'hunkをステージ/アンステージ / 破棄' },
    { '[hunk] Esc/q',    'hunk表示を抜けてファイル一覧へ戻る' },
    { '[Branches] Space','チェックアウト' },
    { '[Branches] n/d',  '新規作成 / 削除' },
    { '[Branches] D',    'PRがMergedのブランチを一括削除（force delete、確認あり）' },
    { '[Branches] M/r',  'マージ / リベース' },
    { '[Branches] R/f',  'リネーム / fast-forward' },
    { '[Branches] c/F/-','名前指定 / 強制チェックアウト / 直前のブランチへ' },
    { '[Branches] u',    '上流ブランチ(upstream)を設定' },
    { '[Branches] y',    'ブランチ名をコピー' },
    { '[Commits] g',     'resetメニュー（soft/mixed/hard）' },
    { '[Commits] t',     'revert' },
    { '[Commits] n',     'このコミットから新規ブランチ' },
    { '[Commits] y',     'SHAをコピー' },
    { '[Commits] c',     'cherry-pick' },
    { '[Commits] Space', 'detached HEADでチェックアウト' },
    { '[Stash] Space/g', 'apply / pop' },
    { '[Stash] d/n',     '削除 / このスタッシュから新規ブランチ' },
    { '[Worktree] Space','移動（cd）' },
    { '[Worktree] n/d',  '新規作成 / 削除' },
    { '[PR] o / Enter',  'PRをブラウザで開く（開けなければURLをコピー）' },
    { '[PR] y',          'PRのURLをコピー' },
    { '[PR] d',          '詳細 ⇄ diff を切替（diff中はvでside-by-side）' },
    { '[PR] c',          'PRのブランチをcheckout' },
    { '[PR] f',          'フィルタ（既定=作成/レビュー依頼 / 全て / 作者 / 検索）' },
  }},
}

DATA[2] = {
  { header = '🧭 移動・ナビゲーション', color = 'ShortcutsYazi', rows = {
    { 'h / ←',           '親ディレクトリへ' },
    { 'l / → / Enter',   'ディレクトリへ入る / ファイルを開く' },
    { 'j / k',           'カーソルを下 / 上へ' },
    { 'H / M / L',       'リストの先頭 / 中央 / 末尾へ' },
    { 'gg / G',          '一番上 / 下へ' },
    { 'Ctrl-u / Ctrl-d', '半ページ上 / 下へ' },
    { 'Ctrl-b / Ctrl-f', '1ページ上 / 下へ' },
  }},
  { header = '📁 ファイル操作', color = 'ShortcutsYazi', rows = {
    { 'o / O',           'ファイルを開く / アプリ選択で開く' },
    { 'a',               'ファイル/ディレクトリを作成' },
    { 'r',               '名前を変更' },
    { 'd / D',           'ゴミ箱へ移動 / 完全削除' },
    { 'c / x / p / P',   'コピー / カット / ペースト / 上書き' },
    { '.',               '隠しファイルの表示トグル' },
  }},
  { header = '✅ 選択', color = 'ShortcutsYazi', rows = {
    { 'Space',           '選択/解除のトグル' },
    { 'v',               'ビジュアル選択モード' },
    { 'Ctrl-a / Ctrl-r', 'すべて選択 / 選択を反転' },
    { 'Esc',             '選択をキャンセル' },
  }},
  { header = '🔍 検索・フィルター', color = 'ShortcutsYazi', rows = {
    { '/',               'ファイル名を検索' },
    { 'n / N',           '次 / 前のマッチへ' },
    { 'f / F',           'フィルター / クリア' },
    { 's / S',           'fd/findで検索 / ripgrepで内容検索' },
  }},
  { header = '📋 パスのコピー', color = 'ShortcutsYazi', rows = {
    { 'y n',             'ファイル名をコピー' },
    { 'y p',             '絶対パスをコピー' },
    { 'y d',             'ディレクトリパスをコピー' },
  }},
  { header = '📑 タブ操作', color = 'ShortcutsYazi', rows = {
    { 't',               '新規タブを作成' },
    { '1 〜 9',          'N番目のタブへ切り替え' },
    { '[ / ]',           '前 / 次のタブへ' },
  }},
}

DATA[3] = {
  { header = '🌍 グローバル', color = 'ShortcutsGit', rows = {
    { '?',               'キーバインド一覧を表示' },
    { 'q',               '終了' },
    { ':',               'カスタムコマンドを実行' },
    { '+ / _',           'パネルを拡大 / 縮小' },
    { 'x',               'コンテキストメニューを開く' },
    { 'Ctrl-r',          '最近のリポジトリへ切り替え' },
  }},
  { header = '🧭 パネル・ナビゲーション', color = 'ShortcutsGit', rows = {
    { 'h / l',           '左 / 右のパネルへ' },
    { 'j / k',           'リストを下 / 上へ' },
    { '[ / ]',           '前 / 次のタブへ' },
    { 'H / L',           '差分ビューを左 / 右にスクロール' },
    { 'Ctrl-u / Ctrl-d', '差分を半ページ上 / 下へ' },
    { '} / {',           '差分のhunkを次 / 前へ' },
  }},
  { header = '📄 ファイルパネル', color = 'ShortcutsGit', rows = {
    { 'Space',           'ステージ/アンステージのトグル' },
    { 'a',               'すべてステージ/アンステージ' },
    { 'Enter',           '行/hunk単位でステージ' },
    { 'c / w',           'コミット / フックなしでコミット' },
    { 'A',               '直前のコミットにamend' },
    { 'd / e / o',       '変更破棄 / 編集 / 開く' },
    { 'i / S',           '.gitignoreに追加 / スタッシュ' },
  }},
  { header = '🌿 ブランチパネル', color = 'ShortcutsGit', rows = {
    { 'Space',           'ブランチをチェックアウト' },
    { 'n / d',           '新規作成 / 削除' },
    { 'r / M / f',       'リベース / マージ / fast-forward' },
    { 'u',               '上流ブランチを設定' },
    { 'g',               'リセットオプションを表示' },
  }},
  { header = '📝 コミットパネル', color = 'ShortcutsGit', rows = {
    { 'r / R',           'メッセージ編集 / エディタで編集' },
    { 'd / e',           'ドロップ / 編集（rebase）' },
    { 'f / s',           'fixup / squash' },
    { 'Ctrl-j / Ctrl-k', 'コミットを下 / 上へ移動' },
    { 'T / c',           'タグ付け / SHAをコピー' },
    { 'g',               'リセットオプションを表示' },
  }},
  { header = '📦 スタッシュ / リモート', color = 'ShortcutsGit', rows = {
    { 'Space / g',       'スタッシュを適用 / pop' },
    { 'd / n',           'スタッシュ削除 / ブランチ作成' },
    { 'P / p / f',       'プッシュ / プル / フェッチ' },
  }},
}

DATA[4] = {
  { header = '⚙️  基本操作', color = 'ShortcutsHerdr', rows = {
    { 'ctrl+b + ?',       'ヘルプを表示' },
    { 'ctrl+b + q',       'デタッチ（セッションを保持して離脱）' },
    { 'ctrl+b + s',       '設定を開く' },
    { 'ctrl+b + b',       'サイドバーの表示/非表示' },
    { 'ctrl+b + e',       'スクロールバックを編集' },
  }},
  { header = '📑 タブ操作', color = 'ShortcutsHerdr', rows = {
    { 'ctrl+b + c',         '新規タブを作成' },
    { 'ctrl+b + n',         '次のタブへ' },
    { 'ctrl+b + p',         '前のタブへ' },
    { 'ctrl+b + 1..9',      'タブを切り替え' },
    { 'ctrl+shift + →/←',  '次 / 前のタブへ' },
    { 'ctrl+shift + 1..9',  'タブを番号で切り替え' },
  }},
  { header = '🪟 ペイン操作', color = 'ShortcutsHerdr', rows = {
    { 'ctrl+b + v',         '垂直分割' },
    { 'ctrl+b + -',         '水平分割' },
    { 'ctrl+b + h/j/k/l',   'ペインを左/下/上/右へフォーカス' },
    { 'ctrl+alt + ↑/↓/←/→', 'ペインを上/下/左/右へフォーカス' },
    { 'ctrl+b + Tab',       '次のペインへ' },
    { 'ctrl+b + x',         'ペインを閉じる' },
    { 'ctrl+b + z',         'ズーム（全画面トグル）' },
    { 'ctrl+b + r',         'リサイズモード' },
  }},
  { header = '🗂️  ワークスペース', color = 'ShortcutsHerdr', rows = {
    { 'ctrl+b + w',         'ワークスペース選択' },
    { 'ctrl+b + t',         'ペインへ移動（goto）' },
    { 'ctrl+shift + ↑/↓',   '前 / 次のワークスペースへ' },
  }},
  { header = '🔧 カスタムコマンド', color = 'ShortcutsHerdr', rows = {
    { 'ctrl+b+Enter / ctrl+alt+t', 'ターミナルを開く' },
  }},
}

-- ══════════════════════════════════════════════
-- レンダリング
-- ══════════════════════════════════════════════

local function render()
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local sections = DATA[cur_tab]
  local q = query:lower()
  local lines    = {}
  local hl_queue = {}

  local function hl(lnum, group, cs, ce)
    table.insert(hl_queue, { lnum, group, cs or 0, ce or -1 })
  end

  -- タブバー
  local tab_line = ' '
  local tab_cols = {}
  for i, name in ipairs(TABS) do
    local label = ' ' .. name .. ' '
    local s = #tab_line
    tab_line = tab_line .. label
    table.insert(tab_cols, { i, s, s + #label })
    if i < #TABS then tab_line = tab_line .. ' ' end
  end
  table.insert(lines, tab_line)
  for _, tc in ipairs(tab_cols) do
    hl(0, tc[1] == cur_tab and 'ShortcutsTabActive' or 'ShortcutsTabInactive', tc[2], tc[3])
  end

  -- 検索バー
  local shint = query == '' and '絞り込む…' or query
  table.insert(lines, ' 🔍 ' .. shint)
  hl(1, query == '' and 'ShortcutsSearchHint' or 'ShortcutsSearchQuery')

  table.insert(lines, '')

  for _, section in ipairs(sections) do
    local visible = {}
    for _, row in ipairs(section.rows) do
      if q == '' or row[1]:lower():find(q, 1, true) or row[2]:lower():find(q, 1, true) then
        table.insert(visible, row)
      end
    end
    if #visible == 0 then goto continue end

    local lnum = #lines
    table.insert(lines, ' ' .. section.header)
    hl(lnum, section.color)

    for _, row in ipairs(visible) do
      local key     = row[1]
      local desc    = row[2]
      local pad     = math.max(1, 24 - vim.fn.strdisplaywidth(key))
      local line    = ' ' .. key .. string.rep(' ', pad) .. desc
      lnum = #lines
      table.insert(lines, line)
      hl(lnum, 'ShortcutsKey',  1, 1 + #key)
      hl(lnum, 'ShortcutsDesc', 1 + #key + pad, -1)
    end

    table.insert(lines, '')
    ::continue::
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, h in ipairs(hl_queue) do
    vim.api.nvim_buf_add_highlight(buf, hl_ns, h[2], h[1], h[3], h[4])
  end
end

-- ══════════════════════════════════════════════
-- 開閉
-- ══════════════════════════════════════════════

local PANEL_WIDTH = 56

local function close()
  vim.api.nvim_clear_autocmds({ group = augrp })
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  win, buf = nil, nil
  query = ''
end

local function open()
  if win and vim.api.nvim_win_is_valid(win) then
    close()
    return
  end

  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype    = 'nofile'
  vim.bo[buf].buflisted  = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype   = 'shortcuts'

  -- 右端に垂直スプリット
  vim.cmd('botright ' .. PANEL_WIDTH .. 'vsplit')
  win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  require('config.hidden_cursor').mark_buffer(buf)
  require('config.util.win_util').mark_sidebar(win, buf)

  vim.wo[win].wrap           = false
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn     = 'no'
  vim.wo[win].cursorline     = false
  vim.wo[win].winfixwidth    = true
  vim.wo[win].winhighlight   = 'Normal:ShortcutsBg'
  vim.wo[win].statusline     = '%#ShortcutsBg#' -- ステータスラインを隠す（パネル背景に溶け込ませる）

  render()

  local function map(key, fn)
    vim.keymap.set('n', key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map('<Tab>',   function() cur_tab = cur_tab % #TABS + 1;       render() end)
  map('<S-Tab>', function() cur_tab = (cur_tab - 2) % #TABS + 1; render() end)
  map('1',       function() cur_tab = 1; render() end)
  map('2',       function() cur_tab = 2; render() end)
  map('3',       function() cur_tab = 3; render() end)
  map('4',       function() cur_tab = 4; render() end)
  map('/',       function()
    vim.ui.input({ prompt = '絞り込む: ', default = query }, function(input)
      if input ~= nil then query = input; render() end
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
      end
    end)
  end)
  map('<BS>',    function() query = ''; render() end)
  map('q',       close)
  map('<Esc>',   close)

  -- パネルを閉じられたら状態をリセット
  vim.api.nvim_create_autocmd('WinClosed', {
    group    = augrp,
    pattern  = tostring(win),
    once     = true,
    callback = function()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
      win, buf = nil, nil
      query = ''
      vim.api.nvim_clear_autocmds({ group = augrp })
    end,
  })

  -- フォーカスを元のウィンドウに戻す
  vim.cmd('wincmd p')
end

-- ══════════════════════════════════════════════
-- ハイライト
-- ══════════════════════════════════════════════

local function setup_hl()
  vim.api.nvim_set_hl(0, 'ShortcutsBg',          { bg = '#1a1b26' })
  vim.api.nvim_set_hl(0, 'ShortcutsTabActive',    { bg = '#2d3250', fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsTabInactive',  { fg = '#565f89' })
  vim.api.nvim_set_hl(0, 'ShortcutsKey',          { fg = '#e0af68', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsDesc',         { fg = '#9aa5ce' })
  vim.api.nvim_set_hl(0, 'ShortcutsSearchHint',   { fg = '#565f89', italic = true })
  vim.api.nvim_set_hl(0, 'ShortcutsSearchQuery',  { fg = '#2ac3de' })
  vim.api.nvim_set_hl(0, 'ShortcutsNormal',       { bg = '#2d3250', fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsInsert',       { bg = '#2d3b2d', fg = '#9ece6a', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsVisual',       { bg = '#3b2d3b', fg = '#bb9af7', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsCommand',      { bg = '#3b302d', fg = '#ff9e64', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsSearch',       { bg = '#2d3a3b', fg = '#2ac3de', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsWindow',       { bg = '#3b3a2d', fg = '#e0af68', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsBuffer',       { bg = '#2d3b3b', fg = '#73daca', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsText',         { bg = '#3b2d36', fg = '#f7768e', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsMacro',        { bg = '#2d2d3b', fg = '#9d7cd8', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsMisc',         { bg = '#2d2d2d', fg = '#a9b1d6', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsYazi',         { bg = '#2d3b30', fg = '#73daca', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsGit',          { bg = '#3b2d28', fg = '#ff9e64', bold = true })
  vim.api.nvim_set_hl(0, 'ShortcutsHerdr',        { bg = '#2d2d3b', fg = '#cba6f7', bold = true })
end

setup_hl()
vim.api.nvim_create_autocmd('ColorScheme', { callback = setup_hl })

vim.keymap.set('n', '<leader>?', open, { desc = 'キーボードショートカット一覧' })

return M
