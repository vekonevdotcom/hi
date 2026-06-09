--============================================================
--  Prison Life | @nklays  (MOBILE VERSION)
--============================================================

-- CLEANUP
if _G.PH5M then
    for _, c in pairs(_G.PH5M.connections or {}) do pcall(function() c:Disconnect() end) end
end
if _G.AimbotFOVCircleM then pcall(function() _G.AimbotFOVCircleM:Remove() end) end
if _G.PH5M and _G.PH5M.espDrwCache then
    for _, d in pairs(_G.PH5M.espDrwCache) do
        pcall(function() for _, l in ipairs(d.box) do l:Remove() end end)
        pcall(function() d.head:Remove() end)
        pcall(function() d.tracer:Remove() end)
        pcall(function() d.name:Remove() end)
        pcall(function() d.info:Remove() end)
    end
end
for _, v in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if v.Name == "PH5M_Main" or v.Name == "PH5M_Lock" or v.Name == "PH5M_HUD"
       or v.Name == "PH5M_KillFlash" or v.Name == "PH5M_AimBtn" or v.Name == "PH5M_Toggle" then
        v:Destroy()
    end
end
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
    if p.Character then
        for _, c in ipairs(p.Character:GetDescendants()) do
            if c.Name == "PH5M_HL" or c.Name == "PH5M_BB" then c:Destroy() end
        end
    end
end

_G.PH5M = { connections = {}, espDrwCache = {} }
local conn = _G.PH5M.connections

--============================================================
-- SERVICES
--============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--============================================================
-- SETTINGS
--============================================================
local S = {
    AimbotOn = true,
    AimPart = "HumanoidRootPart",
    AimMode = "Instant",
    AimSmooth = 0.15,
    AimTeam = "Guards",
    FOVRadius = 150,
    FOVVisible = true,
    FOVColorMode = "Rainbow",
    FOVCustomHex = "#FF0000",
    AimTrigger = "RightHalf",   -- "RightHalf" or "AimButton"

    ESPOn = true,
    ESPTeam = "All",
    ESPStyle = "Highlight",
    ESPNames = true,
    ESPHealth = true,
    ESPDist = true,
    ESPTracers = false,
    ESPTracerOrigin = "Bottom",
    ESPFillAlpha = 0.65,

    HitmarkOn = true,
    HitColor = "#FFFFFF",
    HurtColor = "#FF3333",
    KillColor = "#FF0000",
    ShowFPS = true,
    ShowPing = true,
    ShowSpeed = true,
}

local LOCATIONS = {
    CrimBase = Vector3.new(-940, 94, 2060),
    Prison = Vector3.new(535, 98, 2567),
}

--============================================================
-- STATE
--============================================================
local holding = false
local lockedTarget = nil
local lastShotTime = 0
local SHOT_WINDOW = 0.4
local hue = 0
local playerList = {}
local espHLCache = {}
local espDrwCache = _G.PH5M.espDrwCache
local healthPrev = {}
local lp_hrp = nil
local fpsBuffer = {}
local currentFPS = 0

-- Mobile-specific state
local fovCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
local fovDragPos = nil       -- saved position
local activeTouches = {}     -- track which inputs are which
local guiVisible = true

--============================================================
-- UTILITIES
--============================================================
local function hexToC3(hex)
    hex = hex:gsub("#", "")
    return Color3.fromRGB(
        tonumber(hex:sub(1, 2), 16) or 255,
        tonumber(hex:sub(3, 4), 16) or 0,
        tonumber(hex:sub(5, 6), 16) or 0
    )
end

local function teamMatch(plr, filter)
    if filter == "All" then return true end
    local ok, t = pcall(function() return plr.Team end)
    return ok and t and t.Name == filter
end

local function shouldAim(plr)
    if S.AimTeam == "All" then
        local ok, t = pcall(function() return plr.Team end)
        return not (ok and t and t == LP.Team)
    end
    return teamMatch(plr, S.AimTeam)
end

local function getTeamColor(plr)
    local ok, c = pcall(function() return plr.TeamColor.Color end)
    return ok and c or Color3.fromRGB(200, 200, 200)
end

local function safeGui(name)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.DisplayOrder = 10000
    g.IgnoreGuiInset = true
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    if not pcall(function() g.Parent = game:GetService("CoreGui") end) then
        g.Parent = LP:WaitForChild("PlayerGui")
    end
    return g
end

--============================================================
-- DRAG HELPER FOR MOBILE (touch & mouse)
--============================================================
local function makeDraggable(frame, dragHandle)
    dragHandle = dragHandle or frame
    local dragging = false
    local dragInput, dragStart, startPos

    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
           or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
           or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

--============================================================
-- PLAYER LIST
--============================================================
local function refreshList()
    playerList = {}
    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= LP then table.insert(playerList, v) end
    end
end
refreshList()
conn.plrAdd = Players.PlayerAdded:Connect(function(p)
    if p ~= LP then table.insert(playerList, p) end
end)
conn.plrRem = Players.PlayerRemoving:Connect(function(p)
    for i, v in ipairs(playerList) do
        if v == p then table.remove(playerList, i) break end
    end
    local hd = espHLCache[p]
    if hd then
        if hd.hl and hd.hl.Parent then hd.hl:Destroy() end
        if hd.bb and hd.bb.Parent then hd.bb:Destroy() end
        espHLCache[p] = nil
    end
    local dd = espDrwCache[p]
    if dd then
        for _, l in ipairs(dd.box) do pcall(function() l:Remove() end) end
        pcall(function() dd.head:Remove() end)
        pcall(function() dd.tracer:Remove() end)
        pcall(function() dd.name:Remove() end)
        pcall(function() dd.info:Remove() end)
        espDrwCache[p] = nil
    end
    healthPrev[p] = nil
end)

local pollT = 0
conn.poll = RunService.Heartbeat:Connect(function(dt)
    pollT += dt
    if pollT >= 2 then pollT = 0; refreshList() end
end)

local function updHRP(ch)
    lp_hrp = ch and ch:FindFirstChild("HumanoidRootPart") or nil
end
if LP.Character then updHRP(LP.Character) end
conn.charAdd = LP.CharacterAdded:Connect(function(ch)
    ch:WaitForChild("HumanoidRootPart"); updHRP(ch)
end)

--============================================================
-- COLORS
--============================================================
local C = {
    bg = Color3.fromRGB(15, 15, 20),
    side = Color3.fromRGB(12, 12, 16),
    card = Color3.fromRGB(24, 24, 32),
    accent = Color3.fromRGB(108, 92, 231),
    text = Color3.fromRGB(220, 220, 230),
    dim = Color3.fromRGB(110, 110, 130),
    green = Color3.fromRGB(46, 204, 113),
    red = Color3.fromRGB(231, 76, 60),
    border = Color3.fromRGB(40, 40, 52),
    title = Color3.fromRGB(10, 10, 14),
}

--============================================================
-- MAIN GUI (mobile-sized)
--============================================================
local gui = safeGui("PH5M_Main")

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.new(0, 440, 0, 360)
main.Position = UDim2.new(0.5, -220, 0.5, -180)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local ms = Instance.new("UIStroke", main); ms.Thickness = 1; ms.Color = C.border

-- TITLE BAR (drag handle)
local tBar = Instance.new("Frame")
tBar.Size = UDim2.new(1, 0, 0, 44)
tBar.BackgroundColor3 = C.title
tBar.BorderSizePixel = 0
tBar.ClipsDescendants = true
tBar.Active = true
tBar.Parent = main
Instance.new("UICorner", tBar).CornerRadius = UDim.new(0, 12)

local tBarBot = Instance.new("Frame")
tBarBot.Size = UDim2.new(1, 0, 0, 12)
tBarBot.Position = UDim2.new(0, 0, 1, -12)
tBarBot.BackgroundColor3 = C.title
tBarBot.BorderSizePixel = 0
tBarBot.Parent = tBar

local stripe = Instance.new("Frame")
stripe.Size = UDim2.new(0, 3, 0, 22)
stripe.Position = UDim2.new(0, 14, 0.5, -11)
stripe.BackgroundColor3 = C.accent
stripe.BorderSizePixel = 0
stripe.Parent = tBar
Instance.new("UICorner", stripe).CornerRadius = UDim.new(0, 2)

local tLabel = Instance.new("TextLabel")
tLabel.Size = UDim2.new(1, -150, 1, 0)
tLabel.Position = UDim2.new(0, 24, 0, 0)
tLabel.BackgroundTransparency = 1
tLabel.Text = "PRISON LIFE | @nklays - MOBILE"
tLabel.TextColor3 = C.text
tLabel.TextSize = 13
tLabel.Font = Enum.Font.GothamBlack
tLabel.TextXAlignment = Enum.TextXAlignment.Left
tLabel.Parent = tBar

-- Buttons must be on top so they get touch events
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 36, 0, 32)
closeBtn.Position = UDim2.new(1, -42, 0, 6)
closeBtn.BackgroundColor3 = C.red
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 100
closeBtn.Parent = main
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 36, 0, 32)
minBtn.Position = UDim2.new(1, -84, 0, 6)
minBtn.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
minBtn.Text = "-"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.TextSize = 22
minBtn.Font = Enum.Font.GothamBold
minBtn.BorderSizePixel = 0
minBtn.ZIndex = 100
minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- MAKE MAIN PANEL DRAGGABLE via title bar
makeDraggable(main, tBar)

-- MINI BUTTON (toggles main)
local miniGui = safeGui("PH5M_Toggle")
local miniBtn = Instance.new("TextButton")
miniBtn.Size = UDim2.new(0, 56, 0, 56)
miniBtn.Position = UDim2.new(0, 10, 0, 100)
miniBtn.BackgroundColor3 = C.accent
miniBtn.Text = "PL"
miniBtn.TextSize = 18
miniBtn.TextColor3 = Color3.new(1, 1, 1)
miniBtn.Font = Enum.Font.GothamBlack
miniBtn.BorderSizePixel = 0
miniBtn.Visible = false
miniBtn.Parent = miniGui
Instance.new("UICorner", miniBtn).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", miniBtn).Color = C.border
makeDraggable(miniBtn)

closeBtn.MouseButton1Click:Connect(function()
    for plr, d in pairs(espDrwCache) do
        for _, l in ipairs(d.box) do pcall(function() l:Remove() end) end
        pcall(function() d.head:Remove() end)
        pcall(function() d.tracer:Remove() end)
        pcall(function() d.name:Remove() end)
        pcall(function() d.info:Remove() end)
    end
    espDrwCache = {}
    pcall(function() _G.AimbotFOVCircleM:Remove() end)
    for _, c in pairs(conn) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
    miniGui:Destroy()
    for _, v in ipairs(game:GetService("CoreGui"):GetChildren()) do
        if v.Name == "PH5M_Lock" or v.Name == "PH5M_HUD" or v.Name == "PH5M_KillFlash" or v.Name == "PH5M_AimBtn" then
            v:Destroy()
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            for _, ch in ipairs(p.Character:GetDescendants()) do
                if ch.Name == "PH5M_HL" or ch.Name == "PH5M_BB" then ch:Destroy() end
            end
        end
    end
end)

minBtn.MouseButton1Click:Connect(function() main.Visible = false; miniBtn.Visible = true end)
miniBtn.MouseButton1Click:Connect(function() main.Visible = true; miniBtn.Visible = false end)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 110, 1, -44)
sidebar.Position = UDim2.new(0, 0, 0, 44)
sidebar.BackgroundColor3 = C.side
sidebar.BorderSizePixel = 0
sidebar.Parent = main

local sLayout = Instance.new("UIListLayout", sidebar)
sLayout.Padding = UDim.new(0, 3)
sLayout.SortOrder = Enum.SortOrder.LayoutOrder
local sPad = Instance.new("UIPadding", sidebar)
sPad.PaddingTop = UDim.new(0, 8)
sPad.PaddingLeft = UDim.new(0, 6)
sPad.PaddingRight = UDim.new(0, 6)

local div = Instance.new("Frame")
div.Size = UDim2.new(0, 1, 1, -44)
div.Position = UDim2.new(0, 110, 0, 44)
div.BackgroundColor3 = C.border
div.BorderSizePixel = 0
div.Parent = main

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -110, 1, -44)
content.Position = UDim2.new(0, 110, 0, 44)
content.BackgroundColor3 = C.bg
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.Parent = main

--============================================================
-- TAB SYSTEM
--============================================================
local pages = {}
local tabBtns = {}
local activeTab = nil
local tabNames = { "Aimbot", "ESP", "HUD", "Teleport", "Settings" }
local tabDots = {
    Aimbot = C.red,
    ESP = Color3.fromRGB(0, 170, 255),
    HUD = C.green,
    Teleport = Color3.fromRGB(255, 165, 0),
    Settings = C.dim,
}

local function mkPage(name)
    local sc = Instance.new("ScrollingFrame")
    sc.Name = name
    sc.Size = UDim2.new(1, -12, 1, -12)
    sc.Position = UDim2.new(0, 6, 0, 6)
    sc.BackgroundTransparency = 1
    sc.ScrollBarThickness = 4
    sc.ScrollBarImageColor3 = C.accent
    sc.BorderSizePixel = 0
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.ScrollingDirection = Enum.ScrollingDirection.Y
    sc.Visible = false
    sc.Parent = content
    local l = Instance.new("UIListLayout", sc)
    l.Padding = UDim.new(0, 6)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    Instance.new("UIPadding", sc).PaddingTop = UDim.new(0, 2)
    pages[name] = sc
    return sc
end

local function switchTab(name)
    if activeTab == name then return end
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        if n == name then
            b.BackgroundColor3 = C.accent
            b.BackgroundTransparency = 0
            b.TextColor3 = Color3.new(1, 1, 1)
        else
            b.BackgroundTransparency = 1
            b.TextColor3 = C.dim
        end
    end
    activeTab = name
end

for i, name in ipairs(tabNames) do
    mkPage(name)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundTransparency = 1
    btn.BackgroundColor3 = C.accent
    btn.Text = "   " .. name
    btn.TextColor3 = C.dim
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.LayoutOrder = i
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 6, 0, 6)
    dot.Position = UDim2.new(0, 6, 0.5, -3)
    dot.BackgroundColor3 = tabDots[name]
    dot.BorderSizePixel = 0
    dot.Parent = btn
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
    tabBtns[name] = btn
end

--============================================================
-- UI COMPONENTS (bigger for touch)
--============================================================
local function mkCard(par, h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, h or 44)
    f.BackgroundColor3 = C.card
    f.BorderSizePixel = 0
    f.Parent = par
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", f); s.Color = C.border; s.Transparency = 0.5
    return f
end

local function mkLabel(par, txt, pos)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(0.55, 0, 1, 0)
    l.Position = pos or UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1
    l.Text = txt
    l.TextColor3 = C.text
    l.TextSize = 13
    l.Font = Enum.Font.GothamSemibold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = par
    return l
end

local function mkSection(par, txt)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, 0, 0, 22)
    l.BackgroundTransparency = 1
    l.Text = "  " .. txt:upper()
    l.TextColor3 = C.dim
    l.TextSize = 10
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = par
end

local function mkToggle(par, label, def, cb)
    local card = mkCard(par, 44)
    mkLabel(card, label)
    local bg = Instance.new("TextButton")
    bg.Size = UDim2.new(0, 50, 0, 28)
    bg.Position = UDim2.new(1, -62, 0.5, -14)
    bg.BackgroundColor3 = def and C.green or Color3.fromRGB(55, 55, 65)
    bg.Text = ""
    bg.BorderSizePixel = 0
    bg.Parent = card
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)
    local cir = Instance.new("Frame")
    cir.Size = UDim2.new(0, 22, 0, 22)
    cir.Position = def and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11)
    cir.BackgroundColor3 = Color3.new(1, 1, 1)
    cir.BorderSizePixel = 0
    cir.Parent = bg
    Instance.new("UICorner", cir).CornerRadius = UDim.new(1, 0)
    local st = def
    bg.MouseButton1Click:Connect(function()
        st = not st
        TweenService:Create(bg, TweenInfo.new(0.15), { BackgroundColor3 = st and C.green or Color3.fromRGB(55, 55, 65) }):Play()
        TweenService:Create(cir, TweenInfo.new(0.15), { Position = st and UDim2.new(1, -25, 0.5, -11) or UDim2.new(0, 3, 0.5, -11) }):Play()
        cb(st)
    end)
    return card
end

local function mkDropdown(par, label, opts, def, cb)
    local card = mkCard(par, 44)
    mkLabel(card, label)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 130, 0, 30)
    btn.Position = UDim2.new(1, -142, 0.5, -15)
    btn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    btn.Text = def
    btn.TextColor3 = C.accent
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent = card
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local idx = 1
    for i, v in ipairs(opts) do if v == def then idx = i end end
    btn.MouseButton1Click:Connect(function()
        idx = idx % #opts + 1
        btn.Text = opts[idx]
        cb(opts[idx])
    end)
    return card, btn
end

local function mkSlider(par, label, mn, mx, def, step, cb)
    local card = mkCard(par, 56)
    local lbl = mkLabel(card, label .. ": " .. def, UDim2.new(0, 12, 0, 0))
    lbl.Size = UDim2.new(1, -24, 0, 22)
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -24, 0, 8)
    track.Position = UDim2.new(0, 12, 0, 34)
    track.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    track.BorderSizePixel = 0
    track.Parent = card
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((def - mn) / (mx - mn), 0, 1, 0)
    fill.BackgroundColor3 = C.accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 22, 0, 22)
    knob.Position = UDim2.new((def - mn) / (mx - mn), -11, 0.5, -11)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.Text = ""
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local drag = false
    knob.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = true end
    end)
    conn["sEnd_" .. label] = UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
    conn["sMove_" .. label] = UIS.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local rel = math.clamp((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            local val = math.clamp(math.floor((mn + (mx - mn) * rel) / step + 0.5) * step, mn, mx)
            local pct = (val - mn) / (mx - mn)
            fill.Size = UDim2.new(pct, 0, 1, 0)
            knob.Position = UDim2.new(pct, -11, 0.5, -11)
            lbl.Text = label .. ": " .. val
            cb(val)
        end
    end)
    return card
end

local function mkTextInput(par, label, def, cb)
    local card = mkCard(par, 44)
    mkLabel(card, label)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0, 120, 0, 30)
    box.Position = UDim2.new(1, -132, 0.5, -15)
    box.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    box.Text = def
    box.TextColor3 = C.accent
    box.PlaceholderText = "#HEX"
    box.PlaceholderColor3 = C.dim
    box.TextSize = 12
    box.Font = Enum.Font.GothamBold
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Parent = card
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    box.FocusLost:Connect(function() cb(box.Text) end)
    return card
end

local function mkButton(par, label, col, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 42)
    b.BackgroundColor3 = col
    b.Text = label
    b.TextColor3 = Color3.new(1, 1, 1)
    b.TextSize = 14
    b.Font = Enum.Font.GothamBold
    b.BorderSizePixel = 0
    b.Parent = par
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    b.MouseButton1Click:Connect(cb)
    return b
end

--============================================================
-- AIMBOT TAB
--============================================================
local ap = pages["Aimbot"]
mkSection(ap, "General")
mkToggle(ap, "Aimbot Enabled", S.AimbotOn, function(v) S.AimbotOn = v end)
mkDropdown(ap, "Aim Part", { "HumanoidRootPart", "Head" }, S.AimPart, function(v) S.AimPart = v end)
mkDropdown(ap, "Aim Mode", { "Instant", "Smooth" }, S.AimMode, function(v) S.AimMode = v end)
mkSlider(ap, "Smoothing", 1, 100, math.floor(S.AimSmooth * 100), 1, function(v) S.AimSmooth = v / 100 end)
mkSection(ap, "Targeting")
mkDropdown(ap, "Target Team", { "Guards", "Criminals", "Inmates", "All" }, S.AimTeam, function(v) S.AimTeam = v end)
mkSection(ap, "Trigger Mode")
mkDropdown(ap, "Trigger", { "RightHalf", "AimButton" }, S.AimTrigger, function(v) S.AimTrigger = v end)
mkSection(ap, "FOV Circle")
mkToggle(ap, "Show Circle", S.FOVVisible, function(v) S.FOVVisible = v end)
mkSlider(ap, "Circle Size", 50, 500, S.FOVRadius, 10, function(v) S.FOVRadius = v end)
mkDropdown(ap, "Circle Color", { "Rainbow", "Custom" }, S.FOVColorMode, function(v) S.FOVColorMode = v end)
mkTextInput(ap, "Custom Hex", S.FOVCustomHex, function(v) S.FOVCustomHex = v end)
mkButton(ap, "Reset FOV to Screen Center", C.accent, function()
    fovCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end)

--============================================================
-- ESP TAB
--============================================================
local ep = pages["ESP"]

local function destroyAllDrawings()
    for plr, d in pairs(espDrwCache) do
        for _, l in ipairs(d.box) do pcall(function() l:Remove() end) end
        pcall(function() d.head:Remove() end)
        pcall(function() d.tracer:Remove() end)
        pcall(function() d.name:Remove() end)
        pcall(function() d.info:Remove() end)
    end
    espDrwCache = {}
    _G.PH5M.espDrwCache = espDrwCache
end

local function destroyAllHighlights()
    for _, d in pairs(espHLCache) do
        if d.hl and d.hl.Parent then d.hl:Destroy() end
        if d.bb and d.bb.Parent then d.bb:Destroy() end
    end
    espHLCache = {}
end

mkSection(ep, "General")
mkToggle(ep, "ESP Enabled", S.ESPOn, function(v)
    S.ESPOn = v
    if not v then destroyAllDrawings(); destroyAllHighlights() end
end)
mkDropdown(ep, "Show Team", { "All", "Guards", "Criminals", "Inmates" }, S.ESPTeam, function(v)
    S.ESPTeam = v
    destroyAllDrawings(); destroyAllHighlights()
end)
mkSection(ep, "Style")
mkDropdown(ep, "ESP Style", { "Highlight", "2D Box", "Head Only" }, S.ESPStyle, function(v)
    S.ESPStyle = v
    destroyAllDrawings(); destroyAllHighlights()
end)
mkSection(ep, "Info Labels")
mkToggle(ep, "Show Names", S.ESPNames, function(v) S.ESPNames = v end)
mkToggle(ep, "Show Health", S.ESPHealth, function(v) S.ESPHealth = v end)
mkToggle(ep, "Show Distance", S.ESPDist, function(v) S.ESPDist = v end)
mkSection(ep, "Tracers")
mkToggle(ep, "Tracers", S.ESPTracers, function(v) S.ESPTracers = v end)
mkDropdown(ep, "Tracer Origin", { "Bottom", "Center", "Upper" }, S.ESPTracerOrigin, function(v) S.ESPTracerOrigin = v end)
mkSection(ep, "Appearance")
mkSlider(ep, "Fill Transparency", 0, 100, math.floor(S.ESPFillAlpha * 100), 5, function(v)
    S.ESPFillAlpha = v / 100
    for _, d in pairs(espHLCache) do
        if d.hl then d.hl.FillTransparency = v / 100 end
    end
end)

--============================================================
-- HUD TAB
--============================================================
local hp = pages["HUD"]
mkSection(hp, "Display")
mkToggle(hp, "Show FPS", S.ShowFPS, function(v) S.ShowFPS = v end)
mkToggle(hp, "Show Ping", S.ShowPing, function(v) S.ShowPing = v end)
mkToggle(hp, "Show Speed", S.ShowSpeed, function(v) S.ShowSpeed = v end)
mkSection(hp, "Hitmarkers")
mkToggle(hp, "Hitmarkers Enabled", S.HitmarkOn, function(v) S.HitmarkOn = v end)
mkTextInput(hp, "Hit Color", S.HitColor, function(v) S.HitColor = v end)
mkTextInput(hp, "Hurt Color", S.HurtColor, function(v) S.HurtColor = v end)
mkTextInput(hp, "Kill Color", S.KillColor, function(v) S.KillColor = v end)

--============================================================
-- TELEPORT TAB
--============================================================
local tp = pages["Teleport"]
mkSection(tp, "Locations")
mkButton(tp, "Criminal Base", Color3.fromRGB(170, 50, 50), function()
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        LP.Character.HumanoidRootPart.CFrame = CFrame.new(LOCATIONS.CrimBase)
    end
end)
mkButton(tp, "Prison Spawn", Color3.fromRGB(50, 110, 170), function()
    if LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") then
        LP.Character.HumanoidRootPart.CFrame = CFrame.new(LOCATIONS.Prison)
    end
end)

--============================================================
-- SETTINGS TAB
--============================================================
local spp = pages["Settings"]
mkSection(spp, "Configs")

local cfgCard = mkCard(spp, 44)
mkLabel(cfgCard, "Config Name")
local cfgBox = Instance.new("TextBox")
cfgBox.Size = UDim2.new(0, 120, 0, 30)
cfgBox.Position = UDim2.new(1, -132, 0.5, -15)
cfgBox.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
cfgBox.Text = "default"
cfgBox.TextColor3 = C.accent
cfgBox.TextSize = 12
cfgBox.Font = Enum.Font.GothamBold
cfgBox.BorderSizePixel = 0
cfgBox.ClearTextOnFocus = false
cfgBox.Parent = cfgCard
Instance.new("UICorner", cfgBox).CornerRadius = UDim.new(0, 6)

local cfgStatus = Instance.new("TextLabel")
cfgStatus.Size = UDim2.new(1, 0, 0, 22)
cfgStatus.BackgroundTransparency = 1
cfgStatus.Text = ""
cfgStatus.TextColor3 = C.green
cfgStatus.TextSize = 12
cfgStatus.Font = Enum.Font.GothamSemibold
cfgStatus.Parent = spp

local CONFIG_DIR = "PrisonHubMobile"
local function ensureDir() pcall(function() if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end end) end

mkButton(spp, "Save Config", C.accent, function()
    local name = cfgBox.Text; if name == "" then return end; ensureDir()
    local ok, err = pcall(function() writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(S)) end)
    cfgStatus.Text = ok and ("Saved: " .. name) or ("Error: " .. (err or "?")); cfgStatus.TextColor3 = ok and C.green or C.red
end)
mkButton(spp, "Load Config", Color3.fromRGB(50, 130, 200), function()
    local name = cfgBox.Text; if name == "" then return end
    local ok, err = pcall(function()
        local data = HttpService:JSONDecode(readfile(CONFIG_DIR .. "/" .. name .. ".json"))
        for k, v in pairs(data) do S[k] = v end
    end)
    cfgStatus.Text = ok and ("Loaded: " .. name) or ("Error: " .. (err or "not found")); cfgStatus.TextColor3 = ok and C.green or C.red
end)
mkButton(spp, "Delete Config", C.red, function()
    local name = cfgBox.Text; if name == "" then return end
    local ok, err = pcall(function() delfile(CONFIG_DIR .. "/" .. name .. ".json") end)
    cfgStatus.Text = ok and ("Deleted: " .. name) or ("Error: " .. (err or "?")); cfgStatus.TextColor3 = ok and C.green or C.red
end)
mkSection(spp, "Other")
mkButton(spp, "Rejoin Server", Color3.fromRGB(180, 130, 0), function()
    pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end)
end)

switchTab("Aimbot")

--============================================================
-- FOV CIRCLE
--============================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Radius = S.FOVRadius
fovCircle.Filled = false
fovCircle.Visible = S.FOVVisible
fovCircle.Transparency = 0.1
fovCircle.NumSides = 64
fovCircle.Thickness = 1.5
fovCircle.Color = Color3.new(1, 1, 1)
_G.AimbotFOVCircleM = fovCircle

--============================================================
-- FOV DRAGGABLE HANDLE (invisible touch frame over the circle)
--============================================================
local fovHandleGui = safeGui("PH5M_FOVHandle")
fovHandleGui.Name = "PH5M_FOVHandle"

local fovHandle = Instance.new("Frame")
fovHandle.Name = "FOVHandle"
fovHandle.Size = UDim2.new(0, S.FOVRadius * 2, 0, S.FOVRadius * 2)
fovHandle.Position = UDim2.new(0, fovCenter.X - S.FOVRadius, 0, fovCenter.Y - S.FOVRadius)
fovHandle.BackgroundTransparency = 1
fovHandle.Active = false   -- by default does NOT block touches
fovHandle.Parent = fovHandleGui

-- Long-press to drag the FOV circle:
-- Touch & hold for 0.5s on the FOV handle → enters drag mode
local fovDragging = false
local pressStart = 0
local pressInput = nil
local pressX, pressY = 0, 0

local function setHandleActive(active)
    fovHandle.Active = active   -- when active, swallows touches
end

-- Small "FOV move" button in the corner to toggle FOV drag mode
local fovMoveBtn = Instance.new("TextButton")
fovMoveBtn.Size = UDim2.new(0, 70, 0, 32)
fovMoveBtn.Position = UDim2.new(0, 10, 0, 165)
fovMoveBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
fovMoveBtn.Text = "MOVE FOV"
fovMoveBtn.TextColor3 = Color3.new(1, 1, 1)
fovMoveBtn.TextSize = 11
fovMoveBtn.Font = Enum.Font.GothamBold
fovMoveBtn.BorderSizePixel = 0
fovMoveBtn.Parent = miniGui
Instance.new("UICorner", fovMoveBtn).CornerRadius = UDim.new(0, 6)

local fovMoveActive = false
fovMoveBtn.MouseButton1Click:Connect(function()
    fovMoveActive = not fovMoveActive
    if fovMoveActive then
        fovMoveBtn.BackgroundColor3 = C.green
        fovMoveBtn.Text = "DONE"
        setHandleActive(true)
    else
        fovMoveBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
        fovMoveBtn.Text = "MOVE FOV"
        setHandleActive(false)
    end
end)

-- Drag the FOV handle when active
do
    local dragging = false
    local lastInput
    local startPos
    local dragStart

    fovHandle.InputBegan:Connect(function(input)
        if not fovMoveActive then return end
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = fovCenter
        end
    end)

    fovHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseMovement then
            lastInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input == lastInput then
            local delta = input.Position - dragStart
            fovCenter = Vector2.new(startPos.X + delta.X, startPos.Y + delta.Y)
            fovHandle.Position = UDim2.new(0, fovCenter.X - S.FOVRadius, 0, fovCenter.Y - S.FOVRadius)
        end
    end)

    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
           or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

--============================================================
-- AIM BUTTON (alternative trigger)
--============================================================
local aimBtnGui = safeGui("PH5M_AimBtn")
local aimBtn = Instance.new("TextButton")
aimBtn.Size = UDim2.new(0, 80, 0, 80)
aimBtn.Position = UDim2.new(1, -100, 1, -200)
aimBtn.BackgroundColor3 = C.accent
aimBtn.BackgroundTransparency = 0.3
aimBtn.Text = "AIM"
aimBtn.TextColor3 = Color3.new(1, 1, 1)
aimBtn.TextSize = 16
aimBtn.Font = Enum.Font.GothamBlack
aimBtn.BorderSizePixel = 0
aimBtn.Parent = aimBtnGui
Instance.new("UICorner", aimBtn).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", aimBtnGui:FindFirstChildOfClass("TextButton")).Color = Color3.new(1, 1, 1)
makeDraggable(aimBtn)

local aimBtnHolding = false
aimBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
       or input.UserInputType == Enum.UserInputType.MouseButton1 then
        aimBtnHolding = true
        lastShotTime = tick()
        aimBtn.BackgroundTransparency = 0.1
    end
end)
aimBtn.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
       or input.UserInputType == Enum.UserInputType.MouseButton1 then
        aimBtnHolding = false
        aimBtn.BackgroundTransparency = 0.3
    end
end)

--============================================================
-- RIGHT-HALF SCREEN TOUCH TRIGGER
--============================================================
-- Detects when a touch starts in the right half of the screen
-- AND it's NOT on top of any UI element (so jumping/camera still works)
local rightHalfTouches = {}

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end   -- ignore touches that hit UI
    if input.UserInputType ~= Enum.UserInputType.Touch then return end

    local pos = input.Position
    if pos.X > Camera.ViewportSize.X / 2 then
        rightHalfTouches[input] = true
        lastShotTime = tick()
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch then
        rightHalfTouches[input] = nil
    end
end)

local function isRightHalfHolding()
    for _ in pairs(rightHalfTouches) do return true end
    return false
end

--============================================================
-- LOCK-ON DISPLAY
--============================================================
local lockGui = safeGui("PH5M_Lock")
local lockBg = Instance.new("Frame")
lockBg.Size = UDim2.new(0, 240, 0, 38)
lockBg.Position = UDim2.new(0.5, -120, 0.9, 0)
lockBg.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
lockBg.BackgroundTransparency = 0.25
lockBg.BorderSizePixel = 0
lockBg.Visible = false
lockBg.Parent = lockGui
Instance.new("UICorner", lockBg).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", lockBg).Color = C.border

local lockTxt = Instance.new("TextLabel")
lockTxt.Size = UDim2.new(1, 0, 1, 0)
lockTxt.BackgroundTransparency = 1
lockTxt.TextColor3 = Color3.new(1, 1, 1)
lockTxt.TextSize = 14
lockTxt.Font = Enum.Font.GothamBold
lockTxt.Text = ""
lockTxt.Parent = lockBg

--============================================================
-- HUD DISPLAY
--============================================================
local hudGui = safeGui("PH5M_HUD")
local hudFrame = Instance.new("Frame")
hudFrame.Size = UDim2.new(0, 160, 0, 60)
hudFrame.Position = UDim2.new(0, 8, 0, 8)
hudFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
hudFrame.BackgroundTransparency = 0.4
hudFrame.BorderSizePixel = 0
hudFrame.Parent = hudGui
Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 6)

local hudLabel = Instance.new("TextLabel")
hudLabel.Size = UDim2.new(1, -12, 1, 0)
hudLabel.Position = UDim2.new(0, 6, 0, 0)
hudLabel.BackgroundTransparency = 1
hudLabel.TextColor3 = C.text
hudLabel.TextSize = 12
hudLabel.Font = Enum.Font.GothamSemibold
hudLabel.TextXAlignment = Enum.TextXAlignment.Left
hudLabel.TextYAlignment = Enum.TextYAlignment.Center
hudLabel.Text = ""
hudLabel.Parent = hudFrame

--============================================================
-- KILL FLASH
--============================================================
local flashGui = safeGui("PH5M_KillFlash")
flashGui.DisplayOrder = 99999
local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.new(1, 0, 1, 0)
flashFrame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.Parent = flashGui

--============================================================
-- HITMARKER SYSTEM
--============================================================
local hitLines = {}
for i = 1, 4 do
    local l = Drawing.new("Line")
    l.Visible = false
    l.Thickness = 2
    l.Color = Color3.new(1, 1, 1)
    hitLines[i] = l
end

local function showHitMark()
    if not S.HitmarkOn then return end
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    local off, len = 6, 12
    local col = hexToC3(S.HitColor)
    local pts = {
        { Vector2.new(cx - off, cy - off), Vector2.new(cx - off - len, cy - off - len) },
        { Vector2.new(cx + off, cy - off), Vector2.new(cx + off + len, cy - off - len) },
        { Vector2.new(cx - off, cy + off), Vector2.new(cx - off - len, cy + off + len) },
        { Vector2.new(cx + off, cy + off), Vector2.new(cx + off + len, cy + off + len) },
    }
    for i, l in ipairs(hitLines) do
        l.From = pts[i][1]; l.To = pts[i][2]; l.Color = col; l.Visible = true; l.Transparency = 1
    end
    task.spawn(function()
        local t0 = tick()
        while tick() - t0 < 0.25 do
            local a = 1 - (tick() - t0) / 0.25
            for _, l in ipairs(hitLines) do l.Transparency = a end
            task.wait()
        end
        for _, l in ipairs(hitLines) do l.Visible = false end
    end)
end

local function showHurtArc(angle)
    if not S.HitmarkOn then return end
    local cx = Camera.ViewportSize.X / 2
    local cy = Camera.ViewportSize.Y / 2
    local radius, span, segs = 90, math.pi / 2, 10
    local col = hexToC3(S.HurtColor)
    local lines = {}
    for i = 1, segs do
        local a1 = angle - span / 2 + (i - 1) * span / segs
        local a2 = angle - span / 2 + i * span / segs
        local l = Drawing.new("Line")
        l.From = Vector2.new(cx + math.sin(a1) * radius, cy - math.cos(a1) * radius)
        l.To = Vector2.new(cx + math.sin(a2) * radius, cy - math.cos(a2) * radius)
        l.Thickness = 3; l.Color = col; l.Visible = true; l.Transparency = 1
        table.insert(lines, l)
    end
    task.spawn(function()
        local t0 = tick()
        while tick() - t0 < 0.6 do
            local a = 1 - (tick() - t0) / 0.6
            for _, l in ipairs(lines) do l.Transparency = a end
            task.wait()
        end
        for _, l in ipairs(lines) do l:Remove() end
    end)
end

local function showKillFlash()
    if not S.HitmarkOn then return end
    flashFrame.BackgroundColor3 = hexToC3(S.KillColor)
    flashFrame.BackgroundTransparency = 0.72
    TweenService:Create(flashFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1
    }):Play()
end

local function getDmgAngle()
    if not lp_hrp then return 0 end
    local best, bestD = nil, math.huge
    for _, v in ipairs(playerList) do
        local ch = v.Character; if not ch then continue end
        local hrp = ch:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
        local d = (hrp.Position - lp_hrp.Position).Magnitude
        if d < bestD and d < 120 then bestD = d; best = hrp.Position end
    end
    if not best then return 0 end
    local dir = (best - Camera.CFrame.Position).Unit
    return math.atan2(dir:Dot(Camera.CFrame.RightVector), dir:Dot(Camera.CFrame.LookVector))
end

local function hookLocalHealth()
    local function attach(ch)
        local hum = ch:WaitForChild("Humanoid", 5); if not hum then return end
        local prev = hum.Health
        conn.localHP = hum.HealthChanged:Connect(function(hp)
            if hp < prev and hp > 0 then showHurtArc(getDmgAngle()) end
            prev = hp
        end)
    end
    if LP.Character then attach(LP.Character) end
    conn.localCharHP = LP.CharacterAdded:Connect(function(ch) task.wait(0.2); attach(ch) end)
end
hookLocalHealth()

local function checkHits()
    for _, v in ipairs(playerList) do
        local ch = v.Character
        if not ch then healthPrev[v] = nil; continue end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not hum then healthPrev[v] = nil; continue end

        local cur = hum.Health
        local prev = healthPrev[v]

        if prev and cur < prev
           and v == lockedTarget
           and (tick() - lastShotTime) <= SHOT_WINDOW
        then
            if cur <= 0 then
                showKillFlash()
            else
                showHitMark()
            end
            lastShotTime = 0
        end

        healthPrev[v] = cur
    end
end

--============================================================
-- AIMBOT LOGIC
--============================================================
local function getClosest()
    -- distance from FOV CENTER (not mouse) for mobile
    local best, bestD = nil, S.FOVRadius
    for _, v in ipairs(playerList) do
        local ch = v.Character
        if not ch or not shouldAim(v) then continue end
        local part = ch:FindFirstChild(S.AimPart)
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if not part or not hum or hum.Health <= 0 then continue end
        local sp, vis = Camera:WorldToScreenPoint(part.Position)
        if not vis then continue end
        local d = (Vector2.new(sp.X, sp.Y) - fovCenter).Magnitude
        if d < bestD then bestD = d; best = v end
    end
    return best
end

local function isValid(p)
    if not p or not p.Parent then return false end
    local ch = p.Character; if not ch then return false end
    local part = ch:FindFirstChild(S.AimPart)
    local hum = ch:FindFirstChildOfClass("Humanoid")
    return part and hum and hum.Health > 0
end

--============================================================
-- DRAWING ESP HELPERS
--============================================================
local function getOrCreateDraw(plr)
    if espDrwCache[plr] then return espDrwCache[plr] end
    local d = {}
    d.box = {}
    for i = 1, 4 do
        local l = Drawing.new("Line"); l.Visible = false; l.Thickness = 1.5; d.box[i] = l
    end
    d.head = Drawing.new("Circle"); d.head.Visible = false; d.head.Thickness = 1.5; d.head.Filled = false; d.head.NumSides = 30
    d.tracer = Drawing.new("Line"); d.tracer.Visible = false; d.tracer.Thickness = 1.5
    d.name = Drawing.new("Text"); d.name.Visible = false; d.name.Size = 13; d.name.Center = true; d.name.Outline = true; d.name.Font = 2
    d.info = Drawing.new("Text"); d.info.Visible = false; d.info.Size = 12; d.info.Center = true; d.info.Outline = true; d.info.Font = 2
    espDrwCache[plr] = d
    _G.PH5M.espDrwCache = espDrwCache
    return d
end

local function hideAllDrawings()
    for _, d in pairs(espDrwCache) do
        for _, l in ipairs(d.box) do l.Visible = false end
        d.head.Visible = false
        d.tracer.Visible = false
        d.name.Visible = false
        d.info.Visible = false
    end
end

--============================================================
-- MAIN LOOP
--============================================================
local espTick = 0

conn.render = RunService.RenderStepped:Connect(function(dt)
    local vpX = Camera.ViewportSize.X
    local vpY = Camera.ViewportSize.Y

    -- FPS
    table.insert(fpsBuffer, dt)
    if #fpsBuffer > 60 then table.remove(fpsBuffer, 1) end
    local total = 0; for _, v in ipairs(fpsBuffer) do total += v end
    currentFPS = math.floor(#fpsBuffer / total)

    -- HUD
    local hudParts = {}
    if S.ShowFPS then table.insert(hudParts, "FPS: " .. currentFPS) end
    if S.ShowPing then
        local ping = 0; pcall(function() ping = math.floor(LP:GetNetworkPing() * 1000) end)
        table.insert(hudParts, "Ping: " .. ping .. "ms")
    end
    if S.ShowSpeed then
        local spd = 0
        if lp_hrp then pcall(function()
            local vel = lp_hrp.AssemblyLinearVelocity or lp_hrp.Velocity
            spd = math.floor(Vector3.new(vel.X, 0, vel.Z).Magnitude)
        end) end
        table.insert(hudParts, "Speed: " .. spd)
    end
    hudLabel.Text = table.concat(hudParts, "\n")
    hudFrame.Visible = #hudParts > 0
    hudFrame.Size = UDim2.new(0, 160, 0, 16 * #hudParts + 10)

    -- Rainbow
    hue = (hue + dt * 0.1) % 1
    local rainbow = Color3.fromHSV(hue, 1, 1)

    -- FOV Circle stays at fovCenter (not mouse)
    fovCircle.Position = fovCenter
    fovCircle.Radius = S.FOVRadius
    fovCircle.Visible = S.FOVVisible
    fovCircle.Color = S.FOVColorMode == "Rainbow" and rainbow or hexToC3(S.FOVCustomHex)

    -- Resize FOV handle to match
    fovHandle.Size = UDim2.new(0, S.FOVRadius * 2, 0, S.FOVRadius * 2)
    fovHandle.Position = UDim2.new(0, fovCenter.X - S.FOVRadius, 0, fovCenter.Y - S.FOVRadius)

    -- Determine if aimbot trigger is held
    local aimHolding = false
    if S.AimTrigger == "AimButton" then
        aimHolding = aimBtnHolding
    else -- RightHalf
        aimHolding = isRightHalfHolding() or aimBtnHolding
    end
    holding = aimHolding

    -- Show/hide aim button based on mode
    aimBtn.Visible = (S.AimTrigger == "AimButton")

    -- AIMBOT
    if holding and S.AimbotOn then
        if not lockedTarget then lockedTarget = getClosest() end
        if not isValid(lockedTarget) then
            lockedTarget = nil; lockBg.Visible = false
        else
            local part = lockedTarget.Character:FindFirstChild(S.AimPart)
            if part then
                if S.AimMode == "Instant" then
                    Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, part.Position)
                else
                    Camera.CFrame = Camera.CFrame:Lerp(
                        CFrame.lookAt(Camera.CFrame.Position, part.Position),
                        math.clamp(S.AimSmooth, 0.01, 1)
                    )
                end
            end
            local tn = "?"
            pcall(function() if lockedTarget.Team then tn = lockedTarget.Team.Name end end)
            lockTxt.Text = "LOCKED >> " .. lockedTarget.Name .. " [" .. tn .. "]"
            lockTxt.TextColor3 = rainbow
            lockBg.Visible = true
        end
    else
        lockedTarget = nil
        lockBg.Visible = false
    end

    -- Hitmarks
    checkHits()

    --==============================================
    -- ESP DRAWINGS
    --==============================================
    hideAllDrawings()

    local useDrawings = S.ESPOn and (S.ESPStyle ~= "Highlight" or S.ESPTracers)

    if useDrawings then
        local tracerOrigin
        if S.ESPTracerOrigin == "Bottom" then
            tracerOrigin = Vector2.new(vpX / 2, vpY)
        elseif S.ESPTracerOrigin == "Center" then
            tracerOrigin = Vector2.new(vpX / 2, vpY / 2)
        else
            tracerOrigin = Vector2.new(vpX / 2, 0)
        end

        for _, v in ipairs(playerList) do
            local ch = v.Character
            if not ch then continue end
            if not teamMatch(v, S.ESPTeam) then continue end

            local hrp = ch:FindFirstChild("HumanoidRootPart")
            local head = ch:FindFirstChild("Head")
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum or hum.Health <= 0 then continue end

            local centerSp, _ = Camera:WorldToViewportPoint(hrp.Position)
            if centerSp.Z <= 0 then continue end

            local d = getOrCreateDraw(v)
            local tc = getTeamColor(v)

            if S.ESPStyle == "2D Box" then
                local okBB, cfBB, sizeBB = pcall(function()
                    local cf, sz = ch:GetBoundingBox()
                    return cf, sz
                end)
                local cf, size
                if okBB and cfBB then
                    cf, size = cfBB, sizeBB
                else
                    cf = hrp.CFrame
                    size = Vector3.new(4, 5, 2)
                end

                local halfH = size.Y / 2
                local halfW = size.X / 2
                local halfD = size.Z / 2

                local corners = {
                    cf * CFrame.new( halfW,  halfH,  halfD),
                    cf * CFrame.new(-halfW,  halfH,  halfD),
                    cf * CFrame.new( halfW, -halfH,  halfD),
                    cf * CFrame.new(-halfW, -halfH,  halfD),
                    cf * CFrame.new( halfW,  halfH, -halfD),
                    cf * CFrame.new(-halfW,  halfH, -halfD),
                    cf * CFrame.new( halfW, -halfH, -halfD),
                    cf * CFrame.new(-halfW, -halfH, -halfD),
                }

                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                local anyVisible = false

                for _, c in ipairs(corners) do
                    local s, _ = Camera:WorldToViewportPoint(c.Position)
                    if s.Z > 0 then
                        anyVisible = true
                        if s.X < minX then minX = s.X end
                        if s.Y < minY then minY = s.Y end
                        if s.X > maxX then maxX = s.X end
                        if s.Y > maxY then maxY = s.Y end
                    end
                end

                if anyVisible then
                    local tl = Vector2.new(minX, minY)
                    local tr = Vector2.new(maxX, minY)
                    local bl = Vector2.new(minX, maxY)
                    local br = Vector2.new(maxX, maxY)

                    d.box[1].From = tl; d.box[1].To = tr; d.box[1].Color = tc; d.box[1].Visible = true
                    d.box[2].From = tr; d.box[2].To = br; d.box[2].Color = tc; d.box[2].Visible = true
                    d.box[3].From = br; d.box[3].To = bl; d.box[3].Color = tc; d.box[3].Visible = true
                    d.box[4].From = bl; d.box[4].To = tl; d.box[4].Color = tc; d.box[4].Visible = true

                    local cx = (minX + maxX) / 2
                    local textY = minY - 4
                    if S.ESPNames then
                        d.name.Text = v.Name
                        d.name.Position = Vector2.new(cx, textY - 14)
                        d.name.Color = tc
                        d.name.Visible = true
                        textY = textY - 14
                    end
                    local infoParts = {}
                    if S.ESPHealth then table.insert(infoParts, math.floor(hum.Health) .. "HP") end
                    if S.ESPDist and lp_hrp then
                        table.insert(infoParts, math.floor((hrp.Position - lp_hrp.Position).Magnitude) .. "m")
                    end
                    if #infoParts > 0 then
                        d.info.Text = table.concat(infoParts, " | ")
                        d.info.Position = Vector2.new(cx, textY - 14)
                        d.info.Color = Color3.new(1, 1, 1)
                        d.info.Visible = true
                    end
                end

            elseif S.ESPStyle == "Head Only" then
                if head then
                    local hs, _ = Camera:WorldToViewportPoint(head.Position)
                    if hs.Z > 0 then
                        local dist3D = (head.Position - Camera.CFrame.Position).Magnitude
                        local r = math.clamp(800 / dist3D, 4, 30)
                        d.head.Position = Vector2.new(hs.X, hs.Y)
                        d.head.Radius = r
                        d.head.Color = tc
                        d.head.Visible = true

                        local textY = hs.Y - r - 4
                        if S.ESPNames then
                            d.name.Text = v.Name
                            d.name.Position = Vector2.new(hs.X, textY - 14)
                            d.name.Color = tc
                            d.name.Visible = true
                            textY = textY - 14
                        end
                        local infoParts = {}
                        if S.ESPHealth then table.insert(infoParts, math.floor(hum.Health) .. "HP") end
                        if S.ESPDist and lp_hrp then
                            table.insert(infoParts, math.floor((hrp.Position - lp_hrp.Position).Magnitude) .. "m")
                        end
                        if #infoParts > 0 then
                            d.info.Text = table.concat(infoParts, " | ")
                            d.info.Position = Vector2.new(hs.X, textY - 14)
                            d.info.Color = Color3.new(1, 1, 1)
                            d.info.Visible = true
                        end
                    end
                end
            end

            if S.ESPTracers then
                local okBB, cfBB, sizeBB = pcall(function()
                    local cf, sz = ch:GetBoundingBox()
                    return cf, sz
                end)
                local bottomWorld
                if okBB and cfBB then
                    bottomWorld = cfBB.Position - Vector3.new(0, sizeBB.Y / 2, 0)
                else
                    bottomWorld = hrp.Position - Vector3.new(0, 3, 0)
                end
                local fs, _ = Camera:WorldToViewportPoint(bottomWorld)
                if fs.Z > 0 then
                    d.tracer.From = tracerOrigin
                    d.tracer.To = Vector2.new(fs.X, fs.Y)
                    d.tracer.Color = tc
                    d.tracer.Visible = true
                end
            end
        end
    end

    --==============================================
    -- ESP HIGHLIGHT
    --==============================================
    if S.ESPOn and S.ESPStyle == "Highlight" then
        local now = tick()
        if now - espTick >= 0.05 then
            espTick = now
            local lpPos = lp_hrp and lp_hrp.Position or Vector3.zero

            for _, v in ipairs(playerList) do
                local ch = v.Character
                local show = false
                if ch and teamMatch(v, S.ESPTeam) then
                    local hum = ch:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then show = true end
                end

                local cache = espHLCache[v]

                if not show then
                    if cache then
                        if cache.hl and cache.hl.Parent then cache.hl:Destroy() end
                        if cache.bb and cache.bb.Parent then cache.bb:Destroy() end
                        espHLCache[v] = nil
                    end
                    continue
                end

                local hrp = ch:FindFirstChild("HumanoidRootPart")
                local hum = ch:FindFirstChildOfClass("Humanoid")
                local head = ch:FindFirstChild("Head")
                if not hrp or not hum then continue end

                if not cache or cache.ch ~= ch then
                    if cache then
                        if cache.hl and cache.hl.Parent then cache.hl:Destroy() end
                        if cache.bb and cache.bb.Parent then cache.bb:Destroy() end
                    end
                    local tc = getTeamColor(v)
                    local hl = Instance.new("Highlight")
                    hl.Name = "PH5M_HL"
                    hl.Adornee = ch
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillColor = tc
                    hl.FillTransparency = S.ESPFillAlpha
                    hl.OutlineColor = Color3.new(1, 1, 1)
                    hl.Parent = ch

                    local anchor = head or hrp
                    local bb = Instance.new("BillboardGui")
                    bb.Name = "PH5M_BB"
                    bb.AlwaysOnTop = true
                    bb.StudsOffset = Vector3.new(0, 2.5, 0)
                    bb.Size = UDim2.new(0, 200, 0, 50)
                    bb.Adornee = anchor
                    bb.Parent = anchor

                    local lbl = Instance.new("TextLabel")
                    lbl.BackgroundTransparency = 1
                    lbl.Size = UDim2.new(1, 0, 1, 0)
                    lbl.Font = Enum.Font.GothamBold
                    lbl.TextSize = 13
                    lbl.TextColor3 = tc
                    lbl.TextStrokeTransparency = 0.6
                    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
                    lbl.Text = ""
                    lbl.Parent = bb

                    espHLCache[v] = { ch = ch, hl = hl, bb = bb, lbl = lbl }
                    cache = espHLCache[v]
                end

                local parts = {}
                if S.ESPNames then table.insert(parts, v.Name) end
                if S.ESPHealth then table.insert(parts, math.floor(hum.Health) .. "HP") end
                if S.ESPDist and lp_hrp then
                    table.insert(parts, math.floor((hrp.Position - lpPos).Magnitude) .. "m")
                end
                local txt = table.concat(parts, " | ")
                if cache.lbl.Text ~= txt then cache.lbl.Text = txt end
                cache.bb.Enabled = (#parts > 0)
            end
        end
    else
        destroyAllHighlights()
    end
end)

--============================================================
pcall(function()
    game.StarterGui:SetCore("SendNotification", {
        Title = "Prison Life Mobile | @nklays",
        Text = "Loaded. Hold right half of screen to aim.",
        Duration = 4
    })
end)
