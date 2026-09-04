local PlayerDataStore = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent.Parent
local SessionStore = require(serverFolder:WaitForChild("session"):WaitForChild("PlayerSessionStore"))
local utilFolder = serverFolder:WaitForChild("utils")
local InstanceUtils = require(utilFolder:WaitForChild("InstanceUtils"))
local SharedConfig = require(utilFolder:WaitForChild("SharedConfig"))
local TableUtils = require(utilFolder:WaitForChild("TableUtils"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels"))
local DailyMode = require(sharedFolder:WaitForChild("progression"):WaitForChild("DailyMode"))
local TimedRewards = require(sharedFolder:WaitForChild("config"):WaitForChild("TimedRewards"))

local DEFAULT_META_CONFIG = {
	DEFAULTS = {
		StartingHints = 0,
		Settings = {
			SFX = true,
			Music = true,
		},
	},
}

local cloneTable = TableUtils.CloneDeep
local getOrCreate = InstanceUtils.GetOrCreate
local MetaConfig = SharedConfig.Resolve("MetaConfig", DEFAULT_META_CONFIG)

local DATA_STORE = DataStoreService:GetDataStore("WordSearchData_v1")
local KEY_PREFIX = "player_"
local SESSION_TOKEN = HttpService:GenerateGUID(false)
local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local MAX_SAVED_BOARD_WORDS = 24
local MAX_STORED_RECEIPTS = 150
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
	data.version = math.max(10, clampInt(data.version))
	data.resources = type(data.resources) == "table" and data.resources or {}
	data.resources.hintsAvailable = clampInt(data.resources.hintsAvailable)
	data.resources.timeBoostsAvailable = clampInt(data.resources.timeBoostsAvailable)
	data.resources.freezeTimeAvailable = clampInt(data.resources.freezeTimeAvailable)
	data.resources.puzzlePieces = clampInt(data.resources.puzzlePieces)
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
		version = 10,
		resources = {
			hintsAvailable = MetaConfig.DEFAULTS.StartingHints,
			timeBoostsAvailable = 0,
			freezeTimeAvailable = 0,
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

local function getKey(userId)
	return KEY_PREFIX .. tostring(userId)
end

local function decodeStoredValue(rawValue)
	local decoded = nil

	if type(rawValue) == "string" and rawValue ~= "" then
		local decodeSuccess, decodeResult = pcall(function()
			return HttpService:JSONDecode(rawValue)
		end)
		if decodeSuccess then
			decoded = decodeResult
		end
	elseif type(rawValue) == "table" then
		decoded = rawValue
	end

	return decoded
end

local function prepareStoredData(decoded)
	local data = deepMergeDefaults(decoded or {}, defaultData())
	normalizeStoredData(data)
	return data
end

local function encodeStoredValue(data)
	return HttpService:JSONEncode(data)
end

local function setIntValue(parent, name, value)
	local intValue = getOrCreate(parent, "IntValue", name)
	intValue.Value = math.max(0, math.floor(tonumber(value) or 0))
	return intValue
end

local function setBoolValue(parent, name, value)
	local boolValue = getOrCreate(parent, "BoolValue", name)
	boolValue.Value = value == true
	return boolValue
end

local function setStringValue(parent, name, value)
	local stringValue = getOrCreate(parent, "StringValue", name)
	stringValue.Value = tostring(value or "")
	return stringValue
end

local function removeChildrenByName(parent, names)
	if not parent then
		return
	end

	for _, name in ipairs(names) do
		local child = parent:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

local function getSortedKeys(values)
	local keys = {}

	for key in pairs(values or {}) do
		table.insert(keys, tostring(key))
	end

	table.sort(keys)
	return keys
end

local function sanitizeWordArray(words)
	local sanitized = {}
	local seen = {}

	if type(words) ~= "table" then
		return sanitized
	end

	for _, word in ipairs(words) do
		if type(word) == "string" then
			local normalized = string.upper(word:gsub("%s+", ""))
			if normalized ~= "" and not seen[normalized] then
				seen[normalized] = true
				table.insert(sanitized, normalized)
				if #sanitized >= MAX_SAVED_BOARD_WORDS then
					break
				end
			end
		end
	end

	return sanitized
end

local function sanitizeStarEntries(entries)
	local sanitized = {}

	if type(entries) ~= "table" then
		return sanitized
	end

	for key, value in pairs(entries) do
		local entryKey = tostring(key or "")
		if entryKey ~= "" then
			sanitized[entryKey] = math.clamp(math.floor(tonumber(value) or 0), 0, 3)
		end
	end

	return sanitized
end

local function sanitizeStarProgress(starProgress)
	local sanitized = {}

	if type(starProgress) ~= "table" then
		return sanitized
	end

	for modeKey, packs in pairs(starProgress) do
		local normalizedModeKey = tostring(modeKey or "")
		if normalizedModeKey ~= "" and type(packs) == "table" then
			local sanitizedPacks = {}

			for packKey, entries in pairs(packs) do
				local normalizedPackKey = tostring(packKey or "")
				if normalizedPackKey ~= "" and type(entries) == "table" then
					local sanitizedEntries = sanitizeStarEntries(entries)
					if next(sanitizedEntries) ~= nil then
						sanitizedPacks[normalizedPackKey] = sanitizedEntries
					end
				end
			end

			if next(sanitizedPacks) ~= nil then
				sanitized[normalizedModeKey] = sanitizedPacks
			end
		end
	end

	return sanitized
end

local function refreshStarProgressFolder(parent, starProgress)
	if not parent then
		return
	end

	parent:ClearAllChildren()

	for _, modeKey in ipairs(getSortedKeys(starProgress)) do
		local modeFolder = getOrCreate(parent, "Folder", modeKey)
		local packs = starProgress[modeKey]

		for _, packKey in ipairs(getSortedKeys(packs)) do
			local packFolder = getOrCreate(modeFolder, "Folder", packKey)
			local entries = packs[packKey]

			for _, entryKey in ipairs(getSortedKeys(entries)) do
				setIntValue(packFolder, entryKey, entries[entryKey])
			end
		end
	end
end

local function sanitizeBoardState(boardState)
	if type(boardState) ~= "table" then
		return nil
	end

	local mode = type(boardState.mode) == "string" and boardState.mode or "Classic"
	if not VALID_BOARD_MODES[mode] then
		mode = "Classic"
	end
	local level = math.clamp(math.max(1, math.floor(tonumber(boardState.level) or 1)), 1, MAX_CLASSIC_LEVEL)
	local seed = math.max(1, math.floor(tonumber(boardState.seed) or 1))
	if mode == "Daily" then
		local dailyIdentity = DailyMode.GetDailyIdentity(MAX_CLASSIC_LEVEL)
		if level ~= dailyIdentity.level or seed ~= dailyIdentity.seed then
			return nil
		end
		level = dailyIdentity.level
		seed = dailyIdentity.seed
	end
	local remainingTime = tonumber(boardState.remainingTime)
	local sessionScore = math.max(0, math.floor(tonumber(boardState.sessionScore) or 0))
	local puzzlesCleared = math.max(0, math.floor(tonumber(boardState.puzzlesCleared) or 0))
	local streak = math.max(0, math.floor(tonumber(boardState.streak) or 0))
	local hintUses = math.max(0, math.floor(tonumber(boardState.hintUses) or 0))
	local freezeTimeRemaining = tonumber(boardState.freezeTimeRemaining)
	local startedAtServerTime = tonumber(boardState.startedAtServerTime)
	local timeBoostUsed = boardState.timeBoostUsed == true
	local freezeTimeUsed = boardState.freezeTimeUsed == true
	local foundWords = sanitizeWordArray(boardState.foundWords)
	local hintedWords = sanitizeWordArray(boardState.hintedWords)

	if remainingTime then
		remainingTime = math.max(1, math.floor(remainingTime))
	end
	if freezeTimeRemaining then
		freezeTimeRemaining = math.clamp(freezeTimeRemaining, 0, 30)
	end
	if startedAtServerTime then
		startedAtServerTime = math.max(0, startedAtServerTime)
	end

	return {
		mode = mode,
		level = level,
		seed = seed,
		foundWords = foundWords,
		hintedWords = hintedWords,
		remainingTime = remainingTime,
		timeBoostUsed = timeBoostUsed,
		freezeTimeUsed = freezeTimeUsed,
		freezeTimeRemaining = freezeTimeRemaining,
		sessionScore = sessionScore,
		puzzlesCleared = puzzlesCleared,
		streak = streak,
		hintUses = hintUses,
		startedAtServerTime = startedAtServerTime,
	}
end

local function pruneBoardStateForProgression(data)
	if type(data) ~= "table" then
		return nil
	end

	local boardState = sanitizeBoardState(data.boardState)
	if data.boardState and not boardState then
		data.boardState = nil
		return nil
	end

	if boardState and boardState.mode == "Classic" then
		local lastClassicLevel = math.clamp(
			math.max(1, math.floor(tonumber(data.progression and data.progression.lastClassicLevel) or 1)),
			1,
			MAX_CLASSIC_LEVEL
		)
		if boardState.level ~= lastClassicLevel then
			data.boardState = nil
			return nil
		end
	end

	data.boardState = boardState
	return boardState
end

local function updatePlaytime(player, data)
	local startedAt = SessionStore.GetSessionStartedAt(player.UserId)
	if not startedAt then
		SessionStore.TouchSession(player.UserId)
		return
	end

	local now = os.time()
	local elapsed = math.max(0, now - startedAt)
	if elapsed > 0 then
		data.stats.totalPlaySeconds = math.max(0, math.floor((data.stats.totalPlaySeconds or 0) + elapsed))
		SessionStore.TouchSession(player.UserId, now)
	end
end

local function buildSnapshot(data)
	normalizeStoredData(data)
	local modeStreaks = ensureModeStreaks(data.stats)
	local timedRewardsData = type(data.timedRewards) == "table" and data.timedRewards or createDefaultTimedRewards()
	data.starProgress = sanitizeStarProgress(data.starProgress)

	local dailyIdentity = DailyMode.GetDailyIdentity(MAX_CLASSIC_LEVEL)
	local completedDayStamp = math.floor(tonumber(data.dailyMode and data.dailyMode.completedDayStamp) or -1)
	local lastClassicLevel = math.clamp(math.max(1, math.floor((data.progression and data.progression.lastClassicLevel) or 1)), 1, MAX_CLASSIC_LEVEL)
	local highestClassicLevel = math.clamp(
		math.max(lastClassicLevel, math.floor((data.progression and data.progression.highestClassicLevel) or lastClassicLevel)),
		1,
		MAX_CLASSIC_LEVEL
	)
	local boardState = pruneBoardStateForProgression(data)
	if boardState and boardState.mode == "Daily" and completedDayStamp == dailyIdentity.dayStamp then
		boardState = nil
		data.boardState = nil
	end

	return {
		meta = {
			snapshotVersion = math.max(1, clampInt(data.persistence and data.persistence.snapshotVersion)),
		},
		inventory = {
			hintsAvailable = math.max(0, math.floor((data.resources and data.resources.hintsAvailable) or 0)),
			timeBoostsAvailable = math.max(0, math.floor((data.resources and data.resources.timeBoostsAvailable) or 0)),
			freezeTimeAvailable = math.max(0, math.floor((data.resources and data.resources.freezeTimeAvailable) or 0)),
			puzzlePieces = math.max(0, math.floor((data.resources and data.resources.puzzlePieces) or 0)),
		},
		progression = {
			lastClassicLevel = lastClassicLevel,
			highestClassicLevel = highestClassicLevel,
			giftClaimMilestone = math.max(0, math.floor((data.progression and data.progression.giftClaimMilestone) or 0)),
		},
		stats = {
			totalWordsFound = math.max(0, math.floor((data.stats and data.stats.totalWordsFound) or 0)),
			boardsCleared = math.max(0, math.floor((data.stats and data.stats.boardsCleared) or 0)),
			losses = math.max(0, math.floor((data.stats and data.stats.losses) or 0)),
			classicBoards = math.max(0, math.floor((data.stats and data.stats.classicBoards) or 0)),
			freeplayBoards = math.max(0, math.floor((data.stats and data.stats.freeplayBoards) or 0)),
			backwardsBoards = math.max(0, math.floor((data.stats and data.stats.backwardsBoards) or 0)),
			endlessBoards = math.max(0, math.floor((data.stats and data.stats.endlessBoards) or 0)),
			hintsUsed = math.max(0, math.floor((data.stats and data.stats.hintsUsed) or 0)),
			totalPlaySeconds = math.max(0, math.floor((data.stats and data.stats.totalPlaySeconds) or 0)),
			fastestBoardClearMillis = math.max(0, math.floor((data.stats and data.stats.fastestBoardClearMillis) or 0)),
			currentStreak = math.max(0, math.floor((data.stats and data.stats.currentStreak) or 0)),
			highestStreak = math.max(0, math.floor((data.stats and data.stats.highestStreak) or (data.stats and data.stats.longestStreak) or 0)),
			longestStreak = math.max(0, math.floor((data.stats and data.stats.longestStreak) or 0)),
			modeResults = cloneTable((data.stats and data.stats.modeResults) or createDefaultModeResults()),
			modeStreaks = cloneTable(modeStreaks),
		},
		account = {
			groupRewardClaimed = data.account and data.account.groupRewardClaimed == true,
		},
		settings = {
			SFX = data.settings and data.settings.SFX ~= false,
			Music = data.settings and data.settings.Music ~= false,
		},
		boardState = boardState,
		dailyMode = {
			dayStamp = dailyIdentity.dayStamp,
			level = dailyIdentity.level,
			seed = dailyIdentity.seed,
			completedDayStamp = completedDayStamp,
			completed = completedDayStamp == dailyIdentity.dayStamp,
			resetTimestamp = dailyIdentity.resetTimestamp,
			secondsUntilReset = dailyIdentity.secondsUntilReset,
		},
		timedRewards = {
			playtimeSeconds = clampInt(timedRewardsData.playtimeSeconds),
			rewardClaims = cloneTable(timedRewardsData.rewardClaims),
		},
		starProgress = cloneTable(data.starProgress),
	}
end

local function refreshPlayerDataFolder(player, data)
	normalizeStoredData(data)

	local dataFolder = getOrCreate(player, "Folder", "Data")
	local leaderstatsFolder = getOrCreate(player, "Folder", "leaderstats")
	local hintsFolder = getOrCreate(dataFolder, "Folder", "Hints")
	local powerupsFolder = getOrCreate(dataFolder, "Folder", "Powerups")
	local settingsFolder = getOrCreate(dataFolder, "Folder", "Settings")
	local accountFolder = getOrCreate(dataFolder, "Folder", "Account")
	local progressFolder = getOrCreate(dataFolder, "Folder", "Progress")
	local timedRewardsFolder = getOrCreate(dataFolder, "Folder", "TimedRewards")
	local progressionFolder = getOrCreate(dataFolder, "Folder", "Progression")
	local statsFolder = getOrCreate(dataFolder, "Folder", "Stats")
	local activityFolder = getOrCreate(dataFolder, "Folder", "Activity")
	local starsFolder = getOrCreate(dataFolder, "Folder", "Stars")
	local lastClassicLevel = math.clamp(math.max(1, math.floor(data.progression.lastClassicLevel or 1)), 1, MAX_CLASSIC_LEVEL)
	local highestClassicLevel = math.clamp(math.max(lastClassicLevel, math.floor(data.progression.highestClassicLevel or lastClassicLevel)), 1, MAX_CLASSIC_LEVEL)
	local fastestBoardClearMillis = math.max(0, math.floor((data.stats and data.stats.fastestBoardClearMillis) or 0))
	local fastestSolveSeconds = fastestBoardClearMillis > 0 and string.format("%.2f", fastestBoardClearMillis / 1000) or "0"
	local dailyIdentity = DailyMode.GetDailyIdentity(MAX_CLASSIC_LEVEL)
	local dailyCompleted = math.floor(tonumber(data.dailyMode and data.dailyMode.completedDayStamp) or -1) == dailyIdentity.dayStamp
	local modeResults = ensureModeResults(data.stats)
	local modeStreaks = ensureModeStreaks(data.stats)
	local timedRewardsData = type(data.timedRewards) == "table" and data.timedRewards or createDefaultTimedRewards()
	local wins = clampInt(modeResults.Total.wins)
	local losses = clampInt(modeResults.Total.losses)
	local totalResults = wins + losses
	local winRatio = totalResults > 0 and math.floor(((wins / totalResults) * 100) + 0.5) or 0
	local sanitizedStarProgress = sanitizeStarProgress(data.starProgress)

	data.progression.lastClassicLevel = lastClassicLevel
	data.progression.highestClassicLevel = highestClassicLevel
	data.starProgress = sanitizedStarProgress
	pruneBoardStateForProgression(data)

	removeChildrenByName(dataFolder, { "Currency", "Coins" })
	setIntValue(hintsFolder, "Available", (data.resources and data.resources.hintsAvailable) or 0)
	setIntValue(hintsFolder, "TotalUsed", data.stats.hintsUsed)
	setIntValue(powerupsFolder, "TimeBoostsAvailable", (data.resources and data.resources.timeBoostsAvailable) or 0)
	setIntValue(powerupsFolder, "FreezeTimeAvailable", (data.resources and data.resources.freezeTimeAvailable) or 0)
	setIntValue(dataFolder, "PuzzlePieces", (data.resources and data.resources.puzzlePieces) or 0)
	setBoolValue(settingsFolder, "SFX", data.settings and data.settings.SFX ~= false)
	setBoolValue(settingsFolder, "Music", data.settings and data.settings.Music ~= false)
	removeChildrenByName(settingsFolder, { "Numbers", "Colorblind" })
	setBoolValue(accountFolder, "GroupRewardClaimed", data.account and data.account.groupRewardClaimed == true)
	removeChildrenByName(accountFolder, { "NewPlayer", "TutorialCompleted" })
	setStringValue(progressFolder, "FastestSolve", fastestSolveSeconds)
	setIntValue(progressFolder, "TotalCompleted", data.stats.boardsCleared)
	setIntValue(progressFolder, "GiftClaimMilestone", (data.progression and data.progression.giftClaimMilestone) or 0)
	setIntValue(progressFolder, "DailySolves", (data.activity and data.activity.dailyBoardsCleared) or 0)
	setIntValue(progressFolder, "DailyWordsFound", (data.activity and data.activity.dailyWordsFound) or 0)
	do
		local winsFolder = getOrCreate(progressFolder, "Folder", "Wins")
		local lossesFolder = getOrCreate(progressFolder, "Folder", "Losses")
		local winRatioFolder = getOrCreate(progressFolder, "Folder", "WinRatio")
		local streaksFolder = getOrCreate(progressFolder, "Folder", "Streaks")

		for _, folder in ipairs({ winsFolder, lossesFolder, winRatioFolder }) do
			for _, child in ipairs(folder:GetChildren()) do
				if not MODE_RESULT_NAME_SET[child.Name] then
					child:Destroy()
				end
			end
		end
		for _, child in ipairs(streaksFolder:GetChildren()) do
			if table.find(MODE_STREAK_NAMES, child.Name) == nil then
				child:Destroy()
			end
		end

		for _, modeName in ipairs(MODE_RESULT_NAMES) do
			local bucket = modeResults[modeName] or { wins = 0, losses = 0 }
			setIntValue(winsFolder, modeName, bucket.wins)
			setIntValue(lossesFolder, modeName, bucket.losses)
			setStringValue(winRatioFolder, modeName, formatWinRatioText(bucket.wins, bucket.losses))
		end

		for _, modeName in ipairs(MODE_STREAK_NAMES) do
			local bucket = modeStreaks[modeName] or { current = 0, best = 0 }
			local streakFolder = getOrCreate(streaksFolder, "Folder", modeName)
			setIntValue(streakFolder, "Current", bucket.current)
			setIntValue(streakFolder, "Best", bucket.best)
		end
	end
	setIntValue(timedRewardsFolder, "Playtime", timedRewardsData.playtimeSeconds)
	for index = 1, TimedRewards.GetRewardCount() do
		local rewardName = TimedRewards.GetRewardValueName(index)
		setBoolValue(timedRewardsFolder, rewardName, timedRewardsData.rewardClaims[rewardName] == true)
	end
	setIntValue(progressionFolder, "LastClassicLevel", lastClassicLevel)
	setIntValue(progressionFolder, "HighestClassicLevel", highestClassicLevel)
	setIntValue(statsFolder, "TotalWordsFound", data.stats.totalWordsFound)
	setIntValue(statsFolder, "BoardsCleared", data.stats.boardsCleared)
	setIntValue(statsFolder, "Losses", losses)
	setIntValue(statsFolder, "HintsUsed", data.stats.hintsUsed)
	setIntValue(statsFolder, "TotalPlaySeconds", data.stats.totalPlaySeconds)
	setIntValue(statsFolder, "CurrentStreak", data.stats.currentStreak)
	setIntValue(statsFolder, "HighestStreak", data.stats.highestStreak)
	setIntValue(statsFolder, "LongestStreak", data.stats.longestStreak)
	setIntValue(activityFolder, "DailyBoardsCleared", (data.activity and data.activity.dailyBoardsCleared) or 0)
	setIntValue(activityFolder, "DailyWordsFound", (data.activity and data.activity.dailyWordsFound) or 0)
	setBoolValue(activityFolder, "DailyModeCompleted", dailyCompleted)
	setIntValue(activityFolder, "DailyModeResetSeconds", dailyIdentity.secondsUntilReset)
	refreshStarProgressFolder(starsFolder, sanitizedStarProgress)
	removeChildrenByName(activityFolder, {
		"DailyClassicBoards",
		"DailyBackwardsBoards",
		"DailyFreeplayBoards",
	})

	removeChildrenByName(progressFolder, { "BestTimedScore", "TotalTimedScore", "CurrentXP", "CurrentLevel" })
	removeChildrenByName(progressionFolder, { "PlayerLevel", "PlayerXp", "XpToNextLevel" })
	removeChildrenByName(statsFolder, {
		"ClassicBoards",
		"FreeplayBoards",
		"BackwardsBoards",
		"EndlessBoards",
		"TimedBoards",
		"TimedRuns",
		"TotalTimedScore",
		"BestTimedScore",
		"BestTimedScore5",
		"BestTimedScore6",
		"BestTimedScore7",
		"BestTimedScore8",
		"BestTimedScore9",
	})

	removeChildrenByName(leaderstatsFolder, { "Solves", "Level", "Stars" })
	setIntValue(leaderstatsFolder, "Wins", wins)
	setStringValue(leaderstatsFolder, "WinRatio", string.format("%d%%", winRatio))
end

function PlayerDataStore.LoadPlayer(player)
	local claimedData = nil
	local success, result = pcall(function()
		return DATA_STORE:UpdateAsync(getKey(player.UserId), function(rawValue)
			local data = prepareStoredData(decodeStoredValue(rawValue))
			pruneBoardStateForProgression(data)
			data.persistence.sessionToken = SESSION_TOKEN
			claimedData = data
			return encodeStoredValue(data)
		end)
	end)

	if not success then
		warn(string.format("[PlayerDataStore] Failed to load %s: %s", player.Name, tostring(result)))
	end

	local data = claimedData or prepareStoredData(decodeStoredValue(result))
	SessionStore.SetData(player.UserId, data)
	SessionStore.TouchSession(player.UserId)
	refreshPlayerDataFolder(player, data)
	return data
end

function PlayerDataStore.RecordModeOutcome(data, modeName, didWin)
	if type(data) ~= "table" then
		return
	end

	data.stats = type(data.stats) == "table" and data.stats or {}
	local modeResults = ensureModeResults(data.stats)
	local modeStreaks = ensureModeStreaks(data.stats)
	local modeKey = normalizeModeResultName(modeName)

	if didWin == true then
		modeResults.Total.wins += 1
		if modeKey then
			modeResults[modeKey].wins += 1
			modeStreaks[modeKey].current += 1
			modeStreaks[modeKey].best = math.max(modeStreaks[modeKey].best, modeStreaks[modeKey].current)
		end
		data.stats.boardsCleared = math.max(clampInt(data.stats.boardsCleared), modeResults.Total.wins)
	else
		modeResults.Total.losses += 1
		if modeKey then
			modeResults[modeKey].losses += 1
			modeStreaks[modeKey].current = 0
		end
		data.stats.losses = math.max(clampInt(data.stats.losses), modeResults.Total.losses)
	end

	local currentStreak = 0
	local highestStreak = math.max(clampInt(data.stats.highestStreak), clampInt(data.stats.longestStreak))
	for _, currentModeName in ipairs(MODE_STREAK_NAMES) do
		local bucket = modeStreaks[currentModeName]
		currentStreak = math.max(currentStreak, clampInt(bucket and bucket.current))
		highestStreak = math.max(highestStreak, clampInt(bucket and bucket.best))
	end

	data.stats.currentStreak = currentStreak
	data.stats.highestStreak = highestStreak
	data.stats.longestStreak = highestStreak
end

function PlayerDataStore.GetMutableData(player)
	local data = SessionStore.GetData(player.UserId)
	if data then
		return data
	end

	return PlayerDataStore.LoadPlayer(player)
end

function PlayerDataStore.GetSnapshot(player)
	local data = PlayerDataStore.GetMutableData(player)
	updatePlaytime(player, data)
	data.persistence.snapshotVersion = math.max(1, clampInt(data.persistence and data.persistence.snapshotVersion) + 1)
	refreshPlayerDataFolder(player, data)
	return buildSnapshot(data)
end

function PlayerDataStore.SavePlayer(player)
	local data = SessionStore.GetData(player.UserId)
	if not data then
		return false
	end

	updatePlaytime(player, data)
	refreshPlayerDataFolder(player, data)
	local savePayload = cloneTable(data)
	normalizeStoredData(savePayload)
	savePayload.persistence.sessionToken = SESSION_TOKEN

	local savedData = nil
	local success, result = pcall(function()
		return DATA_STORE:UpdateAsync(getKey(player.UserId), function(rawValue)
			local storedData = prepareStoredData(decodeStoredValue(rawValue))
			local storedSessionToken = tostring(storedData.persistence and storedData.persistence.sessionToken or "")
			if storedSessionToken ~= "" and storedSessionToken ~= SESSION_TOKEN then
				return nil
			end

			savePayload.persistence.saveRevision = math.max(
				clampInt(savePayload.persistence.saveRevision),
				clampInt(storedData.persistence and storedData.persistence.saveRevision or 0)
			) + 1
			savePayload.persistence.lastSavedAt = os.time()
			savePayload.persistence.sessionToken = SESSION_TOKEN
			savedData = savePayload
			return encodeStoredValue(savePayload)
		end)
	end)

	if not success then
		warn(string.format("[PlayerDataStore] Failed to save %s: %s", player.Name, tostring(result)))
		return false
	end
	if not savedData then
		warn(string.format("[PlayerDataStore] Skipped stale save for %s because a newer session owns the record.", player.Name))
		return false
	end

	SessionStore.SetData(player.UserId, savedData)
	return true
end

function PlayerDataStore.ReleasePlayer(player)
	PlayerDataStore.SavePlayer(player)
	SessionStore.ClearData(player.UserId)
end

PlayerDataStore.SanitizeBoardState = sanitizeBoardState

return PlayerDataStore
