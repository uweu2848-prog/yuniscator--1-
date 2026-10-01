-- ───────────────────────────────────────────────────────────────────────────
--  Scorp loader
--
--  Users run ONE line (your server hands out this file, already obfuscated,
--  with its own address filled in):
--
--      loadstring(game:HttpGet("https://YOUR-SERVER/loader.lua"))()
--
--  Owner: run this first so you are never banned by your own anti-tamper
--  (the key is the OWNER_KEY variable on the server; never put it in a script
--  you share):
--
--      getgenv().SCORP_OWNER_KEY = "your-owner-key"
--
--  What it does
--    1. runs the anti-tamper checks
--    2. POSTs /api/session  → gets a session token, the built payload and the UI library
--    3. runs the payload, handing it a context table (token, request fn, …)
--    4. every ~30 s: re-runs the checks and POSTs /api/heartbeat.
--       The server sees a heartbeat = "this session is really running".
--       A session that fetched the payload but never heartbeats is reported to
--       Discord as a possible dump. 403 = revoked → the UI is torn down.
--
--  Anti-tamper codes (only these codes are sent, never readable text):
--    C1  core Lua functions (pcall, error, tostring…) replaced by Lua closures
--    H1  the executor's request function is a Lua wrapper instead of native
--    H2  request / loadstring reference changed since the loader started
--    H3  game.HttpGet replaced by a Lua wrapper
--    M1  game's __namecall / __index metamethods hooked with Lua closures
--    G1  a GUI named like an HTTP spy is sitting in CoreGui / gethui()
--    G2  a well-known spy global exists in _G / shared / getgenv()
--    G3  a spy-like GUI is nested deeper under CoreGui / gethui()
--
--  These checks are best-effort. A careful attacker can defeat any client-side
--  check; the server-side signals (never-confirmed sessions, IP correlation,
--  rate limits) are what catch the rest.
-- ───────────────────────────────────────────────────────────────────────────

local SERVER_URL = "__SERVER_URL__"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if SERVER_URL:sub(1, 4) ~= "http" then
    warn("[Loader] this file must be downloaded from your server (/loader.lua), not from GitHub.")
    return
end

local function pickRequest()
    return (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
end

local requestFunc = pickRequest()
local capturedRequest, capturedLoadstring = requestFunc, loadstring

if not requestFunc or not capturedLoadstring then
    warn("[Loader] your executor doesn't support HTTP requests / loadstring.")
    return
end

local function getHWID()
    local ok, result = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    return ok and result or "UNKNOWN_HWID"
end

local OWNER_KEY = nil
pcall(function() OWNER_KEY = getgenv().SCORP_OWNER_KEY end)

-- ───────────────────────────────────────────────────────────────────────────
--  Anti-tamper checks
-- ───────────────────────────────────────────────────────────────────────────
local BLOCK_SCORE = math.huge  -- local refusal. Leave at math.huge (server-side bans only) until your logs show no false positives.

local SPY_NAMES = { "httpspy", "http spy", "simplespy", "hookspy", "networkspy" }
local SPY_GLOBALS = { "HttpSpy", "httpspy", "SimpleSpy", "SimpleSpyExecuted", "hookedRequest" }

-- True if fn is a native / C closure. Returns true when it can't tell (avoids false positives).
local function isNative(fn)
    if type(fn) ~= "function" then return false end
    local ok, src = pcall(debug.info, fn, "s")
    if ok and type(src) == "string" then return src == "[C]" end
    if islclosure then
        local ok2, isL = pcall(islclosure, fn)
        if ok2 then return not isL end
    end
    return true
end

local function guiHasSpy(container)
    local ok, kids = pcall(function() return container:GetChildren() end)
    if not ok then return false end
    for _, c in ipairs(kids) do
        local n = string.lower(c.Name)
        for _, bad in ipairs(SPY_NAMES) do
            if string.find(n, bad, 1, true) then return true end
        end
    end
    return false
end

local function guiHasNestedSpy(container)
    local ok, descendants = pcall(function() return container:GetDescendants() end)
    if not ok or type(descendants) ~= "table" then return false end
    local direct = {}
    local childrenOk, children = pcall(function() return container:GetChildren() end)
    if childrenOk and type(children) == "table" then
        for _, child in ipairs(children) do direct[child] = true end
    end
    for _, item in ipairs(descendants) do
        local named, name = pcall(function() return item.Name end)
        if not direct[item] and named and type(name) == "string" then
            local n = string.lower(name)
            for _, bad in ipairs(SPY_NAMES) do
                if string.find(n, bad, 1, true) then return true end
            end
        end
    end
    return false
end

local function hasSpyGlobal()
    local envs = { _G, shared }
    if getgenv then
        local ok, g = pcall(getgenv)
        if ok and type(g) == "table" then envs[#envs + 1] = g end
    end
    for _, e in ipairs(envs) do
        for _, name in ipairs(SPY_GLOBALS) do
            local ok, v = pcall(rawget, e, name)
            if ok and v ~= nil then return true end
        end
    end
    return false
end

local function runChecks()
    local hits, score = {}, 0
    local function hit(code, weight)
        hits[#hits + 1] = code
        score = score + weight
    end

    local core = { pcall, error, tostring, type, select, rawget, setmetatable }
    for _, fn in ipairs(core) do
        if not isNative(fn) then hit("C1", 2) break end
    end

    if not isNative(requestFunc) then hit("H1", 1) end

    if pickRequest() ~= capturedRequest or loadstring ~= capturedLoadstring then hit("H2", 3) end

    local okHG, httpGet = pcall(function() return game.HttpGet end)
    if okHG and httpGet and not isNative(httpGet) then hit("H3", 1) end

    if getrawmetatable then
        local okMT, mt = pcall(getrawmetatable, game)
        if okMT and type(mt) == "table" then
            for _, m in ipairs({ "__namecall", "__index" }) do
                local f = rawget(mt, m)
                if f and not isNative(f) then hit("M1", 1) break end
            end
        end
    end

    local okCG, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if (okCG and guiHasSpy(coreGui)) or (gethui and guiHasSpy(gethui())) then hit("G1", 2) end

    if (okCG and guiHasNestedSpy(coreGui)) or (gethui and guiHasNestedSpy(gethui())) then hit("G3", 2) end

    if hasSpyGlobal() then hit("G2", 2) end

    return hits, score
end

-- ───────────────────────────────────────────────────────────────────────────
--  Server calls
-- ───────────────────────────────────────────────────────────────────────────
local function call(path, body, token)
    local headers = { ["Content-Type"] = "application/json" }
    if token then headers["Authorization"] = "Bearer " .. token end
    local ok, res = pcall(requestFunc, {
        Url = SERVER_URL .. path,
        Method = "POST",
        Headers = headers,
        Body = HttpService:JSONEncode(body),
    })
    if not ok or type(res) ~= "table" then return nil end
    return res
end

local function decode(res)
    if not res or not res.Body then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if ok and type(data) == "table" then return data end
    return nil
end

-- Executor detection: UNC standard first, then named globals, then fingerprinting.
-- ── Executor + platform detection ───────────────────────────────────────────
-- Returns: executorString, platformString
-- executorString  e.g. "Synapse X 3.1", "Potassium", "Unknown (advanced)"
-- platformString  "PC" | "Mobile" | "iOS" | "Android" | "Console" | "Unknown"
local function detectEnvironment()
    -- ── Platform ────────────────────────────────────────────────────────────
    local platform = "Unknown"
    pcall(function()
        local UIS = game:GetService("UserInputService")
        local GS  = game:GetService("GuiService")
        if GS:IsTenFootInterface() then
            platform = "Console"
        elseif UIS.TouchEnabled and not UIS.MouseEnabled then
            local inset = GS:GetGuiInset()
            platform = (inset.Y > 0) and "iOS" or "Android"
        elseif UIS.TouchEnabled and UIS.MouseEnabled then
            platform = "Mobile"
        else
            platform = "PC"
        end
    end)

    -- ── Executor ────────────────────────────────────────────────────────────
    local function trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end

    -- 1. UNC standard (identifyexecutor) — covers most modern executors:
    --    Synapse X v3+, Synapse Z, Solara, Seliware, Celery, Comet, Evon,
    --    Wave, Nihon, Coco Z, Vega X, Argon, Electron, Script-Ware M,
    --    Trigon Evo, Mango, JJSploit 2024+, Fluxus (recent)
    if identifyexecutor then
        local ok, name, ver = pcall(identifyexecutor)
        if ok and trim(name) ~= "" then
            ver = trim(ver)
            return trim(name) .. (ver ~= "" and " " .. ver or ""), platform
        end
    end

    -- 2. getexecutorname() — non-UNC executors with a name function
    if getexecutorname then
        local ok, name = pcall(getexecutorname)
        if ok and trim(name) ~= "" then return trim(name), platform end
    end

    -- 3. Named globals — paid / semi-private / older executors
    local G = _G
    local function g(k) return rawget(G, k) end

    -- Script-Ware
    if g("ScriptWare") or g("scriptware") or g("sw") then
        local ver = ""
        pcall(function()
            if type(g("sw")) == "table" and g("sw").version then
                ver = tostring(g("sw").version)
            end
        end)
        return "Script-Ware" .. (ver ~= "" and " " .. ver or ""), platform
    end
    -- Potassium
    if g("Potassium") or g("potassium") then return "Potassium", platform end
    -- Volt
    if g("Volt") or g("volt") then
        local ver = ""
        pcall(function()
            if type(g("Volt")) == "table" and g("Volt").Version then
                ver = tostring(g("Volt").Version)
            end
        end)
        return "Volt" .. (ver ~= "" and " " .. ver or ""), platform
    end
    -- Wave (older builds without identifyexecutor)
    if g("Wave") or g("wave") then return "Wave", platform end
    -- Nihon
    if g("Nihon") or g("nihon_loaded") then return "Nihon", platform end
    -- Trigon / Trigon Evo (older)
    if g("TRIGON_LOADED") or g("trigon") then return "Trigon", platform end
    -- Oxygen U
    if g("OXYGENU") or g("OxygenU") or g("oxygen_u") then return "Oxygen U", platform end
    -- Celes
    if g("Celes") or g("CELES_LOADED") then return "Celes", platform end
    -- Calamari
    if g("Calamari") or g("CALAMARI_LOADED") then return "Calamari", platform end
    -- Ro-Exec
    if g("RoExec") or g("roexec") then return "Ro-Exec", platform end
    -- EzExploit
    if g("EzExploit") or g("EZEXPLOIT") then return "EzExploit", platform end
    -- Dansploit
    if g("Dansploit") or g("DANSPLOIT_LOADED") then return "Dansploit", platform end
    -- Temple
    if g("Temple") or g("temple_loaded") then return "Temple", platform end
    -- Mango (older)
    if g("Mango") or g("MANGO_LOADED") then return "Mango", platform end
    -- Xeno
    if g("Xeno") then return "Xeno", platform end
    -- Zorara / Solara (pre-identifyexecutor builds)
    if g("zorara") then return "Zorara", platform end
    -- Delta
    if g("Delta") then return "Delta", platform end
    -- Arceus X Neo / Arceus X
    if g("ArceusX") then return "Arceus X Neo", platform end
    if g("ARCEUS_X") then return "Arceus X", platform end
    -- Hydrogen (iOS)
    if g("Hydrogen") then return "Hydrogen", platform end
    -- Fluxus (older builds)
    if g("fluxus") then return "Fluxus", platform end
    -- Coco Z (older)
    if g("CocoZ") then return "Coco Z", platform end
    -- Vega X
    if g("VEGA_X") then return "Vega X", platform end
    -- Comet (older)
    if g("Comet") then return "Comet", platform end
    -- Electron (older)
    if g("Electron") then return "Electron", platform end
    -- Evon (older)
    if g("evon") then return "Evon", platform end
    -- Proxo / PEBC
    if g("pebc_execute") then return "Proxo", platform end
    -- JJSploit (legacy global)
    if g("JJSPLOIT_V4") then return "JJSploit", platform end
    -- KRNL (legacy)
    if g("KRNL_LOADED") then return "KRNL", platform end
    -- Synapse X v2 (classic, no identifyexecutor)
    if syn and syn.request then
        local ver = ""
        pcall(function() if syn.get_version then ver = tostring(syn.get_version()) end end)
        return "Synapse X" .. (ver ~= "" and " " .. ver or ""), platform
    end

    -- 4. Capability fingerprinting — executor present but deliberately unnamed
    local hasHook    = type(hookfunction) == "function"
    local hasChecker = type(checkcaller)  == "function"
    local hasGc      = type(getgc)        == "function"
    local hasClone   = type(cloneref)     == "function"
    local hasClosure = type(newcclosure)  == "function"
    local hasDecomp  = type(decompile)    == "function"

    if hasHook and hasChecker and hasGc and hasClone then
        return "Unknown (advanced)", platform
    end
    if hasDecomp and hasHook then
        return "Unknown (decompiler)", platform
    end
    if hasHook or hasClosure then
        return "Unknown (partial UNC)", platform
    end
    if type(loadstring) == "function" then
        return "Unknown (basic)", platform
    end
    return "Unknown", platform
end

local EXECUTOR, PLATFORM = detectEnvironment()

local function identity(extra)
    local t = {
        userId   = tostring(LocalPlayer.UserId),
        username = LocalPlayer.Name,
        hwid     = getHWID(),
        executor = EXECUTOR,
        platform = PLATFORM,
        placeId  = game.PlaceId,
        jobId    = game.JobId,
        ownerKey = OWNER_KEY,
    }
    for k, v in pairs(extra) do t[k] = v end
    return t
end

-- ───────────────────────────────────────────────────────────────────────────
--  Start
-- ───────────────────────────────────────────────────────────────────────────
local hits, score = runChecks()
if score >= BLOCK_SCORE then
    warn("[Loader] environment check failed.")
    return
end

local res = call("/api/session", identity({ flags = hits }))
if not res then
    warn("[Loader] couldn't reach the server.")
    return
end
if res.StatusCode == 429 then
    warn("[Loader] slow down — wait a few seconds and run it again.")
    return
end
local data = decode(res)
if res.StatusCode ~= 200 or not data or not data.ok or type(data.payload) ~= "string" then
    warn("[Loader] connection refused by server (" .. tostring(res.StatusCode) .. ").")
    return
end

local payloadFn, compileErr = capturedLoadstring(data.payload)
if not payloadFn then
    warn("[Loader] failed to load payload: " .. tostring(compileErr))
    return
end

local ctx = {
    token = data.token,
    server = SERVER_URL,
    request = requestFunc,
    loadstring = capturedLoadstring,
    lib = data.lib,
    build = data.build,
    watermark = data.watermark,
    releaseChannel = data.releaseChannel,
    releaseVersion = data.releaseVersion,
    releaseNotes = data.releaseNotes,
}

local ranOk, runErr = pcall(payloadFn, ctx)
if not ranOk then
    warn("[Loader] payload error: " .. tostring(runErr))
end

-- ───────────────────────────────────────────────────────────────────────────
--  Heartbeat: re-check, report, and let the server revoke access mid-session
-- ───────────────────────────────────────────────────────────────────────────
if not ctx.token then return end -- stalled (banned) session: nothing to check in

local function revoke(message, updateRequired)
    message = message or "Your Scorp session was revoked."
    warn("[Loader] " .. tostring(message))
    if ctx.revoke then pcall(ctx.revoke, message, updateRequired == true) end
end

task.spawn(function()
    local interval = tonumber(data.hb) or 30
    task.wait(2) -- first check-in quickly, so the server knows this session is alive
    while true do
        local hb, hbScore = runChecks()
        local r = call("/api/heartbeat", { flags = hb, build = ctx.build, watermark = ctx.watermark }, ctx.token)
        local status = r and r.StatusCode

        if status == 403 or hbScore >= BLOCK_SCORE then
            local reply = decode(r)
            if reply and reply.updateRequired then
                revoke(reply.updateMessage or "Scorp was updated. Relaunch the latest loader to continue.", true)
            else
                revoke()
            end
            break
        elseif status == 401 then
            -- token expired, or the server restarted with a new secret: quietly get a new one
            local rr = call("/api/session", identity({ flags = hb, resume = true }))
            local d2 = decode(rr)
            if rr and rr.StatusCode == 200 and d2 and d2.ok then
                if d2.token then
                    ctx.token = d2.token
                    ctx.build = d2.build or ctx.build
                    ctx.watermark = d2.watermark or ctx.watermark
                    ctx.releaseChannel = d2.releaseChannel or ctx.releaseChannel
                    ctx.releaseVersion = d2.releaseVersion or ctx.releaseVersion
                else
                    revoke()
                    break
                end
            end
        end

        task.wait(interval)
    end
end)
