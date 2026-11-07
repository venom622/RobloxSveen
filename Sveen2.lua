local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    Enabled           = true,
    Box               = true,
    Name              = true,
    Health            = true,
    HeadDot           = true,
    Skeleton          = true,
    SkeletonColor     = Color3.fromRGB(255, 255, 255),
    SkeletonThickness = 1,
    Aimlock           = false,
    AimPart           = "Head",
    AimFOV            = 150,
    AimSmoothness     = 40,
    DeadZone          = 30,
    VisibleCheck      = true,
    SkipReload        = false,
    RapidFire         = false,
    RapidFireRate     = 12,
    AimPriority       = "Crosshair",
    Friends           = {},
    Chams             = false,
    ChamsColor        = "Red",
    ChamsTransparency = 50,
    AimKey            = Enum.KeyCode.E,
    MenuKey           = Enum.KeyCode.RightShift,
}

-- ============================================================
-- STATE
-- ============================================================
local connections = {}
local function track(conn) connections[#connections + 1] = conn; return conn end

local espObjects    = {}
local menuRef       = nil
local aiming        = false
local unloaded      = false
local unload
local aimCFrame     = nil

local draggingSlider  = nil
local draggingMenu    = false
local dragStartPos    = nil
local dragStartPos0   = nil
local keybindButtons  = {}
local bindingKey      = nil

-- forward-deklaracje (uzywane wczesniej w Save/Load)
local SerializeBind, DeserializeBind

local FriendsSet = {}

local refreshPlayersUI = nil

local lmbDown = false
local lmbGameplay = false

-- jesli watek nie ma capability Plugin, Instance.new wywala blad;
-- wtedy menu/chamsy sa wylaczone, a ESP/aim/rapid dalej dzialaja
local canInstance = false
local chamsBlocked = false

-- diagnostyka rapid fire (pokazywana w COMBAT)
local rapidStatus = "idle"
local rapidShots = 0
local rapidLabel = nil
local lastRapidUi = 0

local function rebuildFriendsSet()
    table.clear(FriendsSet)
    if type(Config.Friends) ~= "table" then Config.Friends = {} end
    for _, n in ipairs(Config.Friends) do
        if type(n) == "string" and n ~= "" then FriendsSet[n] = true end
    end
end

-- ============================================================
-- SAVE / LOAD (auto load + auto save do pliku)
-- ============================================================
local HttpService = game:GetService("HttpService")
local CONFIG_FILE = "Sveen2_config.json"
local configDirty = false
local lastSave = 0

local function MarkDirty()
    configDirty = true
end

local function SaveConfig(force)
    if not force then
        -- slider wysyla duzo updateow, zapis max co 1.5s zeby nie spamowac writefile
        if os.clock() - lastSave < 1.5 then
            configDirty = true
            return
        end
    end
    local ok, err = pcall(function()
        if typeof(writefile) ~= "function" then return end
        local data = {
            _v = 3,
            Enabled = Config.Enabled,
            Box = Config.Box,
            Name = Config.Name,
            Health = Config.Health,
            HeadDot = Config.HeadDot,
            Skeleton = Config.Skeleton,
            SkeletonThickness = Config.SkeletonThickness,
            Aimlock = Config.Aimlock,
            AimPart = Config.AimPart,
            AimFOV = Config.AimFOV,
            AimSmoothness = Config.AimSmoothness,
            DeadZone = Config.DeadZone,
            VisibleCheck = Config.VisibleCheck,
            SkipReload = Config.SkipReload,
            RapidFire = Config.RapidFire,
            RapidFireRate = Config.RapidFireRate,
            AimPriority = Config.AimPriority,
            Friends = Config.Friends,
            Chams = Config.Chams,
            ChamsColor = Config.ChamsColor,
            ChamsTransparency = Config.ChamsTransparency,
            AimKey = SerializeBind(Config.AimKey),
            MenuKey = SerializeBind(Config.MenuKey),
        }
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    if ok then lastSave = os.clock(); configDirty = false end
end

local function LoadConfig()
    pcall(function()
        if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then return end
        if not isfile(CONFIG_FILE) then return end
        local raw = readfile(CONFIG_FILE)
        if not raw or raw == "" then return end
        local data = HttpService:JSONDecode(raw)
        if type(data) ~= "table" then return end
        if type(data.Enabled) == "boolean" then Config.Enabled = data.Enabled end
        if type(data.Box) == "boolean" then Config.Box = data.Box end
        if type(data.Name) == "boolean" then Config.Name = data.Name end
        if type(data.Health) == "boolean" then Config.Health = data.Health end
        if type(data.HeadDot) == "boolean" then Config.HeadDot = data.HeadDot end
        if type(data.Skeleton) == "boolean" then Config.Skeleton = data.Skeleton end
        if type(data.SkeletonThickness) == "number" then Config.SkeletonThickness = math.clamp(math.floor(data.SkeletonThickness), 1, 5) end
        if type(data.Aimlock) == "boolean" then Config.Aimlock = data.Aimlock end
        if data.AimPart == "Head" or data.AimPart == "Torso" then Config.AimPart = data.AimPart end
        if type(data.AimFOV) == "number" then Config.AimFOV = math.clamp(math.floor(data.AimFOV), 50, 500) end
        if type(data.AimSmoothness) == "number" then
            local s = math.floor(data.AimSmoothness)
            -- migracja starego zakresu 1-20 na 1-100 (tylko pliki bez _v)
            if data._v == nil and s <= 20 and s >= 1 then
                s = math.clamp(s * 5, 1, 100)
            end
            Config.AimSmoothness = math.clamp(s, 1, 100)
        end
        if type(data.DeadZone) == "number" then Config.DeadZone = math.clamp(math.floor(data.DeadZone), 0, 200) end
        if type(data.VisibleCheck) == "boolean" then Config.VisibleCheck = data.VisibleCheck end
        if type(data.SkipReload) == "boolean" then Config.SkipReload = data.SkipReload end
        if type(data.RapidFire) == "boolean" then Config.RapidFire = data.RapidFire end
        if type(data.RapidFireRate) == "number" then Config.RapidFireRate = math.clamp(math.floor(data.RapidFireRate), 2, 30) end
        if data.AimPriority == "Crosshair" or data.AimPriority == "Distance" then Config.AimPriority = data.AimPriority end
        if type(data.Friends) == "table" then
            local clean = {}
            for _, n in ipairs(data.Friends) do
                if type(n) == "string" and n ~= "" and #clean < 50 then clean[#clean + 1] = n end
            end
            Config.Friends = clean
        end
        if type(data.Chams) == "boolean" then Config.Chams = data.Chams end
        if type(data.ChamsColor) == "string" then Config.ChamsColor = data.ChamsColor end
        if type(data.ChamsTransparency) == "number" then Config.ChamsTransparency = math.clamp(math.floor(data.ChamsTransparency), 0, 90) end
        if type(data.AimKey) == "string" then Config.AimKey = DeserializeBind(data.AimKey, Config.AimKey) end
        if type(data.MenuKey) == "string" then Config.MenuKey = DeserializeBind(data.MenuKey, Config.MenuKey) end
        rebuildFriendsSet()
    end)
end

local function QueueSave()
    MarkDirty()
    SaveConfig(false)
end

-- ============================================================
-- BIND HELPERS (klawiatura + przyciski myszy)
-- UWAGA: Roblox nie wystawia MB4/MB5 (kciuk) - InputBegan dla nich
-- w ogole nie fireuje, wiec da sie zbindowac tylko MB1/MB2/MMB + klawisze.
-- Obejscie na kciuk: przemapuj go w apce myszki na klawisz i zbindowac ten klawisz.
-- ============================================================
local SHORT_MOUSE = { MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MMB" }

local function GetBindName(bind)
    if typeof(bind) == "EnumItem" then
        if bind.EnumType == Enum.UserInputType then
            return SHORT_MOUSE[bind.Name] or bind.Name
        end
        return bind.Name
    end
    return "NONE"
end

local function BindMatches(input, bind)
    if typeof(bind) ~= "EnumItem" or not input then return false end
    if bind.EnumType == Enum.UserInputType then
        return input.UserInputType == bind
    end
    return input.KeyCode == bind
end

SerializeBind = function(bind)
    if typeof(bind) ~= "EnumItem" then return "K:E" end
    if bind.EnumType == Enum.UserInputType then
        return "M:" .. bind.Name
    end
    return "K:" .. bind.Name
end

DeserializeBind = function(str, fallback)
    if type(str) == "string" then
        local prefix, name = str:match("^(%a):(.+)$")
        if prefix == "M" and name then
            local ok, e = pcall(function() return Enum.UserInputType[name] end)
            if ok and typeof(e) == "EnumItem" then return e end
        elseif prefix == "K" and name then
            local ok, e = pcall(function() return Enum.KeyCode[name] end)
            if ok and typeof(e) == "EnumItem" then return e end
        else
            -- legacy: plain "E" = KeyCode
            local ok, e = pcall(function() return Enum.KeyCode[str] end)
            if ok and typeof(e) == "EnumItem" then return e end
        end
    end
    return fallback
end

local function RefreshBindLabel(key)
    local btn = keybindButtons[key]
    if btn then
        btn.Text = btn:GetAttribute("Label") .. ": " .. GetBindName(Config[key])
    end
end

-- ============================================================
-- HELPERS
-- ============================================================
local function createDrawing(class, props)
    local obj = Drawing.new(class)
    if props then for k, v in pairs(props) do obj[k] = v end end
    return obj
end

local function setVisible(esp, visible)
    if not esp then return end
    esp.box.Visible       = visible and Config.Box
    esp.nameTag.Visible   = visible and Config.Name
    esp.healthBg.Visible  = visible and Config.Health
    esp.healthBar.Visible = visible and Config.Health
    if not (visible and Config.HeadDot) then esp.headDot.Visible = false end
end

local function hideSkeleton(esp)
    for _, line in ipairs(esp.skeletonLines) do line.Visible = false end
end

-- ============================================================
-- ESP OBJECTS
-- ============================================================
local function createESP(player)
    if player == LocalPlayer then return end
    if espObjects[player] then return end
    local box = createDrawing("Square", { Color = Color3.fromRGB(255,255,255), Thickness = 0.5, Filled = false, Visible = false })
    local nameTag = createDrawing("Text", { Text = player.Name, Color = Color3.fromRGB(255,255,255), Size = 12, Center = true, Outline = true, OutlineColor = Color3.fromRGB(0,0,0), Visible = false, ZIndex = box.ZIndex + 1 })
    local healthBg = createDrawing("Square", { Color = Color3.fromRGB(0,0,0), Filled = true, Visible = false })
    local healthBar = createDrawing("Square", { Color = Color3.fromRGB(0,255,0), Filled = true, Visible = false })
    local headDot = createDrawing("Circle", { Color = Color3.fromRGB(255,255,255), Thickness = 1, Filled = false, Visible = false })
    espObjects[player] = { box = box, nameTag = nameTag, healthBg = healthBg, healthBar = healthBar, headDot = headDot, skeletonLines = {}, cachedCharacter = nil, cachedMotors = {} }
end

local function removeESP(player)
    local esp = espObjects[player]
    if not esp then return end
    for key, obj in pairs(esp) do
        if key ~= "skeletonLines" and key ~= "cachedMotors" and key ~= "cachedCharacter" then
            pcall(function() obj:Remove() end)
        end
    end
    for _, line in ipairs(esp.skeletonLines) do pcall(function() line:Remove() end) end
    espObjects[player] = nil
end

-- ============================================================
-- BOUNDING BOX
-- ============================================================
local function getScreenBounds(model)
    local cf, size = model:GetBoundingBox()
    local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOnScreen = false
    for _, sx in ipairs({ -hx, hx }) do
        for _, sy in ipairs({ -hy, hy }) do
            for _, sz in ipairs({ -hz, hz }) do
                local worldPos = cf:PointToWorldSpace(Vector3.new(sx, sy, sz))
                local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
                if onScreen and screenPos.Z > 0 then
                    anyOnScreen = true
                    if screenPos.X < minX then minX = screenPos.X end
                    if screenPos.Y < minY then minY = screenPos.Y end
                    if screenPos.X > maxX then maxX = screenPos.X end
                    if screenPos.Y > maxY then maxY = screenPos.Y end
                end
            end
        end
    end
    if not anyOnScreen then return nil end
    return minX, minY, maxX, maxY
end

-- ============================================================
-- SKELETON
-- ============================================================
local function rebuildMotorCache(esp, character)
    local motors = {}
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("Motor6D") then motors[#motors + 1] = d end
    end
    esp.cachedCharacter = character
    esp.cachedMotors    = motors
end

local function updateSkeleton(esp, character)
    if esp.cachedCharacter ~= character then rebuildMotorCache(esp, character) end
    local lines = esp.skeletonLines
    local idx = 1
    for _, motor in ipairs(esp.cachedMotors) do
        if motor.Part0 and motor.Part1 and motor.Parent then
            local s0, on0 = Camera:WorldToViewportPoint(motor.Part0.Position)
            local s1, on1 = Camera:WorldToViewportPoint(motor.Part1.Position)
            if on0 and on1 and s0.Z > 0 and s1.Z > 0 then
                local line = lines[idx]
                if not line then
                    line = createDrawing("Line", { Thickness = Config.SkeletonThickness, Color = Config.SkeletonColor, Visible = false })
                    lines[idx] = line
                end
                line.From      = Vector2.new(s0.X, s0.Y)
                line.To        = Vector2.new(s1.X, s1.Y)
                line.Color     = Config.SkeletonColor
                line.Thickness = Config.SkeletonThickness
                line.Visible   = true
                idx = idx + 1
            end
        end
    end
    for i = idx, #lines do lines[i].Visible = false end
end

-- ============================================================
-- UPDATE ESP
-- ============================================================
local function updateESP(player, esp)
    if not Config.Enabled then setVisible(esp, false); hideSkeleton(esp); return end
    local character = player.Character
    if not character then setVisible(esp, false); hideSkeleton(esp); return end
    local head     = character:FindFirstChild("Head")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not head or not humanoid or humanoid.Health <= 0 then setVisible(esp, false); hideSkeleton(esp); return end

    if Config.Skeleton then updateSkeleton(esp, character) else hideSkeleton(esp) end

    local minX, minY, maxX, maxY = getScreenBounds(character)
    if not minX then setVisible(esp, false); return end
    local width  = maxX - minX
    local height = maxY - minY
    if width <= 0 or height <= 0 then setVisible(esp, false); return end

    local x, y = minX, minY
    esp.box.Size     = Vector2.new(width, height)
    esp.box.Position = Vector2.new(x, y)

    local nameOffset = math.max(2, height * 0.18)
    esp.nameTag.Text     = player.Name
    esp.nameTag.Position = Vector2.new(x + width / 2, y - nameOffset)

    local headPos, headOnScreen = Camera:WorldToViewportPoint(head.Position)
    local headValid = headOnScreen and headPos.Z > 0
    if headValid then
        esp.headDot.Position = Vector2.new(headPos.X, headPos.Y)
        esp.headDot.Radius   = math.max(1, height * 0.035)
    end

    local healthPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
    local barWidth  = math.max(1, width * 0.035)
    local barGap    = math.max(1, width * 0.03)
    local barHeight = height
    local barX      = x - barWidth - barGap
    local barY      = y

    esp.healthBg.Size     = Vector2.new(barWidth, barHeight)
    esp.healthBg.Position = Vector2.new(barX, barY)

    local fillHeight = barHeight * healthPercent
    esp.healthBar.Size     = Vector2.new(barWidth, fillHeight)
    esp.healthBar.Position = Vector2.new(barX, barY + (barHeight - fillHeight))

    if healthPercent > 0.6 then
        esp.healthBar.Color = Color3.fromRGB(0, 255, 0)
    elseif healthPercent > 0.3 then
        esp.healthBar.Color = Color3.fromRGB(255, 255, 0)
    else
        esp.healthBar.Color = Color3.fromRGB(255, 0, 0)
    end

    setVisible(esp, true)
    esp.headDot.Visible = headValid and Config.HeadDot
end

-- ============================================================
-- AIMLOCK
-- ============================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1; fovCircle.Color = Color3.fromRGB(255,255,255)
fovCircle.Filled = false; fovCircle.NumSides = 64
fovCircle.Transparency = 0.5; fovCircle.Visible = false

local deadZoneCircle = Drawing.new("Circle")
deadZoneCircle.Thickness = 1; deadZoneCircle.Color = Color3.fromRGB(255,100,100)
deadZoneCircle.Filled = false; deadZoneCircle.NumSides = 32
deadZoneCircle.Transparency = 0.35; deadZoneCircle.Visible = false

local function getAimPart(character)
    if Config.AimPart == "Head" then
        return character:FindFirstChild("Head")
    else
        return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
    end
end

local aimRayParams = RaycastParams.new()
aimRayParams.FilterType = Enum.RaycastFilterType.Exclude
aimRayParams.IgnoreWater = true

local function isPartVisible(char, part)
    if not Config.VisibleCheck then return true end
    local origin = Camera.CFrame.Position
    local targetPos = part.Position
    local dir = targetPos - origin
    local dist = dir.Magnitude
    if dist < 1 then return true end
    aimRayParams.FilterDescendantsInstances = {}
    local lc = LocalPlayer.Character
    if lc then aimRayParams.FilterDescendantsInstances = { lc } end
    local ok, result = pcall(function()
        return workspace:Raycast(origin, dir.Unit * dist, aimRayParams)
    end)
    if not ok then return true end
    if not result then return true end
    return result.Instance and result.Instance:IsDescendantOf(char) or false
end

local function getBestAimTarget()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local camPos = Camera.CFrame.Position
    local useDist = Config.AimPriority == "Distance"
    local best, bestScore = nil, nil
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and not FriendsSet[player.Name] then
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    local part = getAimPart(char)
                    if part then
                        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and pos.Z > 0 then
                            local d = (Vector2.new(pos.X, pos.Y) - center).Magnitude
                            if d < Config.AimFOV then
                                local score
                                if useDist then
                                    score = (part.Position - camPos).Magnitude
                                else
                                    score = d
                                end
                                if bestScore == nil or score < bestScore then
                                    if isPartVisible(char, part) then
                                        best = { part = part, head = char:FindFirstChild("Head"), character = char }
                                        bestScore = score
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function distFromCenterOfPart(part)
    if not part then return math.huge end
    local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen or pos.Z <= 0 then return math.huge end
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    return (Vector2.new(pos.X, pos.Y) - center).Magnitude
end

-- ============================================================
-- CHAMS (Highlight przez sciany)
-- ============================================================
local CHAMS_COLORS = {
    Red    = Color3.fromRGB(255, 60, 60),
    Green  = Color3.fromRGB(60, 255, 120),
    Blue   = Color3.fromRGB(80, 140, 255),
    Yellow = Color3.fromRGB(255, 220, 60),
    Pink   = Color3.fromRGB(255, 80, 200),
    Cyan   = Color3.fromRGB(60, 230, 255),
    White  = Color3.fromRGB(240, 240, 240),
}
local CHAMS_COLOR_NAMES = { "Red", "Green", "Blue", "Yellow", "Pink", "Cyan", "White" }

local chamsMap = {}

local function updateChams(player)
    if chamsBlocked or not canInstance then return end
    local hl = chamsMap[player]
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not Config.Chams or not char or not hum or hum.Health <= 0 then
        if hl then hl.Enabled = false end
        return
    end
    if not hl or hl.Parent == nil or hl.Adornee ~= char then
        if hl then pcall(function() hl:Destroy() end) end
        local created = nil
        local okHl = pcall(function()
            created = Instance.new("Highlight")
            created.Name = "SveenChams"
            created.Adornee = char
            created.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            created.Parent = char
        end)
        if not okHl or not created then
            chamsBlocked = true
            chamsMap[player] = nil
            return
        end
        hl = created
        chamsMap[player] = hl
    end
    hl.FillColor = CHAMS_COLORS[Config.ChamsColor] or CHAMS_COLORS.Red
    hl.FillTransparency = math.clamp(Config.ChamsTransparency or 50, 0, 90) / 100
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.OutlineTransparency = 0
    hl.Enabled = true
end

local function removeChams(player)
    local hl = chamsMap[player]
    if hl then pcall(function() hl:Destroy() end) end
    chamsMap[player] = nil
end

-- ============================================================
-- SKIP RELOAD (auto anulowanie przeladowania: Reload:FireServer(true))
-- ============================================================
local reloadRemote = nil
local wasReloading = false

local function getReloadRemote()
    if reloadRemote and reloadRemote.Parent then return reloadRemote end
    reloadRemote = nil
    pcall(function()
        local folder = game:GetService("ReplicatedStorage"):WaitForChild("GunRemotes", 5)
        if folder then
            reloadRemote = folder:WaitForChild("Reload", 5)
        end
    end)
    return reloadRemote
end

local function updateSkipReload()
    if not Config.SkipReload then wasReloading = false return end
    local char = LocalPlayer.Character
    if not char then wasReloading = false return end
    local reloading = Camera:GetAttribute("ReloadStart") ~= nil
    if not reloading then
        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool:GetAttribute("Reloading") == true then
                reloading = true
                break
            end
        end
    end
    -- strzal tylko na zboczu (start przeladowania), zeby nie spamowac remote
    if reloading and not wasReloading then
        local rem = getReloadRemote()
        if rem then pcall(function() rem:FireServer(true) end) end
    end
    wasReloading = reloading
end

-- ============================================================
-- RAPID FIRE (auto-ogien przytrzymanym LMB, legitne dane jak gun client)
-- ============================================================
local fireRemote = nil
local lastRapidShot = 0
local lastRapidReload = 0

local function getFireRemote()
    if fireRemote and fireRemote.Parent then return fireRemote end
    fireRemote = nil
    pcall(function()
        local folder = game:GetService("ReplicatedStorage"):WaitForChild("GunRemotes", 5)
        if folder then
            fireRemote = folder:WaitForChild("Fire", 5)
        end
    end)
    return fireRemote
end

local function rapidHumanPart(inst)
    local v = inst
    while v do
        local m = v:FindFirstAncestorOfClass("Model")
        if m then
            if not m:FindFirstChildOfClass("Humanoid") then
                v = m
            else
                return inst
            end
        else
            return nil
        end
    end
    return nil
end

local function updateRapidFire()
    if not Config.RapidFire then rapidStatus = "OFF" return end
    if not lmbDown or not lmbGameplay then rapidStatus = "czekam na LMB" return end
    local now = os.clock()
    local rate = math.clamp(Config.RapidFireRate or 12, 2, 30)
    if now - lastRapidShot < 1 / rate then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then rapidStatus = "brak postaci" return end
    if LocalPlayer:GetAttribute("MenuOpen") then rapidStatus = "MenuOpen" return end
    local tool = char:FindFirstChildOfClass("Tool")
    if not tool then rapidStatus = "brak broni w rece" return end
    if tool:GetAttribute("Reloading") == true then rapidStatus = "reloading..." return end
    local ammo = tool:GetAttribute("Ammo")
    if typeof(ammo) ~= "number" or ammo <= 0 then
        rapidStatus = "pusty magazynek"
        -- pusty magazynek: auto reload (tylko gdy skip wylaczony), max 1x na 0.5s
        if not Config.SkipReload and now - lastRapidReload > 0.5 then
            lastRapidReload = now
            local rem = getReloadRemote()
            if rem then pcall(function() rem:FireServer() end) end
        end
        return
    end
    local aimTraceMod, gunConfigMod = nil, nil
    local okReq = pcall(function()
        local rs = game:GetService("ReplicatedStorage")
        aimTraceMod = require(rs:WaitForChild("AimTrace", 5))
        gunConfigMod = require(rs:WaitForChild("GunConfig", 5))
    end)
    if not okReq or not aimTraceMod then rapidStatus = "blad AimTrace/GunConfig" return end
    local range = 1000
    if gunConfigMod and typeof(gunConfigMod.Range) == "number" then
        range = gunConfigMod.Range
    end
    local vps = Camera.ViewportSize
    local ray = Camera:ViewportPointToRay(vps.X / 2, vps.Y / 2)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { char, Camera }
    params.CollisionGroup = "Bullet"
    params.IgnoreWater = true
    local ok, hitPos, hit = pcall(function()
        local res = workspace:Raycast(ray.Origin, ray.Direction * range, params)
        if res then return res.Position, res end
        return ray.Origin + ray.Direction * range, nil
    end)
    if not ok then rapidStatus = "blad raycast" return end
    local muzzle = nil
    pcall(function()
        local handle = tool:FindFirstChild("Handle")
        local head = char:FindFirstChild("Head")
        if handle and handle:IsA("BasePart") then
            local vm = Camera:FindFirstChild("ViewModel")
            local vmHandle = vm and vm:FindFirstChild("Handle")
            local use = (vmHandle and vmHandle:IsA("BasePart")) and vmHandle or handle
            local tw, th = 4, 1
            pcall(function() tw, th = tool.Size.X, tool.Size.Y end)
            local off = tool:GetAttribute("Muzzle") or Vector3.new(-tw / 2, th * 0.34, 0)
            muzzle = use.CFrame * (off * (use.Size.X / tw))
        elseif head then
            muzzle = head.Position
        else
            muzzle = hitPos
        end
    end)
    if not muzzle then rapidStatus = "blad lufy" return end
    local snapOk, snap = pcall(function() return aimTraceMod.Snapshot() end)
    if not snapOk then rapidStatus = "blad Snapshot" return end
    local rem = getFireRemote()
    if not rem then rapidStatus = "brak Fire remote" return end
    local okFire = pcall(function()
        rem:FireServer(
            hitPos,
            muzzle,
            snap,
            aimTraceMod.CameraPosition(),
            aimTraceMod.Report(snap, hitPos),
            rapidHumanPart(hit and hit.Instance)
        )
    end)
    if okFire then
        rapidStatus = "FIRE ok (ammo " .. tostring(ammo) .. ")"
        rapidShots = rapidShots + 1
        lastRapidShot = now
    else
        rapidStatus = "FireServer odrzucony"
    end
end

-- ============================================================
-- UI HELPERS (fixed padding)
-- ============================================================
local function nextOrder(parent)
    local o = parent:GetAttribute("UIOrder") or 0
    o = o + 1
    parent:SetAttribute("UIOrder", o)
    return o
end

local function makeRow(parent, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h or 24)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(parent)
    f.Parent = parent
    return f
end

local function makeLabel(parent, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -40, 1, 0)
    l.Position = UDim2.new(0, 0, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(180, 180, 180)
    l.TextSize = 11
    l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center
    l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end

local function createToggle(parent, text, key)
    local row = makeRow(parent, 24)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = row
    makeLabel(row, text)

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 28, 0, 14)
    pill.Position = UDim2.new(1, -28, 0.5, -7)
    pill.BackgroundColor3 = Config[key] and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(30, 30, 32)
    pill.BorderSizePixel = 0
    pill.Parent = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 10, 0, 10)
    knob.Position = Config[key] and UDim2.new(1, -12, 0.5, -5) or UDim2.new(0, 2, 0.5, -5)
    knob.BackgroundColor3 = Config[key] and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(130, 130, 130)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    btn.MouseButton1Click:Connect(function()
        Config[key] = not Config[key]
        pill.BackgroundColor3 = Config[key] and Color3.fromRGB(210, 210, 210) or Color3.fromRGB(30, 30, 32)
        knob.BackgroundColor3 = Config[key] and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(130, 130, 130)
        knob.Position = Config[key] and UDim2.new(1, -12, 0.5, -5) or UDim2.new(0, 2, 0.5, -5)
        QueueSave()
    end)
end

local function createSlider(parent, text, key, min, max, suffix)
    local row = makeRow(parent, 38)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -65, 0, 14)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(180, 180, 180)
    label.TextSize = 11
    label.Font = Enum.Font.Gotham
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = row

    local valueLabel = Instance.new("TextLabel")
    valueLabel.Size = UDim2.new(0, 65, 0, 14)
    valueLabel.Position = UDim2.new(1, -65, 0, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.Text = tostring(Config[key]) .. (suffix or "")
    valueLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
    valueLabel.TextSize = 11
    valueLabel.Font = Enum.Font.Gotham
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = row

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, -10, 0, 4)
    track.Position = UDim2.new(0, 5, 0, 24)
    track.BackgroundColor3 = Color3.fromRGB(28, 28, 30)
    track.AutoButtonColor = false
    track.Text = ""
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((Config[key] - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(210, 210, 210)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 10, 0, 10)
    knob.Position = UDim2.new((Config[key] - min) / (max - min), -5, 0.5, -5)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local function update(input)
        local pos = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(min + (max - min) * pos + 0.5)
        Config[key] = val
        fill.Size = UDim2.new(pos, 0, 1, 0)
        knob.Position = UDim2.new(pos, -5, 0.5, -5)
        valueLabel.Text = tostring(val) .. (suffix or "")
        MarkDirty()
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = update
            update(input)
        end
    end)
end

local function createDropdown(parent, text, key, options)
    local row = makeRow(parent, 24)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.Parent = row

    local left = Instance.new("TextLabel")
    left.Size = UDim2.new(0.55, 0, 1, 0)
    left.BackgroundTransparency = 1
    left.Text = text
    left.TextColor3 = Color3.fromRGB(180, 180, 180)
    left.TextSize = 11
    left.Font = Enum.Font.Gotham
    left.TextXAlignment = Enum.TextXAlignment.Left
    left.TextTruncate = Enum.TextTruncate.AtEnd
    left.Parent = row

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0.45, 0, 1, 0)
    val.Position = UDim2.new(0.55, 0, 0, 0)
    val.BackgroundTransparency = 1
    val.Text = tostring(Config[key]) .. "  v"
    val.TextColor3 = Color3.fromRGB(140, 140, 140)
    val.TextSize = 11
    val.Font = Enum.Font.Gotham
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.TextTruncate = Enum.TextTruncate.AtEnd
    val.Parent = row

    btn.MouseButton1Click:Connect(function()
        local idx = 1
        for i, v in ipairs(options) do if v == Config[key] then idx = i; break end end
        idx = idx % #options + 1
        Config[key] = options[idx]
        val.Text = tostring(Config[key]) .. "  v"
        QueueSave()
    end)
end

local function createKeybind(parent, text, key)
    local row = makeRow(parent, 28)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
    btn.BorderSizePixel = 0
    btn.Text = text .. ": " .. GetBindName(Config[key])
    btn.TextColor3 = Color3.fromRGB(180, 180, 180)
    btn.TextSize = 11
    btn.Font = Enum.Font.Gotham
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.AutoButtonColor = false
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = btn

    btn:SetAttribute("Label", text)
    keybindButtons[key] = btn
    btn.MouseButton1Click:Connect(function()
        if bindingKey == key then
            -- drugie klikniecie anuluje bindowanie
            bindingKey = nil
            RefreshBindLabel(key)
            return
        end
        if bindingKey then return end
        bindingKey = key
        btn.Text = text .. ": [Press...]"
    end)
end

local function createTextbox(parent, placeholder)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 26)
    box.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
    box.BorderSizePixel = 0
    box.PlaceholderText = placeholder or "nick..."
    box.PlaceholderColor3 = Color3.fromRGB(90, 90, 90)
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(200, 200, 200)
    box.TextSize = 11
    box.Font = Enum.Font.Gotham
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextTruncate = Enum.TextTruncate.AtEnd
    box.ClearTextOnFocus = false
    box.LayoutOrder = nextOrder(parent)
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = box
    return box
end

local function createSectionLabel(parent, text)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 20)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.LayoutOrder = nextOrder(parent)
    f.Parent = parent
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.fromRGB(100, 100, 100)
    l.TextSize = 10
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Bottom
    l.Parent = f
end

local function getUIParent()
    local ok, coreGui = pcall(function() return game:GetService("CoreGui") end)
    if ok and coreGui then
        local ok2 = pcall(function() return coreGui.Name end)
        if ok2 then return coreGui end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

-- ============================================================
-- MENU (fixed padding + drag)
-- ============================================================
local function createMenu()
    local parent = getUIParent()
    local old = parent:FindFirstChild("ESP_Menu")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name            = "ESP_Menu"
    screenGui.ResetOnSpawn    = false
    screenGui.IgnoreGuiInset  = true
    screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder    = 999
    screenGui.Parent          = parent

    -- Main
    local main = Instance.new("Frame")
    main.Name             = "Main"
    main.Size             = UDim2.new(0, 420, 0, 380)
    main.Position         = UDim2.new(0.5, -210, 0.5, -190)
    main.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    main.BorderSizePixel  = 0
    main.Active           = true
    main.ClipsDescendants = true
    main.Parent           = screenGui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(35, 35, 40)
    stroke.Thickness = 1
    stroke.Parent = main

    -- Drag handle (top bar, square bottom - clipping from main rounds the top)
    local topBar = Instance.new("Frame")
    topBar.Name             = "TopBar"
    topBar.Size             = UDim2.new(1, 0, 0, 28)
    topBar.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    topBar.BorderSizePixel  = 0
    topBar.Parent           = main

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "SVEEN"
    title.TextColor3 = Color3.fromRGB(220, 220, 220)
    title.TextSize = 11
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = topBar

    -- Drag logic
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingMenu  = true
            dragStartPos  = input.Position
            dragStartPos0 = main.Position
        end
    end)

    -- Sidebar
    local sidebar = Instance.new("Frame")
    sidebar.Name             = "Sidebar"
    sidebar.Size             = UDim2.new(0, 100, 1, -28)
    sidebar.Position         = UDim2.new(0, 0, 0, 28)
    sidebar.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
    sidebar.BorderSizePixel  = 0
    sidebar.Parent           = main

    local navContainer = Instance.new("Frame")
    navContainer.Name = "Nav"
    navContainer.Size = UDim2.new(1, -12, 0, 0)
    navContainer.Position = UDim2.new(0, 6, 0, 10)
    navContainer.AutomaticSize = Enum.AutomaticSize.Y
    navContainer.BackgroundTransparency = 1
    navContainer.Parent = sidebar
    local navList = Instance.new("UIListLayout")
    navList.Padding = UDim.new(0, 4)
    navList.SortOrder = Enum.SortOrder.LayoutOrder
    navList.Parent = navContainer

    local pages = {}
    local navButtons = {}
    local navOrder = 0

    local function addNav(name)
        navOrder = navOrder + 1
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 26)
        btn.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
        btn.BorderSizePixel = 0
        btn.Text = name
        btn.TextColor3 = Color3.fromRGB(120, 120, 120)
        btn.TextSize = 10
        btn.Font = Enum.Font.Gotham
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.AutoButtonColor = false
        btn.LayoutOrder = navOrder
        btn.Parent = navContainer
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 6)
        pad.Parent = btn

        navButtons[name] = { btn = btn }

        btn.MouseButton1Click:Connect(function()
            for _, p in pairs(pages) do p.Visible = false end
            if pages[name] then pages[name].Visible = true end
            for _, b in pairs(navButtons) do
                b.btn.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
                b.btn.TextColor3 = Color3.fromRGB(120, 120, 120)
            end
            btn.BackgroundColor3 = Color3.fromRGB(32, 32, 35)
            btn.TextColor3 = Color3.fromRGB(240, 240, 240)
        end)
    end

    -- Content
    local content = Instance.new("Frame")
    content.Name             = "Content"
    content.Size             = UDim2.new(1, -100, 1, -28)
    content.Position         = UDim2.new(0, 100, 0, 28)
    content.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
    content.BorderSizePixel  = 0
    content.Parent           = main

    -- Username at bottom of sidebar
    local userName = Instance.new("TextLabel")
    userName.Size = UDim2.new(1, -12, 0, 16)
    userName.Position = UDim2.new(0, 6, 1, -22)
    userName.BackgroundTransparency = 1
    userName.Text = LocalPlayer.DisplayName or LocalPlayer.Name
    userName.TextColor3 = Color3.fromRGB(90, 90, 90)
    userName.TextSize = 10
    userName.Font = Enum.Font.Gotham
    userName.TextXAlignment = Enum.TextXAlignment.Left
    userName.TextTruncate = Enum.TextTruncate.AtEnd
    userName.Parent = sidebar

    local function createPage(name)
        local page = Instance.new("ScrollingFrame")
        page.Name = name
        page.Size = UDim2.new(1, 0, 1, 0)
        page.Position = UDim2.new(0, 0, 0, 0)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 2
        page.ScrollBarImageColor3 = Color3.fromRGB(50, 50, 50)
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.ScrollingDirection = Enum.ScrollingDirection.Y
        page.Visible = false
        page.Parent = content
        page:SetAttribute("UIOrder", 1)

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Size = UDim2.new(1, 0, 0, 20)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = name
        titleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
        titleLabel.TextSize = 13
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.LayoutOrder = 1
        titleLabel.Parent = page

        local list = Instance.new("UIListLayout")
        list.Padding = UDim.new(0, 6)
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.FillDirection = Enum.FillDirection.Vertical
        list.HorizontalAlignment = Enum.HorizontalAlignment.Left
        list.VerticalAlignment = Enum.VerticalAlignment.Top
        list.Parent = page

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 12)
        padding.PaddingRight = UDim.new(0, 12)
        padding.PaddingTop = UDim.new(0, 10)
        padding.PaddingBottom = UDim.new(0, 12)
        padding.Parent = page

        pages[name] = page
        return page
    end

    local visualsPage  = createPage("VISUALS")
    local combatPage   = createPage("COMBAT")
    local configsPage  = createPage("CONFIGS")
    local skinsPage    = createPage("SKINS")
    local worldPage    = createPage("WORLD")
    local movementPage = createPage("MOVEMENT")

    -- VISUALS
    createSectionLabel(visualsPage, "ESP")
    createToggle(visualsPage, "Master ESP", "Enabled")
    createToggle(visualsPage, "Box", "Box")
    createToggle(visualsPage, "Name", "Name")
    createToggle(visualsPage, "Health Bar", "Health")
    createToggle(visualsPage, "Head Dot", "HeadDot")
    createToggle(visualsPage, "Skeleton", "Skeleton")
    createSectionLabel(visualsPage, "SKELETON")
    createSlider(visualsPage, "Thickness", "SkeletonThickness", 1, 5)
    createSectionLabel(visualsPage, "CHAMS")
    createToggle(visualsPage, "Chams", "Chams")
    createDropdown(visualsPage, "Chams Color", "ChamsColor", CHAMS_COLOR_NAMES)
    createSlider(visualsPage, "Chams Fill", "ChamsTransparency", 0, 90, "%")

    -- COMBAT
    createSectionLabel(combatPage, "AIMLOCK")
    createToggle(combatPage, "Aimlock", "Aimlock")
    createToggle(combatPage, "Wall Check", "VisibleCheck")
    createToggle(combatPage, "Skip Reload", "SkipReload")
    createToggle(combatPage, "Rapid Fire", "RapidFire")
    createSlider(combatPage, "Fire Rate", "RapidFireRate", 2, 30, " /s")
    local rapidStatusLbl = Instance.new("TextLabel")
    rapidStatusLbl.Size = UDim2.new(1, 0, 0, 16)
    rapidStatusLbl.BackgroundTransparency = 1
    rapidStatusLbl.Text = "Rapid: idle"
    rapidStatusLbl.TextColor3 = Color3.fromRGB(90, 90, 90)
    rapidStatusLbl.TextSize = 10
    rapidStatusLbl.Font = Enum.Font.Gotham
    rapidStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
    rapidStatusLbl.TextTruncate = Enum.TextTruncate.AtEnd
    rapidStatusLbl.LayoutOrder = nextOrder(combatPage)
    rapidStatusLbl.Parent = combatPage
    rapidLabel = rapidStatusLbl
    createDropdown(combatPage, "Aim Part", "AimPart", {"Head", "Torso"})
    createDropdown(combatPage, "Priority", "AimPriority", {"Crosshair", "Distance"})
    createSlider(combatPage, "Aim FOV", "AimFOV", 50, 500)
    createSlider(combatPage, "Smoothness", "AimSmoothness", 1, 100)
    createSlider(combatPage, "Dead Zone", "DeadZone", 0, 200, " px")
    createSectionLabel(combatPage, "BINDS")
    createKeybind(combatPage, "Aim Key", "AimKey")
    createSectionLabel(combatPage, "FRIENDS (nie aimuje)")

    local friendBox = createTextbox(combatPage, "Dokladny nick...")

    local addFriendBtn = Instance.new("TextButton")
    addFriendBtn.Size = UDim2.new(1, 0, 0, 26)
    addFriendBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 60)
    addFriendBtn.BorderSizePixel = 0
    addFriendBtn.Text = "ADD FRIEND"
    addFriendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    addFriendBtn.TextSize = 11
    addFriendBtn.Font = Enum.Font.GothamBold
    addFriendBtn.LayoutOrder = nextOrder(combatPage)
    addFriendBtn.Parent = combatPage
    Instance.new("UICorner", addFriendBtn).CornerRadius = UDim.new(0, 4)

    local friendsList = Instance.new("Frame")
    friendsList.Name = "FriendsList"
    friendsList.Size = UDim2.new(1, 0, 0, 0)
    friendsList.AutomaticSize = Enum.AutomaticSize.Y
    friendsList.BackgroundTransparency = 1
    friendsList.BorderSizePixel = 0
    friendsList.LayoutOrder = nextOrder(combatPage)
    friendsList.Parent = combatPage
    friendsList:SetAttribute("UIOrder", 0)
    local friendsLayout = Instance.new("UIListLayout")
    friendsLayout.Padding = UDim.new(0, 4)
    friendsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    friendsLayout.Parent = friendsList

    local function rebuildFriendsList()
        for _, c in ipairs(friendsList:GetChildren()) do
            if c:IsA("GuiObject") then c:Destroy() end
        end
        friendsList:SetAttribute("UIOrder", 0)
        for _, fname in ipairs(Config.Friends) do
            local row = makeRow(friendsList, 24)
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, -32, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = fname
            lbl.TextColor3 = Color3.fromRGB(140, 220, 140)
            lbl.TextSize = 11
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.Parent = row
            local xBtn = Instance.new("TextButton")
            xBtn.Size = UDim2.new(0, 24, 0, 20)
            xBtn.Position = UDim2.new(1, -24, 0.5, -10)
            xBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
            xBtn.BorderSizePixel = 0
            xBtn.Text = "X"
            xBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
            xBtn.TextSize = 11
            xBtn.Font = Enum.Font.GothamBold
            xBtn.AutoButtonColor = false
            xBtn.Parent = row
            Instance.new("UICorner", xBtn).CornerRadius = UDim.new(0, 4)
            local victim = fname
            xBtn.MouseButton1Click:Connect(function()
                for i, n in ipairs(Config.Friends) do
                    if n == victim then table.remove(Config.Friends, i) break end
                end
                rebuildFriendsSet()
                rebuildFriendsList()
                QueueSave()
            end)
        end
    end

    local function addFriendFromBox()
        local raw = friendBox.Text or ""
        local name = raw:match("^%s*(.-)%s*$")
        if name == "" then return end
        for _, n in ipairs(Config.Friends) do
            if n == name then friendBox.Text = "" return end
        end
        if #Config.Friends >= 50 then return end
        Config.Friends[#Config.Friends + 1] = name
        friendBox.Text = ""
        rebuildFriendsSet()
        rebuildFriendsList()
        QueueSave()
    end

    addFriendBtn.MouseButton1Click:Connect(addFriendFromBox)
    friendBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then addFriendFromBox() end
    end)

    rebuildFriendsList()

    createSectionLabel(combatPage, "PLAYERS (klik = friend)")

    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, 0, 0, 24)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "REFRESH LIST"
    refreshBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
    refreshBtn.TextSize = 10
    refreshBtn.Font = Enum.Font.GothamBold
    refreshBtn.LayoutOrder = nextOrder(combatPage)
    refreshBtn.Parent = combatPage
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 4)

    local playersList = Instance.new("Frame")
    playersList.Name = "PlayersList"
    playersList.Size = UDim2.new(1, 0, 0, 0)
    playersList.AutomaticSize = Enum.AutomaticSize.Y
    playersList.BackgroundTransparency = 1
    playersList.BorderSizePixel = 0
    playersList.LayoutOrder = nextOrder(combatPage)
    playersList.Parent = combatPage
    playersList:SetAttribute("UIOrder", 0)
    local playersLayout = Instance.new("UIListLayout")
    playersLayout.Padding = UDim.new(0, 4)
    playersLayout.SortOrder = Enum.SortOrder.LayoutOrder
    playersLayout.Parent = playersList

    local function rebuildPlayersList()
        for _, c in ipairs(playersList:GetChildren()) do
            if c:IsA("GuiObject") then c:Destroy() end
        end
        playersList:SetAttribute("UIOrder", 0)
        local all = Players:GetPlayers()
        table.sort(all, function(a, b) return a.Name:lower() < b.Name:lower() end)
        for _, p in ipairs(all) do
            if p ~= LocalPlayer then
                local pname = p.Name
                local isF = FriendsSet[pname] == true
                local row = makeRow(playersList, 24)
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, -32, 1, 0)
                lbl.BackgroundTransparency = 1
                if p.DisplayName ~= pname then
                    lbl.Text = pname .. " (@" .. p.DisplayName .. ")"
                else
                    lbl.Text = pname
                end
                lbl.TextColor3 = isF and Color3.fromRGB(140, 220, 140) or Color3.fromRGB(180, 180, 180)
                lbl.TextSize = 11
                lbl.Font = Enum.Font.Gotham
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.TextTruncate = Enum.TextTruncate.AtEnd
                lbl.Parent = row
                local tBtn = Instance.new("TextButton")
                tBtn.Size = UDim2.new(0, 24, 0, 20)
                tBtn.Position = UDim2.new(1, -24, 0.5, -10)
                tBtn.BorderSizePixel = 0
                if isF then
                    tBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 60)
                    tBtn.Text = "✓"
                    tBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                else
                    tBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
                    tBtn.Text = "+"
                    tBtn.TextColor3 = Color3.fromRGB(180, 180, 180)
                end
                tBtn.TextSize = 11
                tBtn.Font = Enum.Font.GothamBold
                tBtn.AutoButtonColor = false
                tBtn.Parent = row
                Instance.new("UICorner", tBtn).CornerRadius = UDim.new(0, 4)
                tBtn.MouseButton1Click:Connect(function()
                    if FriendsSet[pname] then
                        for i, n in ipairs(Config.Friends) do
                            if n == pname then table.remove(Config.Friends, i) break end
                        end
                    else
                        if #Config.Friends < 50 then
                            Config.Friends[#Config.Friends + 1] = pname
                        end
                    end
                    rebuildFriendsSet()
                    rebuildFriendsList()
                    rebuildPlayersList()
                    QueueSave()
                end)
            end
        end
    end

    refreshBtn.MouseButton1Click:Connect(function() rebuildPlayersList() end)
    refreshPlayersUI = rebuildPlayersList
    rebuildPlayersList()

    -- CONFIGS
    createSectionLabel(configsPage, "KEYBINDS")
    createKeybind(configsPage, "Menu Key", "MenuKey")

    createSectionLabel(configsPage, "CONFIG FILE")
    local saveStatus = Instance.new("TextLabel")
    saveStatus.Size = UDim2.new(1, 0, 0, 16)
    saveStatus.BackgroundTransparency = 1
    saveStatus.Text = "Auto-save: ON (" .. CONFIG_FILE .. ")"
    saveStatus.TextColor3 = Color3.fromRGB(90, 90, 90)
    saveStatus.TextSize = 10
    saveStatus.Font = Enum.Font.Gotham
    saveStatus.TextXAlignment = Enum.TextXAlignment.Left
    saveStatus.TextTruncate = Enum.TextTruncate.AtEnd
    saveStatus.LayoutOrder = nextOrder(configsPage)
    saveStatus.Parent = configsPage

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, 0, 0, 28)
    saveBtn.BackgroundColor3 = Color3.fromRGB(35, 120, 60)
    saveBtn.BorderSizePixel = 0
    saveBtn.Text = "SAVE NOW"
    saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveBtn.TextSize = 11
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.LayoutOrder = nextOrder(configsPage)
    saveBtn.Parent = configsPage
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 4)
    saveBtn.MouseButton1Click:Connect(function()
        SaveConfig(true)
        saveStatus.Text = "Saved: " .. os.date("%H:%M:%S")
    end)

    local loadBtn = Instance.new("TextButton")
    loadBtn.Size = UDim2.new(1, 0, 0, 28)
    loadBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    loadBtn.BorderSizePixel = 0
    loadBtn.Text = "LOAD"
    loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    loadBtn.TextSize = 11
    loadBtn.Font = Enum.Font.GothamBold
    loadBtn.LayoutOrder = nextOrder(configsPage)
    loadBtn.Parent = configsPage
    Instance.new("UICorner", loadBtn).CornerRadius = UDim.new(0, 4)
    loadBtn.MouseButton1Click:Connect(function()
        LoadConfig()
        saveStatus.Text = "Loaded: " .. os.date("%H:%M:%S") .. " (re-exec for UI refresh)"
    end)

    local unloadBtn = Instance.new("TextButton")
    unloadBtn.Size = UDim2.new(1, 0, 0, 30)
    unloadBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    unloadBtn.BorderSizePixel = 0
    unloadBtn.Text = "UNLOAD"
    unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    unloadBtn.TextSize = 11
    unloadBtn.Font = Enum.Font.GothamBold
    unloadBtn.LayoutOrder = nextOrder(configsPage)
    unloadBtn.Parent = configsPage
    Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 4)
    unloadBtn.MouseButton1Click:Connect(function() unload() end)

    addNav("VISUALS")
    addNav("COMBAT")
    addNav("SKINS")
    addNav("WORLD")
    addNav("MOVEMENT")
    addNav("CONFIGS")

    pages["VISUALS"].Visible = true
    if navButtons["VISUALS"] then
        navButtons["VISUALS"].btn.BackgroundColor3 = Color3.fromRGB(32, 32, 35)
        navButtons["VISUALS"].btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    end

    menuRef = screenGui
end

-- ============================================================
-- UNLOAD
-- ============================================================
unload = function()
    if unloaded then return end
    pcall(function() SaveConfig(true) end)
    unloaded = true
    Config.Enabled = false
    Config.Aimlock = false
    aiming = false
    aimCFrame = nil
    refreshPlayersUI = nil
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    connections = {}
    pcall(function() RunService:UnbindFromRenderStep("AimlockCam") end)
    local players = {}
    for p in pairs(espObjects) do players[#players + 1] = p end
    for _, p in ipairs(players) do removeESP(p) end
    pcall(function() fovCircle:Remove() end)
    pcall(function() deadZoneCircle:Remove() end)
    for p in pairs(chamsMap) do removeChams(p) end
    if menuRef then pcall(function() menuRef:Destroy() end); menuRef = nil end
end

-- ============================================================
-- INIT
-- ============================================================
LoadConfig()
canInstance = pcall(function()
    local t = Instance.new("Frame")
    t:Destroy()
end)
if canInstance then
    local okMenu, errMenu = pcall(createMenu)
    if not okMenu then
        canInstance = false
        pcall(function() warn("[Sveen] Menu error: " .. tostring(errMenu)) end)
    end
else
    pcall(function() warn("[Sveen] Brak capability Plugin: menu/chamsy OFF, ESP+aim dzialaja.") end)
end

for _, player in ipairs(Players:GetPlayers()) do createESP(player) end
track(Players.PlayerAdded:Connect(function(p)
    createESP(p)
    if refreshPlayersUI then pcall(refreshPlayersUI) end
end))
track(Players.PlayerRemoving:Connect(function(p)
    removeESP(p)
    removeChams(p)
    if refreshPlayersUI then pcall(refreshPlayersUI) end
end))

track(UserInputService.InputBegan:Connect(function(input, gp)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbDown = true
        lmbGameplay = not gp
    end
    if gp then return end
    if bindingKey then
        local uitName = input.UserInputType and input.UserInputType.Name or ""
        if uitName:match("^MouseButton") then
            -- klik myszy (MB1/MB2/MMB) - zapisz jako UserInputType
            Config[bindingKey] = input.UserInputType
            RefreshBindLabel(bindingKey)
            bindingKey = nil
            QueueSave()
        elseif input.KeyCode ~= Enum.KeyCode.Unknown then
            if input.KeyCode == Enum.KeyCode.Escape then
                -- ESC anuluje bindowanie
                RefreshBindLabel(bindingKey)
                bindingKey = nil
            else
                Config[bindingKey] = input.KeyCode
                RefreshBindLabel(bindingKey)
                bindingKey = nil
                QueueSave()
            end
        end
        return
    end
    if BindMatches(input, Config.MenuKey) and menuRef then
        menuRef.Enabled = not menuRef.Enabled
    elseif BindMatches(input, Config.AimKey) then
        aiming = true
    elseif input.KeyCode == Enum.KeyCode.Delete then
        unload()
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if BindMatches(input, Config.AimKey) then aiming = false; aimCFrame = nil end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        lmbDown = false
        lmbGameplay = false
        if draggingSlider ~= nil then SaveConfig(true) end
        draggingSlider = nil
        draggingMenu   = false
    end
end))

track(UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    if draggingSlider then
        draggingSlider(input)
    elseif draggingMenu and menuRef then
        local main = menuRef:FindFirstChild("Main", true)
        if main then
            local delta = input.Position - dragStartPos
            main.Position = UDim2.new(
                dragStartPos0.X.Scale, dragStartPos0.X.Offset + delta.X,
                dragStartPos0.Y.Scale, dragStartPos0.Y.Offset + delta.Y
            )
        end
    end
end))

-- ============================================================
-- AIMLOCK CAMERA (hard lock tylko w DeadZone, poza tym smooth)
-- ============================================================
RunService:BindToRenderStep("AimlockCam", Enum.RenderPriority.Camera.Value + 1, function(dt)
    if unloaded then return end
    if not (Config.Aimlock and aiming) then aimCFrame = nil; return end

    local best = getBestAimTarget()
    if not best then aimCFrame = nil; return end

    local camPos = Camera.CFrame.Position
    local lockPart = best.part

    local targetCF = CFrame.lookAt(camPos, lockPart.Position)

    local distFromCenter = distFromCenterOfPart(lockPart)

    -- DeadZone to wewnetrzne kolo w FOV: clamp zeby nigdy nie wyszlo poza FOV
    -- Hard lock TYLKO gdy cel jest juz w srodku deadzone.
    -- Pierscien (deadZone < dist <= FOV) to zawsze smooth.
    local dead = math.clamp(Config.DeadZone, 0, Config.AimFOV)
    if dead > 0 and distFromCenter <= dead then
        aimCFrame = targetCF
        Camera.CFrame = targetCF
    else
        -- Smooth liczony od AKTUALNEJ kamery (a nie od starego aimCFrame),
        -- zeby nie kasowac ruchu myszki i zeby nie wskakiwal po 1 klatce w deadzone.
        -- WIEKSZY Smoothness = WOLNIEJ (bardziej smooth). 1 = szybko, 100 = bardzo wolno.
        local fpsScale = math.clamp(dt * 60, 0.5, 2)
        local s = math.clamp(Config.AimSmoothness or 40, 1, 100)
        local alpha = (0.5 / s) * fpsScale
        alpha = math.clamp(alpha, 0.004, 0.35)

        local cur = Camera.CFrame
        local lerped = cur:Lerp(targetCF, alpha)
        lerped = CFrame.new(camPos) * (lerped - lerped.Position)
        aimCFrame = lerped
        Camera.CFrame = lerped
    end
end)

-- ============================================================
-- RENDER LOOP
-- ============================================================
track(RunService.RenderStepped:Connect(function()
    if unloaded then return end
    if configDirty and os.clock() - lastSave >= 3 then
        SaveConfig(true)
    end
    for player, esp in pairs(espObjects) do
        if player.Parent then updateESP(player, esp) else removeESP(player) end
        updateChams(player)
    end
    updateSkipReload()
    updateRapidFire()
    if rapidLabel and rapidLabel.Parent and os.clock() - lastRapidUi > 0.2 then
        lastRapidUi = os.clock()
        rapidLabel.Text = "Rapid: " .. rapidStatus .. " | strzaly: " .. tostring(rapidShots)
    end
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    if Config.Aimlock then
        fovCircle.Position = center
        fovCircle.Radius   = Config.AimFOV
        fovCircle.Visible  = true
    else
        fovCircle.Visible = false
    end
    
    if Config.Aimlock and Config.DeadZone > 0 then
        deadZoneCircle.Position = center
        deadZoneCircle.Radius   = Config.DeadZone
        deadZoneCircle.Visible  = true
    else
        deadZoneCircle.Visible = false
    end
end))