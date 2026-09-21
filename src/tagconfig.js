'use strict';
/**
 * Nametag options — the ONE place that defines what a custom Scorp tag can contain.
 *
 * Used by:
 *   · server.js        validates + stores per-player overrides (data/tags.json) and sends them to clients
 *   · discord-bot.js   /tag commands (autocomplete lists, validation, the embed)
 *   · obfuscate.js     `--@tagdata` in src/nametags.lua is replaced by toLua() below, so the in-game
 *                      renderer always has exactly the same defaults / role presets as the bot's embed
 *
 * How a tag is resolved (server embed AND in-game):
 *     effective = DEFAULTS  +  ROLE_PRESETS[role]  +  the player's overrides
 * Only the overrides are stored / sent over the wire, so payloads stay tiny.
 */

// ── Roles (mirrors the roles in server.js) ──────────────────────────────────
const ROLE_META = {
    owner:     { accent: '#ffc440', glyph: '👑', label: 'Owner' },
    developer: { accent: '#9678ff', glyph: '⚡', label: 'Developer' },
    admin:     { accent: '#ff586e', glyph: '🛡️', label: 'Admin' },
    moderator: { accent: '#ff9640', glyph: '🔨', label: 'Moderator' },
    support:   { accent: '#60d6ff', glyph: '🎧', label: 'Support' },
    vip:       { accent: '#ff6ed6', glyph: '💎', label: 'VIP' },
    member:    { accent: '#a8bad6', glyph: '🌙', label: 'Member' },
};

// Roblox Enum.Font names that are safe to offer.
const FONTS = [
    'Gotham', 'GothamMedium', 'GothamBold', 'GothamBlack',
    'SourceSans', 'SourceSansLight', 'SourceSansSemibold', 'SourceSansBold', 'SourceSansItalic',
    'Arial', 'ArialBold', 'Legacy', 'Code', 'RobotoMono', 'Roboto', 'RobotoCondensed', 'Ubuntu',
    'Nunito', 'Oswald', 'Jura', 'JosefinSans', 'Michroma', 'Sarpanch', 'TitilliumWeb', 'Merriweather',
    'Bodoni', 'Garamond', 'Cartoon', 'Highway', 'SciFi', 'Arcade', 'Fantasy', 'Antique',
    'Bangers', 'Creepster', 'DenkOne', 'Fondamento', 'FredokaOne', 'IndieFlower', 'Kalam',
    'LuckiestGuy', 'PatrickHand', 'PermanentMarker', 'SpecialElite', 'AmaticSC', 'GrenzeGotisch',
];

const ANIMATIONS = ['default', 'shimmer', 'rainbow', 'wave'];

// Order here = order in the embed (matches the layout of the tag-import embed we mirror).
const COLOR_KEYS = [
    'primary',
    'backgroundColorA', 'backgroundColorB', 'backgroundColorC', 'backgroundImageColor',
    'accentA', 'accentB', 'accentC',
    'highlightColor', 'nameColor', 'textStrokeColor', 'borderColor',
    'outlineColorA', 'outlineColorB', 'outlineColorC',
    'outerGlowColor',
    'glowColorA', 'glowColorB', 'glowColorC', 'logoGlowColor',
    'particleColorA', 'particleColorB',
    'overlayColorA', 'overlayColorB',
    'underlineColorA', 'underlineColorB', 'underlineColorC',
    'gridColor', 'glitchColor',
];
const EFFECT_KEYS = ['glow', 'pulse', 'spin', 'particles', 'underlineSweep', 'glitch', 'effects', 'grid', 'logoMotion'];

// ── Colour helpers ──────────────────────────────────────────────────────────
const hexToRgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const rgbToHex = (r, g, b) => '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
function lerpHex(a, b, t) {
    const A = hexToRgb(a), B = hexToRgb(b);
    return rgbToHex(A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t);
}
const WHITE = '#ffffff', BLACK = '#000000';
const CARD_BG = '#080a16', CARD_BG_BOTTOM = '#05060e';

/** Derive every colour option from one accent colour (also what `/tag theme` uses). */
function paletteFromAccent(accent) {
    const light = lerpHex(accent, WHITE, 0.35);
    const tint = lerpHex(CARD_BG, accent, 0.13);
    return {
        primary: light,
        backgroundColorA: tint,
        backgroundColorB: lerpHex(tint, CARD_BG_BOTTOM, 0.5),
        backgroundColorC: CARD_BG_BOTTOM,
        backgroundImageColor: WHITE,
        accentA: accent,
        accentB: light,
        accentC: lerpHex(accent, WHITE, 0.7),
        highlightColor: WHITE,
        nameColor: '#96a4be',
        textStrokeColor: accent,
        borderColor: lerpHex(accent, BLACK, 0.35),
        outlineColorA: accent,
        outlineColorB: accent,
        outlineColorC: accent,
        outerGlowColor: accent,
        glowColorA: accent,
        glowColorB: light,
        glowColorC: accent,
        logoGlowColor: accent,
        particleColorA: light,
        particleColorB: WHITE,
        overlayColorA: WHITE,
        overlayColorB: accent,
        underlineColorA: accent,
        underlineColorB: light,
        underlineColorC: accent,
        gridColor: accent,
        glitchColor: '#ff3d81',
    };
}

// ── Defaults + role presets ─────────────────────────────────────────────────
const DEFAULTS = Object.freeze({
    // text
    label: '',              // '' = use the role's label
    userText: 'auto',       // auto = the player's display name, none = hide, anything else = that text
    rankFont: 'GothamBold',
    userFont: 'Gotham',
    textSize: 15,
    // layout
    image: '',              // rbxassetid://… logo; '' = the player's avatar headshot
    background: '',         // rbxassetid://… card background image; '' = none
    fullWidth: 0,           // 0 = fit to the text
    fullHeight: 42,
    miniSize: 40,
    offsetFull: 2.9,        // studs above the head
    offsetMini: 2.6,
    distFull: 40,           // full card up to here …
    distMini: 80,           // … shrinking until here, then just the logo …
    distMax: 10000,         // … and hidden beyond this
    // colours
    ...paletteFromAccent(ROLE_META.member.accent),
    // effects
    textAnimation: 'default',
    glow: true,
    pulse: false,
    spin: true,
    particles: false,
    underlineSweep: false,
    glitch: false,
    effects: true,
    grid: false,
    logoMotion: false,
});

/** Only the keys where a role differs from DEFAULTS. */
const ROLE_PRESETS = {};
for (const [role, meta] of Object.entries(ROLE_META)) {
    const p = paletteFromAccent(meta.accent);
    const diff = {};
    for (const k of COLOR_KEYS) if (p[k] !== DEFAULTS[k]) diff[k] = p[k];
    ROLE_PRESETS[role] = diff;
}

// ── Colour presets (the tag editor's preset list + `/tag preset`) ───────────
// accent → whole palette via paletteFromAccent(); `extra` tweaks individual colours on top.
const COLOR_PRESET_DEFS = {
    'Silver Surfer': { accent: '#a8bad6' },
    'Power Cosmic': { accent: '#5b8cff', extra: { glowColorB: '#b06eff', outlineColorC: '#b06eff', accentC: '#d3b3ff', underlineColorB: '#b06eff' } },
    'Lime Noir': { accent: '#8cff3c', extra: { backgroundColorA: '#0d1607', backgroundColorB: '#090f05', backgroundColorC: '#050803' } },
    'Cyber Blue': { accent: '#3cc8ff', extra: { outlineColorB: '#5b6bff', glowColorB: '#5b6bff' } },
    'Gold Royal': { accent: '#ffc440', extra: { outlineColorB: '#ff9640', outlineColorC: '#fff0b3' } },
    'Toxic': { accent: '#b6ff00', extra: { glitchColor: '#00ff9d', particleColorB: '#00ff9d' } },
    'Candy': { accent: '#ff6ed6', extra: { accentC: '#6ecbff', outlineColorB: '#6ecbff', glowColorB: '#6ecbff' } },
    'Inferno': { accent: '#ff4d2e', extra: { outlineColorB: '#ffb02e', glowColorB: '#ffb02e', backgroundColorA: '#1c0a08' } },
    'Ocean': { accent: '#2ee6c8', extra: { outlineColorB: '#3c9bff', glowColorB: '#3c9bff' } },
    'Clean Light': {
        accent: '#4a6cf7',
        extra: {
            primary: '#1b2333', nameColor: '#5b6780', textStrokeColor: '#ffffff', borderColor: '#9aa9c9',
            backgroundColorA: '#f4f6fb', backgroundColorB: '#e6eaf3', backgroundColorC: '#d5dbe8',
            outerGlowColor: '#9aa9c9', glowColorA: '#9aa9c9', glowColorC: '#9aa9c9', overlayColorB: '#ffffff', gridColor: '#9aa9c9',
        },
    },
};
const PRESET_NAMES = Object.keys(COLOR_PRESET_DEFS);
/** Full colour set for a preset (case-insensitive name). Throws TagError for unknown names. */
function presetOverrides(name) {
    const want = String(name).trim().toLowerCase();
    const key = PRESET_NAMES.find(n => n.toLowerCase() === want);
    if (!key) throw new TagError(`Unknown preset \`${name}\`. Presets: ${PRESET_NAMES.join(', ')}.`);
    const def = COLOR_PRESET_DEFS[key];
    return { ...paletteFromAccent(def.accent), ...(def.extra || {}) };
}
const COLOR_PRESETS = {};
for (const n of PRESET_NAMES) {
    const full = { ...paletteFromAccent(COLOR_PRESET_DEFS[n].accent), ...(COLOR_PRESET_DEFS[n].extra || {}) };
    const diff = {};
    for (const k of COLOR_KEYS) if (full[k] !== DEFAULTS[k]) diff[k] = full[k]; // only what differs from the defaults
    COLOR_PRESETS[n] = diff;
}

// ── Option catalogue (drives validation, autocomplete and the embed) ────────
const GROUPS = {
    text: ['label', 'userText', 'rankFont', 'userFont', 'textSize'],
    layout: ['image', 'background', 'fullWidth', 'fullHeight', 'miniSize', 'offsetFull', 'offsetMini', 'distFull', 'distMini', 'distMax'],
    colors: COLOR_KEYS,
    effects: ['textAnimation', ...EFFECT_KEYS],
};
const TYPES = {};
for (const k of COLOR_KEYS) TYPES[k] = 'color';
for (const k of EFFECT_KEYS) TYPES[k] = 'bool';
Object.assign(TYPES, {
    label: 'text', userText: 'text', rankFont: 'font', userFont: 'font', textSize: 'int',
    image: 'asset', background: 'asset',
    fullWidth: 'int', fullHeight: 'int', miniSize: 'int',
    offsetFull: 'float', offsetMini: 'float', distFull: 'float', distMini: 'float', distMax: 'float',
    textAnimation: 'enum',
});
const RANGES = {
    textSize: [8, 28], fullWidth: [0, 400], fullHeight: [24, 90], miniSize: [16, 90],
    offsetFull: [-5, 15], offsetMini: [-5, 15], distFull: [1, 100000], distMini: [1, 100000], distMax: [1, 100000],
};
// "Composite" names accepted by /tag set (they expand into several stored keys).
const COMPOSITES = ['fullSize', 'offsets', 'distances'];
const ALL_OPTION_NAMES = [...GROUPS.text, ...COMPOSITES, ...GROUPS.layout, ...COLOR_KEYS, ...GROUPS.effects];

// ── Parsing / validation ────────────────────────────────────────────────────
class TagError extends Error {}
const RESET_WORDS = new Set(['default', 'reset', 'clear', 'auto-reset']);
const isReset = raw => RESET_WORDS.has(String(raw).trim().toLowerCase());
const cleanText = (v, max) => String(v ?? '').replace(/[\u0000-\u001f\u007f<>]/g, '').trim().slice(0, max);

function parseColor(raw) {
    let s = String(raw).trim().toLowerCase();
    let m = /^#?([0-9a-f]{6})$/.exec(s);
    if (m) return '#' + m[1];
    m = /^#?([0-9a-f])([0-9a-f])([0-9a-f])$/.exec(s);
    if (m) return '#' + m[1] + m[1] + m[2] + m[2] + m[3] + m[3];
    m = /^(?:rgb\()?\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*\)?$/.exec(s);
    if (m && [m[1], m[2], m[3]].every(n => Number(n) <= 255)) return rgbToHex(+m[1], +m[2], +m[3]);
    throw new TagError(`\`${raw}\` isn't a colour — use hex like \`#ff8800\` (or \`255,136,0\`).`);
}
function parseBool(raw) {
    const s = String(raw).trim().toLowerCase();
    if (['on', 'true', 'yes', 'y', '1', 'enable', 'enabled'].includes(s)) return true;
    if (['off', 'false', 'no', 'n', '0', 'disable', 'disabled'].includes(s)) return false;
    throw new TagError(`\`${raw}\` should be on or off.`);
}
function parseAsset(raw) {
    const s = String(raw).trim();
    if (['', 'none', 'off', 'null'].includes(s.toLowerCase())) return '';
    let m = /^rbxassetid:\/\/(\d{1,20})$/i.exec(s) || /^(\d{1,20})$/.exec(s);
    if (!m) m = /(?:library|asset|store\/asset|catalog)\/(\d{1,20})/i.exec(s);
    if (!m) throw new TagError('Image must be an asset id like `1270554045585765` or `rbxassetid://1270554045585765` (or `none`).');
    return `rbxassetid://${m[1]}`;
}
function parseNumber(key, raw, int) {
    const n = Number(String(raw).trim().replace(',', '.'));
    if (!Number.isFinite(n)) throw new TagError(`\`${key}\` needs a number (got \`${raw}\`).`);
    const [lo, hi] = RANGES[key] || [-Infinity, Infinity];
    if (n < lo || n > hi) throw new TagError(`\`${key}\` must be between ${lo} and ${hi}.`);
    return int ? Math.round(n) : Math.round(n * 100) / 100;
}
function matchFont(raw) {
    const s = String(raw).trim().toLowerCase().replace(/[\s_-]/g, '');
    const hit = FONTS.find(f => f.toLowerCase() === s);
    if (!hit) throw new TagError(`Unknown font \`${raw}\`. Try one of: ${FONTS.slice(0, 12).join(', ')}, … (use the autocomplete list).`);
    return hit;
}
function splitNums(raw) { return String(raw).trim().split(/[\s/,;|]+/).filter(Boolean); }

/**
 * Turn one user-supplied (key, raw value) into the flat keys it changes.
 * Returns { set: {key: value}, unset: [key…] }. Throws TagError with a readable message.
 */
function parseOption(key, raw) {
    const canonical = ALL_OPTION_NAMES.find(k => k.toLowerCase() === String(key).replace(/[\s_-]/g, '').toLowerCase());
    if (!canonical) throw new TagError(`Unknown option \`${key}\`.`);
    key = canonical;
    const set = {}, unset = [];

    if (COMPOSITES.includes(key)) {
        if (isReset(raw)) {
            const keys = key === 'fullSize' ? ['fullWidth', 'fullHeight'] : key === 'offsets' ? ['offsetFull', 'offsetMini'] : ['distFull', 'distMini', 'distMax'];
            return { set, unset: keys };
        }
        if (key === 'fullSize') {
            const m = /^\s*(auto|\d+)\s*[x×*]\s*(\d+)\s*$/i.exec(String(raw));
            if (!m) throw new TagError('Full size looks like `168x34` (width x height) or `auto x 42`.');
            set.fullWidth = parseNumber('fullWidth', m[1].toLowerCase() === 'auto' ? 0 : m[1], true);
            set.fullHeight = parseNumber('fullHeight', m[2], true);
        } else if (key === 'offsets') {
            const p = splitNums(raw);
            if (p.length < 1 || p.length > 2) throw new TagError('Offsets look like `3.05/2.65` (full / mini, in studs above the head).');
            set.offsetFull = parseNumber('offsetFull', p[0]);
            set.offsetMini = parseNumber('offsetMini', p[1] ?? p[0]);
        } else {
            const p = splitNums(raw);
            if (p.length < 2 || p.length > 3) throw new TagError('Distances look like `12/20/10000` (full card until / logo only from / hidden beyond).');
            const [a, b, c] = [parseNumber('distFull', p[0]), parseNumber('distMini', p[1]), p[2] === undefined ? DEFAULTS.distMax : parseNumber('distMax', p[2])];
            if (!(a <= b && b <= c)) throw new TagError('Distances must go up: full ≤ mini ≤ max (for example `12/20/10000`).');
            Object.assign(set, { distFull: a, distMini: b, distMax: c });
        }
        return { set, unset };
    }

    if (isReset(raw)) return { set, unset: [key] };

    switch (TYPES[key]) {
        case 'color': set[key] = parseColor(raw); break;
        case 'bool': set[key] = parseBool(raw); break;
        case 'asset': set[key] = parseAsset(raw); break;
        case 'font': set[key] = matchFont(raw); break;
        case 'int': set[key] = parseNumber(key, raw, true); break;
        case 'float': set[key] = parseNumber(key, raw, false); break;
        case 'enum': {
            const v = String(raw).trim().toLowerCase();
            if (!ANIMATIONS.includes(v)) throw new TagError(`Text animation must be one of: ${ANIMATIONS.join(', ')}.`);
            set[key] = v; break;
        }
        case 'text': {
            const v = cleanText(raw, 24);
            if (key === 'label') {
                if (!v) throw new TagError('Label can\'t be empty (use `default` to go back to the role\'s label).');
                set[key] = v;
            } else { // userText
                const low = v.toLowerCase();
                set[key] = low === 'auto' ? 'auto' : low === 'none' || v === '' ? 'none' : v;
            }
            break;
        }
        default: throw new TagError(`Unknown option \`${key}\`.`);
    }
    return { set, unset };
}

/** Apply parseOption results to an overrides object. Returns a NEW object (nothing is mutated). */
function applyOption(overrides, key, raw) {
    const { set, unset } = parseOption(key, raw);
    const next = { ...overrides };
    for (const k of unset) delete next[k];
    Object.assign(next, set);
    return next;
}

/** Paint the whole palette from one colour: `/tag theme`. */
function themeOverrides(hexRaw) {
    return paletteFromAccent(parseColor(hexRaw));
}

/** Drop unknown keys / wrong types (used when loading data/tags.json). */
function sanitizeOverrides(obj) {
    const out = {};
    if (!obj || typeof obj !== 'object') return out;
    for (const [k, v] of Object.entries(obj)) {
        if (!Object.prototype.hasOwnProperty.call(DEFAULTS, k) || typeof v !== typeof DEFAULTS[k]) continue;
        out[k] = v;
    }
    return out;
}

// ── Export codes (SCORPTAG1.<base64url(json)>.<adler32>) ─────────────────────
// The in-game tag editor and the Discord bot both speak this format. The JSON is only the options
// that differ from DEFAULTS; the trailing checksum catches truncated / mangled copy-pastes.
const CODE_PREFIX = 'SCORPTAG1';
const MAX_CODE_CHARS = 12000;
const MAX_JSON_BYTES = 8192;

function adler32(buf) {
    let a = 1, b = 0;
    for (const byte of buf) { a = (a + byte) % 65521; b = (b + a) % 65521; }
    return ((b * 65536) + a) >>> 0;
}
const hex8 = n => n.toString(16).padStart(8, '0');

function encodeCode(overrides) {
    const clean = sanitizeOverrides(overrides);
    const keys = Object.keys(clean).sort();
    const json = JSON.stringify(Object.fromEntries(keys.map(k => [k, clean[k]])));
    const bytes = Buffer.from(json, 'utf8');
    return `${CODE_PREFIX}.${bytes.toString('base64url')}.${hex8(adler32(bytes))}`;
}

const asRaw = v => (typeof v === 'boolean' ? (v ? 'on' : 'off') : String(v));

/**
 * Strictly validate a plain { key: value } object (from an import code or an API body).
 * Every value goes through the same parser as /tag set. Returns
 *   { overrides, ignored: [unknown keys], invalid: ['primary: …message'] }.
 */
function importOverrides(obj) {
    const overrides = {}, ignored = [], invalid = [];
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) throw new TagError('That code doesn\'t contain a tag design.');
    for (const key of Object.keys(obj)) {
        if (!Object.prototype.hasOwnProperty.call(DEFAULTS, key)) { ignored.push(String(key).slice(0, 30)); continue; }
        const v = obj[key];
        if (!['string', 'number', 'boolean'].includes(typeof v) || typeof v !== typeof DEFAULTS[key]) { invalid.push(`${key}: wrong type`); continue; }
        try {
            const { set } = parseOption(key, asRaw(v));
            Object.assign(overrides, set);
        } catch (e) {
            if (!(e instanceof TagError)) throw e;
            invalid.push(`${key}: ${e.message.replace(/`/g, '')}`);
        }
    }
    return { overrides, ignored, invalid };
}

/** Code string → { overrides, ignored, invalid }. Throws TagError with a readable reason. */
function decodeCode(raw) {
    const code = String(raw ?? '').replace(/[`\s"']/g, '');
    if (!code) throw new TagError('Paste an export code (it starts with `SCORPTAG1.`).');
    if (code.length > MAX_CODE_CHARS) throw new TagError('That code is too long.');
    const parts = code.split('.');
    if (parts[0] !== CODE_PREFIX) throw new TagError('That isn\'t a Scorp tag code (it should start with `SCORPTAG1.`).');
    if (parts.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(parts[1]) || !/^[0-9a-f]{8}$/i.test(parts[2])) {
        throw new TagError('The code looks cut off or mangled — copy the whole thing again.');
    }
    const bytes = Buffer.from(parts[1], 'base64url');
    if (bytes.length > MAX_JSON_BYTES) throw new TagError('That code is too big to be a tag design.');
    if (hex8(adler32(bytes)) !== parts[2].toLowerCase()) throw new TagError('Checksum mismatch — the code was changed or cut off. Copy it again.');
    let obj;
    try { obj = JSON.parse(bytes.toString('utf8')); } catch { throw new TagError('The code\'s contents aren\'t readable.'); }
    return importOverrides(obj);
}

// ── Effective config + display ──────────────────────────────────────────────
function effectiveTag(role, overrides, roleLabel) {
    const eff = { ...DEFAULTS, ...(ROLE_PRESETS[role] || {}), ...sanitizeOverrides(overrides) };
    if (!eff.label) eff.label = roleLabel || (ROLE_META[role] || ROLE_META.member).label;
    return eff;
}

const fmtNum = n => String(Math.round(n * 100) / 100);
const on = v => (v ? 'on' : 'off');

/** Everything the embed prints, already formatted. */
function describe(eff) {
    return {
        text: [
            ['Label', eff.label],
            ['User text', eff.userText === 'auto' ? 'auto' : eff.userText],
            ['Rank font', eff.rankFont],
            ['User font', eff.userFont],
            ['Text size', String(eff.textSize)],
        ],
        layout: [
            ['Image', eff.image || 'none'],
            ['Background', eff.background || 'none'],
            ['Full', `${eff.fullWidth ? eff.fullWidth : 'auto'}x${eff.fullHeight}`],
            ['Mini', String(eff.miniSize)],
            ['Offsets', `${fmtNum(eff.offsetFull)}/${fmtNum(eff.offsetMini)}`],
            ['Distances', `${fmtNum(eff.distFull)}/${fmtNum(eff.distMini)}/${fmtNum(eff.distMax)}`],
        ],
        colors: COLOR_KEYS.map(k => [k, eff[k]]),
        effects: [['textAnimation', eff.textAnimation], ...EFFECT_KEYS.map(k => [k, on(eff[k])])],
    };
}

// ── Lua export (inlined into nametags.lua at build time) ────────────────────
const luaStr = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';
function luaValue(v, depth = 1) {
    if (typeof v === 'string') return luaStr(v);
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (Array.isArray(v)) return '{ ' + v.map(x => luaValue(x, depth + 1)).join(', ') + ' }';
    const pad = '    '.repeat(depth), end = '    '.repeat(depth - 1);
    const rows = Object.keys(v).sort().map(k => `${pad}${/^[A-Za-z_]\w*$/.test(k) ? k : `[${luaStr(k)}]`} = ${luaValue(v[k], depth + 1)},`);
    return rows.length ? `{\n${rows.join('\n')}\n${end}}` : '{}';
}
function toLua() {
    const data = { defaults: { ...DEFAULTS }, presets: ROLE_PRESETS, roles: ROLE_META, animations: ANIMATIONS, fonts: FONTS, colorKeys: COLOR_KEYS, colorPresets: COLOR_PRESETS, presetOrder: PRESET_NAMES, ranges: RANGES, codePrefix: CODE_PREFIX };
    return `-- GENERATED from src/tagconfig.js at build time — do not edit by hand.\nlocal TAGDATA = ${luaValue(data)}\n`;
}

module.exports = {
    ROLE_META, FONTS, ANIMATIONS, COLOR_KEYS, EFFECT_KEYS, GROUPS, COMPOSITES, ALL_OPTION_NAMES, TYPES, RANGES,
    DEFAULTS, ROLE_PRESETS, TagError,
    paletteFromAccent, parseOption, applyOption, themeOverrides, sanitizeOverrides, effectiveTag, describe, toLua,
    parseColor, parseAsset, lerpHex,
    PRESET_NAMES, COLOR_PRESETS, presetOverrides, encodeCode, decodeCode, importOverrides, adler32, CODE_PREFIX,
};
