'use strict';
/**
 * Optional Discord bot: lets staff change a player's Scorp nametag role from Discord,
 * without touching the HTTP admin API by hand.
 *
 * Started by server.js only if DISCORD_TOKEN is set (see .env.example). Runs in the
 * SAME process as the web server and calls setRole/clearRole/getRoles directly — the
 * exact same functions the PUT/DELETE /api/admin/roles/:userId routes use, backed by
 * the exact same data/roles.json that /api/nametags/sync reads from. No second
 * datastore, no HTTP round-trip, no admin key needed here.
 *
 * Slash command:
 *   /nametag set   roblox_id:<number> role:<choice> [label:<text>]
 *   /nametag clear roblox_id:<number>
 *   /nametag list
 *
 * Who can use it: if STAFF_DISCORD_IDS (comma-separated Discord user ids) is set in
 * .env, only those people can run it. If it's left empty, it falls back to requiring
 * the "Administrator" permission in whatever Discord server the command is run from —
 * so this is never wide open by accident either way.
 */
const { Client, GatewayIntentBits, REST, Routes, SlashCommandBuilder, PermissionFlagsBits } = require('discord.js');

module.exports = function startDiscordBot(opts) {
    const { token, clientId, guildId, staffIds, roleNames, setRole, clearRole, getRoles, log } = opts;
    const say = log || console.log;

    function isAllowed(interaction) {
        if (staffIds && staffIds.length) return staffIds.includes(interaction.user.id);
        return interaction.memberPermissions?.has(PermissionFlagsBits.Administrator) ?? false;
    }

    const command = new SlashCommandBuilder()
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

    const client = new Client({ intents: [GatewayIntentBits.Guilds] });

    client.once('clientReady', () => say(`[discord-bot] logged in as ${client.user.tag}`));
    client.on('error', e => say(`[discord-bot] client error: ${e.message}`));

    client.on('interactionCreate', async (interaction) => {
        if (!interaction.isChatInputCommand() || interaction.commandName !== 'nametag') return;

        if (!isAllowed(interaction)) {
            await interaction.reply({ content: "You don't have permission to use this.", ephemeral: true });
            return;
        }

        const sub = interaction.options.getSubcommand();
        try {
            if (sub === 'set') {
                const robloxId = interaction.options.getInteger('roblox_id', true);
                const role = interaction.options.getString('role', true);
                const label = interaction.options.getString('label') || undefined;
                const result = setRole(robloxId, role, label);
                await interaction.reply({
                    content: `✅ Set \`${robloxId}\` to **${result.role}**${result.label ? ` ("${result.label}")` : ''}.`,
                    ephemeral: true,
                });
            } else if (sub === 'clear') {
                const robloxId = interaction.options.getInteger('roblox_id', true);
                const had = clearRole(robloxId);
                await interaction.reply({
                    content: had ? `✅ Reset \`${robloxId}\` back to the default role.` : `\`${robloxId}\` didn't have a custom role set.`,
                    ephemeral: true,
                });
            } else if (sub === 'list') {
                const entries = Object.entries(getRoles());
                if (!entries.length) {
                    await interaction.reply({ content: 'No custom roles set.', ephemeral: true });
                } else {
                    const lines = entries.map(([id, r]) => `\`${id}\` → **${r.role}**${r.label ? ` ("${r.label}")` : ''}`);
                    await interaction.reply({ content: lines.join('\n').slice(0, 1900), ephemeral: true });
                }
            }
        } catch (e) {
            await interaction.reply({ content: `❌ ${e.message}`, ephemeral: true });
        }
    });

    client.login(token).catch(e => say(`[discord-bot] login failed: ${e.message}`));

    // Register the slash command. Guild-scoped (when guildId is set) shows up instantly;
    // global registration can take up to an hour to propagate to every server.
    if (clientId) {
        const rest = new REST({ version: '10' }).setToken(token);
        const route = guildId ? Routes.applicationGuildCommands(clientId, guildId) : Routes.applicationCommands(clientId);
        rest.put(route, { body: [command.toJSON()] })
            .then(() => say(`[discord-bot] slash command registered${guildId ? ' (guild-scoped)' : ' (global — allow up to an hour)'}`))
            .catch(e => say(`[discord-bot] failed to register slash command: ${e.message}`));
    } else {
        say('[discord-bot] DISCORD_CLIENT_ID not set — slash command was not registered.');
    }

    return client;
};