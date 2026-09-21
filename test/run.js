'use strict';
/**
 * npm test
 *
 * Starts the real server against a fake Discord webhook and checks the whole
 * flow: handshake, anti-tamper alerts, strikes/bans, owner exemption, nametag
 * roster + roles, admin auth, auto-rebuild, and the obfuscator.
 *
 * If a Lua 5.3 with luasocket is on PATH as `texlua`, it also runs the real
 * loader + built payload against the server inside a mocked Roblox (test/lua/).
 */
const http = require('http');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { spawn, spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const obf = require('../obfuscate');
const luaparse = require('luaparse');

let passed = 0, failed = 0;
const failures = [];
function ok(cond, name, extra) {
    if (cond) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; failures.push(name); console.log(`  ✗ ${name}${extra !== undefined ? '  → ' + JSON.stringify(extra) : ''}`); }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
const section = t => console.log(`\n${t}`);

// ── fake Discord ────────────────────────────────────────────────────────────
function startFakeDiscord() {
    const received = [];
    const state = { rateLimitNext: 0 };
    const server = http.createServer((req, res) => {
        if (req.method === 'GET') { res.setHeader('content-type', 'application/json'); return res.end(JSON.stringify({ name: 'fake-hook' })); }
        let body = '';
        req.on('data', d => (body += d));
        req.on('end', () => {
            if (state.rateLimitNext > 0) {
                state.rateLimitNext--;
                res.statusCode = 429;
                res.setHeader('content-type', 'application/json');
                return res.end(JSON.stringify({ retry_after: 0.2 }));
            }
            try { received.push(JSON.parse(body).embeds[0]); } catch { /* ignore */ }
            res.statusCode = 204;
            res.end();
        });
    });
    return new Promise(r => server.listen(0, '127.0.0.1', () => r({ server, received, state, port: server.address().port })));
}
const titles = d => d.received.map(e => e.title);
const has = (d, re) => d.received.some(e => re.test(e.title));
async function waitFor(fn, ms = 6000) {
    const end = Date.now() + ms;
    while (Date.now() < end) { if (await fn()) return true; await sleep(100); }
    return false;
}

// ── server process ──────────────────────────────────────────────────────────
async function startServer(discordPort, extraEnv = {}) {
    const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'scorp-test-'));
    const port = 3200 + Math.floor(Math.random() * 500);
    const env = {
        ...process.env,
        PORT: String(port),
        DATA_DIR: dataDir,
        DISCORD_WEBHOOK: `http://127.0.0.1:${discordPort}/api/webhooks/1/abc`,
        OWNER_USER_ID: '1000',
        OWNER_KEY: 'owner-secret',
        ADMIN_PASSWORD: 'admin-secret',
        SESSION_COOLDOWN_MS: '1200',
        UNCONFIRMED_AFTER_SECONDS: '1',
        WATCHER_INTERVAL_MS: '300',
        ...extraEnv,
    };
    const child = spawn(process.execPath, [path.join(ROOT, 'src', 'server.js')], { env, stdio: ['ignore', 'pipe', 'pipe'] });
    let log = '';
    child.stdout.on('data', d => (log += d));
    child.stderr.on('data', d => (log += d));
    const base = `http://127.0.0.1:${port}`;
    const up = await waitFor(async () => { try { return (await fetch(`${base}/api/health`)).ok; } catch { return false; } }, 10000);
    if (!up) { child.kill(); throw new Error('server did not start:\n' + log); }
    return { child, base, port, dataDir, getLog: () => log, stop: () => child.kill() };
}

async function post(base, url, body, headers = {}) {
    const res = await fetch(base + url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) });
    let json = null; try { json = await res.json(); } catch { /* ignore */ }
    return { status: res.status, json };
}
const bearer = t => ({ authorization: `Bearer ${t}` });
const admin = { 'x-admin-key': 'admin-secret' };

let uidCounter = 7000;
const newUser = (extra = {}) => ({ userId: String(uidCounter++), username: `User${uidCounter}`, hwid: `HWID-${uidCounter}-${Math.random().toString(36).slice(2)}`, ...extra });

// ────────────────────────────────────────────────────────────────────────────
async function testObfuscator() {
    section('Obfuscator');
    const b = (s) => obf.luaStringBytes(s);
    ok(JSON.stringify(b('"a\\n\\065\\x41\\u{48}"')) === JSON.stringify([97, 10, 65, 65, 72]), 'escapes: \\n \\ddd \\xHH \\u{}');
    ok(JSON.stringify(b("'it\\'s'")) === JSON.stringify([...Buffer.from("it's")]), "escaped quote in 'single' string");
    ok(JSON.stringify(b('[[\nline]]')) === JSON.stringify([...Buffer.from('line')]), 'long string drops the first newline');
    ok(JSON.stringify(b('[==[a]]b]==]')) === JSON.stringify([...Buffer.from('a]]b')]), 'long string with = levels');
    ok(JSON.stringify(b('"🏄"')) === JSON.stringify([...Buffer.from('🏄')]), 'emoji become UTF-8 bytes (0-255)');
    let threw = false; try { b('"\\q"'); } catch { threw = true; }
    ok(threw, 'unknown escape fails the build instead of mis-encoding');

    // Round trip: obfuscate a script, decode the tables like Lua would, compare with the AST strings.
    const src = `local ctx = ...\nlocal a = "hello"\nprint"call-syntax"\nlocal t = { ["k e y"] = 'sq"uote', n = [[long\nstring]] }\nlocal function f(x) return x .. "tail" end\nreturn f(a), t, ctx, ""`;
    const out = obf.obfuscateSource(src, 't');
    luaparse.parse(out, { luaVersion: '5.1' });
    ok(true, 'obfuscated output parses');
    ok(!/hello|call-syntax|tail|k e y/.test(out), 'no plaintext strings left');
    ok(/return _0x[0-9a-f]+\(\.\.\.\)$/.test(out), 'wrapper forwards varargs (ctx reaches the payload)');
    const key = out.match(/local (_0x[0-9a-f]+) = \{(\d+(?:,\d+)*)\}\s+local _0x[0-9a-f]+ = \{/);
    const keyBytes = key[2].split(',').map(Number);
    const rows = [...out.matchAll(/\{(\d+(?:,\d+)*)\}/g)].map(m => m[1].split(',').map(Number)).slice(1);
    const decoded = rows.map(r => Buffer.from(r.map((v, i) => v ^ keyBytes[i % keyBytes.length])).toString('utf8'));
    for (const want of ['hello', 'call-syntax', 'k e y', 'sq"uote', 'long\nstring', 'tail']) ok(decoded.includes(want), `decrypts back to ${JSON.stringify(want)}`);

    // Build twice: different random keys each time
    const o1 = obf.obfuscateSource(src, 't'), o2 = obf.obfuscateSource(src, 't');
    ok(o1 !== o2, 'every build uses a fresh key / names');

    // The real project
    const built = obf.build({ write: false });
    ok(built.sources.length >= 2 && built.sources.some(s => s.endsWith('nametags.lua')), 'real build inlines nametags.lua', built.sources);
    ok(!/ScorpTag|\/api\/nametags|Bearer/.test(built.code), 'real payload has no readable endpoints / names');
    let escape = false; try { const p = path.join(obf.SRC_DIR, 'evil.lua'); fs.writeFileSync(p, '--@include ../../etc/passwd\n'); obf.bundle(p); } catch (e) { escape = /escapes src/.test(e.message); } finally { try { fs.unlinkSync(path.join(obf.SRC_DIR, 'evil.lua')); } catch { /* */ } }
    ok(escape, '--@include cannot escape src/');
}

async function testServer(d) {
    const S = await startServer(d.port);
    const { base } = S;
    try {
        section('Startup, health, loader');
        const health = await (await fetch(`${base}/api/health`)).json();
        ok(health.ok && health.build && /^[0-9a-f]{8}$/.test(health.build.id), 'health reports the live build id', health.build);
        ok(health.webhook.configured && health.ownerKeySet, 'health shows webhook + owner key configured');
        ok(await waitFor(() => has(d, /online/)), 'startup ping reached Discord', titles(d));
        const loader = await (await fetch(`${base}/loader.lua`)).text();
        ok(loader.includes('function(...)') && !loader.includes('__SERVER_URL__'), 'loader is served obfuscated with the URL filled in');
        ok(!loader.includes(base), 'server URL is not readable in the loader');
        const pubOverride = await (await fetch(`${base}/loader.lua`, { headers: { 'x-forwarded-proto': 'https' } })).text();
        ok(pubOverride.length > 1000, 'loader endpoint stable under proxy headers');

        section('Session handshake');
        ok((await post(base, '/api/session', { userId: 'abc', username: 'x' })).status === 400, 'rejects a non-numeric userId');
        const u1 = newUser();
        const s1 = await post(base, '/api/session', u1);
        ok(s1.status === 200 && s1.json.token && s1.json.payload.startsWith('local _0x') && s1.json.lib.includes('SCORP UI LIBRARY'), 'returns token + built payload + UI library');
        ok(!s1.json.payload.includes('Placeholder Feature'), 'payload is obfuscated');
        ok((await post(base, '/api/session', u1)).status === 429, 'same identity re-requesting inside the cooldown is refused');
        ok((await post(base, '/api/heartbeat', {})).status === 401, 'heartbeat without a token → 401');
        ok((await post(base, '/api/heartbeat', {}, bearer('x.y'))).status === 401, 'forged token → 401');
        const forged = s1.json.token.replace(/\.[^.]+$/, '.' + 'A'.repeat(43));
        ok((await post(base, '/api/heartbeat', {}, bearer(forged))).status === 401, 'token with a wrong signature → 401');
        ok((await post(base, '/api/heartbeat', { flags: [] }, bearer(s1.json.token))).status === 200, 'valid heartbeat → 200');
        const resumed = await post(base, '/api/session', { ...u1, resume: true });
        ok(resumed.status === 200 && resumed.json.token && !resumed.json.payload, 'resume returns a fresh token only (no payload)');

        section('Anti-tamper → Discord');
        const u2 = newUser();
        const s2 = await post(base, '/api/session', u2);
        const hb1 = await post(base, '/api/heartbeat', { flags: ['H1'] }, bearer(s2.json.token));
        ok(hb1.status === 200, 'a single weak flag (H1) does not ban');
        ok(await waitFor(() => has(d, /Tamper signal \(heartbeat\)/)), 'weak flag still produces a Discord alert', titles(d));
        const alertEmbed = d.received.find(e => /Tamper signal/.test(e.title));
        ok(alertEmbed && alertEmbed.fields.some(f => f.name === 'Codes' && f.value.includes('H1')) && alertEmbed.fields.some(f => f.value.includes(u2.userId)), 'alert names the user and explains the code');

        const u3 = newUser();
        const s3 = await post(base, '/api/session', u3);
        const hb3 = await post(base, '/api/heartbeat', { flags: ['C1', 'H2'] }, bearer(s3.json.token));
        ok(hb3.status === 403 && hb3.json.revoked, 'strong flags (score ≥ 5) → immediate ban, heartbeat answers 403');
        ok(await waitFor(() => has(d, /Offense #1.*1 day/)), 'ban alert reached Discord', titles(d));
        await sleep(1300);
        const s3b = await post(base, '/api/session', u3);
        ok(s3b.status === 200 && s3b.json.token === null && /task\.wait/.test(s3b.json.payload), 'banned user gets the silent decoy, not an error');
        const u3alt = { ...newUser(), hwid: u3.hwid };
        const s3c = await post(base, '/api/session', u3alt);
        ok(s3c.json.token === null, 'same HWID on a new account is still banned (identity linking)');
        const bl = await (await fetch(`${base}/api/admin/blacklist`, { headers: admin })).json();
        ok(bl.totalGroups >= 1, 'admin blacklist lists the ban');
        const un = await post(base, '/api/admin/unblacklist', { target: u3.userId }, admin);
        ok(un.json.success, 'admin can lift the ban');
        await sleep(1300);
        ok((await post(base, '/api/session', u3)).json.token, 'unbanned user connects again');

        section('Two strikes across separate sessions');
        const u4 = newUser();
        const a = await post(base, '/api/session', u4);
        ok((await post(base, '/api/heartbeat', { flags: ['G1'] }, bearer(a.json.token))).status === 200, 'strike 1: alert only');
        await sleep(1300);
        const b2 = await post(base, '/api/session', u4);
        ok((await post(base, '/api/heartbeat', { flags: ['G1'] }, bearer(b2.json.token))).status === 403, 'strike 2 (new session): banned');
        ok((await post(base, '/api/heartbeat', { flags: ['H1', 'evil<script>', 42, null] }, bearer(a.json.token))).status !== 500, 'garbage flags are sanitised, no crash');

        section('Owner key');
        const spoof = { userId: '1000', username: 'Boss', hwid: 'BOSS-HW' };
        const sp = await post(base, '/api/session', { ...spoof, flags: ['C1', 'H2', 'G1'] });
        ok(sp.json.token === null, 'claiming the owner userId WITHOUT the key gets no immunity (banned like anyone)');
        await post(base, '/api/admin/unblacklist', { target: '1000' }, admin);
        await sleep(1300);
        const before = d.received.length;
        const own = await post(base, '/api/session', { ...spoof, hwid: 'BOSS-HW-2', ownerKey: 'owner-secret', flags: ['C1', 'H2', 'G1'] });
        ok(own.status === 200 && own.json.token, 'owner with the key connects even with flags set');
        ok((await post(base, '/api/heartbeat', { flags: ['C1', 'H2', 'G1'] }, bearer(own.json.token))).status === 200, 'owner heartbeat with flags is never banned');
        await sleep(400);
        ok(d.received.length === before, 'and produces no alert');
        const wrongKey = await post(base, '/api/session', { userId: '1001', username: 'Nope', hwid: 'H-nope', ownerKey: 'wrong', flags: ['C1', 'H2'] });
        ok(wrongKey.json.token === null, 'wrong owner key = no exemption');

        section('Payload delivered but never confirmed');
        const u5 = newUser();
        await post(base, '/api/session', u5);
        ok(await waitFor(() => has(d, /never confirmed/), 6000), 'session that never heartbeats is reported as a possible dump', titles(d));
        const u6 = newUser();
        const s6 = await post(base, '/api/session', u6);
        await post(base, '/api/heartbeat', {}, bearer(s6.json.token));
        const countBefore = d.received.filter(e => /never confirmed/.test(e.title)).length;
        await sleep(1800);
        ok(d.received.filter(e => /never confirmed/.test(e.title)).length === countBefore, 'a session that did check in is not reported');

        section('Nametag roster + roles');
        const A = newUser({ userId: '8001', username: 'Alice' }), B = newUser({ userId: '8002', username: 'Bob' }), C = newUser({ userId: '8003', username: 'Carol' });
        const tok = {};
        for (const [k, u] of Object.entries({ A, B, C })) {
            const r = await post(base, '/api/session', u);
            if (!r.json || !r.json.token) console.log(`  (debug) session ${k} response:`, r.status, JSON.stringify(r.json));
            tok[k] = r.json && r.json.token;
            await sleep(20);
        }
        ok((await post(base, '/api/nametags/sync', { jobId: 'J1' })).status === 401, 'sync needs a token');
        ok((await fetch(`${base}/api/admin/roles/8002`, { method: 'PUT', headers: { 'content-type': 'application/json' }, body: '{"role":"support"}' })).status === 403, 'setting a role needs the admin key');
        const put = await fetch(`${base}/api/admin/roles/8002`, { method: 'PUT', headers: { 'content-type': 'application/json', ...admin }, body: JSON.stringify({ role: 'support', label: 'Scorp Trial Support' }) });
        ok(put.status === 200, 'admin can assign a role + custom label');
        ok((await fetch(`${base}/api/admin/roles/8002`, { method: 'PUT', headers: { 'content-type': 'application/json', ...admin }, body: '{"role":"god"}' })).status === 400, 'unknown role rejected');
        await post(base, '/api/nametags/sync', { jobId: 'J1', displayName: 'Bobby' }, bearer(tok.B));
        await post(base, '/api/nametags/sync', { jobId: 'J2', displayName: 'Carol' }, bearer(tok.C));
        const roster = await post(base, '/api/nametags/sync', { jobId: 'J1', displayName: 'Ali' }, bearer(tok.A));
        if (!roster.json || !roster.json.users) console.log('  (debug) roster response:', roster.status, JSON.stringify(roster.json));
        const names = (roster.json.users || []).map(u => u.username).sort();
        ok(JSON.stringify(names) === JSON.stringify(['Alice', 'Bob']), 'roster only contains players from the same Roblox server', names);
        const bob = roster.json.users.find(u => u.username === 'Bob');
        ok(bob.role === 'support' && bob.label === 'Scorp Trial Support' && bob.displayName === 'Bobby' && typeof bob.userId === 'number', 'roles + labels come from the server');
        ok(roster.json.users.find(u => u.username === 'Alice').role === 'member', 'default role is member');
        const boss = await post(base, '/api/session', { userId: '1000', username: 'Boss', hwid: 'BOSS-HW-3', ownerKey: 'owner-secret' });
        const bossSync = await post(base, '/api/nametags/sync', { jobId: 'J1' }, bearer(boss.json.token));
        ok(bossSync.json.users.find(u => u.username === 'Boss').role === 'owner', 'OWNER_USER_ID gets the Owner role by default');
        ok((await post(base, '/api/nametags/sync', { jobId: 'J1' }, bearer(tok.A))).status === 429, 'sync is rate limited per session');
        await post(base, '/api/nametags/leave', {}, bearer(tok.B));
        await sleep(2100);
        const after = await post(base, '/api/nametags/sync', { jobId: 'J1' }, bearer(tok.A));
        ok(!after.json.users.some(u => u.username === 'Bob'), 'leaving removes you from the roster');
        const clientCannotSetRole = await post(base, '/api/nametags/sync', { jobId: 'J1', role: 'owner', label: 'HAX' }, bearer(tok.C));
        ok(!clientCannotSetRole.json.users.some(u => u.label === 'HAX'), 'a client cannot pick its own role');

        section('Admin');
        ok((await fetch(`${base}/api/admin/blacklist`)).status === 403, 'admin routes reject no key');
        ok((await fetch(`${base}/api/admin/blacklist?password=admin-secret`)).status === 403, 'password in the query string is NOT accepted');
        ok((await fetch(`${base}/api/admin/blacklist`, { headers: { authorization: 'Bearer admin-secret' } })).status === 200, 'Authorization: Bearer works');
        const tw = await post(base, '/api/admin/test-webhook', {}, admin);
        ok(tw.status === 200 && tw.json.ok, 'test-webhook endpoint delivers');
        ok(has(d, /Webhook test/), 'test message arrived');
        const sess = await (await fetch(`${base}/api/admin/sessions`, { headers: admin })).json();
        ok(typeof sess.online === 'number', 'sessions overview works');

        section('Discord rate limiting');
        d.state.rateLimitNext = 1;
        const cnt = d.received.length;
        const t2 = await post(base, '/api/admin/test-webhook', {}, admin);
        ok(t2.json.ok && d.received.length === cnt + 1, 'a 429 from Discord is retried and delivered');
        const hh = await (await fetch(`${base}/api/health`)).json();
        ok(hh.webhook.sent > 3 && hh.webhook.failed === 0, 'health counts sent/failed webhook messages', hh.webhook);

        section('Body handling');
        const bad = await fetch(`${base}/api/session`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{oops' });
        ok(bad.status === 400, 'malformed JSON → 400, not a stack trace');
        const big = await fetch(`${base}/api/session`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ x: 'a'.repeat(40000) }) });
        ok(big.status === 400, 'oversized body rejected');
        ok((await fetch(`${base}/nope`)).status === 404, 'unknown route → 404 json');

        section('Rebuilds on change');
        const idBefore = (await (await fetch(`${base}/api/health`)).json()).build.id;
        const file = path.join(ROOT, 'src', 'nametags.lua');
        const original = fs.readFileSync(file);
        try {
            fs.writeFileSync(file, original.toString() + '\n-- touched by test\n');
            const future = new Date(Date.now() + 5000);
            fs.utimesSync(file, future, future);
            await sleep(1700);
            const u7 = newUser();
            await post(base, '/api/session', u7);
            const idAfter = (await (await fetch(`${base}/api/health`)).json()).build.id;
            ok(idAfter !== idBefore, 'editing a source file rebuilds the payload on the next request', { idBefore, idAfter });
        } finally {
            fs.writeFileSync(file, original);
            const past = new Date(); fs.utimesSync(file, past, past);
        }
        return S;
    } catch (e) { S.stop(); throw e; }
}

async function testLua(d, S) {
    const probe = fs.mkdtempSync(path.join(os.tmpdir(), 'scorp-probe-')) + '/p.lua';
    fs.writeFileSync(probe, 'assert(require("socket.http"))');
    const which = spawnSync('texlua', [probe], { encoding: 'utf8' });
    if (which.error || which.status !== 0) { section('Lua end-to-end'); console.log('  (skipped: needs `texlua` / Lua 5.3 with luasocket)', which.stderr || which.error); return; }
    section('Lua end-to-end (real loader + real payload in a mocked Roblox)');
    const run = (scenario, env) => {
        const r = spawnSync('texlua', [path.join(__dirname, 'lua', 'harness.lua'), path.join(__dirname, 'lua', 'scenarios', scenario)], {
            env: { ...process.env, SCORP_URL: S.base, ...env }, encoding: 'utf8', timeout: 60000,
        });
        const line = (r.stdout || '').split('\n').find(l => l.startsWith('RESULT '));
        if (!line) { console.log((r.stderr || r.stdout || '').slice(0, 600)); return null; }
        return JSON.parse(line.slice(7));
    };
    await sleep(1300);
    await post(S.base, '/api/admin/roles/6002', { role: 'support', label: 'Scorp Trial Support' }, admin).catch(() => {});
    await fetch(`${S.base}/api/admin/roles/6002`, { method: 'PUT', headers: { 'content-type': 'application/json', ...admin }, body: JSON.stringify({ role: 'support', label: 'Scorp Trial Support' }) });
    const drew = run('basic.lua', { MY_ID: '6002', MY_NAME: 'Drew', JOB_ID: 'L1', OTHERS: '5001:Tester:Tester' });
    ok(drew && drew.threadErrors === 0 && drew.sawRealLib > 50000, 'client 1 runs loader → payload → real UI library source without errors', drew && drew.warnings);
    const boss = run('basic.lua', { MY_ID: '1000', MY_NAME: 'Boss', MY_DISPLAY: 'The Boss', OWNER_KEY: 'owner-secret', JOB_ID: 'L1', OTHERS: '5001:Tester:Tester,6002:Drew:Drew', HWID: 'LUA-BOSS' });
    ok(boss && boss.tags.some(t => t.owner === 'Boss' && t.title === 'Owner' && t.accent[0] === 255 && t.accent[1] === 196), 'owner sees their own gold Owner tag');
    const tester = run('basic.lua', { MY_ID: '5001', MY_NAME: 'Tester', JOB_ID: 'L1', OTHERS: '6002:Drew:Drew,1000:Boss:The Boss', HWID: 'LUA-T' });
    const byOwner = Object.fromEntries((tester?.tags || []).map(t => [t.owner, t]));
    ok(byOwner.Drew && byOwner.Drew.title === 'Scorp Trial Support' && byOwner.Drew.name === 'Drew' && byOwner.Drew.accent[2] === 255, 'Tester sees Drew’s "Scorp Trial Support" tag (support colours)');
    ok(byOwner.Boss && byOwner.Boss.title === 'Owner' && byOwner.Boss.name === 'The Boss', 'Tester sees the owner’s tag with display name');
    ok(byOwner.Tester && byOwner.Tester.title === 'Member', 'and their own Member tag');
    ok(byOwner.Drew && byOwner.Drew.avatar && byOwner.Drew.avatar.startsWith('rbxthumb'), 'avatar headshot replaces the glyph');

    await sleep(300);
    await run('basic.lua', { MY_ID: '6002', MY_NAME: 'Drew', JOB_ID: 'L2', OTHERS: '5001:Tester:Tester,1000:Boss:Boss', HWID: 'LUA-DREW2' });
    const ctl = run('controls.lua', { MY_ID: '5001', MY_NAME: 'Tester', JOB_ID: 'L2', OTHERS: '6002:Drew:Drew', HWID: 'LUA-T2' });
    ok(ctl && ctl.tagsOff.length === 0 && ctl.tagsOn.length >= 1, 'UI toggle "Show Nametags" removes and restores tags');
    ok(ctl && ctl.noSelf.every(t => t.owner !== 'Tester'), 'UI toggle "Show My Own Tag" hides only your tag');
    ok(ctl && ctl.preview.some(t => t.owner === 'Tester' && t.title === 'VIP'), 'Preview Style shows the VIP look on your own tag');
    ok(ctl && ctl.previewOff.some(t => t.title === 'Member') && ctl.dist === 220, 'preview off + distance slider apply');
    ok(ctl && ctl.afterUnload.length === 0 && ctl.requests.some(r => r.path.includes('/leave')), 'unloading removes every tag and tells the server');
    ok(ctl && ctl.threadErrors === 0 && ctl.warnings.length === 0, 'no Lua errors or warnings during any of it', ctl && ctl.warnings);

    const before = d.received.length;
    const spy1 = run('tamper.lua', { MY_ID: '9101', MY_NAME: 'Snoop', JOB_ID: 'L3', TAMPER: 'spy_global', HWID: 'LUA-SNOOP' });
    ok(spy1 && spy1.requests.some(r => r.path === '/api/heartbeat' && r.status === 200), 'spy-global session: loader still runs first time (1st strike)');
    ok(await waitFor(() => d.received.slice(before).some(e => /Tamper signal/.test(e.title) && e.fields.some(f => f.value.includes('G2')))), 'Discord got a G2 alert from a real loader run', titles(d).slice(before));
    await sleep(1300);
    const spy2 = run('tamper.lua', { MY_ID: '9101', MY_NAME: 'Snoop', JOB_ID: 'L3', TAMPER: 'spy_global', HWID: 'LUA-SNOOP' });
    ok(spy2 && spy2.prints.some(p => /Connecting to server/.test(p)) && spy2.tags.length === 0, 'second run with the same spy → banned → gets the freeze decoy, no tags');
    await sleep(1300);
    const strong = run('tamper.lua', { MY_ID: '9102', MY_NAME: 'Hooker', JOB_ID: 'L3', TAMPER: 'strong', HWID: 'LUA-HOOKER' });
    ok(strong && strong.prints.some(p => /Connecting to server/.test(p)), 'hooked pcall + wrapped request + spy global → banned on the first run');
    ok(await waitFor(() => has(d, /Offense #1/)), 'ban alert in Discord', titles(d).slice(-4));
}

process.on('unhandledRejection', e => { console.error('UNHANDLED REJECTION:', e && e.stack || e); process.exitCode = 1; });
process.on('uncaughtException', e => { console.error('UNCAUGHT EXCEPTION:', e && e.stack || e); process.exitCode = 1; });

(async () => {
    console.log('Scorp test suite');
    await testObfuscator();
    const d = await startFakeDiscord();
    let S;
    try {
        S = await testServer(d);
        await testLua(d, S);
    } finally {
        if (S) S.stop();
        d.server.close();
    }
    console.log(`\n${passed} passed, ${failed} failed`);
    if (failed) { console.log('Failed:\n - ' + failures.join('\n - ')); process.exit(1); }
    process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
