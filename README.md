# Scorp

A Roblox script host: session handshake + heartbeat anti-tamper, a
build pipeline that obfuscates `src/script.lua` into `dist/script.lua`,
Discord alerts on tamper/bans, and a nametag system with roles set from
the server (not the client).

## What was actually broken (and fixed)

Your uploaded project had four bugs, in order of how much they explain
what you reported:

1. **`src/server.js` had a syntax error** — a stray `\vert{}\vert{}`
   where `||` should be, left over from a bad find/replace. The file
   could not even be `require()`'d, so the server never actually ran
   your anti-tamper/webhook code. This alone explains "webhooks not
   working" and "anti-tamper not working at all."
2. **`package.json`'s `start` script pointed at the wrong file**
   (`node server.js` at the project root, but the real server lived at
   `src/server.js`). Whatever was deployed on Railway wasn't the code
   you were editing.
3. **The obfuscator's input/output was disconnected from what the
   server served.** There was no place in the pipeline that told you
   *which* build was live, so "I changed script.js but nothing
   updates" had no way to be diagnosed. (Also: the file is `script.lua`,
   Lua, not `script.js` — Roblox executors run Lua, not JavaScript.)
4. **Nametags had no server component at all** — the old script just
   drew a hardcoded "OWNER"/"MEMBER" label with no role system, no
   design, and nothing under your control server-side.

Rebuilt: a working obfuscator (`obfuscate.js`), a server with signed
session tokens + real anti-tamper scoring + Discord alerts that retry
correctly (`src/server.js`), a loader with real detection checks
(`loader.lua`), and a nametag system with 7 roles you assign from an
admin endpoint (`src/nametags.lua`). All of it is covered by
`test/run.js` — 94 tests, including a full run of the real loader and
real built payload against the real server inside a mocked Roblox
client (no Roblox needed to test it).

I also found and fixed one real bug you didn't ask about: the original
ban logic linked bans through **shared IP addresses**. That meant one
banned troll on school wifi, a dorm, or a mobile carrier's NAT would
eventually merge into the same "banned person" as everyone else on
that IP, and the next legitimate student/roommate/carrier-mate to
connect would silently get banned too. Bans now only link
`userId ↔ HWID` (a real evasion signal); IP is still tracked as a
separate, non-punitive signal for `/api/admin/suspicious`.

## Setup

```bash
npm install
cp .env.example .env      # fill in DISCORD_WEBHOOK, OWNER_USER_ID, OWNER_KEY, ADMIN_PASSWORD
npm start                 # builds dist/script.lua automatically, then listens
```

Deploy anywhere that runs Node 20+ (Railway, Render, a VPS…). Set the
same variables as real environment variables on the host instead of a
`.env` file if you prefer — real env vars always win.

In-game, run **one line** in your executor:

```lua
loadstring(game:HttpGet("https://your-server/loader.lua"))()
```

You (the owner) should set your key first so you're never caught by
your own anti-tamper:

```lua
getgenv().SCORP_OWNER_KEY = "the same value as OWNER_KEY in .env"
```

## Editing the script

Edit `src/script.lua` (the UI/tabs — same content as your original
`Scorp.lua`, whitelist gate removed since that now lives once in
`loader.lua`) and `src/nametags.lua` (the nametag design + roster
sync). The server rebuilds automatically the moment either file
changes — no manual `node obfuscate.js` step needed, though
`npm run build` / `npm run watch` still work if you want to check the
output yourself. `/api/health` always tells you the build id and
timestamp of what's currently being served, so "did my change go
live" has a real answer.

## Nametags

- Defaults, per-role looks and every custom option live in **`src/tagconfig.js`**
  (one source of truth). The build inlines them into `src/nametags.lua` at the
  `--@tagdata` line, and the Discord embed reads the same file, so what the bot
  shows is exactly what renders in-game. Change a default → restart the server.
- Roles are assigned **server-side only** — a client can never grant
  itself a role:
  ```bash
  curl -X PUT https://your-server/api/admin/roles/123456 \
    -H "X-Admin-Key: $ADMIN_PASSWORD" -H "content-type: application/json" \
    -d '{"role":"support","label":"Trial Support"}'
  ```
  Roles: `owner`, `developer`, `admin`, `moderator`, `support`, `vip`,
  `member`. `OWNER_USER_ID` gets `owner` by default with no extra
  setup.
- In-game, the Settings tab has a **Preview Style** dropdown so you can
  see any role's look on your own tag without asking someone else to
  log in.
- Roles can also be set from Discord instead of `curl` — see the
  **Discord bot** section below.

## Custom tag designs (`/tag`)

Every tag can be styled per player with the same options as the tag-import
embed this was modelled on. Only what you change is stored (`data/tags.json`)
and sent to clients; everything else falls back to
`defaults + the player's role preset`.

| Group   | Options |
|---------|---------|
| Text    | `label`, `userText` (`auto` = display name, `none`, or your text), `rankFont`, `userFont`, `textSize` |
| Layout  | `image` (logo asset id), `background` (asset id), `fullSize` (`168x34`, `auto x 42`), `miniSize`, `offsets` (`3.05/2.65` studs), `distances` (`12/20/10000`) |
| Colours | 29: `primary`, `backgroundColorA/B/C`, `backgroundImageColor`, `accentA/B/C`, `highlightColor`, `nameColor`, `textStrokeColor`, `borderColor`, `outlineColorA/B/C`, `outerGlowColor`, `glowColorA/B/C`, `logoGlowColor`, `particleColorA/B`, `overlayColorA/B`, `underlineColorA/B/C`, `gridColor`, `glitchColor` |
| Effects | `textAnimation` (`default`/`shimmer`/`rainbow`/`wave`), `glow`, `pulse`, `spin`, `particles`, `underlineSweep`, `glitch`, `effects` (master switch), `grid`, `logoMotion` |

`distances` = full card until *a* studs → shrinking to *b* → logo only (`miniSize`)
from *b* → hidden beyond *c*. The viewer's own "Tag Distance" slider still caps it.

**Discord** (needs the bot from the section below):

```
/tag view    roblox_id                      the embed: target, text, layout, colours, effects
/tag set     roblox_id option value         any single option (autocomplete lists them all)
/tag text    roblox_id [label user_text rank_font user_font text_size]
/tag layout  roblox_id [image background full_size mini_size offsets distances]
/tag color   roblox_id name hex             one colour (autocomplete lists all 29)
/tag theme   roblox_id color                repaint every colour from one accent colour
/tag effects roblox_id [text_animation glow pulse spin particles underline_sweep glitch effects grid logo_motion]
/tag reset   roblox_id [option]             back to the role's look (one option or everything)
/tag copy    from_id to_id                  give one player another's design
/tag preset  roblox_id preset               apply a colour preset (Silver Surfer, Cyber Blue, Gold Royal, …)
/tag import  roblox_id code [mode]          apply an export code from the in-game tag editor (replace / merge)
/tag export  roblox_id                      a player's design as a shareable code
/tag list
```

After a change the bot posts the updated embed; the player's tag updates in-game
within about 10 seconds. Re-run the server once after updating so the bot
registers the new `/tag` command (guild-scoped commands appear instantly).

**HTTP** (same functions, same validation):

```bash
curl -X PUT https://your-server/api/admin/tags/123456 \
  -H "X-Admin-Key: $ADMIN_PASSWORD" -H "content-type: application/json" \
  -d '{"label":"Cosmic Herald","primary":"#ff8800","glow":"off","distances":"12/20/10000"}'
# GET /api/admin/tags/options   → every option, allowed values, defaults
# DELETE /api/admin/tags/123456[?option=primary]
```

### Tag editor + export codes

The script has a **Tag Editor** tab: live preview (a 2-D copy of the tag, always visible),
colour presets, text & fonts, images, layout, all 29 colours, effects and text animation.
"Show On My Tag" also puts the draft above your own head so you can judge it in the world.

- **Copy Export Code** → a code like `SCORPTAG1.eyJnbG93…​.075c48e2` on your clipboard (or printed
  to the console if your executor has no clipboard function). It only contains the options
  you changed, so it stays short.
- Send that code to whoever runs the bot; they run
  `/tag import roblox_id:<player> code:<the code>`. The bot posts the tag embed so it can be
  checked (logo image preview included) before it goes live in-game.
  `mode: merge` layers the code on top of a design instead of replacing it.
- **Import Code** in the editor does the reverse: paste any code (yours, one from `/tag export`)
  and every control jumps to it.
- Codes are validated on both sides with the same rules: unknown options are ignored, bad values
  are skipped and reported, a checksum catches cut-off or edited codes, and a code can never
  set anything `/tag set` couldn't. Over HTTP: `GET /api/admin/tags/:userId/export`,
  `POST /api/admin/tags/:userId/import {"code": "...", "mode": "replace"}`,
  `POST /api/admin/tags/:userId/preset {"name": "Cyber Blue"}`.

The editor is `src/tageditor.lua`; the code format lives in `src/tagconfig.js` (JS) and
`src/nametags.lua` (Lua) and is tested in both directions (a code made in Lua is decoded by JS
and vice versa). Presets are defined in `COLOR_PRESET_DEFS` in `src/tagconfig.js` — add yours there.
The admin API allows 30 requests/min per IP by default; set `ADMIN_RATE_PER_MIN` to raise it.

## Discord bot (optional)

Set `DISCORD_TOKEN` in `.env` (see the comments there for how to get one)
and the server starts a bot alongside itself with two slash commands — `/tag` (documented above) and `/nametag` for roles:

- `/nametag set roblox_id:<id> role:<role> [label:<text>]` — same as the
  `PUT /api/admin/roles/:userId` call above, just from Discord
- `/nametag clear roblox_id:<id>` — reset back to the default role
- `/nametag list` — everyone with a custom role right now

It's the same process, same `data/roles.json`, same validation as the
HTTP admin route — this is just another way to call it. Leave
`DISCORD_TOKEN` blank and the server runs exactly as before.

By default only people listed in `STAFF_DISCORD_IDS` can use it; if
that's left blank, anyone with Administrator in the Discord server it's
run from can. Set `DISCORD_GUILD_ID` too and the command appears
instantly in that one server instead of waiting up to an hour for a
global slash-command sync.

## Anti-tamper

`loader.lua` runs checks (hooked core functions, wrapped
request/HttpGet, swapped `request`/`loadstring`, hooked game
metamethods, known HTTP-spy GUIs/globals) before and every ~30s after
loading, and reports opaque codes (`C1`, `H2`, `G1`, …) to the server —
never the readable reason, so nothing meaningful shows up in a spy log
either. The server scores them, alerts Discord, and bans after either
one strong session or `AUTO_BAN_THRESHOLD` separate flagged sessions.
Bans escalate 1 day → 7 days → 30 days → permanent, tracked per
person (`userId ↔ HWID`), so switching just the account or just the
HWID doesn't reset the count.

Manage from `/api/admin/*` (send `X-Admin-Key: <ADMIN_PASSWORD>`):
`blacklist` (GET list / POST manual ban), `unblacklist`, `suspicious`
(shared-IP review, not auto-enforced), `sessions`, `roles`, `rebuild`,
`test-webhook`.

**Honest limit, same as before:** no client-side check is
unbreakable — Roblox has to let the client execute the code, so a
determined attacker can eventually defeat any single check. This
raises the effort a lot and catches casual dumpers/rippers (including
anyone who fetches the payload but never actually runs it — that's
reported to Discord too), but keep your most valuable logic
server-side if you add more features later.

## Tests

```bash
npm test
```

Spins up the real server against a fake Discord endpoint and drives it
with real HTTP: handshake, tamper scoring, ban tiers, owner exemption,
nametag roster/roles, admin auth, rate limits, and auto-rebuild. If
`texlua` (TeX Live's Lua 5.3, with luasocket) is on your PATH, it also
runs the **real** `loader.lua` and **real** built payload against the
server inside a mocked Roblox environment — no Roblox client needed.
