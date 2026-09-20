local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Replace this with your live backend server URL once deployed (or http://localhost:3000 for local testing)
local SERVER_URL = "https://sliver-surfer-test.up.railway.app:8080"

-- Cross-executor HTTP request handler
local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local capturedRequest, capturedLoadstring = requestFunc, loadstring
local SESSION_ID = HttpService:GenerateGUID(false)

local function getHWID()
    local success, result = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    return success and result or "UNKNOWN_HWID"
end

local HEADERS = {
    ["X-User-ID"] = tostring(LocalPlayer.UserId),
    ["X-HWID"]    = getHWID(),
    ["X-Session"] = SESSION_ID,
}

local function reportTamper(reason)
    if not requestFunc then return end
    pcall(function()
        requestFunc({
            Url = SERVER_URL .. "/api/tamper",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                userId = tostring(LocalPlayer.UserId),
                username = LocalPlayer.Name,
                hwid = getHWID(),
                reason = reason,
                session = SESSION_ID,
            })
        })
    end)
end

-- ───────────────────────────────────────────────────────────────────────────
--  Anti-tamper detection
--  Each check has an opaque code + a weight. Only the codes are sent to the
--  server, so nothing readable shows up in a spy log.
--
--    C1  core Lua functions (pcall, error, tostring...) replaced by Lua closures
--    H1  the executor's request function is a Lua wrapper instead of native
--    H2  request / loadstring reference changed since the script started
--    H3  game.HttpGet replaced by a Lua wrapper
--    M1  game's __namecall / __index metamethods hooked with Lua closures
--    G1  a GUI named like an HTTP spy is sitting in CoreGui / gethui()
--
--  Score = sum of weights. Start with BLOCK_SCORE = math.huge (report only),
--  watch your logs for false positives on the executors you support, then
--  lower it.
-- ───────────────────────────────────────────────────────────────────────────
local REPORT_SCORE    = 1          -- report to /api/tamper at or above this
local BLOCK_SCORE     = math.huge  -- refuse to run locally at or above this (try 3 once tuned)
local HEARTBEAT_EVERY = 60         -- seconds between re-checks / revocation checks

local SPY_NAMES = { "httpspy", "http spy", "simplespy", "hookspy", "networkspy" }  -- extend as you find more

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
        local n = c.Name:lower()
        for _, bad in ipairs(SPY_NAMES) do
            if n:find(bad, 1, true) then return true end
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

    local core = { pcall, error, tostring, type, select, rawget, setmetatable, print, warn }
    for _, fn in ipairs(core) do
        if not isNative(fn) then hit("C1", 2) break end
    end

    if requestFunc and not isNative(requestFunc) then hit("H1", 1) end

    local nowRequest = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if nowRequest ~= capturedRequest or loadstring ~= capturedLoadstring then hit("H2", 3) end

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

    return hits, score
end

local reported = {}
local function reportHits(hits, score)
    local key = table.concat(hits, ",")
    if key == "" or reported[key] then return end
    reported[key] = true
    reportTamper(("codes=%s score=%d session=%s"):format(key, score, SESSION_ID))
end

-- ───────────────────────────────────────────────────────────────────────────
--  Run checks, then fetch & execute the payload
-- ───────────────────────────────────────────────────────────────────────────
if not requestFunc then
    warn("[Loader] your executor doesn't support HTTP requests.")
    return
end

local hits, score = runChecks()
if score >= REPORT_SCORE then reportHits(hits, score) end
HEADERS["X-Flags"] = table.concat(hits, ",")

if score >= BLOCK_SCORE then
    warn("[Loader] connection refused by server.")
    return
end

local ok, response = pcall(function()
    return requestFunc({
        Url = SERVER_URL .. "/api/script",
        Method = "GET",
        Headers = HEADERS,
    })
end)

if not (ok and response and response.Body) then
    warn("[Loader] connection refused by server.")
    return
end

local func, err = capturedLoadstring(response.Body)
if not func then
    warn("Failed to load execution stream.")
    return
end

local ranOk, runErr = pcall(func)
if not ranOk then
    warn("[Loader] payload error: " .. tostring(runErr))
end

-- ───────────────────────────────────────────────────────────────────────────
--  Heartbeat: re-run the checks and let the server revoke access mid-session.
--  The server should return 401/403 for blacklisted users.
-- ───────────────────────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(HEARTBEAT_EVERY)

        local hb, hbScore = runChecks()
        if hbScore >= REPORT_SCORE then reportHits(hb, hbScore) end

        local hbOk, hbRes = pcall(function()
            return requestFunc({
                Url = SERVER_URL .. "/api/heartbeat",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["X-User-ID"]    = HEADERS["X-User-ID"],
                    ["X-HWID"]       = HEADERS["X-HWID"],
                    ["X-Session"]    = SESSION_ID,
                },
                Body = HttpService:JSONEncode({ flags = hb, score = hbScore }),
            })
        end)

        local revoked = (hbOk and hbRes and (hbRes.StatusCode == 401 or hbRes.StatusCode == 403))
            or hbScore >= BLOCK_SCORE
        if revoked then
            warn("[Loader] session revoked.")
            break
        end
    end
end)
