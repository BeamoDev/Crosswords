local AdminCommandService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoardValidationService = require(script.Parent.Parent:WaitForChild("gameplay"):WaitForChild("BoardValidationService"))

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels"))

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local ALLOWED_ADMINS = {
	[1790165114] = true,
}

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
	if numberValue == nil then
		return nil
	end
	return math.floor(numberValue)
end

function AdminCommandService.Init(context)
	local Players = context.Players
	local AnalyticsService = context.AnalyticsService
	local LeaderboardService = context.LeaderboardService
	local MetaService = context.MetaService
	local PlayerDataStore = context.PlayerDataStore
	local StateUpdatedRemote = context.StateUpdatedRemote
	local AdminMessageEvent = context.AdminMessageEvent
	local AdminBoardResetEvent = context.AdminBoardResetEvent

	local function isAllowed(player)
		return player and ALLOWED_ADMINS[player.UserId] == true
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
			LeaderboardService.MarkSnapshotDirty(target, snapshot)
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
			AnalyticsService.TrackCustomEvent(target, "AdminClassicLevelSet", levelValue, {
				adminUserId = adminPlayer.UserId,
				command = "level",
			})
			pushSnapshot(target, false)
		end
	end

	local function resetBoards(adminPlayer, targets)
		for _, target in ipairs(targets) do
			local data = PlayerDataStore.GetMutableData(target)
			MetaService.NormalizeData(data)
			data.boardState = nil
			BoardValidationService.ClearBoardState(target)
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

return AdminCommandService
