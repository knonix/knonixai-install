#!/usr/bin/env node
/**
 * Knonix central License Service — PLATFORM HOST ONLY (ai.knonix.com).
 *
 * Purpose:
 *   - Receive outbound heartbeats from customer installs (seat / user counts)
 *   - Let Knonix operators see every enrolled install for accurate billing
 *   - Provision license keys and process Stripe webhooks
 *
 * Customers never run this as their product surface. Public installs only
 * *call* /v1/register|/v1/heartbeat|/v1/validate with an enrollment token.
 * They do not receive fleet-admin credentials and must not expose this service.
 *
 * Endpoints:
 *   GET  /healthz                  (public health)
 *   POST /v1/validate|heartbeat|register  (enrollment / service token)
 *   GET  /v1/licenses              (admin bearer only)
 *   GET  /v1/billing-summary       (admin bearer only)
 *   POST /v1/provision             (admin bearer only)
 *   POST /v1/webhook               (Stripe)
 *   GET  /admin/fleet*             (admin only — HTML fleet + billing board)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);
const DATA_DIR = process.env.KNONIX_LICENSE_DATA_DIR || path.join(__dirname, 'data');
const DB_PATH = path.join(DATA_DIR, 'licenses.json');

const ADMIN_TOKEN =
  process.env.KNONIX_LICENSE_ADMIN_TOKEN ||
  process.env.LICENSE_ADMIN_TOKEN ||
  '';
/** Shared enrollment credential customers put in KNONIX_LICENSE_SERVICE_TOKEN */
const SERVICE_TOKEN = process.env.KNONIX_LICENSE_SERVICE_TOKEN || '';
/** Optional extra shared secret for heartbeats (platform-side) */
const HEARTBEAT_SECRET = process.env.KNONIX_HEARTBEAT_SECRET || '';
const STRIPE_SECRET = process.env.STRIPE_SECRET_KEY || '';
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || '';
const SEAT_PRICE_ID = process.env.KNONIX_SEAT_PRICE_ID || '';

fs.mkdirSync(DATA_DIR, { recursive: true });

function loadDb() {
  try {
    return JSON.parse(fs.readFileSync(DB_PATH, 'utf8'));
  } catch {
    return { licenses: [], heartbeats: [], updated_at: null };
  }
}

function saveDb(db) {
  db.updated_at = new Date().toISOString();
  fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

function genKey(account) {
  const slug =
    String(account || 'CUST')
      .toUpperCase()
      .replace(/[^A-Z0-9]/g, '')
      .slice(0, 8) || 'CUST';
  const parts = [
    crypto.randomBytes(2).toString('hex').toUpperCase(),
    crypto.randomBytes(2).toString('hex').toUpperCase(),
    crypto.randomBytes(2).toString('hex').toUpperCase(),
  ];
  return `KNX-${slug}-${parts.join('-')}`;
}

function bearer(req) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : '';
}

function cookieValue(req, name) {
  const raw = req.headers.cookie || '';
  for (const part of raw.split(';')) {
    const [k, ...rest] = part.trim().split('=');
    if (k === name) return decodeURIComponent(rest.join('=') || '');
  }
  return '';
}

function isAdmin(req, url) {
  if (!ADMIN_TOKEN) return false;
  const tok =
    bearer(req) ||
    url.searchParams.get('token') ||
    cookieValue(req, 'knonix_fleet_admin') ||
    '';
  return tok === ADMIN_TOKEN;
}

function requireAdmin(req, res, url) {
  if (!ADMIN_TOKEN) {
    json(res, 503, {
      error: 'admin_not_configured',
      message: 'KNONIX_LICENSE_ADMIN_TOKEN must be set on the platform host',
    });
    return false;
  }
  if (!isAdmin(req, url || new URL(req.url || '/', 'http://local'))) {
    json(res, 401, {
      error: 'unauthorized',
      message: 'Knonix operator admin token required — not available to customers',
    });
    return false;
  }
  return true;
}

/** Customer install heartbeats / register — enrollment or heartbeat secret, never public. */
function requireService(req, res) {
  const tok = bearer(req);
  const accepted = [SERVICE_TOKEN, HEARTBEAT_SECRET].filter(Boolean);
  if (!accepted.length) {
    json(res, 503, {
      error: 'service_not_configured',
      message: 'Set KNONIX_LICENSE_SERVICE_TOKEN on the platform host',
    });
    return false;
  }
  if (!tok || !accepted.includes(tok)) {
    json(res, 401, {
      error: 'unauthorized',
      message: 'enrollment / service token required',
    });
    return false;
  }
  return true;
}

function json(res, code, body) {
  const raw = JSON.stringify(body);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(raw);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const raw = Buffer.concat(chunks);
      if (!raw.length) return resolve({ raw, json: {} });
      try {
        resolve({ raw, json: JSON.parse(raw.toString('utf8')) });
      } catch {
        // form-urlencoded (fleet login)
        const text = raw.toString('utf8');
        const params = new URLSearchParams(text);
        const obj = {};
        for (const [k, v] of params.entries()) obj[k] = v;
        resolve({ raw, json: obj });
      }
    });
    req.on('error', reject);
  });
}

function findLicense(db, key) {
  return db.licenses.find((l) => l.license_key === key);
}

function ensurePlatformLicense(db) {
  const existing = db.licenses.find((l) => l.account === 'knonix-platform' || l.platform_owner);
  if (existing) return existing;
  const lic = {
    license_key: process.env.KNONIX_LICENSE_KEY || genKey('KNONIX'),
    account: 'knonix-platform',
    status: 'active',
    free_seats: 1,
    paid_seats: 9999,
    max_seats: null,
    unlimited: true,
    platform_owner: true,
    active_user_count: 0,
    last_heartbeat_at: null,
    instance_hash: null,
    version: null,
    stripe_customer: null,
    stripe_subscription: null,
    stripe_subscription_item: null,
    created_at: new Date().toISOString(),
  };
  db.licenses.unshift(lic);
  saveDb(db);
  return lic;
}

function customerLicenses(db) {
  return (db.licenses || []).filter((l) => !l.platform_owner && l.account !== 'knonix-platform');
}

/** Billing-oriented rollup for Knonix operators. */
function billingSummary(db) {
  const customers = customerLicenses(db);
  let totalActiveUsers = 0;
  let totalFreeSeats = 0;
  let totalPaidSeats = 0;
  let billableUsers = 0;
  let online24h = 0;
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;

  for (const l of customers) {
    const users = Number(l.active_user_count || 0);
    const free = Number(l.free_seats || 0);
    const paid = Number(l.paid_seats || 0);
    totalActiveUsers += users;
    totalFreeSeats += free;
    totalPaidSeats += paid;
    // Users beyond free tier are billable (even if paid_seats not yet purchased)
    billableUsers += Math.max(0, users - free);
    if (l.last_heartbeat_at && Date.parse(l.last_heartbeat_at) >= cutoff) online24h += 1;
  }

  return {
    total_installs: customers.length,
    installs_heartbeat_24h: online24h,
    total_active_users: totalActiveUsers,
    total_free_seats_granted: totalFreeSeats,
    total_paid_seats_granted: totalPaidSeats,
    billable_users_over_free: billableUsers,
    seat_price_id: SEAT_PRICE_ID || null,
    updated_at: db.updated_at,
  };
}

function fleetLoginHtml(error) {
  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Knonix Fleet — Operator Login</title>
<style>
  :root { font-family: ui-sans-serif, system-ui, sans-serif; color: #e8eaed; background: #0f1419; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 1.5rem; }
  form { background: #1a1f26; border-radius: 12px; padding: 1.5rem; width: min(400px, 100%); }
  h1 { font-size: 1.15rem; margin: 0 0 .5rem; }
  p { color: #9aa0a6; font-size: .9rem; margin: 0 0 1rem; }
  input { width: 100%; box-sizing: border-box; padding: .65rem .75rem; border-radius: 8px;
    border: 1px solid #2a313c; background: #0f1419; color: #e8eaed; margin-bottom: .75rem; }
  button { width: 100%; padding: .65rem; border: 0; border-radius: 8px; background: #8ab4f8;
    color: #0f1419; font-weight: 600; cursor: pointer; }
  .err { color: #f28b82; margin-bottom: .75rem; font-size: .85rem; }
</style></head><body>
<form method="POST" action="/admin/fleet/login">
  <h1>Knonix operator only</h1>
  <p>Fleet and billing data are not available to customers. Enter the platform admin token.</p>
  ${error ? `<div class="err">${esc(error)}</div>` : ''}
  <input type="password" name="token" placeholder="KNONIX_LICENSE_ADMIN_TOKEN" autocomplete="current-password" required/>
  <button type="submit">Open fleet board</button>
</form>
</body></html>`;
}

function fleetHtml(db) {
  const summary = billingSummary(db);
  const rows = customerLicenses(db)
    .map((l) => {
      const free = Number(l.free_seats || 0);
      const users = Number(l.active_user_count || 0);
      const billable = Math.max(0, users - free);
      return `<tr>
      <td><code>${esc(l.license_key)}</code></td>
      <td>${esc(l.account)}</td>
      <td>${esc(l.status)}</td>
      <td>${l.unlimited ? '∞' : free + Number(l.paid_seats || 0)}</td>
      <td><strong>${users}</strong></td>
      <td>${billable}</td>
      <td>${esc(l.last_heartbeat_at || '—')}</td>
      <td>${esc(l.version || '—')}</td>
    </tr>`;
    })
    .join('\n');

  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Knonix Fleet & Billing</title>
<style>
  :root { font-family: ui-sans-serif, system-ui, sans-serif; color: #e8eaed; background: #0f1419; }
  body { margin: 0; padding: 2rem; }
  h1 { font-size: 1.4rem; margin: 0 0 .25rem; }
  .sub { color: #9aa0a6; margin-bottom: 1.25rem; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: .75rem; margin-bottom: 1.5rem; }
  .card { background: #1a1f26; border-radius: 12px; padding: 1rem; }
  .card .n { font-size: 1.6rem; font-weight: 700; }
  .card .l { color: #9aa0a6; font-size: .75rem; margin-top: .25rem; }
  table { width: 100%; border-collapse: collapse; background: #1a1f26; border-radius: 12px; overflow: hidden; }
  th, td { text-align: left; padding: .75rem 1rem; border-bottom: 1px solid #2a313c; font-size: .9rem; }
  th { color: #9aa0a6; font-weight: 600; background: #151a21; }
  code { font-size: .8rem; }
  .ok { color: #81c995; }
  .badge { display:inline-block; padding:.15rem .5rem; border-radius:999px; background:#243044; font-size:.75rem; }
  a { color: #8ab4f8; }
  .warn { color: #fdd663; font-size: .85rem; margin-top: 1rem; }
</style></head><body>
  <h1>Knonix Fleet &amp; Billing</h1>
  <p class="sub">Operator console · <span class="ok">online</span> ·
    <span class="badge">${summary.total_installs} customer installs</span>
    · customers never see this page
  </p>
  <div class="cards">
    <div class="card"><div class="n">${summary.total_installs}</div><div class="l">Installs enrolled</div></div>
    <div class="card"><div class="n">${summary.installs_heartbeat_24h}</div><div class="l">Heartbeats (24h)</div></div>
    <div class="card"><div class="n">${summary.total_active_users}</div><div class="l">Active users (all)</div></div>
    <div class="card"><div class="n">${summary.billable_users_over_free}</div><div class="l">Billable over free seats</div></div>
    <div class="card"><div class="n">${summary.total_paid_seats_granted}</div><div class="l">Paid seats granted</div></div>
  </div>
  <table>
    <thead><tr>
      <th>License key</th><th>Account</th><th>Status</th><th>Seats allowed</th>
      <th>Active users</th><th>Billable</th><th>Last heartbeat</th><th>Version</th>
    </tr></thead>
    <tbody>${rows || '<tr><td colspan="8">No customer installs yet — provision a key or wait for connected heartbeats.</td></tr>'}
    </tbody>
  </table>
  <p class="warn">Active users come from each install’s privacy-preserving daily heartbeat (opaque install id + seat count — no chat content, no end-user PII).</p>
  <p class="sub" style="margin-top:1rem">
    API: <code>GET /v1/billing-summary</code> · <code>GET /v1/licenses</code> (admin bearer) ·
    App: <a href="/admin">/admin</a>
  </p>
</body></html>`;
}

function esc(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  const method = req.method || 'GET';
  const p = url.pathname;

  try {
    if (method === 'GET' && (p === '/healthz' || p === '/v1/healthz')) {
      return json(res, 200, {
        ok: true,
        service: 'knonix-license-service',
        role: 'platform-only',
        ts: new Date().toISOString(),
      });
    }

    // Operator login → cookie (never for customers)
    if (method === 'POST' && p === '/admin/fleet/login') {
      if (!ADMIN_TOKEN) {
        res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8' });
        return res.end(fleetLoginHtml('Admin token not configured on this host.'));
      }
      const { json: body } = await readBody(req);
      const tok = String(body.token || '').trim();
      if (tok !== ADMIN_TOKEN) {
        res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        return res.end(fleetLoginHtml('Invalid admin token.'));
      }
      res.writeHead(302, {
        Location: '/admin/fleet',
        'Set-Cookie': `knonix_fleet_admin=${encodeURIComponent(tok)}; Path=/admin/fleet; HttpOnly; Secure; SameSite=Strict; Max-Age=86400`,
        'Cache-Control': 'no-store',
      });
      return res.end();
    }

    if (method === 'GET' && (p === '/admin/fleet' || p === '/admin/fleet/' || p.startsWith('/admin/fleet/'))) {
      if (!ADMIN_TOKEN) {
        res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        return res.end(fleetLoginHtml('Set KNONIX_LICENSE_ADMIN_TOKEN on the platform host.'));
      }
      if (!isAdmin(req, url)) {
        res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
        return res.end(fleetLoginHtml());
      }
      const db = loadDb();
      ensurePlatformLicense(db);
      const html = fleetHtml(loadDb());
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(html);
    }

    if (method === 'GET' && p === '/v1/licenses') {
      if (!requireAdmin(req, res, url)) return;
      const db = loadDb();
      ensurePlatformLicense(db);
      const fresh = loadDb();
      return json(res, 200, {
        total_licenses: fresh.licenses.length,
        customer_installs: customerLicenses(fresh).length,
        billing: billingSummary(fresh),
        licenses: fresh.licenses,
        updated_at: fresh.updated_at,
      });
    }

    if (method === 'GET' && p === '/v1/billing-summary') {
      if (!requireAdmin(req, res, url)) return;
      const db = loadDb();
      ensurePlatformLicense(db);
      return json(res, 200, { ok: true, ...billingSummary(loadDb()) });
    }

    if (method === 'POST' && (p === '/v1/validate' || p === '/v1/heartbeat' || p === '/v1/register')) {
      if (!requireService(req, res)) return;
      const { json: body } = await readBody(req);
      const db = loadDb();
      ensurePlatformLicense(db);
      const db2 = loadDb();

      const key = body.license_key || body.licenseKey || '';
      let lic = key ? findLicense(db2, key) : null;

      if (p === '/v1/register' || (!lic && body.account)) {
        if (!lic) {
          lic = {
            license_key: key || genKey(body.account || 'AUTO'),
            account: body.account || body.install_name || 'auto-registered',
            status: body.status || 'active',
            free_seats: Number(body.free_seats ?? 1),
            paid_seats: Number(body.paid_seats ?? 0),
            unlimited: !!body.unlimited,
            platform_owner: false,
            active_user_count: Number(body.active_user_count ?? body.seats ?? 0),
            last_heartbeat_at: new Date().toISOString(),
            instance_hash: body.instance_hash || body.instanceHash || null,
            version: body.version || null,
            stripe_customer: body.stripe_customer || null,
            stripe_subscription: body.stripe_subscription || null,
            stripe_subscription_item: body.stripe_subscription_item || null,
            created_at: new Date().toISOString(),
          };
          db2.licenses.push(lic);
        }
      }

      if (!lic && key) {
        // Unknown key — accept heartbeat so new connected installs appear for billing
        lic = {
          license_key: key,
          account: body.account || 'unknown',
          status: 'active',
          free_seats: Number(body.free_seats ?? 1),
          paid_seats: 0,
          unlimited: false,
          platform_owner: false,
          active_user_count: Number(body.active_user_count ?? body.seats ?? 0),
          last_heartbeat_at: new Date().toISOString(),
          instance_hash: body.instance_hash || null,
          version: body.version || null,
          created_at: new Date().toISOString(),
        };
        db2.licenses.push(lic);
      }

      if (!lic) {
        return json(res, 400, { valid: false, error: 'license_key required' });
      }

      // Never allow customers to promote themselves to platform owner via heartbeat body
      lic.platform_owner = !!lic.platform_owner && lic.account === 'knonix-platform';
      lic.active_user_count = Number(body.active_user_count ?? body.seats ?? lic.active_user_count ?? 0);
      lic.last_heartbeat_at = new Date().toISOString();
      if (body.instance_hash || body.instanceHash) lic.instance_hash = body.instance_hash || body.instanceHash;
      if (body.version) lic.version = body.version;
      if (body.status && !['unlimited', 'platform'].includes(String(body.status))) {
        lic.status = body.status;
      }

      db2.heartbeats.push({
        at: lic.last_heartbeat_at,
        license_key: lic.license_key,
        active_user_count: lic.active_user_count,
        instance_hash: lic.instance_hash,
        version: lic.version,
      });
      if (db2.heartbeats.length > 5000) db2.heartbeats = db2.heartbeats.slice(-2500);
      saveDb(db2);

      const maxSeats = lic.unlimited ? null : (lic.free_seats || 0) + (lic.paid_seats || 0);
      const valid =
        lic.status === 'active' ||
        lic.status === 'paid' ||
        lic.status === 'free' ||
        lic.unlimited ||
        lic.platform_owner;

      // Customer-facing response: their own entitlement only — no fleet list
      return json(res, 200, {
        ok: true,
        valid: !!valid,
        license_key: lic.license_key,
        status: lic.status,
        unlimited: !!lic.unlimited || !!lic.platform_owner,
        free_seats: lic.free_seats,
        paid_seats: lic.paid_seats || 0,
        max_seats: maxSeats,
        active_user_count: lic.active_user_count,
        seats_allowed: lic.unlimited || lic.platform_owner ? 9999 : maxSeats,
      });
    }

    if (method === 'POST' && p === '/v1/provision') {
      if (!requireAdmin(req, res, url)) return;
      const { json: body } = await readBody(req);
      const account = body.account;
      if (!account) return json(res, 400, { error: 'account required' });
      const db = loadDb();
      const lic = {
        license_key: genKey(account),
        account,
        status: body.status || 'free',
        free_seats: Number(body.free_seats ?? body.freeSeats ?? 1),
        paid_seats: Number(body.paid_seats ?? 0),
        unlimited: !!body.unlimited,
        platform_owner: false,
        active_user_count: 0,
        last_heartbeat_at: null,
        instance_hash: null,
        version: null,
        stripe_customer: body.stripe_customer || body.stripeCustomer || null,
        stripe_subscription: body.stripe_subscription || body.stripeSubscription || null,
        stripe_subscription_item: body.stripe_subscription_item || null,
        created_at: new Date().toISOString(),
      };
      db.licenses.push(lic);
      saveDb(db);
      return json(res, 200, {
        ok: true,
        license_key: lic.license_key,
        KNONIX_LICENSE_KEY: lic.license_key,
        account: lic.account,
        status: lic.status,
        free_seats: lic.free_seats,
        paid_seats: lic.paid_seats,
      });
    }

    if (method === 'POST' && p === '/v1/webhook') {
      const { raw, json: body } = await readBody(req);
      if (STRIPE_WEBHOOK_SECRET) {
        const sig = req.headers['stripe-signature'] || '';
        if (!sig) {
          return json(res, 400, { error: 'missing stripe-signature' });
        }
      }
      const db = loadDb();
      const type = body.type || 'unknown';
      const obj = body.data?.object || {};
      if (type.startsWith('customer.subscription.') || type === 'invoice.payment_failed') {
        const subId = obj.id || obj.subscription;
        const cust = obj.customer;
        const status = obj.status;
        for (const lic of db.licenses) {
          if (
            (subId && lic.stripe_subscription === subId) ||
            (cust && lic.stripe_customer === cust)
          ) {
            if (status === 'active' || status === 'trialing') lic.status = 'active';
            else if (status === 'past_due') lic.status = 'past_due';
            else if (status === 'canceled' || status === 'unpaid') lic.status = 'canceled';
            if (type === 'invoice.payment_failed') lic.status = 'past_due';
            // Map quantity → paid seats when present (Stripe subscription item qty)
            const qty = obj.items?.data?.[0]?.quantity;
            if (typeof qty === 'number' && qty >= 0) {
              lic.paid_seats = Math.max(0, qty);
            }
            lic.stripe_subscription = lic.stripe_subscription || subId || null;
            lic.stripe_customer = lic.stripe_customer || cust || null;
          }
        }
        saveDb(db);
      }
      return json(res, 200, { received: true, type, bytes: raw.length });
    }

    json(res, 404, { error: 'not_found', path: p });
  } catch (err) {
    console.error(err);
    json(res, 500, { error: 'internal_error', message: String(err?.message || err) });
  }
});

{
  const db = loadDb();
  ensurePlatformLicense(db);
}

// Bind all interfaces inside Docker network; host port should be 127.0.0.1 only.
server.listen(PORT, '0.0.0.0', () => {
  console.log(`[license-service] listening on :${PORT} (platform-only)`);
  console.log(`[license-service] data: ${DB_PATH}`);
  console.log(`[license-service] admin token set: ${Boolean(ADMIN_TOKEN)}`);
  console.log(`[license-service] service/enrollment token set: ${Boolean(SERVICE_TOKEN)}`);
  console.log(`[license-service] stripe configured: ${Boolean(STRIPE_SECRET)}`);
});
