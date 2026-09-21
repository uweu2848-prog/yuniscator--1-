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
 *   /tag list                                  who has a custom design
 *
 * Who can use it: STAFF_DISCORD_IDS (comma-separated Discord user ids) if set, otherwise anyone with
 * the "Administrator" permission in the server the command is run from — never wide open.
 */
const {
    Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder, PermissionFlagsBits, MessageFlags,
} = require('discord.js');
const tagconfig = require('./tagconfig');
const { buildTagEmbed, makeRobloxLookup } = require('./tag-embed');

const EPHEMERAL = MessageFlags.Ephemeral;

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
            .addStringOption(o => o.setName('user_text').setDescription('Second line: auto (display name), none, or your own text'))
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
        .addSubcommand(sc => sc.setName('list').setDescription('Everyone with a custom design'));
}

function buildCommands(roleNames) {
    return [buildNametagCommand(roleNames), buildTagCommand()];
}

// Slash-command option name → tag option key, for the grouped subcommands.
const GROUPED = {
    text: [['label', 'label'], ['user_text', 'userText'], ['rank_font', 'rankFont'], ['user_font', 'userFont'], ['text_size', 'textSize']],
    layout: [['image', 'image'], ['background', 'background'], ['full_size', 'fullSize'], ['mini_size', 'miniSize'], ['offsets', 'offsets'], ['distances', 'distances']],
    effects: [['text_animation', 'textAnimation'], ['glow', 'glow'], ['pulse', 'pulse'], ['spin', 'spin'], ['particles', 'particles'],
        ['underline_sweep', 'underlineSweep'], ['glitch', 'glitch'], ['effects', 'effects'], ['grid', 'grid'], ['logo_motion', 'logoMotion']],
};

// ── Interaction handling (separate from the Discord connection so it can be tested) ──
function createHandler(deps) {
    const { staffIds, roleNames, setRole, clearRole, getRoles, tags, publicUrl } = deps;
    const say = deps.log || console.log;
    const lookup = deps.lookup || makeRobloxLookup();

    function isAllowed(interaction) {
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

    return async function handle(interaction) {
        try {
            if (interaction.isAutocomplete && interaction.isAutocomplete()) {
                if (interaction.commandName !== 'tag') return;
                const choices = isAllowed(interaction) ? suggestions(interaction.options.getFocused(true)) : [];
                return void (await interaction.respond(choices));
            }
            if (!interaction.isChatInputCommand() || !['nametag', 'tag'].includes(interaction.commandName)) return;
            if (!isAllowed(interaction)) {
                return void (await interaction.reply({ content: "You don't have permission to use this.", flags: EPHEMERAL }));
            }
            if (interaction.commandName === 'nametag') await handleNametag(interaction);
            else await handleTag(interaction);
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
            .then(() => say(`[discord-bot] slash commands registered: /nametag, /tag${guildId ? ' (guild-scoped)' : ' (global — allow up to an hour)'}`))
            .catch(e => say(`[discord-bot] failed to register slash commands: ${e.message}`));
    } else {
        say('[discord-bot] DISCORD_CLIENT_ID not set — slash commands were not registered.');
    }
    return client;
}

module.exports = startDiscordBot;
module.exports.createHandler = createHandler;
module.exports.buildCommands = buildCommands;
