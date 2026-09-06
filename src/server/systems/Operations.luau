local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

-- Optional purchase URL: ServerStorage.PrivateConfig.WebhookPurchaseUrl
-- (StringValue or attribute), or PrivateConfig.WebhookConfig.purchase.
local Operations = {}

local function resolveWebhooks()
	local privateConfigFolder = ServerStorage:FindFirstChild("PrivateConfig")
	local purchaseUrlValue = privateConfigFolder and privateConfigFolder:FindFirstChild("WebhookPurchaseUrl") or nil
	local purchaseUrlAttribute = privateConfigFolder and privateConfigFolder:GetAttribute("WebhookPurchaseUrl") or nil
	local purchaseUrl = nil

	if purchaseUrlValue and purchaseUrlValue:IsA("StringValue") then
		local candidate = tostring(purchaseUrlValue.Value or "")
		if candidate ~= "" then
			purchaseUrl = candidate
		end
	end
	if not purchaseUrl and type(purchaseUrlAttribute) == "string" and purchaseUrlAttribute ~= "" then
		purchaseUrl = purchaseUrlAttribute
	end

	local configModule = privateConfigFolder and privateConfigFolder:FindFirstChild("WebhookConfig") or nil
	if configModule and configModule:IsA("ModuleScript") then
		local ok, result = pcall(require, configModule)
		if ok and type(result) == "table" then
			if type(result.purchase) ~= "string" or result.purchase == "" then
				result.purchase = purchaseUrl
			end
			return result
		end
	end

	return {
		purchase = purchaseUrl,
	}
end

local WEBHOOKS = resolveWebhooks()

local PURCHASE_FOOTER_ICON = "https://cdn.discordapp.com/attachments/1249313018593017906/1290138475323985940/v2.png"
local DEFAULT_HEADSHOT = "https://t3.rbxcdn.com/9fc30fe577bf95e045c9a3d4abaca05d"

local function getPlayerHeadshotUrl(player)
	local success, result = pcall(function()
		local url = "https://thumbnails.roproxy.com/v1/users/avatar-headshot?userIds="
			.. player.UserId
			.. "&size=150x150&format=Png"
		return HttpService:JSONDecode(HttpService:GetAsync(url))
	end)

	if success and result and result.data and result.data[1] and result.data[1].imageUrl then
		return result.data[1].imageUrl
	end

	return DEFAULT_HEADSHOT
end

local function getPlayerName(player)
	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(player.UserId)
	end)

	if success and type(result) == "string" and result ~= "" then
		return result
	end

	return player.Name
end

function Operations.FireWebhook(player, report, webhookType, color)
	if webhookType == true or webhookType == "rejoinLog" then
		return
	end

	if not (player and player.Parent) then
		return
	end
	if type(WEBHOOKS.purchase) ~= "string" or WEBHOOKS.purchase == "" then
		return
	end

	task.spawn(function()
		local playerName = getPlayerName(player)
		local headshotUrl = getPlayerHeadshotUrl(player)
		local aestTime = os.date("!%Y-%m-%d %H:%M:%S", os.time() + 10 * 60 * 60)

		local embedData = {
			content = "",
			embeds = { {
				author = {
					name = "Purchase By " .. playerName,
					icon_url = headshotUrl,
				},
				description = "```" .. tostring(report or "Purchase completed.") .. "```",
				color = math.max(0, math.floor(tonumber(color) or 0x87CEEB)),
				fields = {
					{
						name = "Account Age",
						value = tostring(player.AccountAge) .. " days old",
						inline = true,
					},
					{
						name = "Account ID",
						value = tostring(player.UserId),
						inline = true,
					},
					{
						name = "Experience",
						value = tostring(game.Name) .. " (" .. tostring(game.PlaceId) .. ")",
						inline = true,
					},
					{
						name = "Time (AEST)",
						value = aestTime,
						inline = true,
					},
				},
				footer = {
					text = "Purchase System",
					icon_url = PURCHASE_FOOTER_ICON,
				},
			} },
			attachments = {},
		}

		pcall(function()
			HttpService:PostAsync(WEBHOOKS.purchase, HttpService:JSONEncode(embedData))
		end)
	end)
end


-- Idle-session rejoin ownership.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local antiAfkInitialized = false
local rejoinRequestedAt = {}
local REJOIN_COOLDOWN_SECONDS = 30

function Operations.InitAutoRejoin(rejoinRemote)
	if antiAfkInitialized or not rejoinRemote then
		return
	end

	antiAfkInitialized = true

	rejoinRemote.OnServerEvent:Connect(function(player)
		if not player or player.Parent ~= Players then
			return
		end

		local now = os.clock()
		local lastRequestedAt = tonumber(rejoinRequestedAt[player.UserId]) or -math.huge
		if now - lastRequestedAt < REJOIN_COOLDOWN_SECONDS then
			return
		end
		rejoinRequestedAt[player.UserId] = now

		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ServerInstanceId = game.JobId
		teleportOptions:SetTeleportData({
			autoRejoin = true,
		})

		for _ = 1, 4 do
			local success = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, { player }, teleportOptions)
			end)
			if success then
				return
			end

			task.wait(2)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		local joinData = player:GetJoinData()
		local teleportData = joinData and joinData.TeleportData
		if teleportData and teleportData.autoRejoin then
			warn(string.format("[AntiAFK] %s rejoined after idle protection", player.Name))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		rejoinRequestedAt[player.UserId] = nil
	end)
end


-- Shared daytime environment and camera anchor ownership.
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CAMERA_CFRAME = CFrame.new(-225.271, 136.93, -519.269)
	* CFrame.fromOrientation(math.rad(15.309), math.rad(40.884), 0)
local TRANSITION_SECONDS = 180
local UPDATE_SECONDS = 0.25
local DAYLIGHT = {
	{ hour = 12.25, cover = 0.28, density = 0.32, brightness = 2.5,
		ambient = Color3.fromRGB(142, 155, 171), outdoor = Color3.fromRGB(177, 190, 207), clouds = Color3.fromRGB(250, 253, 255) },
	{ hour = 13.5, cover = 0.58, density = 0.48, brightness = 2.15,
		ambient = Color3.fromRGB(147, 156, 170), outdoor = Color3.fromRGB(179, 190, 203), clouds = Color3.fromRGB(241, 247, 255) },
	{ hour = 15.5, cover = 0.38, density = 0.38, brightness = 2.35,
		ambient = Color3.fromRGB(157, 150, 144), outdoor = Color3.fromRGB(204, 194, 180), clouds = Color3.fromRGB(255, 249, 237) },
	{ hour = 11, cover = 0.44, density = 0.42, brightness = 2.4,
		ambient = Color3.fromRGB(144, 158, 175), outdoor = Color3.fromRGB(179, 197, 216), clouds = Color3.fromRGB(248, 252, 255) },
}
local environmentConnection, cameraPart

local function blend(a, b, alpha)
	return a + (b - a) * alpha
end

local function applyDaylight(clouds, from, to, alpha)
	local eased = (1 - math.cos(alpha * math.pi)) * 0.5
	-- TimeOfDay replicates to clients; all endpoints remain between 11:00 and 15:30.
	local seconds = math.floor(math.clamp(blend(from.hour, to.hour, eased), 11, 15.5) * 3600)
	Lighting.TimeOfDay = string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	Lighting.Brightness = blend(from.brightness, to.brightness, eased)
	Lighting.Ambient = from.ambient:Lerp(to.ambient, eased)
	Lighting.OutdoorAmbient = from.outdoor:Lerp(to.outdoor, eased)
	clouds.Cover = blend(from.cover, to.cover, eased)
	clouds.Density = blend(from.density, to.density, eased)
	clouds.Color = from.clouds:Lerp(to.clouds, eased)
end

function Operations.InitEnvironment()
	if environmentConnection then return cameraPart end
	cameraPart = Workspace:FindFirstChild("CamPart")
	if not cameraPart or not cameraPart:IsA("BasePart") then
		cameraPart = Instance.new("Part")
		cameraPart.Name = "CamPart"
	end
	cameraPart.Anchored = true
	cameraPart.CanCollide, cameraPart.CanTouch, cameraPart.CanQuery = false, false, false
	cameraPart.CastShadow, cameraPart.Transparency = false, 1
	cameraPart.Size = Vector3.new(1, 1, 1)
	cameraPart.CFrame = CAMERA_CFRAME
	cameraPart.Parent = Workspace
	-- The pose remains available even when StreamingEnabled unloads the distant part.
	ReplicatedStorage:SetAttribute("CamPartCFrame", cameraPart.CFrame)

	local terrain = Workspace.Terrain
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Name = "Clouds"
		clouds.Parent = terrain
	end
	clouds.Enabled = true
	Lighting.GeographicLatitude = 35
	local index, elapsed, sinceUpdate = 1, 0, 0
	applyDaylight(clouds, DAYLIGHT[1], DAYLIGHT[2], 0)
	environmentConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		sinceUpdate += dt
		if sinceUpdate < UPDATE_SECONDS then return end
		sinceUpdate %= UPDATE_SECONDS
		local steps = math.floor(elapsed / TRANSITION_SECONDS)
		index = (index - 1 + steps) % #DAYLIGHT + 1
		elapsed %= TRANSITION_SECONDS
		applyDaylight(clouds, DAYLIGHT[index], DAYLIGHT[index % #DAYLIGHT + 1], elapsed / TRANSITION_SECONDS)
	end)
	return cameraPart
end

function Operations.StopEnvironment()
	if environmentConnection then environmentConnection:Disconnect() end
	environmentConnection = nil
end

return Operations
