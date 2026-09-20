const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

// ────────────────────────────────────────────────────────────────────────────
// Honest limits of this file, read before you trust it:
//
// This is a source-level obfuscator (string encryption + local-variable
// renaming + comment/whitespace stripping), not a real virtualizer or
// control-flow flattener. It stops someone from Ctrl+F-ing your code for
// plaintext strings or reading your original variable names, but anyone who
// runs the output through a Luau deobfuscator/beautifier, or just hooks the
// decrypt function and dumps what it returns at runtime, gets your logic
// back. There is no such thing as an unbreakable client-side script in
// Roblox — the client has to be able to execute it, which means the client
// has everything it needs to eventually read it. What this buys you is time
// and effort, not certainty. The real protection is keeping your most
// valuable logic server-side (see CHANGES.md) so the obfuscated client code
// is never the whole picture.
// ────────────────────────────────────────────────────────────────────────────

function generateHexName(length = 8) {
    let result = '_0x';
    const chars = '0123456789abcdef';
    for (let i = 0; i < length; i++) {
        result += chars[Math.floor(Math.random() * chars.length)];
    }
    return result;
}

// Short random identifier for a renamed local variable. Always starts with
// "_" so it can never collide with a Lua keyword (keywords are plain
// lowercase letters, no underscore).
function generateVarName() {
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    let result = '_';
    for (let i = 0; i < 7; i++) {
        result += chars[Math.floor(Math.random() * chars.length)];
    }
    return result;
}

// ────────────────────────────────────────────────────────────────────────────
// Local-variable renaming
//
// Walks the AST doing real Lua scope resolution (locals, function params,
// for-loop variables, local function names) and renames every one of them
// to a random identifier, while leaving table/property keys, method names,
// and globals (game, Enum, Color3, string, table, pcall, print, warn, ...)
// completely alone. This is what stops someone reading obfuscated output
// and immediately understanding your code from names like `Window`,
// `sec`, `stub`, `runChecks`, `AUTO_BAN_THRESHOLD`, etc.
//
// Renaming is done by collecting {start, end, text} edits from the AST's
// own character ranges and splicing them into the source from the end
// backwards — the same range-surgery approach stripComments() already used
// below, just driven by scope resolution instead of comment boundaries.
// ────────────────────────────────────────────────────────────────────────────

class Scope {
    constructor(parent) {
        this.parent = parent;
        this.vars = new Map();
    }
    declare(name) {
        const newName = generateVarName();
        this.vars.set(name, newName);
        return newName;
    }
    resolve(name) {
        let s = this;
        while (s) {
            if (s.vars.has(name)) return s.vars.get(name);
            s = s.parent;
        }
        return null; // not a local anywhere in scope -> it's a global, leave it alone
    }
}

function renameLocalsInSource(sourceCode) {
    const ast = luaparse.parse(sourceCode, { luaVersion: '5.1', ranges: true });
    const edits = [];

    function pushRename(identifierNode, newName) {
        edits.push([identifierNode.range[0], identifierNode.range[1], newName]);
    }

    // Visits an EXPRESSION subtree, renaming any bare Identifier that
    // resolves to a local variable in `scope`. Property names on tables
    // (MemberExpression.identifier, TableKeyString.key) are deliberately
    // never visited here, since renaming those would break real API calls
    // like Window:CreateTab(...) or { Title = "Scorp" }.
    function visitExpr(node, scope) {
        if (!node) return;
        switch (node.type) {
            case 'Identifier': {
                if (node.name === 'self') return; // implicit method receiver, never renamed
                const newName = scope.resolve(node.name);
                if (newName) pushRename(node, newName);
                return;
            }
            case 'MemberExpression':
                visitExpr(node.base, scope);
                return; // node.identifier is a property/method name, not a variable
            case 'IndexExpression':
                visitExpr(node.base, scope);
                visitExpr(node.index, scope);
                return;
            case 'CallExpression':
                visitExpr(node.base, scope);
                (node.arguments || []).forEach(a => visitExpr(a, scope));
                return;
            case 'TableCallExpression':
                visitExpr(node.base, scope);
                visitExpr(node.arguments, scope);
                return;
            case 'StringCallExpression':
                visitExpr(node.base, scope);
                return; // argument is a bare string literal
            case 'BinaryExpression':
            case 'LogicalExpression':
                visitExpr(node.left, scope);
                visitExpr(node.right, scope);
                return;
            case 'UnaryExpression':
                visitExpr(node.argument, scope);
                return;
            case 'ParenthesisExpression':
                visitExpr(node.expression, scope);
                return;
            case 'TableConstructorExpression':
                (node.fields || []).forEach(f => {
                    if (f.type === 'TableKey') {
                        visitExpr(f.key, scope);
                        visitExpr(f.value, scope);
                    } else if (f.type === 'TableKeyString') {
                        visitExpr(f.value, scope); // f.key is a field name, not a variable
                    } else if (f.type === 'TableValue') {
                        visitExpr(f.value, scope);
                    }
                });
                return;
            case 'FunctionDeclaration': {
                // Anonymous function used as a value (e.g. a Callback). A
                // named FunctionDeclaration only ever appears as a
                // statement, handled in visitStatement instead.
                const fnScope = new Scope(scope);
                (node.parameters || []).forEach(p => {
                    if (p.type === 'Identifier' && p.name !== 'self') {
                        const newName = fnScope.declare(p.name);
                        pushRename(p, newName);
                    }
                });
                (node.body || []).forEach(s => visitStatement(s, fnScope));
                return;
            }
            default:
                return; // literals (String/Numeric/Boolean/Nil/Vararg) — nothing to rename
        }
    }

    // Visits one BLOCK (chunk body, function body, do-block body, loop
    // body, if-clause body) as a fresh child scope, then walks its
    // statements in order so a `local x` only affects code after it.
    function visitBlock(body, parentScope) {
        const scope = new Scope(parentScope);
        (body || []).forEach(s => visitStatement(s, scope));
    }

    function visitStatement(stmt, scope) {
        switch (stmt.type) {
            case 'LocalStatement':
                // RHS is evaluated in the OLD scope, before these new
                // locals exist — this is what makes `local x = x` mean
                // "new x, initialized from whatever x meant a moment ago".
                (stmt.init || []).forEach(e => visitExpr(e, scope));
                stmt.variables.forEach(v => {
                    const newName = scope.declare(v.name);
                    pushRename(v, newName);
                });
                return;
            case 'AssignmentStatement':
                (stmt.init || []).forEach(e => visitExpr(e, scope));
                stmt.variables.forEach(v => visitExpr(v, scope));
                return;
            case 'CallStatement':
                visitExpr(stmt.expression, scope);
                return;
            case 'DoStatement':
                visitBlock(stmt.body, scope);
                return;
            case 'WhileStatement':
                visitExpr(stmt.condition, scope);
                visitBlock(stmt.body, scope);
                return;
            case 'RepeatStatement': {
                // `until` can see locals declared in the body — special
                // case in Lua, so the condition shares the body's scope
                // instead of the outer one.
                const bodyScope = new Scope(scope);
                (stmt.body || []).forEach(s => visitStatement(s, bodyScope));
                visitExpr(stmt.condition, bodyScope);
                return;
            }
            case 'IfStatement':
                (stmt.clauses || []).forEach(clause => {
                    if (clause.condition) visitExpr(clause.condition, scope);
                    visitBlock(clause.body, scope);
                });
                return;
            case 'ForNumericStatement': {
                visitExpr(stmt.start, scope);
                visitExpr(stmt.end, scope);
                if (stmt.step) visitExpr(stmt.step, scope);
                const loopScope = new Scope(scope);
                const newName = loopScope.declare(stmt.variable.name);
                pushRename(stmt.variable, newName);
                (stmt.body || []).forEach(s => visitStatement(s, loopScope));
                return;
            }
            case 'ForGenericStatement': {
                (stmt.iterators || []).forEach(it => visitExpr(it, scope));
                const loopScope = new Scope(scope);
                stmt.variables.forEach(v => {
                    const newName = loopScope.declare(v.name);
                    pushRename(v, newName);
                });
                (stmt.body || []).forEach(s => visitStatement(s, loopScope));
                return;
            }
            case 'FunctionDeclaration': {
                let fnScope;
                if (stmt.isLocal && stmt.identifier && stmt.identifier.type === 'Identifier') {
                    // `local function foo()` — foo is visible INSIDE its
                    // own body (so it can recurse), unlike
                    // `local foo = function() end`.
                    const newName = scope.declare(stmt.identifier.name);
                    pushRename(stmt.identifier, newName);
                    fnScope = new Scope(scope);
                } else {
                    // Global function, or `function tbl.foo()` / `function
                    // tbl:foo()` — the identifier is a property path, not
                    // a local variable; still resolve its base if it's a
                    // reassignment of an existing local table.
                    if (stmt.identifier) visitExpr(stmt.identifier, scope);
                    fnScope = new Scope(scope);
                }
                (stmt.parameters || []).forEach(p => {
                    if (p.type === 'Identifier' && p.name !== 'self') {
                        const newName = fnScope.declare(p.name);
                        pushRename(p, newName);
                    }
                });
                (stmt.body || []).forEach(s => visitStatement(s, fnScope));
                return;
            }
            case 'ReturnStatement':
                (stmt.arguments || []).forEach(a => visitExpr(a, scope));
                return;
            case 'BreakStatement':
            case 'GotoStatement':
            case 'LabelStatement':
                return; // nothing to rename
            default:
                return;
        }
    }

    const rootScope = new Scope(null);
    (ast.body || []).forEach(s => visitStatement(s, rootScope));

    // Apply edits from the end of the file backwards so earlier offsets
    // stay valid as we splice.
    edits.sort((a, b) => b[0] - a[0]);
    let out = sourceCode;
    for (const [start, end, text] of edits) {
        out = out.slice(0, start) + text + out.slice(end);
    }
    return out;
}

// Strips every comment (single-line -- and block --[[ ]]/--[=[ ]=]) using the
// exact ranges luaparse's own parser found, instead of a line-based regex.
// A regex that only understands `--.*$` per line leaves the *body* of a
// multi-line --[[ ]] comment behind as bare code once the -- prefix is gone,
// which is a real way to break output silently — this doesn't have that bug
// because it works from the parser's own comment boundaries.
function stripComments(sourceCode) {
    const ast = luaparse.parse(sourceCode, { luaVersion: '5.1', comments: true, ranges: true });
    const comments = (ast.comments || []).slice().sort((a, b) => b.range[0] - a.range[0]);
    let out = sourceCode;
    for (const c of comments) {
        out = out.slice(0, c.range[0]) + ' ' + out.slice(c.range[1]);
    }
    return out;
}

function xorBytes(bytes, key) {
    return bytes.map((b, i) => b ^ key[i % key.length]);
}

function obfuscateLuau(sourceCode) {
    // Parse code to validate syntax before doing anything to it
    try {
        luaparse.parse(sourceCode, { luaVersion: '5.1' });
    } catch (err) {
        console.error('Lua Syntax Error prior to obfuscation:', err.message);
        process.exit(1);
    }

    // Rename locals first, on the clean original source.
    let renamed;
    try {
        renamed = renameLocalsInSource(sourceCode);
        luaparse.parse(renamed, { luaVersion: '5.1' }); // sanity-check our own output
    } catch (err) {
        console.error('Local-variable renaming produced invalid Lua — aborting, nothing was written:', err.message);
        process.exit(1);
    }

    const noComments = stripComments(renamed);

    const varTable = generateHexName(6);
    const varKey = generateHexName(6);
    const varDecrypt = generateHexName(6);
    const constants = [];

    // Random per-build XOR key (4-8 bytes). Every build gets a different key
    // and a different layout, so a decrypted string table from one release
    // tells you nothing about the next one.
    const keyLen = 4 + Math.floor(Math.random() * 5);
    const key = Array.from({ length: keyLen }, () => 1 + Math.floor(Math.random() * 255));

    // String Encryption: every string literal becomes an XOR-encoded byte
    // array plus a call to decrypt it at runtime, so nothing readable sits in
    // the file as plaintext (unlike a plain byte array, which is just the
    // ASCII codes sitting in the open — legible on sight, not actually hidden).
    //
    // Bytes come from the string's UTF-8 encoding (Buffer.from(raw, 'utf8')),
    // not raw.charCodeAt(i) — charCodeAt returns a UTF-16 code UNIT, which for
    // any non-ASCII character (emoji tab icons, curly quotes, accented
    // letters, ...) is a number way above 255. string.char() in Lua only
    // accepts 0-255, so those codes decrypted into "invalid argument #1 to
    // 'char' (invalid value)" at runtime instead of the original character.
    // UTF-8 bytes are always 0-255 by construction, so this round-trips
    // any Unicode string correctly.
    let obfuscatedCode = noComments.replace(/([\"'])(?:\\.|(?!\1).)*\1/g, (match) => {
        const quote = match[0];
        let raw;
        try {
            const jsonSafe = quote === "'"
                ? '"' + match.slice(1, -1).replace(/\\'/g, "'").replace(/(?<!\\)"/g, '\\"') + '"'
                : match;
            raw = JSON.parse(jsonSafe);
        } catch {
            raw = match.slice(1, -1); // fallback for unusual escapes
        }
        if (raw.length === 0) return quote + quote;

        const bytes = xorBytes(Array.from(Buffer.from(raw, 'utf8')), key);
        const index = constants.push(`{${bytes.join(',')}}`) - 1;
        return `${varDecrypt}(${varTable}[${index + 1}])`;
    });

    const header = `
local ${varKey} = {${key.join(',')}}
local ${varTable} = {
    ${constants.join(',\n    ')}
}

local function ${varDecrypt}(bytes)
    local chars = {}
    for i = 1, #bytes do
        chars[i] = string.char(bit32.bxor(bytes[i], ${varKey}[((i - 1) % #${varKey}) + 1]))
    end
    return table.concat(chars)
end
`;

    const combined = `${header}\n${obfuscatedCode}`;
    const minified = combined.replace(/\s+/g, ' ').trim();

    const wrapperVar = generateHexName(8);
    const result = `local ${wrapperVar} = function()\n${minified}\nend; ${wrapperVar}()`;

    // Verify the output is still valid Luau before it's ever written to disk
    // or served to a client — catches obfuscator bugs instead of shipping a
    // broken script.
    try {
        luaparse.parse(result, { luaVersion: '5.1' });
    } catch (err) {
        console.error('Obfuscation produced invalid Lua — aborting, nothing was written:', err.message);
        process.exit(1);
    }

    return result;
}

// Read from src/ and write to dist/
const inputPath = path.join(__dirname, 'src', 'script.lua');
const outputPath = path.join(__dirname, 'dist', 'script.lua');

if (!fs.existsSync(inputPath)) {
    console.error('Source file not found at src/script.lua');
    process.exit(1);
}

const rawCode = fs.readFileSync(inputPath, 'utf8');
const protectedCode = obfuscateLuau(rawCode);

if (!fs.existsSync(path.dirname(outputPath))) {
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
}

fs.writeFileSync(outputPath, protectedCode);
console.log('Successfully obfuscated script! Saved to dist/script.lua');