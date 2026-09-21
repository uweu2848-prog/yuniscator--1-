'use strict';
/**
 * The tag embed the Discord bot posts — same layout as the tag-import embeds it mirrors:
 *
 *   Scorp Tag                                           [logo image]
 *   Tag for Roblox user `id` through your-server.example
 *   Target      username / display name, Roblox ID, Role, Source
 *   Text        Label · User text · Rank font · User font · Text size     (side by side …)
 *   Layout      Image · Background · Preview · Full · Mini · Offsets · Distances
 *   Colors      every colour option
 *   Effects     textAnimation + the on/off effects
 *
 * Pure formatting + two small best-effort Roblox lookups (username, image preview). Nothing here
 * needs a Discord connection, so it is fully unit-tested.
 */
const { EmbedBuilder } = require('discord.js');
const tagconfig = require('./tagconfig');

const SOURCE = 'discord-scorp-bot';
const code = v => `\`${String(v).replace(/`/g, "'")}\``;

// ── Roblox lookups (best effort: 4 s timeout, cached, never throw) ──────────
async function fetchJson(url, ms = 4000) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), ms);
    try {
        const res = await fetch(url, { signal: ctl.signal, headers: { accept: 'application/json' } });
        return res.ok ? await res.json() : null;
    } catch {
        return null;
    } finally {
        clearTimeout(timer);
    }
}

function makeRobloxLookup() {
    const cache = new Map(); // key -> { at, value }
    const TTL = 10 * 60 * 1000;
    async function cached(key, loader) {
        const hit = cache.get(key);
        if (hit && Date.now() - hit.at < TTL) return hit.value;
        const value = await loader();
        if (value) cache.set(key, { at: Date.now(), value });
        if (cache.size > 500) cache.clear();
        return value;
    }
    return {
        /** → { name, displayName } | null */
        user: id => cached(`u${id}`, async () => {
            const j = await fetchJson(`https://users.roblox.com/v1/users/${id}`);
            return j && j.name ? { name: j.name, displayName: j.displayName || j.name } : null;
        }),
        /** rbxassetid://123 → https://tr.rbxcdn.com/… (a picture Discord can show) | null */
        assetPreview: assetUrl => {
            const m = /(\d{1,20})$/.exec(String(assetUrl || ''));
            if (!m) return Promise.resolve(null);
            return cached(`a${m[1]}`, async () => {
                const j = await fetchJson(`https://thumbnails.roblox.com/v1/assets?assetIds=${m[1]}&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false`);
                const item = j && Array.isArray(j.data) && j.data[0];
                return item && item.imageUrl ? item.imageUrl : null;
            });
        },
    };
}

const NO_LOOKUP = { user: async () => null, assetPreview: async () => null };

const hexToInt = h => parseInt(String(h).replace('#', ''), 16) || 0;
const lines = rows => rows.map(([k, v]) => `${k}: ${code(v)}`).join('\n');

/**
 * @param info    server's tagInfo(userId)   → { userId, role, hasCustomTag, effective, … }
 * @param opts    { lookup, publicUrl, title, editedBy }
 */
async function buildTagEmbed(info, opts = {}) {
    const lookup = opts.lookup || NO_LOOKUP;
    const eff = info.effective;
    const d = tagconfig.describe(eff);

    const [user, preview] = await Promise.all([
        lookup.user(info.userId).catch(() => null),
        eff.image ? lookup.assetPreview(eff.image).catch(() => null) : Promise.resolve(null),
    ]);

    const roleShown = info.hasCustomTag && info.role === 'member' ? 'custom' : info.role;
    let host = '';
    try { if (opts.publicUrl) host = new URL(opts.publicUrl).host; } catch { /* ignore */ }

    const target = [
        user ? code(`${user.name} / ${user.displayName}`) : code(`Roblox user ${info.userId}`),
        `Roblox ID: ${code(info.userId)}`,
        `Role: ${code(roleShown)}`,
        `Source: ${code(SOURCE)}`,
    ].join('\n');

    const layoutRows = d.layout.slice();
    layoutRows.splice(2, 0, ['Preview', null]); // Image, Background, Preview, Full, Mini, …
    const layout = layoutRows.map(([k, v]) => (k === 'Preview' ? `Preview: ${preview || code('none')}` : `${k}: ${code(v)}`)).join('\n');

    const colors = d.colors.map(([k, v]) => `${code(k)} ${v}`).join('\n');
    const effects = d.effects.map(([k, v]) => `${code(k)} ${v}`).join('\n');

    const embed = new EmbedBuilder()
        .setTitle(opts.title || 'Scorp Tag')
        .setDescription(`${info.hasCustomTag ? 'Custom tag' : 'Tag (role defaults, no custom design yet)'} for Roblox user ${code(info.userId)}${host ? ` through ${host}` : ''}.`)
        .setColor(hexToInt(eff.primary))
        .addFields(
            { name: 'Target', value: target },
            { name: 'Text', value: lines(d.text), inline: true },
            { name: 'Layout', value: layout, inline: true },
            { name: 'Colors', value: colors },
            { name: 'Effects', value: effects },
        )
        .setFooter({ text: `Shows up in-game within ~10 seconds${opts.editedBy ? ` • ${opts.editedBy}` : ''}` })
        .setTimestamp(info.updatedAt ? new Date(info.updatedAt) : new Date());
    if (preview) embed.setThumbnail(preview);
    return embed;
}

module.exports = { buildTagEmbed, makeRobloxLookup, SOURCE };
