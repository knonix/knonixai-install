#!/usr/bin/env node
/**
 * Patch minified Next health route so authConfigured reads runtime env.
 * Safe no-op if already patched or expression changed in a fixed source build.
 */
const fs = require('fs')
const path = require('path')

const OLD = 'authConfigured:!n||!!"".trim()&&!!"".trim()'
const NEW =
  'authConfigured:!n||!!(process.env.NEXT_PUBLIC_SUPABASE_URL||"").trim()' +
  '&&!!(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||"").trim()'

function walk(dir, out = []) {
  let entries
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
  } catch {
    return out
  }
  for (const e of entries) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if (e.isFile() && e.name.endsWith('.js')) out.push(p)
  }
  return out
}

let patched = 0
let already = 0
const root = '/app/.next/server'
for (const file of walk(root)) {
  let data
  try {
    data = fs.readFileSync(file, 'utf8')
  } catch {
    continue
  }
  if (data.includes(NEW)) {
    already++
    continue
  }
  if (!data.includes(OLD)) continue
  fs.writeFileSync(file, data.split(OLD).join(NEW))
  console.log('patched', file)
  patched++
}

if (patched === 0 && already === 0) {
  console.log(
    'note: health auth pattern not found (image may already use runtime env)'
  )
} else {
  console.log(`done: patched=${patched} already=${already}`)
}

// Also patch getTextFromParts so data-sourceUrl chips trigger server URL prefetch
const URL_OLD = 'function d(e){return e?.filter(e=>"text"===e.type).map(e=>e.text).join(" ")??""}'
const URL_NEW =
  'function d(e){if(!e||!e.length)return"";let t=[];for(let r of e){if("text"===r.type&&"string"==typeof r.text&&r.text)t.push(r.text);else if("data-sourceUrl"===r.type&&r.data&&"string"==typeof r.data.url&&r.data.url)t.push(r.data.url);else if("data-pastedContent"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push(r.data.text);else if("data-quotedContext"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push(r.data.text);else if("data-noteContext"===r.type&&r.data&&"string"==typeof r.data.text&&r.data.text)t.push((r.data.title?String(r.data.title)+": ":"")+r.data.text)}return t.join(" ")}'

let urlPatched = 0
for (const file of walk(root)) {
  let data
  try {
    data = fs.readFileSync(file, 'utf8')
  } catch {
    continue
  }
  if (data.includes('data-sourceUrl') && data.includes('getTextFromParts')) {
    // already may be patched
  }
  if (!data.includes(URL_OLD)) continue
  fs.writeFileSync(file, data.split(URL_OLD).join(URL_NEW))
  console.log('url-prefetch patched', file)
  urlPatched++
}
console.log(`url-prefetch patched=${urlPatched}`)
