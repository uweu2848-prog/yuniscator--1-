'use strict';
/**
 * Scorp build pipeline
 *
 *   src/script.lua  (+ any `--@include file.lua` lines it contains)
 *        │  bundle → validate → rename locals → strip comments →
 *        │  encrypt strings → minify → validate again
 *        ▼
 *   dist/script.lua  +  dist/build.json (id / time / size, so you can SEE which build is live)
 *
 * Usage
 *   node obfuscate.js            one-off build
 *   node obfuscate.js --watch    rebuild whenever anything in src/ changes
 *   require('./obfuscate')       used by src/server.js, which rebuilds on boot and
 *                                whenever a source file is newer than the last build
 *
 * Honest limits: this raises the effort needed to read the script (no plaintext
 * strings, no readable local names) but it is not a virtualizer. Anything the
 * client can execute, the client can eventually dump.
 *
 * Source rules (the parser is Lua 5.1 — the same subset luaparse understands):
 *   - no Luau-only syntax in files that get obfuscated (no `continue`, `+=`,
 *     type annotations, `if x then y else z` expressions)
 *   - never start a statement with `(` — output is minified onto one line, so
 *     a leading paren would be parsed as a call on the previous statement
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const luaparse = require('luaparse');

const ROOT = __dirname;
const SRC_DIR = path.join(ROOT, 'src');
const ENTRY = path.join(SRC_DIR, 'script.lua');
const OUT_DIR = path.join(ROOT, 'dist');
const OUT_FILE = path.join(OUT_DIR, 'script.lua');
const META_FILE = path.join(OUT_DIR, 'build.json');

const PARSE = { luaVersion: '5.1' };

// ────────────────────────────────────────────────────────────────────────────
// Random names
// ────────────────────────────────────────────────────────────────────────────
function randomFrom(chars, n) {
    let out = '';
    const bytes = crypto.randomBytes(n);
    for (let i = 0; i < n; i++) out += chars[bytes[i] % chars.length];
    return out;
}
const hexName = (n = 6) => '_0x' + randomFrom('0123456789abcdef', n);
const varName = () => '_' + randomFrom('abcdefghijklmnopqrstuvwxyz0123456789', 7);

// ────────────────────────────────────────────────────────────────────────────
// Bundling:  a line that is exactly   --@include nametags.lua   is replaced by
// the contents of src/nametags.lua. Lets the nametag design live in its own file.
// ────────────────────────────────────────────────────────────────────────────
const INCLUDE_RE = /^[ \t]*--@include[ \t]+([\w./-]+)[ \t]*$/gm;
const TAGDATA_RE = /^[ \t]*--@tagdata[ \t]*$/gm;

function bundle(entry = ENTRY) {
    const files = new Set();
    function load(file, stack) {
        const resolved = path.resolve(file);
        if (!resolved.startsWith(SRC_DIR + path.sep)) {
            throw new Error(`--@include escapes src/: ${file}`);
        }
        if (stack.includes(resolved)) {
            throw new Error(`circular --@include: ${[...stack, resolved].map(p => path.basename(p)).join(' -> ')}`);
        }
        if (!fs.existsSync(resolved)) throw new Error(`--@include target not found: ${path.relative(ROOT, resolved)}`);
        files.add(resolved);
        let text = fs.readFileSync(resolved, 'utf8').replace(/\r\n/g, '\n');
        // `--@tagdata` → the nametag defaults / role presets generated from src/tagconfig.js, so the
        // in-game renderer and the Discord bot's embed can never disagree about a default.
        text = text.replace(TAGDATA_RE, () => {
            const tagconfigPath = path.join(SRC_DIR, 'tagconfig.js');
            files.add(tagconfigPath);
            if (require.main === module) delete require.cache[require.resolve(tagconfigPath)]; // --watch picks up edits
            return require(tagconfigPath).toLua();
        });
        return text.replace(INCLUDE_RE, (_m, rel) => load(path.join(SRC_DIR, rel), [...stack, resolved]));
    }
    const code = load(entry, []);
    return { code, files: [...files] };
}

// ────────────────────────────────────────────────────────────────────────────
// Local-variable renaming (real scope resolution; globals and table/method
// names are never touched)
// ────────────────────────────────────────────────────────────────────────────
class Scope {
    constructor(parent) { this.parent = parent; this.vars = new Map(); }
    declare(name) { const n = varName(); this.vars.set(name, n); return n; }
    resolve(name) {
        for (let s = this; s; s = s.parent) if (s.vars.has(name)) return s.vars.get(name);
        return null;
    }
}

function renameLocalsInSource(sourceCode) {
    const ast = luaparse.parse(sourceCode, { ...PARSE, ranges: true });
    const edits = [];
    const rename = (node, newName) => edits.push([node.range[0], node.range[1], newName]);

    function visitExpr(node, scope) {
        if (!node) return;
        switch (node.type) {
            case 'Identifier': {
                if (node.name === 'self') return;
                const n = scope.resolve(node.name);
                if (n) rename(node, n);
                return;
            }
            case 'MemberExpression': visitExpr(node.base, scope); return;
            case 'IndexExpression': visitExpr(node.base, scope); visitExpr(node.index, scope); return;
            case 'CallExpression':
                visitExpr(node.base, scope);
                (node.arguments || []).forEach(a => visitExpr(a, scope));
                return;
            case 'TableCallExpression': visitExpr(node.base, scope); visitExpr(node.arguments, scope); return;
            case 'StringCallExpression': visitExpr(node.base, scope); return;
            case 'BinaryExpression':
            case 'LogicalExpression': visitExpr(node.left, scope); visitExpr(node.right, scope); return;
            case 'UnaryExpression': visitExpr(node.argument, scope); return;
            case 'ParenthesisExpression': visitExpr(node.expression, scope); return;
            case 'TableConstructorExpression':
                (node.fields || []).forEach(f => {
                    if (f.type === 'TableKey') { visitExpr(f.key, scope); visitExpr(f.value, scope); }
                    else visitExpr(f.value, scope); // TableKeyString key is a field name; TableValue has only a value
                });
                return;
            case 'FunctionDeclaration': {
                const fnScope = new Scope(scope);
                (node.parameters || []).forEach(p => {
                    if (p.type === 'Identifier' && p.name !== 'self') rename(p, fnScope.declare(p.name));
                });
                (node.body || []).forEach(s => visitStatement(s, fnScope));
                return;
            }
            default: return; // literals, varargs
        }
    }

    function visitBlock(body, parentScope) {
        const scope = new Scope(parentScope);
        (body || []).forEach(s => visitStatement(s, scope));
    }

    function visitStatement(stmt, scope) {
        switch (stmt.type) {
            case 'LocalStatement':
                (stmt.init || []).forEach(e => visitExpr(e, scope)); // RHS sees the OLD scope
                stmt.variables.forEach(v => rename(v, scope.declare(v.name)));
                return;
            case 'AssignmentStatement':
                (stmt.init || []).forEach(e => visitExpr(e, scope));
                stmt.variables.forEach(v => visitExpr(v, scope));
                return;
            case 'CallStatement': visitExpr(stmt.expression, scope); return;
            case 'DoStatement': visitBlock(stmt.body, scope); return;
            case 'WhileStatement': visitExpr(stmt.condition, scope); visitBlock(stmt.body, scope); return;
            case 'RepeatStatement': {
                const bodyScope = new Scope(scope); // `until` can see the body's locals
                (stmt.body || []).forEach(s => visitStatement(s, bodyScope));
                visitExpr(stmt.condition, bodyScope);
                return;
            }
            case 'IfStatement':
                (stmt.clauses || []).forEach(c => {
                    if (c.condition) visitExpr(c.condition, scope);
                    visitBlock(c.body, scope);
                });
                return;
            case 'ForNumericStatement': {
                visitExpr(stmt.start, scope); visitExpr(stmt.end, scope);
                if (stmt.step) visitExpr(stmt.step, scope);
                const loop = new Scope(scope);
                rename(stmt.variable, loop.declare(stmt.variable.name));
                (stmt.body || []).forEach(s => visitStatement(s, loop));
                return;
            }
            case 'ForGenericStatement': {
                (stmt.iterators || []).forEach(it => visitExpr(it, scope));
                const loop = new Scope(scope);
                stmt.variables.forEach(v => rename(v, loop.declare(v.name)));
                (stmt.body || []).forEach(s => visitStatement(s, loop));
                return;
            }
            case 'FunctionDeclaration': {
                if (stmt.isLocal && stmt.identifier && stmt.identifier.type === 'Identifier') {
                    rename(stmt.identifier, scope.declare(stmt.identifier.name)); // visible inside its own body
                } else if (stmt.identifier) {
                    visitExpr(stmt.identifier, scope);
                }
                const fnScope = new Scope(scope);
                (stmt.parameters || []).forEach(p => {
                    if (p.type === 'Identifier' && p.name !== 'self') rename(p, fnScope.declare(p.name));
                });
                (stmt.body || []).forEach(s => visitStatement(s, fnScope));
                return;
            }
            case 'ReturnStatement': (stmt.arguments || []).forEach(a => visitExpr(a, scope)); return;
            default: return;
        }
    }

    const root = new Scope(null);
    (ast.body || []).forEach(s => visitStatement(s, root));
    return applyEdits(sourceCode, edits);
}

function applyEdits(source, edits) {
    edits.sort((a, b) => b[0] - a[0]);
    let out = source;
    for (const [start, end, text] of edits) out = out.slice(0, start) + text + out.slice(end);
    return out;
}

// Comments are removed using the parser's own ranges, so the body of a
// multi-line --[[ ]] comment can never be left behind as bare code.
function stripComments(source) {
    const ast = luaparse.parse(source, { ...PARSE, comments: true, ranges: true });
    const edits = (ast.comments || []).map(c => [c.range[0], c.range[1], ' ']);
    return applyEdits(source, edits);
}

// ────────────────────────────────────────────────────────────────────────────
// String literals → encrypted byte tables
//
// Found via the AST (not a regex), so quotes inside long strings, escaped
// quotes, `foo"bar"` call syntax, and [[long strings]] are all handled.
// luaStringBytes() decodes Lua escapes to the exact bytes Lua itself would
// produce. It throws on anything it doesn't understand, so a bad string fails
// the build loudly instead of shipping a script that decrypts wrongly.
// ────────────────────────────────────────────────────────────────────────────
function luaStringBytes(raw) {
    const long = /^\[(=*)\[/.exec(raw);
    if (long) {
        const eq = long[1].length;
        let body = raw.slice(eq + 2, raw.length - (eq + 2));
        if (body.startsWith('\r\n')) body = body.slice(2);
        else if (body[0] === '\n' || body[0] === '\r') body = body.slice(1);
        return [...Buffer.from(body, 'utf8')];
    }

    const inner = raw.slice(1, -1);
    const out = [];
    const utf8 = s => out.push(...Buffer.from(s, 'utf8'));
    for (let i = 0; i < inner.length;) {
        const ch = inner[i];
        if (ch !== '\\') {
            const cp = String.fromCodePoint(inner.codePointAt(i));
            utf8(cp);
            i += cp.length;
            continue;
        }
        const n = inner[i + 1];
        i += 2;
        switch (n) {
            case 'n': out.push(10); break;
            case 't': out.push(9); break;
            case 'r': out.push(13); break;
            case 'a': out.push(7); break;
            case 'b': out.push(8); break;
            case 'f': out.push(12); break;
            case 'v': out.push(11); break;
            case '\\': out.push(92); break;
            case '"': out.push(34); break;
            case "'": out.push(39); break;
            case '\n': out.push(10); break;
            case '\r': out.push(10); if (inner[i] === '\n') i++; break;
            case 'z': while (i < inner.length && /\s/.test(inner[i])) i++; break;
            case 'x': {
                const hex = inner.slice(i, i + 2);
                if (!/^[0-9a-fA-F]{2}$/.test(hex)) throw new Error(`bad \\x escape in ${raw}`);
                out.push(parseInt(hex, 16));
                i += 2;
                break;
            }
            case 'u': {
                const m = /^\{([0-9a-fA-F]+)\}/.exec(inner.slice(i));
                if (!m) throw new Error(`bad \\u escape in ${raw}`);
                utf8(String.fromCodePoint(parseInt(m[1], 16)));
                i += m[0].length;
                break;
            }
            default: {
                if (n >= '0' && n <= '9') {
                    let digits = n;
                    while (digits.length < 3 && inner[i] >= '0' && inner[i] <= '9') digits += inner[i++];
                    const v = parseInt(digits, 10);
                    if (v > 255) throw new Error(`decimal escape too large in ${raw}`);
                    out.push(v);
                } else {
                    throw new Error(`unsupported escape \\${n} in ${raw}`);
                }
            }
        }
    }
    return out;
}

function encryptStrings(source, decryptName) {
    const ast = luaparse.parse(source, { ...PARSE, ranges: true });

    // Collect every StringLiteral, remembering whether it is the argument of `f"str"` / f[[str]]
    const found = [];
    (function walk(node, parent) {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { node.forEach(n => walk(n, parent)); return; }
        if (node.type === 'StringLiteral') {
            found.push({ node, callArg: !!(parent && parent.type === 'StringCallExpression' && parent.argument === node) });
            return;
        }
        for (const key of Object.keys(node)) {
            if (key === 'range' || key === 'loc') continue;
            walk(node[key], node.type ? node : parent);
        }
    })(ast);

    const keyLen = 4 + (crypto.randomBytes(1)[0] % 5);
    const key = Array.from(crypto.randomBytes(keyLen), b => (b % 255) + 1);
    const rows = [];
    const edits = [];

    for (const { node, callArg } of found) {
        const bytes = luaStringBytes(node.raw);
        if (bytes.length === 0) continue; // "" stays as-is
        const enc = bytes.map((b, i) => b ^ key[i % key.length]);
        rows.push(`{${enc.join(',')}}`);
        const call = `${decryptName}(${rows.length})`;
        edits.push([node.range[0], node.range[1], callArg ? `(${call})` : call]);
    }
    return { code: applyEdits(source, edits), rows, key };
}

// ────────────────────────────────────────────────────────────────────────────
// Full pipeline on one source string
// ────────────────────────────────────────────────────────────────────────────
function obfuscateSource(sourceCode, label = 'script') {
    try { luaparse.parse(sourceCode, PARSE); }
    catch (err) { throw new Error(`[${label}] Lua syntax error before obfuscation: ${err.message}`); }

    const renamed = renameLocalsInSource(sourceCode);
    try { luaparse.parse(renamed, PARSE); }
    catch (err) { throw new Error(`[${label}] local renaming produced invalid Lua: ${err.message}`); }

    const stripped = stripComments(renamed);
    const T = hexName(), K = hexName(), C = hexName(), D = hexName(), W = hexName(8);
    const SC = hexName(), BX = hexName(), TC = hexName();
    const { code: decrypted, rows, key } = encryptStrings(stripped, D);

    const header = `
local ${SC}, ${BX}, ${TC} = string.char, bit32.bxor, table.concat
local ${K} = {${key.join(',')}}
local ${T} = {
${rows.join(',\n')}
}
local ${C} = {}
local function ${D}(i)
    local v = ${C}[i]
    if v then return v end
    local bytes = ${T}[i]
    local chars = {}
    for j = 1, #bytes do
        chars[j] = ${SC}(${BX}(bytes[j], ${K}[((j - 1) % #${K}) + 1]))
    end
    v = ${TC}(chars)
    ${C}[i] = v
    return v
end
`;
    // Pass the loader's context table through (`local ctx = ...` inside the script)
    const minified = `${header}\n${decrypted}`.replace(/\s+/g, ' ').trim();
    const result = `local ${W} = function(...) ${minified} end; return ${W}(...)`;

    try { luaparse.parse(result, PARSE); }
    catch (err) { throw new Error(`[${label}] obfuscated output is invalid Lua: ${err.message}`); }
    return result;
}

// ────────────────────────────────────────────────────────────────────────────
// Build / staleness
// ────────────────────────────────────────────────────────────────────────────
function listSourceFiles() {
    const out = [];
    (function walk(dir) {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
            const p = path.join(dir, e.name);
            if (e.isDirectory()) walk(p);
            else if (e.name.endsWith('.lua')) out.push(p);
        }
    })(SRC_DIR);
    return out;
}

// Newest mtime among files that go into the payload (script.lua + every --@include).
function newestSourceMtime() {
    let newest = 0;
    let files;
    try { files = bundle().files; } catch { files = [ENTRY]; }
    for (const f of files) {
        try { newest = Math.max(newest, fs.statSync(f).mtimeMs); } catch { /* ignore */ }
    }
    return newest;
}

let lastBuild = null; // { id, builtAt, bytes, sourceMtime, code, files }

function build({ write = true } = {}) {
    if (!fs.existsSync(ENTRY)) throw new Error('Source file not found: src/script.lua');
    const { code: raw, files } = bundle();
    const code = obfuscateSource(raw, 'script.lua');
    const id = crypto.createHash('sha256').update(code).digest('hex').slice(0, 8);
    const meta = {
        id,
        builtAt: new Date().toISOString(),
        bytes: Buffer.byteLength(code),
        sources: files.map(f => path.relative(ROOT, f).replace(/\\/g, '/')),
    };
    if (write) {
        fs.mkdirSync(OUT_DIR, { recursive: true });
        fs.writeFileSync(OUT_FILE, code);
        fs.writeFileSync(META_FILE, JSON.stringify(meta, null, 2));
    }
    lastBuild = { ...meta, code, sourceMtime: newestSourceMtime() };
    return lastBuild;
}

function needsRebuild() {
    if (!lastBuild) return true;
    return newestSourceMtime() > lastBuild.sourceMtime;
}

function getBuild() { return lastBuild; }

module.exports = { build, needsRebuild, getBuild, obfuscateSource, luaStringBytes, bundle, OUT_FILE, ENTRY, SRC_DIR };

// ────────────────────────────────────────────────────────────────────────────
// CLI
// ────────────────────────────────────────────────────────────────────────────
if (require.main === module) {
    const run = () => {
        const t0 = Date.now();
        const b = build();
        console.log(`[build] ${new Date().toLocaleTimeString()}  id=${b.id}  ${(b.bytes / 1024).toFixed(1)} KB  ` +
            `${b.sources.join(', ')}  (${Date.now() - t0} ms)  → dist/script.lua`);
    };
    try { run(); } catch (e) { console.error('[build] FAILED:', e.message); process.exit(1); }

    if (process.argv.includes('--watch')) {
        console.log('[build] watching src/ …  (Ctrl+C to stop)');
        let timer = null;
        fs.watch(SRC_DIR, { recursive: true }, (_evt, file) => {
            if (!file || !String(file).endsWith('.lua')) return;
            clearTimeout(timer);
            timer = setTimeout(() => { try { run(); } catch (e) { console.error('[build] FAILED:', e.message); } }, 150);
        });
    }
}
