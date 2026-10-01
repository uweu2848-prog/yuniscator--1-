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
    if (process.env.NODE_ENV === 'test') return;
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
const releaseChannel = String(env.RELEASE_CHANNEL || 'production').trim().toLowerCase();

const CONFIG = {
    PORT: num(env.PORT, 3000),
    PUBLIC_URL: (env.PUBLIC_URL || '').replace(/\/+$/, ''),
    DISCORD_WEBHOOK: (env.DISCORD_WEBHOOK || '').trim(),
    WEBHOOK_STARTUP_PING: flag(env.WEBHOOK_STARTUP_PING, true),
    OWNER_USER_ID: String(env.OWNER_USER_ID || '').trim(),
    ADMIN_ROBLOX_IDS: (env.ADMIN_ROBLOX_IDS || '').split(',').map(s => s.trim()).filter(s => /^\d{1,20}$/.test(s)),
    TAG_MANAGER_ROBLOX_IDS: (env.TAG_MANAGER_ROBLOX_IDS || '').split(',').map(s => s.trim()).filter(s => /^\d{1,20}$/.test(s)),
    SUPPORT_ROBLOX_IDS: (env.SUPPORT_ROBLOX_IDS || '').split(',').map(s => s.trim()).filter(s => /^\d{1,20}$/.test(s)),
    OWNER_DISCORD_IDS: (env.OWNER_DISCORD_IDS || '').split(',').map(s => s.trim()).filter(s => /^\d{1,20}$/.test(s)),
    OWNER_KEY: env.OWNER_KEY || '',
    ADMIN_PASSWORD: env.ADMIN_PASSWORD || '',
    DISCORD_TOKEN: (env.DISCORD_TOKEN || '').trim(),
    DISCORD_CLIENT_ID: (env.DISCORD_CLIENT_ID || '').trim(),
    DISCORD_GUILD_ID: (env.DISCORD_GUILD_ID || '').trim(), // optional: instant slash-command sync to one server
    STAFF_DISCORD_IDS: (env.STAFF_DISCORD_IDS || '').split(',').map(s => s.trim()).filter(Boolean),
    DATA_DIR: env.DATA_DIR ? path.resolve(env.DATA_DIR) : path.join(ROOT, 'data'),
    SESSION_SECRET: env.SESSION_SECRET || '',
    RELEASE_CHANNEL: releaseChannel === 'development' ? 'development' : 'production',
    RELEASE_VERSION: String(env.RELEASE_VERSION || 'unversioned').trim().slice(0, 40),
    RELEASE_NOTES: String(env.RELEASE_NOTES || '').trim().slice(0, 1000),
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
    SESSION_HISTORY_MAX: num(env.SESSION_HISTORY_MAX, 200), // how many past sessions to keep in memory
};

const DAY = 24 * 60 * 60 * 1000;
const BAN_TIERS = [1 * DAY, 7 * DAY, 30 * DAY, null]; // 1st, 2nd, 3rd offense, then permanent
const TIER_LABEL = { [1 * DAY]: '1 day', [7 * DAY]: '7 days', [30 * DAY]: '30 days' };

const ROLES = ['owner', 'developer', 'admin', 'moderator', 'support', 'vip', 'member'];
const DEFAULT_LABEL = { owner: 'Owner', developer: 'Developer', admin: 'Admin', moderator: 'Moderator', support: 'Support', vip: 'VIP', member: 'Member' };

// Server-side weights. The client's own "score" is never trusted, only its codes.
const CODE_INFO = {
    C1: [2, 'Core runtime functions were modified'],
    H1: [1, 'The network request function was wrapped'],
    H2: [3, 'The request or script loader changed after launch'],
    H3: [1, 'The Roblox HTTP function was wrapped'],
    M1: [1, 'Game API hooks were detected'],
    G1: [2, 'A known network-inspection tool was detected'],
    G2: [2, 'A known network-inspection marker was detected'],
    G3: [2, 'A nested network-inspection tool was detected'],
};

fs.mkdirSync(CONFIG.DATA_DIR, { recursive: true });
const OFFENSES_FILE = path.join(CONFIG.DATA_DIR, 'offenses.json');
const ROLES_FILE = path.join(CONFIG.DATA_DIR, 'roles.json');
const TAGS_FILE = path.join(CONFIG.DATA_DIR, 'tags.json');
const PAID_TAGS_FILE = path.join(CONFIG.DATA_DIR, 'paid-tags.json');
const ACCESS_FILE = path.join(CONFIG.DATA_DIR, 'access.json');
const ACCESS_HISTORY_FILE = path.join(CONFIG.DATA_DIR, 'access-history.json');
const SUPPORT_REPORTS_FILE = path.join(CONFIG.DATA_DIR, 'support-reports.json');
const SUPPORT_RESTRICTIONS_FILE = path.join(CONFIG.DATA_DIR, 'support-restrictions.json');
const KNOWN_USERS_FILE = path.join(CONFIG.DATA_DIR, 'known-users.json');
const ACTIVE_WEBHOOK_FILE = path.join(CONFIG.DATA_DIR, 'active-users-webhook.json');
const SECRET_FILE = path.join(CONFIG.DATA_DIR, 'session.key');
const LIB_FILE = path.join(ROOT, 'src', 'ScorpLib.lua');
const ADMIN_PANEL_FILE = path.join(ROOT, 'src', 'adminpanel.lua');
const TAG_PANEL_FILE = path.join(ROOT, 'src', 'tagpanel.lua');
const SUPPORT_PANEL_FILE = path.join(ROOT, 'src', 'supportpanel.lua');
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
const panelAdminIds = new Set([CONFIG.OWNER_USER_ID, ...CONFIG.ADMIN_ROBLOX_IDS].filter(isDigits));
const tagManagerIds = new Set(CONFIG.TAG_MANAGER_ROBLOX_IDS);
const supportIds = new Set(CONFIG.SUPPORT_ROBLOX_IDS);

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
            footer: { text: 'Scorp · discord.gg/scorp' },
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
    const mentionIds = [...new Set((embedSpec.mentionIds || []).map(String).filter(id => /^\d{1,20}$/.test(id)))].slice(0, 50);
    if (mentionIds.length) {
        body.content = mentionIds.map(id => `<@${id}>`).join(' ');
        body.allowed_mentions = { parse: [], users: mentionIds };
    }
    log(`[alert] ${embedSpec.title}${embedSpec.fields ? ' | ' + embedSpec.fields.map(f => `${f.name}=${f.value}`).join(' ') : ''}`);
    if (!CONFIG.DISCORD_WEBHOOK) return;
    if (webhookQueue.length > 50) webhookQueue.shift(); // never let a flood grow memory
    webhookQueue.push(body);
    drainWebhooks();
}

function webhookMessageUrl(messageId) {
    const url = new URL(CONFIG.DISCORD_WEBHOOK);
    url.search = '';
    url.hash = '';
    url.pathname = `${url.pathname.replace(/\/$/, '')}/messages/${encodeURIComponent(messageId)}`;
    return url;
}

function webhookCreateUrl() {
    const url = new URL(CONFIG.DISCORD_WEBHOOK);
    url.searchParams.set('wait', 'true');
    return url;
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
            title: '✅ Scorp is online',
            color: 0x2ecc71,
            description: 'The backend is ready. · discord.gg/scorp',
            fields: [
                { name: 'Release', value: `${CONFIG.RELEASE_CHANNEL} · ${CONFIG.RELEASE_VERSION}`, inline: true },
                { name: 'Build', value: b ? `\`${b.id}\` · ${(b.bytes / 1024).toFixed(1)} KB` : 'unavailable', inline: true },
                { name: 'Protection', value: CONFIG.AUTO_BAN ? 'Automatic blocking is on' : 'Alerts only', inline: true },
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

let adminPanelCache = { mtime: 0, code: '' };
function getAdminPanelModule() {
    const mtime = fs.statSync(ADMIN_PANEL_FILE).mtimeMs;
    if (mtime !== adminPanelCache.mtime) {
        const source = fs.readFileSync(ADMIN_PANEL_FILE, 'utf8').replace(/\r\n/g, '\n');
        adminPanelCache = { mtime, code: obf.obfuscateSource(source, 'adminpanel.lua') };
    }
    return adminPanelCache.code;
}

const personalizedBuildCache = new Map();
function getPersonalizedBuild(userId, baseBuild) {
    userId = String(userId);
    const cacheKey = `${baseBuild.id}:${userId}`;
    const hit = personalizedBuildCache.get(cacheKey);
    if (hit) {
        personalizedBuildCache.delete(cacheKey);
        personalizedBuildCache.set(cacheKey, hit);
        return hit;
    }

    const digest = crypto.createHmac('sha256', SECRET).update(`${baseBuild.id}:${userId}`).digest('base64url').slice(0, 12);
    const watermark = `SC-${digest}`;
    // A tiny harmless prefix personalizes the delivered blob without rerunning
    // the full Lua obfuscation pipeline for every login. The numeric bytes are
    // a tracing marker, not a secret or an authorization credential.
    const markerBytes = [...Buffer.from(watermark, 'utf8')].join(',');
    const prefix = `local _scorp_ctx = ...; if type(_scorp_ctx) == "table" then _scorp_ctx.watermark = string.char(${markerBytes}) end;\n`;
    const code = prefix + baseBuild.code;
    const personalized = { ...baseBuild, code, bytes: Buffer.byteLength(code), watermark };
    personalizedBuildCache.set(cacheKey, personalized);
    if (personalizedBuildCache.size > 256) personalizedBuildCache.delete(personalizedBuildCache.keys().next().value);
    return personalized;
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

let access = readJson(ACCESS_FILE, { allowlist: {} });
if (!access || typeof access !== 'object' || Array.isArray(access)) access = { allowlist: {} };
if (!access.allowlist || typeof access.allowlist !== 'object' || Array.isArray(access.allowlist)) access.allowlist = {};
const saveAccess = () => writeJsonAtomic(ACCESS_FILE, access);

let accessHistory = readJson(ACCESS_HISTORY_FILE, []);
if (!Array.isArray(accessHistory)) accessHistory = [];
let supportReports = readJson(SUPPORT_REPORTS_FILE, []);
if (!Array.isArray(supportReports)) supportReports = [];
let supportRestrictions = readJson(SUPPORT_RESTRICTIONS_FILE, {});
if (!supportRestrictions || typeof supportRestrictions !== 'object' || Array.isArray(supportRestrictions)) supportRestrictions = {};
for (const [userId, restriction] of Object.entries(supportRestrictions)) {
    if (!isDigits(userId) || !restriction || typeof restriction !== 'object' || !Number.isFinite(Number(restriction.until))) delete supportRestrictions[userId];
}
const saveSupportReports = () => writeJsonAtomic(SUPPORT_REPORTS_FILE, supportReports);
const saveSupportRestrictions = () => writeJsonAtomic(SUPPORT_RESTRICTIONS_FILE, supportRestrictions);
function recordAccessEvent(action, details = {}) {
    accessHistory.push({ action, at: new Date().toISOString(), ...details });
    if (accessHistory.length > 2000) accessHistory = accessHistory.slice(-2000);
    writeJsonAtomic(ACCESS_HISTORY_FILE, accessHistory);
}

function setAllowlisted(userId, allowed, reason = '', actor = 'admin') {
    userId = String(userId || '');
    if (!isDigits(userId)) throw new Error('userId must be numeric.');
    if (allowed) {
        access.allowlist[userId] = { reason: cleanStr(reason, 300) || 'Approved by staff', actor: cleanStr(actor, 80), addedAt: new Date().toISOString() };
    } else {
        if (!access.allowlist[userId]) return false;
        delete access.allowlist[userId];
    }
    saveAccess();
    recordAccessEvent(allowed ? 'allowlist_add' : 'allowlist_remove', { userId, reason: cleanStr(reason, 300), actor: cleanStr(actor, 80) });
    return true;
}

function allowlistHas(userId) { return !!access.allowlist[String(userId)]; }

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
const protectedStaffRobloxIds = new Set([
    CONFIG.OWNER_USER_ID,
    ...CONFIG.ADMIN_ROBLOX_IDS,
    ...CONFIG.TAG_MANAGER_ROBLOX_IDS,
].filter(isDigits));
const autoBanProtectedRobloxIds = new Set([
    ...CONFIG.ADMIN_ROBLOX_IDS,
    ...CONFIG.TAG_MANAGER_ROBLOX_IDS,
].filter(isDigits));

function isProtectedStaffIdentity(userId, hwid, protectedIds = protectedStaffRobloxIds) {
    if (userId && protectedIds.has(String(userId))) return true;
    const candidates = [];
    if (userId && isDigits(String(userId))) candidates.push(`uid:${userId}`);
    if (hwid && hwid !== 'UNKNOWN_HWID') candidates.push(`hwid:${hwid}`);
    for (const id of candidates) {
        if (!(id in parent)) continue;
        const root = find(id);
        for (const linkedId of Object.keys(parent)) {
            if (linkedId.startsWith('uid:')
                && protectedIds.has(linkedId.slice(4))
                && find(linkedId) === root) return true;
        }
    }
    return false;
}

function activeSupportRestriction(userId) {
    const restriction = supportRestrictions[String(userId)];
    if (!restriction || !Number.isFinite(Number(restriction.until)) || Number(restriction.until) <= now()) return null;
    return restriction;
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
const issued = new Map();    // nonce -> { userId, username, hwid, ip, executor, platform, issuedAt, confirmed, alerted, ownerOk }
const presence = new Map();  // userId -> { userId, username, displayName, jobId, placeId, lastSeen }
let knownUsers = readJson(KNOWN_USERS_FILE, {});
if (!knownUsers || typeof knownUsers !== 'object' || Array.isArray(knownUsers)) knownUsers = {};

function rememberUser(userId, username, countSession) {
    const t = now();
    let record = knownUsers[userId];
    if (!record || typeof record !== 'object' || Array.isArray(record)) record = knownUsers[userId] = null;
    const firstSeen = !record;
    if (!record) record = knownUsers[userId] = { firstSeen: t, sessions: 0 };
    record.username = cleanStr(username, 40) || record.username || 'Unknown';
    record.lastSeen = t;
    if (countSession) record.sessions = (Number(record.sessions) || 0) + 1;
    writeJsonAtomic(KNOWN_USERS_FILE, knownUsers);
    return { ...record, isFirstSeen: firstSeen };
}

function markUserActive(who, details = {}) {
    const previous = presence.get(who.userId) || {};
    const session = issued.get(who.nonce) || {};
    const known = knownUsers[who.userId] || {};
    presence.set(who.userId, {
        userId: who.userId,
        username: cleanStr(who.username, 40) || previous.username || 'Unknown',
        displayName: cleanStr(details.displayName, 32) || previous.displayName || cleanStr(who.username, 40) || 'Unknown',
        jobId: cleanStr(details.jobId || who.jobId || previous.jobId, 64),
        placeId: cleanStr(details.placeId || who.placeId || previous.placeId, 20),
        executor: cleanStr(session.executor || who.executor || previous.executor, 80) || 'Unknown',
        platform: cleanStr(session.platform || who.platform || previous.platform, 20) || 'Unknown',
        firstSeen: Number(known.firstSeen) || now(),
        sessions: Number(known.sessions) || 0,
        lastSeen: now(),
    });
    scheduleActiveUsersWebhook();
}

// Ring buffer of completed/expired sessions — survives the issued map TTL cleanup.
// Lets you see who used the script in the last N sessions even after they left.
const sessionHistory = [];
function pushHistory(entry) {
    sessionHistory.push({ ...entry, endedAt: now() });
    while (sessionHistory.length > CONFIG.SESSION_HISTORY_MAX) sessionHistory.shift();
}
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

let paidTags = readJson(PAID_TAGS_FILE, {});
if (!paidTags || typeof paidTags !== 'object' || Array.isArray(paidTags)) paidTags = {};
const savePaidTags = () => writeJsonAtomic(PAID_TAGS_FILE, paidTags);

function setPaidTagTier(userId, enabled, reason = '', actor = 'admin') {
    userId = String(userId || '');
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    if (enabled) {
        paidTags[userId] = { enabled: true, reason: cleanStr(reason, 300) || 'Custom tag approved by staff', actor: cleanStr(actor, 80) || 'admin', updatedAt: new Date().toISOString() };
    } else {
        delete paidTags[userId];
    }
    savePaidTags();
    recordAccessEvent(enabled ? 'premium_tag_grant' : 'premium_tag_revoke', { userId, reason: cleanStr(reason, 300), actor: cleanStr(actor, 80) || 'admin' });
    return paidTags[userId] || null;
}

/** What the Discord embed / admin API show: role, label and the fully resolved design. */
function tagInfo(userId) {
    userId = String(userId);
    const r = roleFor(userId);
    const overrides = (tags[userId] && tags[userId].overrides) || {};
    return {
        userId,
        role: r.role,
        roleLabel: r.label,
        tier: paidTags[userId] && paidTags[userId].enabled ? 'premium' : 'free',
        paidTag: paidTags[userId] || null,
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

/** Apply only the three curated selections exposed by the free self-service editor. */
function applyFreeTagPresets(userId, selections) {
    userId = String(userId);
    if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
    if (paidTags[userId] && paidTags[userId].enabled) throw new tagconfig.TagError('This account has a staff-managed premium tag. Contact Scorp staff for changes.');
    if (!selections || typeof selections !== 'object' || Array.isArray(selections)) {
        throw new tagconfig.TagError('Choose a color, font, and effect preset.');
    }
    const expected = ['colorPreset', 'fontPreset', 'effectPreset'];
    if (Object.keys(selections).length !== expected.length || expected.some(k => !Object.prototype.hasOwnProperty.call(selections, k))) {
        throw new tagconfig.TagError('Free designs require exactly one color, font, and effect preset.');
    }
    const matchName = (raw, names, label) => {
        const key = names.find(n => n.toLowerCase() === String(raw || '').trim().toLowerCase());
        if (!key) throw new tagconfig.TagError(`Choose a listed ${label} preset.`);
        return key;
    };
    const colorName = matchName(selections.colorPreset, tagconfig.PRESET_NAMES, 'color');
    const fontName = matchName(selections.fontPreset, tagconfig.FREE_FONT_PRESET_ORDER, 'font');
    const effectName = matchName(selections.effectPreset, tagconfig.FREE_EFFECT_PRESET_ORDER, 'effect');
    const next = {};
    const addDifferences = values => {
        for (const [key, value] of Object.entries(values)) if (value !== tagconfig.DEFAULTS[key]) next[key] = value;
    };
    addDifferences(tagconfig.presetOverrides(colorName));
    addDifferences(tagconfig.FREE_FONT_PRESETS[fontName]);
    addDifferences(tagconfig.FREE_EFFECT_PRESETS[effectName]);
    return commitTag(userId, next);
}

/** The public part of a player's tag that goes to other clients: role, label and only the changed options. */
function publicTagFor(userId) {
    const r = roleFor(userId);
    const id = String(userId);
    const overrides = tags[id] && tags[id].overrides;
    const isPremium = !!(paidTags[id] && paidTags[id].enabled);
    const out = { role: r.role, label: (isPremium && overrides && overrides.label) || r.label };
    if (overrides && isPremium) out.tag = overrides;
    else if (overrides) {
        const free = {};
        const effective = tagconfig.effectiveTag(r.role, overrides, r.label);
        const roleDefault = tagconfig.effectiveTag(r.role, {}, r.label);

        // A free account only gets whole known presets, never arbitrary color values.
        for (const presetName of tagconfig.PRESET_NAMES) {
            const palette = tagconfig.presetOverrides(presetName);
            if (tagconfig.COLOR_KEYS.every(key => effective[key] === palette[key])) {
                for (const key of tagconfig.COLOR_KEYS) if (palette[key] !== roleDefault[key]) free[key] = palette[key];
                break;
            }
        }

        for (const presetName of tagconfig.FREE_FONT_PRESET_ORDER) {
            const fontPreset = tagconfig.FREE_FONT_PRESETS[presetName];
            if (effective.rankFont === fontPreset.rankFont && effective.userFont === fontPreset.userFont) {
                for (const key of ['rankFont', 'userFont']) if (fontPreset[key] !== tagconfig.DEFAULTS[key]) free[key] = fontPreset[key];
                break;
            }
        }

        for (const presetName of tagconfig.FREE_EFFECT_PRESET_ORDER) {
            const effectPreset = tagconfig.FREE_EFFECT_PRESETS[presetName];
            const keys = ['textAnimation', ...tagconfig.EFFECT_KEYS];
            if (keys.every(key => effective[key] === effectPreset[key])) {
                for (const key of keys) if (effectPreset[key] !== tagconfig.DEFAULTS[key]) free[key] = effectPreset[key];
                break;
            }
        }
        if (Object.keys(free).length) out.tag = free;
    }
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
                title: '👥 Several accounts share a network',
                color: 0x9b59b6,
                description: 'Review only. Shared homes, schools, and mobile networks can trigger this; nothing was blocked.',
                fields: [
                    { name: 'Accounts seen in the last hour', value: String(seen.size), inline: true },
                    { name: 'Network address', value: `\`${ip}\``, inline: true },
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

function alertIdentityFields(who) {
    const session = issued.get(who.nonce) || {};
    const value = v => `\`${cleanStr(v || 'Unknown', 180)}\``;
    return [
        { name: 'Account', value: `${value(who.username)} (#${cleanStr(who.userId || '?', 30)})`, inline: true },
        { name: 'Client', value: `${cleanStr(session.executor || who.executor || 'Unknown', 60)} · ${cleanStr(session.platform || who.platform || 'Unknown', 30)}`, inline: true },
        { name: 'Server', value: `${cleanStr(session.placeId || who.placeId || 'Unknown', 30)} · ${cleanStr(session.jobId || who.jobId || 'Unknown', 50)}`, inline: true },
    ];
}

function applyBan(root, who, reason, codes, source) {
    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    const tier = BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.permanent = tier === null;
    g.bannedUntil = g.permanent ? null : now() + tier;
    g.reasons.push({ username: who.username || 'Unknown', userId: who.userId || null, hwid: who.hwid || null, ip: who.ip || null, reason, date: new Date().toISOString() });
    groups[root] = g;
    saveOffenses();
    recordAccessEvent('auto_blacklist', {
        userId: who.userId || null, username: who.username || 'Unknown', hwid: who.hwid || null,
        reason: cleanStr(reason, 500), permanent: g.permanent, bannedUntil: g.bannedUntil,
    });
    strikes.delete(root);
    const label = g.permanent ? 'permanent' : TIER_LABEL[tier] || `${tier}ms`;
    alert({
        title: `⛔ Account blocked for ${label}`,
        color: 0xe74c3c,
        description: 'Scorp automatically blocked this account after suspicious activity.',
        fields: [
            ...alertIdentityFields(who),
            { name: 'Why', value: `${source === 'session start' ? 'At sign-in' : 'During a session'}: ${(codes || []).map(c => CODE_INFO[c] ? CODE_INFO[c][1] : 'Unrecognized check').join('; ')}` },
            { name: 'Device / network', value: `${cleanStr(who.hwid || 'Unknown', 80)} · ${cleanStr(who.ip || 'Unknown', 60)}`, inline: false },
        ],
    });
}

/** Returns true if the identity is banned after processing. */
function handleFlags(who, rawCodes, source) {
    const codes = sanitizeCodes(rawCodes);
    const protectedStaff = !who.ownerOk && isProtectedStaffIdentity(who.userId, who.hwid, autoBanProtectedRobloxIds);
    const root = who.ownerOk ? null : linkIdentity(who.userId, who.hwid);
    if (!codes.length) return isGroupBanned(root);

    const score = scoreCodes(codes);

    if (who.ownerOk) {
        log(`[tamper] owner-verified session flagged ${codes.join(',')} (ignored)`);
        return false;
    }

    if (protectedStaff) {
        if (!throttled(`protected-staff:${who.userId}:${codes.join(',')}`, 10 * 60 * 1000)) {
            alert({
                title: '🛡️ Activity flagged · protected staff account',
                color: 0x3498db,
                description: 'No automatic blacklist was applied. An owner must review any action against configured staff.',
                fields: [
                    ...alertIdentityFields(who),
                    { name: 'Checks', value: codes.map(c => `${c}: ${CODE_INFO[c] ? CODE_INFO[c][1] : 'unrecognized check'}`).join('\n') },
                ],
            });
        }
        return isGroupBanned(root);
    }

    if (allowlistHas(who.userId)) {
        if (!throttled(`allowlisted:${who.userId}:${codes.join(',')}`, 10 * 60 * 1000)) {
            alert({
                title: '🛡️ Activity flagged · allowlisted account',
                color: 0x3498db,
                description: 'No automatic action was taken. Any existing blacklist still applies.',
                fields: [...alertIdentityFields(who),
                    { name: 'Checks', value: codes.map(c => `${c}: ${CODE_INFO[c] ? CODE_INFO[c][1] : 'unrecognized check'}`).join('\n') },
                    { name: 'Staff note', value: access.allowlist[String(who.userId)].reason || 'Approved by staff' },
                ],
            });
        }
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
            applyBan(root, who, reason, codes, source);
            return true;
        }
        if (!CONFIG.AUTO_BAN) action = 'Review only · automatic blocking is off';
        else action = `Review only · ${strikeCount}/${CONFIG.AUTO_BAN_THRESHOLD} flagged sessions`;
    }

    if (!throttled(`det:${root}:${codes.join(',')}`, 10 * 60 * 1000)) {
        alert({
            title: '⚠️ Unusual client activity',
            color: 0xf39c12,
            description: `${source === 'session start' ? 'At sign-in' : 'During a session'}, Scorp detected checks that need review.`,
            fields: [
                ...alertIdentityFields(who),
                { name: 'Checks', value: codes.map(c => `${c}: ${CODE_INFO[c] ? CODE_INFO[c][1] : 'unrecognized check'}`).join('\n') },
                { name: 'Next step', value: action, inline: true },
            ],
        });
    }
    return isGroupBanned(root);
}

// Payload delivered, but the loader never checked in → someone fetched it without running it.
setInterval(() => {
    const t = now();
    for (const [nonce, s] of issued) {
        if (t - s.issuedAt > 10 * 60 * 1000) { pushHistory(s); issued.delete(nonce); continue; }
        if (!s.confirmed && !s.alerted && !s.ownerOk && t - s.issuedAt > CONFIG.UNCONFIRMED_AFTER_MS) {
            s.alerted = true;
            const who = { ...s, nonce, ownerOk: false };
            alert({
                title: '⏱️ Session did not check in',
                color: 0xf1c40f,
                description: 'Scorp did not receive a check-in in time. This may be a connection issue; it is not proof of tampering.',
                fields: [
                    ...alertIdentityFields(who),
                    { name: 'Time since launch', value: `${Math.round((t - s.issuedAt) / 1000)} seconds`, inline: true },
                ],
            });
        }
    }
    let expiredPresence = false;
    for (const [uid, p] of presence) {
        if (t - p.lastSeen > CONFIG.PRESENCE_TTL_MS) {
            presence.delete(uid);
            expiredPresence = true;
        }
    }
    if (expiredPresence) scheduleActiveUsersWebhook();
    for (const [k, ts] of alertSeen) if (t - ts > 60 * 60 * 1000) alertSeen.delete(k);
    for (const [k, ts] of lastIssue) if (t - ts > 60 * 1000) lastIssue.delete(k);
    let restrictionsChanged = false;
    for (const [userId, restriction] of Object.entries(supportRestrictions)) {
        if (!restriction || Number(restriction.until) <= t) {
            delete supportRestrictions[userId];
            restrictionsChanged = true;
        }
    }
    if (restrictionsChanged) saveSupportRestrictions();
    for (const [userId, submittedAt] of supportReportLastSubmitted) if (t - submittedAt > 60 * 1000) supportReportLastSubmitted.delete(userId);
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
    const issuedSession = issued.get(claims.n) || {};
    return {
        userId: claims.u,
        username: claims.nm,
        hwid: claims.h,
        ip: clientIp(req),
        nonce: claims.n,
        ownerOk: !!claims.ok,
        executor: issuedSession.executor || 'Unknown',
        platform: issuedSession.platform || 'Unknown',
        jobId: issuedSession.jobId || 'Unknown',
        placeId: issuedSession.placeId || 'Unknown',
    };
}

function requireToken(req, res, next) {
    const m = /^Bearer (.+)$/.exec(req.get('authorization') || '');
    const claims = m && verifyToken(m[1]);
    if (!claims) return res.status(401).json({ ok: false, error: 'bad token' });
    const restriction = !claims.ok && activeSupportRestriction(claims.u);
    if (restriction) return res.status(403).json({
        ok: false,
        revoked: true,
        message: `Scorp access was paused by support until ${new Date(restriction.until).toISOString()}.`,
    });
    const currentBuild = ensureBuilt();
    if (!currentBuild) return res.status(503).json({ ok: false, error: 'payload unavailable' });
    const channelMismatch = claims.c !== CONFIG.RELEASE_CHANNEL;
    const versionMismatch = claims.rv !== CONFIG.RELEASE_VERSION;
    if (claims.b !== currentBuild.id || channelMismatch || versionMismatch) {
        const note = CONFIG.RELEASE_NOTES ? ` ${CONFIG.RELEASE_NOTES}` : '';
        const channelMessage = channelMismatch
            ? `This session is for the ${claims.c || 'unknown'} channel; this server runs ${CONFIG.RELEASE_CHANNEL}. Use the matching loader.`
            : `Scorp ${CONFIG.RELEASE_CHANNEL} ${CONFIG.RELEASE_VERSION} has been updated. Relaunch the latest loader to continue.`;
        return res.status(403).json({
            ok: false,
            revoked: true,
            updateRequired: true,
            build: currentBuild.id,
            releaseChannel: CONFIG.RELEASE_CHANNEL,
            releaseVersion: CONFIG.RELEASE_VERSION,
            updateMessage: `${channelMessage}${note}`,
        });
    }
    req.claims = claims;
    req.who = whoFromToken(req, claims);
    if (!req.who.ownerOk) {
        const root = linkIdentity(req.who.userId, req.who.hwid);
        if (isGroupBanned(root)) {
            return res.status(403).json({
                ok: false,
                revoked: true,
                message: 'This Scorp session was revoked because this account is blacklisted or blocked by staff.',
            });
        }
    }
    const s = issued.get(claims.n);
    if (s) s.confirmed = true;
    next();
}

function requirePanelAdmin(req, res, next) {
    if (!req.claims || !panelAdminIds.has(String(req.claims.u))) {
        return res.status(403).json({ ok: false, error: 'This Roblox account is not authorized for the Scorp admin panel.' });
    }
    next();
}

function isTagManager(userId) {
    const id = String(userId || '');
    return panelAdminIds.has(id) || tagManagerIds.has(id);
}

function requireTagManager(req, res, next) {
    if (!req.claims || !isTagManager(req.claims.u)) {
        return res.status(403).json({ ok: false, error: 'This Roblox account is not authorized for tag management.' });
    }
    next();
}

function requireSupport(req, res, next) {
    if (!req.claims || !supportIds.has(String(req.claims.u))) {
        return res.status(403).json({ ok: false, error: 'This Roblox account is not authorized for the Scorp support panel.' });
    }
    next();
}

app.get('/api/panel/authorize', requireToken, (req, res) => {
    const admin = panelAdminIds.has(String(req.claims.u));
    res.json({ ok: true, authorized: admin, tagManager: isTagManager(req.claims.u), support: supportIds.has(String(req.claims.u)) });
});

app.get('/api/support-panel/module', requireToken, requireSupport, (_req, res) => {
    try {
        res.type('text/plain').set('Cache-Control', 'no-store').send(fs.readFileSync(SUPPORT_PANEL_FILE, 'utf8'));
    } catch (e) {
        console.error('[support-panel] could not load authorized module:', e.message);
        res.status(503).json({ ok: false, error: 'Support panel module is temporarily unavailable.' });
    }
});

const supportReportLastSubmitted = new Map();
const SUPPORT_REPORT_CATEGORIES = new Set(['behavior', 'harassment', 'cheating', 'exploiting', 'other']);
app.post('/api/support-panel/report', requireToken, requireSupport, (req, res) => {
    const actorId = String(req.claims.u);
    const lastSubmitted = supportReportLastSubmitted.get(actorId) || 0;
    if (now() - lastSubmitted < 30_000) return res.status(429).json({ ok: false, error: 'Please wait 30 seconds before submitting another report.' });
    const body = req.body || {};
    const category = cleanStr(body.category, 24).toLowerCase();
    const subject = cleanStr(body.subject, 100);
    const details = cleanStr(body.details, 1800);
    const targetUserId = body.targetUserId == null || String(body.targetUserId).trim() === '' ? null : String(body.targetUserId).trim();
    if (!SUPPORT_REPORT_CATEGORIES.has(category)) return res.status(400).json({ ok: false, error: 'Choose a valid report category.' });
    if (subject.length < 4 || details.length < 20) return res.status(400).json({ ok: false, error: 'Add a short subject and at least 20 characters of report details.' });
    if (targetUserId && !isDigits(targetUserId)) return res.status(400).json({ ok: false, error: 'Target Roblox ID must be numeric.' });

    supportReportLastSubmitted.set(actorId, now());
    const report = {
        id: `SR-${crypto.randomBytes(5).toString('hex').toUpperCase()}`,
        category,
        subject,
        details,
        targetUserId,
        reporterUserId: actorId,
        reporterUsername: cleanStr(req.claims.nm, 40) || 'Unknown',
        createdAt: new Date().toISOString(),
        status: 'open',
    };
    supportReports.push(report);
    if (supportReports.length > 1000) supportReports = supportReports.slice(-1000);
    saveSupportReports();
    recordAccessEvent('support_report', { reportId: report.id, userId: actorId, targetUserId, category, subject });
    const reportDetailFields = [];
    for (let offset = 0, part = 1; offset < details.length; offset += 950, part++) {
        reportDetailFields.push({ name: reportDetailFields.length ? `Report details (${part})` : 'Report details', value: details.slice(offset, offset + 950) });
    }
    alert({
        title: `📨 Support report · ${report.id}`,
        color: 0x3498db,
        description: 'A Scorp support member filed a report for staff review. Review it before taking moderation action.',
        mentionIds: [...CONFIG.OWNER_DISCORD_IDS, ...CONFIG.STAFF_DISCORD_IDS],
        fields: [
            { name: 'Category', value: category, inline: true },
            { name: 'Target Roblox ID', value: targetUserId || 'Not specified', inline: true },
            { name: 'Submitted by', value: `${report.reporterUsername} (#${actorId})`, inline: true },
            { name: 'Subject', value: subject },
            ...reportDetailFields,
        ],
    });
    res.json({ ok: true, report: { id: report.id, status: report.status, createdAt: report.createdAt } });
});

app.post('/api/support-panel/end-session', requireToken, requireSupport, (req, res) => {
    const body = req.body || {};
    const userId = String(body.userId || '').trim();
    const durationMinutes = Number(body.durationMinutes);
    const reason = cleanStr(body.reason, 300);
    if (!isDigits(userId)) return res.status(400).json({ ok: false, error: 'Target Roblox ID must be numeric.' });
    if (![5, 15, 60, 1440].includes(durationMinutes)) return res.status(400).json({ ok: false, error: 'Choose a 5-minute, 15-minute, 1-hour, or 24-hour session pause.' });
    if (reason.length < 8) return res.status(400).json({ ok: false, error: 'Enter a short reason (at least 8 characters).' });
    if (isProtectedStaffIdentity(userId, null)) return res.status(403).json({ ok: false, error: 'Support cannot end a configured staff member’s session.' });
    const active = presence.has(userId) || [...issued.values()].some(session => session.userId === userId && now() - session.issuedAt <= 10 * 60 * 1000);
    if (!active) return res.status(404).json({ ok: false, error: 'No active Scorp session was found for that account.' });

    const until = now() + durationMinutes * 60 * 1000;
    supportRestrictions[userId] = {
        until,
        reason,
        actor: String(req.claims.u),
        createdAt: new Date().toISOString(),
    };
    saveSupportRestrictions();
    presence.delete(userId);
    scheduleActiveUsersWebhook();
    recordAccessEvent('support_session_ended', { userId, actor: String(req.claims.u), reason, durationMinutes, until });
    res.json({ ok: true, userId, until: new Date(until).toISOString(), message: 'Scorp was stopped for this account and cannot be loaded again until the pause expires.' });
});

app.get('/api/panel/support/reports', requireToken, requirePanelAdmin, (_req, res) => {
    res.json({ ok: true, reports: supportReports.slice(-50).reverse() });
});

const panelLookupLimiter = new Map();
app.post('/api/panel/resolve-user', requireToken, requireTagManager, async (req, res) => {
    const username = cleanStr((req.body || {}).username, 40).replace(/^@/, '');
    if (!/^[A-Za-z0-9_]{3,20}$/.test(username)) return res.status(400).json({ ok: false, error: 'Enter a Roblox username (3–20 letters, numbers, or underscores).' });
    const t = now();
    const last = panelLookupLimiter.get(req.claims.u) || 0;
    if (t - last < 1000) return res.status(429).json({ ok: false, error: 'Please wait before looking up another username.' });
    panelLookupLimiter.set(req.claims.u, t);
    try {
        const response = await fetch('https://users.roblox.com/v1/usernames/users', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usernames: [username], excludeBannedUsers: false }),
            signal: AbortSignal.timeout(8000),
        });
        if (!response.ok) return res.status(502).json({ ok: false, error: 'Roblox username lookup is temporarily unavailable.' });
        const data = await response.json();
        const user = Array.isArray(data.data) && data.data.find(entry => String(entry.name || '').toLowerCase() === username.toLowerCase());
        if (!user || !isDigits(String(user.id))) return res.status(404).json({ ok: false, error: `No Roblox account found for @${username}.` });
        res.json({ ok: true, user: { userId: String(user.id), username: cleanStr(user.name, 40), displayName: cleanStr(user.displayName, 40) } });
    } catch (e) {
        console.warn('[panel] Roblox username lookup failed:', e.message);
        res.status(502).json({ ok: false, error: 'Roblox username lookup is temporarily unavailable.' });
    }
});

app.get('/api/panel/active-users', requireToken, requireTagManager, (req, res) => {
    const jobId = cleanStr(req.query.jobId, 64);
    const users = activeUsersSnapshot().filter(user => !jobId || user.jobId === jobId);
    res.json({ ok: true, users });
});

app.get('/api/panel/module', requireToken, requirePanelAdmin, (req, res) => {
    try {
        res.type('text/plain').set('Cache-Control', 'no-store').send(getAdminPanelModule());
    } catch (e) {
        console.error('[panel] could not build authorized module:', e.message);
        res.status(503).json({ ok: false, error: 'Staff panel module is temporarily unavailable.' });
    }
});

app.get('/api/tag-panel/module', requireToken, requireTagManager, (req, res) => {
    try {
        res.type('text/plain').set('Cache-Control', 'no-store').send(fs.readFileSync(TAG_PANEL_FILE, 'utf8'));
    } catch (e) {
        console.error('[tag-panel] could not load authorized module:', e.message);
        res.status(503).json({ ok: false, error: 'Tag management panel is temporarily unavailable.' });
    }
});

app.post('/api/tag-panel/tag', requireToken, requireTagManager, (req, res) => {
    try {
        const b = req.body || {};
        const userId = String(b.userId || '');
        if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
        const role = String(b.role || 'member').toLowerCase();
        if (!['member', 'vip'].includes(role)) throw new tagconfig.TagError('Tag managers can assign only Member or VIP roles.');
        const label = cleanStr(b.label, 24);
        if (!label) throw new tagconfig.TagError('Enter a tag title (max 24 characters).');
        const tier = b.tier;
        if (tier !== 'free' && tier !== 'premium') throw new tagconfig.TagError('Choose free or premium tag access.');
        let tag;
        if (tier === 'free') {
            const presets = b.freePresets;
            if (!presets || typeof presets !== 'object' || Array.isArray(presets)) throw new tagconfig.TagError('Choose free color, font, and effect presets.');
            if (!tagconfig.PRESET_NAMES.includes(presets.colorPreset)
                || !tagconfig.FREE_FONT_PRESET_ORDER.includes(presets.fontPreset)
                || !tagconfig.FREE_EFFECT_PRESET_ORDER.includes(presets.effectPreset)) {
                throw new tagconfig.TagError('Choose only an approved free color, font, and effect preset.');
            }
            setRole(userId, role, label);
            setPaidTagTier(userId, false, b.reason || 'Updated by tag manager', req.who.userId);
            tag = applyFreeTagPresets(userId, presets);
        } else {
            const options = { ...(b.options || {}), label };
            if (!b.options || typeof b.options !== 'object' || Array.isArray(b.options)) throw new tagconfig.TagError('Choose a supported tag design.');
            const managerOptionKeys = new Set([
                'theme', 'primary', 'accentA', 'accentB', 'accentC', 'backgroundColorA', 'backgroundColorB', 'backgroundColorC',
                'nameColor', 'rankFont', 'userFont', 'textSize', 'nameTextSize', 'textAnimation', 'glow', 'pulse', 'spin',
                'particles', 'underlineSweep', 'glitch', 'effects', 'grid', 'logoMotion',
            ]);
            const unsupported = Object.keys(options).find(key => !managerOptionKeys.has(key) && key !== 'label');
            if (unsupported) throw new tagconfig.TagError(`Tag managers cannot edit this option: ${unsupported}.`);
            let candidate = { ...((tags[userId] && tags[userId].overrides) || {}) };
            for (const [key, value] of Object.entries(options)) {
                if (key === 'theme') candidate = { ...candidate, ...tagconfig.themeOverrides(value) };
                else candidate = tagconfig.applyOption(candidate, key, value);
            }
            setRole(userId, role, label);
            setPaidTagTier(userId, true, b.reason || 'Granted by tag manager', req.who.userId);
            tag = setTagOptions(userId, options);
        }
        recordAccessEvent('tag_manager_design', {
            userId,
            username: cleanStr(b.username, 40) || 'Unknown',
            role,
            tier,
            title: label,
            actor: req.who.userId,
        });
        res.json({ ok: true, tag });
    } catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});

// ── Public ──────────────────────────────────────────────────────────────────
app.get('/', (_req, res) => res.type('text/plain').send('ok'));

app.get('/api/health', (_req, res) => {
    const b = getBuild();
    res.json({
        ok: true,
        uptimeSeconds: Math.round(process.uptime()),
        build: b ? { id: b.id, builtAt: b.builtAt, kb: Math.round(b.bytes / 102.4) / 10 } : null,
        releaseChannel: CONFIG.RELEASE_CHANNEL,
        releaseVersion: CONFIG.RELEASE_VERSION,
        releaseNotes: CONFIG.RELEASE_NOTES || null,
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
    const executor = cleanStr(b.executor, 80) || 'Unknown';
    const platform = cleanStr(b.platform, 20) || 'Unknown';
    const jobId = cleanStr(b.jobId, 64) || 'Unknown';
    const placeId = cleanStr(b.placeId, 20) || 'Unknown';
    const ip = clientIp(req);
    const ownerOk = ownerKeyOk(b.ownerKey);
    const who = { userId, username, hwid, ip, ownerOk, nonce: null, executor, platform, jobId, placeId };

    trackIpCorrelation(userId, hwid, ip);

    // Banned people get a harmless stall instead of an error, so they can't tell what happened.
    const decoy = () => res.json({ ok: true, token: null, payload: 'print("Connecting to server..."); task.wait(9e9)', lib: '', hb: 60 });

    if (!ownerOk && activeSupportRestriction(userId)) return decoy();
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

    const build = ensureBuilt();
    if (!build) return res.status(503).json({ ok: false, error: 'payload not built yet' });
    let personalized;
    try { personalized = getPersonalizedBuild(userId, build); }
    catch (e) {
        console.error('[build] personalized payload failed:', e.message);
        return res.status(503).json({ ok: false, error: 'payload personalization failed' });
    }

    const claims = { v: 1, n: nonce, u: userId, nm: username, h: hwid, b: build.id, c: CONFIG.RELEASE_CHANNEL, rv: CONFIG.RELEASE_VERSION, iat: now(), exp: now() + CONFIG.TOKEN_TTL_MS, ok: ownerOk ? 1 : 0 };
    const token = signToken(claims);
    issued.set(nonce, { userId, username, hwid, ip, executor, platform, jobId, placeId, buildId: build.id, releaseChannel: CONFIG.RELEASE_CHANNEL, releaseVersion: CONFIG.RELEASE_VERSION, watermark: personalized.watermark, issuedAt: now(), confirmed: !!b.resume, alerted: false, ownerOk });
    rememberUser(userId, username, !b.resume);
    scheduleActiveUsersWebhook();

    if (b.resume) return res.json({ ok: true, token, hb: CONFIG.HEARTBEAT_SECONDS, build: build.id, watermark: personalized.watermark, releaseChannel: CONFIG.RELEASE_CHANNEL, releaseVersion: CONFIG.RELEASE_VERSION });

    res.json({ ok: true, token, payload: personalized.code, lib: getLib(), hb: CONFIG.HEARTBEAT_SECONDS, build: build.id, watermark: personalized.watermark, releaseChannel: CONFIG.RELEASE_CHANNEL, releaseVersion: CONFIG.RELEASE_VERSION, releaseNotes: CONFIG.RELEASE_NOTES || null });
});

app.post('/api/heartbeat', requireToken, (req, res) => {
    const b = req.body || {};
    const banned = handleFlags(req.who, b.flags, 'heartbeat');
    if (banned) return res.status(403).json({
        ok: false,
        revoked: true,
        message: 'This Scorp session was revoked after a blacklist or anti-tamper check triggered.',
    });
    markUserActive(req.who);
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
    markUserActive(req.who, {
        displayName: cleanStr(b.displayName, 32),
        jobId,
        placeId: cleanStr(b.placeId, 20),
    });

    const users = [];
    for (const p of presence.values()) {
        if (t - p.lastSeen > CONFIG.PRESENCE_TTL_MS) continue;
        if (p.userId !== req.who.userId && (!jobId || p.jobId !== jobId)) continue;
        users.push({ userId: Number(p.userId), username: p.username, displayName: p.displayName, ...publicTagFor(p.userId) });
        if (users.length >= 100) break;
    }
    res.json({ ok: true, users });
});

app.post('/api/nametags/leave', requireToken, (req, res) => {
    if (presence.delete(req.who.userId)) scheduleActiveUsersWebhook();
    res.json({ ok: true });
});

// ── Self-service free tag editor ────────────────────────────────────────────
// The in-game flow mints a short-lived link to GET /tag. This editor and its
// session API accept only named free presets; admin/Discord tools retain the
// full design controls. The link carries just enough auth for that player —
// never the admin key.
const editorCodes = new Map(); // code -> { userId, username, expiresAt }
const EDITOR_LINK_TTL_MS = 15 * 60 * 1000;

function mintEditorCode(userId, username) {
    const t = now();
    if (editorCodes.size > 2000) for (const [c, v] of editorCodes) if (v.expiresAt < t) editorCodes.delete(c);
    const code = crypto.randomBytes(16).toString('base64url');
    editorCodes.set(code, { userId: String(userId), username: username || 'Unknown', expiresAt: t + EDITOR_LINK_TTL_MS });
    return code;
}

function requireEditorCode(req, res, next) {
    const v = editorCodes.get(req.params.code);
    if (!v || v.expiresAt < now()) return res.status(410).json({ ok: false, error: 'This link expired — reopen the editor from the game.' });
    v.expiresAt = now() + EDITOR_LINK_TTL_MS; // sliding expiry while they're actively editing
    req.editorUserId = v.userId;
    req.editorUsername = v.username;
    next();
}

const editorLinkLimiter = rateLimit({ windowMs: 60_000, max: 12, name: 'editor-link' });
app.post('/api/nametags/editor-link', editorLinkLimiter, requireToken, (req, res) => {
    const code = mintEditorCode(req.who.userId, req.who.username);
    // fragment (#), not a query string, so the code never shows up in server access logs or a Referer header
    res.json({ ok: true, url: `${publicBase(req)}/tag#${code}`, expiresInSeconds: Math.round(EDITOR_LINK_TTL_MS / 1000) });
});

app.get('/tag', (_req, res) => res.sendFile(path.join(ROOT, 'public', 'tag-editor.html')));

app.get('/api/tag-session/:code', requireEditorCode, (req, res) => {
    const premium = !!(paidTags[req.editorUserId] && paidTags[req.editorUserId].enabled);
    res.json({
        ok: true,
        username: req.editorUsername,
        premium,
        options: {
            defaults: tagconfig.DEFAULTS, rolePresets: tagconfig.ROLE_PRESETS, colorKeys: tagconfig.COLOR_KEYS,
            colorPresets: tagconfig.PRESET_NAMES, colorPresetValues: tagconfig.COLOR_PRESETS,
            freeFontPresets: tagconfig.FREE_FONT_PRESETS, freeFontPresetOrder: tagconfig.FREE_FONT_PRESET_ORDER,
            freeEffectPresets: tagconfig.FREE_EFFECT_PRESETS, freeEffectPresetOrder: tagconfig.FREE_EFFECT_PRESET_ORDER,
            ...(premium ? { fonts: tagconfig.FONTS, animations: tagconfig.ANIMATIONS, groups: tagconfig.GROUPS } : {}),
        },
        tag: tagInfo(req.editorUserId),
    });
});
app.put('/api/tag-session/:code', requireEditorCode, (req, res) => {
    try {
        if (paidTags[req.editorUserId] && paidTags[req.editorUserId].enabled) {
            const options = (req.body || {}).options;
            if (!options || typeof options !== 'object' || Array.isArray(options)) throw new tagconfig.TagError('Choose at least one premium tag option.');
            const premiumKeys = new Set([
                ...tagconfig.GROUPS.text,
                ...tagconfig.GROUPS.colors,
                ...tagconfig.GROUPS.effects,
                ...tagconfig.GROUPS.layout,
                'theme',
            ]);
            const unsupported = Object.keys(options).find(key => !premiumKeys.has(key));
            if (unsupported) throw new tagconfig.TagError(`That option isn't available in premium tag editing: ${unsupported}.`);
            res.json({ ok: true, tag: setTagOptions(req.editorUserId, options) });
        } else {
            res.json({ ok: true, tag: applyFreeTagPresets(req.editorUserId, req.body) });
        }
    }
    catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.delete('/api/tag-session/:code', requireEditorCode, (req, res) => {
    try {
        res.json({ ok: true, tag: resetTag(req.editorUserId, req.query.option ? String(req.query.option) : undefined) });
    }
    catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.post('/api/tag-session/:code/preset', requireEditorCode, (req, res) => {
    try {
        if (paidTags[req.editorUserId] && paidTags[req.editorUserId].enabled) {
            res.json({ ok: true, tag: applyPreset(req.editorUserId, (req.body || {}).name) });
        } else {
            res.json({ ok: true, tag: applyFreeTagPresets(req.editorUserId, {
                colorPreset: (req.body || {}).name,
                fontPreset: 'Classic',
                effectPreset: 'Classic Glow',
            }) });
        }
    }
    catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.get('/api/tag-session/:code/export', requireEditorCode, (req, res) => {
    try { res.json({ ok: true, ...exportTag(req.editorUserId) }); }
    catch (e) { res.status(400).json({ ok: false, error: e.message }); }
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

    // Build userId → issued-session lookup for enriching presence records
    const issuedByUser = new Map();
    for (const s of issued.values()) issuedByUser.set(s.userId, s);

    res.json({
        issuedTracked: issued.size,
        unconfirmed: pending.length,
        online: live.length,
        users: live.map(p => {
            const s = issuedByUser.get(p.userId) || {};
            return {
                userId: p.userId,
                username: p.username,
                jobId: p.jobId,
                placeId: p.placeId || null,
                executor: s.executor || 'Unknown',
                platform: s.platform || 'Unknown',
                buildId: s.buildId || null,
                watermark: s.watermark || null,
                joinedAgo: s.issuedAt ? Math.round((t - s.issuedAt) / 1000) : null,
                ...roleFor(p.userId),
            };
        }),
    });
});

function activeUsersSnapshot() {
    const t = now();
    return [...presence.values()]
        .filter(p => t - p.lastSeen <= CONFIG.PRESENCE_TTL_MS)
        .map(p => ({
            userId: p.userId,
            username: p.username,
            displayName: p.displayName,
            placeId: p.placeId || null,
            jobId: p.jobId || null,
            lastSeen: p.lastSeen,
            firstSeen: p.firstSeen,
            sessions: p.sessions,
            executor: p.executor || 'Unknown',
            platform: p.platform || 'Unknown',
            ...roleFor(p.userId),
        }))
        .sort((a, b) => a.username.localeCompare(b.username));
}

const savedActiveWebhook = readJson(ACTIVE_WEBHOOK_FILE, {});
let activeWebhookMessageId = savedActiveWebhook && typeof savedActiveWebhook === 'object' ? savedActiveWebhook.messageId || null : null;
let activeWebhookSignature = null;
let activeWebhookTimer = null;
let activeWebhookBusy = false;

function escapeDiscordText(value) {
    return cleanStr(value, 100).replace(/@/g, '@\u200b').replace(/[\\`*_{}\[\]()#+\-.!|>~]/g, '\\$&');
}

function activeUsersWebhookBody(users) {
    const knownIds = Object.keys(knownUsers);
    const totalSessions = knownIds.reduce((total, id) => total + (Number(knownUsers[id]?.sessions) || 0), 0);
    const rows = [];
    for (const user of users) {
        const name = escapeDiscordText(user.displayName || user.username || 'Unknown');
        const id = cleanStr(user.userId, 24);
        const client = `${escapeDiscordText(user.executor)} · ${escapeDiscordText(user.platform)}`;
        const place = cleanStr(user.placeId, 24) || 'unknown';
        const firstSeen = Number(user.firstSeen) || now();
        const sessions = Number(user.sessions) || 0;
        const line = `🟢 **${name}** · \`${id}\` · ${client} · place \`${place}\` · tracked since <t:${Math.floor(firstSeen / 1000)}:D> · ${sessions} run${sessions === 1 ? '' : 's'}`;
        if (rows.join('\n').length + line.length + 1 > 3600) break;
        rows.push(line);
    }
    const omitted = users.length - rows.length;
    let description = users.length ? rows.join('\n') : 'No active users right now. The roster will update automatically when a session checks in.';
    if (omitted > 0) description += `\n…and ${omitted} more active account${omitted === 1 ? '' : 's'}.`;
    return {
        allowed_mentions: { parse: [] },
        embeds: [{
            title: '🟢 Scorp · Live Users',
            description: clip(description, 3900),
            color: 0x36c98f,
            fields: [
                { name: 'Active now', value: String(users.length), inline: true },
                { name: 'Known accounts', value: String(knownIds.length), inline: true },
                { name: 'Recorded sessions', value: String(totalSessions), inline: true },
            ],
            timestamp: new Date().toISOString(),
            footer: { text: 'Scorp · Live presence · discord.gg/scorp' },
        }],
    };
}

function activeUsersWebhookState() {
    const users = activeUsersSnapshot();
    const signature = JSON.stringify({
        knownCount: Object.keys(knownUsers).length,
        totalSessions: Object.values(knownUsers).reduce((total, user) => total + (Number(user && user.sessions) || 0), 0),
        users: users.map(({ userId, username, displayName, placeId, jobId, firstSeen, sessions, executor, platform }) =>
            ({ userId, username, displayName, placeId, jobId, firstSeen, sessions, executor, platform })),
    });
    return { users, signature };
}

async function deliverActiveUsersWebhook(body, attempt = 0) {
    const editing = !!activeWebhookMessageId;
    const url = editing ? webhookMessageUrl(activeWebhookMessageId) : webhookCreateUrl();
    try {
        const res = await fetch(url, {
            method: editing ? 'PATCH' : 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(10000),
        });
        if (res.status === 429 && attempt < 3) {
            const data = await res.json().catch(() => ({}));
            await sleep((Number(data.retry_after) || 1) * 1000 + 250);
            return deliverActiveUsersWebhook(body, attempt + 1);
        }
        if (editing && res.status === 404) {
            activeWebhookMessageId = null;
            try { fs.unlinkSync(ACTIVE_WEBHOOK_FILE); } catch { /* already absent */ }
            return deliverActiveUsersWebhook(body, attempt + 1);
        }
        if (!res.ok) {
            const text = await res.text().catch(() => '');
            webhook.failed++;
            webhook.lastError = `HTTP ${res.status}: ${clip(text, 160)}`;
            console.error(`[webhook] live roster update failed: ${webhook.lastError}`);
            return false;
        }
        if (!editing) {
            const message = await res.json().catch(() => null);
            if (!message || !message.id) {
                webhook.failed++;
                webhook.lastError = 'Discord did not return a message id for the live roster';
                console.error(`[webhook] ${webhook.lastError}`);
                return false;
            }
            activeWebhookMessageId = String(message.id);
            try { writeJsonAtomic(ACTIVE_WEBHOOK_FILE, { messageId: activeWebhookMessageId }); }
            catch (e) { console.error('[webhook] could not persist live roster message id:', e.message); }
        }
        webhook.sent++;
        webhook.lastOkAt = new Date().toISOString();
        return true;
    } catch (e) {
        webhook.failed++;
        webhook.lastError = e.message;
        console.error('[webhook] live roster request failed:', e.message);
        return false;
    }
}

async function refreshActiveUsersWebhook() {
    if (!CONFIG.DISCORD_WEBHOOK) return;
    if (activeWebhookBusy) { scheduleActiveUsersWebhook(); return; }
    activeWebhookBusy = true;
    try {
        const { users, signature } = activeUsersWebhookState();
        if (activeWebhookMessageId && signature === activeWebhookSignature) return;
        if (await deliverActiveUsersWebhook(activeUsersWebhookBody(users))) activeWebhookSignature = signature;
        else {
            const retryTimer = setTimeout(scheduleActiveUsersWebhook, 30000);
            retryTimer.unref();
        }
    } finally {
        activeWebhookBusy = false;
    }
}

function scheduleActiveUsersWebhook() {
    if (!CONFIG.DISCORD_WEBHOOK || activeWebhookTimer) return;
    activeWebhookTimer = setTimeout(() => {
        activeWebhookTimer = null;
        refreshActiveUsersWebhook();
    }, 5000);
    activeWebhookTimer.unref();
}

// Executor usage stats across all currently-tracked issued sessions
app.get('/api/admin/executor-stats', (_req, res) => {
    const counts = {};
    const platforms = {};
    for (const s of issued.values()) {
        const exe = s.executor || 'Unknown';
        const plat = s.platform || 'Unknown';
        counts[exe] = (counts[exe] || 0) + 1;
        platforms[plat] = (platforms[plat] || 0) + 1;
    }
    // Also tally from history so stats survive session expiry
    for (const s of sessionHistory) {
        const exe = s.executor || 'Unknown';
        const plat = s.platform || 'Unknown';
        counts[exe] = (counts[exe] || 0) + 1;
        platforms[plat] = (platforms[plat] || 0) + 1;
    }
    const executors = Object.entries(counts)
        .sort((a, b) => b[1] - a[1])
        .map(([name, total]) => ({ name, total }));
    res.json({ executors, platforms, totalSessions: Object.values(counts).reduce((a, b) => a + b, 0) });
});

// Recent session history (last SESSION_HISTORY_MAX entries)
app.get('/api/admin/history', (req, res) => {
    const limit = Math.min(Number(req.query.limit) || 50, CONFIG.SESSION_HISTORY_MAX);
    const slice = sessionHistory.slice(-limit).reverse(); // newest first
    res.json({
        total: sessionHistory.length,
        limit,
        sessions: slice.map(s => ({
            userId: s.userId,
            username: s.username,
            executor: s.executor || 'Unknown',
            platform: s.platform || 'Unknown',
            buildId: s.buildId || null,
            watermark: s.watermark || null,
            ip: s.ip,
            hwid: s.hwid,
            issuedAt: s.issuedAt,
            endedAt: s.endedAt,
            durationSeconds: s.endedAt && s.issuedAt ? Math.round((s.endedAt - s.issuedAt) / 1000) : null,
            confirmed: s.confirmed,
            ownerOk: s.ownerOk,
        })),
    });
});

app.get('/api/admin/watermarks/:marker', (req, res) => {
    const marker = cleanStr(req.params.marker, 32);
    const session = [...issued.values(), ...sessionHistory].find(s => s.watermark === marker);
    if (!session) return res.status(404).json({ found: false });
    res.json({
        found: true,
        userId: session.userId,
        username: session.username,
        buildId: session.buildId || null,
        watermark: session.watermark,
        issuedAt: session.issuedAt || null,
        endedAt: session.endedAt || null,
    });
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

function blacklistIdentity({ userId, hwid, username, reason, permanent, durationSeconds, actor = 'admin', ownerAuthorized = false }) {
    userId = userId == null ? '' : String(userId);
    hwid = cleanStr(hwid, 200);
    if ((!userId || !isDigits(userId)) && !hwid) throw new Error('Provide a numeric userId and/or HWID. IP-only blacklisting is disabled.');
    if (!ownerAuthorized && isProtectedStaffIdentity(userId, hwid)) {
        throw new Error('This account is protected staff. Only an owner-authorized action can blacklist configured staff.');
    }
    let customDurationMs = null;
    if (durationSeconds !== undefined && durationSeconds !== null && durationSeconds !== '') {
        const seconds = Number(durationSeconds);
        if (!Number.isSafeInteger(seconds) || seconds < 60 || seconds > 365 * 24 * 60 * 60) {
            throw new Error('Custom ban duration must be a whole number of seconds between 60 and 31536000.');
        }
        if (permanent === true) throw new Error('Choose either a custom duration or a permanent blacklist, not both.');
        customDurationMs = seconds * 1000;
    }
    const root = linkIdentity(userId && isDigits(userId) ? userId : null, hwid || null);
    if (!root) throw new Error('Could not resolve a blacklist identity.');
    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    const forever = permanent === true;
    const tier = BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.permanent = forever || (customDurationMs === null && tier === null);
    g.bannedUntil = g.permanent ? null : now() + (customDurationMs === null ? tier : customDurationMs);
    const cleanReason = cleanStr(reason, 500) || 'Manual staff blacklist';
    const entry = {
        username: cleanStr(username, 80) || 'Manual Entry',
        userId: userId && isDigits(userId) ? userId : null,
        hwid: hwid || null,
        ip: null,
        reason: cleanReason,
        source: 'manual',
        actor: cleanStr(actor, 80) || 'admin',
        ownerAuthorized: !!ownerAuthorized,
        durationSeconds: g.permanent ? null : (customDurationMs === null ? tier / 1000 : customDurationMs / 1000),
        date: new Date().toISOString(),
    };
    g.reasons.push(entry);
    g.reasons = g.reasons.slice(-30);
    groups[root] = g;
    saveOffenses();
    recordAccessEvent('manual_blacklist', { ...entry, permanent: g.permanent, bannedUntil: g.bannedUntil });
    return { root, ...banInfo(root), latestReason: entry };
}

function unblacklistIdentity(target, actor = 'admin') {
    target = String(target || '').trim();
    if (!target) throw new Error('Missing target (userId or HWID).');
    const candidates = [`uid:${target}`, `hwid:${target}`].filter(id => id in parent);
    if (!candidates.length) return false;
    const root = find(candidates[0]);
    const g = groups[root];
    if (!g) return false;
    g.permanent = false;
    g.bannedUntil = null;
    strikes.delete(root);
    saveOffenses();
    recordAccessEvent('blacklist_remove', { target, root, actor: cleanStr(actor, 80) || 'admin' });
    return true;
}

function editBlacklistReason(target, reason, actor = 'admin') {
    target = String(target || '').trim();
    reason = cleanStr(reason, 500);
    if (!target || !reason) throw new Error('Provide a target and a non-empty reason (max 500 characters).');
    const candidates = [`uid:${target}`, `hwid:${target}`].filter(id => id in parent);
    if (!candidates.length) return false;
    const root = find(candidates[0]);
    const g = groups[root];
    const last = g && g.reasons && g.reasons[g.reasons.length - 1];
    if (!last) return false;
    const previousReason = last.reason || '';
    last.reason = reason;
    last.reasonEditedAt = new Date().toISOString();
    last.reasonEditedBy = cleanStr(actor, 80) || 'admin';
    saveOffenses();
    recordAccessEvent('blacklist_reason_edit', { target, root, previousReason, reason, actor: last.reasonEditedBy });
    return { root, reason };
}

function moderationSnapshot() {
    const blacklisted = Object.keys(groups).map(root => ({
        identities: Object.keys(parent).filter(id => find(id) === root),
        ...banInfo(root),
        latestReason: (groups[root].reasons || []).slice(-1)[0] || null,
    }));
    const allowlisted = Object.entries(access.allowlist).map(([userId, value]) => ({ userId, ...value }));
    return { blacklisted, allowlisted };
}

app.post('/api/admin/blacklist', (req, res) => {
    try { res.json({ success: true, entry: blacklistIdentity({ ...(req.body || {}), ownerAuthorized: ownerKeyOk(req.get('x-owner-key')) }) }); }
    catch (e) { res.status(400).json({ error: e.message }); }
});

app.post('/api/admin/unblacklist', (req, res) => {
    try {
        const target = String((req.body || {}).target || '');
        if (!unblacklistIdentity(target)) return res.status(404).json({ success: false, message: `Active blacklist not found for ${target || 'target'}.` });
        res.json({ success: true, message: `Lifted blacklist for ${target}` });
    } catch (e) { res.status(400).json({ success: false, error: e.message }); }
});

app.get('/api/admin/access', (_req, res) => res.json(moderationSnapshot()));
app.get('/api/admin/access/history', (req, res) => {
    const limit = Math.max(1, Math.min(Number(req.query.limit) || 100, 500));
    res.json({ total: accessHistory.length, events: accessHistory.slice(-limit).reverse() });
});
app.get('/api/admin/overview', (_req, res) => {
    const t = now();
    res.json({
        ok: true,
        service: 'Scorp',
        build: getBuild() && { id: getBuild().id, builtAt: getBuild().builtAt, bytes: getBuild().bytes },
        uptimeSeconds: Math.round(process.uptime()),
        enforcement: { automatic: CONFIG.AUTO_BAN, banScore: CONFIG.BAN_SCORE, strikeThreshold: CONFIG.AUTO_BAN_THRESHOLD, strikeScore: CONFIG.STRIKE_SCORE },
        webhook: { configured: !!CONFIG.DISCORD_WEBHOOK, sent: webhook.sent, failed: webhook.failed, lastError: webhook.lastError, lastOkAt: webhook.lastOkAt },
        usersOnline: [...presence.values()].filter(p => t - p.lastSeen <= CONFIG.PRESENCE_TTL_MS).length,
        sessions: { tracked: issued.size, unconfirmed: [...issued.values()].filter(s => !s.confirmed).length },
        moderation: { ...moderationSnapshot(), recentEvents: accessHistory.slice(-10).reverse() },
        paidTags: Object.keys(paidTags).length,
    });
});
app.put('/api/admin/access/allowlist/:userId', (req, res) => {
    try {
        const userId = req.params.userId;
        setAllowlisted(userId, req.body && req.body.allowed !== false, req.body && req.body.reason, req.body && req.body.actor);
        res.json({ success: true, userId, allowlisted: allowlistHas(userId), entry: access.allowlist[userId] || null });
    } catch (e) { res.status(400).json({ success: false, error: e.message }); }
});
app.put('/api/admin/blacklist/reason', (req, res) => {
    try {
        const result = editBlacklistReason(req.body && req.body.target, req.body && req.body.reason, req.body && req.body.actor);
        if (!result) return res.status(404).json({ success: false, error: 'Blacklist entry not found.' });
        res.json({ success: true, ...result });
    } catch (e) { res.status(400).json({ success: false, error: e.message }); }
});

// In-game admin panel API. Authentication requires a valid session AND a server-configured
// Roblox admin ID; a client-side UI flag alone can never authorize a request.
app.get('/api/panel/overview', requireToken, requirePanelAdmin, (_req, res) => {
    const t = now();
    res.json({
        ok: true,
        service: 'Scorp',
        build: getBuild() && { id: getBuild().id, builtAt: getBuild().builtAt },
        usersOnline: [...presence.values()].filter(p => t - p.lastSeen <= CONFIG.PRESENCE_TTL_MS).length,
        sessions: { tracked: issued.size, unconfirmed: [...issued.values()].filter(s => !s.confirmed).length },
        access: moderationSnapshot(),
        history: accessHistory.slice(-25).reverse(),
        activeWatermarks: [...issued.values()].filter(s => s.watermark).map(s => ({ userId: s.userId, watermark: s.watermark, buildId: s.buildId })),
        paidTags: Object.entries(paidTags).filter(([, v]) => v && v.enabled).map(([userId, value]) => ({ userId, ...value })),
        tagCount: Object.keys(tags).length,
        webhook: { configured: !!CONFIG.DISCORD_WEBHOOK, sent: webhook.sent, failed: webhook.failed },
    });
});

app.post('/api/panel/blacklist', requireToken, requirePanelAdmin, (req, res) => {
    try {
        const ownerAuthorized = String(req.claims.u) === CONFIG.OWNER_USER_ID && !!req.claims.ok;
        res.json({ ok: true, entry: blacklistIdentity({ ...(req.body || {}), actor: req.who.userId, ownerAuthorized }) });
    }
    catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.post('/api/panel/unblacklist', requireToken, requirePanelAdmin, (req, res) => {
    try {
        const target = req.body && req.body.target;
        if (!unblacklistIdentity(target, req.who.userId)) return res.status(404).json({ ok: false, error: 'Active blacklist not found.' });
        res.json({ ok: true });
    } catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.post('/api/panel/allowlist', requireToken, requirePanelAdmin, (req, res) => {
    try {
        const b = req.body || {};
        const changed = setAllowlisted(b.userId, b.allowed === true, b.reason, req.who.userId);
        res.json({ ok: true, changed, allowlisted: allowlistHas(b.userId) });
    } catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.post('/api/panel/blacklist/reason', requireToken, requirePanelAdmin, (req, res) => {
    try {
        const result = editBlacklistReason(req.body && req.body.target, req.body && req.body.reason, req.who.userId);
        if (!result) return res.status(404).json({ ok: false, error: 'Blacklist entry not found.' });
        res.json({ ok: true, ...result });
    } catch (e) { res.status(400).json({ ok: false, error: e.message }); }
});
app.post('/api/panel/tag', requireToken, requirePanelAdmin, (req, res) => {
    try {
        const b = req.body || {};
        const userId = String(b.userId || '');
        if (!isDigits(userId)) throw new tagconfig.TagError('userId must be numeric.');
        if (b.role !== undefined && !ROLES.includes(String(b.role).toLowerCase())) {
            throw new tagconfig.TagError(`role must be one of: ${ROLES.join(', ')}`);
        }
        // Validate every design field before writing role, entitlement, or tag data.
        if (b.options && typeof b.options === 'object' && !Array.isArray(b.options)) {
            let candidate = { ...((tags[userId] && tags[userId].overrides) || {}) };
            for (const [key, value] of Object.entries(b.options)) {
                if (key === 'theme') candidate = { ...candidate, ...tagconfig.themeOverrides(value) };
                else candidate = tagconfig.applyOption(candidate, key, value);
            }
        }
        if (b.role !== undefined) setRole(userId, String(b.role).toLowerCase(), b.label);
        if (b.tier === 'premium') setPaidTagTier(userId, true, b.reason || 'In-game admin panel', req.who.userId);
        else if (b.tier === 'free') setPaidTagTier(userId, false, b.reason || 'In-game admin panel', req.who.userId);
        if (b.options && typeof b.options === 'object' && !Array.isArray(b.options)) setTagOptions(userId, b.options);
        res.json({ ok: true, tag: tagInfo(userId) });
    } catch (e) { res.status(400).json({ ok: false, error: e.message }); }
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
app.put('/api/admin/tags/:userId/tier', (req, res) => {
    try {
        const enabled = (req.body || {}).tier === 'premium';
        if (!enabled && (req.body || {}).tier !== 'free') return res.status(400).json({ error: 'tier must be free or premium' });
        const premiumTag = setPaidTagTier(req.params.userId, enabled, (req.body || {}).reason, (req.body || {}).actor);
        res.json({ success: true, tier: enabled ? 'premium' : 'free', premiumTag, tag: tagInfo(req.params.userId) });
    } catch (e) { res.status(400).json({ error: e.message }); }
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
            ownerDiscordIds: CONFIG.OWNER_DISCORD_IDS,
            roleNames: ROLES,
            setRole,
            clearRole,
            getRoles: () => roles,
            tags: {
                info: tagInfo, set: setTagOptions, reset: resetTag, copy: copyTag, list: () => tags,
                import: importTag, export: exportTag, preset: applyPreset,
                tier: (userId, tier, reason, actor) => {
                    if (tier !== 'free' && tier !== 'premium') throw new tagconfig.TagError('tier must be free or premium');
                    setPaidTagTier(userId, tier === 'premium', reason, actor);
                    return tagInfo(userId);
                },
            },
            access: {
                blacklist: blacklistIdentity,
                unblacklist: unblacklistIdentity,
                allow: (userId, reason, actor) => setAllowlisted(userId, true, reason, actor),
                unallow: (userId, actor) => setAllowlisted(userId, false, '', actor),
                editReason: editBlacklistReason,
                snapshot: moderationSnapshot,
                history: limit => ({ total: accessHistory.length, events: accessHistory.slice(-Math.max(1, Math.min(Number(limit) || 100, 500))).reverse() }),
            },
            getActiveUsers: activeUsersSnapshot,
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
        scheduleActiveUsersWebhook();
        startDiscordBotIfConfigured();
    });
    return server;
}

if (require.main === module) start();
module.exports = { app, start, CONFIG };