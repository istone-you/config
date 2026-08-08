-- 起動中のレビューセッションを外部(AI skill / CLI)から見つけるためのディスカバリ。
--
-- 実体は config.util.session_registry(nvim_api と共有)。namespace 'diff-review' を割り当てる
-- ので、ファイル位置は従来どおり stdpath('cache')/diff-review/sessions.json のまま。
-- skill 側の解決規則(${XDG_CACHE_HOME:-$HOME/.cache}/nvim/diff-review/sessions.json)も変わらない。

return require('config.util.session_registry').new('diff-review')
