-- 差分レビューのブラウザ画面(difit を参考にした単一ページアプリ)。
--
-- ページ自体は静的で、/api/diff・/api/comments・/api/session を fetch して描画する。
-- 行をクリックするとその行にコメントを追加でき、スレッド(返信)も表示する。
-- unified / side-by-side(split) の表示切替を持ち、選択は localStorage に保存する(difit 相当)。
-- /__version を 1 秒間隔でポーリングし、AI が API 経由で足したコメントも自動で反映する。
-- 配色は browser/markdown.lua のプレビューと同系統の暗色テーマに揃えている。

local M = {}

local function html_escape(s)
  return (tostring(s or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- HTML/CSS/JS 本体。データは実行時に fetch するのでテンプレートは静的。
local PAGE = [==[<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
*{box-sizing:border-box;}
body{margin:0;background:#0d1117;color:#e6edf3;font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;}
header{position:sticky;top:0;z-index:5;background:#161b22;border-bottom:1px solid #30363d;padding:10px 20px;display:flex;align-items:center;gap:14px;flex-wrap:wrap;}
header h1{font-size:15px;margin:0;font-weight:600;}
header .meta{color:#8b949e;font-size:12px;}
header .spacer{flex:1;}
header .pill{background:#21262d;border:1px solid #30363d;border-radius:999px;padding:2px 10px;font-size:12px;color:#8b949e;}
header button.pill{cursor:pointer;color:#c9d1d9;}
header button.pill:hover{background:#30363d;border-color:#8b949e;}
.seg{display:inline-flex;border:1px solid #30363d;border-radius:999px;overflow:hidden;}
.seg button{background:#21262d;color:#8b949e;border:0;padding:3px 12px;font-size:12px;cursor:pointer;}
.seg button:hover{background:#30363d;}
.seg button.active{background:#388bfd33;color:#79c0ff;}
.seg button+button{border-left:1px solid #30363d;}
#layout{display:flex;align-items:flex-start;max-width:1500px;margin:0 auto;}
main{flex:1;min-width:0;padding:20px;}
/* 変更ファイルのツリー(サイドバー)。ヘッダー高さぶん下げてスティッキー表示。 */
nav.tree{position:sticky;top:44px;align-self:flex-start;flex:0 0 270px;width:270px;max-height:calc(100vh - 44px);overflow:auto;padding:14px 6px 40px;border-right:1px solid #30363d;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px;}
nav.tree .tree-title{color:#8b949e;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.04em;padding:0 6px 8px;}
/* ツリーを折りたたむと main(flex:1) が空いた幅いっぱいに広がる */
#layout.tree-collapsed nav.tree{display:none;}
.tnode{display:flex;align-items:center;gap:6px;padding:3px 6px;border-radius:6px;cursor:pointer;white-space:nowrap;}
.tnode:hover{background:#161b22;}
.tdir .tw{color:#8b949e;width:12px;flex:none;}
.tdir .tname{color:#c9d1d9;font-weight:600;overflow:hidden;text-overflow:ellipsis;}
.tfile .tname{color:#adbac7;overflow:hidden;text-overflow:ellipsis;}
.tbadge{font-size:10px;width:14px;flex:none;text-align:center;color:#8b949e;}
.tbadge.A{color:#3fb950;} .tbadge.D{color:#f85149;} .tbadge.R{color:#d29922;} .tbadge.M{color:#58a6ff;}
.tcount{margin-left:auto;background:#388bfd33;color:#79c0ff;border-radius:999px;padding:0 6px;font-size:11px;flex:none;}
@media(max-width:820px){nav.tree{display:none;}}
.empty{color:#8b949e;text-align:center;padding:60px 0;}
.file{border:1px solid #30363d;border-radius:8px;margin:0 0 20px;overflow:hidden;background:#0d1117;}
.file-head{background:#161b22;border-bottom:1px solid #30363d;padding:8px 12px;display:flex;align-items:center;gap:10px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;}
.file-head .path{font-weight:600;}
.file-head .stat-add{color:#3fb950;} .file-head .stat-del{color:#f85149;}
.badge{font-size:11px;padding:1px 6px;border-radius:4px;border:1px solid #30363d;color:#8b949e;}
.badge.A{color:#3fb950;border-color:#238636;} .badge.D{color:#f85149;border-color:#da3633;}
.badge.R{color:#d29922;border-color:#9e6a03;}
table.diff{width:100%;border-collapse:collapse;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12.5px;}
/* split は colgroup で列幅を固定する。hunk ヘッダー行が colspan=4 の 1 セルなので、
   table-layout:fixed の「先頭行から列幅を決める」だけだと均等割りされてしまう。colgroup なら効く。 */
table.diff.split{table-layout:fixed;}
table.diff.split col.c-ln{width:50px;}
table.diff.split col.c-code{width:calc(50% - 50px);}
table.diff td{padding:0 8px;vertical-align:top;white-space:pre-wrap;word-break:break-word;overflow-wrap:anywhere;}
td.ln{width:50px;text-align:right;color:#6e7681;user-select:none;background:#0d1117;border-right:1px solid #21262d;}
td.content.left{border-right:1px solid #30363d;}
/* 追加・削除の色付けは unified では行(tr)に、split ではセル(td)に付く */
tr.add td.content,td.content.add{background:rgba(63,185,80,.15);}
tr.del td.content,td.content.del{background:rgba(248,81,73,.15);}
tr.add td.ln,td.ln.add{background:rgba(63,185,80,.10);}
tr.del td.ln,td.ln.del{background:rgba(248,81,73,.10);}
td.content.filler{background:#0b0f14;}
tr.hunk td{background:#161b22;color:#8b949e;padding:2px 8px;}
td.content{cursor:default;}
td.content .sign{display:inline-block;width:1ch;color:#6e7681;}
tr.add td.content .sign,td.content.add .sign{color:#3fb950;}
tr.del td.content .sign,td.content.del .sign{color:#f85149;}
.threadrow td{background:#0d1117;padding:0;}
.thread{margin:6px 10px;border-left:2px solid #388bfd;background:#11161d;border-radius:0 6px 6px 0;}
.comment{padding:9px 13px;border-bottom:1px solid #21262d;}
.comment:last-child{border-bottom:0;}
.comment .who{font-size:13px;font-weight:600;margin-bottom:3px;display:flex;gap:8px;align-items:center;}
.comment .who .author-ai{color:#d2a8ff;} .comment .who .author-human{color:#79c0ff;}
.comment .who .time{color:#6e7681;font-weight:400;}
.comment .who .del{margin-left:auto;color:#6e7681;cursor:pointer;font-weight:400;border:0;background:none;font-size:13px;}
.comment .who .del:hover{color:#f85149;}
.comment .body{white-space:pre-wrap;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:15px;line-height:1.65;}
.cform{padding:9px 13px;background:#0d1117;}
.cform textarea{width:100%;min-height:60px;background:#0d1117;color:#e6edf3;border:1px solid #30363d;border-radius:6px;padding:9px;font:14.5px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;resize:vertical;}
.cform .actions{margin-top:6px;display:flex;gap:8px;}
button.btn{background:#238636;color:#fff;border:0;border-radius:6px;padding:5px 14px;font-size:13px;cursor:pointer;}
button.btn:hover{background:#2ea043;}
button.btn.ghost{background:#21262d;color:#c9d1d9;border:1px solid #30363d;}
button.btn.ghost:hover{background:#30363d;}
.orphans{padding:10px 12px;border-top:1px solid #30363d;background:#11161d;}
.orphans .h{color:#8b949e;font-size:12px;margin-bottom:6px;}
</style>
</head>
<body>
<header>
  <button class="pill" id="treebtn" title="ファイルツリーの表示を切り替え">☰</button>
  <h1>Diff Review</h1>
  <span class="meta" id="repo"></span>
  <span class="spacer"></span>
  <span class="seg" id="viewseg" title="差分ソースを切り替え。コメントは All のみ、Unstaged/Staged は閲覧専用">
    <button data-view="all">All</button>
    <button data-view="unstaged">Unstaged</button>
    <button data-view="staged">Staged</button>
  </span>
  <button class="pill" id="modebtn" title="表示を切り替え (unified / side-by-side)"></button>
  <span class="pill" id="counts"></span>
  <span class="pill" id="status">接続中…</span>
</header>
<div id="layout">
<nav id="tree" class="tree"></nav>
<main id="app"><div class="empty">読み込み中…</div></main>
</div>
<script>
const state = {
  session:null, diff:{files:[]}, comments:[], version:null,
  openForm:null, draft:'',
  mode: (localStorage.getItem('diffReviewMode')==='split') ? 'split' : 'unified',
  view: (['unstaged','staged'].indexOf(localStorage.getItem('diffReviewView'))>=0) ? localStorage.getItem('diffReviewView') : 'all',
  collapsedDirs: new Set(),
  treeCollapsed: localStorage.getItem('diffReviewTreeCollapsed')==='1',
};
function applyTreeCollapsed(){ document.getElementById('layout').classList.toggle('tree-collapsed', state.treeCollapsed); }
// コメントを付けられるのは All ビューのみ。Unstaged/Staged は閲覧専用。
function commentable(){ return state.view==='all'; }

function el(tag, cls, text){ const e=document.createElement(tag); if(cls) e.className=cls; if(text!=null) e.textContent=text; return e; }
async function getJSON(p){ const r=await fetch(p); return r.json(); }
async function postJSON(p, body){
  const r = await fetch(p, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(body)});
  return {ok:r.ok, data: await r.json().catch(()=>({}))};
}

function keyOf(file, side, line){ return file+' '+side+' '+line; }
function targetOf(line){
  if(line.type==='add') return {side:'new', line:line.new_line};
  if(line.type==='del') return {side:'old', line:line.old_line};
  return {side:'new', line:line.new_line};
}
function topFor(file, side, line){
  return state.comments.filter(c=>c.parent_id==null && c.file===file && c.side===side && Number(c.line)===Number(line));
}
function repliesFor(id){ return state.comments.filter(c=>c.parent_id===id); }
function fmtTime(t){ if(!t) return ''; try{ return new Date(t*1000).toLocaleString(); }catch(e){ return ''; } }

async function loadAll(){
  try{
    const [session, diff, comments] = await Promise.all([
      getJSON('/api/session'), getJSON('/api/diff?view='+encodeURIComponent(state.view)), getJSON('/api/comments')
    ]);
    state.session=session; state.diff=diff||{files:[]}; state.comments=(comments&&comments.comments)||[];
    state.version = String(session.version);
    document.getElementById('status').textContent='接続中';
    render();
  }catch(e){
    document.getElementById('status').textContent='切断';
  }
}

function render(){
  const app = document.getElementById('app');
  app.innerHTML='';
  const files = (state.diff && state.diff.files) || [];
  document.getElementById('repo').textContent = state.session ? (state.session.repoRoot||'') + ' · ' + (state.session.source||'') : '';
  document.getElementById('modebtn').textContent = state.mode==='split' ? '⇆ Side-by-side' : '≡ Unified';
  document.querySelectorAll('#viewseg button').forEach(b=>b.classList.toggle('active', b.dataset.view===state.view));
  let add=0, del=0; files.forEach(f=>{add+=f.added||0; del+=f.deleted||0;});
  document.getElementById('counts').textContent = files.length+' files  +'+add+' -'+del;

  if(!files.length){ app.appendChild(el('div','empty','変更はありません')); renderTree([]); return; }
  files.forEach((f,idx)=>app.appendChild(renderFile(f, idx)));
  renderTree(files);
  if(state.openForm) restoreForm();
}

// ── 変更ファイルのツリー(サイドバー) ─────────────────────────
function fileCommentCount(path){
  return state.comments.filter(c=>c.parent_id==null && c.file===path).length;
}
function buildTree(files){
  const root = {dirs:{}, files:[]};
  files.forEach((f,idx)=>{
    const parts = f.path.split('/');
    let node = root;
    for(let i=0;i<parts.length-1;i++){ const d=parts[i]; node.dirs[d]=node.dirs[d]||{dirs:{},files:[]}; node=node.dirs[d]; }
    node.files.push({file:f, idx, name:parts[parts.length-1]});
  });
  return root;
}
function renderTreeNode(node, prefix, depth, out){
  Object.keys(node.dirs).sort().forEach(name=>{
    const path = prefix ? prefix+'/'+name : name;
    const collapsed = state.collapsedDirs.has(path);
    const row = el('div','tnode tdir'); row.style.paddingLeft = (6+depth*12)+'px';
    row.appendChild(el('span','tw', collapsed?'▸':'▾'));
    row.appendChild(el('span','tname', name));
    row.onclick = ()=>{ if(collapsed) state.collapsedDirs.delete(path); else state.collapsedDirs.add(path); renderTree((state.diff&&state.diff.files)||[]); };
    out.appendChild(row);
    if(!collapsed) renderTreeNode(node.dirs[name], path, depth+1, out);
  });
  node.files.sort((a,b)=>a.name.localeCompare(b.name)).forEach(item=>{
    const f = item.file;
    const row = el('div','tnode tfile'); row.style.paddingLeft = (6+depth*12+14)+'px';
    row.appendChild(el('span','tbadge '+(f.status||'M'), f.status||'M'));
    row.appendChild(el('span','tname', item.name));
    const cc = fileCommentCount(f.path);
    if(cc) row.appendChild(el('span','tcount', String(cc)));
    row.title = f.path + '  +' + (f.added||0) + ' -' + (f.deleted||0);
    row.onclick = ()=>{ const b=document.getElementById('file-'+item.idx); if(b) b.scrollIntoView({behavior:'smooth', block:'start'}); };
    out.appendChild(row);
  });
}
function renderTree(files){
  const tree = document.getElementById('tree');
  tree.innerHTML='';
  if(!files.length) return;
  tree.appendChild(el('div','tree-title', 'Changed files ('+files.length+')'));
  renderTreeNode(buildTree(files), '', 0, tree);
}

function fileHead(f){
  const head = el('div','file-head');
  head.appendChild(el('span','badge '+(f.status||'M'), f.status||'M'));
  head.appendChild(el('span','path', f.path));
  const st = el('span');
  st.appendChild(el('span','stat-add',' +'+(f.added||0)));
  st.appendChild(el('span','stat-del',' -'+(f.deleted||0)));
  head.appendChild(st);
  return head;
}

// content セル。side/lineNo があればクリックでその行にコメントフォームを開く。
function contentCell(file, side, lineNo, type, content, extraClass){
  let cls = 'content';
  if(extraClass) cls += ' '+extraClass;
  if(type) cls += ' '+type;
  const td = el('td', cls);
  if(content==null && !type){ return td; } // filler(空セル)
  td.appendChild(el('span','sign', type==='add'?'+':(type==='del'?'-':' ')));
  if(content!=null) td.appendChild(document.createTextNode(content));
  if(side && lineNo!=null && commentable()){
    td.style.cursor='pointer';
    td.onclick=(ev)=>{ if(ev.target.closest('.thread,.cform')) return; openForm(file, side, lineNo); };
  }
  return td;
}

function hunkHeaderRow(h, colspan){
  const tr = el('tr','hunk'); const td=el('td'); td.colSpan=colspan; td.textContent=h.header; tr.appendChild(td); return tr;
}

// 行の下に、該当する (side,line) のスレッド/フォームを差し込む。seen に描画済みキーを記録。
// staged はインライン表示しない(行番号が index 基準でズレるため全部まとめ送り)。
// unstaged は new 側のみ一致させる(new 側は作業ツリー基準で All と一致するため)。
function afterRowThreads(table, f, targets, colspan, seen){
  if(state.view==='staged') return;
  targets.forEach(t=>{
    if(!t || t.line==null) return;
    if(state.view==='unstaged' && t.side!=='new') return;
    const tops = topFor(f.path, t.side, t.line);
    const k = keyOf(f.path, t.side, t.line);
    if(tops.length || (commentable() && state.openForm===k)){ seen[k]=true; table.appendChild(threadRow(f.path, t.side, t.line, tops, colspan)); }
  });
}

function renderFile(f, idx){
  const box = el('div','file');
  if(idx!=null) box.id = 'file-'+idx;
  box.appendChild(fileHead(f));
  if(f.binary){ const b=el('div','orphans'); b.appendChild(el('div','h','バイナリファイル(差分表示なし)')); box.appendChild(b); return box; }

  const table = el('table', state.mode==='split' ? 'diff split' : 'diff');
  if(state.mode==='split'){
    // colgroup で 4 列(行番号/コード/行番号/コード)の幅を固定する
    const cg = document.createElement('colgroup');
    ['c-ln','c-code','c-ln','c-code'].forEach(c=>{ const col=document.createElement('col'); col.className=c; cg.appendChild(col); });
    table.appendChild(cg);
  }
  const seen = {};
  (f.hunks||[]).forEach(h=>{
    if(state.mode==='split') renderHunkSplit(table, f, h, seen);
    else renderHunkUnified(table, f, h, seen);
  });
  box.appendChild(table);

  // インライン表示できなかったコメントはファイル末尾にまとめる。
  // All では「行がずれた等で一致しないもの」、Unstaged/Staged では「All で付いた閲覧専用コメント」。
  const orphans = state.comments.filter(c=>c.parent_id==null && c.file===f.path && !seen[keyOf(f.path,c.side,c.line)]);
  if(orphans.length){
    const heading = state.view==='all' ? '表示中の差分に一致しないコメント' : 'All のコメント（このビューでは閲覧のみ）';
    const ob = el('div','orphans'); ob.appendChild(el('div','h', heading));
    orphans.forEach(c=>ob.appendChild(renderThread(c)));
    box.appendChild(ob);
  }
  return box;
}

function renderHunkUnified(table, f, h, seen){
  table.appendChild(hunkHeaderRow(h, 3));
  (h.lines||[]).forEach(line=>{
    const tr = el('tr','line '+line.type);
    tr.appendChild(el('td','ln', line.old_line!=null?String(line.old_line):''));
    tr.appendChild(el('td','ln', line.new_line!=null?String(line.new_line):''));
    const tgt = targetOf(line);
    tr.appendChild(contentCell(f.path, tgt.side, tgt.line, line.type, line.content));
    table.appendChild(tr);
    afterRowThreads(table, f, [tgt], 3, seen);
  });
}

// side-by-side: 連続する del ブロックと add ブロックを行ごとにペアリングして左右に並べる。
function renderHunkSplit(table, f, h, seen){
  table.appendChild(hunkHeaderRow(h, 4));
  const lines = h.lines || [];
  let i = 0;
  while(i < lines.length){
    const line = lines[i];
    if(line.type==='context'){
      const tr = el('tr','line');
      tr.appendChild(el('td','ln', line.old_line!=null?String(line.old_line):''));
      tr.appendChild(contentCell(f.path,'old',line.old_line,'context',line.content,'left'));
      tr.appendChild(el('td','ln', line.new_line!=null?String(line.new_line):''));
      tr.appendChild(contentCell(f.path,'new',line.new_line,'context',line.content));
      table.appendChild(tr);
      afterRowThreads(table, f, [{side:'old',line:line.old_line},{side:'new',line:line.new_line}], 4, seen);
      i++;
    }else{
      const dels=[], adds=[];
      while(i<lines.length && lines[i].type==='del'){ dels.push(lines[i]); i++; }
      while(i<lines.length && lines[i].type==='add'){ adds.push(lines[i]); i++; }
      const n = Math.max(dels.length, adds.length);
      for(let k=0;k<n;k++){
        const d=dels[k], a=adds[k];
        const tr = el('tr','line');
        tr.appendChild(el('td', d?'ln del':'ln', d?String(d.old_line):''));
        tr.appendChild(d ? contentCell(f.path,'old',d.old_line,'del',d.content,'left')
                         : contentCell(f.path,null,null,null,null,'left filler'));
        tr.appendChild(el('td', a?'ln add':'ln', a?String(a.new_line):''));
        tr.appendChild(a ? contentCell(f.path,'new',a.new_line,'add',a.content)
                         : contentCell(f.path,null,null,null,null,'filler'));
        table.appendChild(tr);
        const targets=[];
        if(d) targets.push({side:'old',line:d.old_line});
        if(a) targets.push({side:'new',line:a.new_line});
        afterRowThreads(table, f, targets, 4, seen);
      }
    }
  }
}

function threadRow(file, side, line, tops, colspan){
  const tr = el('tr','threadrow'); const td=el('td'); td.colSpan=colspan||3;
  tops.forEach(c=>td.appendChild(renderThread(c)));
  if(commentable()){ const k = keyOf(file, side, line); if(state.openForm===k){ td.appendChild(commentForm({file, side, line})); } }
  tr.appendChild(td);
  return tr;
}

function renderThread(top){
  const wrap = el('div','thread');
  wrap.appendChild(renderComment(top));
  repliesFor(top.id).forEach(r=>wrap.appendChild(renderComment(r)));
  if(commentable()) wrap.appendChild(replyForm(top.id)); // 閲覧専用ビューでは返信欄を出さない
  return wrap;
}

function renderComment(c){
  const box = el('div','comment');
  const who = el('div','who');
  const isAI = c.author && c.author!=='human';
  who.appendChild(el('span', isAI?'author-ai':'author-human', c.author||'human'));
  who.appendChild(el('span','time', fmtTime(c.created_at)));
  if(commentable()){ // 閲覧専用ビューでは削除ボタンを出さない
    const del = el('button','del','✕'); del.title='削除';
    del.onclick = async ()=>{ await postJSON('/api/comments/delete', {id:c.id}); await loadAll(); };
    who.appendChild(del);
  }
  box.appendChild(who);
  box.appendChild(el('div','body', c.body));
  return box;
}

function commentForm(tgt){
  const form = el('div','cform');
  const ta = el('textarea'); ta.placeholder='コメントを書く…'; ta.id='cf-active'; ta.value=state.draft||'';
  ta.oninput = ()=>{ state.draft = ta.value; };
  const actions = el('div','actions');
  const submit = el('button','btn','コメント');
  submit.onclick = async ()=>{
    const body = ta.value.trim(); if(!body) return;
    state.draft=''; state.openForm=null;
    await postJSON('/api/comments', {file:tgt.file, side:tgt.side, line:tgt.line, body, author:'human'});
    await loadAll();
  };
  const cancel = el('button','btn ghost','キャンセル');
  cancel.onclick = ()=>{ state.draft=''; state.openForm=null; render(); };
  actions.appendChild(submit); actions.appendChild(cancel);
  form.appendChild(ta); form.appendChild(actions);
  return form;
}

function replyForm(parentId){
  const form = el('div','cform');
  const ta = el('textarea'); ta.placeholder='返信…';
  const actions = el('div','actions');
  const submit = el('button','btn ghost','返信');
  submit.onclick = async ()=>{
    const body = ta.value.trim(); if(!body) return;
    await postJSON('/api/comments/reply', {parent_id:parentId, body, author:'human'});
    await loadAll();
  };
  actions.appendChild(submit);
  form.appendChild(ta); form.appendChild(actions);
  return form;
}

function openForm(file, side, line){
  state.openForm = keyOf(file, side, line);
  state.draft = '';
  render();
  restoreForm();
}
function restoreForm(){
  const ta = document.getElementById('cf-active');
  if(ta){ ta.focus(); ta.scrollIntoView({block:'center', behavior:'smooth'}); }
}

async function refresh(){
  const sy = window.scrollY;
  await loadAll();
  window.scrollTo(0, sy);
}

document.getElementById('modebtn').onclick = ()=>{
  state.mode = state.mode==='split' ? 'unified' : 'split';
  localStorage.setItem('diffReviewMode', state.mode);
  render();
};

document.getElementById('treebtn').onclick = ()=>{
  state.treeCollapsed = !state.treeCollapsed;
  localStorage.setItem('diffReviewTreeCollapsed', state.treeCollapsed ? '1' : '0');
  applyTreeCollapsed();
};
applyTreeCollapsed();

document.querySelectorAll('#viewseg button').forEach(b=>{
  b.onclick = ()=>{
    if(state.view===b.dataset.view) return;
    state.view = b.dataset.view;
    localStorage.setItem('diffReviewView', state.view);
    state.openForm = null; // ビューをまたぐ編集中フォームは畳む
    loadAll(); // 選択ビューの diff を取り直して再描画
  };
});

loadAll();
setInterval(async ()=>{
  try{
    const v = (await (await fetch('/__version')).text()).trim();
    if(state.version!==null && v!==state.version){ await refresh(); }
    state.version = v;
    document.getElementById('status').textContent='接続中';
  }catch(e){ document.getElementById('status').textContent='切断'; }
}, 1000);
</script>
</body>
</html>]==]

--- 完全な HTML を返す。opts.repo_root はタイトルに使う。
function M.render(opts)
  opts = opts or {}
  local title = 'Diff Review'
  if opts.repo_root and opts.repo_root ~= '' then
    title = 'Diff Review · ' .. vim.fn.fnamemodify(opts.repo_root, ':t')
  end
  -- 関数置換にして、タイトルに `%` が含まれても gsub の置換パターンとして解釈されないようにする。
  return (PAGE:gsub('__TITLE__', function() return html_escape(title) end))
end

M._private = {
  html_escape = html_escape,
  PAGE = PAGE,
}

return M
