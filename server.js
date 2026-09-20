const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const Database = require('better-sqlite3');

const app = express();
const port = Number(process.env.PORT || 3000);
const apiKey = process.env.YUNIKU_API_KEY || 'local-development-key';
const database = new Database('yuniku.sqlite');

database.pragma('journal_mode = WAL');
database.exec(`
  CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    username TEXT NOT NULL,
    game_id INTEGER NOT NULL,
    place_id INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    ended_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS roles (
    user_id INTEGER PRIMARY KEY,
    role TEXT NOT NULL DEFAULT 'member',
    label TEXT NOT NULL DEFAULT 'MEMBER',
    updated_at INTEGER NOT NULL
  );
`);

app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '16kb' }));

function requireApiKey(request, response, next) {
  if (request.get('x-api-key') !== apiKey) {
    return response.status(401).json({ error: 'invalid api key' });
  }
  next();
}

function cleanInteger(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 ? number : null;
}

app.get('/api/health', (_request, response) => {
  response.json({ status: 'ok', service: 'yuniku-network' });
});

app.post('/api/session/start', requireApiKey, (request, response) => {
  const { sessionId, userId, username, gameId, placeId } = request.body || {};
  const safeUserId = cleanInteger(userId);
  const safeGameId = cleanInteger(gameId);
  const safePlaceId = cleanInteger(placeId);

  if (typeof sessionId !== 'string' || !sessionId || !safeUserId ||
      typeof username !== 'string' || !username || !safeGameId || !safePlaceId) {
    return response.status(400).json({ error: 'sessionId, userId, username, gameId and placeId are required' });
  }

  const now = Date.now();
  database.prepare(`
    INSERT INTO sessions (session_id, user_id, username, game_id, place_id, started_at, last_seen)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(session_id) DO UPDATE SET last_seen = excluded.last_seen, ended_at = NULL
  `).run(sessionId, safeUserId, username.slice(0, 64), safeGameId, safePlaceId, now, now);

  response.status(201).json({ ok: true, role: getRole(safeUserId) });
});

app.post('/api/session/heartbeat', requireApiKey, (request, response) => {
  const { sessionId } = request.body || {};
  if (typeof sessionId !== 'string' || !sessionId) {
    return response.status(400).json({ error: 'sessionId is required' });
  }

  const result = database.prepare(
    'UPDATE sessions SET last_seen = ?, ended_at = NULL WHERE session_id = ?'
  ).run(Date.now(), sessionId);

  response.json({ ok: result.changes === 1 });
});

app.post('/api/session/end', requireApiKey, (request, response) => {
  const { sessionId } = request.body || {};
  if (typeof sessionId !== 'string' || !sessionId) {
    return response.status(400).json({ error: 'sessionId is required' });
  }

  const result = database.prepare(
    'UPDATE sessions SET ended_at = ?, last_seen = ? WHERE session_id = ?'
  ).run(Date.now(), Date.now(), sessionId);

  response.json({ ok: result.changes === 1 });
});

app.get('/api/roles/:userId', requireApiKey, (request, response) => {
  const userId = cleanInteger(request.params.userId);
  if (!userId) return response.status(400).json({ error: 'invalid userId' });
  response.json({ userId, ...getRole(userId) });
});

app.put('/api/roles/:userId', requireApiKey, (request, response) => {
  const userId = cleanInteger(request.params.userId);
  const { role, label } = request.body || {};
  const allowedRoles = new Set(['owner', 'creator', 'admin', 'moderator', 'support', 'vip', 'member']);

  if (!userId || typeof role !== 'string' || !allowedRoles.has(role.toLowerCase())) {
    return response.status(400).json({ error: 'invalid userId or role' });
  }

  const normalizedRole = role.toLowerCase();
  const safeLabel = typeof label === 'string' && label.trim() ? label.trim().slice(0, 24) : normalizedRole.toUpperCase();
  database.prepare(`
    INSERT INTO roles (user_id, role, label, updated_at) VALUES (?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET role = excluded.role, label = excluded.label, updated_at = excluded.updated_at
  `).run(userId, normalizedRole, safeLabel, Date.now());

  response.json({ userId, role: getRole(userId) });
});

app.get('/api/online', requireApiKey, (_request, response) => {
  const cutoff = Date.now() - 90000;
  const sessions = database.prepare(`
    SELECT session_id AS sessionId, user_id AS userId, username, game_id AS gameId, place_id AS placeId, last_seen AS lastSeen
    FROM sessions WHERE last_seen >= ? AND ended_at IS NULL ORDER BY last_seen DESC
  `).all(cutoff);
  response.json({ sessions });
});

function getRole(userId) {
  return database.prepare('SELECT role, label FROM roles WHERE user_id = ?').get(userId) || {
    role: 'member',
    label: 'MEMBER'
  };
}

app.listen(port, () => {
  console.log(`Yuniku network listening at http://localhost:${port}`);
  if (apiKey === 'local-development-key') {
    console.warn('Using the local development API key. Set YUNIKU_API_KEY before exposing this server.');
  }
});
