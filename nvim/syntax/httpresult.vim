" HTTP レスポンスパネル（lua/config/http_client/ui.lua）のシンタックス

if exists('b:current_syntax')
  finish
endif

syn case match

syn match httpResultHeaderName /^[A-Za-z][A-Za-z0-9-]*\ze\s*:/
" ステータス行はヘッダ名より優先させたいので後に定義する
syn match httpResultStatus /^HTTP\/[0-9.]\+\s\+\d\+.*$/
syn match httpResultSummary /^###.*$/ contains=httpResultOk,httpResultWarn,httpResultErr
syn match httpResultOk   /\<[23]\d\d\>/ contained
syn match httpResultWarn /\<3\d\d\>/ contained
syn match httpResultErr  /\(\<[45]\d\d\>\|失敗\)/ contained

syn region httpResultString start=/"/ skip=/\\./ end=/"/ oneline
syn match httpResultNumber /\<-\?\d\+\(\.\d\+\)\?\>/
syn keyword httpResultBoolean true false null

hi def link httpResultHeaderName Identifier
hi def link httpResultStatus     Constant
hi def link httpResultSummary    Title
hi def link httpResultOk         DiagnosticOk
hi def link httpResultWarn       DiagnosticWarn
hi def link httpResultErr        DiagnosticError
hi def link httpResultString     String
hi def link httpResultNumber     Number
hi def link httpResultBoolean    Boolean

let b:current_syntax = 'httpresult'
