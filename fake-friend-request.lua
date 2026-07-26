--// Fake Friend Request (No Menu / Auto)
--// Grabs a random real Roblox person: DisplayName as title,
--// @username in the message, and their avatar headshot as the icon.

local Players       = game:GetService("Players")
local StarterGui    = game:GetService("StarterGui")
local HttpService   = game:GetService("HttpService")

--============ CONFIG ============--
local DURATION      = 5      -- how long the friend request notification stays
local ACCEPT_DURATION = 5    -- how long the "New friend" popup stays after accepting
local BUTTON1       = "Accept"
local BUTTON2       = "Decline"
local PREFER_INGAME = true   -- true = try a random player in the server first
local REPEATING     = false  -- true = keep spamming requests forever
local REPEAT_DELAY  = 8      -- seconds between requests when REPEATING
--================================--

local LocalPlayer = Players.LocalPlayer

-- Fallback list of well-known userIds (used if web request fails)
local FALLBACK_IDS = {
	1, 2, 3, 16, 261, 1234567, 156, 5010050, 13365322,
	261959614, 20396599, 39640825, 12345, 998796, 30832574,
}

local httpGet = (syn and syn.request and function(url)
	local ok, res = pcall(syn.request, {Url = url, Method = "GET"})
	if ok and res and res.Body then return res.Body end
end) or (request and function(url)
	local ok, res = pcall(request, {Url = url, Method = "GET"})
	if ok and res and res.Body then return res.Body end
end) or (http_request and function(url)
	local ok, res = pcall(http_request, {Url = url, Method = "GET"})
	if ok and res and res.Body then return res.Body end
end) or function(url)
	local ok, body = pcall(function() return game:HttpGet(url) end)
	if ok then return body end
end

-- Try to pull real name + displayName straight from the Roblox users API
local function fetchUserInfo(userId)
	local body = httpGet("https://users.roblox.com/v1/users/" .. userId)
	if not body then return nil end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
	if ok and type(data) == "table" and data.name then
		return {
			UserId      = userId,
			Name        = data.name,
			DisplayName = data.displayName or data.name,
		}
	end
end

-- Pick a random userId that actually exists
local function randomUserFromWeb()
	for _ = 1, 12 do
		local id = math.random(1, 3000000000) -- huge range, most ids are real-ish
		local info = fetchUserInfo(id)
		if info then return info end
	end
	-- last resort: known-good ids
	for _ = 1, #FALLBACK_IDS do
		local id = FALLBACK_IDS[math.random(1, #FALLBACK_IDS)]
		local info = fetchUserInfo(id)
		if info then return info end
		local ok, name = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
		if ok and name then
			return {UserId = id, Name = name, DisplayName = name}
		end
	end
end

-- Pick a random player currently in the server (not you)
local function randomUserInGame()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			table.insert(list, plr)
		end
	end
	if #list == 0 then return nil end
	local p = list[math.random(1, #list)]
	return {UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName}
end

-- Grab the headshot thumbnail for a userId
local function getHeadshot(userId)
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size420x420
		)
	end)
	if ok and url and url ~= "" then
		return url
	end
	return "rbxthumb://type=AvatarHeadShot&id=" .. userId .. "&w=420&h=420"
end

local function sendFakeRequest()
	local user = (PREFER_INGAME and randomUserInGame()) or randomUserFromWeb() or randomUserInGame()
	if not user then
		warn("[FakeFriendRequest] Couldn't find a random person.")
		return
	end

	local icon = getHeadshot(user.UserId)

	-- Callback so we can react to Accept / Decline
	local callback = Instance.new("BindableFunction")
	callback.OnInvoke = function(chosen)
		if chosen == BUTTON1 then
			-- Mirrors the real "New friend" popup: title + their USERNAME
			-- Fake network delay, like the real request going through
			task.wait(math.random(40, 60) / 100) -- 0.40 - 0.60s
			pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title    = "New friend",
					Text     = user.Name,
					Icon     = icon,
					Duration = ACCEPT_DURATION,
				})
			end)
		end
	end

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title    = user.DisplayName,
			Text     = "Sent you a friend request!",
			Icon     = icon,
			Duration = DURATION,
			Button1  = BUTTON1,
			Button2  = BUTTON2,
			Callback = callback,
		})
	end)
end

-- Fire it
task.spawn(function()
	math.randomseed(tick() % 1 * 1e6)
	sendFakeRequest()
	while REPEATING do
		task.wait(REPEAT_DELAY)
		sendFakeRequest()
	end
end)
