local DataService = {}

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent.Parent
local SessionStore = {}

local sessionData = {}
local sessionStartedAt = {}

function SessionStore.GetData(userId)
	return sessionData[userId]
end

function SessionStore.SetData(userId, data)
	sessionData[userId] = data
end

function SessionStore.ClearData(userId)
	sessionData[userId] = nil
	sessionStartedAt[userId] = nil
end

function SessionStore.GetSessionStartedAt(userId)
	return sessionStartedAt[userId]
end

function SessionStore.TouchSession(userId, timestamp)
	sessionStartedAt[userId] = timestamp or os.time()
end
local Utility = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("utility"):WaitForChild("Utility"))
local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("PuzzleCatalog"))
local ProgressionConfig = require(sharedFolder:WaitForChild("config"):WaitForChild("ProgressionConfig"))
local DailyMode = ProgressionConfig.Daily
local TimedRewards = ProgressionConfig.TimedRewards
local cloneTable = Utility.CloneDeep
local getOrCreate = Utility.GetOrCreate

local DATA_STORE = DataStoreService:GetDataStore("WordSearchData_v1")
local KEY_PREFIX = "player_"
local SESSION_TOKEN = HttpService:GenerateGUID(false)
local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local MAX_SAVED_BOARD_WORDS = 24
local autosaveStarted = false
local DataSchema = require(script.Parent:WaitForChild("DataSchema"))
local CURRENT_DATA_VERSION = DataSchema.Version
local VALID_BOARD_MODES = DataSchema.ValidBoardModes
local MODE_RESULT_NAMES = DataSchema.ModeResultNames
local MODE_STREAK_NAMES = DataSchema.ModeStreakNames
local deepMergeDefaults = DataSchema.MergeDefaults
local clampInt = DataSchema.ClampInt
local formatWinRatioText = DataSchema.FormatWinRatioText
local createDefaultModeResults = DataSchema.CreateModeResults
local createDefaultModeStreaks = DataSchema.CreateModeStreaks
local createDefaultTimedRewards = DataSchema.CreateTimedRewards
local normalizeModeResultName = DataSchema.NormalizeModeResultName
local ensureModeResults = DataSchema.EnsureModeResults
local ensureModeStreaks = DataSchema.EnsureModeStreaks
local normalizeStoredData = DataSchema.Normalize
local defaultData = DataSchema.CreateDefault

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
	local storedVersion = type(decoded) == "table" and clampInt(decoded.version) or 0
	local data = deepMergeDefaults(decoded or {}, defaultData())
	data.version = storedVersion
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
	local sessionScore = math.max(0, math.floor(tonumber(boardState.sessionScore) or 0))
	local puzzlesCleared = math.max(0, math.floor(tonumber(boardState.puzzlesCleared) or 0))
	local streak = math.max(0, math.floor(tonumber(boardState.streak) or 0))
	local hintUses = math.max(0, math.floor(tonumber(boardState.hintUses) or 0))
	local startedAtServerTime = tonumber(boardState.startedAtServerTime)
	local foundWords = sanitizeWordArray(boardState.foundWords)
	local hintedWords = sanitizeWordArray(boardState.hintedWords)

	if startedAtServerTime then
		startedAtServerTime = math.max(0, startedAtServerTime)
	end

	return {
		mode = mode,
		level = level,
		seed = seed,
		foundWords = foundWords,
		hintedWords = hintedWords,
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

	removeChildrenByName(dataFolder, { "Currency", "Coins", "Powerups" })
	setIntValue(hintsFolder, "Available", (data.resources and data.resources.hintsAvailable) or 0)
	setIntValue(hintsFolder, "TotalUsed", data.stats.hintsUsed)
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
				if table.find(MODE_RESULT_NAMES, child.Name) == nil then
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

function DataService.LoadPlayer(player)
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
		warn(string.format("[DataService] Failed to load %s: %s", player.Name, tostring(result)))
	end

	local data = claimedData or prepareStoredData(decodeStoredValue(result))
	SessionStore.SetData(player.UserId, data)
	SessionStore.TouchSession(player.UserId)
	refreshPlayerDataFolder(player, data)
	return data
end

function DataService.RecordModeOutcome(data, modeName, didWin)
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

function DataService.GetMutableData(player)
	local data = SessionStore.GetData(player.UserId)
	if data then
		return data
	end

	return DataService.LoadPlayer(player)
end

function DataService.GetSnapshot(player)
	local data = DataService.GetMutableData(player)
	updatePlaytime(player, data)
	data.persistence.snapshotVersion = math.max(1, clampInt(data.persistence and data.persistence.snapshotVersion) + 1)
	refreshPlayerDataFolder(player, data)
	return buildSnapshot(data)
end

function DataService.SavePlayer(player)
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
		warn(string.format("[DataService] Failed to save %s: %s", player.Name, tostring(result)))
		return false
	end
	if not savedData then
		warn(string.format("[DataService] Skipped stale save for %s because a newer session owns the record.", player.Name))
		return false
	end

	SessionStore.SetData(player.UserId, savedData)
	return true
end

function DataService.ReleasePlayer(player)
	DataService.SavePlayer(player)
	SessionStore.ClearData(player.UserId)
end

function DataService.SaveAll()
	local allSaved = true
	for _, player in ipairs(Players:GetPlayers()) do
		if not DataService.SavePlayer(player) then
			allSaved = false
		end
	end
	return allSaved
end

function DataService.StartAutosave(intervalSeconds)
	if autosaveStarted then
		return
	end
	autosaveStarted = true
	local interval = math.max(30, math.floor(tonumber(intervalSeconds) or 60))
	task.spawn(function()
		while autosaveStarted do
			task.wait(interval)
			if autosaveStarted then
				DataService.SaveAll()
			end
		end
	end)
end

function DataService.StopAutosave()
	autosaveStarted = false
end

DataService.SanitizeBoardState = sanitizeBoardState

return DataService
