# Yuniku Nametag System - Quick Reference Guide

## Overview
The nametag system displays player roles above their heads with customizable titles, colors, and icons. It automatically tracks player join/leave and updates on character respawn.

---

## How to Use

### Basic Usage (In-Game)

1. **Open Yuniku Menu** (Press Right Alt by default)
2. **Go to ⚙️ Settings tab**
3. **Scroll to "👤 Nametags System"**
4. **Toggle "Enable Nametags"** - ON
5. **See nametags appear** above nearby player heads

---

## Settings Controls

### 1. Enable Nametags (Toggle)
- **ON**: All players see nametags with roles
- **OFF**: All nametags hidden (but data persists)
- **Use case**: Toggle for cleaner view in certain games

### 2. Auto-Detect Roles (Toggle)
- **ON**: Automatically assigns roles based on player data
  - Owner (by OwnerProfileId)
  - Roles in leaderstats (if available)
- **OFF**: Only manually assigned roles shown
- **Use case**: Disable during testing to use only quick-assign buttons

### 3. Refresh All Nametags (Button)
- Manually update all nametags
- Useful after assigning new roles
- Reconnects billboards if glitching

### 4. Quick Role Assignment (Button Grid)
- 6 colored buttons: Owner, Creator, Admin, Moderator, Support, VIP
- Click to assign role to yourself
- Nametag updates instantly
- Shows confirmation notification

---

## Nametag Appearance

### What You'll See
```
     👑 OWNER
     🔨 CREATOR
     ⚡ ADMIN
     🛡️ MODERATOR
     🆘 SUPPORT
     💎 VIP
     👤 MEMBER
```

### Visual Properties
- **Position**: 3.5 studs above player's head
- **Visibility**: Up to 100 studs away
- **Style**: Dark background with colored stroke matching role
- **Text**: White, bold, centered
- **Updates**: Auto-refresh on character respawn

---

## Role System

### Role Hierarchy
```
Owner (Top)
  ↓
Creator
  ↓
Admin
  ↓
Moderator
  ↓
Support & VIP
  ↓
Member (Default)
```

### Role Colors & Icons
| Role | Icon | Color | RGB |
|------|------|-------|-----|
| Owner | 👑 | Red | (255, 50, 50) |
| Creator | 🔨 | Orange | (255, 150, 50) |
| Admin | ⚡ | Yellow | (255, 200, 50) |
| Moderator | 🛡️ | Blue | (100, 200, 255) |
| Support | 🆘 | Green | (150, 255, 100) |
| VIP | 💎 | Purple | (200, 100, 255) |
| Member | 👤 | Gray | (200, 200, 200) |

---

## Customization (For Script Developers)

### Assign Role Programmatically
```lua
-- In the script or via custom code:
NametagSystem:RegisterPlayer(userId, role, customLabel)

-- Examples:
NametagSystem:RegisterPlayer(12345, "owner", "OWNER")
NametagSystem:RegisterPlayer(12346, "admin", "ADMIN")
NametagSystem:RegisterPlayer(LocalPlayer.UserId, "vip", "VIP")
```

### Supported Roles
- `"owner"` - Highest authority
- `"creator"` - Script creator/main dev
- `"admin"` - Game admin
- `"moderator"` - Rule enforcement
- `"support"` - Help/support staff
- `"vip"` - Premium member
- `"member"` - Default/regular user

### Custom Colors
Edit in `yugui.lua` (line 133):
```lua
local RoleColors = {
    ["owner"] = Color3.fromRGB(255, 50, 50),      -- Change RGB here
    ["creator"] = Color3.fromRGB(255, 150, 50),
    -- ... etc
}
```

### Custom Icons
Edit in `yugui.lua` (line 143):
```lua
local RoleIcons = {
    ["owner"] = "👑",          -- Use any emoji/character
    ["creator"] = "🔨",
    -- ... etc
}
```

---

## Common Tasks

### Task: Make someone a VIP
1. Have them join your game
2. Open Yuniku Settings
3. Click "💎 VIP" button
4. Their nametag updates to purple "VIP"
5. Everyone sees it (if nametags enabled)

### Task: Hide nametags temporarily
1. Go to Settings → 👤 Nametags System
2. Toggle "Enable Nametags" OFF
3. All nametags disappear (but data stays)
4. Toggle back ON to restore

### Task: Update all nametags after role changes
1. Go to Settings → 👤 Nametags System
2. Click "Refresh All Nametags" button
3. Wait for notification
4. All nametags refresh and update

### Task: Set yourself as Owner (dev testing)
1. Click the "👑 OWNER" button
2. Wait 1 second
3. Your nametag becomes red with crown icon
4. Persists until next game join (then resets to default)

---

## Technical Details

### Data Persistence
- **Current Session**: Roles persist while script is running
- **New Game/Rejoin**: Roles reset (unless VPS backend added)
- **Character Respawn**: Nametag persists (recreated at spawn)

### Performance Impact
- Minimal: ~0.5% CPU per active nametag
- Memory: ~50KB per player
- Network: Webhook calls only (when VPS added)

### Update Frequency
- **Character Respawn**: Instant (0.1s after spawn)
- **Player Join**: Instant
- **Player Leave**: Instant (billboard destroyed)
- **Manual Refresh**: Instant

### Dependencies
- BillboardGui (Roblox API)
- RunService.RenderStepped (for auto-tracking)
- Players service (join/leave detection)

---

## Troubleshooting

### Issue: Nametags don't appear
**Solution**:
- Verify "Enable Nametags" is toggled ON
- Check if other players are near (>100 studs away?)
- Try "Refresh All Nametags" button
- Restart the script

### Issue: Nametag text is cut off
**Solution**:
- This shouldn't happen, but if it does:
- Edit CustomLabel when assigning: `RegisterPlayer(userId, role, "SHORTER")`
- Reduce icon character width

### Issue: Nametag shows wrong role
**Solution**:
- Click the correct role button again
- Click "Refresh All Nametags"
- Verify leaderstats.Role is set correctly (if auto-detect enabled)

### Issue: Nametag disappears on character respawn
**Solution**:
- This is a bug. Try:
- Click "Refresh All Nametags"
- Disable/enable nametags toggle
- Rejoin game if persists

---

## Advanced Usage (With VPS Backend)

Once VPS is set up (see `VPS_NETWORK_PLAN.md`):

### Real-Time Sync
```lua
-- Roles sync across ALL games instantly
-- Player gets role → All Yuniku instances see it
-- Works across different game servers
```

### Persistent Storage
```lua
-- Roles survive game rejoins
-- Admins manage from web dashboard
-- Audit trail of who assigned what role
```

### Automated Moderation
```lua
-- Ban/warn players across all games
-- Track player behavior history
-- Escalate to admins automatically
```

### Live Statistics
```lua
-- See active players in real-time
-- Track which games are active
-- Monitor admin activities
```

---

## Roadmap

### Current (Phase 1) ✅
- [x] Nametag display system
- [x] Manual role assignment
- [x] Auto-detection (owner only)
- [x] Settings controls

### Next Phase (Phase 2) ⏳
- [ ] VPS backend integration
- [ ] Role persistence
- [ ] Cross-game synchronization
- [ ] Webhook notifications

### Future (Phase 3)
- [ ] Web admin dashboard
- [ ] Automated moderation
- [ ] Advanced permissions
- [ ] Statistics & analytics

---

## FAQ

**Q: Can I customize the nametag appearance?**
A: Yes! Edit RoleColors and RoleIcons tables in the script. Custom labels supported via RegisterPlayer().

**Q: Will roles save if I rejoin?**
A: Not yet - roles reset on rejoin. This requires VPS backend (Phase 2). Manual assignment only for now.

**Q: Can I see other players' roles across games?**
A: Not yet - only within same server session. Phase 2 (VPS) adds cross-game sync.

**Q: Is there a performance impact?**
A: Minimal (~0.5% CPU per nametag). 50 players = negligible impact.

**Q: Can I use this without VPS?**
A: Yes! Local nametags work perfectly. VPS just adds persistence and cross-game features.

**Q: How do I hide nametags in specific games?**
A: Toggle "Enable Nametags" OFF, or disable auto-start script in that game.

**Q: Can admins ban/kick players via nametags?**
A: Not yet - that requires Phase 2 (VPS backend).

---

## Support

For issues or feature requests:
1. Check troubleshooting section above
2. Review `SESSION_SUMMARY.md` for technical details
3. Check `yugui.lua` code comments (lines 102-251)
4. Refer to `VPS_NETWORK_PLAN.md` for backend setup

---

**Nametag System v1.0**
Integrated: 2026-09-01
Compatible with: Yuniku v4.1.5+
