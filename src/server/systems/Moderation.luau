local Moderation = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameService = require(script.Parent.Parent:WaitForChild("services"):WaitForChild("GameService"))

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("PuzzleCatalog"))

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local MAX_ADMIN_GRANT = 100000
local ALLOWED_ADMINS = {
	[1790165114] = true,
}
local serviceContext = nil

local function splitWords(text)
	local words = {}
	for token in string.gmatch(text or "", "%S+") do
		table.insert(words, token)
	end
	return words
end

local function trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(text)
	return string.lower(tostring(text or ""))
end

local function toInt(value)
	local numberValue = tonumber(value)
	if numberValue == nil
		or numberValue ~= numberValue
		or numberValue == math.huge
		or numberValue == -math.huge then
		return nil
	end
	return math.floor(numberValue)
end

function Moderation.IsAllowed(player)
	return player and ALLOWED_ADMINS[player.UserId] == true
end

local function buildPlayerList(Players)
	local players = {
		{
			userId = "all",
			name = "All Players",
			displayName = "All Players",
		},
	}

	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(players, {
			userId = player.UserId,
			name = player.Name,
			displayName = player.DisplayName,
		})
	end

	table.sort(players, function(left, right)
		if left.userId == "all" then
			return true
		end
		if right.userId == "all" then
			return false
		end
		return string.lower(left.name or "") < string.lower(right.name or "")
	end)

	return players
end

local function resolveMenuTargets(Players, targetUserId)
	if targetUserId == "all" then
		return Players:GetPlayers()
	end

	local numericUserId = tonumber(targetUserId)
	if not numericUserId then
		return {}
	end

	local target = Players:GetPlayerByUserId(numericUserId)
	return target and { target } or {}
end

function Moderation.Init(context)
	if serviceContext ~= nil then
		return
	end
	serviceContext = context
	local Players = context.Players
	local AnalyticsService = context.AnalyticsService
	local SocialService = context.SocialService
	local MetaService = context.MetaService
	local PlayerDataStore = context.PlayerDataStore
	local StateUpdatedRemote = context.StateUpdatedRemote
	local AdminMessageEvent = context.AdminMessageEvent
	local AdminBoardResetEvent = context.AdminBoardResetEvent

	local function isAllowed(player)
		return Moderation.IsAllowed(player)
	end

	local function sendChatMessage(player, text, color)
		if not (player and player.Parent and AdminMessageEvent) then
			return
		end
		AdminMessageEvent:FireClient(player, {
			text = tostring(text or ""),
			color = color,
		})
	end

	local function sendPrivateMessage(player, text, color)
		sendChatMessage(player, text, color or Color3.fromRGB(105, 255, 97))
	end

	local function resolveTargets(sourcePlayer, selector)
		local key = lower(selector)
		if key == "" or key == "me" then
			return { sourcePlayer }
		end
		if key == "all" then
			return Players:GetPlayers()
		end

		local matches = {}
		for _, candidate in ipairs(Players:GetPlayers()) do
			if lower(candidate.Name) == key then
				return { candidate }
			end
			if string.find(lower(candidate.Name), key, 1, true) == 1 then
				table.insert(matches, candidate)
			end
		end

		if #matches > 0 then
			return { matches[1] }
		end

		return {}
	end

	local function pushSnapshot(target, refreshLeaderboard)
		local snapshot = PlayerDataStore.GetSnapshot(target)
		if refreshLeaderboard then
			SocialService.MarkSnapshotDirty(target, snapshot)
		end
		StateUpdatedRemote:FireClient(target, snapshot)
	end

	local function showCommandList(player)
		local lines = {
			"!cmd / !cmds - show commands",
			"!say <message> - broadcast system message",
			"!hints <player|all|me> <amount> - add free hints",
			"!solves <player|all|me> <amount> - add wins",
			"!level <player|all|me> <amount> - set classic level",
			"!resetboard <player|all|me> - clear active board",
		}

		for index, line in ipairs(lines) do
			task.delay((index - 1) * 0.08, function()
				sendPrivateMessage(player, line, Color3.fromRGB(105, 255, 97))
			end)
		end
	end

	local function adjustHints(adminPlayer, targets, amount)
		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.resources.hintsAvailable = math.max(0, math.floor((data.resources.hintsAvailable or 0) + amount))
			AnalyticsService.TrackEconomySource(target, "hints", "AdminCommand", math.max(0, amount), {
				adminUserId = adminPlayer.UserId,
				command = "hints",
			})
			pushSnapshot(target, false)
		end
	end

	local function adjustSolves(adminPlayer, targets, amount)
		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.stats.boardsCleared = math.max(0, math.floor((data.stats.boardsCleared or 0) + amount))
			AnalyticsService.TrackCustomEvent(target, "AdminSolvesGranted", amount, {
				adminUserId = adminPlayer.UserId,
				command = "solves",
			})
			pushSnapshot(target, true)
		end
	end

	local function setClassicLevel(adminPlayer, targets, amount)
		local levelValue = math.clamp(math.max(1, amount), 1, MAX_CLASSIC_LEVEL)
		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.progression.lastClassicLevel = levelValue
			data.progression.highestClassicLevel = math.max(
				math.max(1, math.floor(tonumber(data.progression.highestClassicLevel) or 1)),
				levelValue
			)
			data.boardState = nil
			GameService.ClearBoardState(target)
			AnalyticsService.TrackCustomEvent(target, "AdminClassicLevelSet", levelValue, {
				adminUserId = adminPlayer.UserId,
				command = "level",
			})
			pushSnapshot(target, false)
			if AdminBoardResetEvent then
				AdminBoardResetEvent:FireClient(target)
			end
		end
	end

	local function resetBoards(adminPlayer, targets)
		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.boardState = nil
			GameService.ClearBoardState(target)
			AnalyticsService.TrackCustomEvent(target, "AdminBoardReset", 1, {
				adminUserId = adminPlayer.UserId,
				command = "resetboard",
			})
			pushSnapshot(target, false)
			if AdminBoardResetEvent then
				AdminBoardResetEvent:FireClient(target)
			end
		end
	end

	local function handleCommand(player, rawMessage)
		local message = trim(rawMessage)
		if message == "" or string.sub(message, 1, 1) ~= "!" then
			return
		end

		if not isAllowed(player) then
			sendPrivateMessage(player, "You're not eligible to use these commands.", Color3.fromRGB(255, 120, 120))
			return
		end

		local args = splitWords(message)
		local command = lower(string.sub(args[1] or "", 2))

		if command == "cmd" or command == "cmds" or command == "help" then
			showCommandList(player)
			return
		end

		if command == "say" then
			local payload = trim(string.sub(message, #(args[1] or "") + 1))
			if payload == "" then
				sendPrivateMessage(player, "Usage: !say <message>", Color3.fromRGB(255, 120, 120))
				return
			end
			if #payload > 180 then
				sendPrivateMessage(player, "Messages are limited to 180 characters.", Color3.fromRGB(255, 120, 120))
				return
			end
			AdminMessageEvent:FireAllClients({
				text = "[SERVER] " .. payload,
				color = Color3.fromRGB(255, 79, 79),
			})
			AnalyticsService.TrackCustomEvent(player, "AdminSayUsed", 1, {
				messageLength = #payload,
			})
			return
		end

		local selector = args[2] or "me"
		local targets = resolveTargets(player, selector)
		if #targets == 0 then
			sendPrivateMessage(player, "No player matched: " .. tostring(selector), Color3.fromRGB(255, 120, 120))
			return
		end

		if command == "hints" or command == "solves" or command == "level" then
			local amount = toInt(args[3])
			if amount == nil then
				sendPrivateMessage(player, string.format("Usage: !%s <player|all|me> <amount>", command), Color3.fromRGB(255, 120, 120))
				return
			end
			if command ~= "level" and amount <= 0 then
				sendPrivateMessage(player, "Amount must be above 0.", Color3.fromRGB(255, 120, 120))
				return
			end
			if command ~= "level" and amount > MAX_ADMIN_GRANT then
				sendPrivateMessage(player, "Amount is above the admin safety limit.", Color3.fromRGB(255, 120, 120))
				return
			end

			if command == "hints" then
				adjustHints(player, targets, amount)
				sendPrivateMessage(player, "Added hints to " .. tostring(#targets) .. " player(s).")
			elseif command == "solves" then
				adjustSolves(player, targets, amount)
				sendPrivateMessage(player, "Added wins to " .. tostring(#targets) .. " player(s).")
			elseif command == "level" then
				setClassicLevel(player, targets, amount)
				sendPrivateMessage(player, "Classic level set for " .. tostring(#targets) .. " player(s).")
			end
			return
		end

		if command == "resetboard" then
			resetBoards(player, targets)
			sendPrivateMessage(player, "Reset board for " .. tostring(#targets) .. " player(s).")
			return
		end

		sendPrivateMessage(player, "Unknown command. Type !cmd", Color3.fromRGB(255, 120, 120))
	end

	local function bindPlayer(player)
		player.Chatted:Connect(function(message)
			handleCommand(player, message)
		end)
	end

	for _, currentPlayer in ipairs(Players:GetPlayers()) do
		bindPlayer(currentPlayer)
	end

	Players.PlayerAdded:Connect(bindPlayer)
end

function Moderation.HandleMenuRequest(player, payload)
	local context = serviceContext
	if not context or not Moderation.IsAllowed(player) then
		return {
			success = false,
			allowed = false,
			message = "Not allowed.",
		}
	end

	payload = type(payload) == "table" and payload or {}
	local action = lower(payload.action)
	local Players = context.Players
	local AnalyticsService = context.AnalyticsService
	local SocialService = context.SocialService
	local MetaService = context.MetaService
	local PlayerDataStore = context.PlayerDataStore
	local StateUpdatedRemote = context.StateUpdatedRemote
	local AdminBoardResetEvent = context.AdminBoardResetEvent

	local function pushSnapshot(target, refreshLeaderboard)
		local snapshot = PlayerDataStore.GetSnapshot(target)
		if refreshLeaderboard then
			SocialService.MarkSnapshotDirty(target, snapshot)
		end
		StateUpdatedRemote:FireClient(target, snapshot)
	end

	if action == "" or action == "state" or action == "getstate" then
		return {
			success = true,
			allowed = true,
			maxClassicLevel = MAX_CLASSIC_LEVEL,
			players = buildPlayerList(Players),
		}
	end

	local targets = resolveMenuTargets(Players, payload.targetUserId)
	if #targets <= 0 then
		return {
			success = false,
			allowed = true,
			message = "No player selected.",
			players = buildPlayerList(Players),
			maxClassicLevel = MAX_CLASSIC_LEVEL,
		}
	end

	if action == "givehints" then
		local amount = toInt(payload.amount)
		if not amount or amount <= 0 or amount > MAX_ADMIN_GRANT then
			return {
				success = false,
				allowed = true,
				message = "Hint amount must be between 1 and 100000.",
				players = buildPlayerList(Players),
				maxClassicLevel = MAX_CLASSIC_LEVEL,
			}
		end

		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.resources.hintsAvailable = math.max(0, math.floor((data.resources.hintsAvailable or 0) + amount))
			AnalyticsService.TrackEconomySource(target, "hints", "AdminMenu", amount, {
				adminUserId = player.UserId,
			})
			pushSnapshot(target, false)
		end

		return {
			success = true,
			allowed = true,
			message = string.format("Added %d hint%s to %d player(s).", amount, amount == 1 and "" or "s", #targets),
			players = buildPlayerList(Players),
			maxClassicLevel = MAX_CLASSIC_LEVEL,
		}
	end

	if action == "setlevel" then
		local levelValue = toInt(payload.level)
		if not levelValue then
			return {
				success = false,
				allowed = true,
				message = "Enter a Classic level.",
				players = buildPlayerList(Players),
				maxClassicLevel = MAX_CLASSIC_LEVEL,
			}
		end
		levelValue = math.clamp(math.max(1, levelValue), 1, MAX_CLASSIC_LEVEL)

		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.progression.lastClassicLevel = levelValue
			data.progression.highestClassicLevel = math.max(
				math.max(1, math.floor(tonumber(data.progression.highestClassicLevel) or 1)),
				levelValue
			)
			data.boardState = nil
			GameService.ClearBoardState(target)
			AnalyticsService.TrackCustomEvent(target, "AdminClassicLevelSet", levelValue, {
				adminUserId = player.UserId,
				command = "menu_level",
			})
			pushSnapshot(target, false)
			if AdminBoardResetEvent then
				AdminBoardResetEvent:FireClient(target)
			end
		end

		return {
			success = true,
			allowed = true,
			message = string.format("Set Classic level to %d for %d player(s).", levelValue, #targets),
			players = buildPlayerList(Players),
			maxClassicLevel = MAX_CLASSIC_LEVEL,
		}
	end

	return {
		success = false,
		allowed = true,
		message = "Unknown admin action.",
		players = buildPlayerList(Players),
		maxClassicLevel = MAX_CLASSIC_LEVEL,
	}
end

return Moderation
