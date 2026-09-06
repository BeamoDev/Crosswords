local ProgressionService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local servicesFolder = script.Parent
local serverFolder = servicesFolder.Parent
local systemsFolder = serverFolder:WaitForChild("systems")
local AnalyticsService = require(systemsFolder:WaitForChild("Analytics"))
local GameService = require(servicesFolder:WaitForChild("GameService"))
local DuelService = require(servicesFolder:WaitForChild("DuelService"))
local SocialService = require(servicesFolder:WaitForChild("SocialService"))
local DataService = require(serverFolder:WaitForChild("data"):WaitForChild("DataService"))
local RewardService = require(servicesFolder:WaitForChild("RewardService"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local GameConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("GameConfig"))
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local PuzzleGenerator = require(sharedFolder:WaitForChild("puzzle"):WaitForChild("PuzzleGenerator"))
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("PuzzleCatalog"))
local PuzzleEconomy = GameConfig.Economy
local DailyMode = ProgressionConfig.Daily
local StarRules = ProgressionConfig.Stars
local DefinitionBuilder = PuzzleGenerator

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)

local function getDailyIdentity()
	return DailyMode.GetDailyIdentity(MAX_CLASSIC_LEVEL)
end

local function hasCompletedDailyToday(data)
	local dailyIdentity = getDailyIdentity()
	local completedDayStamp = math.floor(tonumber(data.dailyMode and data.dailyMode.completedDayStamp) or -1)
	return completedDayStamp == dailyIdentity.dayStamp, dailyIdentity
end

local function isDailyBoardState(boardState)
	return type(boardState) == "table" and boardState.mode == "Daily"
end

local function sanitizePayloadBoardState(payload)
	if type(payload) ~= "table" then
		return nil
	end

	return DataService.SanitizeBoardState(payload.boardState or payload)
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

local function filterBoardStateForProgression(boardState, progression)
	if type(boardState) ~= "table" then
		return nil
	end

	if boardState.mode == "Classic" then
		local unlockedLevel = math.clamp(
			math.max(1, math.floor(tonumber(progression and progression.lastClassicLevel) or 1)),
			1,
			MAX_CLASSIC_LEVEL
		)
		if math.floor(tonumber(boardState.level) or 1) > unlockedLevel then
			return nil
		end
	end

	return boardState
end

local function buildStarMetadata(mode, dailyIdentity)
	if mode == "Daily" then
		return {
			dayStamp = dailyIdentity and dailyIdentity.dayStamp or nil,
		}
	end

	return nil
end

local function recordStarProgress(data, mode, level, stars, metadata)
	if type(data) ~= "table" then
		return 0
	end

	data.starProgress = type(data.starProgress) == "table" and data.starProgress or {}
	local slot = StarRules.ResolveSlot(mode, level, metadata)
	local modeBucket = type(data.starProgress[slot.mode]) == "table" and data.starProgress[slot.mode] or {}
	local packBucket = type(modeBucket[slot.pack]) == "table" and modeBucket[slot.pack] or {}
	local numericStars = math.clamp(math.floor(tonumber(stars) or 0), 0, 3)
	local previousBest = math.clamp(math.floor(tonumber(packBucket[slot.entry]) or 0), 0, 3)

	modeBucket[slot.pack] = packBucket
	data.starProgress[slot.mode] = modeBucket
	packBucket[slot.entry] = math.max(previousBest, numericStars)

	return packBucket[slot.entry]
end

local function calculateAwardedPuzzlePieces(mode, level, boardState, clearTimeMillis, fallbackReward)
	if type(boardState) ~= "table" then
		local scaledFallbackReward = PuzzleEconomy.ScaleCompletionReward(fallbackReward)
		return scaledFallbackReward, {
			mode = tostring(mode or "Classic"),
			gridSize = 0,
			timeSpent = math.max(0, tonumber(clearTimeMillis) or 0) / 1000,
			hintsUsed = 0,
			resetsUsed = 0,
			basePieces = 0,
			modeMultiplier = PuzzleEconomy.ModeMultipliers[string.lower(tostring(mode or "Classic"))] or 1,
			speedBonus = 0,
			hintPenalty = 0,
			resetPenalty = 0,
			cleanHintBonus = 0,
			cleanResetBonus = 0,
			preMultiplierReward = math.max(0, math.floor(tonumber(fallbackReward) or 0)),
			completionMultiplier = PuzzleEconomy.CompletionRewardMultiplier,
			reward = scaledFallbackReward,
			rewardSource = "fallback",
		}
	end

	local definition = DefinitionBuilder.BuildDefinition(
		math.max(1, math.floor(tonumber(level) or 1)),
		tostring(mode or "Classic"),
		math.max(1, math.floor(tonumber(boardState.seed) or 1))
	)

	local breakdown = PuzzleEconomy.CalculateCompletionBreakdown({
		mode = mode,
		gridSize = definition and definition.gridSize or 5,
		time = math.max(0, tonumber(clearTimeMillis) or 0) / 1000,
		hints = math.max(0, math.floor(tonumber(boardState.hintUses) or 0)),
		resets = 0,
	})
	breakdown.rewardSource = "calculated"
	return breakdown.reward, breakdown
end

local function processHintUsed(player, data, stats, storedBoardState, payloadBoardState, claimedWord)
	local availableHints = math.max(0, math.floor((data.resources and data.resources.hintsAvailable) or 0))
	if availableHints <= 0 then
		return {
			accepted = false,
			boardState = storedBoardState,
		}, false, "No hints available."
	end

	local result = GameService.ValidateHintUsed(player, storedBoardState, payloadBoardState, claimedWord)
	if result.accepted then
		data.resources.hintsAvailable = availableHints - 1
		stats.hintsUsed = math.max(0, math.floor((stats.hintsUsed or 0) + 1))
		AnalyticsService.TrackHintUsed(player, result.mode)
	end
	if result.boardState then
		data.boardState = result.boardState
	end

	return result, result.accepted == true, result.accepted and nil or "Hint could not be used."
end

function ProgressionService.RecordAction(player, actionName, payload)
	payload = type(payload) == "table" and payload or {}

	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	local stats = data.stats
	local progression = data.progression
	local activity = data.activity
	local sanitizedStoredBoardState = DataService.SanitizeBoardState(data.boardState)
	local storedBoardState = filterBoardStateForProgression(sanitizedStoredBoardState, progression)
	local payloadBoardState = filterBoardStateForProgression(sanitizePayloadBoardState(payload), progression)
	if sanitizedStoredBoardState and not storedBoardState then
		data.boardState = nil
	end
	local dailyCompletedToday, dailyIdentity = hasCompletedDailyToday(data)
	if dailyCompletedToday and (isDailyBoardState(storedBoardState) or isDailyBoardState(payloadBoardState)) then
		GameService.ClearPlayer(player)
		data.boardState = nil
		return DataService.GetSnapshot(player)
	end

	if actionName == "WordFound" then
		local result = GameService.ValidateWordFound(player, storedBoardState, payloadBoardState, payload.word, payload.path)
		if result.accepted then
			stats.totalWordsFound = math.max(0, math.floor((stats.totalWordsFound or 0) + 1))
			activity.dailyWordsFound = math.max(0, math.floor((activity.dailyWordsFound or 0) + 1))
		end
		if result.boardState then
			data.boardState = result.boardState
		end
	elseif actionName == "BoardStateUpdated" then
		local validatedBoardState = GameService.ProcessBoardState(player, storedBoardState, payloadBoardState)
		if validatedBoardState then
			data.boardState = validatedBoardState
		end
	elseif actionName == "BoardStateCleared" then
		GameService.ClearBoardState(player)
		data.boardState = nil
	elseif actionName == "HintUsed" then
		processHintUsed(player, data, stats, storedBoardState, payloadBoardState, payload.word)
	elseif actionName == "ClientFunnel" then
		local stepName = sanitizeClientFunnelStep(payload.step or payload.name)
		if stepName then
			local details = type(payload.details) == "table" and payload.details or nil
			AnalyticsService.TrackCriticalStep(player, stepName, details)
		end
		return nil
	elseif actionName == "BoardCleared" then
		local finalBoardState = GameService.ProcessBoardState(player, storedBoardState, payloadBoardState)
			or storedBoardState
			or payloadBoardState
		local result = GameService.ValidateBoardCleared(player, storedBoardState, finalBoardState)
		if result.accepted then
			local mode = result.mode
			local level = result.level
			local starMetadata = buildStarMetadata(mode, dailyIdentity)
			local clearTimeMillis = math.max(0, math.floor(tonumber(result.clearTimeMillis) or 0))
			local awardedStars = StarRules.CalculateAward(
				mode,
				level,
				finalBoardState and finalBoardState.hintUses,
				true
			)
			local awardedPuzzlePieces, puzzlePieceBreakdown = calculateAwardedPuzzlePieces(
				mode,
				level,
				finalBoardState,
				clearTimeMillis,
				result.reward
			)

			DataService.RecordModeOutcome(data, mode, true)
			data.resources.puzzlePieces = math.max(
				0,
				math.floor(tonumber((data.resources and data.resources.puzzlePieces) or 0) + awardedPuzzlePieces)
			)
			data.boardState = nil
			activity.dailyBoardsCleared = math.max(0, math.floor((activity.dailyBoardsCleared or 0) + 1))
			recordStarProgress(data, mode, level, awardedStars, starMetadata)

			if mode == "Daily" then
				data.dailyMode.completedDayStamp = dailyIdentity.dayStamp
			elseif mode ~= "Classic" then
				stats.endlessBoards = math.max(0, math.floor((stats.endlessBoards or 0) + 1))
				if mode == "Freeplay" then
					stats.freeplayBoards = math.max(0, math.floor((stats.freeplayBoards or 0) + 1))
				elseif mode == "Backwards" then
					stats.backwardsBoards = math.max(0, math.floor((stats.backwardsBoards or 0) + 1))
				end
			else
				stats.classicBoards = math.max(0, math.floor((stats.classicBoards or 0) + 1))
				local unlockedLevel = math.min(MAX_CLASSIC_LEVEL, level + 1)
				progression.lastClassicLevel = math.max(progression.lastClassicLevel or 1, unlockedLevel)
				progression.highestClassicLevel = math.max(progression.highestClassicLevel or 1, unlockedLevel)
			end

			if clearTimeMillis > 0 then
				local fastestBoardClearMillis = math.max(0, math.floor(tonumber(stats.fastestBoardClearMillis) or 0))
				if fastestBoardClearMillis <= 0 or clearTimeMillis < fastestBoardClearMillis then
					stats.fastestBoardClearMillis = clearTimeMillis
				end
			end

			AnalyticsService.TrackEconomySource(player, "pieces", "board_clear", awardedPuzzlePieces, {
				mode = mode,
				level = level,
				stars = awardedStars,
				clearTimeMillis = clearTimeMillis,
				gridSize = puzzlePieceBreakdown and puzzlePieceBreakdown.gridSize,
				timeSpentSeconds = puzzlePieceBreakdown and puzzlePieceBreakdown.timeSpent,
				hintsUsed = puzzlePieceBreakdown and puzzlePieceBreakdown.hintsUsed,
				resetsUsed = puzzlePieceBreakdown and puzzlePieceBreakdown.resetsUsed,
				basePieces = puzzlePieceBreakdown and puzzlePieceBreakdown.basePieces,
				modeMultiplier = puzzlePieceBreakdown and puzzlePieceBreakdown.modeMultiplier,
				speedBonus = puzzlePieceBreakdown and puzzlePieceBreakdown.speedBonus,
				hintPenalty = puzzlePieceBreakdown and puzzlePieceBreakdown.hintPenalty,
				resetPenalty = puzzlePieceBreakdown and puzzlePieceBreakdown.resetPenalty,
				cleanHintBonus = puzzlePieceBreakdown and puzzlePieceBreakdown.cleanHintBonus,
				cleanResetBonus = puzzlePieceBreakdown and puzzlePieceBreakdown.cleanResetBonus,
				preMultiplierReward = puzzlePieceBreakdown and puzzlePieceBreakdown.preMultiplierReward,
				rewardMultiplier = puzzlePieceBreakdown and puzzlePieceBreakdown.completionMultiplier,
				rewardSource = puzzlePieceBreakdown and puzzlePieceBreakdown.rewardSource,
			})

			AnalyticsService.TrackModeComplete(player, mode, {
				level = level,
				reward = awardedPuzzlePieces,
				pieces = awardedPuzzlePieces,
				stars = awardedStars,
				pack = StarRules.GetPackName(mode, level),
			})
			AnalyticsService.TrackBoardMilestone(player, stats.boardsCleared)
			local snapshot = DataService.GetSnapshot(player)
			SocialService.MarkSnapshotDirty(player, snapshot)
			return snapshot
		end
	elseif actionName == "BoardLost" then
		local lossBoardState = storedBoardState and GameService.ProcessBoardState(player, storedBoardState, payloadBoardState)
			or storedBoardState

		DataService.RecordModeOutcome(
			data,
			(type(lossBoardState) == "table" and lossBoardState.mode) or nil,
			false
		)
		GameService.ClearBoardState(player)
		data.boardState = nil
	end

	local snapshot = DataService.GetSnapshot(player)
	if actionName == "BoardLost" then
		SocialService.MarkSnapshotDirty(player, snapshot)
	end
	if actionName == "WordFound" or actionName == "BoardStateUpdated" or actionName == "BoardStateCleared" then
		return nil
	end
	return snapshot
end

function ProgressionService.UseHint(player, payload)
	payload = type(payload) == "table" and payload or {}
	if tostring(payload.mode or "") == "Duel" then
		return DuelService:UseHint(player, payload.word)
	end

	local data = DataService.GetMutableData(player)
	RewardService.NormalizeData(data)
	local stats = data.stats
	local progression = data.progression
	local sanitizedStoredBoardState = DataService.SanitizeBoardState(data.boardState)
	local storedBoardState = filterBoardStateForProgression(sanitizedStoredBoardState, progression)
	local payloadBoardState = filterBoardStateForProgression(sanitizePayloadBoardState(payload), progression)
	if sanitizedStoredBoardState and not storedBoardState then
		data.boardState = nil
	end
	local dailyCompletedToday = hasCompletedDailyToday(data)
	if dailyCompletedToday and (isDailyBoardState(storedBoardState) or isDailyBoardState(payloadBoardState)) then
		GameService.ClearPlayer(player)
		data.boardState = nil
		return {
			success = false,
			accepted = false,
			message = "Daily already completed.",
			snapshot = DataService.GetSnapshot(player),
			boardState = nil,
		}
	end
	local result, accepted, message = processHintUsed(player, data, stats, storedBoardState, payloadBoardState, payload.word)
	local snapshot = DataService.GetSnapshot(player)

	return {
		success = accepted,
		accepted = accepted,
		message = message,
		snapshot = snapshot,
		boardState = result and result.boardState or nil,
	}
end

function ProgressionService.ClearPlayer(player)
	GameService.ClearPlayer(player)
end

return ProgressionService
