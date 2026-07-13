#!/bin/sh
# Runtime patches for published GHCR images (safe no-ops when already fixed).
# 1) Health authConfigured: NEXT_PUBLIC_* empty at build → read process.env
# 2) URL chips: getTextFromParts ignored data-sourceUrl → prefetch never ran
# 3) Office tools: bare "POAM"/"SSP" wrongly opened Word tools and drowned answers
# 4) Related follow-ups: small local models skip ```spec — inject after answer
set -e

if command -v node >/dev/null 2>&1; then
  node <<'NODE'
const fs = require("fs");
const path = require("path");

function walk(dir, out = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.isFile() && e.name.endsWith(".js") && !e.name.endsWith(".map"))
      out.push(p);
  }
  return out;
}

function patchFile(file, oldStr, newStr, label) {
  let data;
  try {
    data = fs.readFileSync(file, "utf8");
  } catch {
    return false;
  }
  // Only treat as "already applied" when the NEW marker is unique enough
  // (short replacements like "null" appear everywhere and would false-positive).
  const uniqueEnough = newStr.length >= 24 || newStr.includes("Knonix") || newStr.includes("knonix-");
  if (uniqueEnough && data.includes(newStr) && !data.includes(oldStr)) {
    console.log(`[knonix-entrypoint] ${label}: already applied (${path.basename(file)})`);
    return true;
  }
  if (!data.includes(oldStr)) return false;
  fs.writeFileSync(file, data.split(oldStr).join(newStr));
  console.log(`[knonix-entrypoint] ${label}: patched ${path.basename(file)}`);
  return true;
}

const serverFiles = walk("/app/.next/server");
const staticFiles = walk("/app/.next/static");
const allFiles = serverFiles.concat(staticFiles);

// Minified ensure-related helper (injects tappable Related buttons when model omitted ```spec).
// Args: t=answer text, u=optional user query for topic grounding.
const ENSURE_RELATED_FN =
  'function(t,u){if(!t||t.length<100)return t;if(/```spec[\\s\\S]*?submitQuery[\\s\\S]*?```/.test(t)||/```spec/.test(t))return t;let plain=t.replace(/```[\\s\\S]*?```/g,"").replace(/\\[([^\\]]+)\\]\\([^)]+\\)/g,"$1").replace(/[#*_>`|]/g," ").replace(/\\s+/g," ").trim();if(plain.length<80)return t;if(/^(hi|hello|hey|thanks|thank you|ok|okay|sure)\\b/i.test(plain)&&plain.length<180)return t;let raw=((u||"").replace(/\\s+/g," ").trim()||(t.match(/^#{1,3}\\s+(.+)$/m)||[])[1]||plain.split(/(?<=[.!?])\\s+/)[0]||plain).trim(),topic=raw.replace(/^(what|how|why|when|where|who|which)\\s+(is|are|does|do|did|can|could|should|would|will)\\s+/i,"").replace(/^(what|how|why|when|where|who|which)\\s+/i,"").replace(/\\?+$/,"").replace(/^[\\d.\\-\\s]+/,"").trim().slice(0,64);let q1=(topic.length>8?"Explain more about "+topic:"Can you explain this in more detail?").slice(0,80),q2=(topic.length>8?"What should I do next with "+topic+"?":"What are practical next steps?").slice(0,80),q3=(topic.length>8?"What related topics connect to "+topic+"?":"What related topics should I explore?").slice(0,80),btn=(id,q)=>JSON.stringify({op:"add",path:"/elements/"+id,value:{type:"Button",props:{text:q,variant:"link",icon:"arrow-right"},on:{press:{action:"submitQuery",params:{query:q}}},children:[]}});return t.replace(/\\s+$/,"")+"\\n\\n```spec\\n"+[\'{"op":"add","path":"/root","value":"main"}\',\'{"op":"add","path":"/elements/main","value":{"type":"Stack","props":{"direction":"vertical","gap":"sm"},"children":["header","questions"]}}\',\'{"op":"add","path":"/elements/header","value":{"type":"Heading","props":{"title":"Related","icon":"related"},"children":[]}}\',\'{"op":"add","path":"/elements/questions","value":{"type":"Stack","props":{"direction":"vertical","gap":"xs"},"children":["q1","q2","q3"]}}\',btn("q1",q1),btn("q2",q2),btn("q3",q3)].join("\\n")+"\\n```"}';

// --- 1) Health check NEXT_PUBLIC inlining ---
{
  const OLD = 'authConfigured:!n||!!"".trim()&&!!"".trim()';
  const NEW =
    'authConfigured:!n||!!(process.env.NEXT_PUBLIC_SUPABASE_URL||"").trim()' +
    '&&!!(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"").trim()';
  let ok = false;
  for (const f of serverFiles) if (patchFile(f, OLD, NEW, "auth-health")) ok = true;
  if (!ok) console.log("[knonix-entrypoint] auth-health: pattern not found");
}

// --- 2) URL chips + pasted content in userQuery (triggers server prefetch) ---
{
  const OLD =
    'function d(e){return e?.filter(e=>"text"===e.type).map(e=>e.text).join(" ")??""}';
  const NEW =
    'function d(e){if(!e||!e.length)return"";let t=[];for(let r of e){if("text"===r.type&&"string"==typeof r.text&&r.text)t.push(r.text);else if("data-sourceUrl"===r.type&&r.data&&"string"==typeof r.data.url&&r.data.url)t.push(r.data.url);else if("data-pastedContent"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push(r.data.text);else if("data-quotedContext"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push(r.data.text);else if("data-noteContext"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push((r.data.title?String(r.data.title)+": ":"")+r.data.text)}return t.join(" ")}';
  let ok = false;
  for (const f of serverFiles) if (patchFile(f, OLD, NEW, "url-prefetch")) ok = true;
  if (!ok) console.log("[knonix-entrypoint] url-prefetch: pattern not found");
}

// --- 3) Do not treat bare POAM/SSP as "create a Word doc" ---
// "What does POAM stand for on this NIST page?" was opening office tools and
// the small local model then ignored the already-visited page content.
{
  const OLD1 =
    "ssp|poa&m|poam|system security plan|write|draft|generate|create|produce|policy|procedure|word|docx|excel|xlsx|download|export|document package";
  // Require document-creation verbs / file types — not the acronym alone.
  const NEW1 =
    "write|draft|generate|create|produce|download|export|document package|word|docx|excel|xlsx|pdf|spreadsheet|presentation|policy|procedure";
  let ok = false;
  for (const f of serverFiles) if (patchFile(f, OLD1, NEW1, "office-poam-false-positive")) ok = true;

  const OLD2 = "export (as|to)|download (as|a )|ssp|poa&m|poam";
  const NEW2 = "export (as|to)|download (as|a )|document package";
  for (const f of serverFiles) if (patchFile(f, OLD2, NEW2, "office-poam-false-positive-2")) ok = true;

  // When user sites were visited successfully, answer from page text first
  // (tools=[]). Only re-enable office tools if they clearly ask to create a file.
  // Original: 0===IZ.length?(IN=IN.filter(I=>"fetch"!==I),Ip=Ig?Math.min(IR.stepCap,Math.max(2,Ip)):1)
  const OLD3 =
    '0===IZ.length?(IN=IN.filter(I=>"fetch"!==I),Ip=Ig?Math.min(IR.stepCap,Math.max(2,Ip)):1)';
  // d = userQuery in this minified scope
  const NEW3 =
    '0===IZ.length?(/\\b(write|draft|generate|create|produce|download|export|word|docx|excel|xlsx|pdf|document package)\\b/i.test(d||"")?(IN=IN.filter(I=>"fetch"!==I),Ip=Math.min(IR.stepCap,Math.max(2,Ip))):(IN=[],Ip=1))';
  let clampOk = false;
  for (const f of serverFiles) {
    if (patchFile(f, OLD3, NEW3, "visited-sites-answer-first")) clampOk = true;
  }
  if (!ok && !clampOk) {
    console.log("[knonix-entrypoint] office/visited clamps: patterns not found");
  }
}

// --- 3b) Spaces: after create, share with all active org members (org-only) ---
// App lists/opens spaces via space_members ⋈ userId; only creator was added by default.
// Do NOT use drizzle eq/and here: in createSpace the space id shadows the orm alias (`t`).
// Select memberships and filter in JS; schema export includes memberships + spaceMembers.
{
  function orgSharePatch(schema, spaceVar, userObj) {
    const oldStr =
      `await e.insert(${schema}.spaceMembers).values({spaceId:${spaceVar},userId:${userObj}.userId,role:"owner"})});`;
    const newStr =
      `await e.insert(${schema}.spaceMembers).values({spaceId:${spaceVar},userId:${userObj}.userId,role:"owner"});` +
      `try{const _om=await e.select({userId:${schema}.memberships.userId,orgId:${schema}.memberships.orgId,status:${schema}.memberships.status}).from(${schema}.memberships);` +
      `for(const _m of _om){if(_m.orgId===${userObj}.orgId&&"active"===_m.status&&_m.userId&&_m.userId!==${userObj}.userId){try{await e.insert(${schema}.spaceMembers).values({spaceId:${spaceVar},userId:_m.userId,role:"editor"})}catch(_e){}}}` +
      `}catch(_e){console.warn("[spaces] org share:",_e)}});`;
    return [oldStr, newStr];
  }
  // Chunk alias variants observed in .next server builds
  const variants = [
    orgSharePatch("i", "t", "r"), // spaceId=t, params=r
    orgSharePatch("n", "t", "r"),
    orgSharePatch("s", "r", "t"), // spaceId=r, params=t
    orgSharePatch("n", "r", "t"),
    orgSharePatch("a", "r", "t"),
  ];
  let ok = false;
  for (const [oldStr, newStr] of variants) {
    for (const f of serverFiles) {
      if (patchFile(f, oldStr, newStr, "spaces-org-share-on-create")) ok = true;
    }
  }
  if (!ok) console.log("[knonix-entrypoint] spaces-org-share-on-create: pattern not found");
}

// --- 4) Related follow-ups fallback (small Ollama models rarely emit ```spec) ---
// UI needs a valid ```spec JSONL with Button+submitQuery. forceFollowUps is set
// but never enforced server-side — inject after stream completes (persist) and in
// the answer renderer when status is ready (live UI).
{
  // 4a) Server: inject into saved assistant message after IK cleanup
  // Scope: relatedEnabled=p, userQuery=w inside cM onFinish
  const OLD_SAVE =
    "let G=IK(I.text);return G===I.text?I:{...I,text:G}";
  const NEW_SAVE =
    "let G=IK(I.text);if(!1!==p)G=(" +
    ENSURE_RELATED_FN +
    ')(G,w||"");return G===I.text?I:{...I,text:G}';
  let saveOk = false;
  for (const f of serverFiles) {
    if (patchFile(f, OLD_SAVE, NEW_SAVE, "related-followups-save")) saveOk = true;
  }

  // 4b) Client answer section (static + SSR): inject when not streaming
  // Static minified uses message:e status:c; SSR uses message:a status:j
  const clientPatches = [
    {
      label: "related-followups-ui-static",
      old: "(0,t.jsx)(k.MarkdownMessage,{message:e,citationMaps:u})",
      // status c = chat status; only inject after stream finished
      new:
        '(0,t.jsx)(k.MarkdownMessage,{message:("streaming"===c||"submitted"===c)?e:(' +
        ENSURE_RELATED_FN +
        ")(e),citationMaps:u})",
    },
    {
      label: "related-followups-ui-ssr",
      old: "(0,b.jsx)(x.MarkdownMessage,{message:a,citationMaps:l})",
      new:
        '(0,b.jsx)(x.MarkdownMessage,{message:("streaming"===j||"submitted"===j)?a:(' +
        ENSURE_RELATED_FN +
        ")(a),citationMaps:l})",
    },
  ];
  let uiOk = false;
  for (const { label, old, new: neu } of clientPatches) {
    for (const f of allFiles) {
      if (patchFile(f, old, neu, label)) uiOk = true;
    }
  }

  if (!saveOk && !uiOk) {
    console.log("[knonix-entrypoint] related-followups: patterns not found");
  } else {
    console.log(
      `[knonix-entrypoint] related-followups: save=${saveOk} ui=${uiOk}`
    );
  }
}

// --- 5) Thinking dots cleanup: only ONE bounce-dot group (activity header) ---
// List rows previously also rendered bounce dots + spin icons per active step.
{
  const dotPatches = [
    // Static client: remove per-row bounce dots next to labels (header keeps the only dots)
    {
      label: "thinking-dots-row-static",
      old: '"active"===e.status?(0,i.jsx)(j,{size:"sm",className:"text-primary"}):null',
      new: '/*knonix-one-think-dots*/null',
    },
    // Static client: replace per-row spin loader with a quiet solid marker
    {
      label: "thinking-spin-row-static",
      old: '"active"===e.status?(0,i.jsx)(h,{className:(0,o.cn)("size-4 animate-spin text-primary",t)})',
      new: '"active"===e.status?(0,i.jsx)("span",{className:(0,o.cn)("mt-1 block size-2 rounded-full bg-primary knonix-step-dot",t),"aria-hidden":!0})',
    },
    // SSR: remove per-row bounce dots
    {
      label: "thinking-dots-row-ssr",
      old: '"active"===a.status?(0,g.jsx)(u,{size:"sm",className:"text-primary"}):null',
      new: '/*knonix-one-think-dots*/null',
    },
    // SSR: quiet solid marker instead of spin
    {
      label: "thinking-spin-row-ssr",
      old: '"active"===a.status?(0,g.jsx)(o,{className:(0,i.cn)("size-4 animate-spin text-primary",b)})',
      new: '"active"===a.status?(0,g.jsx)("span",{className:(0,i.cn)("mt-1 block size-2 rounded-full bg-primary knonix-step-dot",b),"aria-hidden":!0})',
    },
  ];
  let dotsOk = false;
  for (const { label, old, new: neu } of dotPatches) {
    for (const f of allFiles) {
      if (patchFile(f, old, neu, label)) dotsOk = true;
    }
  }
  if (!dotsOk) console.log("[knonix-entrypoint] thinking-dots: patterns not found");
}

// --- 6) Chat resources rail (links / files / artifacts) — right side, collapsible ---
// Collects visitedSources, tool search/fetch URLs, uploads, and shows them per chat.
{
  // Resource collector + collapsible rail (uses ChatMessages module aliases: t=jsx,s=react,n=cn)
  const RAIL_FN_STATIC =
    'function KnonixResourcesRail({sections:e}){let[a,r]=(0,s.useState)(!0),i=(0,s.useMemo)(()=>{let t=[],l=[],o=new Set;function c(e,s){if(!e||o.has(e))return;try{new URL(e)}catch{return}o.add(e),t.push({url:e,title:(s||e).slice(0,120)})}function d(e,s,a){l.push({name:e||"File",url:s||"",kind:a||"file"})}for(let s of e||[]){let a=s.userMessage;if(a?.parts)for(let e of a.parts){if("file"===e.type)d(e.filename||e.name,e.url,"upload");if("text"===e.type&&"string"==typeof e.text){let s=e.text.match(/https?:\\/\\/[^\\s)\\]>\'"\\]]+/g)||[];for(let e of s)c(e.replace(/[.,;:]+$/,""),e)}}for(let a of s.assistantMessages||[]){if(Array.isArray(a.metadata?.visitedSources))for(let e of a.metadata.visitedSources)e?.url&&c(e.url,e.title);if(a.parts)for(let e of a.parts){if("tool-search"===e.type&&e.output?.results)for(let s of e.output.results)c(s.url||s.link,s.title);if("tool-fetch"===e.type){let s=e.input?.url||e.output?.url||e.output?.results?.[0]?.url;s&&c(s,e.output?.results?.[0]?.title||s)}if("file"===e.type)d(e.filename||e.name,e.url,"file");if(e.type&&String(e.type).includes("office")||"data-officeDocument"===e.type)d(e.data?.filename||e.filename||"Document",e.data?.url||e.url||"","artifact");if("text"===e.type&&"string"==typeof e.text){let s=e.text.match(/https?:\\/\\/[^\\s)\\]>\'"\\]]+/g)||[];for(let e of s)c(e.replace(/[.,;:]+$/,""),e)}}}}return{links:t,files:l}},[e]),l=i.links.length+i.files.length;if(0===l)return null;return(0,t.jsxs)("aside",{className:(0,n.cn)("knonix-resources-rail hidden md:flex shrink-0 flex-col border-l bg-card/40 backdrop-blur-sm transition-[width] duration-200",a?"w-72":"w-10"),"aria-label":"Chat resources",children:[(0,t.jsxs)("button",{type:"button",onClick:()=>r(e=>!e),className:"flex h-11 items-center gap-2 border-b px-2 text-xs font-medium text-muted-foreground hover:text-foreground",title:a?"Collapse resources":"Expand resources",children:[(0,t.jsx)("span",{className:"inline-flex size-6 items-center justify-center rounded-md border bg-background text-[11px]",children:a?"»":"«"}),(0,t.jsx)("span",{className:(0,n.cn)("truncate",!a&&"sr-only"),children:`Resources (${l})`})]}),a?(0,t.jsxs)("div",{className:"min-h-0 flex-1 space-y-4 overflow-y-auto p-3 text-sm",children:[i.files.length?(0,t.jsxs)("div",{children:[(0,t.jsx)("h3",{className:"mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground",children:"Files & artifacts"}),(0,t.jsx)("ul",{className:"space-y-1.5",children:i.files.map((e,s)=>(0,t.jsx)("li",{className:"rounded-md border bg-background/80 px-2 py-1.5",children:e.url?(0,t.jsx)("a",{href:e.url,target:"_blank",rel:"noopener noreferrer",className:"block truncate text-primary hover:underline",children:e.name}):(0,t.jsx)("span",{className:"truncate",children:e.name})},s))}]}):null,i.links.length?(0,t.jsxs)("div",{children:[(0,t.jsx)("h3",{className:"mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground",children:"Links & sources"}),(0,t.jsx)("ul",{className:"space-y-1.5",children:i.links.slice(0,40).map((e,s)=>(0,t.jsx)("li",{children:(0,t.jsxs)("a",{href:e.url,target:"_blank",rel:"noopener noreferrer",className:"block rounded-md border bg-background/80 px-2 py-1.5 hover:border-primary/40",children:[(0,t.jsx)("span",{className:"line-clamp-2 text-foreground",children:e.title}),(0,t.jsx)("span",{className:"mt-0.5 block truncate text-[11px] text-muted-foreground",children:e.url.replace(/^https?:\\/\\//,"")})]})},s))}]}):null,0===l?(0,t.jsx)("p",{className:"text-xs text-muted-foreground",children:"Links, files, and sources from this chat appear here."}):null]}):null])}';

  // SSR module uses g=jsx, h=react, i=cn
  const RAIL_FN_SSR =
    'function KnonixResourcesRail({sections:a}){let[b,c]=(0,h.useState)(!0),d=(0,h.useMemo)(()=>{let e=[],f=[],g=new Set;function i(a,b){if(!a||g.has(a))return;try{new URL(a)}catch{return}g.add(a),e.push({url:a,title:(b||a).slice(0,120)})}function j(a,b,c){f.push({name:a||"File",url:b||"",kind:c||"file"})}for(let b of a||[]){let c=b.userMessage;if(c?.parts)for(let a of c.parts){if("file"===a.type)j(a.filename||a.name,a.url,"upload");if("text"===a.type&&"string"==typeof a.text){let b=a.text.match(/https?:\\/\\/[^\\s)\\]>\'"\\]]+/g)||[];for(let a of b)i(a.replace(/[.,;:]+$/,""),a)}}for(let c of b.assistantMessages||[]){if(Array.isArray(c.metadata?.visitedSources))for(let a of c.metadata.visitedSources)a?.url&&i(a.url,a.title);if(c.parts)for(let a of c.parts){if("tool-search"===a.type&&a.output?.results)for(let b of a.output.results)i(b.url||b.link,b.title);if("tool-fetch"===a.type){let b=a.input?.url||a.output?.url||a.output?.results?.[0]?.url;b&&i(b,a.output?.results?.[0]?.title||b)}if("file"===a.type)j(a.filename||a.name,a.url,"file");if(a.type&&String(a.type).includes("office")||"data-officeDocument"===a.type)j(a.data?.filename||a.filename||"Document",a.data?.url||a.url||"","artifact");if("text"===a.type&&"string"==typeof a.text){let b=a.text.match(/https?:\\/\\/[^\\s)\\]>\'"\\]]+/g)||[];for(let a of b)i(a.replace(/[.,;:]+$/,""),a)}}}}return{links:e,files:f}},[a]),e=d.links.length+d.files.length;if(0===e)return null;return(0,g.jsxs)("aside",{className:(0,i.cn)("knonix-resources-rail hidden md:flex shrink-0 flex-col border-l bg-card/40 backdrop-blur-sm transition-[width] duration-200",b?"w-72":"w-10"),"aria-label":"Chat resources",children:[(0,g.jsxs)("button",{type:"button",onClick:()=>c(a=>!a),className:"flex h-11 items-center gap-2 border-b px-2 text-xs font-medium text-muted-foreground hover:text-foreground",title:b?"Collapse resources":"Expand resources",children:[(0,g.jsx)("span",{className:"inline-flex size-6 items-center justify-center rounded-md border bg-background text-[11px]",children:b?"»":"«"}),(0,g.jsx)("span",{className:(0,i.cn)("truncate",!b&&"sr-only"),children:`Resources (${e})`})]}),b?(0,g.jsxs)("div",{className:"min-h-0 flex-1 space-y-4 overflow-y-auto p-3 text-sm",children:[d.files.length?(0,g.jsxs)("div",{children:[(0,g.jsx)("h3",{className:"mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground",children:"Files & artifacts"}),(0,g.jsx)("ul",{className:"space-y-1.5",children:d.files.map((a,b)=>(0,g.jsx)("li",{className:"rounded-md border bg-background/80 px-2 py-1.5",children:a.url?(0,g.jsx)("a",{href:a.url,target:"_blank",rel:"noopener noreferrer",className:"block truncate text-primary hover:underline",children:a.name}):(0,g.jsx)("span",{className:"truncate",children:a.name})},b))}]}):null,d.links.length?(0,g.jsxs)("div",{children:[(0,g.jsx)("h3",{className:"mb-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground",children:"Links & sources"}),(0,g.jsx)("ul",{className:"space-y-1.5",children:d.links.slice(0,40).map((a,b)=>(0,g.jsx)("li",{children:(0,g.jsxs)("a",{href:a.url,target:"_blank",rel:"noopener noreferrer",className:"block rounded-md border bg-background/80 px-2 py-1.5 hover:border-primary/40",children:[(0,g.jsx)("span",{className:"line-clamp-2 text-foreground",children:a.title}),(0,g.jsx)("span",{className:"mt-0.5 block truncate text-[11px] text-muted-foreground",children:a.url.replace(/^https?:\\/\\//,"")})]})},b))}]}):null]}):null]})}';

  // Inject rail function + wrap ChatMessages return (static)
  const OLD_CM_STATIC =
    '["ChatMessages",0,function({sections:e,status:m,chatId:p,isGuest:h=!1,isCloudDeployment:x=!1,libraryAvailable:g=!0,addToolResult:f,scrollContainerRef:b,onUpdateMessage:v,reload:j,error:y,onQuoteContext:w}){';
  const NEW_CM_STATIC =
    '["ChatMessages",0,function({sections:e,status:m,chatId:p,isGuest:h=!1,isCloudDeployment:x=!1,libraryAvailable:g=!0,addToolResult:f,scrollContainerRef:b,onUpdateMessage:v,reload:j,error:y,onQuoteContext:w}){' +
    RAIL_FN_STATIC;

  const OLD_RET_STATIC =
    'return(0,t.jsx)("div",{id:"scroll-container",ref:b,role:"list","aria-roledescription":"chat messages",className:(0,n.cn)("relative size-full min-w-0 pt-12 sm:pt-14",e.length>0?"flex-1 overflow-y-auto overscroll-contain":""),children:(0,t.jsx)("div",{className:"relative mx-auto w-full min-w-0 max-w-full px-3 sm:px-4 md:max-w-3xl",children:e.map';
  const NEW_RET_STATIC =
    'return(0,t.jsxs)("div",{className:"flex size-full min-h-0 min-w-0",children:[(0,t.jsx)("div",{id:"scroll-container",ref:b,role:"list","aria-roledescription":"chat messages",className:(0,n.cn)("relative min-w-0 flex-1 pt-12 sm:pt-14",e.length>0?"overflow-y-auto overscroll-contain":""),children:(0,t.jsx)("div",{className:"relative mx-auto w-full min-w-0 max-w-full px-3 sm:px-4 md:max-w-3xl",children:e.map';

  // Close map + max-w column, then sibling resources rail, then flex row.
  // Original: s.id))})})}],510724
  // Wrapped:  s.id))})}),RAIL])}],510724
  const OLD_END_STATIC =
    'A&&a===e.length-1&&(0,t.jsxs)("div",{className:"flex items-center gap-3 py-1 md:py-4",children:[(0,t.jsx)(l.AnimatedLogo,{className:"size-10 shrink-0",animate:C}),C?null:(0,t.jsx)(d.ChatFooterMessage,{isLoading:!1})]}),a===e.length-1&&(0,t.jsx)(c.ChatError,{error:y,onRetry:j&&e.length>0?()=>{let t=e[e.length-1]?.userMessage;t?.id&&j(t.id)}:void 0})]},s.id))})})}],510724';
  const NEW_END_STATIC =
    'A&&a===e.length-1&&(0,t.jsxs)("div",{className:"flex items-center gap-3 py-1 md:py-4",children:[(0,t.jsx)(l.AnimatedLogo,{className:"size-10 shrink-0",animate:C}),C?null:(0,t.jsx)(d.ChatFooterMessage,{isLoading:!1})]}),a===e.length-1&&(0,t.jsx)(c.ChatError,{error:y,onRetry:j&&e.length>0?()=>{let t=e[e.length-1]?.userMessage;t?.id&&j(t.id)}:void 0})]},s.id))})}),(0,t.jsx)(KnonixResourcesRail,{sections:e})])}],510724';

  let railOk = false;
  for (const f of allFiles) {
    if (
      patchFile(f, OLD_CM_STATIC, NEW_CM_STATIC, "resources-rail-fn-static") &&
      patchFile(f, OLD_RET_STATIC, NEW_RET_STATIC, "resources-rail-wrap-static")
    ) {
      // end patch is required for valid JSX tree
      if (patchFile(f, OLD_END_STATIC, NEW_END_STATIC, "resources-rail-end-static"))
        railOk = true;
    }
  }

  // SSR ChatMessages — discover exact signatures if present
  const ssrCm = allFiles.filter(
    (f) =>
      f.includes("/ssr/") &&
      (() => {
        try {
          return fs.readFileSync(f, "utf8").includes('["ChatMessages"');
        } catch {
          return false;
        }
      })()
  );
  for (const f of ssrCm) {
    let data = fs.readFileSync(f, "utf8");
    // SSR aliases: g=jsx, h=react, i=cn — inject rail if ChatMessages exists with sections:a
    if (
      data.includes('["ChatMessages",0,function({sections:a') &&
      !data.includes("KnonixResourcesRail")
    ) {
      const oldStart =
        '["ChatMessages",0,function({sections:a,status:b,chatId:c,isGuest:d=!1,isCloudDeployment:e=!1,libraryAvailable:f=!0,addToolResult:j,scrollContainerRef:k,onUpdateMessage:l,reload:m,error:n,onQuoteContext:o}){';
      // Try looser match
      const m = data.match(
        /\["ChatMessages",0,function\(\{sections:[a-z],status:[a-z]/
      );
      if (m) {
        // Inject function after opening brace of ChatMessages if not already
        const insertAt = data.indexOf(m[0]);
        if (insertAt >= 0) {
          const brace = data.indexOf("{", insertAt + m[0].length - 1);
          // find first { of function body after params
          const bodyStart = data.indexOf("){", insertAt);
          if (bodyStart > 0 && !data.includes("function KnonixResourcesRail")) {
            data =
              data.slice(0, bodyStart + 2) +
              RAIL_FN_SSR +
              data.slice(bodyStart + 2);
            fs.writeFileSync(f, data);
            console.log(
              `[knonix-entrypoint] resources-rail-fn-ssr: patched ${path.basename(f)}`
            );
            railOk = true;
          }
        }
      }
    }
  }

  if (!railOk) {
    console.log(
      "[knonix-entrypoint] resources-rail: static wrap may need manual verify; partial ok if dots fixed"
    );
  } else {
    console.log("[knonix-entrypoint] resources-rail: applied");
  }
}
NODE
else
  echo "[knonix-entrypoint] WARNING: node not found; cannot apply runtime patches"
fi

exec /app/docker-entrypoint.sh "$@"
