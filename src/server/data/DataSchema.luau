local DataSchema = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local GameConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("GameConfig"))
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local MetaConfig = GameConfig.Meta
local TimedRewards = ProgressionConfig.TimedRewards

local MAX_STORED_RECEIPTS = 150
local CURRENT_DATA_VERSION = 11
local VALID_BOARD_MODES = {
	Classic = true,
	Themed = true,
	Freeplay = true,
	Backwards = true,
	Fog = true,
	OneLife = true,
	Mega = true,
	Daily = true,
}
local MODE_RESULT_NAMES = {
	"Total",
	"Classic",
	"Themed",
	"Daily",
	"Freeplay",
	"Backwards",
	"Fog",
	"OneLife",
	"Mega",
	"Duel",
}
local MODE_RESULT_NAME_SET = {}
local MODE_STREAK_NAMES = {
	"Classic",
	"Themed",
	"Daily",
	"Freeplay",
	"Backwards",
	"Fog",
	"OneLife",
	"Mega",
	"Duel",
}

for _, modeName in ipairs(MODE_RESULT_NAMES) do
	MODE_RESULT_NAME_SET[modeName] = true
end

local function deepMergeDefaults(target, defaults)
	target = target or {}

	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				deepMergeDefaults(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			deepMergeDefaults(target[key], value)
		end
	end

	return target
end

local function clampInt(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function formatWinRatioText(wins, losses)
	local total = clampInt(wins) + clampInt(losses)
	if total <= 0 then
		return "0%"
	end

	return string.format("%d%%", math.floor(((clampInt(wins) / total) * 100) + 0.5))
end

local function createDefaultModeResults()
	local modeResults = {}

	for _, modeName in ipairs(MODE_RESULT_NAMES) do
		modeResults[modeName] = {
			wins = 0,
			losses = 0,
		}
	end

	return modeResults
end

local function createDefaultModeStreaks()
	local modeStreaks = {}

	for _, modeName in ipairs(MODE_STREAK_NAMES) do
		modeStreaks[modeName] = {
			current = 0,
			best = 0,
		}
	end

	return modeStreaks
end

local function createDefaultTimedRewards()
	local timedRewards = {
		playtimeSeconds = 0,
		rewardClaims = {},
	}

	for index = 1, TimedRewards.GetRewardCount() do
		timedRewards.rewardClaims[TimedRewards.GetRewardValueName(index)] = false
	end

	return timedRewards
end

local function normalizeModeResultName(modeName)
	local normalized = tostring(modeName or "")
	if MODE_RESULT_NAME_SET[normalized] and normalized ~= "Total" then
		return normalized
	end

	return nil
end

local function ensureModeResults(stats)
	stats = type(stats) == "table" and stats or {}

	local modeResults = createDefaultModeResults()
	local storedModeResults = type(stats.modeResults) == "table" and stats.modeResults or nil

	for _, modeName in ipairs(MODE_RESULT_NAMES) do
		local storedBucket = storedModeResults and storedModeResults[modeName] or nil
		if type(storedBucket) == "table" then
			modeResults[modeName].wins = clampInt(storedBucket.wins)
			modeResults[modeName].losses = clampInt(storedBucket.losses)
		end
	end

	modeResults.Total.wins = math.max(modeResults.Total.wins, clampInt(stats.boardsCleared))
	modeResults.Total.losses = math.max(modeResults.Total.losses, clampInt(stats.losses))
	modeResults.Classic.wins = math.max(modeResults.Classic.wins, clampInt(stats.classicBoards))
	modeResults.Freeplay.wins = math.max(modeResults.Freeplay.wins, clampInt(stats.freeplayBoards))
	modeResults.Backwards.wins = math.max(modeResults.Backwards.wins, clampInt(stats.backwardsBoards))

	stats.modeResults = modeResults
	stats.boardsCleared = math.max(clampInt(stats.boardsCleared), modeResults.Total.wins)
	stats.losses = math.max(clampInt(stats.losses), modeResults.Total.losses)
	stats.classicBoards = clampInt(stats.classicBoards)
	stats.freeplayBoards = clampInt(stats.freeplayBoards)
	stats.backwardsBoards = clampInt(stats.backwardsBoards)
	stats.endlessBoards = clampInt(stats.endlessBoards)

	return modeResults
end

local function ensureModeStreaks(stats)
	stats = type(stats) == "table" and stats or {}

	local modeStreaks = createDefaultModeStreaks()
	local storedModeStreaks = type(stats.modeStreaks) == "table" and stats.modeStreaks or nil

	for _, modeName in ipairs(MODE_STREAK_NAMES) do
		local storedBucket = storedModeStreaks and storedModeStreaks[modeName] or nil
		if type(storedBucket) == "table" then
			modeStreaks[modeName].current = clampInt(storedBucket.current or storedBucket.Current)
			modeStreaks[modeName].best = clampInt(storedBucket.best or storedBucket.Best)
		end
	end

	stats.modeStreaks = modeStreaks

	local currentStreak = clampInt(stats.currentStreak)
	local highestStreak = math.max(clampInt(stats.highestStreak), clampInt(stats.longestStreak))

	for _, modeName in ipairs(MODE_STREAK_NAMES) do
		local bucket = modeStreaks[modeName]
		currentStreak = math.max(currentStreak, bucket.current)
		highestStreak = math.max(highestStreak, bucket.best)
	end

	stats.currentStreak = currentStreak
	stats.highestStreak = highestStreak
	stats.longestStreak = highestStreak

	return modeStreaks
end

local function normalizeStoredData(data)
	data = type(data) == "table" and data or {}
	local storedVersion = clampInt(data.version)
	data.resources = type(data.resources) == "table" and data.resources or {}
	data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable)
	if storedVersion < CURRENT_DATA_VERSION then
		local retiredTimerItems = clampInt(data.resources.timeBoostsAvailable)
			+ clampInt(data.resources.freezeTimeAvailable)
		data.resources.hintsAvailable += retiredTimerItems
	end
	data.resources.timeBoostsAvailable = nil
	data.resources.freezeTimeAvailable = nil
	data.resources.puzzlePieces = clampInt(data.resources.puzzlePieces)
	data.version = CURRENT_DATA_VERSION
	data.progression = type(data.progression) == "table" and data.progression or {}
	data.progression.giftClaimMilestone = clampInt(data.progression.giftClaimMilestone)
	data.stats = type(data.stats) == "table" and data.stats or {}
	ensureModeResults(data.stats)
	ensureModeStreaks(data.stats)
	data.account = type(data.account) == "table" and data.account or {}
	data.account.groupRewardClaimed = data.account.groupRewardClaimed == true
	data.account.processedReceipts = type(data.account.processedReceipts) == "table" and data.account.processedReceipts or {}
	do
		local normalizedReceipts = {}
		local receiptEntries = {}
		for receiptId, receiptTimestamp in pairs(data.account.processedReceipts) do
			local normalizedId = tostring(receiptId or "")
			if normalizedId ~= "" then
				table.insert(receiptEntries, {
					id = normalizedId,
					timestamp = clampInt(receiptTimestamp),
				})
			end
		end
		table.sort(receiptEntries, function(left, right)
			if left.timestamp == right.timestamp then
				return left.id < right.id
			end
			return left.timestamp > right.timestamp
		end)
		for index, entry in ipairs(receiptEntries) do
			if index > MAX_STORED_RECEIPTS then
				break
			end
			normalizedReceipts[entry.id] = entry.timestamp
		end
		data.account.processedReceipts = normalizedReceipts
	end
	data.persistence = type(data.persistence) == "table" and data.persistence or {}
	data.persistence.sessionToken = tostring(data.persistence.sessionToken or "")
	data.persistence.saveRevision = clampInt(data.persistence.saveRevision)
	data.persistence.lastSavedAt = clampInt(data.persistence.lastSavedAt)
	data.persistence.snapshotVersion = clampInt(data.persistence.snapshotVersion)
	data.timedRewards = type(data.timedRewards) == "table" and data.timedRewards or {}
	data.timedRewards.playtimeSeconds = math.max(
		clampInt(data.timedRewards.playtimeSeconds or data.timedRewards.Playtime),
		clampInt(data.stats.totalPlaySeconds)
	)
	data.timedRewards.rewardClaims = type(data.timedRewards.rewardClaims) == "table" and data.timedRewards.rewardClaims or {}
	for index = 1, TimedRewards.GetRewardCount() do
		local rewardName = TimedRewards.GetRewardValueName(index)
		data.timedRewards.rewardClaims[rewardName] = data.timedRewards.rewardClaims[rewardName] == true
			or data.timedRewards[rewardName] == true
	end
	return data
end

local function defaultData()
	return {
		version = CURRENT_DATA_VERSION,
		resources = {
			hintsAvailable = MetaConfig.DEFAULTS.StartingHints,
			puzzlePieces = 0,
		},
		progression = {
			lastClassicLevel = 1,
			highestClassicLevel = 1,
			giftClaimMilestone = 0,
		},
		stats = {
			totalWordsFound = 0,
			boardsCleared = 0,
			losses = 0,
			classicBoards = 0,
			freeplayBoards = 0,
			backwardsBoards = 0,
			endlessBoards = 0,
			hintsUsed = 0,
			totalPlaySeconds = 0,
			fastestBoardClearMillis = 0,
			currentStreak = 0,
			highestStreak = 0,
			longestStreak = 0,
			modeResults = createDefaultModeResults(),
			modeStreaks = createDefaultModeStreaks(),
		},
		account = {
			groupRewardClaimed = false,
			processedReceipts = {},
		},
		persistence = {
			sessionToken = "",
			saveRevision = 0,
			lastSavedAt = 0,
			snapshotVersion = 0,
		},
		settings = {
			SFX = MetaConfig.DEFAULTS.Settings.SFX,
			Music = MetaConfig.DEFAULTS.Settings.Music,
		},
		activity = {
			dailyDayStamp = -1,
			dailyBoardsCleared = 0,
			dailyWordsFound = 0,
		},
		dailyReward = {
			currentStreak = 0,
			bestStreak = 0,
			lastClaimDay = -1,
		},
		dailyMode = {
			completedDayStamp = -1,
		},
		timedRewards = createDefaultTimedRewards(),
		starProgress = {},
	}
end

DataSchema.Version = CURRENT_DATA_VERSION
DataSchema.ValidBoardModes = VALID_BOARD_MODES
DataSchema.ModeResultNames = MODE_RESULT_NAMES
DataSchema.ModeStreakNames = MODE_STREAK_NAMES
DataSchema.MergeDefaults = deepMergeDefaults
DataSchema.ClampInt = clampInt
DataSchema.FormatWinRatioText = formatWinRatioText
DataSchema.CreateModeResults = createDefaultModeResults
DataSchema.CreateModeStreaks = createDefaultModeStreaks
DataSchema.CreateTimedRewards = createDefaultTimedRewards
DataSchema.NormalizeModeResultName = normalizeModeResultName
DataSchema.EnsureModeResults = ensureModeResults
DataSchema.EnsureModeStreaks = ensureModeStreaks
DataSchema.Normalize = normalizeStoredData
DataSchema.CreateDefault = defaultData

return DataSchema
