" .http / .rest ファイルのシンタックス（自作・プラグイン不使用）
" 実行などの機能は lua/config/http_client/ 側

if exists('b:current_syntax')
  finish
endif

syn case match

" ### 区切りと衝突しないよう、# / ## で始まる行だけをコメント扱いにする
syn match httpComment /^\s*\(#\{1,2}\([^#]\|$\)\|\/\/\).*$/ contains=httpDirective
syn match httpDirective /@\(name\|follow\|insecure\|timeout\)\>/ contained

syn match httpSeparator /^\s*###.*$/

syn match httpVarDef /^@[A-Za-z0-9_.-]\+\ze\s*=/
syn match httpVarRef /{{[^{}]*}}/ containedin=ALL

syn match httpMethod /^\s*\(GET\|POST\|PUT\|PATCH\|DELETE\|HEAD\|OPTIONS\|TRACE\|CONNECT\)\>/
      \ nextgroup=httpUrl skipwhite
syn match httpUrl /\S.*$/ contained contains=httpVarRef,httpVersion
syn match httpVersion /\<HTTP\/[0-9.]\+\>/ contained

syn match httpHeaderName /^[A-Za-z][A-Za-z0-9-]*\ze\s*:/

" ボディ（主に JSON）を読みやすくするための最低限のハイライト
syn region httpString start=/"/ skip=/\\./ end=/"/ oneline contains=httpVarRef
syn match httpNumber /\<-\?\d\+\(\.\d\+\)\?\>/
syn keyword httpBoolean true false null

hi def link httpComment     Comment
hi def link httpDirective   SpecialComment
hi def link httpSeparator   Title
hi def link httpVarDef      Identifier
hi def link httpVarRef      Special
hi def link httpMethod      Statement
hi def link httpUrl         Underlined
hi def link httpVersion     Constant
hi def link httpHeaderName  Identifier
hi def link httpString      String
hi def link httpNumber      Number
hi def link httpBoolean     Boolean

let b:current_syntax = 'http'
