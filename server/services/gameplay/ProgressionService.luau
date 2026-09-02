local ProgressionService = {}

local servicesFolder = script.Parent.Parent
local serverFolder = servicesFolder.Parent
local AnalyticsService = require(servicesFolder:WaitForChild("ops"):WaitForChild("AnalyticsService"))
local BoardValidationService = require(script.Parent:WaitForChild("BoardValidationService"))
local LeaderboardService = require(servicesFolder:WaitForChild("meta"):WaitForChild("LeaderboardService"))
local PlayerDataStore = require(serverFolder:WaitForChild("data"):WaitForChild("PlayerDataStore"))
local MetaService = require(servicesFolder:WaitForChild("meta"):WaitForChild("MetaService"))
local DEFAULT_MODE = "Classic"

local function sanitizePayloadBoardState(payload)
	if type(payload) ~= "table" then
		return nil
	end

	return PlayerDataStore.SanitizeBoardState(payload.boardState or payload)
end

local function sanitizeClientFunnelStep(stepName)
	if type(stepName) ~= "string" then
		return nil
	end

	local normalized = tostring(stepName)
	if normalized == "" or #normalized > 96 then
		return nil
	end
	if not string.match(normalized, "^[%w_]+$") then
		return nil
	end

	return normalized
end

local function resolveBoardMode(...)
	for index = 1, select("#", ...) do
		local candidate = select(index, ...)
		if type(candidate) == "table" and type(candidate.mode) == "string" and candidate.mode ~= "" then
			return candidate.mode
		end
	end

	return DEFAULT_MODE
end

local function applySolveProgress(data, rewardAmount, clearTimeMillis, modeName)
	data.stats = type(data.stats) == "table" and data.stats or {}
	data.activity = type(data.activity) == "table" and data.activity or {}
	data.resources = type(data.resources) == "table" and data.resources or {}

	data.stats.solves = math.max(0, math.floor(tonumber(data.stats.solves) or 0) + 1)
	data.stats.boardsCleared = data.stats.solves
	data.activity.dailyBoardsCleared = math.max(0, math.floor(tonumber(data.activity.dailyBoardsCleared) or 0) + 1)
	data.resources.puzzlePieces = math.max(0, math.floor(tonumber(data.resources.puzzlePieces) or 0) + rewardAmount)
	PlayerDataStore.RecordModeOutcome(data, modeName, true)

	if clearTimeMillis > 0 then
		local fastestBoardClearMillis = math.max(0, math.floor(tonumber(data.stats.fastestBoardClearMillis) or 0))
		if fastestBoardClearMillis <= 0 or clearTimeMillis < fastestBoardClearMillis then
			data.stats.fastestBoardClearMillis = clearTimeMillis
		end
	end
end

local function processHintUsed(player, data, storedBoardState, payloadBoardState, claimedWord)
	local availableHints = math.max(0, math.floor((data.resources and data.resources.hintsAvailable) or 0))
	if availableHints <= 0 then
		return {
			accepted = false,
			boardState = storedBoardState,
		}, false, "No hints available."
	end

	local result = BoardValidationService.ValidateHintUsed(player, storedBoardState, payloadBoardState, claimedWord)
	if result.accepted then
		data.resources.hintsAvailable = availableHints - 1
		data.stats = type(data.stats) == "table" and data.stats or {}
		data.stats.hintsUsed = math.max(0, math.floor((data.stats.hintsUsed or 0) + 1))
		AnalyticsService.TrackHintUsed(player, resolveBoardMode(result, payloadBoardState, storedBoardState))
	end
	if result.boardState then
		data.boardState = result.boardState
	end

	return result, result.accepted == true, result.accepted and nil or "Hint could not be used."
end

function ProgressionService.RecordAction(player, actionName, payload)
	payload = type(payload) == "table" and payload or {}

	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)
	data.stats = type(data.stats) == "table" and data.stats or {}
	data.activity = type(data.activity) == "table" and data.activity or {}
	data.resources = type(data.resources) == "table" and data.resources or {}

	local storedBoardState = PlayerDataStore.SanitizeBoardState(data.boardState)
	local payloadBoardState = sanitizePayloadBoardState(payload)

	if storedBoardState == nil and data.boardState ~= nil then
		data.boardState = nil
	end

	if actionName == "WordFound" then
		local result = BoardValidationService.ValidateWordFound(player, storedBoardState, payloadBoardState, payload.word, payload.path)
		if result.accepted then
			data.stats.totalWordsFound = math.max(0, math.floor((data.stats.totalWordsFound or 0) + 1))
			data.activity.dailyWordsFound = math.max(0, math.floor((data.activity.dailyWordsFound or 0) + 1))
		end
		if result.boardState then
			data.boardState = result.boardState
		end
	elseif actionName == "BoardStateUpdated" then
		local validatedBoardState = BoardValidationService.ProcessBoardState(player, storedBoardState, payloadBoardState)
		if validatedBoardState then
			data.boardState = validatedBoardState
		end
	elseif actionName == "BoardStateCleared" then
		BoardValidationService.ClearBoardState(player)
		data.boardState = nil
	elseif actionName == "HintUsed" then
		processHintUsed(player, data, storedBoardState, payloadBoardState, payload.word)
	elseif actionName == "ClientFunnel" then
		local stepName = sanitizeClientFunnelStep(payload.step or payload.name)
		if stepName then
			local details = type(payload.details) == "table" and payload.details or nil
			AnalyticsService.TrackCriticalStep(player, stepName, details)
		end
		return nil
	elseif actionName == "BoardCleared" then
		local finalBoardState = BoardValidationService.ProcessBoardState(player, storedBoardState, payloadBoardState)
			or storedBoardState
			or payloadBoardState
		local result = BoardValidationService.ValidateBoardCleared(player, storedBoardState, finalBoardState)
		if result.accepted then
			local rewardAmount = math.max(1, math.floor(tonumber(result.reward) or 1))
			local clearTimeMillis = math.max(0, math.floor(tonumber(result.clearTimeMillis) or 0))
			local modeName = resolveBoardMode(result, finalBoardState, storedBoardState, payloadBoardState)

			applySolveProgress(data, rewardAmount, clearTimeMillis, modeName)
			data.boardState = nil

			AnalyticsService.TrackEconomySource(player, "pieces", "board_clear", rewardAmount, {
				mode = modeName,
				level = 1,
				clearTimeMillis = clearTimeMillis,
			})
			AnalyticsService.TrackModeComplete(player, modeName, {
				level = 1,
				reward = rewardAmount,
				pieces = rewardAmount,
				stars = 0,
				pack = modeName,
			})
			AnalyticsService.TrackBoardMilestone(player, data.stats.solves)

			local snapshot = PlayerDataStore.GetSnapshot(player)
			LeaderboardService.MarkSnapshotDirty(player, snapshot)
			return snapshot
		end
	elseif actionName == "BoardLost" then
		PlayerDataStore.RecordModeOutcome(data, resolveBoardMode(payloadBoardState, storedBoardState, payload), false)
		BoardValidationService.ClearBoardState(player)
		data.boardState = nil
	end

	local snapshot = PlayerDataStore.GetSnapshot(player)
	if actionName == "BoardLost" then
		LeaderboardService.MarkSnapshotDirty(player, snapshot)
	end
	if actionName == "WordFound" or actionName == "BoardStateUpdated" or actionName == "BoardStateCleared" then
		return nil
	end
	return snapshot
end

function ProgressionService.UseHint(player, payload)
	payload = type(payload) == "table" and payload or {}

	local data = PlayerDataStore.GetMutableData(player)
	MetaService.NormalizeData(data)

	local storedBoardState = PlayerDataStore.SanitizeBoardState(data.boardState)
	local payloadBoardState = sanitizePayloadBoardState(payload)

	if storedBoardState == nil and data.boardState ~= nil then
		data.boardState = nil
	end

	local result, accepted, message = processHintUsed(player, data, storedBoardState, payloadBoardState, payload.word)
	local snapshot = PlayerDataStore.GetSnapshot(player)

	return {
		success = accepted,
		accepted = accepted,
		message = message,
		snapshot = snapshot,
		boardState = result and result.boardState or nil,
	}
end

function ProgressionService.UseTimedProduct(player, _payload)
	return {
		success = false,
		message = "Timed products are disabled.",
		snapshot = PlayerDataStore.GetSnapshot(player),
		boardState = nil,
	}
end

function ProgressionService.ClearPlayer(player)
	BoardValidationService.ClearPlayer(player)
end

return ProgressionService
