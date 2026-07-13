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
  if (data.includes(newStr)) {
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
NODE
else
  echo "[knonix-entrypoint] WARNING: node not found; cannot apply runtime patches"
fi

exec /app/docker-entrypoint.sh "$@"
