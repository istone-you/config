-- Code Notes のブラウザ画面。

local M = {}

local function html_escape(s)
  return (tostring(s or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

local PAGE = [==[<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
*{box-sizing:border-box}
:root{--header-h:49px}
body{margin:0;background:#0d1117;color:#e6edf3;font:14px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow:hidden}
header{height:var(--header-h);background:#161b22;border-bottom:1px solid #30363d;padding:10px 18px;display:flex;gap:12px;align-items:center}
h1{font-size:15px;margin:0;font-weight:650}
.meta,.status{color:#8b949e;font-size:12px}.spacer{flex:1}
button{background:#21262d;color:#c9d1d9;border:1px solid #30363d;border-radius:6px;padding:5px 10px;cursor:pointer}
button:hover{background:#30363d}button.primary{background:#238636;border-color:#238636;color:#fff}button.danger{color:#f85149}
.seg{display:inline-flex;border:1px solid #30363d;border-radius:8px;overflow:hidden}
.seg button{border:0;border-radius:0}.seg button+button{border-left:1px solid #30363d}.seg button.active{background:#388bfd33;color:#79c0ff}
#layout{display:grid;grid-template-columns:minmax(260px,380px) 1fr;height:calc(100vh - var(--header-h));min-height:0}
#list{border-right:1px solid #30363d;overflow:auto;min-height:0}.row{padding:10px 12px;border-bottom:1px solid #21262d;cursor:pointer}
.row:hover{background:#11161d}.row.active{background:#172033}
.rowmeta{display:flex;gap:6px;align-items:center;margin-top:6px;color:#8b949e;font-size:12px}
.badge{border:1px solid #30363d;border-radius:999px;padding:0 7px;font-size:11px;color:#8b949e}
.badge.open{color:#79c0ff;border-color:#1f6feb}.badge.closed{color:#3fb950;border-color:#238636}
.path{font:12px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;color:#79c0ff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.text{margin-top:4px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.empty{color:#8b949e;padding:36px;text-align:center}
#detail{padding:22px;overflow:auto;min-height:0}.detail-card{max-width:980px}
.body{white-space:pre-wrap;font-size:16px;line-height:1.7;margin:14px 0 20px}
.topline{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.topline .path{flex:1;min-width:220px}
.code{border:1px solid #30363d;border-radius:6px;overflow:auto;background:#010409;margin:0 0 18px}
.code table{border-collapse:collapse;width:100%;font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.code td{padding:0 10px;vertical-align:top}.code .ln{width:1%;text-align:right;color:#6e7681;border-right:1px solid #21262d;user-select:none}
.code .src{white-space:pre}.code .hljs{background:transparent;padding:0;color:inherit}.code tr.hit{background:#1f2a44}.code tr.hit .ln{color:#79c0ff}
.kv{display:grid;grid-template-columns:90px 1fr;gap:6px 12px;color:#8b949e;margin:12px 0}.kv code{color:#c9d1d9}
.comments{margin-top:22px;border-top:1px solid #30363d;padding-top:14px}.comments h2{font-size:14px;margin:0 0 10px}
.comment{border-bottom:1px solid #21262d;padding:10px 0}.comment:last-child{border-bottom:0}
.comment .who{display:flex;gap:8px;align-items:center;color:#8b949e;font-size:12px;margin-bottom:4px}
.comment .who .author-ai{color:#d2a8ff;font-weight:600}.comment .who .author-human{color:#79c0ff;font-weight:600}
.comment .body{font-size:14px;line-height:1.6;margin:0;white-space:pre-wrap}
.comment .del{margin-left:auto;border:0;background:none;color:#6e7681;padding:0 4px}.comment .del:hover{color:#f85149;background:none}
.comment-form{display:grid;gap:8px;margin-top:12px}.comment-form textarea{min-height:74px}
textarea,input{width:100%;background:#0d1117;color:#e6edf3;border:1px solid #30363d;border-radius:6px;padding:8px;font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
textarea{min-height:110px;resize:vertical}.form{display:grid;gap:8px}
.form .grid{display:grid;grid-template-columns:1fr 90px 90px 90px;gap:8px}.actions{display:flex;gap:8px;flex-wrap:wrap}
.modal{position:fixed;inset:0;z-index:20;display:none;align-items:center;justify-content:center;background:#01040999;padding:18px}
.modal.open{display:flex}.dialog{width:min(720px,100%);background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px;box-shadow:0 20px 60px #0008}
.dialog-head{display:flex;align-items:center;gap:12px;margin-bottom:12px}.dialog-head strong{font-size:14px}.dialog-head .spacer{flex:1}
@media(max-width:760px){#layout{grid-template-columns:1fr;grid-template-rows:minmax(180px,40vh) 1fr}#list{border-right:0;border-bottom:1px solid #30363d}}
</style>
<link rel="stylesheet" href="/__vendor/highlight-theme.css">
<script src="/__vendor/highlight.min.js"></script>
</head>
<body>
<header>
  <h1>Code Notes</h1>
  <span class="meta" id="repo"></span>
  <span class="spacer"></span>
  <span class="seg" id="filterseg"><button data-filter="all">All</button><button data-filter="open">Open</button><button data-filter="closed">Closed</button></span>
  <button id="showadd" class="primary">Add</button>
  <button id="clear" class="danger">Clear</button>
  <span class="status" id="status">Connecting…</span>
</header>
<div id="layout">
  <section id="list"></section>
  <section id="detail"></section>
</div>
<div class="modal" id="modal">
  <div class="dialog">
    <div class="dialog-head"><strong>Add entry</strong><span class="spacer"></span><button id="canceladd">Close</button></div>
    <div id="formhost"></div>
  </div>
</div>
<script>
const state={session:null,items:[],selected:null,version:null,filter:localStorage.getItem('codeNotesFilter')||'all'};
const $=id=>document.getElementById(id);
function esc(s){return String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}
async function getJSON(p){const r=await fetch(p);return r.json();}
async function postJSON(p,b){const r=await fetch(p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b||{})});return {ok:r.ok,data:await r.json().catch(()=>({}))};}
function loc(f){
  if(!f.file) return '(no location)';
  const start=f.line||1, end=f.lineEnd&&f.lineEnd!==start ? `-${f.lineEnd}` : '';
  return `${f.file}:${start}${end}:${f.col||1}`;
}
function displayAuthor(a){return a==='human'?'You':(a||'ai');}
function authorClass(a){return a==='human'?'author-human':'author-ai';}
function visibleItems(){return state.items.filter(x=>state.filter==='all'||(x.status||'open')===state.filter);}
const HL_EXT={lua:'lua',js:'javascript',jsx:'javascript',mjs:'javascript',cjs:'javascript',ts:'typescript',tsx:'typescript',py:'python',go:'go',rs:'rust',rb:'ruby',java:'java',kt:'kotlin',swift:'swift',c:'c',h:'c',cpp:'cpp',cc:'cpp',hpp:'cpp',cs:'csharp',php:'php',json:'json',md:'markdown',markdown:'markdown',html:'xml',htm:'xml',xml:'xml',vue:'xml',css:'css',scss:'scss',less:'less',sh:'bash',bash:'bash',zsh:'bash',sql:'sql',yaml:'yaml',yml:'yaml',toml:'ini',ini:'ini'};
function hlLang(path){
  if(!window.hljs||!path) return null;
  const base=(path.split('/').pop()||'').toLowerCase();
  if(base==='dockerfile') return hljs.getLanguage('dockerfile')?'dockerfile':null;
  if(base==='makefile') return hljs.getLanguage('makefile')?'makefile':null;
  const ext=base.indexOf('.')>=0?base.split('.').pop():'';
  const lang=HL_EXT[ext];
  return (lang&&hljs.getLanguage(lang))?lang:null;
}
function codeLineHTML(line,lang){
  if(lang&&window.hljs){
    try{return hljs.highlight(line,{language:lang,ignoreIllegals:true}).value;}catch(e){}
  }
  return esc(line);
}
function codeHTML(f){
  if(!f.code||!f.code.text) return '';
  const lines=String(f.code.text).split('\n');
  const start=Number(f.code.startLine)||1;
  const hit=Number(f.code.highlightLine)||start;
  const hitEnd=Number(f.code.highlightEndLine)||hit;
  const lang=hlLang(f.file);
  return `<div class="code"><table>${lines.map((line,i)=>{
    const n=start+i;
    return `<tr class="${n>=hit&&n<=hitEnd?'hit':''}"><td class="ln">${n}</td><td class="src"><code class="${lang?'hljs language-'+esc(lang):''}">${codeLineHTML(line,lang)}</code></td></tr>`;
  }).join('')}</table></div>`;
}
async function load(){
  try{
    state.session=await getJSON('/api/session');
    const data=await getJSON('/api/entries');
    state.items=data.entries||[]; state.version=String(data.version);
    if(state.selected && !state.items.find(x=>x.id===state.selected)) state.selected=null;
    const vis=visibleItems();
    if(state.selected && !vis.find(x=>x.id===state.selected)) state.selected=null;
    if(!state.selected && vis[0]) state.selected=vis[0].id;
    $('repo').textContent=state.session.repoRoot||''; $('status').textContent='Connected';
    render();
  }catch(e){$('status').textContent='Disconnected';}
}
function selected(){return state.items.find(x=>x.id===state.selected)||null;}
function renderList(){
  const list=$('list'); list.innerHTML='';
  const items=visibleItems();
  if(!items.length){list.innerHTML='<div class="empty">entry はありません</div>'; return;}
  for(const f of items){
    const row=document.createElement('div'); row.className='row '+(f.id===state.selected?'active ':'');
    const st=f.status||'open';
    const count=(f.comments||[]).length;
    row.innerHTML=`<div class="path">${esc(loc(f))}</div><div class="text">${esc(f.text)}</div><div class="rowmeta"><span class="badge ${esc(st)}">${esc(st)}</span><span>${count} comments</span></div>`;
    row.onclick=()=>{state.selected=f.id;render();};
    list.appendChild(row);
  }
}
function renderDetail(){
  const f=selected(); const d=$('detail');
  if(!f){d.innerHTML=visibleItems().length?'<div class="empty">左の entry を選択</div>':''; return;}
  const st=f.status||'open';
  d.innerHTML=`<div class="detail-card">
    <div class="topline"><div class="path">${esc(loc(f))}</div><button id="toggleStatus">${st==='closed'?'Reopen':'Close'}</button></div>
    <div class="body">${esc(f.text)}</div>
    ${codeHTML(f)}
    <div class="kv">
      <div>status</div><code>${esc(st)}</code>
      <div>author</div><code>${esc(displayAuthor(f.author))}</code>
      <div>id</div><code>${esc(f.id)}</code>
    </div>
    <div class="actions">
      <button class="primary" id="jump">Open in nvim</button>
      <button class="danger" id="delete">Delete</button>
    </div>
    ${commentsHTML(f)}
  </div>`;
  $('toggleStatus').onclick=async()=>{ await postJSON('/api/entries/status',{id:f.id,status:st==='closed'?'open':'closed'}); await load(); };
  $('jump').onclick=async()=>{ if(f.file) await postJSON('/api/jump',{file:f.file,line:f.line,col:f.col}); };
  $('delete').onclick=async()=>{ await postJSON('/api/entries/delete',{id:f.id}); state.selected=null; await load(); };
  $('addcomment').onclick=async()=>{
    const text=$('newcomment').value.trim(); if(!text) return;
    await postJSON('/api/entries/comment',{id:f.id,text,author:'human'});
    await load();
  };
  for(const btn of Array.from(document.querySelectorAll('[data-del-comment]'))){
    btn.onclick=async()=>{ await postJSON('/api/entries/comment/delete',{id:f.id,commentId:btn.dataset.delComment}); await load(); };
  }
}
function commentsHTML(f){
  const items=f.comments||[];
  return `<div class="comments"><h2>Comments</h2>${items.map(c=>`<div class="comment"><div class="who"><span class="${authorClass(c.author)}">${esc(displayAuthor(c.author))}</span><span>${esc(new Date((c.createdAt||0)*1000).toLocaleString())}</span><button class="del" data-del-comment="${esc(c.id)}">Delete</button></div><div class="body">${esc(c.text)}</div></div>`).join('')}<div class="comment-form"><textarea id="newcomment" placeholder="コメントを書く..."></textarea><div class="actions"><button class="primary" id="addcomment">Comment</button></div></div></div>`;
}
function formHTML(){return `<div class="form">
  <input id="newloc" placeholder="file:line:col or file:start-end:col">
  <textarea id="newtext" placeholder="新しい entry"></textarea>
  <div class="actions"><button class="primary" id="add">Add entry</button><button id="canceladd2">Cancel</button></div>
</div>`;}
function parseLocation(raw){
  const s=String(raw||'').trim();
  if(!s) return {};
  const range=s.match(/^(.+):(\d+)-(\d+)(?::(\d+))?$/);
  if(range) return {file:range[1],line:Number(range[2]),lineEnd:Number(range[3]),col:range[4]?Number(range[4]):undefined};
  const point=s.match(/^(.+):(\d+)(?::(\d+))?$/);
  if(point) return {file:point[1],line:Number(point[2]),col:point[3]?Number(point[3]):undefined};
  return {file:s};
}
function openForm(){
  $('formhost').innerHTML=formHTML();
  $('modal').classList.add('open');
  bindForm();
  $('newloc').focus();
}
function closeForm(){
  $('modal').classList.remove('open');
  $('formhost').innerHTML='';
}
function bindForm(){
  $('add').onclick=async()=>{
    const loc=parseLocation($('newloc').value);
    const body=Object.assign({text:$('newtext').value,author:'human'},loc);
    const r=await postJSON('/api/entries',body); if(r.ok){state.selected=r.data.entry.id; closeForm(); await load();}
  };
  $('canceladd2').onclick=closeForm;
}
function render(){renderList();renderDetail();}
function renderFilter(){
  document.querySelectorAll('#filterseg button').forEach(b=>b.classList.toggle('active',b.dataset.filter===state.filter));
}
$('showadd').onclick=openForm;
$('canceladd').onclick=closeForm;
$('modal').onclick=e=>{if(e.target===$('modal')) closeForm();};
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&$('modal').classList.contains('open')) closeForm();});
$('clear').onclick=async()=>{if(confirm('entry をすべて削除しますか？')){await postJSON('/api/entries/clear',{});state.selected=null;await load();}};
document.querySelectorAll('#filterseg button').forEach(b=>{b.onclick=()=>{state.filter=b.dataset.filter;localStorage.setItem('codeNotesFilter',state.filter);state.selected=null;renderFilter();render();};});
renderFilter();
setInterval(async()=>{try{const v=await fetch('/__version').then(r=>r.text()); if(state.version!=null && v!==state.version) await load();}catch(e){}},1000);
load();
</script>
</body>
</html>]==]

function M.render(opts)
  opts = opts or {}
  local title = 'Code Notes'
  if opts.repo_root and opts.repo_root ~= '' then
    title = title .. ' - ' .. vim.fn.fnamemodify(opts.repo_root, ':t')
  end
  return PAGE:gsub('__TITLE__', html_escape(title))
end

return M
