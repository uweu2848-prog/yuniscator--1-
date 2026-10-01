'use strict';
/**
 * Optional Discord bot: staff manage Scorp nametags from Discord.
 *
 * Started by server.js only if DISCORD_TOKEN is set. Runs in the SAME process as the web server
 * and calls the same functions as the /api/admin/* routes — no second datastore, no HTTP hop.
 *
 *   /nametag set|clear|list        a player's ROLE (owner, admin, vip …) and role label
 *   /tag view   roblox_id                     post the tag embed (everything the tag currently uses)
 *   /tag set    roblox_id option value        change any single option  (autocomplete lists them all)
 *   /tag text   roblox_id [label user_text rank_font user_font text_size]
 *   /tag layout roblox_id [image background full_size mini_size offsets distances]
 *   /tag color  roblox_id name hex            one colour  (autocomplete lists all 29)
 *   /tag theme  roblox_id color               repaint every colour from one accent colour
 *   /tag effects roblox_id [text_animation glow pulse spin particles underline_sweep glitch effects grid logo_motion]
 *   /tag reset  roblox_id [option]            back to the role's default (one option or everything)
 *   /tag copy   from_id to_id                 give one player another player's design
 *   /tag import roblox_id code [mode]         apply an export code made by the in-game tag editor
 *   /tag export roblox_id                     get a player's design as a SCORPTAG1 code
 *   /tag preset roblox_id preset              apply a colour preset (Cyber Blue, Gold Royal, …)
 *   /tag style roblox_id colors font effects  quickly apply a curated design pack
 *   /tag tier roblox_id free|premium          control staff-managed custom-tag entitlement
 *   /tag list                                  who has a custom design
 *   /access ban|unban|allow|unallow|reason|list|history   account controls + audit history
 *
 * Who can use it: STAFF_DISCORD_IDS (comma-separated Discord user ids) if set, otherwise anyone with
 * the "Administrator" permission in the server the command is run from — never wide open.
 */
const {
    Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder, PermissionFlagsBits, MessageFlags,
    ActionRowBuilder, ButtonBuilder, ButtonStyle, ModalBuilder, TextInputBuilder, TextInputStyle,
} = require('discord.js');
const tagconfig = require('./tagconfig');
const { buildTagEmbed, makeRobloxLookup } = require('./tag-embed');

const EPHEMERAL = MessageFlags.Ephemeral;
const BAN_DURATION_SECONDS = { '1h': 3600, '6h': 21600, '1d': 86400, '7d': 604800, '30d': 2592000 };

function banDurationOptions(raw, permanentFallback = false) {
    const duration = String(raw || '').trim().toLowerCase();
    if (!duration || duration === 'tiered') return { permanent: permanentFallback };
    if (duration === 'permanent') return { permanent: true };
    if (BAN_DURATION_SECONDS[duration]) return { durationSeconds: BAN_DURATION_SECONDS[duration], permanent: false };
    throw new Error('Choose tiered, 1h, 6h, 1d, 7d, 30d, or permanent.');
}

// ── Slash command definitions ───────────────────────────────────────────────
function buildNametagCommand(roleNames) {
    return new SlashCommandBuilder()
        .setName('nametag')
        .setDescription("Manage a player's Scorp nametag role")
        .addSubcommand(sc => sc
            .setName('set')
            .setDescription("Set a player's nametag role")
            .addIntegerOption(o => o.setName('roblox_id').setDescription('Roblox user id').setRequired(true))
            .addStringOption(o => o.setName('role').setDescription('Role').setRequired(true)
                .addChoices(...roleNames.map(r => ({ name: r, value: r }))))
            .addStringOption(o => o.setName('label').setDescription('Custom label shown on the tag (optional)')))
        .addSubcommand(sc => sc
            .setName('clear')
            .setDescription('Reset a player back to the default role')
            .addIntegerOption(o => o.setName('roblox_id').setDescription('Roblox user id').setRequired(true)))
        .addSubcommand(sc => sc
            .setName('list')
            .setDescription('List everyone with a custom nametag role'));
}

function buildAccessCommand() {
    const id = o => o.setName('roblox_id').setDescription('Roblox user id').setRequired(true);
    const target = o => o.setName('target').setDescription('Roblox user id or HWID').setRequired(true);
    return new SlashCommandBuilder()
        .setName('access')
        .setDescription('Manage Scorp account access and review moderation history')
        .addSubcommand(sc => sc.setName('ban').setDescription('Blacklist a Roblox account')
            .addIntegerOption(id)
            .addStringOption(o => o.setName('reason').setDescription('Why this account is being blocked').setRequired(true).setMaxLength(500))
            .addStringOption(o => o.setName('duration').setDescription('Ban duration (default uses offense tiers)').addChoices(
                { name: 'Tiered by offense', value: 'tiered' }, { name: '1 hour', value: '1h' }, { name: '6 hours', value: '6h' },
                { name: '1 day', value: '1d' }, { name: '1 week', value: '7d' }, { name: '1 month', value: '30d' },
                { name: 'Permanent', value: 'permanent' })))
        .addSubcommand(sc => sc.setName('unban').setDescription('Lift an account/HWID blacklist')
            .addStringOption(target))
        .addSubcommand(sc => sc.setName('allow').setDescription('Allowlist an account from automatic tamper enforcement')
            .addIntegerOption(id)
            .addStringOption(o => o.setName('reason').setDescription('Approval/support note').setMaxLength(300)))
        .addSubcommand(sc => sc.setName('unallow').setDescription('Remove an account from the allowlist')
            .addIntegerOption(id))
        .addSubcommand(sc => sc.setName('reason').setDescription('Edit the latest blacklist reason')
            .addStringOption(target)
            .addStringOption(o => o.setName('text').setDescription('Updated reason').setRequired(true).setMaxLength(500)))
        .addSubcommand(sc => sc.setName('list').setDescription('List allowlisted or blacklisted accounts')
            .addStringOption(o => o.setName('kind').setDescription('Which list to show').setRequired(true)
                .addChoices({ name: 'blacklist', value: 'blacklist' }, { name: 'allowlist', value: 'allowlist' })))
        .addSubcommand(sc => sc.setName('history').setDescription('Show recent blacklist/allowlist changes')
            .addIntegerOption(o => o.setName('limit').setDescription('Number of events (1–25)').setMinValue(1).setMaxValue(25)));
}

function buildPanelCommand() {
    return new SlashCommandBuilder()
        .setName('panel')
        .setDescription('Open the Scorp staff dashboard with buttons');
}

function buildUsersCommand() {
    return new SlashCommandBuilder()
        .setName('users')
        .setDescription('List accounts currently running Scorp');
}

const robloxId = o => o.setName('roblox_id').setDescription('Roblox user id').setRequired(true);

function buildTagCommand() {
    return new SlashCommandBuilder()
        .setName('tag')
        .setDescription("Design a player's Scorp nametag (colours, fonts, effects, layout)")
        .addSubcommand(sc => sc.setName('view').setDescription("Show everything a player's tag uses")
            .addIntegerOption(robloxId))
        .addSubcommand(sc => sc.setName('set').setDescription('Change any single option')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('option').setDescription('Which option (start typing to search)').setRequired(true).setAutocomplete(true))
            .addStringOption(o => o.setName('value').setDescription('New value: #hex, on/off, a number, a font, an asset id …').setRequired(true)))
        .addSubcommand(sc => sc.setName('text').setDescription('Label, user text, fonts and text size')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('label').setDescription('Text on the tag (max 24 chars)'))
            .addStringOption(o => o.setName('user_text').setDescription('Paid-tag prefix before the Roblox name (name and invite always remain)'))
            .addStringOption(o => o.setName('rank_font').setDescription('Font of the label').setAutocomplete(true))
            .addStringOption(o => o.setName('user_font').setDescription('Font of the second line').setAutocomplete(true))
            .addIntegerOption(o => o.setName('text_size').setDescription('Label size, 8–28').setMinValue(8).setMaxValue(28)))
        .addSubcommand(sc => sc.setName('layout').setDescription('Logo image, background, sizes, offsets and distances')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('image').setDescription('Logo: asset id or rbxassetid://… (none = player avatar)'))
            .addStringOption(o => o.setName('background').setDescription('Card background image: asset id, or none'))
            .addStringOption(o => o.setName('full_size').setDescription('Card size like 168x34 (or auto x 42)'))
            .addIntegerOption(o => o.setName('mini_size').setDescription('Logo-only size when far away, 16–90').setMinValue(16).setMaxValue(90))
            .addStringOption(o => o.setName('offsets').setDescription('Studs above the head, full/mini — e.g. 3.05/2.65'))
            .addStringOption(o => o.setName('distances').setDescription('Full card until / logo only from / hidden beyond — e.g. 12/20/10000')))
        .addSubcommand(sc => sc.setName('color').setDescription('Change one colour')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('name').setDescription('Which colour (start typing to search)').setRequired(true).setAutocomplete(true))
            .addStringOption(o => o.setName('hex').setDescription('#rrggbb (or 255,136,0)').setRequired(true)))
        .addSubcommand(sc => sc.setName('theme').setDescription('Repaint every colour from one accent colour')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('color').setDescription('#rrggbb').setRequired(true)))
        .addSubcommand(sc => sc.setName('effects').setDescription('Turn effects on/off and pick the text animation')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('text_animation').setDescription('How the label text moves')
                .addChoices(...tagconfig.ANIMATIONS.map(a => ({ name: a, value: a }))))
            .addBooleanOption(o => o.setName('glow').setDescription('Soft glow around the card'))
            .addBooleanOption(o => o.setName('pulse').setDescription('Card and glow gently pulse'))
            .addBooleanOption(o => o.setName('spin').setDescription('Light travels around the border'))
            .addBooleanOption(o => o.setName('particles').setDescription('Floating sparkles inside the card'))
            .addBooleanOption(o => o.setName('underline_sweep').setDescription('Animated line under the label'))
            .addBooleanOption(o => o.setName('glitch').setDescription('Occasional glitch flicker on the label'))
            .addBooleanOption(o => o.setName('effects').setDescription('Master switch — off disables every animation'))
            .addBooleanOption(o => o.setName('grid').setDescription('Faint grid pattern on the card'))
            .addBooleanOption(o => o.setName('logo_motion').setDescription('Logo floats up and down')))
        .addSubcommand(sc => sc.setName('reset').setDescription("Back to the role's default look")
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('option').setDescription('Only reset this option (leave empty to reset everything)').setAutocomplete(true)))
        .addSubcommand(sc => sc.setName('copy').setDescription("Give a player another player's design")
            .addIntegerOption(o => o.setName('from_id').setDescription('Copy from this Roblox id').setRequired(true))
            .addIntegerOption(o => o.setName('to_id').setDescription('Apply to this Roblox id').setRequired(true)))
        .addSubcommand(sc => sc.setName('import').setDescription('Apply an export code from the in-game tag editor')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('code').setDescription('The SCORPTAG1.… code').setRequired(true).setMaxLength(6000))
            .addStringOption(o => o.setName('mode').setDescription('replace = the code becomes their design (default), merge = layer it on top')
                .addChoices({ name: 'replace', value: 'replace' }, { name: 'merge', value: 'merge' })))
        .addSubcommand(sc => sc.setName('export').setDescription("Get a player's design as a shareable code")
            .addIntegerOption(robloxId))
        .addSubcommand(sc => sc.setName('preset').setDescription('Apply a colour preset (keeps everything else)')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('preset').setDescription('Preset name').setRequired(true).setAutocomplete(true)))
        .addSubcommand(sc => sc.setName('style').setDescription('Apply one curated color/font/effect style pack')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('colors').setDescription('Premade palette').setRequired(true)
                .addChoices(...tagconfig.PRESET_NAMES.map(n => ({ name: n, value: n }))))
            .addStringOption(o => o.setName('font').setDescription('Paired title/name font style').setRequired(true)
                .addChoices(...tagconfig.FREE_FONT_PRESET_ORDER.map(n => ({ name: n, value: n }))))
            .addStringOption(o => o.setName('effects').setDescription('Animated effect pack').setRequired(true)
                .addChoices(...tagconfig.FREE_EFFECT_PRESET_ORDER.map(n => ({ name: n, value: n }))))
            .addBooleanOption(o => o.setName('premium').setDescription('Also mark this tag as staff-managed premium')))
        .addSubcommand(sc => sc.setName('tier').setDescription('Set the account tag tier')
            .addIntegerOption(robloxId)
            .addStringOption(o => o.setName('tier').setDescription('Free presets or staff-managed custom tag').setRequired(true)
                .addChoices({ name: 'free', value: 'free' }, { name: 'premium', value: 'premium' }))
            .addStringOption(o => o.setName('reason').setDescription('Purchase/support note').setMaxLength(300)))
        .addSubcommand(sc => sc.setName('list').setDescription('Everyone with a custom design'));
}

function buildCommands(roleNames) {
    return [buildNametagCommand(roleNames), buildTagCommand(), buildAccessCommand(), buildPanelCommand(), buildUsersCommand()];
}

// Slash-command option name → tag option key, for the grouped subcommands.
const GROUPED = {
    text: [['label', 'label'], ['user_text', 'userText'], ['rank_font', 'rankFont'], ['user_font', 'userFont'], ['text_size', 'textSize']],
    layout: [['image', 'image'], ['background', 'background'], ['full_size', 'fullSize'], ['mini_size', 'miniSize'], ['offsets', 'offsets'], ['distances', 'distances']],
    effects: [['text_animation', 'textAnimation'], ['glow', 'glow'], ['pulse', 'pulse'], ['spin', 'spin'], ['particles', 'particles'],
        ['underline_sweep', 'underlineSweep'], ['glitch', 'glitch'], ['effects', 'effects'], ['grid', 'grid'], ['logo_motion', 'logoMotion']],
};

const PANEL_PREFIX = 'scorp:panel:';

function panelButton(customId, label, style = ButtonStyle.Secondary, emoji) {
    const button = new ButtonBuilder().setCustomId(PANEL_PREFIX + customId).setLabel(label).setStyle(style);
    if (emoji) button.setEmoji(emoji);
    return button;
}

function buildPanelComponents() {
    return [
        new ActionRowBuilder().addComponents(
            panelButton('overview', 'Refresh Overview', ButtonStyle.Primary, '🔄'),
            panelButton('ban', 'Blacklist', ButtonStyle.Danger, '⛔'),
            panelButton('allow', 'Allowlist', ButtonStyle.Success, '🛡️'),
            panelButton('unban', 'Lift Blacklist', ButtonStyle.Secondary, '🔓'),
            panelButton('reason', 'Edit Reason', ButtonStyle.Secondary, '📝'),
        ),
        new ActionRowBuilder().addComponents(
            panelButton('premium', 'Premium Tag', ButtonStyle.Primary, '🏷️'),
            panelButton('style', 'Apply Style Pack', ButtonStyle.Secondary, '🎨'),
            panelButton('tagview', 'View Tag', ButtonStyle.Secondary, '👁️'),
            panelButton('users', 'Active Users', ButtonStyle.Secondary, '🌐'),
        ),
    ];
}

function formatActiveUsers(users) {
    if (!Array.isArray(users) || users.length === 0) return '**Scorp users online**\nNo active users right now.';
    const now = Date.now();
    const rows = users.slice(0, 35).map(user => {
        const name = String(user.displayName || user.username || 'Unknown').replace(/[`*_~|]/g, '');
        const account = String(user.username || 'Unknown').replace(/[`*_~|]/g, '');
        const age = Math.max(0, Math.floor((now - Number(user.lastSeen || now)) / 1000));
        return `• **${name}** (@${account}) · ID \`${user.userId}\` · Place \`${user.placeId || 'unknown'}\` · active ${age}s ago`;
    });
    if (users.length > rows.length) rows.push(`…and ${users.length - rows.length} more`);
    return `**Scorp users online · ${users.length}**\n${rows.join('\n')}`.slice(0, 1900);
}

function buildPanelModal(action) {
    const definitions = {
        ban: { title: 'Blacklist Roblox Account', fields: [['roblox_id', 'Roblox User ID', TextInputStyle.Short, true], ['reason', 'Reason', TextInputStyle.Paragraph, true], ['duration', 'Duration: tiered/1h/6h/1d/7d/30d/perm', TextInputStyle.Short, false]] },
        allow: { title: 'Allowlist Roblox Account', fields: [['roblox_id', 'Roblox User ID', TextInputStyle.Short, true], ['reason', 'Review note', TextInputStyle.Paragraph, false]] },
        unban: { title: 'Lift Account Blacklist', fields: [['target', 'Roblox User ID or HWID', TextInputStyle.Short, true]] },
        reason: { title: 'Edit Blacklist Reason', fields: [['target', 'Roblox User ID or HWID', TextInputStyle.Short, true], ['reason', 'Updated reason', TextInputStyle.Paragraph, true]] },
        premium: { title: 'Grant Premium Tag', fields: [['roblox_id', 'Roblox User ID', TextInputStyle.Short, true], ['title', 'Approved title (optional)', TextInputStyle.Short, false], ['reason', 'Purchase/support note', TextInputStyle.Paragraph, false]] },
        style: { title: 'Apply Preset Style Pack', fields: [['roblox_id', 'Roblox User ID', TextInputStyle.Short, true], ['colors', 'Color preset name', TextInputStyle.Short, true], ['font', 'Font style name', TextInputStyle.Short, true], ['effects', 'Effect pack name', TextInputStyle.Short, true]] },
        tagview: { title: 'View Roblox Tag', fields: [['roblox_id', 'Roblox User ID', TextInputStyle.Short, true]] },
    };
    const definition = definitions[action];
    if (!definition) return null;
    const modal = new ModalBuilder().setCustomId(PANEL_PREFIX + 'submit:' + action).setTitle(definition.title);
    for (const [id, label, style, required] of definition.fields) {
        const field = new TextInputBuilder().setCustomId(id).setLabel(label).setStyle(style).setRequired(required);
        if (id === 'reason') field.setMaxLength(500);
        if (id === 'title') field.setMaxLength(24);
        modal.addComponents(new ActionRowBuilder().addComponents(field));
    }
    return modal;
}

// ── Interaction handling (separate from the Discord connection so it can be tested) ──
function createHandler(deps) {
    const { staffIds, ownerDiscordIds = [], roleNames, setRole, clearRole, getRoles, tags, access, publicUrl } = deps;
    const say = deps.log || console.log;
    const lookup = deps.lookup || makeRobloxLookup();
    const ownerIdSet = new Set(ownerDiscordIds);

    function isOwner(interaction) {
        return ownerIdSet.has(interaction.user.id);
    }

    function isAllowed(interaction) {
        if (isOwner(interaction)) return true;
        if (staffIds && staffIds.length) return staffIds.includes(interaction.user.id);
        return interaction.memberPermissions?.has(PermissionFlagsBits.Administrator) ?? false;
    }

    // ── autocomplete ──
    function suggestions(focused) {
        const q = String(focused.value || '').toLowerCase().replace(/[\s_-]/g, '');
        let pool;
        if (focused.name === 'name') pool = tagconfig.COLOR_KEYS.map(k => [k, k]);
        else if (focused.name === 'preset') pool = tagconfig.PRESET_NAMES.map(n => [n, n]);
        else if (focused.name === 'rank_font' || focused.name === 'user_font') pool = tagconfig.FONTS.map(f => [f, f]);
        else pool = tagconfig.ALL_OPTION_NAMES.map(k => [`${k}  ·  ${tagconfig.COMPOSITES.includes(k) ? 'multiple' : tagconfig.TYPES[k]}`, k]);
        return pool.filter(([, v]) => v.toLowerCase().includes(q)).slice(0, 25).map(([name, value]) => ({ name, value }));
    }

    async function showTag(interaction, userId, extra = {}) {
        const info = tags.info(userId);
        const embed = await buildTagEmbed(info, { lookup, publicUrl, editedBy: `by ${interaction.user.username || interaction.user.tag || interaction.user.id}`, ...extra.embed });
        await interaction.editReply({ content: extra.content || undefined, embeds: [embed] });
    }

    function panelOverviewText() {
        if (!access) return 'Scorp staff dashboard · access management is unavailable.';
        const snapshot = access.snapshot();
        const activeBans = snapshot.blacklisted.filter(entry => entry.active);
        const recent = access.history(6).events;
        const rows = [
            '## Scorp Staff Dashboard',
            `**Active blacklists:** ${activeBans.length}  ·  **Allowlisted:** ${snapshot.allowlisted.length}`,
            '',
            '**Recent blacklists**',
            ...(activeBans.slice(0, 5).map(entry => {
                const latest = entry.latestReason || {};
                const target = latest.userId || entry.identities?.join(', ') || entry.root || 'unknown';
                return `• **${target}** — ${latest.reason || 'No reason recorded'} (${entry.permanent ? 'permanent' : 'temporary'})`;
            })),
            ...(activeBans.length ? [] : ['• none']),
            '',
            '**Recent staff actions**',
            ...(recent.map(event => `• ${event.action} — ${event.userId || event.target || '—'}${event.reason ? ` · ${event.reason}` : ''}`)),
            ...(recent.length ? [] : ['• none']),
            '',
            'Use the buttons below to manage access and tags. All actions are permission-checked and audited.',
        ];
        return rows.join('\n').slice(0, 3900);
    }

    async function handlePanelButton(interaction) {
        const action = interaction.customId.slice(PANEL_PREFIX.length);
        if (action === 'users') {
            const users = typeof deps.getActiveUsers === 'function' ? deps.getActiveUsers() : [];
            const text = formatActiveUsers(users);
            return void (await interaction.update({ content: text, components: buildPanelComponents() }));
        }
        if (action === 'overview') {
            return void (await interaction.update({ content: panelOverviewText(), components: buildPanelComponents() }));
        }
        const modal = buildPanelModal(action);
        if (!modal) return void (await interaction.reply({ content: 'That panel action is no longer available.', flags: EPHEMERAL }));
        return void (await interaction.showModal(modal));
    }

    async function handlePanelModal(interaction) {
        const action = interaction.customId.slice((PANEL_PREFIX + 'submit:').length);
        const value = key => interaction.fields.getTextInputValue(key).trim();
        const actor = interaction.user.username || interaction.user.tag || interaction.user.id;
        if (!access && action !== 'premium' && action !== 'style' && action !== 'tagview') throw new Error('Access-control management is not configured.');

        if (action === 'ban') {
            const userId = value('roblox_id'), reason = value('reason');
            if (!/^\d{1,20}$/.test(userId)) throw new Error('Roblox user ID must be numeric.');
            const duration = banDurationOptions(value('duration'));
            const result = access.blacklist({ userId, username: `Roblox ${userId}`, reason, actor, ownerAuthorized: isOwner(interaction), ...duration });
            return void (await interaction.reply({ content: `⛔ Blacklisted **${userId}** (${result.permanent ? 'permanent' : 'temporary'}). Reason: ${reason}`, flags: EPHEMERAL }));
        }
        if (action === 'allow') {
            const userId = value('roblox_id');
            if (!/^\d{1,20}$/.test(userId)) throw new Error('Roblox user ID must be numeric.');
            access.allow(userId, value('reason') || 'Approved by staff', actor);
            return void (await interaction.reply({ content: `✅ Allowlisted **${userId}** for automatic tamper enforcement review. Manual blacklists still apply.`, flags: EPHEMERAL }));
        }
        if (action === 'unban') {
            const target = value('target');
            if (!access.unblacklist(target, actor)) throw new Error(`No active blacklist found for ${target}.`);
            return void (await interaction.reply({ content: `✅ Lifted the blacklist for **${target}**.`, flags: EPHEMERAL }));
        }
        if (action === 'reason') {
            const target = value('target'), reason = value('reason');
            if (!access.editReason(target, reason, actor)) throw new Error(`No blacklist entry found for ${target}.`);
            return void (await interaction.reply({ content: `✅ Updated the latest blacklist reason for **${target}**.`, flags: EPHEMERAL }));
        }
        if (action === 'premium') {
            const userId = value('roblox_id'), title = value('title'), reason = value('reason') || 'Approved through Discord staff dashboard';
            if (!/^\d{1,20}$/.test(userId)) throw new Error('Roblox user ID must be numeric.');
            if (typeof tags.tier !== 'function') throw new Error('Premium tag management is unavailable.');
            tags.tier(userId, 'premium', reason, actor);
            if (title) tags.set(userId, { label: title });
            return void (await interaction.reply({ content: `✅ Granted premium tag access to **${userId}**${title ? ` with approved title **${title}**` : ''}. Roblox name and invite branding remain visible.`, flags: EPHEMERAL }));
        }
        if (action === 'style') {
            const userId = value('roblox_id');
            if (!/^\d{1,20}$/.test(userId)) throw new Error('Roblox user ID must be numeric.');
            const pick = (raw, names, kind) => {
                const found = names.find(name => name.toLowerCase() === raw.toLowerCase());
                if (!found) throw new Error(`Unknown ${kind} preset: ${raw}.`);
                return found;
            };
            const colorName = pick(value('colors'), tagconfig.PRESET_NAMES, 'color');
            const fontName = pick(value('font'), tagconfig.FREE_FONT_PRESET_ORDER, 'font');
            const effectName = pick(value('effects'), tagconfig.FREE_EFFECT_PRESET_ORDER, 'effect');
            const values = { ...tagconfig.presetOverrides(colorName), ...tagconfig.FREE_FONT_PRESETS[fontName], ...tagconfig.FREE_EFFECT_PRESETS[effectName] };
            tags.set(userId, Object.fromEntries(Object.entries(values).map(([key, v]) => [key, typeof v === 'boolean' ? (v ? 'on' : 'off') : String(v)])));
            return void (await interaction.reply({ content: `✅ Applied **${colorName}** · **${fontName}** · **${effectName}** to **${userId}**.`, flags: EPHEMERAL }));
        }
        if (action === 'tagview') {
            const userId = value('roblox_id');
            if (!/^\d{1,20}$/.test(userId)) throw new Error('Roblox user ID must be numeric.');
            await interaction.deferReply({ flags: EPHEMERAL });
            return void (await showTag(interaction, userId));
        }
        throw new Error('Unknown staff dashboard action.');
    }

    async function handleAccess(interaction) {
        const sub = interaction.options.getSubcommand();
        const actor = interaction.user.username || interaction.user.tag || interaction.user.id;
        if (!access) throw new Error('Access-control management is not configured.');
        if (sub === 'ban') {
            const userId = interaction.options.getInteger('roblox_id', true);
            const reason = interaction.options.getString('reason', true);
            const duration = banDurationOptions(interaction.options.getString('duration'), interaction.options.getBoolean('permanent') === true);
            const result = access.blacklist({ userId, username: `Roblox ${userId}`, reason, actor, ownerAuthorized: isOwner(interaction), ...duration });
            return void (await interaction.reply({ content: `⛔ Blacklisted Roblox account **${userId}** (${result.permanent ? 'permanent' : 'temporary'}). Reason: ${reason}`, flags: EPHEMERAL }));
        }
        if (sub === 'unban') {
            const target = interaction.options.getString('target', true);
            if (!access.unblacklist(target, actor)) return void (await interaction.reply({ content: `No active blacklist found for **${target}**.`, flags: EPHEMERAL }));
            return void (await interaction.reply({ content: `✅ Lifted the blacklist for **${target}**.`, flags: EPHEMERAL }));
        }
        if (sub === 'allow') {
            const userId = interaction.options.getInteger('roblox_id', true);
            const reason = interaction.options.getString('reason') || 'Approved by staff';
            access.allow(userId, reason, actor);
            return void (await interaction.reply({ content: `✅ Allowlisted **${userId}** for automatic tamper enforcement review. Manual blacklists still block access.`, flags: EPHEMERAL }));
        }
        if (sub === 'unallow') {
            const userId = interaction.options.getInteger('roblox_id', true);
            if (!access.unallow(userId, actor)) return void (await interaction.reply({ content: `**${userId}** was not allowlisted.`, flags: EPHEMERAL }));
            return void (await interaction.reply({ content: `✅ Removed **${userId}** from the allowlist.`, flags: EPHEMERAL }));
        }
        if (sub === 'reason') {
            const target = interaction.options.getString('target', true);
            const reason = interaction.options.getString('text', true);
            if (!access.editReason(target, reason, actor)) return void (await interaction.reply({ content: `No blacklist entry found for **${target}**.`, flags: EPHEMERAL }));
            return void (await interaction.reply({ content: `✅ Updated the latest blacklist reason for **${target}**.`, flags: EPHEMERAL }));
        }
        if (sub === 'list') {
            const kind = interaction.options.getString('kind', true);
            const snapshot = access.snapshot();
            const rows = kind === 'allowlist'
                ? snapshot.allowlisted.map(v => `• **${v.userId}** — ${v.reason || 'Approved by staff'}`)
                : snapshot.blacklisted.filter(v => v.active).map(v => `• **${v.latestReason?.userId || v.identities?.join(', ') || v.root}** — ${v.permanent ? 'permanent' : `until ${v.bannedUntil ? new Date(v.bannedUntil).toISOString() : 'unknown'}`} — ${v.latestReason?.reason || 'No reason recorded'}`);
            return void (await interaction.reply({ content: rows.length ? rows.join('\n').slice(0, 1900) : `No active ${kind} entries.`, flags: EPHEMERAL }));
        }
        if (sub === 'history') {
            const limit = interaction.options.getInteger('limit') || 10;
            const events = access.history(limit);
            const rows = events.events.map(e => `• ${e.at} · **${e.action}** · ${e.userId || e.target || '—'}${e.reason ? ` · ${e.reason}` : ''}`);
            return void (await interaction.reply({ content: rows.length ? rows.join('\n').slice(0, 1900) : 'No moderation history yet.', flags: EPHEMERAL }));
        }
    }

    // ── /nametag (roles) ──
    async function handleNametag(interaction) {
        const sub = interaction.options.getSubcommand();
        if (sub === 'set') {
            const id = interaction.options.getInteger('roblox_id', true);
            const role = interaction.options.getString('role', true);
            const label = interaction.options.getString('label') || undefined;
            const result = setRole(id, role, label);
            await interaction.reply({ content: `✅ Set \`${id}\` to **${result.role}**${result.label ? ` ("${result.label}")` : ''}.`, flags: EPHEMERAL });
        } else if (sub === 'clear') {
            const id = interaction.options.getInteger('roblox_id', true);
            const had = clearRole(id);
            await interaction.reply({ content: had ? `✅ Reset \`${id}\` back to the default role.` : `\`${id}\` didn't have a custom role set.`, flags: EPHEMERAL });
        } else if (sub === 'list') {
            const entries = Object.entries(getRoles());
            if (!entries.length) return void (await interaction.reply({ content: 'No custom roles set.', flags: EPHEMERAL }));
            const out = entries.map(([id, r]) => `\`${id}\` → **${r.role}**${r.label ? ` ("${r.label}")` : ''}`);
            await interaction.reply({ content: out.join('\n').slice(0, 1900), flags: EPHEMERAL });
        }
    }

    // ── /tag (designs) ──
    async function handleTag(interaction) {
        const sub = interaction.options.getSubcommand();
        await interaction.deferReply();

        if (sub === 'list') {
            const all = Object.entries(tags.list());
            if (!all.length) return void (await interaction.editReply('No custom tag designs yet. Start with `/tag theme` or `/tag set`.'));
            const out = all.map(([id, t]) => `\`${id}\` — ${Object.keys(t.overrides).length} custom option(s)`);
            return void (await interaction.editReply(out.join('\n').slice(0, 1900)));
        }
        if (sub === 'copy') {
            const from = interaction.options.getInteger('from_id', true);
            const to = interaction.options.getInteger('to_id', true);
            tags.copy(from, to);
            return void (await showTag(interaction, to, { content: `✅ Copied \`${from}\`'s design to \`${to}\`.` }));
        }

        const id = interaction.options.getInteger('roblox_id', true);
        if (sub === 'view') return void (await showTag(interaction, id));

        if (sub === 'tier') {
            const tier = interaction.options.getString('tier', true);
            const reason = interaction.options.getString('reason') || 'Updated by staff';
            const info = tags.tier(id, tier, reason, interaction.user.username || interaction.user.id);
            return void (await showTag(interaction, id, { content: `✅ Set \`${id}\` to the **${info.tier}** tag tier.` }));
        }

        if (sub === 'style') {
            const colorName = interaction.options.getString('colors', true);
            const fontName = interaction.options.getString('font', true);
            const effectName = interaction.options.getString('effects', true);
            const values = {
                ...tagconfig.presetOverrides(colorName),
                ...tagconfig.FREE_FONT_PRESETS[fontName],
                ...tagconfig.FREE_EFFECT_PRESETS[effectName],
            };
            const patch = Object.fromEntries(Object.entries(values).map(([key, value]) => [key, typeof value === 'boolean' ? (value ? 'on' : 'off') : String(value)]));
            tags.set(id, patch);
            if (interaction.options.getBoolean('premium') === true) tags.tier(id, 'premium', 'Curated style assigned by staff', interaction.user.username || interaction.user.id);
            return void (await showTag(interaction, id, { content: `✅ Applied **${colorName}** · **${fontName}** · **${effectName}** to \`${id}\`.` }));
        }

        if (sub === 'export') {
            const { code, options } = tags.export(id);
            const header = `Export code for \`${id}\` (${options} option${options === 1 ? '' : 's'}) — paste it into \`/tag import\` or the tag editor:`;
            if (code.length <= 1800) return void (await interaction.editReply({ content: `${header}\n\`\`\`\n${code}\n\`\`\`` }));
            return void (await interaction.editReply({ content: header, files: [{ attachment: Buffer.from(code, 'utf8'), name: `scorp-tag-${id}.txt` }] }));
        }
        if (sub === 'import') {
            const mode = interaction.options.getString('mode') || 'replace';
            const r = tags.import(id, interaction.options.getString('code', true), mode);
            const notes = [];
            if (r.ignored.length) notes.push(`ignored ${r.ignored.length} unknown option${r.ignored.length === 1 ? '' : 's'}`);
            if (r.invalid.length) notes.push(`skipped ${r.invalid.length} invalid value${r.invalid.length === 1 ? '' : 's'} (${r.invalid.slice(0, 3).join('; ').slice(0, 300)})`);
            const content = `✅ Imported ${r.applied} option${r.applied === 1 ? '' : 's'} for \`${id}\` (${r.mode})${notes.length ? ` — ${notes.join(', ')}` : ''}. Check the preview below before it goes live.`;
            return void (await showTag(interaction, id, { content }));
        }
        if (sub === 'preset') {
            const name = interaction.options.getString('preset', true);
            tags.preset(id, name);
            return void (await showTag(interaction, id, { content: `✅ Applied the **${name}** colour preset to \`${id}\`.` }));
        }

        if (sub === 'reset') {
            const option = interaction.options.getString('option') || undefined;
            tags.reset(id, option);
            return void (await showTag(interaction, id, { content: option ? `✅ Reset \`${option}\` for \`${id}\`.` : `✅ Reset \`${id}\` to the role's default look.` }));
        }
        if (sub === 'theme') {
            const color = interaction.options.getString('color', true);
            tags.set(id, { theme: color });
            return void (await showTag(interaction, id, { content: `✅ Repainted \`${id}\`'s tag from \`${color}\`.` }));
        }

        // set / color / grouped subcommands → a { option: value } patch
        const patch = {};
        if (sub === 'set') patch[interaction.options.getString('option', true)] = interaction.options.getString('value', true);
        else if (sub === 'color') patch[interaction.options.getString('name', true)] = interaction.options.getString('hex', true);
        else if (GROUPED[sub]) {
            for (const [slash, key] of GROUPED[sub]) {
                const isBool = sub === 'effects' && slash !== 'text_animation';
                const isInt = slash === 'text_size' || slash === 'mini_size';
                const v = isBool ? interaction.options.getBoolean(slash) : isInt ? interaction.options.getInteger(slash) : interaction.options.getString(slash);
                if (v !== null && v !== undefined) patch[key] = isBool ? (v ? 'on' : 'off') : String(v);
            }
        }
        if (!Object.keys(patch).length) return void (await interaction.editReply('Pick at least one option to change.'));
        tags.set(id, patch);
        await showTag(interaction, id, { content: `✅ Updated ${Object.keys(patch).map(k => `\`${k}\``).join(', ')} for \`${id}\`.` });
    }

    async function handleUsers(interaction) {
        const users = typeof deps.getActiveUsers === 'function' ? deps.getActiveUsers() : [];
        await interaction.reply({ content: formatActiveUsers(users), flags: EPHEMERAL });
    }

    return async function handle(interaction) {
        try {
            if (interaction.isButton && interaction.isButton() && interaction.customId?.startsWith(PANEL_PREFIX)) {
                if (!isAllowed(interaction)) return void (await interaction.reply({ content: "You don't have permission to use this panel.", flags: EPHEMERAL }));
                return await handlePanelButton(interaction);
            }
            if (interaction.isModalSubmit && interaction.isModalSubmit() && interaction.customId?.startsWith(PANEL_PREFIX + 'submit:')) {
                if (!isAllowed(interaction)) return void (await interaction.reply({ content: "You don't have permission to submit this panel action.", flags: EPHEMERAL }));
                return await handlePanelModal(interaction);
            }
            if (interaction.isAutocomplete && interaction.isAutocomplete()) {
                if (interaction.commandName !== 'tag') return;
                const choices = isAllowed(interaction) ? suggestions(interaction.options.getFocused(true)) : [];
                return void (await interaction.respond(choices));
            }
            if (!interaction.isChatInputCommand() || !['nametag', 'tag', 'access', 'panel', 'users'].includes(interaction.commandName)) return;
            if (!isAllowed(interaction)) {
                return void (await interaction.reply({ content: "You don't have permission to use this.", flags: EPHEMERAL }));
            }
            if (interaction.commandName === 'panel') {
                return void (await interaction.reply({ content: panelOverviewText(), components: buildPanelComponents(), flags: EPHEMERAL }));
            }
            if (interaction.commandName === 'users') return await handleUsers(interaction);
            if (interaction.commandName === 'nametag') await handleNametag(interaction);
            else if (interaction.commandName === 'tag') await handleTag(interaction);
            else await handleAccess(interaction);
        } catch (e) {
            const msg = `❌ ${e && e.message ? e.message : 'Something went wrong.'}`;
            if (!(e instanceof tagconfig.TagError)) say(`[discord-bot] ${interaction.commandName || 'interaction'} failed: ${e && e.stack || e}`);
            try {
                if (interaction.deferred || interaction.replied) await interaction.editReply({ content: msg, embeds: [] });
                else await interaction.reply({ content: msg, flags: EPHEMERAL });
            } catch { /* interaction expired */ }
        }
    };
}

// ── Discord connection ──────────────────────────────────────────────────────
function startDiscordBot(opts) {
    const { token, clientId, guildId, roleNames, log } = opts;
    const say = log || console.log;
    const handle = createHandler(opts);

    const client = new Client({ intents: [GatewayIntentBits.Guilds] });
    client.once('clientReady', () => say(`[discord-bot] logged in as ${client.user.tag}`));
    client.on('error', e => say(`[discord-bot] client error: ${e.message}`));
    client.on('interactionCreate', handle);
    client.login(token).catch(e => say(`[discord-bot] login failed: ${e.message}`));

    // Guild-scoped registration shows up instantly; global can take up to an hour.
    if (clientId) {
        const rest = new REST({ version: '10' }).setToken(token);
        const route = guildId ? Routes.applicationGuildCommands(clientId, guildId) : Routes.applicationCommands(clientId);
        rest.put(route, { body: buildCommands(roleNames).map(c => c.toJSON()) })
            .then(() => say(`[discord-bot] slash commands registered: /panel, /users, /nametag, /tag, /access${guildId ? ' (guild-scoped)' : ' (global — allow up to an hour)'}`))
            .catch(e => say(`[discord-bot] failed to register slash commands: ${e.message}`));
    } else {
        say('[discord-bot] DISCORD_CLIENT_ID not set — slash commands were not registered.');
    }
    return client;
}

module.exports = startDiscordBot;
module.exports.createHandler = createHandler;
module.exports.buildCommands = buildCommands;
module.exports.buildPanelComponents = buildPanelComponents;
module.exports.buildPanelModal = buildPanelModal;
