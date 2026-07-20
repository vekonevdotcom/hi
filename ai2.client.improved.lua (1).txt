-- ai2.client.improved.lua
-- Spectra AI Client - cleaned UI, draggable/resizable window, raw JSON viewer, and emote system.
-- IMPORTANT: Your API key was removed from this file. Paste it in Settings at runtime.

local CONFIG = {
    API_KEY       = "", -- Paste your OpenRouter key in the Settings tab. Do NOT hardcode/share keys.
    TRIGGER       = "bot",
    MODEL         = "openai/gpt-oss-20b:free",
    MAX_TOKENS    = 150,
    SYSTEM_PROMPT = "You are a friendly Roblox player, not an assistant. Reply naturally in the same language as the user's message. If the user uses English, reply in simple English only. Keep replies under 160 characters. Do not invent words, do not mix random languages/scripts, and do not output gibberish. For greetings like hi/hello, answer with a normal greeting.",
    COOLDOWN      = 3,
    TEMPERATURE   = 0.35,
    TOP_P         = 0.85,
    MEMORY_ENABLED = true,
    MEMORY_LIMIT   = 5, -- last N chat messages remembered per player
    MAX_LOGS      = 80,
    PROXY_URL     = "https://corsproxy.io/?url=",
    CHAT_METHOD   = "auto", -- auto, textchat, legacy
    MENU_KEY      = Enum.KeyCode.RightShift,
    ACCENT        = Color3.fromRGB(94, 234, 212), -- softer cyan accent, less generic purple-hub look

    COMMAND_PREFIX = "!",

    -- Animation IDs requested
    IDLE_ANIM_ID   = "75730360108389",
    SIT_ANIM_ID    = "74543120303961", -- new sit animation
    KNEEL_ANIM_ID  = "94599985584623",
    IDLE_DELAY     = 0, -- standing emote starts immediately when actually standing still

    FOLLOW_DISTANCE = 6,    -- ideal distance from followed player
    FOLLOW_BUFFER   = 1.25, -- dead-zone so it doesn't twitch
    FOLLOW_REPATH   = 0.6,  -- seconds between path refreshes while following

    SMART_WALKING_ENABLED = true,
    PATH_AGENT_RADIUS     = 2.2,
    PATH_AGENT_HEIGHT     = 5,
    PATH_WAYPOINT_SPACING = 4,
    PATH_ARRIVE_DISTANCE  = 2.25,
    PATH_GOAL_REFRESH     = 3, -- studs target must move before recalculating path early

    LOOK_AT_ENABLED       = true,
    LOOK_AFTER_RESPONSE   = 4,  -- after response, keep looking at the speaker for this many seconds

    FOLLOW_VISUAL_ENABLED = true,
    FOLLOW_VISUAL_DOTS    = 36,
    KNEEL_DISTANCE        = 3.25,
    SITAT_DISTANCE        = 2.75,

    -- UI sizing
    DEFAULT_W     = 620,
    DEFAULT_H     = 640,
    MIN_W         = 460,
    MIN_H         = 420,
    MAX_W         = 980,
    MAX_H         = 820,
}

--// Services
local Players            = game:GetService("Players")
local HttpService        = game:GetService("HttpService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TeleportService    = game:GetService("TeleportService")
local LocalPlayer        = Players.LocalPlayer

--// Runtime state
local botEnabled       = true
local showThinking     = false
local privateMode      = false
local triggerRequired  = true
local autoSendChat     = true
local trimResponses    = true
local memoryEnabled    = CONFIG.MEMORY_ENABLED
local memoryLimit      = CONFIG.MEMORY_LIMIT
local jsonAutoFormat   = true
local currentPrompt    = CONFIG.SYSTEM_PROMPT
local lastUsed         = {}
local playerMemory     = {}
local whitelist        = {}
whitelist[LocalPlayer.UserId] = true

local followEnabled       = false
local followOnTrigger     = false
local currentFollowTarget = nil
local followRange         = CONFIG.FOLLOW_DISTANCE
local followBuffer        = CONFIG.FOLLOW_BUFFER
local followMoving        = false
local lastFollowMoveAt    = 0
local smartWalkingEnabled = CONFIG.SMART_WALKING_ENABLED
local lookAtEnabled       = CONFIG.LOOK_AT_ENABLED
local followVisualEnabled = CONFIG.FOLLOW_VISUAL_ENABLED

local idleEmoteEnabled = true
local sitEmoteEnabled  = true

--// UI helpers
local function clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function compactLine(s, maxLen)
    s = tostring(s or ""):gsub("[%c]", " "):gsub("%s+", " ")
    s = trim(s)
    maxLen = maxLen or 160
    if #s > maxLen then s = string.sub(s, 1, maxLen - 3) .. "..." end
    return s
end

local function trimMemoryBucket(bucket)
    while #bucket > memoryLimit do
        table.remove(bucket, 1)
    end
end

local function rememberPlayerMessage(player, message)
    if not memoryEnabled or not player then return end
    local text = compactLine(message, 180)
    if text == "" then return end

    local uid = player.UserId
    playerMemory[uid] = playerMemory[uid] or {
        name = player.Name,
        displayName = player.DisplayName or player.Name,
        messages = {},
    }

    local bucket = playerMemory[uid]
    bucket.name = player.Name
    bucket.displayName = player.DisplayName or player.Name

    table.insert(bucket.messages, {
        time = os.date("%H:%M:%S"),
        text = text,
    })
    trimMemoryBucket(bucket.messages)
end

local function clearPlayerMemory()
    playerMemory = {}
end

local function rebuildMemoryLimits()
    memoryLimit = math.max(1, math.floor(tonumber(memoryLimit) or CONFIG.MEMORY_LIMIT or 5))
    for _, bucket in pairs(playerMemory) do
        if bucket.messages then trimMemoryBucket(bucket.messages) end
    end
end

local function buildMemoryContext(focusUserId)
    if not memoryEnabled then return "Memory disabled." end

    rebuildMemoryLimits()

    local lines = {}
    local included = {}

    local function addBucket(uid, bucket)
        if not bucket or not bucket.messages or #bucket.messages == 0 or included[uid] then return end
        included[uid] = true
        table.insert(lines, "- " .. tostring(bucket.name or "Unknown") .. " (display: " .. tostring(bucket.displayName or bucket.name or "Unknown") .. ", userId: " .. tostring(uid) .. "):")
        for i, entry in ipairs(bucket.messages) do
            table.insert(lines, "  " .. i .. ". [" .. tostring(entry.time or "??:??:??") .. "] " .. compactLine(entry.text, 160))
        end
    end

    if focusUserId and playerMemory[focusUserId] then
        addBucket(focusUserId, playerMemory[focusUserId])
    end

    for _, p in ipairs(Players:GetPlayers()) do
        addBucket(p.UserId, playerMemory[p.UserId])
    end

    for uid, bucket in pairs(playerMemory) do
        addBucket(uid, bucket)
    end

    if #lines == 0 then return "No remembered messages yet." end
    return table.concat(lines, "\n")
end

local function safeParent(gui)
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end

local function addCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(32, 32, 46)
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

local function addPadding(parent, left, right, top, bottom)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, left or 0)
    p.PaddingRight = UDim.new(0, right or 0)
    p.PaddingTop = UDim.new(0, top or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.Parent = parent
    return p
end

local function makeText(parent, props)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.TextColor3 = Color3.fromRGB(200, 200, 220)
    t.Font = Enum.Font.Gotham
    t.TextSize = 12
    t.TextXAlignment = Enum.TextXAlignment.Left
    for k, v in pairs(props or {}) do t[k] = v end
    t.Parent = parent
    return t
end

local function makeButton(parent, text, color)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = color or Color3.fromRGB(24, 24, 36)
    b.BorderSizePixel = 0
    b.Text = text or "Button"
    b.TextColor3 = Color3.fromRGB(245, 245, 255)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.AutoButtonColor = false
    b.Parent = parent
    addCorner(b, 7)
    return b
end

local function tween(obj, info, goal)
    local ok, tw = pcall(function()
        return TweenService:Create(obj, info, goal)
    end)
    if ok and tw then tw:Play() end
    return tw
end

--// Disclaimer popup
local disclaimerAccepted = false
local function showDisclaimer()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SpectraDisclaimer"
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    safeParent(gui)

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.35
    overlay.BorderSizePixel = 0
    overlay.Parent = gui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(500, 340)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    addCorner(frame, 12)
    addStroke(frame, CONFIG.ACCENT, 1)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = Color3.fromRGB(24, 24, 38)
    header.BorderSizePixel = 0
    header.Parent = frame
    addCorner(header, 12)

    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = header.BackgroundColor3
    headerFix.BorderSizePixel = 0
    headerFix.Parent = header

    makeText(header, {
        Size = UDim2.new(1, -24, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        Text = "DISCLAIMER",
        TextColor3 = CONFIG.ACCENT,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local body = Instance.new("TextLabel")
    body.Size = UDim2.new(1, -40, 0, 130)
    body.Position = UDim2.fromOffset(20, 70)
    body.BackgroundColor3 = Color3.fromRGB(26, 26, 38)
    body.BorderSizePixel = 0
    body.Text = "The script author is not responsible for bans, chat moderation issues, revoked communication privileges, or problems caused by misuse. Use responsibly and follow the game's rules."
    body.TextColor3 = Color3.fromRGB(255, 150, 150)
    body.Font = Enum.Font.Gotham
    body.TextSize = 14
    body.TextWrapped = true
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Parent = frame
    addCorner(body, 8)
    addPadding(body, 12, 12, 12, 12)

    makeText(frame, {
        Size = UDim2.new(1, -40, 0, 44),
        Position = UDim2.fromOffset(20, 210),
        Text = "Open-source • No key system\nTip: never share hardcoded API keys.",
        TextColor3 = Color3.fromRGB(185, 170, 255),
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local timerLabel = makeText(frame, {
        Size = UDim2.new(1, -40, 0, 20),
        Position = UDim2.fromOffset(20, 258),
        Text = "Please wait 5 seconds...",
        TextColor3 = Color3.fromRGB(135, 135, 155),
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local progressBg = Instance.new("Frame")
    progressBg.Size = UDim2.new(1, -40, 0, 6)
    progressBg.Position = UDim2.fromOffset(20, 282)
    progressBg.BackgroundColor3 = Color3.fromRGB(38, 38, 50)
    progressBg.BorderSizePixel = 0
    progressBg.Parent = frame
    addCorner(progressBg, 99)

    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(74, 222, 128)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressBg
    addCorner(progressBar, 99)

    local acceptBtn = makeButton(frame, "Wait 5 seconds...", Color3.fromRGB(54, 54, 66))
    acceptBtn.Size = UDim2.new(1, -40, 0, 38)
    acceptBtn.Position = UDim2.new(0, 20, 1, -48)
    acceptBtn.TextColor3 = Color3.fromRGB(145, 145, 160)
    acceptBtn.TextSize = 14

    local timeLeft = 5
    local canAccept = false

    task.spawn(function()
        while timeLeft > 0 do
            timerLabel.Text = "Please wait " .. timeLeft .. " seconds..."
            acceptBtn.Text = "Wait " .. timeLeft .. " seconds..."
            tween(progressBar, TweenInfo.new(1, Enum.EasingStyle.Linear), {
                Size = UDim2.new((5 - timeLeft) / 5, 0, 1, 0)
            })
            timeLeft -= 1
            task.wait(1)
        end
        canAccept = true
        timerLabel.Text = "Ready to continue"
        acceptBtn.Text = "I Understand & Accept"
        tween(acceptBtn, TweenInfo.new(0.18), {
            BackgroundColor3 = Color3.fromRGB(34, 197, 94),
            TextColor3 = Color3.fromRGB(255, 255, 255)
        })
        tween(progressBar, TweenInfo.new(0.18), {
            Size = UDim2.new(1, 0, 1, 0)
        })
    end)

    acceptBtn.MouseButton1Click:Connect(function()
        if canAccept then
            disclaimerAccepted = true
            gui:Destroy()
        end
    end)

    repeat task.wait(0.1) until disclaimerAccepted
end

showDisclaimer()
print("[Spectra] Disclaimer accepted. Initializing...")

--// Warning toast
local function showWarning(message, duration)
    local gui = Instance.new("ScreenGui")
    gui.Name = "SpectraWarning"
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    safeParent(gui)

    local UI = {
        bg = Color3.fromRGB(18, 24, 38),
        panel = Color3.fromRGB(24, 32, 48),
        panel2 = Color3.fromRGB(30, 41, 59),
        card = Color3.fromRGB(35, 48, 68),
        input = Color3.fromRGB(15, 23, 42),
        stroke = Color3.fromRGB(71, 85, 105),
        muted = Color3.fromRGB(148, 163, 184),
        text = Color3.fromRGB(226, 232, 240),
        accent = CONFIG.ACCENT,
        danger = Color3.fromRGB(251, 113, 133),
        ok = Color3.fromRGB(52, 211, 153),
        radius = 16,
    }

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(420, 76)
    frame.Position = UDim2.new(0.5, 0, -0.2, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0)
    frame.BackgroundColor3 = Color3.fromRGB(32, 22, 24)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    addCorner(frame, UI.radius)
    addStroke(frame, Color3.fromRGB(239, 68, 68), 1)

    makeText(frame, {
        Size = UDim2.new(1, -22, 1, -18),
        Position = UDim2.fromOffset(11, 9),
        Text = "WARNING: " .. tostring(message),
        TextColor3 = Color3.fromRGB(255, 150, 150),
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    tween(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.08, 0)
    })

    task.delay(duration or 2.5, function()
        local t = tween(frame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, -0.2, 0)
        })
        if t then
            t.Completed:Connect(function() gui:Destroy() end)
        else
            gui:Destroy()
        end
    end)
end

--// Console module
local Console = {}
Console.__index = Console

function Console.new(max)
    local s = setmetatable({}, Console)
    s.entries = {}
    s.maxEntries = max or 80
    s.requestCount = 0
    s.errorCount = 0
    s.levels = {
        info    = { color = Color3.fromRGB(96, 165, 250),  icon = "i" },
        success = { color = Color3.fromRGB(74, 222, 128),  icon = "+" },
        warning = { color = Color3.fromRGB(250, 204, 21),  icon = "!" },
        error   = { color = Color3.fromRGB(248, 113, 113), icon = "x" },
    }
    s.ui = { logContainer = nil, statsLabel = nil }
    return s
end

function Console:Log(level, text)
    local e = {
        level = level or "info",
        text = tostring(text or ""),
        time = os.date("%H:%M:%S"),
    }
    table.insert(self.entries, e)
    while #self.entries > self.maxEntries do table.remove(self.entries, 1) end
    if e.level == "error" then self.errorCount += 1 end
    pcall(function() self:RenderEntry(e) end)
    pcall(function() self:RenderStats() end)
end

function Console:Info(t)    self:Log("info", t) end
function Console:Success(t) self:Log("success", t) end
function Console:Warn(t)    self:Log("warning", t) end
function Console:Error(t)   self:Log("error", t) end

function Console:Clear()
    self.entries = {}
    self.requestCount = 0
    self.errorCount = 0
    if self.ui.logContainer then
        for _, c in ipairs(self.ui.logContainer:GetChildren()) do
            if c:IsA("Frame") or c.Name == "EmptyState" then c:Destroy() end
        end
    end
    self:RenderStats()
end

function Console:RenderStats()
    if not self.ui.statsLabel then return end
    self.ui.statsLabel.Text = "Req: " .. self.requestCount .. "  •  Err: " .. self.errorCount .. "  •  Lines: " .. #self.entries
end

function Console:RenderEntry(entry)
    if not self.ui.logContainer then return end
    local emp = self.ui.logContainer:FindFirstChild("EmptyState")
    if emp then emp:Destroy() end

    local lvl = self.levels[entry.level]
    local col = lvl and lvl.color or Color3.fromRGB(150, 150, 150)
    local ico = lvl and lvl.icon or "?"

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -8, 0, 18)
    row.BackgroundTransparency = 1
    row.LayoutOrder = #self.entries

    makeText(row, {
        Size = UDim2.fromOffset(52, 18),
        Text = entry.time,
        TextColor3 = Color3.fromRGB(80, 80, 105),
        Font = Enum.Font.Code,
        TextSize = 10,
    })

    makeText(row, {
        Size = UDim2.fromOffset(22, 18),
        Position = UDim2.fromOffset(54, 0),
        Text = "[" .. ico .. "]",
        TextColor3 = col,
        Font = Enum.Font.Code,
        TextSize = 10,
    })

    makeText(row, {
        Size = UDim2.new(1, -82, 0, 18),
        Position = UDim2.fromOffset(78, 0),
        Text = entry.text,
        TextColor3 = col,
        Font = Enum.Font.Code,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    row.Parent = self.ui.logContainer
    task.defer(function()
        if self.ui.logContainer then
            self.ui.logContainer.CanvasPosition = Vector2.new(0, math.huge)
        end
    end)
end

local console = Console.new(CONFIG.MAX_LOGS)

--// Raw JSON viewer module
local RawViewer = {}
RawViewer.__index = RawViewer

local function prettyJson(raw)
    raw = tostring(raw or "")
    if raw == "" then return "" end

    local out = {}
    local indent = 0
    local inString = false
    local escape = false
    local function spaces()
        return string.rep("  ", indent)
    end

    for i = 1, #raw do
        local c = raw:sub(i, i)
        if inString then
            table.insert(out, c)
            if escape then
                escape = false
            elseif c == "\\" then
                escape = true
            elseif c == '"' then
                inString = false
            end
        else
            if c == '"' then
                inString = true
                table.insert(out, c)
            elseif c == "{" or c == "[" then
                table.insert(out, c)
                table.insert(out, "\n")
                indent += 1
                table.insert(out, spaces())
            elseif c == "}" or c == "]" then
                table.insert(out, "\n")
                indent = math.max(indent - 1, 0)
                table.insert(out, spaces())
                table.insert(out, c)
            elseif c == "," then
                table.insert(out, c)
                table.insert(out, "\n")
                table.insert(out, spaces())
            elseif c == ":" then
                table.insert(out, ": ")
            elseif c ~= " " and c ~= "\n" and c ~= "\t" and c ~= "\r" then
                table.insert(out, c)
            end
        end
    end

    return table.concat(out)
end

function RawViewer.new()
    local s = setmetatable({}, RawViewer)
    s.latestRequest = ""
    s.latestRaw = ""
    s.latestPretty = ""
    s.latestMeta = "No AI response captured yet."
    s.mode = "response" -- response/request
    s.pretty = true
    s.ui = { box = nil, meta = nil, modeLabel = nil }
    return s
end

function RawViewer:CaptureRequest(rawBody, meta)
    self.latestRequest = prettyJson(rawBody or "")
    self.requestMeta = meta or "Latest request body"
end

function RawViewer:CaptureResponse(rawBody, meta)
    self.latestRaw = tostring(rawBody or "")
    self.latestPretty = prettyJson(self.latestRaw)
    self.latestMeta = meta or ("Response captured: " .. #self.latestRaw .. " bytes")
    self:Render()
end

function RawViewer:Clear()
    self.latestRaw = ""
    self.latestPretty = ""
    self.latestRequest = ""
    self.latestMeta = "Cleared."
    self:Render()
end

function RawViewer:GetText()
    if self.mode == "request" then
        return self.latestRequest ~= "" and self.latestRequest or "No request captured yet."
    end
    if self.pretty then
        return self.latestPretty ~= "" and self.latestPretty or "No response captured yet."
    end
    return self.latestRaw ~= "" and self.latestRaw or "No response captured yet."
end

function RawViewer:Render()
    if self.ui.box then
        local txt = self:GetText()
        self.ui.box.Text = txt
        local lines = 1
        for _ in string.gmatch(txt, "\n") do lines += 1 end
        self.ui.box.Size = UDim2.new(1, -10, 0, math.max(320, (lines * 15) + 24))
    end
    if self.ui.meta then
        if self.mode == "request" then
            self.ui.meta.Text = self.requestMeta or "Latest request body"
        else
            self.ui.meta.Text = self.latestMeta
        end
    end
    if self.ui.modeLabel then
        self.ui.modeLabel.Text = "Viewing: " .. string.upper(self.mode) .. (self.mode == "response" and (self.pretty and " (pretty)" or " (raw)") or "")
    end
end

local rawViewer = RawViewer.new()

--// Animation/emote module
local Emotes = {}
Emotes.__index = Emotes

function Emotes.new()
    local s = setmetatable({}, Emotes)
    s.idleTrack = nil
    s.sitTrack = nil -- active locked pose/emote track (sit/kneel/custom)
    s.activePoseName = nil
    s.activePoseAnimId = nil
    s.lastHumanoid = nil
    s.lastMovingAt = tick()
    s.sitMode = false
    s.sitStartedAt = 0
    s._lastCheck = 0
    return s
end

function Emotes:GetHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

function Emotes:GetRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

function Emotes:ResetTracks()
    self.idleTrack = nil
    self.sitTrack = nil
    self.activePoseName = nil
    self.activePoseAnimId = nil
    self.lastHumanoid = nil
    self.lastMovingAt = tick()
    self.sitMode = false
    self.sitStartedAt = 0
end

function Emotes:LoadTrack(animId, priority, looped)
    local hum = self:GetHumanoid()
    if not hum then return nil end

    if self.lastHumanoid ~= hum then
        self:ResetTracks()
        self.lastHumanoid = hum
    end

    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end

    local anim = Instance.new("Animation")
    local id = tostring(animId or ""):gsub("rbxassetid://", "")
    anim.AnimationId = "rbxassetid://" .. id

    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        console:Error("Failed to load animation " .. tostring(animId))
        return nil
    end

    track.Priority = priority or Enum.AnimationPriority.Idle
    track.Looped = looped == true
    return track
end

function Emotes:StopIdle(fade)
    if self.idleTrack and self.idleTrack.IsPlaying then
        pcall(function() self.idleTrack:Stop(fade or 0.15) end)
    end
end

function Emotes:StopSit(fade)
    self.sitMode = false
    self.sitStartedAt = 0
    self.activePoseName = nil
    self.activePoseAnimId = nil
    if self.sitTrack and self.sitTrack.IsPlaying then
        pcall(function() self.sitTrack:Stop(fade or 0.15) end)
    end
end

function Emotes:IsStandingIdle()
    if not idleEmoteEnabled then return false end
    if self.sitMode then return false end

    local hum = self:GetHumanoid()
    if not hum or hum.Health <= 0 then return false end
    if hum.Sit or hum.PlatformStand then return false end
    if hum.MoveDirection.Magnitude > 0.05 then return false end
    if hum.FloorMaterial == Enum.Material.Air then return false end

    local state = hum:GetState()
    local blocked = {
        [Enum.HumanoidStateType.Jumping] = true,
        [Enum.HumanoidStateType.Freefall] = true,
        [Enum.HumanoidStateType.FallingDown] = true,
        [Enum.HumanoidStateType.Climbing] = true,
        [Enum.HumanoidStateType.Swimming] = true,
        [Enum.HumanoidStateType.Seated] = true,
        [Enum.HumanoidStateType.Dead] = true,
        [Enum.HumanoidStateType.PlatformStanding] = true,
        [Enum.HumanoidStateType.Ragdoll] = true,
    }
    if blocked[state] then return false end

    local root = self:GetRoot()
    if root then
        local v = root.AssemblyLinearVelocity
        local horizontalSpeed = Vector3.new(v.X, 0, v.Z).Magnitude
        if horizontalSpeed > 0.75 then return false end
    end

    return true
end

function Emotes:StartIdle()
    if not self:IsStandingIdle() then return end
    if not self.idleTrack then
        self.idleTrack = self:LoadTrack(CONFIG.IDLE_ANIM_ID, Enum.AnimationPriority.Action, true)
    end
    if self.idleTrack then
        self.idleTrack.Looped = true
        if not self.idleTrack.IsPlaying then
            pcall(function() self.idleTrack:Play(0.12, 1, 1) end)
        end
    end
end

function Emotes:PlayLockedEmote(animId, poseName)
    animId = tostring(animId or ""):gsub("rbxassetid://", "")
    if animId == "" then return end

    -- Locked emote state. Standing idle cannot restart until StopSit/stand/follow/jump.
    self:StopIdle(0)

    if self.sitTrack and self.sitTrack.IsPlaying and self.activePoseAnimId ~= animId then
        pcall(function() self.sitTrack:Stop(0.05) end)
        self.sitTrack = nil
    end

    self.sitMode = true
    self.sitStartedAt = tick()
    self.activePoseName = poseName or "custom"
    self.activePoseAnimId = animId

    if not self.sitTrack then
        self.sitTrack = self:LoadTrack(animId, Enum.AnimationPriority.Action4, true)
    end

    if self.sitTrack then
        self.sitTrack.Priority = Enum.AnimationPriority.Action4
        self.sitTrack.Looped = true
        pcall(function() self.sitTrack:Play(0.05, 1, 1) end)
    end
end

function Emotes:PlaySit()
    if not sitEmoteEnabled then return end
    self:PlayLockedEmote(CONFIG.SIT_ANIM_ID, "sit")
end

function Emotes:PlayKneel()
    self:PlayLockedEmote(CONFIG.KNEEL_ANIM_ID, "kneel")
end

function Emotes:PlayCustom(animId)
    self:PlayLockedEmote(animId, "custom")
end

function Emotes:Heartbeat()
    if tick() - self._lastCheck < 0.08 then return end
    self._lastCheck = tick()

    -- Sit command is an emote-only locked state. Do NOT stop it just because MoveDirection/velocity
    -- flickers for a frame after MoveTo cancellation; that was causing standing idle to overwrite sit.
    if self.sitMode then
        self:StopIdle(0)

        local hum = self:GetHumanoid()
        local state = hum and hum:GetState()
        local shouldStopSit = (not hum) or hum.Health <= 0 or followEnabled
            or state == Enum.HumanoidStateType.Jumping
            or state == Enum.HumanoidStateType.Freefall
            or state == Enum.HumanoidStateType.Climbing
            or state == Enum.HumanoidStateType.Swimming
            or state == Enum.HumanoidStateType.Dead

        if shouldStopSit then
            self:StopSit(0.12)
        else
            local animId = self.activePoseAnimId or CONFIG.SIT_ANIM_ID
            if not self.sitTrack then
                self.sitTrack = self:LoadTrack(animId, Enum.AnimationPriority.Action4, true)
            end
            if not self.sitTrack then
                self.sitMode = false
                self.activePoseName = nil
                self.activePoseAnimId = nil
                return
            end
            self.sitTrack.Priority = Enum.AnimationPriority.Action4
            self.sitTrack.Looped = true
            if not self.sitTrack.IsPlaying then
                pcall(function() self.sitTrack:Play(0.05, 1, 1) end)
            end
        end
        return
    end

    if self:IsStandingIdle() then
        -- No delay: if the character is standing still, always keep the standing emote running.
        self:StartIdle()
    else
        self.lastMovingAt = tick()
        self:StopIdle(0.12)
    end
end

local emotes = Emotes.new()
LocalPlayer.CharacterAdded:Connect(function()
    emotes:ResetTracks()
end)
RunService.Heartbeat:Connect(function()
    emotes:Heartbeat()
end)

--// Smart walking module: uses Roblox pathfinding instead of walking in a straight line through walls.
local SmartWalker = {}
SmartWalker.__index = SmartWalker

function SmartWalker.new()
    local s = setmetatable({}, SmartWalker)
    s.active = false
    s.computing = false
    s.currentGoal = nil
    s.lastGoal = nil
    s.lastCompute = 0
    s.waypoints = {}
    s.index = 0
    s.humanoid = nil
    s.moveConn = nil
    s.blockedConn = nil
    s.lastWarnAt = 0
    return s
end

function SmartWalker:GetCharacterParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

function SmartWalker:BindHumanoid(hum)
    if self.humanoid == hum then return end
    if self.moveConn then self.moveConn:Disconnect() self.moveConn = nil end
    self.humanoid = hum
    if hum then
        self.moveConn = hum.MoveToFinished:Connect(function(reached)
            if not self.active then return end
            if reached then
                self.index += 1
                self:MoveNext()
            else
                local goal = self.currentGoal
                self.active = false
                if goal then
                    task.defer(function()
                        self:Start(goal, "retry", true)
                    end)
                end
            end
        end)
    end
end

function SmartWalker:DisconnectBlocked()
    if self.blockedConn then
        self.blockedConn:Disconnect()
        self.blockedConn = nil
    end
end

function SmartWalker:Stop(holdPosition)
    self.active = false
    self.computing = false
    self.currentGoal = nil
    self.waypoints = {}
    self.index = 0
    self:DisconnectBlocked()

    if holdPosition ~= false then
        local _, hum, root = self:GetCharacterParts()
        if hum and root then
            pcall(function() hum:Move(Vector3.new(0, 0, 0), false) end)
            pcall(function() hum:MoveTo(root.Position) end)
        end
    end
end

function SmartWalker:MoveNext()
    if not self.active then return end

    local _, hum, root = self:GetCharacterParts()
    if not hum or not root or hum.Health <= 0 then
        self:Stop(false)
        return
    end
    self:BindHumanoid(hum)

    while self.index <= #self.waypoints do
        local wp = self.waypoints[self.index]
        if (root.Position - wp.Position).Magnitude <= CONFIG.PATH_ARRIVE_DISTANCE then
            self.index += 1
        else
            if wp.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
            hum:MoveTo(wp.Position)
            return
        end
    end

    self:Stop(true)
end

function SmartWalker:WarnThrottled(text)
    if tick() - self.lastWarnAt > 2 then
        self.lastWarnAt = tick()
        console:Warn(text)
    end
end

function SmartWalker:Start(goalPosition, reason, force)
    if not goalPosition then return false end

    local _, hum, root = self:GetCharacterParts()
    if not hum or not root or hum.Health <= 0 then return false end
    self:BindHumanoid(hum)

    local distanceToGoal = (root.Position - goalPosition).Magnitude
    if distanceToGoal <= CONFIG.PATH_ARRIVE_DISTANCE then
        self:Stop(true)
        return true
    end

    if not smartWalkingEnabled then
        self:Stop(false)
        self.currentGoal = goalPosition
        hum:MoveTo(goalPosition)
        return true
    end

    if self.computing then return false end

    local now = tick()
    local goalMoved = (not self.lastGoal) or ((self.lastGoal - goalPosition).Magnitude >= CONFIG.PATH_GOAL_REFRESH)
    if not force and self.active and not goalMoved and (now - self.lastCompute) < CONFIG.FOLLOW_REPATH then
        return true
    end

    self.computing = true
    self.currentGoal = goalPosition
    self.lastGoal = goalPosition
    self.lastCompute = now

    local path = PathfindingService:CreatePath({
        AgentRadius = CONFIG.PATH_AGENT_RADIUS,
        AgentHeight = CONFIG.PATH_AGENT_HEIGHT,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = CONFIG.PATH_WAYPOINT_SPACING,
    })

    local ok, err = pcall(function()
        path:ComputeAsync(root.Position, goalPosition)
    end)

    self.computing = false

    if not ok or path.Status ~= Enum.PathStatus.Success then
        self:Stop(true)
        self:WarnThrottled("No smart path found" .. (reason and (" (" .. tostring(reason) .. ")") or ""))
        return false
    end

    self:DisconnectBlocked()
    self.blockedConn = path.Blocked:Connect(function(blockedIndex)
        if self.active and blockedIndex >= self.index and self.currentGoal then
            local goal = self.currentGoal
            self.active = false
            task.defer(function()
                self:Start(goal, "blocked", true)
            end)
        end
    end)

    self.waypoints = path:GetWaypoints()
    if #self.waypoints == 0 then
        self:Stop(true)
        return false
    end

    self.index = 2 -- waypoint 1 is usually the current position
    if self.index > #self.waypoints then self.index = 1 end
    self.active = true
    self:MoveNext()
    return true
end

local smartWalker = SmartWalker.new()
LocalPlayer.CharacterAdded:Connect(function()
    smartWalker:Stop(false)
end)

--// Look controller: looks at the speaker while thinking, then looks where that speaker is looking.
local LookController = {}
LookController.__index = LookController

function LookController.new()
    local s = setmetatable({}, LookController)
    s.active = false
    s.mode = "none"
    s.targetPlayer = nil
    s.untilTime = 0
    s.humanoid = nil
    s.previousAutoRotate = nil
    s._lastStep = 0
    return s
end

function LookController:GetHumanoidRoot()
    local char = LocalPlayer.Character
    if not char then return nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return hum, root
end

function LookController:GetTargetRoot(player)
    local char = player and player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end

function LookController:LockAutoRotate(hum)
    if self.humanoid ~= hum then
        if self.humanoid and self.previousAutoRotate ~= nil then
            pcall(function() self.humanoid.AutoRotate = self.previousAutoRotate end)
        end
        self.humanoid = hum
        self.previousAutoRotate = hum and hum.AutoRotate or nil
    end
    if hum then hum.AutoRotate = false end
end

function LookController:Release()
    self.active = false
    self.mode = "none"
    self.targetPlayer = nil
    self.untilTime = 0
    if self.humanoid and self.previousAutoRotate ~= nil then
        pcall(function() self.humanoid.AutoRotate = self.previousAutoRotate end)
    end
    self.humanoid = nil
    self.previousAutoRotate = nil
end

function LookController:FacePoint(point)
    if not lookAtEnabled then
        self:Release()
        return
    end

    local hum, root = self:GetHumanoidRoot()
    if not hum or not root or hum.Health <= 0 then
        self:Release()
        return
    end

    self:LockAutoRotate(hum)

    local origin = root.Position
    local target = Vector3.new(point.X, origin.Y, point.Z)
    if (target - origin).Magnitude > 0.15 then
        root.CFrame = CFrame.lookAt(origin, target)
    end
end

function LookController:LookAtPlayer(player, duration)
    if not lookAtEnabled or not player then return end
    self.active = true
    self.mode = "player"
    self.targetPlayer = player
    self.untilTime = duration and (tick() + duration) or 0
end

function LookController:Heartbeat()
    if not self.active then return end
    if tick() - self._lastStep < 0.05 then return end
    self._lastStep = tick()

    if self.untilTime > 0 and tick() > self.untilTime then
        self:Release()
        return
    end

    local targetRoot = self:GetTargetRoot(self.targetPlayer)
    if not targetRoot then
        self:Release()
        return
    end

    if self.mode == "player" then
        self:FacePoint(targetRoot.Position)
    end
end

local lookController = LookController.new()
RunService.Heartbeat:Connect(function()
    lookController:Heartbeat()
end)
LocalPlayer.CharacterAdded:Connect(function()
    lookController:Release()
end)

--// Follow circle visualizer. Local-only neon dots show too-close / ideal / too-far range.
local FollowVisualizer = {}
FollowVisualizer.__index = FollowVisualizer

function FollowVisualizer.new()
    local s = setmetatable({}, FollowVisualizer)
    s.folder = nil
    s.dots = {}
    s.radiusKey = ""
    s._lastUpdate = 0
    return s
end

function FollowVisualizer:Clear()
    if self.folder then
        self.folder:Destroy()
    end
    self.folder = nil
    self.dots = {}
    self.radiusKey = ""
end

function FollowVisualizer:AddRing(radius, color, transparency, count, name)
    if radius <= 0 then return end
    count = count or CONFIG.FOLLOW_VISUAL_DOTS
    for i = 1, count do
        local angle = ((i - 1) / count) * math.pi * 2
        local dot = Instance.new("Part")
        dot.Name = name or "RingDot"
        dot.Shape = Enum.PartType.Ball
        dot.Size = Vector3.new(0.18, 0.18, 0.18)
        dot.Anchored = true
        dot.CanCollide = false
        dot.CanTouch = false
        dot.CanQuery = false
        dot.CastShadow = false
        dot.Material = Enum.Material.Neon
        dot.Color = color
        dot.Transparency = transparency or 0.25
        dot.Parent = self.folder
        table.insert(self.dots, { part = dot, radius = radius, angle = angle })
    end
end

function FollowVisualizer:Ensure()
    local minDistance = math.max(1.5, followRange - followBuffer)
    local maxDistance = followRange + followBuffer
    local key = string.format("%.2f|%.2f|%.2f|%d", minDistance, followRange, maxDistance, CONFIG.FOLLOW_VISUAL_DOTS)
    if self.folder and self.radiusKey == key then return end

    self:Clear()
    self.radiusKey = key

    local folder = Instance.new("Folder")
    folder.Name = "SpectraSmartFollowCircle"
    folder.Parent = workspace
    self.folder = folder

    self:AddRing(minDistance, Color3.fromRGB(248, 113, 113), 0.55, math.max(20, math.floor(CONFIG.FOLLOW_VISUAL_DOTS * 0.8)), "TooCloseRing")
    self:AddRing(followRange, CONFIG.ACCENT, 0.12, CONFIG.FOLLOW_VISUAL_DOTS, "IdealRing")
    self:AddRing(maxDistance, Color3.fromRGB(96, 165, 250), 0.55, math.max(20, math.floor(CONFIG.FOLLOW_VISUAL_DOTS * 0.8)), "TooFarRing")
end

function FollowVisualizer:Heartbeat()
    if tick() - self._lastUpdate < 0.05 then return end
    self._lastUpdate = tick()

    if not followVisualEnabled or not followEnabled or not currentFollowTarget or not currentFollowTarget.Character then
        if self.folder then self:Clear() end
        return
    end

    local root = currentFollowTarget.Character:FindFirstChild("HumanoidRootPart")
    if not root then
        if self.folder then self:Clear() end
        return
    end

    self:Ensure()
    local center = root.Position
    local y = center.Y - 2.75
    for _, dotInfo in ipairs(self.dots) do
        local dot = dotInfo.part
        if dot and dot.Parent then
            local x = center.X + math.cos(dotInfo.angle) * dotInfo.radius
            local z = center.Z + math.sin(dotInfo.angle) * dotInfo.radius
            dot.CFrame = CFrame.new(x, y, z)
        end
    end
end

local followVisualizer = FollowVisualizer.new()
RunService.Heartbeat:Connect(function()
    followVisualizer:Heartbeat()
end)

--// Chat sender
local function sendAsPlayer(text)
    text = tostring(text or "")
    if text == "" then return false end

    local success = false

    if CONFIG.CHAT_METHOD == "auto" or CONFIG.CHAT_METHOD == "textchat" then
        pcall(function()
            local TCS = game:GetService("TextChatService")
            local generalChannel = TCS.TextChannels:WaitForChild("RBXGeneral", 5)
            if generalChannel then
                generalChannel:SendAsync(text)
                success = true
                console:Info("Sent via TextChat")
            end
        end)
        if success then return true end
    end

    if CONFIG.CHAT_METHOD == "auto" or CONFIG.CHAT_METHOD == "legacy" then
        pcall(function()
            local ce = ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 5)
            if ce then
                local sm = ce:WaitForChild("SayMessageRequest", 5)
                if sm and sm:IsA("RemoteEvent") then
                    sm:FireServer(text, "All")
                    success = true
                    console:Info("Sent via Legacy Chat")
                end
            end
        end)
        if success then return true end
    end

    console:Error("All chat methods failed")
    return false
end

--// HTTP
local function getGlobal(name)
    local env
    pcall(function()
        if getgenv then
            env = getgenv()
        elseif getfenv then
            env = getfenv()
        end
    end)
    if env and rawget(env, name) ~= nil then return rawget(env, name) end
    if _G and _G[name] ~= nil then return _G[name] end
    return nil
end

local function makeHttpRequest(url, headers, body)
    local funcs = {
        { name = "httprequest", fn = getGlobal("httprequest") },
        { name = "request",     fn = getGlobal("request") },
    }

    local synGlobal = getGlobal("syn")
    if synGlobal and synGlobal.request then
        table.insert(funcs, { name = "syn.request", fn = synGlobal.request })
    end
    local httpGlobal = getGlobal("http")
    if httpGlobal and httpGlobal.request then
        table.insert(funcs, { name = "http.request", fn = httpGlobal.request })
    end

    for _, item in ipairs(funcs) do
        if type(item.fn) == "function" then
            local ok, res = pcall(function()
                return item.fn({
                    Url = url,
                    Method = "POST",
                    Headers = headers,
                    Body = body,
                })
            end)
            if ok and res then
                local responseBody = res.Body or res.body
                if responseBody then
                    return {
                        body = responseBody,
                        status = res.StatusCode or res.status_code or res.Status or "?",
                        source = item.name,
                    }
                end
            end
        end
    end

    return nil
end

local function extractAIMessage(data)
    if data and data.choices and data.choices[1] and data.choices[1].message then
        return data.choices[1].message.content
    end
    return nil
end

local function isMostlyAscii(text)
    text = tostring(text or "")
    if text == "" then return true end

    local total, nonAscii = 0, 0
    local ok = pcall(function()
        for _, code in utf8.codes(text) do
            total += 1
            if code > 127 then nonAscii += 1 end
        end
    end)

    if not ok or total == 0 then
        total, nonAscii = #text, 0
        for i = 1, #text do
            if string.byte(text, i) > 127 then nonAscii += 1 end
        end
    end

    return total == 0 or (nonAscii / total) <= 0.05
end

local function suspiciousForeignChars(text)
    text = tostring(text or "")
    local count = 0

    local ok = pcall(function()
        for _, code in utf8.codes(text) do
            -- Count non-ASCII letters/scripts, but ignore emoji-ish ranges.
            if code > 127 and code < 0x1F000 then
                count += 1
            end
        end
    end)

    if not ok then
        for i = 1, #text do
            if string.byte(text, i) > 127 then count += 1 end
        end
    end

    return count
end

local function sanitizeAIResponse(prompt, content)
    local s = trim(content)
    s = s:gsub("[%c]", " "):gsub("%s+", " ")

    if s == "" then
        return nil, "empty response"
    end

    if isMostlyAscii(prompt) and suspiciousForeignChars(s) >= 2 then
        return nil, "blocked mixed-language/gibberish response"
    end

    return s, nil
end

local function queryAI(username, prompt, userId, retrying)
    if trim(CONFIG.API_KEY) == "" then
        local msg = "Missing API key. Paste it in Settings."
        console:Error(msg)
        return nil, msg
    end

    local effectivePrompt = currentPrompt
    if retrying then
        effectivePrompt = currentPrompt .. "\nCritical retry rule: Your previous answer was rejected as mixed-language/gibberish. Answer again using only the user's language. If the user wrote in English, use plain English letters only. No random foreign characters."
    end

    local memoryContext = buildMemoryContext(userId)
    local senderBucket = userId and playerMemory[userId]
    local senderDisplayName = senderBucket and senderBucket.displayName or username
    local userContent = table.concat({
        "Sender username: " .. tostring(username),
        "Sender display name: " .. tostring(senderDisplayName),
        "Sender userId: " .. tostring(userId or "unknown"),
        "",
        "Recent memory, last " .. tostring(memoryLimit) .. " message(s) per player:",
        memoryContext,
        "",
        "Current message from " .. tostring(username) .. ":",
        tostring(prompt),
    }, "\n")

    local body = HttpService:JSONEncode({
        model = CONFIG.MODEL,
        max_tokens = tonumber(CONFIG.MAX_TOKENS) or 150,
        temperature = retrying and 0.15 or (tonumber(CONFIG.TEMPERATURE) or 0.35),
        top_p = retrying and 0.65 or (tonumber(CONFIG.TOP_P) or 0.85),
        messages = {
            { role = "system", content = effectivePrompt .. "\nUse the sender username and recent memory when helpful, but keep replies natural and short." },
            { role = "user", content = userContent },
        }
    })

    local directUrl = "https://openrouter.ai/api/v1/chat/completions"
    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. CONFIG.API_KEY,
        ["HTTP-Referer"] = "https://roblox.com",
        ["X-Title"]      = "Spectra",
    }

    rawViewer:CaptureRequest(body, "Request by " .. tostring(username) .. (retrying and " | retry" or "") .. " | prompt: " .. tostring(prompt))
    console:Info(retrying and "Retrying API with stricter language rules..." or "Requesting API...")

    local response = makeHttpRequest(directUrl, headers, body)
    if not response then
        console:Warn("Direct request failed; trying proxy")
        response = makeHttpRequest(CONFIG.PROXY_URL .. HttpService:UrlEncode(directUrl), headers, body)
    end

    if not response then
        console:Error("All HTTP methods failed")
        return nil, "HTTP request failed"
    end

    local responseBody = response.body
    rawViewer:CaptureResponse(
        responseBody,
        "HTTP " .. tostring(response.status) .. " via " .. tostring(response.source) .. " | " .. #responseBody .. " bytes | " .. os.date("%H:%M:%S")
    )
    console:Success("AI JSON captured in JSON tab (" .. #responseBody .. " bytes)")

    local parseOk, data = pcall(function()
        return HttpService:JSONDecode(responseBody)
    end)
    if not parseOk or not data then
        console:Error("Invalid JSON returned by API")
        return nil, "Parse failed"
    end

    if data.error then
        local e = (type(data.error) == "table" and (data.error.message or data.error.code)) or tostring(data.error)
        console:Error(e)
        return nil, e
    end

    local content = extractAIMessage(data)
    if content and content ~= "" then
        local clean, blockedReason = sanitizeAIResponse(prompt, content)
        if blockedReason then console:Warn(blockedReason) end
        if clean then
            console:Success("AI: " .. string.sub(clean, 1, 80))
            return clean
        end
        if not retrying then
            console:Warn("Retrying because AI returned mixed-language/gibberish text")
            return queryAI(username, prompt, userId, true)
        end
        return nil, "AI returned gibberish after retry"
    end

    console:Error("No message in API response")
    return nil, "No response from AI"
end

local function getBangPrompt(message)
    local prefix = CONFIG.COMMAND_PREFIX or "!"
    if string.sub(message, 1, #prefix) == prefix then
        return trim(string.sub(message, #prefix + 1))
    end
    return nil
end

--// Message and command handling
local function handleMessage(player, message)
    if not botEnabled then return end
    if privateMode and not whitelist[player.UserId] then return end

    local prompt = message
    local bangPrompt = getBangPrompt(message)

    if bangPrompt ~= nil then
        -- Second prefix: if !text was not a valid command, use it as an AI prompt.
        prompt = bangPrompt
        if prompt == "" then return end
    elseif triggerRequired then
        local lowerMsg = string.lower(message)
        local trigger = string.lower(CONFIG.TRIGGER)
        local triggerLen = #trigger
        if string.sub(lowerMsg, 1, triggerLen) ~= trigger then return end
        if #message > triggerLen and string.sub(message, triggerLen + 1, triggerLen + 1) ~= " " then return end
        prompt = trim(string.sub(message, triggerLen + 2))
        if prompt == "" then return end
    else
        prompt = trim(message)
        if prompt == "" then return end
    end

    local now = tick()
    if lastUsed[player.UserId] and (now - lastUsed[player.UserId]) < CONFIG.COOLDOWN then return end
    lastUsed[player.UserId] = now

    console.requestCount += 1
    console:Info(player.Name .. ": " .. prompt)

    -- While generating, face the player who asked.
    lookController:LookAtPlayer(player)

    if showThinking and autoSendChat then
        task.wait(0.08)
        sendAsPlayer("Thinking...")
    end

    task.spawn(function()
        local aiResponse, errorMsg = queryAI(player.Name, prompt, player.UserId)

        -- Once the answer is ready, keep looking at the speaker for 4 seconds, then stop looking.
        lookController:LookAtPlayer(player, CONFIG.LOOK_AFTER_RESPONSE)

        if aiResponse then
            if trimResponses and #aiResponse > 250 then
                aiResponse = string.sub(aiResponse, 1, 247) .. "..."
            end
            if autoSendChat then
                local sent = sendAsPlayer(aiResponse)
                if not sent then
                    task.wait(0.5)
                    sendAsPlayer(aiResponse)
                end
            else
                console:Info("Auto-send off. Response only stored in JSON/console.")
            end
        else
            if autoSendChat then sendAsPlayer("Error: " .. (errorMsg or "unknown")) end
        end
    end)
end

local function followPlayer(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    currentFollowTarget = targetPlayer
    followEnabled = true
    followMoving = false
    lastFollowMoveAt = 0
    emotes:StopSit(0.1)
    emotes:StopIdle(0.1)
    smartWalker:Stop(true)
    console:Info("Following " .. targetPlayer.Name)
end

local function unfollowPlayer()
    followEnabled = false
    currentFollowTarget = nil
    followMoving = false
    smartWalker:Stop(true)
    console:Info("Stopped following")
end

local function comeToPlayer(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return end
    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")

    if targetRoot and myRoot and myHum then
        emotes:StopSit(0.1)
        emotes:StopIdle(0.1)
        local offset = myRoot.Position - targetRoot.Position
        local flat = Vector3.new(offset.X, 0, offset.Z)
        local dir
        if flat.Magnitude > 0.1 then
            dir = flat.Unit
        else
            local back = -targetRoot.CFrame.LookVector
            local flatBack = Vector3.new(back.X, 0, back.Z)
            dir = flatBack.Magnitude > 0.1 and flatBack.Unit or Vector3.new(0, 0, -1)
        end
        smartWalker:Start(targetRoot.Position + (dir * followRange), "come", true)
        console:Info("Smart-walking close to " .. targetPlayer.Name)
    end
end

RunService.Heartbeat:Connect(function()
    if not followEnabled or not currentFollowTarget then return end

    local myChar = LocalPlayer.Character
    local targetChar = currentFollowTarget.Character
    if not myChar or not targetChar then return end

    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
    local myHum = myChar:FindFirstChildOfClass("Humanoid")

    if myRoot and targetRoot and myHum then
        local offset = myRoot.Position - targetRoot.Position
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)
        local distance = flatOffset.Magnitude

        local minDistance = math.max(1.5, followRange - followBuffer)
        local maxDistance = followRange + followBuffer

        local dir
        if distance > 0.1 then
            dir = flatOffset.Unit
        else
            local back = -targetRoot.CFrame.LookVector
            local flatBack = Vector3.new(back.X, 0, back.Z)
            dir = flatBack.Magnitude > 0.1 and flatBack.Unit or Vector3.new(0, 0, -1)
        end

        -- Stand beside/behind the target at the ideal radius, never directly on their root position.
        local desiredPos = targetRoot.Position + (dir * followRange)

        if distance < minDistance or distance > maxDistance then
            -- Too close = walk away to desired radius. Too far = walk closer to the same desired radius.
            if tick() - lastFollowMoveAt >= CONFIG.FOLLOW_REPATH then
                emotes:StopSit(0.1)
                emotes:StopIdle(0.1)
                local started = smartWalker:Start(desiredPos, "follow", false)
                lastFollowMoveAt = tick()
                followMoving = started == true
            end
        else
            -- In the dead-zone: cancel pathing once so it doesn't jitter/twitch.
            if followMoving or smartWalker.active then
                smartWalker:Stop(true)
                followMoving = false
                console:Info("Follow target reached; holding position")
            end
        end
    end
end)

local function rejoinSameServer()
    console:Warn("Rejoining same server...")
    smartWalker:Stop(true)

    local ok, err = pcall(function()
        if game.JobId and game.JobId ~= "" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        else
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    end)

    if not ok then
        local msg = "Rejoin failed: " .. tostring(err)
        console:Error(msg)
        showWarning(msg, 4)
    end
end

local function getRandomPlayer(exclude)
    exclude = exclude or {}
    local pool = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if not exclude[p.UserId] and p ~= LocalPlayer then
            table.insert(pool, p)
        end
    end
    if #pool == 0 then
        for _, p in ipairs(Players:GetPlayers()) do
            if not exclude[p.UserId] then
                table.insert(pool, p)
            end
        end
    end
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

local function findPlayerByName(query, fallbackPlayer)
    query = trim(query or "")
    local lowerQuery = string.lower(query)
    if query == "" or lowerQuery == "me" or lowerQuery == "myself" then
        return fallbackPlayer
    end
    if lowerQuery == "random" then
        return getRandomPlayer({ [LocalPlayer.UserId] = true }) or fallbackPlayer
    end

    local q = lowerQuery
    local best = nil

    for _, p in ipairs(Players:GetPlayers()) do
        local name = string.lower(p.Name)
        local display = string.lower(p.DisplayName or p.Name)
        if name == q or display == q then return p end
        if not best and (string.sub(name, 1, #q) == q or string.sub(display, 1, #q) == q) then
            best = p
        end
    end

    if best then return best end

    for _, p in ipairs(Players:GetPlayers()) do
        local name = string.lower(p.Name)
        local display = string.lower(p.DisplayName or p.Name)
        if string.find(name, q, 1, true) or string.find(display, q, 1, true) then
            return p
        end
    end

    return nil
end

local function splitWords(text)
    local words = {}
    for word in string.gmatch(trim(text), "%S+") do
        table.insert(words, word)
    end
    return words
end

local function parseVector3(text)
    local nums = {}
    for num in string.gmatch(tostring(text or ""), "[-+]?%d+%.?%d*") do
        table.insert(nums, tonumber(num))
    end
    if #nums >= 3 then
        return Vector3.new(nums[1], nums[2], nums[3])
    end
    return nil
end

local function getFrontPosition(targetPlayer, distance)
    local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return nil end

    local look = targetRoot.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end

    return targetRoot.Position + (flat.Unit * distance)
end

local walkJob = 0
local function smartWalkTo(position, reason, onArrive, arriveDistance)
    if not position then return false end
    walkJob += 1
    local thisJob = walkJob
    arriveDistance = arriveDistance or (CONFIG.PATH_ARRIVE_DISTANCE + 1.5)

    emotes:StopSit(0.1)
    emotes:StopIdle(0.1)
    local started = smartWalker:Start(position, reason or "command", true)

    if onArrive then
        task.spawn(function()
            local startedAt = tick()
            local lastDirectMove = 0
            local arrived = false

            while walkJob == thisJob and tick() - startedAt < 25 do
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local dist = root and (root.Position - position).Magnitude or math.huge

                if dist <= arriveDistance then
                    arrived = true
                    break
                end

                -- If pathfinding got close but stopped early, do a tiny direct final correction.
                if root and hum and not smartWalker.active and dist <= (arriveDistance + 6) then
                    if tick() - lastDirectMove > 0.35 then
                        hum:MoveTo(position)
                        lastDirectMove = tick()
                    end
                elseif not smartWalker.active and tick() - startedAt > 1.0 then
                    break
                end

                task.wait(0.1)
            end

            if walkJob == thisJob and arrived then
                onArrive()
            elseif walkJob == thisJob then
                console:Warn("Could not reach target position for " .. tostring(reason or "command"))
            end
        end)
    end

    return started
end

local function facePointOnce(point)
    if not point then return end

    -- One-time turn only. Do not keep LookController active / AutoRotate locked.
    lookController:Release()

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local origin = root.Position
    local target = Vector3.new(point.X, origin.Y, point.Z)
    if (target - origin).Magnitude > 0.15 then
        root.CFrame = CFrame.lookAt(origin, target)
    end
    if hum then
        pcall(function() hum.AutoRotate = true end)
    end
end

local function facePlayerNow(targetPlayer)
    local targetRoot = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end
    lookController:FacePoint(targetRoot.Position)
end

local function facePlayerLookPositionOnce(targetPlayer)
    local char = targetPlayer and targetPlayer.Character
    local targetRoot = char and char:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return end

    -- Other players' exact camera direction is not replicated, so use Head look when available,
    -- then fall back to HumanoidRootPart look direction.
    local head = char:FindFirstChild("Head")
    local lookSource = head or targetRoot
    local look = lookSource.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.05 then
        local rootLook = targetRoot.CFrame.LookVector
        flat = Vector3.new(rootLook.X, 0, rootLook.Z)
    end
    if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end

    -- Look at the same world direction/point that the target is looking at.
    facePointOnce(targetRoot.Position + (flat.Unit * 80))
end

local function kneelInFrontOf(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then
        console:Warn("Kneel target not found")
        return
    end

    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        console:Warn("Kneel target has no root")
        return
    end

    followEnabled = false
    currentFollowTarget = nil
    followMoving = false

    -- In front of the target and closer than before, but not inside them.
    local kneelPos = getFrontPosition(targetPlayer, CONFIG.KNEEL_DISTANCE)
    smartWalkTo(kneelPos, "kneel", function()
        facePlayerNow(targetPlayer)
        emotes:PlayKneel()
        lookController:LookAtPlayer(targetPlayer, CONFIG.LOOK_AFTER_RESPONSE)
        console:Info("Kneeling in front of " .. targetPlayer.Name)
    end, 1.35)
end

local function sitAtTarget(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then
        console:Warn("SitAt target not found")
        return
    end

    local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        console:Warn("SitAt target has no root")
        return
    end

    followEnabled = false
    currentFollowTarget = nil
    followMoving = false

    -- ONLY in front of the target: target's own LookVector decides the position.
    local sitPos = getFrontPosition(targetPlayer, CONFIG.SITAT_DISTANCE)
    smartWalkTo(sitPos, "sitat", function()
        -- Face the same direction/point the target is looking at, once. Do not lock looking after.
        facePlayerLookPositionOnce(targetPlayer)
        emotes:PlaySit()
        lookController:Release()
        console:Info("Sitting in front of " .. targetPlayer.Name .. " and facing their look direction")
    end, 1.15)
end

local spinning = false
local function spinBot(seconds)
    seconds = clamp(tonumber(seconds) or 3, 0.5, 15)
    spinning = false
    task.wait()
    spinning = true
    console:Info("Spinning for " .. tostring(seconds) .. "s")

    task.spawn(function()
        local _, hum, root
        local oldAutoRotate
        local finish = tick() + seconds
        while spinning and tick() < finish do
            local char = LocalPlayer.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            root = char and char:FindFirstChild("HumanoidRootPart")
            if hum and oldAutoRotate == nil then
                oldAutoRotate = hum.AutoRotate
                hum.AutoRotate = false
            end
            if root then
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(28), 0)
            end
            RunService.Heartbeat:Wait()
        end
        spinning = false
        if hum and oldAutoRotate ~= nil then
            pcall(function() hum.AutoRotate = oldAutoRotate end)
        end
    end)
end

local function getPingMs()
    local ping = nil
    pcall(function()
        ping = math.floor((LocalPlayer:GetNetworkPing() or 0) * 1000 + 0.5)
    end)
    return ping
end

local talkRandomSession = 0
local function startTalkRandom(requester)
    local exclude = { [LocalPlayer.UserId] = true }
    if requester then exclude[requester.UserId] = true end

    local target = getRandomPlayer(exclude) or getRandomPlayer({ [LocalPlayer.UserId] = true })
    if not target then
        console:Warn("No random player found")
        return
    end

    talkRandomSession += 1
    local session = talkRandomSession
    local wasWhitelisted = whitelist[target.UserId] == true
    local previousPrivateMode = privateMode

    botEnabled = true
    privateMode = true
    triggerRequired = false
    whitelist[target.UserId] = true

    followEnabled = false
    currentFollowTarget = nil
    followMoving = false

    console:Info("TalkRandom: approaching " .. target.Name .. " for 60s")

    local talkPos = getFrontPosition(target, math.max(CONFIG.KNEEL_DISTANCE, 3.5))
    smartWalkTo(talkPos, "talkrandom", function()
        facePlayerNow(target)
        lookController:LookAtPlayer(target, CONFIG.LOOK_AFTER_RESPONSE)

        task.spawn(function()
            local opener = nil
            if trim(CONFIG.API_KEY) ~= "" then
                opener = select(1, queryAI(LocalPlayer.Name, "Start a short casual Roblox conversation with " .. target.Name .. ". One sentence under 80 characters. Do not mention you are AI.", LocalPlayer.UserId))
            end
            opener = opener or ("yo " .. (target.DisplayName or target.Name) .. ", what's up?")
            if #opener > 140 then opener = string.sub(opener, 1, 137) .. "..." end
            sendAsPlayer(opener)
        end)
    end, 1.8)

    task.delay(60, function()
        if session ~= talkRandomSession then return end

        triggerRequired = true -- restore normal trigger requirement; ! prefix still works too.
        privateMode = previousPrivateMode
        if not wasWhitelisted then whitelist[target.UserId] = nil end

        console:Info("TalkRandom ended. Returning to " .. (requester and requester.Name or "requester"))
        if requester and requester.Parent == Players then
            comeToPlayer(requester)
        end
    end)
end

local function setSystemsEnabled(on)
    botEnabled = on
    smartWalkingEnabled = on
    lookAtEnabled = on
    followVisualEnabled = on
    idleEmoteEnabled = on

    if not on then
        followEnabled = false
        currentFollowTarget = nil
        followMoving = false
        smartWalker:Stop(true)
        followVisualizer:Clear()
        lookController:Release()
        emotes:StopSit(0.1)
        emotes:StopIdle(0.1)
        spinning = false
    end

    console:Success(on and "Systems ON" or "Systems OFF")
end

local function handleCommand(player, message)
    if not whitelist[player.UserId] then return false end

    local raw = trim(message)
    local bangPrompt = getBangPrompt(raw)
    local prefixed = bangPrompt ~= nil
    local cmdLine = prefixed and bangPrompt or raw
    local lowerLine = string.lower(trim(cmdLine))
    local words = splitWords(cmdLine)
    local command = words[1] and string.lower(words[1]) or ""
    local argText = ""
    if #cmdLine > #command then
        argText = trim(string.sub(cmdLine, #words[1] + 1))
    end

    local myChar = LocalPlayer.Character
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")

    local function exactNoArg(name)
        return command == name and #words == 1
    end

    local function oneOptionalArg(name)
        return command == name and #words <= 2
    end

    local function stopMovementForPose()
        followEnabled = false
        currentFollowTarget = nil
        followMoving = false
        smartWalker:Stop(true)
    end

    -- Rejoin aliases
    if lowerLine == "-rj" or (prefixed and exactNoArg("rj")) then
        rejoinSameServer()
        return true
    end

    -- Global on/off. Commands still work while bot is off, so !on can recover it.
    if prefixed and exactNoArg("on") then
        setSystemsEnabled(true)
        return true
    elseif prefixed and exactNoArg("off") then
        setSystemsEnabled(false)
        return true
    end

    if prefixed and exactNoArg("status") then
        local ping = getPingMs()
        local apiStatus = trim(CONFIG.API_KEY) ~= "" and "Has API" or "NO API"
        local botStatus = botEnabled and "ON" or "OFF"
        sendAsPlayer("Ping: " .. (ping and (tostring(ping) .. "ms") or "?") .. " | Bot: " .. botStatus .. " | API: " .. apiStatus)
        return true
    end

    if prefixed and exactNoArg("talkrandom") then
        startTalkRandom(player)
        return true
    end

    -- Sit / stand / kneel poses. Prefixed versions must be exact unless the command supports a parameter.
    if (not prefixed and lowerLine == "sit") or (prefixed and exactNoArg("sit")) then
        if myHum then
            stopMovementForPose()
            emotes:PlaySit()
            console:Info(player.Name .. " used command: sit emote")
        end
        return true
    end

    if prefixed and oneOptionalArg("sitat") then
        local target = findPlayerByName(argText, player)
        if target then
            sitAtTarget(target)
        else
            console:Warn("SitAt target not found: " .. argText)
        end
        return true
    end

    if (not prefixed and lowerLine == "kneel") or (prefixed and oneOptionalArg("kneel")) then
        if prefixed and argText ~= "" then
            local target = findPlayerByName(argText, player)
            if target then
                kneelInFrontOf(target)
            else
                console:Warn("Kneel target not found: " .. argText)
            end
        elseif myHum then
            stopMovementForPose()
            emotes:PlayKneel()
            console:Info(player.Name .. " used command: kneel emote")
        end
        return true
    end

    if (not prefixed and (lowerLine == "stand" or lowerLine == "stop sit")) or (prefixed and exactNoArg("stand")) then
        emotes:StopSit(0.1)
        emotes:StartIdle()
        console:Info(player.Name .. " stopped pose emote")
        return true
    end

    if (not prefixed and lowerLine == "jump") or (prefixed and exactNoArg("jump")) then
        if myHum then
            smartWalker:Stop(true)
            emotes:StopSit(0.1)
            emotes:StopIdle(0.1)
            myHum.Jump = true
            console:Info(player.Name .. " used command: jump")
        end
        return true
    end

    -- Follow / unfollow / come.
    if (not prefixed and lowerLine == "follow") or (prefixed and oneOptionalArg("follow")) then
        local target = prefixed and findPlayerByName(argText, player) or player
        if target then
            followPlayer(target)
        else
            console:Warn("Follow target not found: " .. argText)
        end
        return true
    end

    if (not prefixed and lowerLine == "unfollow") or (prefixed and exactNoArg("unfollow")) then
        unfollowPlayer()
        return true
    end

    if not prefixed and (lowerLine == "come here" or lowerLine == "come") then
        comeToPlayer(player)
        return true
    end

    if prefixed and command == "come" then
        if argText == "" then
            comeToPlayer(player)
            return true
        end
        local pos = parseVector3(argText)
        if pos then
            followEnabled = false
            currentFollowTarget = nil
            followMoving = false
            smartWalkTo(pos, "come-position")
            console:Info("Walking to position: " .. tostring(math.floor(pos.X)) .. ", " .. tostring(math.floor(pos.Y)) .. ", " .. tostring(math.floor(pos.Z)))
            return true
        end
        -- Not a valid !come command, so allow it to become an AI prompt.
        return false
    end

    -- Utility commands.
    if prefixed and command == "runemote" and #words == 2 then
        local animId = tostring(words[2] or ""):match("%d+")
        if animId then
            stopMovementForPose()
            emotes:PlayCustom(animId)
            console:Info("Running custom emote " .. animId)
            return true
        end
        return false
    end

    if prefixed and command == "say" then
        if argText ~= "" then
            sendAsPlayer(argText)
        else
            console:Warn("!say needs text")
        end
        return true
    end

    if prefixed and exactNoArg("ping") then
        local ping = getPingMs()
        sendAsPlayer(ping and ("Ping: " .. tostring(ping) .. "ms") or "Ping unavailable")
        return true
    end

    if prefixed and command == "spin" and #words <= 2 then
        if #words == 1 or tonumber(words[2]) then
            spinBot(words[2])
            return true
        end
        return false
    end

    if prefixed and (command == "lookat" or command == "look") and #words <= 2 then
        local target = findPlayerByName(argText, player)
        if target then
            lookController:LookAtPlayer(target, CONFIG.LOOK_AFTER_RESPONSE)
            console:Info("Looking at " .. target.Name)
        else
            console:Warn("Look target not found: " .. argText)
        end
        return true
    end

    if (not prefixed and lowerLine == "stop emote") or (prefixed and lowerLine == "stop emote") then
        spinning = false
        emotes:StopSit(0.1)
        emotes:StopIdle(0.1)
        console:Info("Stopped emotes")
        return true
    end

    -- Important: for !prefix, unknown/long command-looking text becomes an AI prompt.
    return false
end

local function onPlayerAddedWithCommands(player)
    player.Chatted:Connect(function(message)
        local wasCommand = handleCommand(player, message)
        if not wasCommand then
            -- Remember normal chat from every player, not just the person currently using the bot.
            rememberPlayerMessage(player, message)
            handleMessage(player, message)
        end

        if followOnTrigger and string.sub(string.lower(message), 1, #CONFIG.TRIGGER) == string.lower(CONFIG.TRIGGER) then
            if whitelist[player.UserId] then followPlayer(player) end
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do onPlayerAddedWithCommands(p) end
Players.PlayerAdded:Connect(onPlayerAddedWithCommands)

--// Chat readiness check
task.spawn(function()
    local chatReady = false
    console:Info("Waiting for chat system...")

    pcall(function()
        local TCS = game:GetService("TextChatService")
        local gen = TCS.TextChannels:WaitForChild("RBXGeneral", 10)
        if gen then
            chatReady = true
            console:Success("TextChatService ready")
        end
    end)

    if not chatReady then
        pcall(function()
            local ce = ReplicatedStorage:WaitForChild("DefaultChatSystemChatEvents", 10)
            if ce then
                chatReady = true
                console:Success("Legacy Chat ready")
            end
        end)
    end

    if not chatReady then
        console:Warn("Chat system not detected; responses may not send")
        showWarning("Chat system not ready. Responses may not send.", 4)
    end
end)

--// Better draggable/resizable UI
local menuOk, menuErr = pcall(function()
    local gui = Instance.new("ScreenGui")
    gui.Name = "SpectraUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    safeParent(gui)

    local UI = {
        bg = Color3.fromRGB(18, 24, 38),
        panel = Color3.fromRGB(24, 32, 48),
        panel2 = Color3.fromRGB(30, 41, 59),
        card = Color3.fromRGB(35, 48, 68),
        input = Color3.fromRGB(15, 23, 42),
        stroke = Color3.fromRGB(71, 85, 105),
        muted = Color3.fromRGB(148, 163, 184),
        text = Color3.fromRGB(226, 232, 240),
        accent = CONFIG.ACCENT,
        danger = Color3.fromRGB(251, 113, 133),
        ok = Color3.fromRGB(52, 211, 153),
        radius = 16,
    }

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(CONFIG.DEFAULT_W, CONFIG.DEFAULT_H)
    frame.Position = UDim2.new(0.5, -CONFIG.DEFAULT_W / 2, 0.5, -CONFIG.DEFAULT_H / 2)
    frame.AnchorPoint = Vector2.new(0, 0)
    frame.BackgroundColor3 = UI.bg
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Visible = false
    frame.Parent = gui
    addCorner(frame, UI.radius)
    addStroke(frame, UI.stroke, 1, 0.15)

    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 56)
    topBar.BackgroundColor3 = UI.panel
    topBar.BorderSizePixel = 0
    topBar.Parent = frame
    addCorner(topBar, UI.radius)

    local topFix = Instance.new("Frame")
    topFix.Size = UDim2.new(1, 0, 0, 10)
    topFix.Position = UDim2.new(0, 0, 1, -10)
    topFix.BackgroundColor3 = topBar.BackgroundColor3
    topFix.BorderSizePixel = 0
    topFix.Parent = topBar

    local title = makeText(topBar, {
        Size = UDim2.new(1, -150, 0, 28),
        Position = UDim2.fromOffset(18, 6),
        Text = "Spectra",
        TextColor3 = UI.text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
    })

    local subtitle = makeText(topBar, {
        Size = UDim2.new(1, -150, 0, 18),
        Position = UDim2.fromOffset(18, 31),
        Text = "AI companion controls",
        TextColor3 = UI.muted,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    })

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(10, 10)
    statusDot.Position = UDim2.new(1, -84, 0.5, -5)
    statusDot.BackgroundColor3 = UI.ok
    statusDot.BorderSizePixel = 0
    statusDot.Parent = topBar
    addCorner(statusDot, 99)

    local miniBtn = makeButton(topBar, "—", UI.panel)
    miniBtn.Size = UDim2.fromOffset(24, 24)
    miniBtn.Position = UDim2.new(1, -64, 0.5, -12)
    miniBtn.BackgroundTransparency = 1
    miniBtn.TextColor3 = UI.muted
    miniBtn.TextSize = 14

    local closeBtn = makeButton(topBar, "×", UI.panel)
    closeBtn.Size = UDim2.fromOffset(24, 24)
    closeBtn.Position = UDim2.new(1, -32, 0.5, -12)
    closeBtn.BackgroundTransparency = 1
    closeBtn.TextColor3 = UI.muted

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -20, 0, 42)
    tabBar.Position = UDim2.fromOffset(10, 60)
    tabBar.BackgroundColor3 = UI.panel2
    tabBar.BorderSizePixel = 0
    tabBar.Parent = frame
    addCorner(tabBar, 12)

    local tabs = {}
    local pages = {}
    local tabNames = { "CONSOLE", "JSON", "SETTINGS", "PLAYERS" }

    for i, name in ipairs(tabNames) do
        local tab = makeButton(tabBar, string.sub(name,1,1) .. string.lower(string.sub(name,2)), UI.panel2)
        tab.Size = UDim2.new(1 / #tabNames, 0, 1, 0)
        tab.Position = UDim2.new((i - 1) / #tabNames, 0, 0, 0)
        tab.BackgroundTransparency = 1
        tab.TextColor3 = (i == 1) and UI.accent or UI.muted
        tab.TextSize = 11
        tabs[name] = tab
    end

    local tabInd = Instance.new("Frame")
    tabInd.Size = UDim2.new(1 / #tabNames, -6, 0, 2)
    tabInd.Position = UDim2.new(0, 3, 1, -2)
    tabInd.BackgroundColor3 = UI.accent
    tabInd.BorderSizePixel = 0
    tabInd.Parent = tabBar
    addCorner(tabInd, 99)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -24, 1, -114)
    content.Position = UDim2.fromOffset(12, 108)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = true
    content.Parent = frame

    local function makePage(name)
        local p = Instance.new("Frame")
        p.Name = name .. "Page"
        p.Size = UDim2.new(1, 0, 1, 0)
        p.BackgroundTransparency = 1
        p.Visible = name == "CONSOLE"
        p.Parent = content
        pages[name] = p
        return p
    end

    local logsPage = makePage("CONSOLE")
    local jsonPage = makePage("JSON")
    local settingsPage = makePage("SETTINGS")
    local playersPage = makePage("PLAYERS")

    local function selectTab(name)
        local index = 1
        for i, n in ipairs(tabNames) do
            local active = n == name
            pages[n].Visible = active
            tabs[n].TextColor3 = active and UI.accent or UI.muted
            if active then index = i end
        end
        tween(tabInd, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new((index - 1) / #tabNames, 3, 1, -2),
            Size = UDim2.new(1 / #tabNames, -6, 0, 2),
        })
        if name == "JSON" then rawViewer:Render() end
    end

    for _, n in ipairs(tabNames) do
        tabs[n].MouseButton1Click:Connect(function() selectTab(n) end)
    end

    -- Console page
    local statsBar = Instance.new("Frame")
    statsBar.Size = UDim2.new(1, 0, 0, 24)
    statsBar.BackgroundColor3 = UI.panel2
    statsBar.BorderSizePixel = 0
    statsBar.Parent = logsPage
    addCorner(statsBar, 7)

    local statsL = makeText(statsBar, {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        Text = "Req: 0  •  Err: 0  •  Lines: 0",
        TextColor3 = Color3.fromRGB(105, 105, 135),
        TextSize = 10,
    })
    console.ui.statsLabel = statsL

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Size = UDim2.new(1, 0, 1, -30)
    logScroll.Position = UDim2.fromOffset(0, 30)
    logScroll.BackgroundColor3 = UI.input
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 4
    logScroll.ScrollBarImageColor3 = UI.stroke
    logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    logScroll.CanvasSize = UDim2.fromOffset(0, 0)
    logScroll.Parent = logsPage
    addCorner(logScroll, 7)
    addPadding(logScroll, 6, 4, 5, 5)
    console.ui.logContainer = logScroll

    local logLay = Instance.new("UIListLayout")
    logLay.SortOrder = Enum.SortOrder.LayoutOrder
    logLay.Padding = UDim.new(0, 1)
    logLay.Parent = logScroll

    local empL = makeText(logScroll, {
        Name = "EmptyState",
        Size = UDim2.new(1, 0, 0, 30),
        Text = "Waiting for input...",
        TextColor3 = Color3.fromRGB(60, 60, 84),
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    -- JSON page
    local jsonTop = Instance.new("Frame")
    jsonTop.Size = UDim2.new(1, 0, 0, 58)
    jsonTop.BackgroundColor3 = UI.panel2
    jsonTop.BorderSizePixel = 0
    jsonTop.Parent = jsonPage
    addCorner(jsonTop, 7)

    local jsonMeta = makeText(jsonTop, {
        Size = UDim2.new(1, -230, 0, 25),
        Position = UDim2.fromOffset(8, 4),
        Text = "No AI response captured yet.",
        TextColor3 = Color3.fromRGB(135, 135, 165),
        Font = Enum.Font.Code,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    rawViewer.ui.meta = jsonMeta

    local jsonModeLabel = makeText(jsonTop, {
        Size = UDim2.new(1, -230, 0, 20),
        Position = UDim2.fromOffset(8, 30),
        Text = "Viewing: RESPONSE (pretty)",
        TextColor3 = UI.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
    })
    rawViewer.ui.modeLabel = jsonModeLabel

    local btnResponse = makeButton(jsonTop, "RESPONSE", UI.accent)
    btnResponse.Size = UDim2.fromOffset(70, 24)
    btnResponse.Position = UDim2.new(1, -218, 0, 7)

    local btnRequest = makeButton(jsonTop, "REQUEST", UI.card)
    btnRequest.Size = UDim2.fromOffset(64, 24)
    btnRequest.Position = UDim2.new(1, -144, 0, 7)

    local btnFormat = makeButton(jsonTop, "RAW", UI.card)
    btnFormat.Size = UDim2.fromOffset(50, 24)
    btnFormat.Position = UDim2.new(1, -76, 0, 7)

    local btnClearJson = makeButton(jsonTop, "CLR", Color3.fromRGB(56, 28, 34))
    btnClearJson.Size = UDim2.fromOffset(38, 24)
    btnClearJson.Position = UDim2.new(1, -42, 0, 34)
    btnClearJson.TextColor3 = Color3.fromRGB(255, 150, 150)

    local jsonScroll = Instance.new("ScrollingFrame")
    jsonScroll.Size = UDim2.new(1, 0, 1, -66)
    jsonScroll.Position = UDim2.fromOffset(0, 66)
    jsonScroll.BackgroundColor3 = UI.input
    jsonScroll.BorderSizePixel = 0
    jsonScroll.ScrollBarThickness = 4
    jsonScroll.ScrollBarImageColor3 = UI.stroke
    jsonScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    jsonScroll.CanvasSize = UDim2.fromOffset(0, 0)
    jsonScroll.Parent = jsonPage
    addCorner(jsonScroll, 7)
    addPadding(jsonScroll, 6, 6, 6, 6)

    local jsonBox = Instance.new("TextBox")
    jsonBox.Size = UDim2.new(1, -10, 0, 320)
    jsonBox.BackgroundTransparency = 1
    jsonBox.BorderSizePixel = 0
    jsonBox.ClearTextOnFocus = false
    jsonBox.MultiLine = true
    jsonBox.Text = "No response captured yet."
    jsonBox.TextColor3 = UI.text
    jsonBox.PlaceholderText = "Raw API response will appear here..."
    jsonBox.PlaceholderColor3 = UI.muted
    jsonBox.Font = Enum.Font.Code
    jsonBox.TextSize = 10
    jsonBox.TextXAlignment = Enum.TextXAlignment.Left
    jsonBox.TextYAlignment = Enum.TextYAlignment.Top
    jsonBox.TextWrapped = false
    jsonBox.Parent = jsonScroll

    local jsonLay = Instance.new("UIListLayout")
    jsonLay.SortOrder = Enum.SortOrder.LayoutOrder
    jsonLay.Parent = jsonScroll

    rawViewer.ui.box = jsonBox

    btnResponse.MouseButton1Click:Connect(function()
        rawViewer.mode = "response"
        btnResponse.BackgroundColor3 = UI.accent
        btnRequest.BackgroundColor3 = UI.card
        rawViewer:Render()
    end)

    btnRequest.MouseButton1Click:Connect(function()
        rawViewer.mode = "request"
        btnResponse.BackgroundColor3 = UI.card
        btnRequest.BackgroundColor3 = UI.accent
        rawViewer:Render()
    end)

    btnFormat.MouseButton1Click:Connect(function()
        rawViewer.pretty = not rawViewer.pretty
        btnFormat.Text = rawViewer.pretty and "RAW" or "PRETTY"
        rawViewer:Render()
    end)

    btnClearJson.MouseButton1Click:Connect(function()
        rawViewer:Clear()
        console:Info("JSON viewer cleared")
    end)

    -- Settings page helpers
    local sScroll = Instance.new("ScrollingFrame")
    sScroll.Size = UDim2.new(1, 0, 1, 0)
    sScroll.BackgroundTransparency = 1
    sScroll.BorderSizePixel = 0
    sScroll.ScrollBarThickness = 4
    sScroll.ScrollBarImageColor3 = UI.stroke
    sScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sScroll.CanvasSize = UDim2.fromOffset(0, 0)
    sScroll.Parent = settingsPage
    addPadding(sScroll, 2, 6, 2, 8)

    local sLay = Instance.new("UIListLayout")
    sLay.SortOrder = Enum.SortOrder.LayoutOrder
    sLay.Padding = UDim.new(0, 7)
    sLay.Parent = sScroll

    local settingsSections = {}
    local currentSection = nil
    local function layoutOrder(order)
        return math.floor((tonumber(order) or 0) * 100)
    end

    local function setSectionCollapsed(section, collapsed)
        section.collapsed = collapsed
        section.header.Text = (collapsed and "▸  " or "▾  ") .. section.title
        for _, item in ipairs(section.items) do
            if item and item.Parent then
                item.Visible = not collapsed
            end
        end
    end

    local function trackSetting(item)
        if currentSection then
            table.insert(currentSection.items, item)
        end
        return item
    end

    local function mkSection(order, text)
        local h = makeButton(sScroll, "▾  " .. text, UI.panel2)
        h.Size = UDim2.new(1, -4, 0, 36)
        h.LayoutOrder = layoutOrder(order)
        h.TextColor3 = UI.text
        h.Font = Enum.Font.GothamBold
        h.TextSize = 12
        h.TextXAlignment = Enum.TextXAlignment.Left
        addPadding(h, 12, 12, 0, 0)
        addStroke(h, UI.stroke, 1, 0.45)

        local section = { header = h, title = text, items = {}, collapsed = false }
        table.insert(settingsSections, section)
        currentSection = section

        h.MouseButton1Click:Connect(function()
            setSectionCollapsed(section, not section.collapsed)
        end)
        return h
    end

    local function mkToggle(order, label, defaultOn, cb)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 44)
        row.LayoutOrder = layoutOrder(order)
        row.BackgroundColor3 = UI.card
        row.BorderSizePixel = 0
        row.Parent = sScroll
        trackSetting(row)
        addCorner(row, 12)

        makeText(row, {
            Size = UDim2.new(1, -104, 1, 0),
            Position = UDim2.fromOffset(14, 0),
            Text = label,
            TextColor3 = UI.text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextWrapped = true,
        })

        local btn = makeButton(row, defaultOn and "ON" or "OFF", defaultOn and UI.ok or UI.panel2)
        btn.Size = UDim2.fromOffset(62, 26)
        btn.Position = UDim2.new(1, -76, 0.5, -13)
        btn.TextSize = 9

        local isOn = defaultOn
        btn.MouseButton1Click:Connect(function()
            isOn = not isOn
            btn.Text = isOn and "ON" or "OFF"
            btn.BackgroundColor3 = isOn and UI.ok or UI.panel2
            cb(isOn)
        end)
        return row
    end

    local function mkTextInput(order, label, default, placeholder, height, multi, onApply)
        local labelObj = makeText(sScroll, {
            Size = UDim2.new(1, -4, 0, 22),
            LayoutOrder = layoutOrder(order),
            Text = label,
            TextColor3 = UI.muted,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
        })
        trackSetting(labelObj)

        local box = Instance.new("TextBox")
        box.Size = UDim2.new(1, -4, 0, height or 38)
        box.LayoutOrder = layoutOrder(order) + 1
        box.BackgroundColor3 = UI.input
        box.BorderSizePixel = 0
        box.ClearTextOnFocus = false
        box.MultiLine = multi == true
        box.Text = tostring(default or "")
        box.PlaceholderText = placeholder or ""
        box.PlaceholderColor3 = UI.muted
        box.TextColor3 = UI.text
        box.Font = Enum.Font.Code
        box.TextSize = 11
        box.TextXAlignment = Enum.TextXAlignment.Left
        box.TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
        box.Parent = sScroll
        trackSetting(box)
        addCorner(box, 12)
        addPadding(box, 8, 8, multi and 6 or 0, 0)

        local apply = makeButton(sScroll, "Save " .. label, UI.accent)
        apply.Size = UDim2.new(1, -4, 0, 30)
        apply.LayoutOrder = layoutOrder(order) + 2
        trackSetting(apply)
        apply.MouseButton1Click:Connect(function()
            onApply(box.Text, box)
        end)
        return box, apply
    end

    mkSection(1, "GENERAL")
    mkToggle(2, "Bot Enabled", true, function(on)
        botEnabled = on
        statusDot.BackgroundColor3 = on and UI.ok or UI.danger
        console:Success(on and "Bot enabled" or "Bot disabled")
    end)
    mkToggle(3, "Show Thinking Message", false, function(on)
        showThinking = on
        console:Info(on and "Thinking message ON" or "Thinking message OFF")
    end)
    mkToggle(4, "Private Mode (whitelist only)", false, function(on)
        privateMode = on
        console:Info(on and "Private mode ON" or "Public mode ON")
    end)
    mkToggle(5, "Disable Trigger Word", false, function(on)
        triggerRequired = not on
        if on and not privateMode then
            showWarning("Trigger disabled while public. This can spam API requests.", 3)
            console:Warn("Trigger disabled without private mode")
        else
            console:Info(on and "Trigger disabled" or "Trigger enabled")
        end
    end)
    mkToggle(6, "Auto Send AI Response To Chat", true, function(on)
        autoSendChat = on
        console:Info(on and "Auto-send ON" or "Auto-send OFF")
    end)
    mkToggle(7, "Trim Long Responses", true, function(on)
        trimResponses = on
        console:Info(on and "Response trim ON" or "Response trim OFF")
    end)
    mkToggle(8, "Player Memory", CONFIG.MEMORY_ENABLED, function(on)
        memoryEnabled = on
        console:Info(on and "Player memory ON" or "Player memory OFF")
    end)

    local memoryLimitBox = mkTextInput(8.2, "MEMORY LIMIT PER PLAYER", tostring(memoryLimit), "5", 34, false, function(v)
        memoryLimit = math.max(1, math.floor(tonumber(v) or memoryLimit or 5))
        rebuildMemoryLimits()
        console:Success("Memory limit set to " .. tostring(memoryLimit) .. " per player")
    end)

    local clearMemoryBtn = makeButton(sScroll, "Clear player memory", Color3.fromRGB(80, 38, 48))
    clearMemoryBtn.Size = UDim2.new(1, -4, 0, 24)
    clearMemoryBtn.LayoutOrder = layoutOrder(8.5)
    trackSetting(clearMemoryBtn)
    clearMemoryBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
    clearMemoryBtn.MouseButton1Click:Connect(function()
        clearPlayerMemory()
        console:Info("Player memory cleared")
    end)

    mkSection(10, "MOVEMENT / COMMANDS")
    mkToggle(11, "Idle Standing Emote", true, function(on)
        idleEmoteEnabled = on
        if not on then emotes:StopIdle(0.1) end
        console:Info(on and "Idle emote ON" or "Idle emote OFF")
    end)
    mkToggle(12, "Sit Command Emote", true, function(on)
        sitEmoteEnabled = on
        if not on then emotes:StopSit(0.1) end
        console:Info(on and "Sit emote ON" or "Sit emote OFF")
    end)
    mkToggle(13, "Follow On Trigger", false, function(on)
        followOnTrigger = on
        console:Info(on and "Follow on trigger ON" or "Follow on trigger OFF")
    end)
    mkToggle(13.25, "Look At Speaker While Responding", CONFIG.LOOK_AT_ENABLED, function(on)
        lookAtEnabled = on
        if not on then lookController:Release() end
        console:Info(on and "Look-at system ON" or "Look-at system OFF")
    end)
    mkToggle(13.5, "Smart Walking / Pathfinding", CONFIG.SMART_WALKING_ENABLED, function(on)
        smartWalkingEnabled = on
        smartWalker:Stop(true)
        console:Info(on and "Smart walking ON" or "Smart walking OFF")
    end)
    mkToggle(13.75, "Show Smart Follow Circle", CONFIG.FOLLOW_VISUAL_ENABLED, function(on)
        followVisualEnabled = on
        if not on then followVisualizer:Clear() end
        console:Info(on and "Follow circle ON" or "Follow circle OFF")
    end)

    local idleBox = mkTextInput(14, "IDLE ANIMATION ID", CONFIG.IDLE_ANIM_ID, "75730360108389", 34, false, function(v)
        CONFIG.IDLE_ANIM_ID = trim(v)
        emotes:StopIdle(0.05)
        emotes.idleTrack = nil
        console:Success("Idle animation ID updated")
    end)

    local sitBox = mkTextInput(15, "SIT ANIMATION ID", CONFIG.SIT_ANIM_ID, "74543120303961", 34, false, function(v)
        CONFIG.SIT_ANIM_ID = trim(v)
        emotes:StopSit(0.05)
        emotes.sitTrack = nil
        console:Success("Sit animation ID updated")
    end)

    local kneelBox = mkTextInput(15.5, "KNEEL ANIMATION ID", CONFIG.KNEEL_ANIM_ID, "94599985584623", 34, false, function(v)
        CONFIG.KNEEL_ANIM_ID = trim(v)
        emotes:StopSit(0.05)
        emotes.sitTrack = nil
        console:Success("Kneel animation ID updated")
    end)

    local kneelDistanceBox = mkTextInput(15.65, "KNEEL DISTANCE", tostring(CONFIG.KNEEL_DISTANCE), "3.25", 34, false, function(v)
        CONFIG.KNEEL_DISTANCE = clamp(tonumber(v) or CONFIG.KNEEL_DISTANCE, 2, 10)
        console:Success("Kneel distance set to " .. tostring(CONFIG.KNEEL_DISTANCE))
    end)

    local sitAtDistanceBox = mkTextInput(15.8, "SITAT DISTANCE", tostring(CONFIG.SITAT_DISTANCE), "2.75", 34, false, function(v)
        CONFIG.SITAT_DISTANCE = clamp(tonumber(v) or CONFIG.SITAT_DISTANCE, 2, 8)
        console:Success("SitAt distance set to " .. tostring(CONFIG.SITAT_DISTANCE))
    end)

    local rangeBox = mkTextInput(16, "FOLLOW DISTANCE", tostring(followRange), "6", 34, false, function(v)
        followRange = math.max(2, tonumber(v) or followRange)
        followBuffer = clamp(followBuffer, 0.25, math.max(0.25, followRange - 1))
        console:Success("Follow distance set to " .. tostring(followRange))
    end)

    local followBufferBox = mkTextInput(16.15, "FOLLOW BUFFER / DEAD-ZONE", tostring(followBuffer), "1.25", 34, false, function(v)
        followBuffer = clamp(tonumber(v) or followBuffer, 0.25, math.max(0.25, followRange - 1))
        console:Success("Follow buffer set to " .. tostring(followBuffer))
    end)

    local stopFollowBtn = makeButton(sScroll, "Stop following", Color3.fromRGB(80, 38, 48))
    stopFollowBtn.Size = UDim2.new(1, -4, 0, 24)
    stopFollowBtn.LayoutOrder = layoutOrder(16.3)
    trackSetting(stopFollowBtn)
    stopFollowBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
    stopFollowBtn.MouseButton1Click:Connect(unfollowPlayer)

    local testSitBtn = makeButton(sScroll, "Test sit emote", UI.accent)
    testSitBtn.Size = UDim2.new(1, -4, 0, 24)
    testSitBtn.LayoutOrder = layoutOrder(16.4)
    trackSetting(testSitBtn)
    testSitBtn.MouseButton1Click:Connect(function()
        emotes:PlaySit()
    end)

    mkSection(20, "AI / API")
    local apiKeyBox = mkTextInput(21, "API KEY", CONFIG.API_KEY, "sk-or-v1-...", 34, false, function(v)
        CONFIG.API_KEY = trim(v)
        console:Success("API key updated")
    end)

    local modelBox = mkTextInput(22, "AI MODEL", CONFIG.MODEL, "openai/gpt-4o-mini", 34, false, function(v)
        CONFIG.MODEL = trim(v)
        console:Success("Model set to " .. CONFIG.MODEL)
    end)

    local tokensBox = mkTextInput(23, "MAX TOKENS", tostring(CONFIG.MAX_TOKENS), "150", 34, false, function(v)
        CONFIG.MAX_TOKENS = tonumber(v) or CONFIG.MAX_TOKENS
        console:Success("Max tokens set to " .. tostring(CONFIG.MAX_TOKENS))
    end)

    local tempBox = mkTextInput(23.3, "TEMPERATURE", tostring(CONFIG.TEMPERATURE), "0.35", 34, false, function(v)
        CONFIG.TEMPERATURE = clamp(tonumber(v) or CONFIG.TEMPERATURE, 0, 2)
        console:Success("Temperature set to " .. tostring(CONFIG.TEMPERATURE))
    end)

    local topPBox = mkTextInput(23.6, "TOP P", tostring(CONFIG.TOP_P), "0.85", 34, false, function(v)
        CONFIG.TOP_P = clamp(tonumber(v) or CONFIG.TOP_P, 0.05, 1)
        console:Success("Top P set to " .. tostring(CONFIG.TOP_P))
    end)

    local cooldownBox = mkTextInput(24, "COOLDOWN SECONDS", tostring(CONFIG.COOLDOWN), "3", 34, false, function(v)
        CONFIG.COOLDOWN = tonumber(v) or CONFIG.COOLDOWN
        console:Success("Cooldown set to " .. tostring(CONFIG.COOLDOWN))
    end)

    local triggerBox = mkTextInput(25, "TRIGGER WORD", CONFIG.TRIGGER, "bot", 34, false, function(v)
        CONFIG.TRIGGER = trim(v) ~= "" and trim(v) or CONFIG.TRIGGER
        console:Success("Trigger set to '" .. CONFIG.TRIGGER .. "'")
    end)

    local chatMethodBox = mkTextInput(26, "CHAT METHOD", CONFIG.CHAT_METHOD, "auto / textchat / legacy", 34, false, function(v)
        local m = string.lower(trim(v))
        if m == "auto" or m == "textchat" or m == "legacy" then
            CONFIG.CHAT_METHOD = m
            console:Success("Chat method set to " .. m)
        else
            console:Warn("Invalid chat method. Use auto, textchat, or legacy.")
        end
    end)

    local proxyBox = mkTextInput(27, "PROXY URL", CONFIG.PROXY_URL, "https://corsproxy.io/?url=", 34, false, function(v)
        CONFIG.PROXY_URL = trim(v)
        console:Success("Proxy URL updated")
    end)

    local promptBox = mkTextInput(28, "SYSTEM PROMPT", currentPrompt, "System prompt...", 86, true, function(v)
        if trim(v) ~= "" then
            currentPrompt = v
            console:Success("System prompt updated")
        else
            console:Warn("System prompt is empty")
        end
    end)

    mkSection(40, "MAINTENANCE")
    local clearConsoleBtn = makeButton(sScroll, "Clear console", Color3.fromRGB(80, 38, 48))
    clearConsoleBtn.Size = UDim2.new(1, -4, 0, 26)
    clearConsoleBtn.LayoutOrder = layoutOrder(41)
    trackSetting(clearConsoleBtn)
    clearConsoleBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
    clearConsoleBtn.MouseButton1Click:Connect(function()
        console:Clear()
        console:Info("Console cleared")
    end)

    local clearJsonBtn2 = makeButton(sScroll, "Clear JSON viewer", Color3.fromRGB(80, 38, 48))
    clearJsonBtn2.Size = UDim2.new(1, -4, 0, 26)
    clearJsonBtn2.LayoutOrder = layoutOrder(42)
    trackSetting(clearJsonBtn2)
    clearJsonBtn2.TextColor3 = Color3.fromRGB(255, 150, 150)
    clearJsonBtn2.MouseButton1Click:Connect(function()
        rawViewer:Clear()
        console:Info("JSON viewer cleared")
    end)

    -- Players page
    local pHeader = Instance.new("Frame")
    pHeader.Size = UDim2.new(1, 0, 0, 25)
    pHeader.BackgroundColor3 = Color3.fromRGB(17, 17, 27)
    pHeader.BorderSizePixel = 0
    pHeader.Parent = playersPage
    addCorner(pHeader, 7)

    makeText(pHeader, {
        Size = UDim2.new(1, -12, 1, 0),
        Position = UDim2.fromOffset(8, 0),
        Text = "PLAYERS IN SERVER - tap to toggle whitelist",
        TextColor3 = Color3.fromRGB(115, 115, 145),
        Font = Enum.Font.GothamBold,
        TextSize = 10,
    })

    local playerScroll = Instance.new("ScrollingFrame")
    playerScroll.Size = UDim2.new(1, 0, 1, -31)
    playerScroll.Position = UDim2.fromOffset(0, 31)
    playerScroll.BackgroundColor3 = Color3.fromRGB(7, 7, 12)
    playerScroll.BorderSizePixel = 0
    playerScroll.ScrollBarThickness = 4
    playerScroll.ScrollBarImageColor3 = Color3.fromRGB(52, 52, 76)
    playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    playerScroll.CanvasSize = UDim2.fromOffset(0, 0)
    playerScroll.Parent = playersPage
    addCorner(playerScroll, 7)
    addPadding(playerScroll, 5, 5, 5, 5)

    local pLay = Instance.new("UIListLayout")
    pLay.SortOrder = Enum.SortOrder.LayoutOrder
    pLay.Padding = UDim.new(0, 4)
    pLay.Parent = playerScroll

    local function rebuildPlayerList()
        for _, c in ipairs(playerScroll:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end

        local order = 0
        for _, p in ipairs(Players:GetPlayers()) do
            order += 1
            local isWhitelisted = whitelist[p.UserId] == true
            local isMe = p.UserId == LocalPlayer.UserId

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -4, 0, 34)
            row.LayoutOrder = layoutOrder(order)
            row.BackgroundColor3 = isWhitelisted and Color3.fromRGB(15, 29, 20) or Color3.fromRGB(17, 17, 27)
            row.BorderSizePixel = 0
            row.Parent = playerScroll
            addCorner(row, 7)

            makeText(row, {
                Size = UDim2.new(1, -96, 1, 0),
                Position = UDim2.fromOffset(10, 0),
                Text = p.Name .. (isMe and " (you)" or ""),
                TextColor3 = isWhitelisted and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(175, 175, 195),
                Font = Enum.Font.GothamBold,
                TextSize = 11,
            })

            local btn = makeButton(row, isWhitelisted and "ON" or "ADD", isWhitelisted and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(58, 58, 78))
            btn.Size = UDim2.fromOffset(64, 22)
            btn.Position = UDim2.new(1, -74, 0.5, -11)
            btn.TextSize = 9

            if isMe then
                btn.Text = "YOU"
                btn.BackgroundColor3 = UI.accent
            else
                btn.MouseButton1Click:Connect(function()
                    if whitelist[p.UserId] then
                        whitelist[p.UserId] = nil
                        console:Info("Removed " .. p.Name .. " from whitelist")
                    else
                        whitelist[p.UserId] = true
                        console:Success("Added " .. p.Name .. " to whitelist")
                    end
                    rebuildPlayerList()
                end)
            end
        end
    end

    rebuildPlayerList()
    Players.PlayerAdded:Connect(function() task.wait(0.5) rebuildPlayerList() end)
    Players.PlayerRemoving:Connect(function(p)
        whitelist[p.UserId] = nil
        task.wait(0.25)
        rebuildPlayerList()
    end)

    -- Floating launcher: pill instead of tiny single-letter hub button.
    local floatBtn = makeButton(gui, "Open Spectra", UI.panel)
    floatBtn.Size = UDim2.fromOffset(116, 40)
    floatBtn.Position = UDim2.new(1, -132, 0.5, -20)
    floatBtn.TextColor3 = UI.text
    floatBtn.TextSize = 12
    addCorner(floatBtn, 20)
    addStroke(floatBtn, UI.stroke, 1, 0.25)

    -- Resizer, no glow/shadow
    local resizeHandle = makeButton(frame, "↘", UI.panel2)
    resizeHandle.Size = UDim2.fromOffset(22, 22)
    resizeHandle.Position = UDim2.new(1, -24, 1, -24)
    resizeHandle.TextColor3 = UI.muted
    resizeHandle.TextSize = 13
    resizeHandle.ZIndex = 10

    local menuOpen = false
    local savedWidth = CONFIG.DEFAULT_W
    local savedHeight = CONFIG.DEFAULT_H

    local function toggleMenu(force)
        if force ~= nil then
            menuOpen = force
        else
            menuOpen = not menuOpen
        end

        if menuOpen then
            frame.Visible = true
            frame.Size = UDim2.fromOffset(savedWidth, 0)
            tween(frame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.fromOffset(savedWidth, savedHeight)
            })
            floatBtn.Visible = false
        else
            savedWidth = clamp(frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X or savedWidth, CONFIG.MIN_W, CONFIG.MAX_W)
            savedHeight = clamp(frame.AbsoluteSize.Y > 0 and frame.AbsoluteSize.Y or savedHeight, CONFIG.MIN_H, CONFIG.MAX_H)
            local t = tween(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Size = UDim2.fromOffset(savedWidth, 0)
            })
            if t then
                t.Completed:Connect(function()
                    frame.Visible = false
                    frame.Size = UDim2.fromOffset(savedWidth, savedHeight)
                    floatBtn.Visible = true
                end)
            else
                frame.Visible = false
                frame.Size = UDim2.fromOffset(savedWidth, savedHeight)
                floatBtn.Visible = true
            end
        end
    end

    closeBtn.MouseButton1Click:Connect(function() toggleMenu(false) end)
    miniBtn.MouseButton1Click:Connect(function() toggleMenu(false) end)
    floatBtn.MouseButton1Click:Connect(function() toggleMenu(true) end)

    UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == CONFIG.MENU_KEY then toggleMenu() end
    end)

    -- Drag main window
    local dragging = false
    local dragStart = nil
    local startPos = nil

    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- Resize main window
    local resizing = false
    local resizeStartPos = nil
    local resizeStartSize = nil

    resizeHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = true
            resizeStartPos = input.Position
            resizeStartSize = frame.AbsoluteSize
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - resizeStartPos
            local newW = clamp(resizeStartSize.X + d.X, CONFIG.MIN_W, CONFIG.MAX_W)
            local newH = clamp(resizeStartSize.Y + d.Y, CONFIG.MIN_H, CONFIG.MAX_H)
            savedWidth = newW
            savedHeight = newH
            frame.Size = UDim2.fromOffset(newW, newH)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            resizing = false
        end
    end)

    -- Optional: drag floating button too
    local fDragging = false
    local fDragStart = nil
    local fStartPos = nil

    floatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            fDragging = true
            fDragStart = input.Position
            fStartPos = floatBtn.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if fDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - fDragStart
            floatBtn.Position = UDim2.new(fStartPos.X.Scale, fStartPos.X.Offset + d.X, fStartPos.Y.Scale, fStartPos.Y.Offset + d.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            fDragging = false
        end
    end)

    for _, e in ipairs(console.entries) do pcall(function() console:RenderEntry(e) end) end
    console:RenderStats()
    rawViewer:Render()
end)

if not menuOk then
    print("[Spectra] Menu failed: " .. tostring(menuErr))
    print("[Spectra] Bot still works.")
end

console:Success("Spectra loaded. Press RightShift or tap [S].")
console:Info("Trigger: '" .. CONFIG.TRIGGER .. "' | You are whitelisted by default")
console:Warn("API key is blank in this safer version. Paste it in Settings. Rotate any key you shared publicly.")
print("[Spectra] Loaded. Press RightShift for menu.")
