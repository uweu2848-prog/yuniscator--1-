const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();
app.set('trust proxy', true); // needed so req.ip is the real client IP behind Railway/any reverse proxy
app.use(express.json());

// ====================
// CONFIGURATION
// ====================
const DISCORD_WEBHOOK = "YOUR_DISCORD_WEBHOOK_URL_HERE";
const OWNER_USER_ID = "YOUR_ROBLOX_USER_ID"; // Your Roblox User ID so you never blacklist yourself
const ADMIN_PASSWORD = "SecretPassword123";  // Used to authorize admin API actions

// __dirname is src/, but obfuscate.js writes to <project root>/dist/script.lua,
// so both paths need to step up one level to the project root.
const OFFENSES_FILE = path.join(__dirname, '..', 'offenses.json');
const SCRIPT_FILE = path.join(__dirname, '..', 'dist', 'script.lua');

// Auto-blacklist: revoke a user after this many distinct tamper reports
const AUTO_BAN_THRESHOLD = 2;

// Escalating ban durations, in ms, indexed by offense number (1st, 2nd, 3rd, 4th+).
// null = permanent. This is keyed on a *person*, not a single userId or hwid (see
// identityKey/mergeIdentity below), so switching accounts or HWID doesn't reset it
// once the system has linked the identities together.
const DAY = 24 * 60 * 60 * 1000;
const BAN_TIERS = [1 * DAY, 7 * DAY, 30 * DAY, null];


// Rate limit: minimum ms between /api/script fetches per user/HWID
const SCRIPT_FETCH_COOLDOWN_MS = 5000;

// Multi-account correlation: if one IP is seen with more than this many distinct
// userId/HWID combos inside the window, it's flagged as suspicious (NOT auto-banned
// — shared IPs, campus wifi, mobile carriers etc. can trigger false positives, so
// this is for you to review, not to act on automatically).
const SUSPICIOUS_IDENTITY_COUNT = 3;
const SUSPICIOUS_WINDOW_MS = 60 * 60 * 1000; // 1 hour

// In-memory session + rate-limit tracking (fine for a single server instance;
// swap for a real DB/Redis if you scale to multiple instances)
const sessions = new Map();       // sessionId -> { userId, hwid, lastSeen }
const lastFetch = new Map();      // identityKey -> timestamp
const ipIdentities = new Map();   // ip -> Map(identityKey -> firstSeen)
const suspiciousIps = new Map();  // ip -> { identities: [...], flaggedAt }

function identityKey(userId, hwid) {
    return `${userId || 'unknown'}::${hwid || 'unknown'}`;
}

// ====================
// IDENTITY LINKING (union-find over userId / hwid / ip)
// ====================
// Every userId, hwid, and ip we ever see together gets linked into one "person"
// group. That's what makes the ban escalate correctly: someone who gets banned,
// then comes back on a new Roblox account but the same HWID (or the same IP,
// depending on how much you want to link on), is recognized as the same person
// and their offense count carries over instead of resetting to zero.
//
// This does NOT defeat someone who changes account, HWID, AND IP all at once —
// nothing server-side can, since none of those values are cryptographically
// tied to a real person. It closes the easy/lazy bypasses, not a determined one.
let parent = {};   // identifier -> parent identifier
let groups = {};   // rootIdentifier -> { offenseCount, bannedUntil (ms|null), permanent, reasons: [...] }

function find(id) {
    if (!(id in parent)) parent[id] = id;
    if (parent[id] !== id) parent[id] = find(parent[id]); // path compression
    return parent[id];
}

function union(a, b) {
    const ra = find(a), rb = find(b);
    if (ra === rb) return ra;
    // Merge group data onto whichever root survives, keep the worse ban state
    const ga = groups[ra], gb = groups[rb];
    parent[rb] = ra;
    if (ga || gb) {
        const merged = {
            offenseCount: Math.max(ga?.offenseCount || 0, gb?.offenseCount || 0),
            bannedUntil: (ga?.permanent || gb?.permanent) ? null
                : Math.max(ga?.bannedUntil || 0, gb?.bannedUntil || 0),
            permanent: !!(ga?.permanent || gb?.permanent),
            reasons: [...(ga?.reasons || []), ...(gb?.reasons || [])],
        };
        groups[ra] = merged;
        delete groups[rb];
    }
    return ra;
}

// Links the identifiers seen on one request together and returns the group root.
function linkIdentity(userId, hwid, ip) {
    const ids = [];
    if (userId) ids.push(`uid:${userId}`);
    if (hwid) ids.push(`hwid:${hwid}`);
    if (ip) ids.push(`ip:${ip}`);
    if (ids.length === 0) return null;
    let root = find(ids[0]);
    for (let i = 1; i < ids.length; i++) root = union(root, ids[i]);
    return root;
}

function saveOffenses() {
    fs.writeFileSync(OFFENSES_FILE, JSON.stringify({ parent, groups }, null, 4));
}

function loadOffenses() {
    if (fs.existsSync(OFFENSES_FILE)) {
        try {
            const data = JSON.parse(fs.readFileSync(OFFENSES_FILE, 'utf8'));
            parent = data.parent || {};
            groups = data.groups || {};
        } catch (err) {
            console.error("Error reading offenses.json, resetting:", err);
            parent = {}; groups = {};
        }
    } else {
        saveOffenses();
    }
}
loadOffenses();

// True if the group is currently serving a ban (auto-expires tiered bans; permanent never expires)
function isGroupBanned(root) {
    if (!root) return false;
    const g = groups[root];
    if (!g) return false;
    if (g.permanent) return true;
    return !!(g.bannedUntil && g.bannedUntil > Date.now());
}

function banInfo(root) {
    const g = groups[root];
    if (!g) return null;
    return {
        offenseCount: g.offenseCount,
        permanent: !!g.permanent,
        bannedUntil: g.permanent ? null : g.bannedUntil,
        active: isGroupBanned(root),
        reasons: g.reasons.slice(-10), // last 10, file doesn't need to grow forever
    };
}

// Reports-before-ban counter, per person-group, in memory only (doesn't need to
// survive a restart — worst case someone gets one extra freebie report after a reboot)
const tamperCounts = new Map();

// Records a tamper reason against the linked identity group, escalates through
// BAN_TIERS once AUTO_BAN_THRESHOLD reports land on that group, and alerts Discord.
// Never bans OWNER_USER_ID.
async function recordTamper(userId, hwid, ip, reason, username) {
    if (userId && String(userId) === String(OWNER_USER_ID)) return;

    const root = linkIdentity(userId, hwid, ip);
    if (!root) return;

    if (isGroupBanned(root)) return; // already serving a ban, no need to re-count

    const count = (tamperCounts.get(root) || 0) + 1;
    tamperCounts.set(root, count);
    if (count < AUTO_BAN_THRESHOLD) return;
    tamperCounts.set(root, 0);

    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    const tier = BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.permanent = tier === null;
    g.bannedUntil = g.permanent ? null : Date.now() + tier;
    g.reasons.push({
        username: username || "Unknown",
        userId: userId ? String(userId) : null,
        hwid: hwid ? String(hwid) : null,
        ip: ip || null,
        reason: reason || "Unspecified tampering attempt",
        date: new Date().toISOString(),
    });
    groups[root] = g;
    saveOffenses();

    if (DISCORD_WEBHOOK && DISCORD_WEBHOOK !== "YOUR_DISCORD_WEBHOOK_URL_HERE") {
        const durationLabel = g.permanent ? "PERMANENT" :
            ({ [1*DAY]: "1 day", [7*DAY]: "7 days", [30*DAY]: "30 days" }[tier] || `${tier}ms`);
        const embed = {
            embeds: [{
                title: `🚨 Offense #${g.offenseCount} — banned (${durationLabel})`,
                color: 16711680,
                fields: [
                    { name: "Username", value: `\`${username || "Unknown"}\``, inline: true },
                    { name: "User ID", value: `\`${userId || "Unknown"}\``, inline: true },
                    { name: "HWID", value: `\`${hwid || "Unknown"}\``, inline: false },
                    { name: "IP", value: `\`${ip || "Unknown"}\``, inline: false },
                    { name: "Reason", value: reason || "Unspecified", inline: false },
                    { name: "Ban length", value: durationLabel, inline: true },
                ],
                timestamp: new Date().toISOString()
            }]
        };
        try {
            await fetch(DISCORD_WEBHOOK, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(embed)
            });
        } catch (err) {
            console.error("Discord Webhook delivery failed:", err.message);
        }
    }
}

// Tracks which identities have shown up behind which IP, and flags (does not ban)
// an IP juggling more distinct identities than SUSPICIOUS_IDENTITY_COUNT inside
// SUSPICIOUS_WINDOW_MS — a pattern consistent with someone cycling alt accounts
// or spoofed HWIDs to dodge a ban. Review /api/admin/suspicious yourself; this
// is a signal, not a verdict, because shared/dynamic IPs can trigger it too.
function trackIpCorrelation(userId, hwid, ip) {
    if (!ip) return;
    const key = identityKey(userId, hwid);
    const now = Date.now();

    if (!ipIdentities.has(ip)) ipIdentities.set(ip, new Map());
    const seen = ipIdentities.get(ip);
    seen.set(key, now);
    for (const [k, t] of seen) { if (now - t > SUSPICIOUS_WINDOW_MS) seen.delete(k); }

    if (seen.size > SUSPICIOUS_IDENTITY_COUNT) {
        suspiciousIps.set(ip, { identities: [...seen.keys()], flaggedAt: now });
    }
}

// ====================
// PUBLIC CLIENT ROUTES
// ====================

// 1. Loader Endpoint: Serves obfuscated script from dist/script.lua
app.get('/api/script', (req, res) => {
    const userId = req.headers['x-user-id'];
    const hwid = req.headers['x-hwid'];
    const session = req.headers['x-session'];
    const flags = req.headers['x-flags']; // opaque codes from the client's own checks, e.g. "H2,M1"
    const ip = req.ip;

    trackIpCorrelation(userId, hwid, ip);
    const root = linkIdentity(userId, hwid, ip);

    if (isGroupBanned(root)) {
        // Serve a fake freeze script instead of your actual code
        return res.setHeader('Content-Type', 'text/plain').send(`print("Connecting to server..."); task.wait(9e9);`);
    }

    // Rate limit repeated fetches from the same identity (script scraping / reload loops)
    const key = identityKey(userId, hwid);
    const now = Date.now();
    const prevFetch = lastFetch.get(key);
    if (prevFetch && now - prevFetch < SCRIPT_FETCH_COOLDOWN_MS) {
        return res.status(429).send('print("Please wait before reconnecting.");');
    }
    lastFetch.set(key, now);

    // If the loader already reported flags on this request, treat it the same
    // as a tamper report so a single hot-loaded run can't skip escalation.
    if (flags) {
        recordTamper(userId, hwid, ip, `client-reported flags: ${flags}`);
        if (isGroupBanned(root)) {
            return res.setHeader('Content-Type', 'text/plain').send(`print("Connecting to server..."); task.wait(9e9);`);
        }
    }

    if (session) {
        sessions.set(session, { userId: userId ? String(userId) : null, hwid: hwid ? String(hwid) : null, lastSeen: now });
    }

    // Read and serve the real obfuscated code generated by your build pipeline
    if (fs.existsSync(SCRIPT_FILE)) {
        const realScript = fs.readFileSync(SCRIPT_FILE, 'utf8');
        return res.setHeader('Content-Type', 'text/plain').send(realScript);
    } else {
        return res.status(404).send('print("Error: Script payload not found on server.");');
    }
});

// 1b. Heartbeat Endpoint: the running client checks in periodically.
// Returns 403 once the user/HWID/IP group is (or becomes) banned, so the client
// can tear its UI down mid-session instead of waiting for a reload.
app.post('/api/heartbeat', (req, res) => {
    const userId = req.headers['x-user-id'];
    const hwid = req.headers['x-hwid'];
    const session = req.headers['x-session'];
    const ip = req.ip;
    const { flags, score } = req.body || {};

    trackIpCorrelation(userId, hwid, ip);

    if (session && sessions.has(session)) {
        sessions.get(session).lastSeen = Date.now();
    }

    if (Array.isArray(flags) && flags.length > 0) {
        recordTamper(userId, hwid, ip, `heartbeat flags: ${flags.join(',')} (score ${score ?? '?'})`);
    }

    const root = linkIdentity(userId, hwid, ip);
    if (isGroupBanned(root)) {
        return res.status(403).send('revoked');
    }

    res.status(200).send('ok');
});

// 2. Silent Tamper Logging Endpoint
app.post('/api/tamper', async (req, res) => {
    const { userId, hwid, username, reason } = req.body;
    await recordTamper(userId, hwid, req.ip, reason, username);
    // Respond with 200 OK so network loggers don't raise suspicion
    res.status(200).send("OK");
});

// ====================
// ADMIN CONTROL ROUTES
// ====================

// View all banned person-groups:
// GET http://localhost:3000/api/admin/blacklist?password=SecretPassword123
app.get('/api/admin/blacklist', (req, res) => {
    if (req.query.password !== ADMIN_PASSWORD) {
        return res.status(403).json({ error: "Unauthorized" });
    }
    const roots = new Set(Object.keys(groups));
    const entries = [...roots].map(root => {
        const identities = Object.keys(parent).filter(id => find(id) === root);
        return { identities, ...banInfo(root) };
    });
    res.json({ totalGroups: entries.length, groups: entries });
});

// Multi-account / spoofing signal (review, not auto-enforced — see comment on
// trackIpCorrelation above):
// GET http://localhost:3000/api/admin/suspicious?password=SecretPassword123
app.get('/api/admin/suspicious', (req, res) => {
    if (req.query.password !== ADMIN_PASSWORD) {
        return res.status(403).json({ error: "Unauthorized" });
    }
    const flagged = [...suspiciousIps.entries()].map(([ip, data]) => ({ ip, ...data }));
    res.json({ total: flagged.length, flagged });
});

// Lift a ban early (identify by userId, hwid, or ip — any identifier in the group works):
// POST http://localhost:3000/api/admin/unblacklist
// JSON Body: { "password": "SecretPassword123", "target": "ROBLOX_USER_ID_OR_HWID_OR_IP" }
app.post('/api/admin/unblacklist', (req, res) => {
    const { password, target } = req.body;
    if (password !== ADMIN_PASSWORD) {
        return res.status(403).json({ error: "Unauthorized" });
    }
    if (!target) {
        return res.status(400).json({ error: "Missing target ID, HWID, or IP" });
    }

    const candidates = [`uid:${target}`, `hwid:${target}`, `ip:${target}`].filter(id => id in parent);
    if (candidates.length === 0) {
        return res.status(404).json({ success: false, message: `Target ${target} not found.` });
    }

    const root = find(candidates[0]);
    if (groups[root]) {
        groups[root].permanent = false;
        groups[root].bannedUntil = null;
        tamperCounts.set(root, 0);
        saveOffenses();
    }

    res.json({ success: true, message: `Lifted ban for target: ${target}` });
});

// Manually ban someone immediately at a given tier, bypassing AUTO_BAN_THRESHOLD:
// POST http://localhost:3000/api/admin/blacklist
// JSON Body: { "password": "...", "userId": "123", "hwid": "...", "reason": "...", "permanent": true }
app.post('/api/admin/blacklist', (req, res) => {
    const { password, userId, hwid, ip, username, reason, permanent } = req.body;
    if (password !== ADMIN_PASSWORD) {
        return res.status(403).json({ error: "Unauthorized" });
    }
    if (!userId && !hwid && !ip) {
        return res.status(400).json({ error: "Must provide at least userId, hwid, or ip" });
    }

    const root = linkIdentity(userId, hwid, ip);
    const g = groups[root] || { offenseCount: 0, bannedUntil: null, permanent: false, reasons: [] };
    g.offenseCount += 1;
    g.permanent = !!permanent;
    g.bannedUntil = permanent ? null : Date.now() + BAN_TIERS[Math.min(g.offenseCount - 1, BAN_TIERS.length - 1)];
    g.reasons.push({
        username: username || "Manual Entry", userId: userId || null, hwid: hwid || null, ip: ip || null,
        reason: reason || "Manual Administrator Ban", date: new Date().toISOString(),
    });
    groups[root] = g;
    saveOffenses();

    res.json({ success: true, message: "Banned.", entry: banInfo(root) });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));