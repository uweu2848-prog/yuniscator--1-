const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

// ────────────────────────────────────────────────────────────────────────────
// Honest limits of this file, read before you trust it:
//
// This is a STRING/whitespace obfuscator, not a real virtualizer or control-flow
// flattener. It will stop someone from Ctrl+F-ing your code for plaintext
// strings or reading clean variable names, but anyone who runs the output
// through a Luau deobfuscator/beautifier, or just hooks the decrypt function
// and dumps what it returns at runtime, gets your logic back. There is no such
// thing as an unbreakable client-side script in Roblox — the client has to be
// able to execute it, which means the client has everything it needs to
// eventually read it. What this buys you is time and effort, not certainty.
// The real protection is keeping your most valuable logic server-side (see
// CHANGES.md) so the obfuscated client code is never the whole picture.
// ────────────────────────────────────────────────────────────────────────────

function generateHexName(length = 8) {
    let result = '_0x';
    const chars = '0123456789abcdef';
    for (let i = 0; i < length; i++) {
        result += chars[Math.floor(Math.random() * chars.length)];
    }
    return result;
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

    const noComments = stripComments(sourceCode);

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
    let obfuscatedCode = noComments.replace(/(["'])(?:\\.|(?!\1).)*\1/g, (match) => {
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

        const bytes = xorBytes(Array.from(raw).map(c => c.charCodeAt(0)), key);
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
