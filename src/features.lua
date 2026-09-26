-- ───────────────────────────────────────────────────────────────────────────
--  Misc features (movement, visuals, players, world, staff panel).
--  Pulled into src/script.lua by the build (--@include). Lua 5.1 only.
--  Nametags are not touched here.
-- ───────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

local Features = {}
local conns = {}
local alive = true
local started = false

local function connect(sig, fn)
    local c = sig:Connect(fn)
    conns[#conns + 1] = c
    return c
end

local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function findPlayer(txt)
    txt = string.lower(tostring(txt or ""))
    if txt == "" then return nil end
    local list = Players:GetPlayers()
    for i = 1, #list do
        local p = list[i]
        if p ~= LocalPlayer then
            local name = string.lower(p.Name)
            local display = string.lower(p.DisplayName)
            if string.sub(name, 1, #txt) == txt or string.sub(display, 1, #txt) == txt then
                return p
            end
        end
    end
    return nil
end

-- ── movement ──────────────────────────────────────────────────────────────
local cframeOn = false
local cframeSpeed = 16
local noclipOn = false
local noclipParts = {}
local infJumpOn = false
local walkSpeed = 16
local jumpPower = 50
local spinOn = false
local spinSpeed = 10

function Features.SetCFrame(on) cframeOn = on and true or false end
function Features.CFrameOn() return cframeOn end
function Features.SetCFrameSpeed(n)
    n = tonumber(n) or cframeSpeed
    if n < 0 then n = 0 end
    if n > 1000000 then n = 1000000 end
    cframeSpeed = n
end

local function noclipRestore()
    for part, orig in pairs(noclipParts) do
        if part and part.Parent then part.CanCollide = orig end
    end
    noclipParts = {}
end

function Features.SetNoclip(on)
    noclipOn = on and true or false
    if not noclipOn then noclipRestore() end
end

function Features.SetInfJump(on) infJumpOn = on and true or false end

local function applyWalk()
    local hum = getHum()
    if hum then hum.WalkSpeed = walkSpeed end
end

local function applyJump()
    local hum = getHum()
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = jumpPower
    end
end

function Features.SetWalkSpeed(n)
    n = tonumber(n) or walkSpeed
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    walkSpeed = n
    applyWalk()
end

function Features.SetJumpPower(n)
    n = tonumber(n) or jumpPower
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    jumpPower = n
    applyJump()
end

function Features.SetSpin(on) spinOn = on and true or false end
function Features.SetSpinSpeed(n)
    n = tonumber(n) or spinSpeed
    if n < -50 then n = -50 end
    if n > 50 then n = 50 end
    spinSpeed = n
end

-- ── fly ───────────────────────────────────────────────────────────────────
local flyOn = false
local flySpeed = 50
local flyBV, flyBG
local flyMove = { f = 0, b = 0, l = 0, r = 0 }

local function stopFly()
    local hum = getHum()
    if hum then hum.PlatformStand = false end
    local root = getHRP()
    if root then
        local g = root:FindFirstChild("ScorpFlyGyro")
        local v = root:FindFirstChild("ScorpFlyVel")
        if g then g:Destroy() end
        if v then v:Destroy() end
    end
    flyBV, flyBG = nil, nil
    flyMove = { f = 0, b = 0, l = 0, r = 0 }
end

local function startFly()
    local root, hum = getHRP(), getHum()
    if not root or not hum then return end
    hum.PlatformStand = true
    flyBG = Instance.new("BodyGyro")
    flyBG.Name = "ScorpFlyGyro"
    flyBG.P = 90000
    flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root
    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "ScorpFlyVel"
    flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Velocity = Vector3.new(0, 0, 0)
    flyBV.Parent = root
end

function Features.SetFly(on)
    flyOn = on and true or false
    if flyOn then startFly() else stopFly() end
end
function Features.FlyOn() return flyOn end
function Features.SetFlySpeed(n)
    n = tonumber(n) or flySpeed
    if n < 0 then n = 0 end
    if n > 1000000 then n = 1000000 end
    flySpeed = n
end

-- ── gravity / world ───────────────────────────────────────────────────────
local normalGravity = workspace.Gravity
if normalGravity == 0 then normalGravity = 196.2 end
local customGravity = normalGravity
local gravOn = false
local applyingGravity = false

function Features.SetGravity(on)
    gravOn = on and true or false
    applyingGravity = true
    workspace.Gravity = gravOn and customGravity or normalGravity
    applyingGravity = false
end
function Features.GravityOn() return gravOn end
function Features.SetCustomGravity(n)
    n = tonumber(n) or customGravity
    if n < 0 then n = 0 end
    if n > 500 then n = 500 end
    customGravity = n
    if gravOn then
        applyingGravity = true
        workspace.Gravity = customGravity
        applyingGravity = false
    end
end

local worldOrig = nil
local fullbrightOn = false
local nofogOn = false
local xrayOn = false
local xrayParts = {}
local fov = 70
local origFov = (workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView) or 70
local lockFovOn = false

local function captureLighting()
    if worldOrig then return end
    worldOrig = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
    }
end

local function applyLighting()
    captureLighting()
    if fullbrightOn then
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
    else
        Lighting.Ambient = worldOrig.Ambient
        Lighting.OutdoorAmbient = worldOrig.OutdoorAmbient
        Lighting.Brightness = worldOrig.Brightness
        Lighting.ClockTime = worldOrig.ClockTime
        Lighting.GlobalShadows = worldOrig.GlobalShadows
    end
    if nofogOn then
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
    else
        Lighting.FogEnd = worldOrig.FogEnd
        Lighting.FogStart = worldOrig.FogStart
    end
end

function Features.SetFullbright(on)
    fullbrightOn = on and true or false
    applyLighting()
end
function Features.SetNoFog(on)
    nofogOn = on and true or false
    applyLighting()
end

function Features.SetXray(on)
    xrayOn = on and true or false
    if xrayOn then
        local desc = workspace:GetDescendants()
        for i = 1, #desc do
            local p = desc[i]
            if p:IsA("BasePart") and p.Parent and not p.Parent:FindFirstChildOfClass("Humanoid") then
                if xrayParts[p] == nil then xrayParts[p] = p.LocalTransparencyModifier end
                p.LocalTransparencyModifier = 0.65
            end
        end
    else
        for p, orig in pairs(xrayParts) do
            if p and p.Parent then p.LocalTransparencyModifier = orig end
        end
        xrayParts = {}
    end
end

function Features.SetFov(n)
    n = tonumber(n) or fov
    if n < 1 then n = 1 end
    if n > 120 then n = 120 end
    fov = n
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = fov end
end
function Features.SetLockFov(on) lockFovOn = on and true or false end

local infFolder = nil
function Features.ToggleInfBaseplate()
    if infFolder and infFolder.Parent then
        infFolder:Destroy()
        infFolder = nil
        return "infbaseplate removed"
    end
    local TILE, THICK, N = 2048, 16, 8
    local bp = workspace:FindFirstChild("Baseplate") or workspace:FindFirstChild("Base") or workspace:FindFirstChild("Ground")
    if bp and not bp:IsA("BasePart") then bp = nil end
    local floorY, mat, col = 0, Enum.Material.Plastic, Color3.fromRGB(110, 110, 110)
    if bp then
        floorY = bp.Position.Y + bp.Size.Y / 2 - THICK / 2
        mat = bp.Material
        col = bp.Color
    end
    infFolder = Instance.new("Folder")
    infFolder.Name = "ScorpInfBaseplate"
    infFolder.Parent = workspace
    local parts, cframes, index = {}, {}, 1
    for x = -N, N do
        for z = -N, N do
            local p = Instance.new("Part")
            p.Anchored = true
            p.CanCollide = true
            p.Size = Vector3.new(TILE, THICK, TILE)
            p.Material = mat
            p.Color = col
            p.TopSurface = Enum.SurfaceType.Smooth
            p.BottomSurface = Enum.SurfaceType.Smooth
            parts[index] = p
            cframes[index] = CFrame.new(x * TILE, floorY, z * TILE)
            index = index + 1
        end
    end
    for i = 1, #parts do parts[i].Parent = infFolder end
    workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
    return "infbaseplate placed"
end

-- ── anti-fling / air / void / invis / freecam ─────────────────────────────
local antiflingOn = false
local airOn = false
local airOffset = 3
local airPart = nil
local platOn = false
local platBV = nil
local hipValue = nil
local voidOn = false
local lastSafe = nil
local invisOn = false

function Features.SetAntifling(on) antiflingOn = on and true or false end

local function airClear()
    if airPart then airPart:Destroy() airPart = nil end
end
function Features.SetAirwalk(on)
    airOn = on and true or false
    if not airOn then airClear() end
end
function Features.SetAirOffset(n)
    n = tonumber(n) or airOffset
    if n < -50 then n = -50 end
    if n > 50 then n = 50 end
    airOffset = n
end

local function platApply()
    if platBV then platBV:Destroy() platBV = nil end
    if not platOn then return end
    local hrp = getHRP()
    if not hrp then return end
    platBV = Instance.new("BodyVelocity")
    platBV.Name = "ScorpHover"
    platBV.MaxForce = Vector3.new(0, 400000, 0)
    platBV.Velocity = Vector3.new(0, 0, 0)
    platBV.Parent = hrp
end
function Features.SetPlatform(on)
    platOn = on and true or false
    platApply()
end

function Features.SetHip(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    if n > 100 then n = 100 end
    hipValue = n
    local hum = getHum()
    if hum then hum.HipHeight = hipValue end
end

function Features.SetAntivoid(on) voidOn = on and true or false end

local function invisApply()
    local c = getChar()
    if not c then return end
    local desc = c:GetDescendants()
    for i = 1, #desc do
        local p = desc[i]
        if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then
            p.LocalTransparencyModifier = invisOn and 1 or 0
        end
    end
end
function Features.SetInvisible(on)
    invisOn = on and true or false
    invisApply()
end

local fcOn = false
local fcPos = Vector3.new()
local fcYaw, fcPitch = 0, 0
local fcKeys = { W = false, A = false, S = false, D = false, E = false, Q = false, Shift = false }

function Features.SetFreecam(on)
    fcOn = on and true or false
    local cam = workspace.CurrentCamera
    if not cam then return end
    if fcOn then
        fcPos = cam.CFrame.Position
        local look = cam.CFrame.LookVector
        fcYaw = math.deg(math.atan2(-look.X, -look.Z))
        fcPitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
        cam.CameraType = Enum.CameraType.Scriptable
    else
        cam.CameraType = Enum.CameraType.Custom
        local hum = getHum()
        if hum then cam.CameraSubject = hum end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        for k in pairs(fcKeys) do fcKeys[k] = false end
    end
end
function Features.FreecamOn() return fcOn end

function Features.FirstPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
end
function Features.ThirdPerson()
    LocalPlayer.CameraMode = Enum.CameraMode.Classic
    LocalPlayer.CameraMaxZoomDistance = 128
end
function Features.FixCam()
    local cam = workspace.CurrentCamera
    if not cam then return end
    cam.CameraType = Enum.CameraType.Custom
    local hum = getHum()
    if hum then cam.CameraSubject = hum end
    if fcOn then
        fcOn = false
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end
end

-- ── hitbox ────────────────────────────────────────────────────────────────
local hitboxOn = false
local hitboxVisible = true
local hitboxSize = 5
local hbOriginals = {}
local HITBOX_COLOR = Color3.fromRGB(255, 40, 40)

local function hbRestore()
    for hrp, o in pairs(hbOriginals) do
        if hrp and hrp.Parent then
            hrp.Size = o.Size
            hrp.Transparency = o.Transparency
            hrp.Color = o.Color
            hrp.CanCollide = o.CanCollide
            hrp.Massless = o.Massless
        end
    end
    hbOriginals = {}
end

function Features.SetHitbox(on)
    hitboxOn = on and true or false
    if not hitboxOn then hbRestore() end
end
function Features.SetHitboxVisible(on) hitboxVisible = on and true or false end
function Features.SetHitboxSize(n)
    n = tonumber(n) or hitboxSize
    if n < 1 then n = 1 end
    if n > 10 then n = 10 end
    hitboxSize = n
end

-- ── ESP ───────────────────────────────────────────────────────────────────
local espOn = false
local espBox, espName, espHealth, espDistance, espSkeleton, espTracer, espChams = true, true, false, false, false, false, false
local espMax = 0
local espColor = Color3.fromRGB(230, 68, 68)
local espObjects = {}
local drawingOk = (Drawing ~= nil)

local SKELETON_R6 = {
    { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
    { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}
local SKELETON_R15 = {
    { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
    { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
    { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function espHide(o)
    o.box.Visible = false
    o.name.Visible = false
    o.hpBg.Visible = false
    o.hpFill.Visible = false
    o.tracer.Visible = false
    for i = 1, #o.bones do o.bones[i].Visible = false end
    if o.highlight then o.highlight.Enabled = false end
end

local function espRemove(plr)
    local o = espObjects[plr]
    if not o then return end
    pcall(function() o.box:Remove() end)
    pcall(function() o.name:Remove() end)
    pcall(function() o.hpBg:Remove() end)
    pcall(function() o.hpFill:Remove() end)
    pcall(function() o.tracer:Remove() end)
    for i = 1, #o.bones do pcall(function() o.bones[i]:Remove() end) end
    if o.highlight then o.highlight:Destroy() end
    espObjects[plr] = nil
end

local function espAdd(plr)
    if not drawingOk or plr == LocalPlayer or espObjects[plr] then return end
    local bones = {}
    for i = 1, 16 do
        bones[i] = newDrawing("Line", { Thickness = 1, Color = Color3.new(1, 1, 1), Visible = false })
    end
    espObjects[plr] = {
        box = newDrawing("Square", { Thickness = 1.5, Color = espColor, Filled = false, Visible = false }),
        name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.new(1, 1, 1), Visible = false }),
        hpBg = newDrawing("Square", { Thickness = 1, Color = Color3.new(0, 0, 0), Filled = true, Visible = false }),
        hpFill = newDrawing("Square", { Thickness = 1, Color = Color3.fromRGB(70, 210, 110), Filled = true, Visible = false }),
        tracer = newDrawing("Line", { Thickness = 1, Color = espColor, Visible = false }),
        bones = bones,
        highlight = nil,
    }
end

function Features.HasDrawing() return drawingOk end
function Features.SetEsp(on)
    espOn = on and drawingOk or false
    if not espOn then
        for _, o in pairs(espObjects) do espHide(o) end
    end
    return espOn
end
function Features.EspOn() return espOn end
function Features.SetEspFlag(name, on)
    on = on and true or false
    if name == "box" then espBox = on
    elseif name == "name" then espName = on
    elseif name == "health" then espHealth = on
    elseif name == "distance" then espDistance = on
    elseif name == "skeleton" then espSkeleton = on
    elseif name == "tracer" then espTracer = on
    elseif name == "chams" then espChams = on
    end
end
function Features.SetEspDistance(n)
    n = tonumber(n) or 0
    if n < 0 then n = 0 end
    espMax = n
end
function Features.SetEspColor(c)
    if typeof(c) == "Color3" then espColor = c end
end

-- ── players ───────────────────────────────────────────────────────────────
local spectating = nil
local carryMode, carryTarget = nil, nil

function Features.TeleportTo(query)
    local target = findPlayer(query)
    local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local my = getHRP()
    if not (thrp and my) then return "player not found" end
    my.CFrame = thrp.CFrame + Vector3.new(0, 0, 3)
    return "teleported to " .. target.Name
end

function Features.Spectate(query)
    local cam = workspace.CurrentCamera
    if spectating then
        local hum = getHum()
        if hum and cam then cam.CameraSubject = hum end
        spectating = nil
        return "stopped spectating"
    end
    local target = findPlayer(query)
    local thum = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if not (thum and cam) then return "player not found" end
    cam.CameraSubject = thum
    spectating = target
    return "spectating " .. target.Name
end

function Features.StopSpectate()
    local cam = workspace.CurrentCamera
    local hum = getHum()
    if hum and cam then cam.CameraSubject = hum end
    spectating = nil
end

function Features.SetCarry(mode, query)
    local target = findPlayer(query)
    if not target then
        carryMode, carryTarget = nil, nil
        return "player not found"
    end
    if carryMode == mode and carryTarget == target then
        carryMode, carryTarget = nil, nil
        return "stopped"
    end
    carryMode, carryTarget = mode, target
    return mode .. " -> " .. target.Name
end

function Features.Behind(query)
    local target = findPlayer(query)
    local thrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    local my = getHRP()
    if not (thrp and my) then return "player not found" end
    my.CFrame = thrp.CFrame * CFrame.new(0, 0, 2.5)
    return "behind " .. target.Name
end

function Features.TeleportCoords(x, y, z)
    local hrp = getHRP()
    if not hrp then return "no character" end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return "enter X, Y and Z" end
    hrp.CFrame = CFrame.new(x, y, z)
    return "teleported"
end

function Features.GetPos()
    local hrp = getHRP()
    if not hrp then return nil end
    local p = hrp.Position
    return string.format("%.1f, %.1f, %.1f", p.X, p.Y, p.Z)
end

local clickMouse = nil
function Features.ClickTP()
    local root, hum = getHRP(), getHum()
    if not (root and hum) or hum.Health <= 0 then return "no character" end
    if not clickMouse then clickMouse = LocalPlayer:GetMouse() end
    if not clickMouse or not clickMouse.Target or not clickMouse.Hit then
        return "nothing under the cursor"
    end
    root.CFrame = CFrame.new(clickMouse.Hit.Position + Vector3.new(0, 3, 0))
    return nil
end

-- ── staff panel (firebase admins; receivers are other clients running this) ─
local ADMIN_IDS, ADMIN_NAMES = {}, {}
local isAdmin = false
local FIREBASE_URL, API_KEY, API_MODE = "", "", false
local seenCmd = {}
local startedAt = os.time() - 5
local staffStatus = "staff: not loaded"
local requestFn = nil

local SELF_SAFE = {
    fw = true, spn = true, frz = true, flg = true, sit = true,
    jmp = true, brg = true, vod = true, rst = true, bld = true, kck = true,
    usp = true, thw = true, ubl = true,
}
local PROTECTED = { vod = true, rst = true, kck = true }

local spinConn = nil
local blindGui = nil

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(body) == "string" and body ~= "" then return body end
    local req = requestFn or request or (syn and syn.request) or (http and http.request)
    if req then
        local ok2, resp = pcall(req, { Url = url, Method = "GET" })
        if ok2 and resp and type(resp.Body) == "string" and resp.Body ~= "" then
            return resp.Body
        end
    end
    return nil
end

local function httpReq(method, url, body)
    local req = requestFn or request or (syn and syn.request) or (http and http.request)
    if not req then return false end
    local ok, resp = pcall(req, {
        Url = url, Method = method, Body = body,
        Headers = { ["Content-Type"] = "application/json" },
    })
    if not ok or not resp then return false end
    local code = tonumber(resp.StatusCode or resp.Status or resp.status or resp.code)
    return code == nil or (code >= 200 and code < 300)
end

local function fbUrl(path)
    if FIREBASE_URL == "" then return "" end
    local q = ""
    if API_MODE and API_KEY ~= "" then
        q = "?key=" .. HttpService:UrlEncode(API_KEY)
    end
    return FIREBASE_URL .. "/" .. path .. q
end

local function addIdentity(raw)
    local s = tostring(raw or "")
    if s == "" then return end
    local id = tonumber(s)
    if id then ADMIN_IDS[id] = true else ADMIN_NAMES[string.lower(s)] = true end
end

local function clearMap(t)
    for k in pairs(t) do t[k] = nil end
end

local function applyStaff(body)
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" then return false end
    local has = type(data.ids) == "table" or type(data.usernames) == "table" or type(data.admins) == "table"
    if not has then return false end
    clearMap(ADMIN_IDS)
    clearMap(ADMIN_NAMES)
    local lists = { data.ids, data.usernames }
    for i = 1, #lists do
        local list = lists[i]
        if type(list) == "table" then
            for key, value in pairs(list) do
                if type(value) == "string" or type(value) == "number" then
                    addIdentity(value)
                elseif value == true then
                    addIdentity(key)
                end
            end
        end
    end
    if type(data.admins) == "table" then
        for i = 1, #data.admins do addIdentity(data.admins[i]) end
    end
    return true
end

local function loadFirebaseConfig()
    local buster = "?t=" .. tostring(os.time())
    local apiSources = {
        "https://raw.githubusercontent.com/vertxxy-1/Xyro/main/api.json" .. buster,
        "https://cdn.jsdelivr.net/gh/vertxxy-1/Xyro@main/api.json",
    }
    for i = 1, #apiSources do
        local body = httpGet(apiSources[i])
        if type(body) == "string" and body ~= "" then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and type(data) == "table" then
                local api = data.api or data
                if type(api) == "table" and type(api.url) == "string" and api.url ~= "" then
                    FIREBASE_URL = string.gsub(api.url, "/+$", "")
                    API_KEY = tostring(api.key or "")
                    API_MODE = true
                    return
                end
            end
            return
        end
    end
    local fbSources = {
        "https://raw.githubusercontent.com/vertxxy-1/Xyro/main/firebase.json" .. buster,
        "https://cdn.jsdelivr.net/gh/vertxxy-1/Xyro@main/firebase.json",
    }
    for i = 1, #fbSources do
        local body = httpGet(fbSources[i])
        if type(body) == "string" and body ~= "" then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok and type(data) == "table" then
                local fb = data.firebase or data
                if type(fb) == "table" and type(fb.url) == "string" and fb.url ~= "" then
                    FIREBASE_URL = string.gsub(fb.url, "/+$", "")
                end
            elseif string.sub(body, 1, 8) == "https://" then
                FIREBASE_URL = string.gsub(body, "%s+", "")
            end
            return
        end
    end
end

local function refreshAdminFlag()
    isAdmin = ADMIN_IDS[LocalPlayer.UserId] == true or ADMIN_NAMES[string.lower(LocalPlayer.Name)] == true
    if FIREBASE_URL == "" then
        staffStatus = "staff: firebase not configured"
    elseif isAdmin then
        staffStatus = "staff: you are an administrator"
    else
        staffStatus = "staff: loaded (you are not staff)"
    end
end

function Features.RefreshStaff()
    local url = fbUrl("staff.json")
    if url == "" then
        staffStatus = "staff: firebase not configured"
        return staffStatus
    end
    local body = httpGet(url)
    if type(body) ~= "string" or body == "" or body == "null" then
        staffStatus = "staff: fetch failed"
        return staffStatus
    end
    if applyStaff(body) then
        refreshAdminFlag()
        return staffStatus
    end
    staffStatus = "staff: bad staff list"
    return staffStatus
end

function Features.StaffStatus() return staffStatus end
function Features.IsStaff() return isAdmin end

local function fxSettle(delay)
    task.delay(delay, function()
        local hum, hrp = getHum(), getHRP()
        if not hum then return end
        if hrp then hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end
        hum.PlatformStand = false
        if hum:GetState() == Enum.HumanoidStateType.Physics then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function fxSpin(on)
    if spinConn then spinConn:Disconnect() spinConn = nil end
    if on then
        spinConn = connect(RunService.Heartbeat, function(dt)
            local hrp = getHRP()
            if hrp then hrp.CFrame = hrp.CFrame * CFrame.Angles(0, dt * 16, 0) end
        end)
    end
end

local function fxFlywheel()
    local hrp, hum = getHRP(), getHum()
    if not (hrp and hum) then return end
    local old = hrp:FindFirstChild("ScorpFlyWheel")
    if old then old:Destroy() end
    local lift = Instance.new("BodyVelocity")
    lift.Name = "ScorpFlyWheel"
    lift.MaxForce = Vector3.new(0, math.huge, 0)
    lift.Velocity = Vector3.new(0, 130, 0)
    lift.Parent = hrp
    task.wait(1.15)
    if lift.Parent then lift:Destroy() end
    local c = getChar()
    if c then
        local desc = c:GetDescendants()
        for i = 1, #desc do
            local p = desc[i]
            if p:IsA("BasePart") then
                p.AssemblyLinearVelocity = Vector3.new(math.random(-80, 80), math.random(40, 110), math.random(-80, 80))
            end
        end
    end
    hum:ChangeState(Enum.HumanoidStateType.Physics)
    fxSettle(2)
end

local function fxFreeze(on)
    local hrp, hum = getHRP(), getHum()
    if hrp then hrp.Anchored = on end
    if hum then
        hum.PlatformStand = on
        if not on then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
    end
end

local function fxFling()
    local hrp, hum = getHRP(), getHum()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Physics) end
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.new(math.random(-160, 160), math.random(90, 180), math.random(-160, 160))
        hrp.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-12, 12), math.random(-8, 8))
    end
    fxSettle(1.6)
end

local function fxBlind(on)
    if blindGui then blindGui:Destroy() blindGui = nil end
    if not on then return end
    local host = (gethui and gethui()) or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not host then return end
    local g = Instance.new("ScreenGui")
    g.Name = "ScorpStaffBlind"
    g.IgnoreGuiInset = true
    g.ResetOnSpawn = false
    g.DisplayOrder = 100000
    local cover = Instance.new("Frame")
    cover.BackgroundColor3 = Color3.new(0, 0, 0)
    cover.BorderSizePixel = 0
    cover.Size = UDim2.fromScale(1, 1)
    cover.Parent = g
    g.Parent = host
    blindGui = g
end

local function staffIsAdmin(userId, userName)
    if ADMIN_IDS[userId] == true then return true end
    if type(userName) == "string" and ADMIN_NAMES[string.lower(userName)] == true then return true end
    return false
end

local function applyCmd(cmd, issuerId, issuerName)
    if not staffIsAdmin(issuerId, issuerName) then return end
    cmd = string.lower(tostring(cmd or ""))
    if issuerId == LocalPlayer.UserId and SELF_SAFE[cmd] then return end
    if PROTECTED[cmd] and isAdmin then return end
    if cmd == "fw" then task.spawn(fxFlywheel)
    elseif cmd == "spn" then task.spawn(fxSpin, true)
    elseif cmd == "usp" then task.spawn(fxSpin, false)
    elseif cmd == "frz" then task.spawn(fxFreeze, true)
    elseif cmd == "thw" then task.spawn(fxFreeze, false)
    elseif cmd == "flg" then task.spawn(fxFling)
    elseif cmd == "sit" then
        local hum = getHum()
        if hum then hum.Sit = true end
    elseif cmd == "jmp" then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    elseif cmd == "brg" then
        task.spawn(function()
            if not issuerId or issuerId == LocalPlayer.UserId then return end
            local issuer = Players:GetPlayerByUserId(issuerId)
            local target = issuer and issuer.Character and issuer.Character:FindFirstChild("HumanoidRootPart")
            local hrp = getHRP()
            if target and hrp then hrp.CFrame = target.CFrame * CFrame.new(0, 0, 3) end
        end)
    elseif cmd == "vod" then
        local hrp = getHRP()
        if hrp then hrp.CFrame = CFrame.new(hrp.Position.X, -400, hrp.Position.Z) end
    elseif cmd == "rst" then
        local hum = getHum()
        if hum then hum.Health = 0 end
    elseif cmd == "bld" then fxBlind(true)
    elseif cmd == "ubl" then fxBlind(false)
    elseif cmd == "kck" then
        pcall(function() LocalPlayer:Kick("Kicked by staff") end)
    end
end

local function targetsMe(payload)
    for idText in string.gmatch(payload or "", "%d+") do
        if tonumber(idText) == LocalPlayer.UserId then return true end
    end
    return false
end

local function handleWire(msg)
    if type(msg) ~= "string" or #msg == 0 or #msg >= 180 then return end
    local issuerId, issuerName, rest = string.match(msg, "^(%d+)|([^|]+)|(.+)$")
    if not (issuerId and rest) then return end
    local cmd, targets = string.match(rest, "^([%a]+):?(.*)$")
    if not cmd or cmd == "" then return end
    if targets == nil or targets == "" or targetsMe(targets) then
        applyCmd(cmd, tonumber(issuerId), issuerName)
    end
end

local function pollFirebase()
    local url = fbUrl("cmd.json")
    if url == "" then return end
    local body = httpGet(url)
    if type(body) ~= "string" or body == "" or body == "null" then return end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or type(data) ~= "table" or data.error ~= nil then return end
    local now = os.time()
    for key, value in pairs(data) do
        local sec = tonumber(string.match(tostring(key), "^(%d+)%-"))
        if type(value) == "string" and sec and (now - sec) <= 90 and sec >= startedAt and sec <= now + 120 and not seenCmd[key] then
            seenCmd[key] = true
            handleWire(value)
        end
    end
end

local function staffSend(cmd, targets)
    if not isAdmin then return false, "staff only" end
    local body = tostring(LocalPlayer.UserId) .. "|" .. LocalPlayer.Name .. "|" .. tostring(cmd) .. ":" .. tostring(targets or "")
    local url = fbUrl("cmd/" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 99999999)) .. ".json")
    if url == "" then return false, "firebase not configured" end
    local payload = HttpService:JSONEncode(body)
    if httpReq("PUT", url, payload) then return true, "sent" end
    return false, "send failed"
end

function Features.StaffAction(cmd, query)
    if not isAdmin then return false, staffStatus end
    local targets = ""
    if query and query ~= "" then
        local p = findPlayer(query)
        if not p then return false, "no player matched" end
        targets = tostring(p.UserId)
    end
    return staffSend(cmd, targets)
end

function Features.Start(opts)
    if started or not alive then return staffStatus end
    started = true
    opts = opts or {}
    requestFn = opts.request
    if not alive then return staffStatus end

    -- The movement / ESP loops need Roblox signals. Skip them when those signals
    -- are not there (the local test harness) instead of erroring the session.
    if type(workspace.GetPropertyChangedSignal) ~= "function" or not RunService.Heartbeat then
        return staffStatus
    end

    pcall(loadFirebaseConfig)
    pcall(function() Features.RefreshStaff() end)

    local existing = Players:GetPlayers()
    for i = 1, #existing do espAdd(existing[i]) end
    connect(Players.PlayerAdded, espAdd)
    connect(Players.PlayerRemoving, function(plr)
        espRemove(plr)
        if spectating == plr then Features.StopSpectate() end
        if carryTarget == plr then carryMode, carryTarget = nil, nil end
    end)

    connect(workspace:GetPropertyChangedSignal("Gravity"), function()
        if not applyingGravity and not gravOn then
            normalGravity = workspace.Gravity
            if normalGravity == 0 then normalGravity = 196.2 end
        end
    end)

    connect(UserInputService.JumpRequest, function()
        if not infJumpOn then return end
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)

    connect(UserInputService.InputBegan, function(input, gp)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = input.KeyCode.Name
        if flyOn and not gp then
            if name == "W" then flyMove.f = 1
            elseif name == "S" then flyMove.b = 1
            elseif name == "A" then flyMove.l = 1
            elseif name == "D" then flyMove.r = 1
            end
        end
        if fcOn and not gp then
            if fcKeys[name] ~= nil then fcKeys[name] = true end
            if input.KeyCode == Enum.KeyCode.LeftShift then fcKeys.Shift = true end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = input.KeyCode.Name
        if name == "W" then flyMove.f = 0
        elseif name == "S" then flyMove.b = 0
        elseif name == "A" then flyMove.l = 0
        elseif name == "D" then flyMove.r = 0
        end
        if fcKeys[name] ~= nil then fcKeys[name] = false end
        if input.KeyCode == Enum.KeyCode.LeftShift then fcKeys.Shift = false end
    end)

    connect(LocalPlayer.CharacterAdded, function(c)
        if flyOn then
            flyOn = false
            stopFly()
        end
        noclipParts = {}
        c:WaitForChild("Humanoid")
        applyWalk()
        applyJump()
        if hipValue then
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum then hum.HipHeight = hipValue end
        end
        if platOn then platApply() end
        if invisOn then task.delay(0.2, invisApply) end
    end)

    connect(RunService.Stepped, function()
        if not alive then return end
        if cframeOn then
            local hrp, hum = getHRP(), getHum()
            if hrp and hum then
                hrp.CFrame = hrp.CFrame + hum.MoveDirection * cframeSpeed * 0.1
            end
        end
        if noclipOn then
            local c = getChar()
            if c then
                local desc = c:GetDescendants()
                for i = 1, #desc do
                    local part = desc[i]
                    if part:IsA("BasePart") and part.CanCollide then
                        if noclipParts[part] == nil then noclipParts[part] = true end
                        part.CanCollide = false
                    end
                end
            end
        end
    end)

    connect(RunService.Heartbeat, function()
        if not alive then return end
        if hitboxOn then
            local sizeVec = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
            local tp = hitboxVisible and 0.75 or 1
            local list = Players:GetPlayers()
            for i = 1, #list do
                local plr = list[i]
                if plr ~= LocalPlayer and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        if not hbOriginals[hrp] then
                            hbOriginals[hrp] = {
                                Size = hrp.Size, Transparency = hrp.Transparency,
                                Color = hrp.Color, CanCollide = hrp.CanCollide, Massless = hrp.Massless,
                            }
                        end
                        hrp.Size = sizeVec
                        hrp.CanCollide = false
                        hrp.Transparency = tp
                        hrp.Color = HITBOX_COLOR
                        hrp.Massless = true
                    end
                end
            end
        end
        if airOn then
            local hrp = getHRP()
            if hrp then
                if not (airPart and airPart.Parent) then
                    airPart = Instance.new("Part")
                    airPart.Name = "ScorpAirwalk"
                    airPart.Anchored = true
                    airPart.CanCollide = true
                    airPart.Size = Vector3.new(7, 1, 7)
                    airPart.Transparency = 1
                    airPart.Parent = workspace
                end
                airPart.CFrame = CFrame.new(hrp.Position.X, hrp.Position.Y - airOffset - 0.5, hrp.Position.Z)
            end
        end
        if voidOn then
            local hrp, hum = getHRP(), getHum()
            if hrp and hum then
                if hum.FloorMaterial ~= Enum.Material.Air then lastSafe = hrp.CFrame end
                if hrp.Position.Y < workspace.FallenPartsDestroyHeight + 50 and lastSafe then
                    hrp.CFrame = lastSafe + Vector3.new(0, 5, 0)
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end
            end
        end
        if antiflingOn then
            local hum, hrp = getHum(), getHRP()
            if hum then
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            end
            if hrp and (hrp.AssemblyLinearVelocity.Magnitude > 100 or hrp.AssemblyAngularVelocity.Magnitude > 50) then
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
        end
    end)

    connect(RunService.RenderStepped, function(dt)
        if not alive then return end
        if spinOn then
            local root = getHRP()
            if root then root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0) end
        end
        if flyOn and flyBV and flyBG then
            local cam = workspace.CurrentCamera
            if cam then
                local fwd = flyMove.f - flyMove.b
                local side = flyMove.r - flyMove.l
                local inputVec = (cam.CFrame.LookVector * fwd) + (cam.CFrame.RightVector * side)
                local desired = Vector3.new(0, 0, 0)
                if inputVec.Magnitude > 0 then desired = inputVec.Unit * flySpeed end
                flyBV.Velocity = desired
                flyBG.CFrame = cam.CFrame
            end
        end
        if carryMode and carryTarget then
            local thrp = carryTarget.Character and carryTarget.Character:FindFirstChild("HumanoidRootPart")
            local my = getHRP()
            if not thrp or not my or carryTarget.Parent ~= Players then
                carryMode, carryTarget = nil, nil
            else
                local off = CFrame.new(0, 0, 4)
                if carryMode == "head" then off = CFrame.new(0, 3.2, 0)
                elseif carryMode == "back" then off = CFrame.new(0, 0.4, 1.6)
                end
                my.CFrame = (thrp.CFrame * off) + thrp.AssemblyLinearVelocity * 0.03
                my.AssemblyLinearVelocity = thrp.AssemblyLinearVelocity
            end
        end
        if lockFovOn and workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = fov
        end
        if invisOn then invisApply() end
        if fcOn and workspace.CurrentCamera then
            local cam = workspace.CurrentCamera
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            local d = UserInputService:GetMouseDelta()
            fcYaw = fcYaw - d.X * 0.3
            fcPitch = math.clamp(fcPitch - d.Y * 0.3, -89, 89)
            local rot = CFrame.fromEulerAnglesYXZ(math.rad(fcPitch), math.rad(fcYaw), 0)
            local speed = (fcKeys.Shift and 4 or 1) * 60 * dt
            local move = Vector3.new(0, 0, 0)
            if fcKeys.W then move = move + rot.LookVector end
            if fcKeys.S then move = move - rot.LookVector end
            if fcKeys.D then move = move + rot.RightVector end
            if fcKeys.A then move = move - rot.RightVector end
            if fcKeys.E then move = move + Vector3.new(0, 1, 0) end
            if fcKeys.Q then move = move - Vector3.new(0, 1, 0) end
            if move.Magnitude > 0 then fcPos = fcPos + move.Unit * speed end
            cam.CFrame = CFrame.new(fcPos) * rot
        end

        if espOn and drawingOk then
            local cam = workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                for plr, o in pairs(espObjects) do
                    local ch = plr.Character
                    local head = ch and ch:FindFirstChild("Head")
                    local root = ch and ch:FindFirstChild("HumanoidRootPart")
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    if root and head and hum and hum.Health > 0 then
                        local dist = (cam.CFrame.Position - root.Position).Magnitude
                        local inRange = espMax <= 0 or dist <= espMax
                        local top, onTop = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local bot = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                        if onTop and inRange then
                            local height = math.abs(bot.Y - top.Y)
                            local width = height * 0.5
                            local boxX = top.X - width / 2
                            if espBox then
                                o.box.Color = espColor
                                o.box.Size = Vector2.new(width, height)
                                o.box.Position = Vector2.new(boxX, top.Y)
                                o.box.Visible = true
                            else
                                o.box.Visible = false
                            end
                            if espName or espDistance or espHealth then
                                local label = plr.Name
                                if espDistance then label = string.format("%s [%dm]", label, math.floor(dist)) end
                                if espHealth then label = string.format("%s (%d)", label, math.floor(hum.Health)) end
                                o.name.Text = label
                                o.name.Color = Color3.new(1, 1, 1)
                                o.name.Position = Vector2.new(top.X, top.Y - 16)
                                o.name.Visible = true
                            else
                                o.name.Visible = false
                            end
                            if espHealth then
                                local pct = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                                local barW, barX = 3, boxX - 6
                                o.hpBg.Size = Vector2.new(barW, height)
                                o.hpBg.Position = Vector2.new(barX, top.Y)
                                o.hpBg.Visible = true
                                local fillH = height * pct
                                o.hpFill.Size = Vector2.new(barW, fillH)
                                o.hpFill.Position = Vector2.new(barX, top.Y + (height - fillH))
                                o.hpFill.Color = Color3.fromRGB(math.floor(255 * (1 - pct)), math.floor(210 * pct), 90)
                                o.hpFill.Visible = true
                            else
                                o.hpBg.Visible = false
                                o.hpFill.Visible = false
                            end
                            if espSkeleton then
                                local rig = hum.RigType == Enum.HumanoidRigType.R15 and SKELETON_R15 or SKELETON_R6
                                local used = 0
                                for pi = 1, #rig do
                                    local a = ch:FindFirstChild(rig[pi][1])
                                    local b = ch:FindFirstChild(rig[pi][2])
                                    if a and b then
                                        local pa, va = cam:WorldToViewportPoint(a.Position)
                                        local pb, vb = cam:WorldToViewportPoint(b.Position)
                                        if va and vb then
                                            used = used + 1
                                            local ln = o.bones[used]
                                            if ln then
                                                ln.Color = espColor
                                                ln.From = Vector2.new(pa.X, pa.Y)
                                                ln.To = Vector2.new(pb.X, pb.Y)
                                                ln.Visible = true
                                            end
                                        end
                                    end
                                end
                                for j = used + 1, #o.bones do o.bones[j].Visible = false end
                            else
                                for j = 1, #o.bones do o.bones[j].Visible = false end
                            end
                            if espTracer then
                                local feet, onScreen = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                                if onScreen then
                                    o.tracer.Color = espColor
                                    o.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                                    o.tracer.To = Vector2.new(feet.X, feet.Y)
                                    o.tracer.Visible = true
                                else
                                    o.tracer.Visible = false
                                end
                            else
                                o.tracer.Visible = false
                            end
                            if espChams then
                                if not (o.highlight and o.highlight.Parent == ch) then
                                    o.highlight = Instance.new("Highlight")
                                    o.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                    o.highlight.FillTransparency = 0.5
                                    o.highlight.OutlineTransparency = 0
                                    o.highlight.Parent = ch
                                end
                                o.highlight.FillColor = espColor
                                o.highlight.OutlineColor = Color3.new(1, 1, 1)
                                o.highlight.Enabled = true
                            elseif o.highlight then
                                o.highlight.Enabled = false
                            end
                        else
                            espHide(o)
                        end
                    else
                        espHide(o)
                    end
                end
            end
        end
    end)

    task.spawn(function()
        while alive do
            pcall(pollFirebase)
            task.wait(2)
        end
    end)
end

function Features.Cleanup()
    alive = false
    cframeOn, noclipOn, flyOn, gravOn = false, false, false, false
    hitboxOn, espOn, airOn, platOn = false, false, false, false
    invisOn, fcOn, voidOn, antiflingOn = false, false, false, false
    carryMode, carryTarget = nil, nil
    stopFly()
    noclipRestore()
    hbRestore()
    airClear()
    if platBV then platBV:Destroy() platBV = nil end
    if spinConn then spinConn:Disconnect() spinConn = nil end
    fxBlind(false)
    Features.StopSpectate()
    Features.FixCam()
    if worldOrig then
        fullbrightOn, nofogOn = false, false
        pcall(applyLighting)
    end
    pcall(function() Features.SetXray(false) end)
    pcall(function()
        if workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = origFov end
    end)
    if infFolder then infFolder:Destroy() infFolder = nil end
    for plr in pairs(espObjects) do espRemove(plr) end
    for i = 1, #conns do
        pcall(function() conns[i]:Disconnect() end)
    end
    conns = {}
end

return Features
