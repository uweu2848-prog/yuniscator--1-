🦂 Welcome to Scorp
The all-in-one script hosting, deployment, and security backend for Roblox.

Welcome to the Scorp repository! Whether you are deploying tools for a small team or managing a large-scale Roblox community, Scorp is designed to take the headache out of script management. We provide a rock-solid, server-authoritative backend that handles your build pipeline, Lua obfuscation, custom nametags, and anti-tampering security natively.

No more desynchronized files or easily bypassed client-side checks. Scorp keeps your logic on the server, alerts you via Discord when things go wrong, and makes live updates seamless.

✨ Core Features
Secure, Synchronized Build Pipeline: Scorp automatically obfuscates your source files (src/script.lua) into a deployment-ready payload (dist/script.lua) and serves it instantly. You always know exactly which build is live.

Server-Authoritative Nametags: Say goodbye to easily exploited client-side UI. Scorp features a highly customizable, fully server-side role management system with seven distinct tiers.

Smart Anti-Tamper & HWID Banning: Our security system evaluates client environments using opaque telemetry. When bad actors are detected, Scorp issues escalating bans linked securely to userId ↔ HWID—protecting legitimate players on shared IPs (like dorms or mobile networks) from collateral damage.

Discord Integration: Manage user roles, preview custom tags, and receive tamper alerts directly in your community's Discord server.
