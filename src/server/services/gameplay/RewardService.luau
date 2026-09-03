--[[
	RewardService

	Server-only round result calculator. Callers provide measurements produced by
	the authoritative RoundService; client-supplied stars, XP, rewards, difficulty,
	or daily identity are ignored. Persistence is delegated to DataService's durable,
	idempotent ApplyRoundCompletion operation.

	Public API (dot calls):
		CalculateStars(context, level?) -> stars, details
		CalculateXp(mode, difficulty, stars) -> xp
		CalculateResult(context) -> result?, error?
		CalculateAndApply(player, context) -> success, rewardResult?, error?
		Apply(player, context) -> success, rewardResult?, error? -- alias
		ApplyRoundCompletion(player, context) -> success, rewardResult?, error? -- alias
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local serverFolder = script.Parent.Parent.Parent
local contentFolder = assert(serverFolder:WaitForChild("content", 10), "Word Search server content folder is missing")
local dataFolder = assert(serverFolder:WaitForChild("data", 10), "Word Search data folder is missing")
local metaFolder = assert(script.Parent.Parent:WaitForChild("meta", 10), "Word Search meta services folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
local DataService = require(assert(dataFolder:WaitForChild("DataService", 10), "Word Search DataService is missing"))
local DailyPuzzleService = require(assert(metaFolder:WaitForChild("DailyPuzzleService", 10), "Word Search DailyPuzzleService is missing"))

local RewardService = {}

local MAX_COMPLETION_ID_LENGTH = 128
local MAX_ELAPSED_MS = 7 * 24 * 60 * 60 * 1000
local MAX_ROUND_COUNTER = 100_000
local DEFAULT_TIME_LIMITS = {
	Easy = 100,
	Medium = 140,
	Hard = 185,
	Expert = 240,
}

local cachedCatalog = nil
local rewardTimesByUserId = {}

local function finiteNumber(value, fallback)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return fallback
	end
	return numberValue
end

local function clampInteger(value, minimum, maximum)
	return math.clamp(math.floor(finiteNumber(value, minimum)), minimum, maximum)
end

local function getLevelCatalog()
	if cachedCatalog then
		return cachedCatalog
	end

	local moduleScript = contentFolder:FindFirstChild("LevelCatalog")
	if not (moduleScript and moduleScript:IsA("ModuleScript")) then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if ok and type(result) == "table" then
		cachedCatalog = result
		return result
	end
	return nil
end

local function safeCatalogCall(methodName, ...)
	local catalog = getLevelCatalog()
	local method = catalog and catalog[methodName]
	if type(method) ~= "function" then
		return nil
	end

	local ok, result = pcall(method, ...)
	if ok then
		return result
	end
	ok, result = pcall(method, catalog, ...)
	return ok and result or nil
end

local function resolveLevel(levelId)
	if levelId == nil then
		return nil
	end

	local stringId = tostring(levelId)
	local level = safeCatalogCall("GetLevel", stringId)
	if type(level) == "table" then
		return level
	end

	local numericId = tonumber(levelId)
	if numericId then
		level = safeCatalogCall("GetLevelByIndex", math.floor(numericId)) or safeCatalogCall("GetLevel", math.floor(numericId))
		if type(level) == "table" then
			return level
		end
	end

	local levels = safeCatalogCall("GetLevels")
	if type(levels) ~= "table" then
		local publicCatalog = safeCatalogCall("GetPublicCatalog")
		levels = type(publicCatalog) == "table" and publicCatalog.levels or nil
	end
	if type(levels) == "table" then
		for _, candidate in ipairs(levels) do
			if type(candidate) == "table" and tostring(candidate.id or candidate.levelId or "") == stringId then
				return candidate
			end
		end
	end
	return nil
end

local function getConfiguredThreshold(level, names)
	for _, containerName in ipairs({ "starTimes", "starThresholds", "stars" }) do
		local container = type(level) == "table" and level[containerName] or nil
		if type(container) == "table" then
			for _, name in ipairs(names) do
				local value = finiteNumber(container[name], nil)
				if value and value > 0 then
					return value
				end
			end
		end
	end

	for _, name in ipairs(names) do
		local value = finiteNumber(type(level) == "table" and level[name] or nil, nil)
		if value and value > 0 then
			return value
		end
	end
	return nil
end

local function getExpectedWordCount(level, context)
	if type(level) == "table" then
		if type(level.words) == "table" then
			return #level.words
		end
		local count = tonumber(level.wordCount)
		if count then
			return math.max(0, math.floor(count))
		end
	end

	local puzzle = type(context.puzzle) == "table" and context.puzzle
		or (type(context.definition) == "table" and context.definition or nil)
	if puzzle and type(puzzle.words) == "table" then
		return #puzzle.words
	end
	local reportedCount = finiteNumber(context.wordCount, nil)
	return reportedCount and math.max(0, math.floor(reportedCount)) or nil
end

function RewardService.CalculateStars(context, level)
	context = type(context) == "table" and context or {}
	level = type(level) == "table" and level or {}
	local difficulty = tostring(level.difficulty or context.difficulty or "Easy")
	local elapsedSeconds = math.max(0, finiteNumber(context.elapsedMs, 0) / 1000)
	local mistakes = clampInteger(context.mistakes, 0, MAX_ROUND_COUNTER)
	local hintsUsed = clampInteger(context.hintsUsed, 0, MAX_ROUND_COUNTER)
	local pauseCount = clampInteger(context.pauseCount, 0, MAX_ROUND_COUNTER)
	local timeLimit = finiteNumber(level.timeLimitSeconds or level.timeLimit or context.timeLimitSeconds, nil)
	if not timeLimit or timeLimit <= 0 then
		timeLimit = DEFAULT_TIME_LIMITS[difficulty] or DEFAULT_TIME_LIMITS.Medium
	end

	local threeStarSeconds = getConfiguredThreshold(level, {
		3,
		"3",
		"three",
		"threeStarSeconds",
		"threeStars",
	}) or (timeLimit * 0.6)
	local twoStarSeconds = getConfiguredThreshold(level, {
		2,
		"2",
		"two",
		"twoStarSeconds",
		"twoStars",
	}) or (timeLimit * 0.85)
	twoStarSeconds = math.max(threeStarSeconds, twoStarSeconds)

	local stars
	if elapsedSeconds <= threeStarSeconds then
		stars = 3
	elseif elapsedSeconds <= twoStarSeconds then
		stars = 2
	else
		stars = 1
	end

	-- Three stars represent a genuinely clean solve. Larger assistance/error counts
	-- cap the result further while every completed puzzle still earns one star.
	if hintsUsed > 0 or mistakes > 0 then
		stars = math.min(stars, 2)
	end
	if hintsUsed >= 2 or mistakes >= 4 then
		stars = 1
	end
	-- A pause is useful accessibility, but the board remains visible behind the
	-- overlay. Capping ranked modes at two stars prevents pause-to-inspect exploits.
	if pauseCount > 0 and tostring(context.mode or "") ~= "Zen" then
		stars = math.min(stars, 2)
	end

	return stars, {
		elapsedSeconds = elapsedSeconds,
		threeStarSeconds = threeStarSeconds,
		twoStarSeconds = twoStarSeconds,
		timeLimitSeconds = timeLimit,
		pausePenalty = pauseCount > 0,
	}
end

local function rewardEligibility(player, result)
	if result.mode == "Zen" then
		return false, "Zen Mode is untimed and does not grant ranked rewards."
	end

	local guard = type(GameConfig.Gameplay) == "table" and GameConfig.Gameplay.RewardGuard or nil
	guard = type(guard) == "table" and guard or {}
	local baseSeconds = math.clamp(finiteNumber(guard.MinSolveBaseSeconds, 1.5), 0, 60)
	local perWordSeconds = math.clamp(finiteNumber(guard.MinSecondsPerWord, 0.3), 0, 10)
	local minimumSeconds = baseSeconds + (math.max(1, result.wordsFound) * perWordSeconds)
	if (result.elapsedMs / 1000) + 0.001 < minimumSeconds then
		return false, "This solve was too fast to rank, so no progress or reward was granted."
	end

	local userId = player and tonumber(player.UserId)
	if not userId then
		return false, "This completion could not be ranked."
	end
	local windowSeconds = math.clamp(finiteNumber(guard.WindowSeconds, 60), 10, 3600)
	local maximum = math.clamp(math.floor(finiteNumber(guard.MaxRankedCompletionsPerWindow, 6)), 1, 100)
	local now = os.clock()
	local history = rewardTimesByUserId[userId] or {}
	local retained = {}
	for _, timestamp in ipairs(history) do
		if now - timestamp < windowSeconds then
			table.insert(retained, timestamp)
		end
	end
	rewardTimesByUserId[userId] = retained
	if #retained >= maximum then
		return false, "Too many completions arrived at once, so this solve was not ranked."
	end
	return true, nil
end

local function unrankedResult(result, snapshot, message)
	return {
		completionId = result.completionId,
		mode = result.mode,
		levelId = result.levelId,
		elapsedMs = result.elapsedMs,
		stars = 0,
		xp = 0,
		hintReward = 0,
		coinReward = 0,
		mistakes = result.mistakes,
		hintsUsed = result.hintsUsed,
		wordsFound = result.wordsFound,
		applied = false,
		unranked = true,
		message = message,
		snapshot = snapshot,
	}
end

function RewardService.CalculateXp(mode, difficulty, stars)
	local progression = type(GameConfig.Progression) == "table" and GameConfig.Progression or {}
	local xpByDifficulty = type(progression.XpByDifficulty) == "table" and progression.XpByDifficulty or {}
	local baseXp = clampInteger(xpByDifficulty[tostring(difficulty or "Easy")], 0, 1_000_000)
	local starBonus = clampInteger(progression.StarXpBonus, 0, 100_000)
	local dailyBonus = mode == "Daily" and clampInteger(progression.DailyXpBonus, 0, 100_000) or 0
	return math.min(1_000_000, baseXp + (clampInteger(stars, 0, 3) * starBonus) + dailyBonus)
end

function RewardService.CalculateCoins(mode, difficulty, stars)
	local progression = type(GameConfig.Progression) == "table" and GameConfig.Progression or {}
	local byDifficulty = type(progression.CoinByDifficulty) == "table" and progression.CoinByDifficulty or {}
	local baseCoins = clampInteger(byDifficulty[tostring(difficulty or "Easy")], 0, 1_000_000)
	local starBonus = clampInteger(progression.StarCoinBonus, 0, 100_000)
	local dailyBonus = mode == "Daily" and clampInteger(progression.DailyCoinBonus, 0, 100_000) or 0
	return math.min(1_000_000, baseCoins + (clampInteger(stars, 0, 3) * starBonus) + dailyBonus)
end

function RewardService.CalculateResult(context)
	if type(context) ~= "table" then
		return nil, "Invalid completion context."
	end

	local completionId = type(context.completionId) == "string" and context.completionId or ""
	if completionId == "" or #completionId > MAX_COMPLETION_ID_LENGTH or string.find(completionId, "%c") then
		return nil, "Invalid completion ID."
	end
	local mode = type(context.mode) == "string" and context.mode or ""
	local modeConfig = type(GameConfig.Modes) == "table" and GameConfig.Modes[mode] or nil
	if type(modeConfig) ~= "table" then
		return nil, "Invalid game mode."
	end

	local elapsedNumber = finiteNumber(context.elapsedMs, nil)
	if not elapsedNumber or elapsedNumber < 0 or elapsedNumber > MAX_ELAPSED_MS then
		return nil, "Invalid completion time."
	end

	local levelId = context.levelId ~= nil and tostring(context.levelId) or nil
	local sourceLevelId = context.sourceLevelId ~= nil and tostring(context.sourceLevelId) or levelId
	local level = resolveLevel(sourceLevelId)
	local dailyDayStamp = nil
	if mode == "Daily" then
		local identity = DailyPuzzleService.GetIdentity()
		dailyDayStamp = identity.dayStamp
		if context.dailyDayStamp ~= nil and clampInteger(context.dailyDayStamp, 0, 1_000_000_000) ~= dailyDayStamp then
			return nil, "Daily puzzle is no longer current."
		end
		if levelId and levelId ~= tostring(identity.levelId) then
			return nil, "Daily puzzle identity does not match."
		end
		levelId = tostring(identity.levelId)
		level = resolveLevel(levelId) or identity.level
	end
	if modeConfig.tracksLevelProgress == true and type(level) ~= "table" then
		return nil, "Unknown level."
	end

	local maxWords = math.max(1, math.floor(tonumber(GameConfig.Gameplay and GameConfig.Gameplay.MaxWords) or 100))
	local wordsFound = clampInteger(context.wordsFound ~= nil and context.wordsFound or context.wordCount, 0, maxWords)
	local expectedWords = getExpectedWordCount(level, context)
	if expectedWords and expectedWords > 0 and wordsFound ~= expectedWords then
		return nil, "Puzzle is incomplete."
	end

	local mistakes = clampInteger(context.mistakes, 0, MAX_ROUND_COUNTER)
	local hintsUsed = clampInteger(context.hintsUsed, 0, MAX_ROUND_COUNTER)
	local starContext = {
		elapsedMs = elapsedNumber,
		mistakes = mistakes,
		hintsUsed = hintsUsed,
		pauseCount = context.pauseCount,
		mode = mode,
		difficulty = level and level.difficulty or context.difficulty,
		timeLimitSeconds = level and (level.timeLimitSeconds or level.timeLimit) or (context.timeLimitSeconds or context.timeLimit),
	}
	local stars, starDetails = RewardService.CalculateStars(starContext, level)
	local difficulty = tostring((level and level.difficulty) or context.difficulty or "Easy")
	local xp = RewardService.CalculateXp(mode, difficulty, stars)
	local coinReward = RewardService.CalculateCoins(mode, difficulty, stars)
	local hintReward = mode == "Daily"
		and clampInteger(GameConfig.Progression and GameConfig.Progression.DailyHintReward, 0, tonumber(GameConfig.Progression and GameConfig.Progression.MaxHints) or 999)
		or 0

	return {
		completionId = completionId,
		mode = mode,
		levelId = levelId,
		elapsedMs = math.floor(elapsedNumber),
		stars = stars,
		xp = xp,
		coinReward = coinReward,
		hintReward = hintReward,
		mistakes = mistakes,
		hintsUsed = hintsUsed,
		wordsFound = wordsFound,
		dailyDayStamp = dailyDayStamp,
		difficulty = difficulty,
		starDetails = starDetails,
		contentRevision = tostring(GameConfig.ContentRevision or "1"),
	}, nil
end

function RewardService.CalculateAndApply(player, context)
	local completionId = type(context) == "table" and context.completionId or nil
	if type(completionId) == "string" and completionId ~= "" then
		local receiptFound, retrySnapshotOrError, receipt = DataService.RetryRoundCompletion(player, completionId)
		if receiptFound == false then
			return false, nil, tostring(retrySnapshotOrError or "Reward retry could not be saved.")
		elseif receiptFound == true then
			local stored = type(receipt) == "table" and receipt.result or nil
			local priorResult = {}
			for key, value in pairs(type(stored) == "table" and stored or {}) do
				priorResult[key] = value
			end
			priorResult.completionId = completionId
			priorResult.originalXp = priorResult.xp or 0
			priorResult.originalHintReward = priorResult.hintReward or 0
			priorResult.originalCoinReward = priorResult.coinReward or 0
			priorResult.xp = 0
			priorResult.hintReward = 0
			priorResult.coinReward = 0
			priorResult.applied = false
			priorResult.snapshot = retrySnapshotOrError
			return true, priorResult, nil
		end
	end

	local result, calculationError = RewardService.CalculateResult(context)
	if not result then
		return false, nil, calculationError
	end
	local eligible, eligibilityMessage = rewardEligibility(player, result)
	if not eligible then
		return true, unrankedResult(result, DataService.GetSnapshot(player), eligibilityMessage), nil
	end

	local success, snapshotOrError, newlyApplied, _, disposition = DataService.ApplyRoundCompletion(player, result)
	if not success then
		return false, nil, tostring(snapshotOrError or "Reward could not be saved.")
	end
	if disposition == "reward_velocity_limited" then
		return true, unrankedResult(
			result,
			snapshotOrError,
			"Too many recent completions were recorded, so this solve was not ranked."
		), nil
	end

	result.applied = newlyApplied == true
	if not newlyApplied then
		result.originalXp = result.xp
		result.originalHintReward = result.hintReward
		result.originalCoinReward = result.coinReward
		result.xp = 0
		result.hintReward = 0
		result.coinReward = 0
	end
	result.snapshot = snapshotOrError
	if newlyApplied == true then
		local userId = player and tonumber(player.UserId)
		if userId then
			local history = rewardTimesByUserId[userId] or {}
			table.insert(history, os.clock())
			rewardTimesByUserId[userId] = history
		end
	end
	return true, result, nil
end

function RewardService.ClearPlayer(player)
	local userId = player and tonumber(player.UserId)
	if userId then
		rewardTimesByUserId[userId] = nil
	end
end

RewardService.Apply = RewardService.CalculateAndApply
RewardService.ApplyRoundCompletion = RewardService.CalculateAndApply

return table.freeze(RewardService)
