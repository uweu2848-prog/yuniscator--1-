'use strict';
/**
 * Unit tests for src/tagconfig.js and src/discord-bot.js's interaction handler.
 * No real Discord connection or HTTP server — a fake `interaction` object stands in for
 * discord.js, and a tiny in-memory `tags` store stands in for server.js's role/tag data.
 * Run standalone (`node test/tagbot.test.js`) or from test/run.js.
 */
const assert = require('assert');
const tagconfig = require('../src/tagconfig');
const { createHandler, buildCommands } = require('../src/discord-bot');

let passed = 0, failed = 0;
const failures = [];
function ok(cond, name, extra) {
    if (cond) { passed++; }
    else { failed++; failures.push(name); console.log(`  ✗ ${name}${extra !== undefined ? '  → ' + JSON.stringify(extra) : ''}`); }
}

// ── tagconfig ────────────────────────────────────────────────────────────────
function testTagconfig() {
    ok(Object.keys(tagconfig.DEFAULTS).length > 40, 'DEFAULTS has every text/layout/color/effect key');
    ok(tagconfig.COLOR_KEYS.length === 29, 'exactly 29 colour options (matches the reference embed)', tagconfig.COLOR_KEYS.length);
    for (const role of Object.keys(tagconfig.ROLE_META)) {
        const eff = tagconfig.effectiveTag(role, {});
        ok(/^#[0-9a-f]{6}$/.test(eff.primary), `${role}: effective tag has a valid primary colour`, eff.primary);
    }

    let o = {};
    o = tagconfig.applyOption(o, 'primary', '#FF8800');
    ok(o.primary === '#ff8800', 'hex colour lowercased', o.primary);
    o = tagconfig.applyOption(o, 'primary', '255,0,128');
    ok(o.primary === '#ff0080', 'rgb() triplet parsed', o.primary);
    o = tagconfig.applyOption(o, 'glow', 'off');
    ok(o.glow === false, 'bool off parsed');
    o = tagconfig.applyOption(o, 'fullSize', '168x34');
    ok(o.fullWidth === 168 && o.fullHeight === 34, 'fullSize composite splits into width/height', o);
    o = tagconfig.applyOption(o, 'distances', '12/20/10000');
    ok(o.distFull === 12 && o.distMini === 20 && o.distMax === 10000, 'distances composite parses', o);
    o = tagconfig.applyOption(o, 'image', '1270554045585765');
    ok(o.image === 'rbxassetid://1270554045585765', 'bare numeric id becomes rbxassetid://', o.image);
    o = tagconfig.applyOption(o, 'rank_font', 'gotham bold');
    ok(o.rankFont === 'GothamBold', 'font name matched case/spacing-insensitively', o.rankFont);
    o = tagconfig.applyOption(o, 'primary', 'default');
    ok(!('primary' in o), '"default" resets a single option instead of setting it');

    const cases = [
        ['primary', 'not-a-color'], ['textSize', '99'], ['distances', '30/20/10'],
        ['bogus_option', '1'], ['image', 'not an id'], ['textAnimation', 'nonsense'], ['glow', 'maybe'],
    ];
    for (const [k, v] of cases) {
        let threw = false;
        try { tagconfig.applyOption({}, k, v); } catch (e) { threw = e instanceof tagconfig.TagError; }
        ok(threw, `rejects bad ${k}=${v}`);
    }

    const themed = tagconfig.themeOverrides('#33aaff');
    ok(themed.accentA === '#33aaff', 'theme() sets the accent colour directly', themed.accentA);
    ok(tagconfig.COLOR_KEYS.every(k => k in themed), 'theme() sets every colour key');

    const dirty = tagconfig.sanitizeOverrides({ primary: '#fff', bogus: 'x', glow: 'not-a-bool', textSize: 12 });
    ok('primary' in dirty && 'textSize' in dirty && !('bogus' in dirty) && !('glow' in dirty),
        'sanitizeOverrides drops unknown keys and wrong types', dirty);

    // export codes
    const design = { label: 'Cosmic Herald ✨', primary: '#ff8800', glow: false, textSize: 18, image: 'rbxassetid://1270554045585765' };
    const code = tagconfig.encodeCode(design);
    ok(code.startsWith('SCORPTAG1.') && /\.[0-9a-f]{8}$/.test(code), 'export code has the SCORPTAG1.<payload>.<checksum> shape', code.slice(0, 20));
    const back = tagconfig.decodeCode(code);
    const sortObj = o => JSON.stringify(Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : 1))));
    ok(sortObj(back.overrides) === sortObj(tagconfig.sanitizeOverrides(design)) && !back.ignored.length && !back.invalid.length, 'code round-trips exactly (including emoji / UTF-8)', back);
    ok(tagconfig.encodeCode({ ...design }) === tagconfig.encodeCode({ textSize: 18, glow: false, image: design.image, primary: '#ff8800', label: design.label }), 'same design → same code regardless of key order');
    const decodeErr = c => { try { tagconfig.decodeCode(c); return null; } catch (e) { return e instanceof tagconfig.TagError ? e.message : 'CRASH ' + e.message; } };
    ok(/checksum/i.test(decodeErr(code.replace(/.$/, c => (c === '0' ? '1' : '0')))), 'a changed checksum is caught');
    ok(/cut off|mangled|checksum/i.test(decodeErr(code.slice(0, -12))), 'a truncated code is caught');
    ok(/isn.t a Scorp tag code/.test(decodeErr('M7TAG1.abc.def')), 'a code from something else is refused');
    ok(decodeErr('') && decodeErr(null) && decodeErr('x'.repeat(20000)), 'empty / huge input is refused, never a crash');
    const evilJson = Buffer.from('{"__proto__":{"polluted":1},"constructor":"x","primary":"red","glow":"yes","textSize":5000,"label":"<b>hi</b>","image":"javascript:alert(1)","rankFont":"NotAFont","unknownThing":1}');
    const evilCode = `SCORPTAG1.${evilJson.toString('base64url')}.${tagconfig.adler32(evilJson).toString(16).padStart(8, '0')}`;
    const evil = tagconfig.decodeCode(evilCode);
    ok(({}).polluted === undefined && Object.keys(evil.overrides).join() === 'label', 'hostile code: no prototype pollution, only the one valid option survives', evil);
    ok(evil.ignored.includes('unknownThing') && evil.ignored.includes('__proto__') && evil.invalid.length >= 5, 'hostile code: unknown keys ignored, bad values reported', evil);
    ok(!/[<>]/.test(evil.overrides.label), 'imported text is cleaned of markup characters');
    const wrongTypes = tagconfig.importOverrides({ glow: 'on', textSize: '18', primary: 12 });
    ok(Object.keys(wrongTypes.overrides).length === 0 && wrongTypes.invalid.length === 3, 'values with the wrong JSON type are refused');

    // presets
    ok(tagconfig.PRESET_NAMES.length >= 8, 'ships a set of colour presets', tagconfig.PRESET_NAMES);
    for (const n of tagconfig.PRESET_NAMES) {
        const full = tagconfig.presetOverrides(n);
        ok(tagconfig.COLOR_KEYS.every(k => /^#[0-9a-f]{6}$/.test(full[k])), `preset "${n}" defines all 29 colours`);
    }
    ok(tagconfig.presetOverrides('cyber blue').accentA === '#3cc8ff', 'preset names are case-insensitive');
    let presetThrew = false; try { tagconfig.presetOverrides('nope'); } catch (e) { presetThrew = e instanceof tagconfig.TagError; }
    ok(presetThrew, 'unknown preset gives a readable error');

    const lua = tagconfig.toLua();
    require('luaparse').parse(lua, { luaVersion: '5.1' });
    ok(true, 'toLua() output is valid Lua 5.1');
    ok(lua.includes('defaults') && lua.includes('presets') && lua.includes('roles'), 'toLua() includes defaults/presets/roles');
}

// ── discord-bot interaction handler ─────────────────────────────────────────
function fakeInteraction({ command, sub, opts = {}, staffOk = true, focused }) {
    const replies = [];
    return {
        user: { id: 'u1', username: 'staffer' },
        commandName: command,
        memberPermissions: { has: () => staffOk },
        isAutocomplete: () => !!focused,
        isChatInputCommand: () => !focused,
        options: {
            getSubcommand: () => sub,
            getInteger: (name, req) => (name in opts ? opts[name] : (req ? (() => { throw new Error(`missing ${name}`); })() : null)),
            getString: (name, req) => (name in opts ? opts[name] : (req ? (() => { throw new Error(`missing ${name}`); })() : null)),
            getBoolean: name => (name in opts ? opts[name] : null),
            getFocused: () => focused,
        },
        _replies: replies,
        reply: async payload => { replies.push({ type: 'reply', payload }); },
        deferReply: async () => { replies.push({ type: 'defer' }); },
        editReply: async payload => { replies.push({ type: 'edit', payload }); },
        respond: async choices => { replies.push({ type: 'autocomplete', choices }); },
    };
}

function makeStore() {
    let roles = {};
    let tags = {};
    const roleMeta = tagconfig.ROLE_META;
    function roleFor(id) { return roles[id] ? { role: roles[id].role, label: roles[id].label } : { role: 'member', label: roleMeta.member.label }; }
    function info(id) {
        id = String(id);
        const r = roleFor(id);
        const overrides = (tags[id] && tags[id].overrides) || {};
        return { userId: id, role: r.role, roleLabel: r.label, hasCustomTag: !!Object.keys(overrides).length, overrides, effective: tagconfig.effectiveTag(r.role, overrides, r.label), updatedAt: (tags[id] && tags[id].updatedAt) || null };
    }
    return {
        setRole: (id, role, label) => { roles[String(id)] = { role, label: label || roleMeta[role]?.label }; return roles[String(id)]; },
        clearRole: id => { const had = String(id) in roles; delete roles[String(id)]; return had; },
        getRoles: () => roles,
        tags: {
            info,
            set: (id, options) => {
                id = String(id);
                let next = { ...((tags[id] && tags[id].overrides) || {}) };
                for (const [k, v] of Object.entries(options)) next = k === 'theme' ? { ...next, ...tagconfig.themeOverrides(v) } : tagconfig.applyOption(next, k, v);
                tags[id] = { overrides: next, updatedAt: new Date().toISOString() };
                return info(id);
            },
            reset: (id, option) => {
                id = String(id);
                if (!option) { delete tags[id]; return info(id); }
                const next = tagconfig.applyOption((tags[id] && tags[id].overrides) || {}, option, 'default');
                if (Object.keys(next).length) tags[id] = { overrides: next, updatedAt: new Date().toISOString() }; else delete tags[id];
                return info(id);
            },
            copy: (from, to) => {
                const src = tags[String(from)]; if (!src) throw new tagconfig.TagError('nothing to copy');
                tags[String(to)] = { overrides: { ...src.overrides }, updatedAt: new Date().toISOString() };
                return info(to);
            },
            list: () => tags,
            import: (id, code, mode = 'replace') => {
                id = String(id);
                const { overrides, ignored, invalid } = tagconfig.decodeCode(code);
                if (!Object.keys(overrides).length) throw new tagconfig.TagError('That code doesn\'t change anything from the defaults.');
                const base = mode === 'merge' ? ((tags[id] && tags[id].overrides) || {}) : {};
                tags[id] = { overrides: { ...base, ...overrides }, updatedAt: new Date().toISOString() };
                return { info: info(id), ignored, invalid, applied: Object.keys(overrides).length, mode: mode === 'merge' ? 'merge' : 'replace' };
            },
            export: id => {
                const o = (tags[String(id)] && tags[String(id)].overrides) || {};
                if (!Object.keys(o).length) throw new tagconfig.TagError('no custom design to export');
                return { code: tagconfig.encodeCode(o), options: Object.keys(o).length };
            },
            preset: (id, name) => {
                id = String(id);
                tags[id] = { overrides: { ...((tags[id] && tags[id].overrides) || {}), ...tagconfig.presetOverrides(name) }, updatedAt: new Date().toISOString() };
                return info(id);
            },
        },
        publicUrl: 'https://example.test',
        lookup: { user: async () => null, assetPreview: async () => null }, // no network in tests
        log: () => {},
    };
}

async function testBot() {
    // command builder sanity
    const cmds = buildCommands(Object.keys(tagconfig.ROLE_META)).map(c => c.toJSON());
    ok(cmds.map(c => c.name).sort().join(',') === 'nametag,tag', 'buildCommands registers /nametag and /tag');

    // permission gate
    const deps0 = makeStore();
    const handle0 = createHandler(deps0);
    const denied = fakeInteraction({ command: 'tag', sub: 'view', opts: { roblox_id: 111 }, staffOk: false });
    await handle0(denied);
    ok(denied._replies[0]?.payload?.content?.includes("don't have permission"), 'non-staff is refused');

    // theme + view
    const deps = makeStore();
    const handle = createHandler(deps);
    await handle(fakeInteraction({ command: 'tag', sub: 'theme', opts: { roblox_id: 42, color: '#33aaff' } }));
    let info = deps.tags.info(42);
    ok(info.effective.accentA === '#33aaff', 'theme subcommand repaints accentA', info.effective.accentA);
    const viewInter = fakeInteraction({ command: 'tag', sub: 'view', opts: { roblox_id: 42 } });
    await handle(viewInter);
    ok(viewInter._replies.some(r => r.type === 'edit' && r.payload.embeds), 'view subcommand posts an embed');

    // set (single option) with an invalid value → error, not a crash
    const badInter = fakeInteraction({ command: 'tag', sub: 'set', opts: { roblox_id: 42, option: 'primary', value: 'nope' } });
    await handle(badInter);
    ok(badInter._replies.some(r => r.payload && (r.payload.content || '').startsWith('❌')), 'bad /tag set value reports a friendly error, not a stack trace');
    ok(!badInter._replies.some(r => r.type === 'edit' && r.payload.embeds), 'no embed posted after a rejected value');

    // set (valid) then grouped effects
    await handle(fakeInteraction({ command: 'tag', sub: 'set', opts: { roblox_id: 42, option: 'glow', value: 'off' } }));
    ok(deps.tags.info(42).effective.glow === false, 'valid /tag set applies');
    await handle(fakeInteraction({ command: 'tag', sub: 'effects', opts: { roblox_id: 42, glow: true, spin: false } }));
    info = deps.tags.info(42);
    ok(info.effective.glow === true && info.effective.spin === false, 'grouped /tag effects applies multiple booleans at once', info.effective);

    // text / layout groups
    await handle(fakeInteraction({ command: 'tag', sub: 'text', opts: { roblox_id: 42, label: 'Cosmic Herald', text_size: 18 } }));
    info = deps.tags.info(42);
    ok(info.effective.label === 'Cosmic Herald' && info.effective.textSize === 18, 'grouped /tag text applies', info.effective);
    await handle(fakeInteraction({ command: 'tag', sub: 'layout', opts: { roblox_id: 42, full_size: '180x40', distances: '10/25/9000' } }));
    info = deps.tags.info(42);
    ok(info.effective.fullWidth === 180 && info.effective.distMax === 9000, 'grouped /tag layout applies composites', info.effective);

    // copy
    await handle(fakeInteraction({ command: 'tag', sub: 'copy', opts: { from_id: 42, to_id: 43 } }));
    ok(deps.tags.info(43).effective.label === 'Cosmic Herald', 'copy duplicates the full override set');

    // reset one option, then everything
    await handle(fakeInteraction({ command: 'tag', sub: 'reset', opts: { roblox_id: 42, option: 'label' } }));
    ok(deps.tags.info(42).effective.label === 'Member', 'reset one option falls back to the role default', deps.tags.info(42).effective.label);
    ok(deps.tags.info(42).hasCustomTag, 'other overrides survive a single-option reset');
    await handle(fakeInteraction({ command: 'tag', sub: 'reset', opts: { roblox_id: 42 } }));
    ok(!deps.tags.info(42).hasCustomTag, 'reset with no option clears the whole design');

    // list
    const listInter = fakeInteraction({ command: 'tag', sub: 'list', opts: {} });
    await handle(listInter);
    ok(listInter._replies.some(r => r.type === 'edit' && /43/.test(r.payload)), '/tag list shows players with a custom design');

    // /nametag still works unmodified
    const roleInter = fakeInteraction({ command: 'nametag', sub: 'set', opts: { roblox_id: 99, role: 'vip', label: 'Big Deal' } });
    await handle(roleInter);
    ok(deps.getRoles()['99']?.role === 'vip', '/nametag set still assigns roles');
    ok(roleInter._replies[0]?.payload?.content?.includes('vip'), '/nametag set replies with confirmation');

    // export → import round trip through the bot
    await handle(fakeInteraction({ command: 'tag', sub: 'theme', opts: { roblox_id: 50, color: '#ff8800' } }));
    await handle(fakeInteraction({ command: 'tag', sub: 'set', opts: { roblox_id: 50, option: 'label', value: 'Copy Me' } }));
    const exp = fakeInteraction({ command: 'tag', sub: 'export', opts: { roblox_id: 50 } });
    await handle(exp);
    const expMsg = exp._replies.find(r => r.type === 'edit').payload.content;
    const exportedCode = (/(SCORPTAG1\.[A-Za-z0-9_.-]+)/.exec(expMsg) || [])[1];
    ok(exportedCode && expMsg.includes('```'), '/tag export replies with the code in a code block', expMsg.slice(0, 120));
    const imp = fakeInteraction({ command: 'tag', sub: 'import', opts: { roblox_id: 51, code: '```' + exportedCode + '```' } });
    await handle(imp);
    ok(deps.tags.info(51).effective.label === 'Copy Me' && deps.tags.info(51).effective.accentA === '#ff8800', '/tag import applies the exported design (pasted inside a code block too)');
    ok(imp._replies.some(r => r.type === 'edit' && r.payload.embeds && /Imported \d+ option/.test(r.payload.content)), '/tag import shows the embed + how many options were applied');
    const impBad = fakeInteraction({ command: 'tag', sub: 'import', opts: { roblox_id: 52, code: exportedCode.slice(0, -4) } });
    await handle(impBad);
    ok(impBad._replies.some(r => r.payload && /^❌/.test(r.payload.content || '')) && !deps.tags.info(52).hasCustomTag, '/tag import with a damaged code errors out and changes nothing');
    await handle(fakeInteraction({ command: 'tag', sub: 'set', opts: { roblox_id: 51, option: 'glow', value: 'off' } }));
    await handle(fakeInteraction({ command: 'tag', sub: 'import', opts: { roblox_id: 51, code: tagconfig.encodeCode({ textSize: 20 }), mode: 'merge' } }));
    ok(deps.tags.info(51).effective.textSize === 20 && deps.tags.info(51).effective.glow === false && deps.tags.info(51).effective.label === 'Copy Me', 'import mode "merge" layers the code over the existing design');
    await handle(fakeInteraction({ command: 'tag', sub: 'import', opts: { roblox_id: 51, code: tagconfig.encodeCode({ textSize: 12 }) } }));
    ok(deps.tags.info(51).effective.textSize === 12 && deps.tags.info(51).effective.label === 'Member', 'import mode "replace" (default) makes the code the whole design');
    const preset = fakeInteraction({ command: 'tag', sub: 'preset', opts: { roblox_id: 53, preset: 'Ocean' } });
    await handle(preset);
    ok(deps.tags.info(53).effective.accentA === tagconfig.presetOverrides('Ocean').accentA, '/tag preset applies a colour preset');
    const acPreset = fakeInteraction({ command: 'tag', focused: { name: 'preset', value: 'clean' } });
    await handle(acPreset);
    ok(acPreset._replies[0].choices.map(c => c.value).join() === 'Clean Light', 'preset autocomplete finds presets by name');
    const emptyExport = fakeInteraction({ command: 'tag', sub: 'export', opts: { roblox_id: 99999 } });
    await handle(emptyExport);
    ok(emptyExport._replies.some(r => r.payload && /^❌/.test(r.payload.content || '')), '/tag export for a player without a design says so');

    // autocomplete
    const acColor = fakeInteraction({ command: 'tag', focused: { name: 'name', value: 'glow' } });
    await handle(acColor);
    const colorChoices = acColor._replies[0].choices.map(c => c.value);
    ok(colorChoices.includes('glowColorA') && colorChoices.every(v => tagconfig.COLOR_KEYS.includes(v)), 'colour autocomplete only returns colour keys', colorChoices);

    const acOption = fakeInteraction({ command: 'tag', focused: { name: 'option', value: 'dist' } });
    await handle(acOption);
    const optChoices = acOption._replies[0].choices.map(c => c.value);
    ok(optChoices.includes('distances'), 'option autocomplete finds composite names too', optChoices);

    const acFont = fakeInteraction({ command: 'tag', focused: { name: 'rank_font', value: 'gotham' } });
    await handle(acFont);
    ok(acFont._replies[0].choices.every(c => tagconfig.FONTS.includes(c.value)), 'font autocomplete only returns real fonts');

    const acDenied = fakeInteraction({ command: 'tag', focused: { name: 'name', value: '' }, staffOk: false });
    await handle(acDenied);
    ok(acDenied._replies[0].choices.length === 0, 'autocomplete returns nothing for non-staff');
}

async function runAll() {
    testTagconfig();
    await testBot();
    return { passed, failed, failures };
}

if (require.main === module) {
    runAll().then(r => {
        console.log(`tagbot: ${r.passed} passed, ${r.failed} failed`);
        if (r.failed) { console.log('Failed:\n - ' + r.failures.join('\n - ')); process.exitCode = 1; }
    });
}

module.exports = { run: runAll };
