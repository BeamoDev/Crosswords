local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local WebhookService = {}

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

function WebhookService.FireWebhook(player, report, webhookType, color)
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

return WebhookService
