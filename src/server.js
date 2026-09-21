'use strict';
/**
 * Scorp backend
 *
 *   POST /api/session          loader handshake → token + freshly built payload + UI library
 *   POST /api/heartbeat        loader check-in (anti-tamper flags, revocation)
 *   POST /api/nametags/sync    register presence + get the other Scorp users in your Roblox server
 *   POST /api/nametags/leave
 *   GET  /loader.lua           the (obfuscated) loader, with this server's URL baked in
 *   GET  /api/health           build id, webhook status — no secrets
 *   /api/admin/*               roles, custom nametag designs, bans, sessions, webhook test (X-Admin-Key header)
 *
 * All secrets come from environment variables (see .env.example). Nothing
 * secret lives in this file, so it is safe to commit.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, '..');

// ────────────────────────────────────────────────────────────────────────────
// .env support (tiny, no dependency). Real environment variables always win.
// ────────────────────────────────────────────────────────────────────────────
(function loadDotEnv() {
    const file = path.join(ROOT, '.env');
    if (!fs.existsSync(file)) return;
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
        const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
        if (!m || line.trim().startsWith('#')) continue;
        let v = m[2];
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
        if (process.env[m[1]] === undefined) process.env[m[1]] = v;
    }
})();

const express = require('express');
const obf = require('../obfuscate');
const tagconfig = require('./tagconfig');

// ────────────────────────────────────────────────────────────────────────────
// CONFIG
// ────────────────────────────────────────────────────────────────────────────
const env = process.env;
const num = (v, d) => (v !== undefined && v !== '' && Number.isFinite(Number(v)) ? Number(v) : d);
const flag = (v, d) => (v === undefined || v === '' ? d : !/^(0|false|no|off)$/i.test(v));

const CONFIG = {
    PORT: num(env.PORT, 3000),
    PUBLIC_URL: (env.PUBLIC_URL || '').replace(/\/+$/, ''),
    DISCORD_WEBHOOK: (env.DISCORD_WEBHOOK || '').trim(),
    WEBHOOK_STARTUP_PING: flag(env.WEBHOOK_STARTUP_PING, true),
    OWNER_USER_ID: String(env.OWNER_USER_ID || '').trim(),
    OWNER_KEY: env.OWNER_KEY || '',
    ADMIN_PASSWORD: env.ADMIN_PASSWORD || '',
    DISCORD_TOKEN: (env.DISCORD_TOKEN || '').trim(),
    DISCORD_CLIENT_ID: (env.DISCORD_CLIENT_ID || '').trim(),
    DISCORD_GUILD_ID: (env.DISCORD_GUILD_ID || '').trim(), // optional: instant slash-command sync to one server
    STAFF_DISCORD_IDS: (env.STAFF_DISCORD_IDS || '').split(',').map(s => s.trim()).filter(Boolean),
    DATA_DIR: env.DATA_DIR ? path.resolve(env.DATA_DIR) : path.join(ROOT, 'data'),
    SESSION_SECRET: env.SESSION_SECRET || '',
    TRUST_PROXY_HOPS: num(env.TRUST_PROXY_HOPS, 1), // Railway = 1 proxy hop. NEVER use `true`: clients could forge X-Forwarded-For.

    HEARTBEAT_SECONDS: num(env.HEARTBEAT_SECONDS, 30),
    TOKEN_TTL_MS: num(env.TOKEN_TTL_HOURS, 12) * 3600 * 1000,
    SESSION_COOLDOWN_MS: num(env.SESSION_COOLDOWN_MS, 5000),
    UNCONFIRMED_AFTER_MS: num(env.UNCONFIRMED_AFTER_SECONDS, 75) * 1000,
    PRESENCE_TTL_MS: 45 * 1000,
    WATCHER_INTERVAL_MS: num(env.WATCHER_INTERVAL_MS, 30 * 1000),

    AUTO_BAN: flag(env.AUTO_BAN, true),
    AUTO_BAN_THRESHOLD: num(env.AUTO_BAN_THRESHOLD, 2), // separate sessions with a strong flag before a ban
    BAN_SCORE: num(env.BAN_SCORE, 5),                   // …or one session this bad → immediate ban
    STRIKE_SCORE: num(env.STRIKE_SCORE, 2),             // a session needs at least this score to count as a strike
    SUSPICIOUS_IDENTITY_COUNT: 3,
    SUSPICIOUS_WINDOW_MS: 60 * 60 * 1000,
};

const DAY = 24 * 60 * 60 * 1000;
const BAN_TIERS = [1 * DAY, 7 * DAY, 30 * DAY, null]; // 1st, 2nd, 3rd offense, then permanent
const TIER_LABEL = { [1 * DAY]: '1 day', [7 * DAY]: '7 days', [30 * DAY]: '30 days' };

const ROLES = ['owner', 'developer', 'admin', 'moderator', 'support', 'vip', 'member'];
const DEFAULT_LABEL = { owner: 'Owner', developer: 'Developer', admin: 'Admin', moderator: 'Moderator', support: 'Support', vip: 'VIP', member: 'Member' };

// Server-side weights. The client's own "score" is never trusted, only its codes.
const CODE_INFO = {
    C1: [2, 'core Lua function replaced by a Lua closure (pcall/error/tostring/…)'],
    H1: [1, 'request function is a Lua wrapper, not native'],
    H2: [3, 'request/loadstring reference swapped after the loader started'],
    H3: [1, 'game.HttpGet is a Lua wrapper'],
    M1: [1, 'game __namecall/__index hooked with a Lua closure'],
    G1: [2, 'HTTP-spy style GUI found in CoreGui/gethui'],
    G2: [2, 'known spy global present in the environment'],
};

fs.mkdirSync(CONFIG.DATA_DIR, { recursive: true });
const OFFENSES_FILE = path.join(CONFIG.DATA_DIR, 'offenses.json');
const ROLES_FILE = path.join(CONFIG.DATA_DIR, 'roles.json');
const TAGS_FILE = path.join(CONFIG.DATA_DIR, 'tags.json');
const SECRET_FILE = path.join(CONFIG.DATA_DIR, 'session.key');
const LIB_FILE = path.join(ROOT, 'src', 'ScorpLib.lua');
const LOADER_FILE = path.join(ROOT, 'loader.lua');

// Secrets that were not provided
if (!CONFIG.ADMIN_PASSWORD) {
    CONFIG.ADMIN_PASSWORD = crypto.randomBytes(18).toString('base64url');
    console.warn(`[config] ADMIN_PASSWORD is not set. Temporary one for this run: ${CONFIG.ADMIN_PASSWORD}`);
    console.warn('[config] Set ADMIN_PASSWORD in your environment variables to keep it stable.');
}
if (!CONFIG.OWNER_KEY) console.warn('[config] OWNER_KEY is not set: nobody is exempt from anti-tamper bans (including you).');
if (!CONFIG.OWNER_USER_ID) console.warn('[config] OWNER_USER_ID is not set: nobody gets the default Owner nametag.');
if (!CONFIG.DISCORD_WEBHOOK) console.warn('[config] DISCORD_WEBHOOK is not set: alerts will only be printed to this console.');

// Persisted signing secret so tokens survive restarts
function loadSecret() {
    if (CONFIG.SESSION_SECRET) return CONFIG.SESSION_SECRET;
    try { return fs.readFileSync(SECRET_FILE, 'utf8').trim(); } catch { /* generate below */ }
    const s = crypto.randomBytes(32).toString('hex');
    try { fs.writeFileSync(SECRET_FILE, s, { mode: 0o600 }); } catch (e) { console.warn('[config] could not persist session.key:', e.message); }
    return s;
}
const SECRET = loadSecret();

// ────────────────────────────────────────────────────────────────────────────
// Small helpers
// ────────────────────────────────────────────────────────────────────────────
const sleep = ms => new Promise(r => setTimeout(r, ms));
const now = () => Date.now();
const log = (...a) => console.log(new Date().toISOString(), ...a);

function safeEqual(a, b) {
    const ha = crypto.createHash('sha256').update(String(a)).digest();
    const hb = crypto.createHash('sha256').update(String(b)).digest();
    return crypto.timingSafeEqual(ha, hb);
}

function writeJsonAtomic(file, obj) {
    const tmp = `${file}.${process.pid}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2));
    fs.renameSync(tmp, file);
}
function readJson(file, fallback) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function clientIp(req) {
    let ip = req.ip || '';
    if (ip.startsWith('::ffff:')) ip = ip.slice(7);
    return ip;
}
const cleanStr = (v, max) => String(v ?? '').replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, max);
const isDigits = v => typeof v === 'string' && /^\d{1,20}$/.test(v);

function b64u(buf) { return Buffer.from(buf).toString('base64url'); }
function sign(data) { return crypto.createHmac('sha256', SECRET).update(data).digest('base64url'); }

function signToken(payload) {
    const body = b64u(JSON.stringify(payload));
    return `${body}.${sign(body)}`;
}
function verifyToken(token) {
    if (typeof token !== 'string') return null;
    const [body, sig] = token.split('.');
    if (!body || !sig) return null;
    const expected = sign(body);
    if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
    try {
        const p = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
        if (!p || p.exp < now()) return null;
        return p;
    } catch { return null; }
}

const ownerKeyOk = k => !!CONFIG.OWNER_KEY && typeof k === 'string' && k.length > 0 && safeEqual(k, CONFIG.OWNER_KEY);

// ────────────────────────────────────────────────────────────────────────────
// Discord webhook — queued, rate-limit aware, and it tells you when it fails
// ────────────────────────────────────────────────────────────────────────────
const webhook = { sent: 0, failed: 0, lastError: null, lastOkAt: null };
const webhookQueue = [];
let webhookDraining = false;

function clip(s, n) { s = String(s ?? ''); return s.length > n ? s.slice(0, n - 1) + '…' : s; }

function makeEmbed({ title, description, color, fields = [] }) {
    return {
        embeds: [{
            title: clip(title, 250),
            description: description ? clip(description, 2000) : undefined,
            color,
            fields: fields.slice(0, 20).map(f => ({ name: clip(f.name, 250), value: clip(f.value || '—', 1000), inline: !!f.inline })),
            timestamp: new Date().toISOString(),
            footer: { text: 'Scorp anti-tamper' },
        }],
    };
}

async function postWebhook(body, attempt = 0) {
    try {
        const res = await fetch(CONFIG.DISCORD_WEBHOOK, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(10000),
        });
        if (res.status === 429 && attempt < 3) {
            const j = await res.json().catch(() => ({}));
            await sleep((Number(j.retry_after) || 1) * 1000 + 250);
            return postWebhook(body, attempt + 1);
        }
        if (!res.ok) {
            const text = await res.text().catch(() => '');
            webhook.failed++;
            webhook.lastError = `HTTP ${res.status}: ${clip(text, 160)}`;
            console.error(`[webhook] Discord replied ${webhook.lastError}`);
            return false;
        }
        webhook.sent++;
        webhook.lastOkAt = new Date().toISOString();
        return true;
    } catch (e) {
        webhook.failed++;
        webhook.lastError = e.message;
        console.error('[webhook] request failed:', e.message);
        return false;
    }
}

async function drainWebhooks() {
    if (webhookDraining) return;
    webhookDraining = true;
    try {
        while (webhookQueue.length) {
            await postWebhook(webhookQueue.shift());
            await sleep(1100); // stay far below Discord's per-webhook rate limit
        }
    } finally { webhookDraining = false; }
}

function alert(embedSpec) {
    const body = makeEmbed(embedSpec);
    log(`[alert] ${embedSpec.title}${embedSpec.fields ? ' | ' + embedSpec.fields.map(f => `${f.name}=${f.value}`).join(' ') : ''}`);
    if (!CONFIG.DISCORD_WEBHOOK) return;
    if (webhookQueue.length > 50) webhookQueue.shift(); // never let a flood grow memory
    webhookQueue.push(body);
    drainWebhooks();
}

async function checkWebhookAtStartup() {
    if (!CONFIG.DISCORD_WEBHOOK) return;
    if (!/^https?:\/\//i.test(CONFIG.DISCORD_WEBHOOK)) {
        console.error('[webhook] DISCORD_WEBHOOK is not a URL. It should look like https://discord.com/api/webhooks/<id>/<token>');
        webhook.lastError = 'not a URL';
        return;
    }
    if (!/discord(app)?\.com\/api\/webhooks\//i.test(CONFIG.DISCORD_WEBHOOK)) {
        console.warn('[webhook] that URL does not look like a Discord webhook — continuing anyway.');
    }
    try {
        const res = await fetch(CONFIG.DISCORD_WEBHOOK, { signal: AbortSignal.timeout(8000) });
        if (!res.ok) {
            webhook.lastError = `startup check: HTTP ${res.status} (webhook deleted, or URL/token wrong?)`;
            console.error(`[webhook] ${webhook.lastError}`);
            return;
        }
        const info = await res.json().catch(() => ({}));
        log(`[webhook] OK${info.name ? ` (name: ${info.name})` : ''}`);
    } catch (e) {
        webhook.lastError = `startup check failed: ${e.message}`;
        console.error(`[webhook] ${webhook.lastError}`);
        return;
    }
    if (CONFIG.WEBHOOK_STARTUP_PING) {
        const b = getBuild();
        alert({
            title: '✅ Scorp server online',
            color: 0x2ecc71,
            fields: [
                { name: 'Payload build', value: `\`${b ? b.id : 'none'}\``, inline: true },
                { name: 'Auto-ban', value: CONFIG.AUTO_BAN ? 'on' : 'off (alerts only)', inline: true },
                { name: 'Owner key', value: CONFIG.OWNER_KEY ? 'set' : 'NOT SET', inline: true },
            ],
        });
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Build / payload cache — rebuilds by itself when a source file changes
// ────────────────────────────────────────────────────────────────────────────
let buildError = null;
let lastStaleCheck = 0;

function getBuild() { return obf.getBuild(); }

function ensureBuilt(force = false) {
    const t = now();
    if (!force && getBuild() && t - lastStaleCheck < 1500) return getBuild();
    lastStaleCheck = t;
    try {
        if (force || obf.needsRebuild()) {
            const b = obf.build();
            buildError = null;
            log(`[build] payload rebuilt  id=${b.id}  ${(b.bytes / 1024).toFixed(1)} KB  from ${b.sources.join(', ')}`);
        }
    } catch (e) {
        buildError = e.message;
        console.error('[build] FAILED — still serving the previous build:', e.message);
        if (!getBuild() && fs.existsSync(obf.OUT_FILE)) {
            // last resort: a build left on disk by `npm run build`
            const code = fs.readFileSync(obf.OUT_FILE, 'utf8');
            return { id: 'disk', code, builtAt: null, bytes: code.length };
        }
    }
    return getBuild();
}

let libCache = { mtime: 0, text: '' };
function getLib() {
    const m = fs.statSync(LIB_FILE).mtimeMs;
    if (m !== libCache.mtime) libCache = { mtime: m, text: fs.readFileSync(LIB_FILE, 'utf8') };
    return libCache.text;
}

const loaderCache = new Map(); // baseUrl -> { mtime, code }
function getLoader(baseUrl) {
    const m = fs.statSync(LOADER_FILE).mtimeMs;
    const hit = loaderCache.get(baseUrl);
    if (hit && hit.mtime === m) return hit.code;
    const src = fs.readFileSync(LOADER_FILE, 'utf8').replace(/\r\n/g, '\n').split('__SERVER_URL__').join(baseUrl);
    let code;
    try { code = obf.obfuscateSource(src, 'loader.lua'); }
    catch (e) { console.error('[build] loader obfuscation failed, serving it as-is:', e.message); code = src; }
    loaderCache.set(baseUrl, { mtime: m, code });
    return code;
}

// ────────────────────────────────────────────────────────────────────────────
// Identity linking (union-find over userId / hwid / ip) and offenses
// ────────────────────────────────────────────────────────────────────────────
let parent = {};
let groups = {};
{
    const saved = readJson(OFFENSES_FILE, null);
    if (saved) { parent = saved.parent || {}; groups = saved.groups || {}; }
    else writeJsonAtomic(OFFENSES_FILE, { parent, groups });
}
const saveOffenses = () => writeJsonAtomic(OFFENSES_FILE, { parent, groups });

function find(id) {
    if (!(id in parent)) parent[id] = id;
    if (parent[id] !== id) parent[id] = find(parent[id]);
    return parent[id];
}
function union(a, b) {
    const ra = find(a), rb = find(b);
    if (ra === rb) return ra;
    const ga = groups[ra], gb = groups[rb];
    parent[rb] = ra;
    if (ga || gb) {
        const permanent = !!(ga?.permanent || gb?.permanent);
        groups[ra] = {
            offenseCount: Math.max(ga?.offenseCount || 0, gb?.offenseCount || 0),
            permanent,
            bannedUntil: permanent ? null : Math.max(ga?.bannedUntil || 0, gb?.bannedUntil || 0) || null,
            reasons: [...(ga?.reasons || []), ...(gb?.reasons || [])].slice(-30),
        };
        delete groups[rb];
    }
    return ra;
}
// Only userId <-> HWID are unioned into the same "person": that's a real evasion
// signal (same account with a new HWID, or the same HWID on a new account).
// IP is deliberately NEVER unioned here — many unrelated people share an IP
// (school/dorm wifi, campus NAT, mobile carriers), and merging by IP would let
// one banned troll's offense count sweep in everyone else on that network the
// next time any of them connects. IP correlation is still tracked, just as a
// separate (non-punitive) signal — see trackIpCorrelation / /api/admin/suspicious.
function linkIdentity(userId, hwid) {
    const ids = [];
    if (userId) ids.push(`uid:${userId}`);
    if (hwid && hwid !== 'UNKNOWN_HWID') ids.push(`hwid:${hwid}`);
    if (!ids.length) return null;
    let root = find(ids[0]);
    for (let i = 1; i < ids.length; i++) root = union(root, ids[i]);
    return root;
}
function isGroupBanned(root) {
    const g = root && groups[root];
    if (!g) return false;
    return !!g.permanent || !!(g.bannedUntil && g.bannedUntil > now());
}
function banInfo(root) {
    const g = groups[root];
    if (!g) return null;
    return { offenseCount: g.offenseCount, permanent: !!g.permanent, bannedUntil: g.permanent ? null : g.bannedUntil, active: isGroupBanned(root), reasons: g.reasons.slice(-10) };
}

// ────────────────────────────────────────────────────────────────────────────
// Sessions, presence, roles
// ────────────────────────────────────────────────────────────────────────────
const issued = new Map();    // nonce -> { userId, username, hwid, ip, issuedAt, confirmed, alerted, ownerOk }
const presence = new Map();  // userId -> { userId, username, displayName, jobId, placeId, lastSeen }
const lastIssue = new Map(); // identity -> ts (cooldown)
const strikes = new Map();   // root -> Set(nonce)
const alertSeen = new Map(); // throttle key -> ts
const ipIdentities = new Map();
const suspiciousIps = new Map();

let roles = readJson(ROLES_FILE, {});
const saveRoles = () => writeJsonAtomic(ROLES_FILE, roles);

function roleFor(userId) {
    const r = roles[userId];
    if (r) return { role: r.role, label: r.label || DEFAULT_LABEL[r.role] };
    if (CONFIG.OWNER_USER_ID && String(userId) === CONFIG.OWNER_USER_ID) return { role: 'owner', label: DEFAULT_LABEL.owner };
    return { role: 'member', label: DEFAULT_LABEL.member };
}

// ── Custom tag designs (colours, fonts, effects …) ─────────────────────────
// data/tags.json:  { "<userId>": { overrides: { …only what was changed… }, updatedAt } }
// Options, validation, defaults and role presets all live in src/tagconfig.js.
let tags = {};
for (const [id, v] of Object.entries(readJson(TAGS_FILE, {}))) {
    const overrides = tagconfig.sanitizeOverrides(v && v.overrides);
    if (isDigits(id) && Object.keys(overrides).length) tags[id] = { overrides, updatedAt: (v && v.updatedAt) || null };
}
const saveTags = () => writeJsonAtomic(TAGS_FILE, tags);

/** What the Discord embed / admin API show: role, label and the fully resolved design. */
function tagInfo(userId) {
    userId = String(userId);
    const r = roleFor(userId);
    const overrides = (tags[userId] && tags[userId].overrides) || {};
    return {
        userId,
        role: r.role,
        roleLabel: r.label,
        hasCustomTag: Object.keys(overrides).length > 0,
        overrides,
        effective: tagconfig.effectiveTag(r.role, overrides, r.label),
        updatedAt: (tags[userId] && tags[userId].updatedAt) || null,
    };
}

function commitTag(userId, overrides) {
    if (Object.keys(overrides).length) tags[userId] = { overrides, updatedAt: new Date().toISOString() };
    else delete tags[userId];
    saveTags();
    return tagInfo(userId);
}

/** Change options: { primary: '#ff8800', glow: 'off', distances: '12/20/10000', theme: '#ff8800', … } — all or nothing. */
function setTagOptions(userId, options) {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    let next = { ...((tags[userId] && tags[userId].overrides) || {}) };
    const entries = Object.entries(options || {});
    if (!entries.length) throw new tagconfig.TagError('Nothing to change.');
    for (const [key, value] of entries) {
        if (key === 'theme') next = { ...next, ...tagconfig.themeOverrides(value) };
        else next = tagconfig.applyOption(next, key, value);
    }
    return commitTag(userId, next);
}

/** resetTag(id) wipes the whole design; resetTag(id, 'primary') resets just that option. */
function resetTag(userId, option) {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    if (!option) return commitTag(userId, {});
    return commitTag(userId, tagconfig.applyOption((tags[userId] && tags[userId].overrides) || {}, option, 'default'));
}

function copyTag(fromId, toId) {
    fromId = String(fromId); toId = String(toId);
    if (!isDigits(fromId) || !isDigits(toId)) throw new tagconfig.TagError('Both ids must be numeric.');
    const src = (tags[fromId] && tags[fromId].overrides) || null;
    if (!src) throw new tagconfig.TagError(`\`${fromId}\` doesn't have a custom tag to copy.`);
    return commitTag(toId, { ...src });
}

/**
 * Import a SCORPTAG1 export code (from the in-game tag editor or /tag export).
 * mode 'replace' (default) makes the code THE design; 'merge' layers it over what's already there.
 * Unknown / invalid options are skipped and reported back, never applied.
 */
function importTag(userId, code, mode = 'replace') {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    const { overrides, ignored, invalid } = tagconfig.decodeCode(code);
    if (!Object.keys(overrides).length) {
        throw new tagconfig.TagError(invalid.length ? `Nothing usable in that code: ${invalid.slice(0, 3).join('; ')}` : 'That code doesn\'t change anything from the defaults.');
    }
    const base = mode === 'merge' ? ((tags[userId] && tags[userId].overrides) || {}) : {};
    const info = commitTag(userId, { ...base, ...overrides });
    return { info, ignored, invalid, applied: Object.keys(overrides).length, mode: mode === 'merge' ? 'merge' : 'replace' };
}

/** A player's current design as a shareable code. */
function exportTag(userId) {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    const overrides = (tags[userId] && tags[userId].overrides) || {};
    if (!Object.keys(overrides).length) throw new tagconfig.TagError(`\`${userId}\` doesn't have a custom design to export.`);
    return { code: tagconfig.encodeCode(overrides), options: Object.keys(overrides).length };
}

/** Apply a named colour preset (keeps every non-colour option). */
function applyPreset(userId, name) {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    return commitTag(userId, { ...((tags[userId] && tags[userId].overrides) || {}), ...tagconfig.presetOverrides(name) });
}

/** The public part of a player's tag that goes to other clients: role, label and only the changed options. */
function publicTagFor(userId) {
    const r = roleFor(userId);
    const overrides = tags[String(userId)] && tags[String(userId)].overrides;
    const out = { role: r.role, label: (overrides && overrides.label) || r.label };
    if (overrides && Object.keys(overrides).length) out.tag = overrides;
    return out;
}

function throttled(key, ms) {
    const t = now();
    const last = alertSeen.get(key);
    if (last && t - last < ms) return true;
    alertSeen.set(key, t);
    return false;
}

function trackIpCorrelation(userId, hwid, ip) {
    if (!ip) return;
    const t = now();
    if (!ipIdentities.has(ip)) ipIdentities.set(ip, new Map());
    const seen = ipIdentities.get(ip);
    seen.set(`${userId || '?'}::${hwid || '?'}`, t);
    for (const [k, ts] of seen) if (t - ts > CONFIG.SUSPICIOUS_WINDOW_MS) seen.delete(k);
    if (seen.size > CONFIG.SUSPICIOUS_IDENTITY_COUNT) {
        suspiciousIps.set(ip, { identities: [...seen.keys()], flaggedAt: t });
        if (!throttled(`ip:${ip}`, CONFIG.SUSPICIOUS_WINDOW_MS)) {
            alert({
                title: '👥 Many accounts on one IP',
                color: 0x9b59b6,
                description: 'Review only — shared/school/mobile IPs can trigger this too. Nothing was blocked.',
                fields: [
                    { name: 'IP', value: `\`${ip}\``, inline: true },
                    { name: 'Identities (1h)', value: String(seen.size), inline: true },
                    { name: 'Seen', value: [...seen.keys()].slice(0, 6).map(k => `\`${k}\``).join('\n') },
                ],
            });
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────
// Anti-tamper pipeline: flags → alert → strikes → ban
// ────────────────────────────────────────────────────────────────────────────
function sanitizeCodes(codes) {
    if (!Array.isArray(codes)) return [];
    const out = new Set();
    for (const c of codes.slice(0, 16)) if (typeof c === 'string' && /^[A-Z][A-Z0-9]{0,3}$/.test(c)) out.add(c);
    return [...out];
}
function scoreCodes(codes) { return codes.reduce((s, c) => s + (CODE_INFO[c] ? CODE_INFO[c][0] : 1), 0); }

function applyBan(root, who, reason) {
    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    const tier = BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.permanent = tier === null;
    g.bannedUntil = g.permanent ? null : now() + tier;
    g.reasons.push({ username: who.username || 'Unknown', userId: who.userId || null, hwid: who.hwid || null, ip: who.ip || null, reason, date: new Date().toISOString() });
    groups[root] = g;
    saveOffenses();
    strikes.delete(root);
    const label = g.permanent ? 'PERMANENT' : TIER_LABEL[tier] || `${tier}ms`;
    alert({
        title: `🚨 Offense #${g.offenseCount} — banned (${label})`,
        color: 0xe74c3c,
        fields: [
            { name: 'Username', value: `\`${who.username || 'Unknown'}\``, inline: true },
            { name: 'User ID', value: `\`${who.userId || 'Unknown'}\``, inline: true },
            { name: 'HWID', value: `\`${who.hwid || 'Unknown'}\`` },
            { name: 'IP', value: `\`${who.ip || 'Unknown'}\`` },
            { name: 'Reason', value: reason },
        ],
    });
}

/** Returns true if the identity is banned after processing. */
function handleFlags(who, rawCodes, source) {
    const codes = sanitizeCodes(rawCodes);
    const root = who.ownerOk ? null : linkIdentity(who.userId, who.hwid);
    if (!codes.length) return isGroupBanned(root);

    const score = scoreCodes(codes);

    if (who.ownerOk) {
        log(`[tamper] owner-verified session flagged ${codes.join(',')} (ignored)`);
        return false;
    }

    let strikeCount = 0;
    let action = 'alert only';
    if (root && !isGroupBanned(root)) {
        const set = strikes.get(root) || new Set();
        if (score >= CONFIG.STRIKE_SCORE) set.add(who.nonce || who.sessionId || 'n/a');
        strikes.set(root, set);
        strikeCount = set.size;
        if (CONFIG.AUTO_BAN && (score >= CONFIG.BAN_SCORE || strikeCount >= CONFIG.AUTO_BAN_THRESHOLD)) {
            const reason = `${source}: ${codes.join(',')} (score ${score}${strikeCount ? `, ${strikeCount} flagged session(s)` : ''})`;
            applyBan(root, who, reason);
            return true;
        }
        if (!CONFIG.AUTO_BAN) action = 'alert only (auto-ban is off)';
        else action = `alert only — strike ${strikeCount}/${CONFIG.AUTO_BAN_THRESHOLD}`;
    }

    if (!throttled(`det:${root}:${codes.join(',')}`, 10 * 60 * 1000)) {
        alert({
            title: `⚠️ Tamper signal (${source})`,
            color: 0xf39c12,
            fields: [
                { name: 'Username', value: `\`${who.username || 'Unknown'}\``, inline: true },
                { name: 'User ID', value: `\`${who.userId || 'Unknown'}\``, inline: true },
                { name: 'Score', value: String(score), inline: true },
                { name: 'Codes', value: codes.map(c => `**${c}** — ${CODE_INFO[c] ? CODE_INFO[c][1] : 'unknown check'}`).join('\n') },
                { name: 'HWID', value: `\`${who.hwid || 'Unknown'}\`` },
                { name: 'IP', value: `\`${who.ip || 'Unknown'}\``, inline: true },
                { name: 'Action', value: action, inline: true },
            ],
        });
    }
    return isGroupBanned(root);
}

// Payload delivered, but the loader never checked in → someone fetched it without running it.
setInterval(() => {
    const t = now();
    for (const [nonce, s] of issued) {
        if (t - s.issuedAt > 10 * 60 * 1000) { issued.delete(nonce); continue; }
        if (!s.confirmed && !s.alerted && !s.ownerOk && t - s.issuedAt > CONFIG.UNCONFIRMED_AFTER_MS) {
            s.alerted = true;
            alert({
                title: '📦 Payload fetched but never confirmed',
                color: 0xf1c40f,
                description: 'The loader normally checks in within seconds. This session never did — the payload may have been downloaded by hand (curl/dumper) or the heartbeat was blocked.',
                fields: [
                    { name: 'Username', value: `\`${s.username}\``, inline: true },
                    { name: 'User ID', value: `\`${s.userId}\``, inline: true },
                    { name: 'IP', value: `\`${s.ip}\``, inline: true },
                    { name: 'HWID', value: `\`${s.hwid}\`` },
                ],
            });
        }
    }
    for (const [uid, p] of presence) if (t - p.lastSeen > CONFIG.PRESENCE_TTL_MS * 4) presence.delete(uid);
    for (const [k, ts] of alertSeen) if (t - ts > 60 * 60 * 1000) alertSeen.delete(k);
    for (const [k, ts] of lastIssue) if (t - ts > 60 * 1000) lastIssue.delete(k);
}, CONFIG.WATCHER_INTERVAL_MS).unref();

// ────────────────────────────────────────────────────────────────────────────
// Express
// ────────────────────────────────────────────────────────────────────────────
const app = express();
app.disable('x-powered-by');
app.set('trust proxy', CONFIG.TRUST_PROXY_HOPS);
app.use(express.json({ limit: '32kb' }));

function rateLimit({ windowMs, max, name }) {
    const hits = new Map();
    setInterval(() => { const t = now(); for (const [k, v] of hits) if (t > v.reset) hits.delete(k); }, windowMs).unref();
    return (req, res, next) => {
        const key = clientIp(req);
        const t = now();
        let h = hits.get(key);
        if (!h || t > h.reset) { h = { n: 0, reset: t + windowMs }; hits.set(key, h); }
        if (++h.n > max) {
            res.set('Retry-After', String(Math.ceil((h.reset - t) / 1000)));
            return res.status(429).json({ ok: false, error: `rate limited (${name})` });
        }
        next();
    };
}
app.use('/api', rateLimit({ windowMs: 60_000, max: 600, name: 'api' }));

function publicBase(req) {
    return CONFIG.PUBLIC_URL || `${req.protocol}://${req.get('host')}`;
}

function whoFromToken(req, claims) {
    return {
        userId: claims.u,
        username: claims.nm,
        hwid: claims.h,
        ip: clientIp(req),
        nonce: claims.n,
        ownerOk: !!claims.ok,
    };
}

function requireToken(req, res, next) {
    const m = /^Bearer (.+)$/.exec(req.get('authorization') || '');
    const claims = m && verifyToken(m[1]);
    if (!claims) return res.status(401).json({ ok: false, error: 'bad token' });
    req.claims = claims;
    req.who = whoFromToken(req, claims);
    if (!req.who.ownerOk) {
        const root = linkIdentity(req.who.userId, req.who.hwid);
        if (isGroupBanned(root)) return res.status(403).json({ ok: false, revoked: true });
    }
    const s = issued.get(claims.n);
    if (s) s.confirmed = true;
    next();
}

// ── Public ──────────────────────────────────────────────────────────────────
app.get('/', (_req, res) => res.type('text/plain').send('ok'));

app.get('/api/health', (_req, res) => {
    const b = getBuild();
    res.json({
        ok: true,
        uptimeSeconds: Math.round(process.uptime()),
        build: b ? { id: b.id, builtAt: b.builtAt, kb: Math.round(b.bytes / 102.4) / 10 } : null,
        buildError,
        webhook: { configured: !!CONFIG.DISCORD_WEBHOOK, sent: webhook.sent, failed: webhook.failed, lastError: webhook.lastError, lastOkAt: webhook.lastOkAt },
        ownerKeySet: !!CONFIG.OWNER_KEY,
        autoBan: CONFIG.AUTO_BAN,
    });
});

app.get('/loader.lua', (req, res) => {
    res.type('text/plain').send(getLoader(publicBase(req)));
});

const sessionLimiter = rateLimit({ windowMs: 60_000, max: 40, name: 'session' });

app.post('/api/session', sessionLimiter, (req, res) => {
    const b = req.body || {};
    const userId = String(b.userId ?? '');
    if (!isDigits(userId)) return res.status(400).json({ ok: false, error: 'bad userId' });
    const username = cleanStr(b.username, 40) || 'Unknown';
    const hwid = cleanStr(b.hwid, 200) || 'UNKNOWN_HWID';
    const ip = clientIp(req);
    const ownerOk = ownerKeyOk(b.ownerKey);
    const who = { userId, username, hwid, ip, ownerOk, nonce: null };

    trackIpCorrelation(userId, hwid, ip);

    // Banned people get a harmless stall instead of an error, so they can't tell what happened.
    const decoy = () => res.json({ ok: true, token: null, payload: 'print("Connecting to server..."); task.wait(9e9)', lib: '', hb: 60 });

    if (!ownerOk && isGroupBanned(linkIdentity(userId, hwid))) return decoy();

    if (!b.resume) {
        const key = `${userId}::${hwid}`;
        const last = lastIssue.get(key);
        if (last && now() - last < CONFIG.SESSION_COOLDOWN_MS) {
            return res.status(429).json({ ok: false, error: 'cooldown', retryAfterMs: CONFIG.SESSION_COOLDOWN_MS - (now() - last) });
        }
        lastIssue.set(key, now());
    }

    const nonce = crypto.randomBytes(9).toString('base64url');
    who.nonce = nonce;
    if (handleFlags(who, b.flags, 'session start')) return decoy();

    const claims = { v: 1, n: nonce, u: userId, nm: username, h: hwid, iat: now(), exp: now() + CONFIG.TOKEN_TTL_MS, ok: ownerOk ? 1 : 0 };
    const token = signToken(claims);
    issued.set(nonce, { userId, username, hwid, ip, issuedAt: now(), confirmed: !!b.resume, alerted: false, ownerOk });

    if (b.resume) return res.json({ ok: true, token, hb: CONFIG.HEARTBEAT_SECONDS });

    const build = ensureBuilt();
    if (!build) return res.status(503).json({ ok: false, error: 'payload not built yet' });
    res.json({ ok: true, token, payload: build.code, lib: getLib(), hb: CONFIG.HEARTBEAT_SECONDS, build: build.id });
});

app.post('/api/heartbeat', requireToken, (req, res) => {
    const banned = handleFlags(req.who, (req.body || {}).flags, 'heartbeat');
    if (banned) return res.status(403).json({ ok: false, revoked: true });
    res.json({ ok: true });
});

const syncLimiter = new Map();
app.post('/api/nametags/sync', requireToken, (req, res) => {
    const t = now();
    const lastSync = syncLimiter.get(req.claims.n) || 0;
    if (t - lastSync < 2000) return res.status(429).json({ ok: false, error: 'too fast' });
    syncLimiter.set(req.claims.n, t);
    if (syncLimiter.size > 5000) for (const [k, v] of syncLimiter) if (t - v > 60_000) syncLimiter.delete(k);

    const b = req.body || {};
    const jobId = cleanStr(b.jobId, 64);
    const me = {
        userId: req.who.userId,
        username: req.who.username,
        displayName: cleanStr(b.displayName, 32) || req.who.username,
        jobId,
        placeId: cleanStr(b.placeId, 20),
        lastSeen: t,
    };
    presence.set(me.userId, me);

    const users = [];
    for (const p of presence.values()) {
        if (t - p.lastSeen > CONFIG.PRESENCE_TTL_MS) continue;
        if (p.userId !== me.userId && (!jobId || p.jobId !== jobId)) continue;
        users.push({ userId: Number(p.userId), username: p.username, displayName: p.displayName, ...publicTagFor(p.userId) });
        if (users.length >= 100) break;
    }
    res.json({ ok: true, users });
});

app.post('/api/nametags/leave', requireToken, (req, res) => {
    presence.delete(req.who.userId);
    res.json({ ok: true });
});

// ── Admin ───────────────────────────────────────────────────────────────────
const adminLimiter = rateLimit({ windowMs: 60_000, max: num(env.ADMIN_RATE_PER_MIN, 30), name: 'admin' }); // per IP; raise it if you script the admin API
function requireAdmin(req, res, next) {
    const m = /^Bearer (.+)$/.exec(req.get('authorization') || '');
    const supplied = req.get('x-admin-key') || (m && m[1]) || '';
    if (!supplied || !safeEqual(supplied, CONFIG.ADMIN_PASSWORD)) return res.status(403).json({ error: 'Unauthorized' });
    next();
}
app.use('/api/admin', adminLimiter, requireAdmin);

app.get('/api/admin/sessions', (_req, res) => {
    const t = now();
    const live = [...presence.values()].filter(p => t - p.lastSeen <= CONFIG.PRESENCE_TTL_MS);
    const pending = [...issued.values()].filter(s => !s.confirmed);
    res.json({ issuedTracked: issued.size, unconfirmed: pending.length, online: live.length, users: live.map(p => ({ userId: p.userId, username: p.username, jobId: p.jobId, ...roleFor(p.userId) })) });
});

app.get('/api/admin/blacklist', (_req, res) => {
    const entries = Object.keys(groups).map(root => ({
        identities: Object.keys(parent).filter(id => find(id) === root),
        ...banInfo(root),
    }));
    res.json({ totalGroups: entries.length, groups: entries });
});

app.get('/api/admin/suspicious', (_req, res) => {
    const flagged = [...suspiciousIps.entries()].map(([ip, d]) => ({ ip, ...d }));
    res.json({ total: flagged.length, flagged });
});

app.post('/api/admin/blacklist', (req, res) => {
    const { userId, hwid, ip, username, reason, permanent } = req.body || {};
    if (!userId && !hwid) return res.status(400).json({ error: 'Must provide userId and/or hwid (IPs are not banned: too many people share one)' });
    const root = linkIdentity(userId ? String(userId) : null, hwid || null);
    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    g.permanent = !!permanent;
    g.bannedUntil = permanent ? null : now() + BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.reasons.push({ username: username || 'Manual Entry', userId: userId || null, hwid: hwid || null, ip: ip || null, reason: reason || 'Manual administrator ban', date: new Date().toISOString() });
    groups[root] = g;
    saveOffenses();
    res.json({ success: true, entry: banInfo(root) });
});

app.post('/api/admin/unblacklist', (req, res) => {
    const target = String((req.body || {}).target || '');
    if (!target) return res.status(400).json({ error: 'Missing target (userId or hwid)' });
    const candidates = [`uid:${target}`, `hwid:${target}`].filter(id => id in parent);
    if (!candidates.length) return res.status(404).json({ success: false, message: `Target ${target} not found.` });
    const root = find(candidates[0]);
    if (groups[root]) {
        groups[root].permanent = false;
        groups[root].bannedUntil = null;
        strikes.delete(root);
        saveOffenses();
    }
    res.json({ success: true, message: `Lifted ban for ${target}` });
});

// Shared by the HTTP admin routes below AND the optional Discord bot (src/discord-bot.js),
// so both ways of changing a role go through the exact same validation and write to the
// exact same store that /api/nametags/sync reads from.
function setRole(userId, role, label) {
    userId = String(userId);
    role = String(role || '').toLowerCase();
    if (!isDigits(userId) || !ROLES.includes(role)) {
        throw new Error(`userId must be numeric and role one of: ${ROLES.join(', ')}`);
    }
    label = cleanStr(label, 24) || DEFAULT_LABEL[role];
    roles[userId] = { role, label, updatedAt: new Date().toISOString() };
    saveRoles();
    return { userId, ...roles[userId] };
}

function clearRole(userId) {
    userId = String(userId);
    const had = userId in roles;
    delete roles[userId];
    saveRoles();
    return had;
}

app.get('/api/admin/roles', (_req, res) => res.json({ roles, available: ROLES }));

app.put('/api/admin/roles/:userId', (req, res) => {
    try {
        res.json(setRole(req.params.userId, (req.body || {}).role, (req.body || {}).label));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});

app.delete('/api/admin/roles/:userId', (req, res) => {
    clearRole(req.params.userId);
    res.json({ ok: true });
});

// ── Custom tag designs (same functions the Discord /tag command uses) ───────
//   GET    /api/admin/tags                 everyone with a custom design
//   GET    /api/admin/tags/options         every option + allowed values + defaults
//   GET    /api/admin/tags/:userId         role, overrides and the fully resolved design
//   PUT    /api/admin/tags/:userId         body: { "primary": "#ff8800", "glow": "off", "theme": "#33aaff", … }
//   DELETE /api/admin/tags/:userId[?option=primary]   reset one option, or the whole design
//   GET    /api/admin/tags/:userId/export   → { code }   (SCORPTAG1.… — same format the in-game tag editor makes)
//   POST   /api/admin/tags/:userId/import   body: { code, mode: 'replace' | 'merge' }
//   POST   /api/admin/tags/:userId/preset   body: { name: 'Cyber Blue' }
app.get('/api/admin/tags', (_req, res) => res.json({ tags: Object.fromEntries(Object.entries(tags).map(([id, t]) => [id, t.overrides])) }));
app.get('/api/admin/tags/options', (_req, res) => res.json({
    groups: tagconfig.GROUPS, composites: tagconfig.COMPOSITES, types: tagconfig.TYPES, fonts: tagconfig.FONTS,
    animations: tagconfig.ANIMATIONS, defaults: tagconfig.DEFAULTS, rolePresets: tagconfig.ROLE_PRESETS, colorPresets: tagconfig.PRESET_NAMES,
}));
app.get('/api/admin/tags/:userId', (req, res) => {
    if (!isDigits(req.params.userId)) return res.status(400).json({ error: 'bad userId' });
    res.json(tagInfo(req.params.userId));
});
app.put('/api/admin/tags/:userId', (req, res) => {
    try {
        res.json(setTagOptions(req.params.userId, req.body));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});
app.get('/api/admin/tags/:userId/export', (req, res) => {
    try {
        res.json(exportTag(req.params.userId));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});
app.post('/api/admin/tags/:userId/import', (req, res) => {
    try {
        const b = req.body || {};
        res.json(importTag(req.params.userId, b.code, b.mode));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});
app.post('/api/admin/tags/:userId/preset', (req, res) => {
    try {
        res.json(applyPreset(req.params.userId, (req.body || {}).name));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});
app.delete('/api/admin/tags/:userId', (req, res) => {
    try {
        res.json(resetTag(req.params.userId, req.query.option ? String(req.query.option) : undefined));
    } catch (e) {
        res.status(400).json({ error: e.message });
    }
});

app.post('/api/admin/rebuild', (_req, res) => {
    const b = ensureBuilt(true);
    res.json({ ok: !buildError, build: b && { id: b.id, builtAt: b.builtAt, bytes: b.bytes }, buildError });
});

app.post('/api/admin/test-webhook', async (_req, res) => {
    if (!CONFIG.DISCORD_WEBHOOK) return res.status(400).json({ ok: false, error: 'DISCORD_WEBHOOK is not set' });
    const ok = await postWebhook(makeEmbed({ title: '🔔 Webhook test', color: 0x3498db, description: 'If you can read this, alerts from the Scorp server will reach this channel.' }));
    res.status(ok ? 200 : 502).json({ ok, lastError: webhook.lastError });
});

// ── Fallbacks ───────────────────────────────────────────────────────────────
app.use((_req, res) => res.status(404).json({ ok: false, error: 'not found' }));
app.use((err, _req, res, _next) => {
    if (err && (err.type === 'entity.parse.failed' || err.type === 'entity.too.large')) return res.status(400).json({ ok: false, error: 'bad request body' });
    console.error('[server] unhandled error:', err);
    res.status(500).json({ ok: false, error: 'server error' });
});

process.on('unhandledRejection', e => console.error('[server] unhandled rejection:', e));

// ────────────────────────────────────────────────────────────────────────────
// Start
// ────────────────────────────────────────────────────────────────────────────
// ── Discord bot (optional) ───────────────────────────────────────────────────
// Lets staff run /nametag set|clear|list from Discord instead of hitting the HTTP
// admin API by hand. Runs in this same process and calls setRole/clearRole directly
// (no network hop, no need to hand the bot the admin key). Only starts if a bot
// token is configured; the rest of the server works fine without it.
function startDiscordBotIfConfigured() {
    if (!CONFIG.DISCORD_TOKEN) return null;
    try {
        const startDiscordBot = require('./discord-bot');
        return startDiscordBot({
            token: CONFIG.DISCORD_TOKEN,
            clientId: CONFIG.DISCORD_CLIENT_ID,
            guildId: CONFIG.DISCORD_GUILD_ID,
            staffIds: CONFIG.STAFF_DISCORD_IDS,
            roleNames: ROLES,
            setRole,
            clearRole,
            getRoles: () => roles,
            tags: { info: tagInfo, set: setTagOptions, reset: resetTag, copy: copyTag, list: () => tags, import: importTag, export: exportTag, preset: applyPreset },
            publicUrl: CONFIG.PUBLIC_URL,
            log,
        });
    } catch (e) {
        log(`[discord-bot] failed to start: ${e.message}`);
        return null;
    }
}

function start() {
    const b = ensureBuilt(true);
    const server = app.listen(CONFIG.PORT, () => {
        log(`Scorp server listening on :${CONFIG.PORT}  payload=${b ? b.id : 'NOT BUILT'}  data=${CONFIG.DATA_DIR}`);
        checkWebhookAtStartup();
        startDiscordBotIfConfigured();
    });
    return server;
}

if (require.main === module) start();
module.exports = { app, start, CONFIG };
