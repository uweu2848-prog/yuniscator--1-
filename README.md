🦂 Welcome to Scorp
The all-in-one script hosting, deployment, and security backend for Roblox.

Welcome to the Scorp repository! Whether you are deploying tools for a small team or managing a large-scale Roblox community, Scorp is designed to take the headache out of script management. We provide a rock-solid, server-authoritative backend that handles your build pipeline, Lua obfuscation, custom nametags, and anti-tampering security natively.

No more desynchronized files or easily bypassed client-side checks. Scorp keeps your logic on the server, alerts you via Discord when things go wrong, and makes live updates seamless.

✨ Core Features
Secure, Synchronized Build Pipeline: Scorp automatically obfuscates your source files (src/script.lua) into a deployment-ready payload (dist/script.lua) and serves it instantly. You always know exactly which build is live.

Server-Authoritative Nametags: Say goodbye to easily exploited client-side UI. Scorp features a highly customizable, fully server-side role management system with seven distinct tiers.

Smart Anti-Tamper & HWID Banning: Our security system evaluates client environments using opaque telemetry. When bad actors are detected, Scorp issues escalating bans linked securely to userId ↔ HWID—protecting legitimate players on shared IPs (like dorms or mobile networks) from collateral damage.

Discord Integration: Manage user roles and custom tags, apply curated style packs, control paid-tag entitlements, review detailed tamper alerts, and manage account access from `/access` commands or the private button dashboard opened with `/panel`.

Moderation data is stored under `DATA_DIR` (`access.json`, `access-history.json`, `offenses.json`, and `paid-tags.json`). The allowlist only suppresses automatic tamper enforcement; an existing blacklist still blocks the account. Manual and automatic blacklist actions include reasons and are recorded in the moderation history.

Set `ADMIN_ROBLOX_IDS` to a comma-separated list of trusted Roblox user IDs to authorize the in-game staff panel. `OWNER_USER_ID` is also authorized. Discord commands use `STAFF_DISCORD_IDS` when configured; otherwise they require the Discord Administrator permission.

Nametag identity is always the player's Roblox display name, followed by `discord.gg/scorp`. Custom tag label text is staff-controlled. Free users may choose the available preset palette/font/effect combinations; staff-managed premium tags require an explicit premium entitlement and cannot be overwritten from the free editor.

Client-side tamper checks and Lua obfuscation are deterrence/telemetry, not guarantees: any client-delivered code can eventually be inspected or modified. The authoritative controls are server-side access decisions, session checks, and the admin/Discord allowlist and blacklist.
