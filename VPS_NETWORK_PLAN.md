# Project Yuniku - VPS Network Infrastructure Plan

## Overview
Build a VPS-based backend network to track Yuniku script usage across games, enable player role synchronization, and create a centralized hub for script management and statistics.

---

## Architecture

### 1. Backend Server (VPS)
**Technology Stack**: Node.js + Express.js + MongoDB

#### Core Components

**A. Express API Server**
- Port: 3000 (HTTP) / 443 (HTTPS)
- Endpoints structure:
  ```
  /api/auth
  /api/players
  /api/games
  /api/roles
  /api/stats
  /api/webhooks
  ```

**B. WebSocket Server** (Real-time player tracking)
- Separate port: 8080
- Real-time player list sync across clients
- Live game state updates

**C. Database (MongoDB)**
```javascript
// Collections:
// 1. Players
{
  _id: ObjectId,
  userId: number,
  username: string,
  displayName: string,
  role: "owner" | "creator" | "admin" | "moderator" | "support" | "vip" | "member",
  joinedAt: Date,
  lastSeen: Date,
  stats: {
    gamesPlayed: number,
    timeOnline: number,    // seconds
    robloxId: number
  }
}

// 2. Games
{
  _id: ObjectId,
  gameId: number,
  gameName: string,
  creatorId: number,
  currentPlayers: [userId],
  playersOnline: number,
  lastActivity: Date
}

// 3. Roles & Permissions
{
  _id: ObjectId,
  userId: number,
  role: string,
  assignedBy: number,      // userId of who assigned
  assignedAt: Date,
  expiresAt: Date,         // null = permanent
  permissions: [string]
}

// 4. Session Logs
{
  _id: ObjectId,
  userId: number,
  gameId: number,
  executorName: string,
  joinedAt: Date,
  leftAt: Date,
  actions: [{timestamp, action, details}]
}
```

---

## Client-Side Integration (Lua Script)

### 1. Network Module
```lua
local Network = {}
Network.API_URL = "https://your-vps-domain.com"
Network.WS_URL = "wss://your-vps-domain.com:8080"

-- Functions:
Network:AuthenticatePlayer()      -- Register player with backend
Network:SendHeartbeat()           -- Keep-alive (every 30 seconds)
Network:SyncPlayerRole()          -- Get role from server
Network:ReportGameEvent()         -- Log actions/stats
Network:GetOnlinePlayers()        -- Real-time player list
Network:SubscribeToUpdates()      -- WebSocket subscription
```

### 2. Webhook Integration
Script sends HTTP POST requests to backend:
```lua
-- On player join
HttpService:RequestAsync({
  Url = API_URL .. "/api/webhooks/player-joined",
  Method = "POST",
  Headers = {"Content-Type": "application/json"},
  Body = HttpService:JSONEncode({
    userId = LocalPlayer.UserId,
    username = LocalPlayer.Name,
    gameId = game.PlaceId,
    executor = GetExecutor(),
    timestamp = os.time()
  })
})

-- Periodic heartbeat (every 30s)
-- On script unload
```

---

## Feature Set

### A. Player Tracking
- See all active Yuniku users in real-time
- View which games they're playing
- Track session duration and frequency
- Build user statistics dashboard

### B. Role Management
- Owner: Full control, assign roles, manage server
- Creator: Can assign moderator/support roles
- Admin: Manage content, ban players
- Moderator: Enforce rules, log actions
- Support: Help users, escalate issues
- VIP: Premium features, priority support
- Member: Basic access

### C. Cross-Game Synchronization
- Player joins Game A → role syncs to all Yuniku instances in that game
- Player joins Game B → role recognized immediately
- Real-time updates via WebSocket

### D. Statistics Dashboard (Web UI)
```
- Total active users (today/week/month)
- Most played games
- User retention chart
- Role distribution
- System health metrics
- Live player map (game ID -> player list)
```

---

## Implementation Phases

### Phase 1: Backend Setup (Week 1)
- [ ] Provision VPS (DigitalOcean/Linode/AWS)
- [ ] Install Node.js + MongoDB
- [ ] Create Express server with basic endpoints
- [ ] Setup HTTPS/SSL certificate
- [ ] Deploy authentication system
- [ ] Create database schema

### Phase 2: Lua Integration (Week 2)
- [ ] Create Network module in script
- [ ] Add authentication on script startup
- [ ] Implement heartbeat system
- [ ] Add role sync on character load
- [ ] Test webhook delivery

### Phase 3: WebSocket & Real-Time (Week 3)
- [ ] Setup WebSocket server
- [ ] Implement player list subscription
- [ ] Create live sync protocol
- [ ] Add cache system for scalability
- [ ] Test with 10+ concurrent users

### Phase 4: Dashboard & Admin Panel (Week 4)
- [ ] Build admin web interface
- [ ] Add role assignment controls
- [ ] Create statistics pages
- [ ] Implement user search/filtering
- [ ] Setup logging and audit trail

### Phase 5: Security & Optimization
- [ ] Add API rate limiting
- [ ] Implement JWT token system
- [ ] Add DDoS protection
- [ ] Setup database backups
- [ ] Performance optimization

---

## VPS Specifications

### Minimum Requirements
- CPU: 2 vCPU (1-2 cores)
- RAM: 2 GB
- Storage: 20 GB SSD
- Bandwidth: 1 TB/month
- **Cost**: $5-10/month

### Recommended for 500+ users
- CPU: 4 vCPU
- RAM: 4-8 GB
- Storage: 50+ GB SSD
- Database: Managed MongoDB ($57-117/month)
- **Total Cost**: $15-25/month

### Recommended VPS Providers
1. **DigitalOcean** - Simple, affordable, great docs
2. **Linode** - High performance, good uptime
3. **Vultr** - Multiple locations, good pricing
4. **AWS EC2** - Enterprise, scalable

---

## API Endpoints Reference

### Authentication
```
POST /api/auth/register
  Body: { userId, username, executorName, gameId }
  Response: { token, role, permissions }

POST /api/auth/login
  Body: { token }
  Response: { valid: bool, role, expiresAt }
```

### Players
```
GET /api/players
  Query: { gameId? }
  Response: { players: [{userId, username, role, status}] }

PUT /api/players/:userId
  Body: { role, customLabel? }
  Response: { success, message }

GET /api/players/:userId
  Response: { userId, username, role, stats, ... }
```

### Games
```
GET /api/games
  Response: { games: [{gameId, name, playersOnline, ... }] }

GET /api/games/:gameId
  Response: { gameId, players: [...], stats, ... }

POST /api/games/:gameId/join
  Body: { userId, timestamp }
  Response: { success }

POST /api/games/:gameId/leave
  Body: { userId, timestamp }
  Response: { success }
```

### Webhooks
```
POST /api/webhooks/player-joined
POST /api/webhooks/player-left
POST /api/webhooks/heartbeat
POST /api/webhooks/role-changed
POST /api/webhooks/action-logged
```

---

## Security Considerations

### 1. Authentication
- Use API tokens or JWT
- Token rotation every 24 hours
- Rate limit: 100 requests/minute per IP

### 2. Data Protection
- HTTPS/TLS for all traffic
- Database password hashing (bcrypt)
- No sensitive data in logs
- Encrypt stored tokens

### 3. Access Control
- Role-based permissions (RBAC)
- Only owners can assign admin roles
- Action logging for audit trail
- IP whitelist option

### 4. DDoS Protection
- Use Cloudflare or similar CDN
- Rate limiting per endpoint
- Connection pooling
- Load balancing

---

## Testing Checklist

### Unit Tests
- [ ] API endpoint returns correct data
- [ ] Database queries work correctly
- [ ] Authentication tokens validate
- [ ] Role permissions enforced

### Integration Tests
- [ ] Script connects to API
- [ ] Player data syncs correctly
- [ ] Role updates propagate
- [ ] Webhooks fire successfully

### Load Testing
- [ ] Handle 100+ concurrent connections
- [ ] WebSocket broadcast to 50+ players
- [ ] API handles 10 requests/second
- [ ] Database handles 1000 concurrent sessions

### Real-World Testing
- [ ] Test in actual Roblox games
- [ ] Test with script auto-execute
- [ ] Test character respawn scenarios
- [ ] Test game transitions

---

## Monitoring & Maintenance

### Metrics to Track
- API response time (target: <100ms)
- Database connection pool health
- WebSocket connection count
- Error rate (target: <0.1%)
- CPU/RAM usage
- Disk I/O

### Logging
- All API requests with timestamp/IP
- Database queries (slow query log)
- WebSocket connections/disconnections
- Authentication failures
- Role changes with audit trail

### Backups
- Daily database backups
- 30-day retention
- Test restore process monthly
- Backup encryption at rest

### Alerts
- CPU > 80%
- Memory > 90%
- Disk space < 10%
- API error rate > 1%
- Database unavailable
- WebSocket connection losses

---

## Example: Setting Up Backend (Quick Start)

### 1. VPS Setup (DigitalOcean)
```bash
# SSH into VPS
ssh root@your_vps_ip

# Update system
apt update && apt upgrade -y

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt install -y nodejs

# Install MongoDB
apt install -y mongodb

# Start MongoDB
systemctl start mongodb
systemctl enable mongodb
```

### 2. Create Express Server
```bash
mkdir ~/yuniku-api
cd ~/yuniku-api
npm init -y
npm install express cors dotenv axios

# Create server.js
```

### 3. Basic Server (server.js)
```javascript
const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Test endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date() });
});

// Player register
app.post('/api/auth/register', (req, res) => {
  const { userId, username } = req.body;
  // TODO: Save to MongoDB
  res.json({ token: 'token_here', role: 'member' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Yuniku API listening on port ${PORT}`);
});
```

### 4. Deploy with PM2
```bash
npm install -g pm2
pm2 start server.js --name yuniku-api
pm2 startup
pm2 save
```

---

## Next Steps

1. **Choose VPS Provider** - Recommend DigitalOcean for ease
2. **Setup Backend** - Follow quick start above
3. **Create Database Schema** - Copy MongoDB collections
4. **Update Lua Script** - Add Network module
5. **Test Integration** - Run in test game
6. **Deploy to Production** - Scale gradually

---

## Cost Breakdown (Monthly)

| Component | Cost | Notes |
|-----------|------|-------|
| VPS (2 vCPU, 2GB RAM) | $6 | DigitalOcean |
| Database (MongoDB) | $0 | Free tier or $57+ managed |
| Domain (optional) | $12 | Namecheap or similar |
| Backups/Storage | $0-5 | Included or add-on |
| **TOTAL** | **$18-75** | Scales with users |

---

Generated: 2026-09-01
For questions, refer to: `/memories/session/yuniku-fixes-tasks.md`
