🦂 Welcome to Scorp
The all-in-one script hosting, deployment, and security backend for Roblox.

Welcome to the Scorp repository! Whether you are deploying tools for a small team or managing a large-scale Roblox community, Scorp is designed to take the headache out of script management. We provide a rock-solid, server-authoritative backend that handles your build pipeline, Lua obfuscation, custom nametags, and anti-tampering security natively.

No more desynchronized files or easily bypassed client-side checks. Scorp keeps your logic on the server, alerts you via Discord when things go wrong, and makes live updates seamless.

✨ Core Features
Secure, Synchronized Build Pipeline: Scorp automatically obfuscates your source files (src/script.lua) into a deployment-ready payload (dist/script.lua) and serves it instantly. You always know exactly which build is live.

Server-Authoritative Nametags: Say goodbye to easily exploited client-side UI. Scorp features a highly customizable, fully server-side role management system with seven distinct tiers.

Smart Anti-Tamper & HWID Banning: Our security system evaluates client environments using opaque telemetry. When bad actors are detected, Scorp issues escalating bans linked securely to userId ↔ HWID—protecting legitimate players on shared IPs (like dorms or mobile networks) from collateral damage.

Discord Integration: Manage user roles and custom tags, apply curated style packs, control paid-tag entitlements, review detailed tamper alerts, and manage account access from `/access` commands or the private button dashboard opened with `/panel`.

The configured Discord webhook keeps one editable **Scorp · Live Users** message instead of posting a join alert for every execution. It refreshes from authenticated session heartbeats, lists only currently active accounts, and removes users after the presence timeout. Tracking dates and successful session counts are persisted in `DATA_DIR/known-users.json`, so returning accounts are recognized after a restart. History begins when this version first observes an account; older runs cannot be reconstructed. The webhook message ID is stored in `DATA_DIR/active-users-webhook.json` and is recreated if the message is deleted.

Configured in-game staff can open the staff console to resolve a Roblox username to its account ID, select an active Scorp user in the same Roblox game server, copy their ID, review access lists, and run access actions. Nametag design supports role, displayed text, custom hex/RGB accent colors, a visual picker, and synchronized red/green/blue sliders. Username resolution calls Roblox from the backend and is staff-authenticated; the console's access checks remain server-authoritative.

Scorp nametags emphasize the Roblox `@username` in a brighter, larger line, with the community invite in a smaller footer. Free users can mix curated color, font, and effect presets; staff-entitled premium users get the web studio's individual palette, typography, layout, badge/background, and animation controls. At long range, a tag collapses to the avatar bubble; its small arrow action attempts to move your character next to that Scorp user in the same Roblox server. This is client-side movement and may be blocked or corrected by the game.

Moderation data is stored under `DATA_DIR` (`access.json`, `access-history.json`, `offenses.json`, and `paid-tags.json`). The allowlist only suppresses automatic tamper enforcement; an existing blacklist still blocks the account. Manual and automatic blacklist actions include reasons and are recorded in the moderation history.

Set `ADMIN_ROBLOX_IDS` to a comma-separated list of trusted Roblox user IDs to authorize the full in-game staff panel. `OWNER_USER_ID` is also authorized. For trusted community managers/tag givers who must not have moderation powers, set `TAG_MANAGER_ROBLOX_IDS` to their comma-separated Roblox IDs. For support staff, set `SUPPORT_ROBLOX_IDS`; they receive an isolated report/session-support panel, not the admin or tag manager panel. Discord commands use `STAFF_DISCORD_IDS` when configured; otherwise they require the Discord Administrator permission.

Support reports are stored in `support-reports.json`, sent to `DISCORD_WEBHOOK`, and mention only the configured `OWNER_DISCORD_IDS` and `STAFF_DISCORD_IDS`. Full in-game admins can review the report queue from their panel. Support can pause a non-staff user's Scorp sessions for 5 minutes, 15 minutes, 1 hour, or 24 hours; this revokes the current Scorp client and blocks new Scorp loads during the pause, but cannot kick the player from the Roblox game. Custom manual ban durations are available to admins (1 hour, 6 hours, 1 day, 1 week, or 30 days); absent a custom duration, the existing offense tiers remain in effect.

Configured Roblox owner, admin, and tag-manager accounts are protected from manual blacklisting by regular staff. Configured admins and tag managers receive review alerts rather than automatic anti-tamper bans; the owner still needs a valid `OWNER_KEY` for automatic-ban exemption, so merely claiming the owner ID is not enough. An owner-authorized manual blacklist is possible from the in-game panel only with an `OWNER_USER_ID` session authenticated using `OWNER_KEY`; the HTTP admin API additionally requires `X-Owner-Key: <OWNER_KEY>` for a protected target. To authorize owner-level Discord moderation, set `OWNER_DISCORD_IDS` to comma-separated Discord user IDs; those accounts can use the bot as staff and are the only bot users allowed to blacklist protected Roblox staff. Keep owner keys and ID lists private and configure them in Railway.

The Shaders tab ports Yuniku-inspired Unreal, Cinematic, and Bodycam looks with reversible post-processing, screen overlays, raycast-based environment sampling, adaptive exposure, and quality scaling. Roblox LocalScripts do not expose custom GPU shaders, true SSR, or TAA; those effects are approximated. The engine leaves pre-existing lighting effects, map materials, camera motion, and audio untouched and removes only its own effects on stop/unload.

The in-game admin panel source is excluded from the public payload bundle. After authorization, the client fetches a separately obfuscated module from the backend; non-admin sessions cannot download it and get no panel button. The free name-tag editor is available as its own main-window tab. The menu toggle key is stored in the executor's `Scorp/default.json` config when file APIs are available and restored automatically on next launch. Code delivered to an authorized client can still be inspected; the server remains authoritative for every admin action.

## Releases and build verification

Run `npm run build:verify` before publishing. It writes `dist/script.lua`, parses the artifact as Lua 5.1, and checks representative plaintext markers. This verifies the local build only. The Roblox loader URL fetches `/loader.lua`; the running server builds/serves the payload during session creation. After deployment, check `/api/health` for the live `build.id`, `releaseChannel`, and `releaseVersion`.

Keep production and development in separate server deployments with separate loader URLs, `DATA_DIR`, `SESSION_SECRET`, `ADMIN_PASSWORD`, `OWNER_KEY`, and webhook settings. Configure production with `RELEASE_CHANNEL=production`; configure the test deployment with `RELEASE_CHANNEL=development`. Set `RELEASE_VERSION` and optional `RELEASE_NOTES` on each. Do not point public users at the development loader. Session tokens are bound to both channel and build, so a changed release causes the old client to show an update notice, stop Scorp features, and unload its UI after 30 seconds; it does not kick the player from their Roblox game.

Nametag identity is always the player's Roblox display name, followed by `discord.gg/scorp`. Custom tag label text is staff-controlled. Free users may choose the available preset palette/font/effect combinations; staff-managed premium tags require an explicit premium entitlement and cannot be overwritten from the free editor.

Client-side tamper checks and Lua obfuscation are deterrence/telemetry, not guarantees: any client-delivered code can eventually be inspected or modified. The authoritative controls are server-side access decisions, session checks, and the admin/Discord allowlist and blacklist.

Session tokens are bound to the current server build; deploying a new build revokes heartbeats from older builds so clients must relaunch. Each account also receives an account-scoped HMAC watermark encoded into its personalized payload. Staff can resolve a recovered marker with the authenticated `/api/admin/watermarks/:marker` route. The marker contains no credentials or direct user ID; it supports attribution only and can still be removed by someone modifying the client.
