# What was added

## loader.lua
- Replaced the no-op honeypot with real checks: native-function tampering (C1),
  wrapped request/HttpGet (H1/H3), request/loadstring swapped mid-run (H2),
  hooked game metamethods (M1), known spy GUI names in CoreGui/gethui() (G1).
- Each check reports an opaque code, not a readable string, in X-Flags and in
  the /api/tamper body — so nothing meaningful shows up in an HTTP spy log.
- Added a session ID (X-Session) generated once per run.
- Added a heartbeat loop (default every 60s) that re-runs the checks, reports
  them, and stops the script if the server answers 401/403.
- BLOCK_SCORE is math.huge by default (report-only). Watch your /api/tamper
  / Discord logs for false positives on the executors you support, then set
  BLOCK_SCORE to something like 3 to start refusing locally.

## src/server.js
- Added POST /api/heartbeat: accepts periodic check-ins, records any flags
  via the same auto-ban path as /api/tamper, and returns 403 once a user/HWID
  is blacklisted so a running client can be torn down mid-session.
- Added a shared recordTamper() used by both /api/tamper and /api/heartbeat,
  with an AUTO_BAN_THRESHOLD (default 2) — a user is blacklisted after that
  many distinct tamper reports rather than on the first one. Set it to 1 to
  keep the old immediate-ban behavior.
- Added a per-identity rate limit on GET /api/script (SCORE_FETCH_COOLDOWN_MS,
  default 5s) to slow down repeated scraping/reload loops.
- /api/script now also treats X-Flags sent on the initial fetch as a tamper
  report, so a single hot-loaded run can't dodge auto-ban.

## Still on you
- Fill in DISCORD_WEBHOOK, OWNER_USER_ID, ADMIN_PASSWORD, and SERVER_URL.
- sessions/tamperCounts/lastFetch are in-memory Maps — fine for one server
  process; move to a real store (Redis/DB) if you ever run more than one.
- Put your real feature code in src/script.lua, then run `node obfuscate.js`
  to regenerate dist/script.lua before deploying.
- The client-side checks can be patched by anyone determined enough; keep
  your most valuable logic server-side rather than relying on the client.

## Fixed
- **Bug in the original code**: `SCRIPT_FILE` and `BLACKLIST_FILE` in `src/server.js`
  were built from `__dirname` (which is `src/`), so the server was looking for
  `src/dist/script.lua` instead of the real `dist/script.lua` at the project
  root — GET /api/script would 404 for every legitimate user even with a
  correct build. Both paths now step up to the project root. Verified by
  running the server for real and fetching /api/script, /api/heartbeat,
  /api/tamper and the admin routes with curl.

## src/script.lua
- Filled in with your actual Scorp hub script (window/tabs/sections — the
  code that used to live directly in Scorp.lua), with the old duplicate
  whitelist/blacklist gate stripped out of it. That gate now lives once, in
  loader.lua, which is what runs before this payload is ever requested.
  Run `node obfuscate.js` any time you change src/script.lua to refresh
  dist/script.lua.

## Tested, not just written
- Parsed loader.lua and src/script.lua with the real Luau compiler (no
  syntax errors — the "Unknown global" notices are just the type-checker
  not knowing Roblox's API surface, expected outside Roblox).
- Ran loader.lua's detection logic under Luau against mocked Roblox APIs:
  confirmed a clean run reports score 0, and confirmed simulating a hooked
  pcall correctly trips the C1 code, reports it to /api/tamper, and adds it
  to X-Flags.
  Note: with no Roblox environment to test in, this validates the *logic*
  runs correctly against mocks — it doesn't guarantee every executor's real
  hooks are caught. Some checks (e.g. H1) are naturally weighted low because
  a few executors wrap `request` in ways that look identical to a hook.
- Ran the real server.js and exercised the full flow with curl: a fresh
  user pulls the real obfuscated dist/script.lua; a second immediate fetch
  gets 429 (rate limit); two /api/tamper reports auto-blacklist a user
  (AUTO_BAN_THRESHOLD=2); a banned user's /api/script now returns the frozen
  script and /api/heartbeat returns 403; the owner ID is never banned even
  after repeated reports.

## Ban escalation (this update)
- Bans now escalate per *person*, not per report: offense 1 = 1 day, offense 2 =
  7 days, offense 3 = 30 days, offense 4+ = permanent. BAN_TIERS in server.js.
- "Person" is a group of linked identifiers (userId, HWID, and IP), joined with
  a union-find whenever they're seen together. This is what stops the naive
  bypass of "just tamper again on a different Roblox account" or "just spoof a
  new HWID" — if either the account or the HWID is reused, the ban and offense
  count follow it. IP is included as a third link, since alone or together with
  a fresh account+HWID it still lets you connect the dots more often than not.
  Honest limit: nothing server-side can stop someone who changes account, HWID,
  AND IP all at once, since none of those values are cryptographically tied to
  a real person — this closes the easy bypasses, not a determined one.
- offenses.json replaces blacklist.json as the persistent store (identity graph
  + per-group offense count/ban state). Delete it to wipe all bans.
- Admin routes updated to match: GET /api/admin/blacklist now lists groups
  (with all linked identifiers and ban status), POST /api/admin/unblacklist
  lifts a ban early given ANY identifier in the group, POST /api/admin/blacklist
  can manually ban at any offense tier (pass "permanent": true to skip straight
  to a permaban).
- New GET /api/admin/suspicious: flags an IP that's been seen with more than
  SUSPICIOUS_IDENTITY_COUNT distinct userId/HWID combos within an hour — a
  pattern consistent with someone cycling alt accounts or spoofed HWIDs. This
  is a signal for you to review, not an auto-ban: shared/dynamic IPs (campus
  wifi, mobile carriers, VPNs) can trigger it legitimately, and reacting to it
  automatically would ban innocent people sharing a network.
- Verified with curl: offense 1 landed a ~1 day ban, lifting it and re-tripping
  the threshold produced a ~7 day ban (offenseCount now 2), and switching HWID
  while keeping the same userId+IP still hit the banned group instead of
  getting a clean script.

## Obfuscator (obfuscate.js — rewritten)
- Comments are now stripped using luaparse's own comment ranges instead of a
  per-line regex. The old regex only strips text after `--` on each line, so a
  multi-line `--[[ ... ]]` block comment had its opening `--[[` removed but the
  *body* of the comment was left behind as bare code — a real way to silently
  ship a broken file the moment your source ever used a block comment.
- Strings are now XOR-encrypted with a random key generated fresh on every
  build (4–8 bytes), not just turned into a plain byte array. A byte array of
  raw ASCII codes is legible on sight (65,66,67 = "ABC"); XORing against a
  random key that changes every build means a decrypted table from one release
  tells you nothing about the next one.
- The obfuscator re-parses its own output with luaparse before writing
  anything to disk, and aborts loudly instead of shipping a broken dist/script.lua
  if something went wrong.
- Honest limit, stated in the file itself: this is a string/whitespace
  obfuscator, not a virtualizer. It stops casual reading (Ctrl+F for strings,
  clean variable names) but a determined person with a Luau deobfuscator, or
  who just hooks the decrypt function and logs what it returns at runtime,
  gets your logic back. Nothing running on the client can be made unreadable
  to the client — the real protection is keeping your most valuable logic
  server-side rather than in the payload you obfuscate and serve.
- Verified: obfuscated a real hub script, confirmed dist/script.lua parses
  with the real Luau compiler, and ran it under Luau with mocks far enough to
  confirm every decrypted string comes back byte-for-byte correct (the error
  message the script prints on a mocked network failure came through as clean
  text, proving the encrypt/decrypt round trip works).
