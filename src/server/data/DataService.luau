--[[
	DataService

	Authoritative profile owner for the Word Search revamp. This service uses only
	WordSearchRevamp_v1/schema v1; it intentionally does not read or migrate legacy data.
	Studio sessions are memory-only so a local play test cannot overwrite remote data.

	Public API (dot calls):
		Init()
		LoadPlayer(player) -> success, snapshotOrError
		IsReady(player) -> boolean
		GetSnapshot(player) -> snapshot?
		GetMutableProfile(player) -> profile? -- server-only escape hatch; marks dirty
		UpdateSetting(player, name, value) -> success, snapshotOrError
		CompleteTutorial(player) -> success, snapshotOrError
		RecordWordFound(player) -> success, snapshotOrError
		SpendHint(player) -> success, snapshotOrMessage
		RetryRoundCompletion(player, completionId) -> found?, snapshotOrError?, receipt?
		ApplyRoundCompletion(player, result) -> success, snapshotOrError, newlyApplied, receipt?, disposition?
		ClaimDailyReward(player, coinReward, hintReward) -> success, snapshotOrError, newlyApplied
		ApplyShopPurchase(player, product, requestId) -> success, snapshotOrError, newlyApplied
		EquipCosmetic(player, kind, itemId) -> success, snapshotOrError
		SavePlayer(player, reason?) -> success, snapshotOrError
		ReleasePlayer(player) -> success, error?
		StartAutosave()
		Shutdown()

	ApplyRoundCompletion accepts a trusted server result containing completionId,
	mode, optional levelId, elapsedMs, stars, xp, hintReward, coinReward, mistakes, hintsUsed,
	wordsFound, and optional dailyDayStamp. The completion ID is durably recorded in
	the same UpdateAsync as its rewards before the call reports success.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local serverFolder = script.Parent.Parent
local contentFolder = assert(serverFolder:WaitForChild("content", 10), "Word Search server content folder is missing")
local servicesFolder = assert(serverFolder:WaitForChild("services", 10), "Word Search services folder is missing")
local metaFolder = assert(servicesFolder:WaitForChild("meta", 10), "Word Search meta services folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
local DailyPuzzleService = require(assert(metaFolder:WaitForChild("DailyPuzzleService", 10), "Word Search DailyPuzzleService is missing"))
local EconomyProfile = require(assert(script.Parent:WaitForChild("EconomyProfile", 10), "Word Search EconomyProfile is missing"))

local DataService = {}

local SCHEMA_VERSION = 1
local DATA_STORE_NAME = tostring(GameConfig.DataStoreName or "WordSearchRevamp_v1")
local KEY_PREFIX = "player_"
local DATA_STORE = DataStoreService:GetDataStore(DATA_STORE_NAME)
local IS_STUDIO = RunService:IsStudio()
local MAX_STAT = 1_000_000_000
local MAX_TIMESTAMP = 4_102_444_800 -- 2100-01-01 UTC; safely above current Unix time.
local MAX_LEVEL_ENTRIES = 10_000
local MAX_STRING_KEY_LENGTH = 128
local MAX_ELAPSED_MS = 7 * 24 * 60 * 60 * 1000
local MAX_COMPLETION_RECEIPTS = 512

local persistenceConfig = type(GameConfig.Persistence) == "table" and GameConfig.Persistence or {}
local progressionConfig = type(GameConfig.Progression) == "table" and GameConfig.Progression or {}
local AUTO_SAVE_SECONDS = math.max(30, math.floor(tonumber(persistenceConfig.AutoSaveSeconds) or 60))
local SESSION_LEASE_SECONDS = math.max(AUTO_SAVE_SECONDS * 2, math.floor(tonumber(persistenceConfig.SessionLeaseSeconds) or 180))
local MAX_ATTEMPTS = math.clamp(math.floor(tonumber(persistenceConfig.MaxAttempts) or 5), 1, 10)
local RETRY_BASE_SECONDS = math.clamp(tonumber(persistenceConfig.RetryBaseSeconds) or 1, 0.1, 8)
local SHUTDOWN_BUDGET_SECONDS = math.clamp(tonumber(persistenceConfig.ShutdownBudgetSeconds) or 25, 5, 28)
local MAX_OUTER_RELEASE_ATTEMPTS = 2
local RELEASE_RETRY_WINDOW_SECONDS = 60
local MAX_XP = math.max(1, math.floor(tonumber(progressionConfig.MaxXp) or 100_000_000))
local MAX_HINTS = math.max(1, math.floor(tonumber(progressionConfig.MaxHints) or 999))
local STARTING_HINTS = math.clamp(math.floor(tonumber(progressionConfig.StartingHints) or 0), 0, MAX_HINTS)
local MAX_COINS = math.max(1, math.floor(tonumber(progressionConfig.MaxCoins) or 100_000_000))
local STARTING_COINS = math.clamp(math.floor(tonumber(progressionConfig.StartingCoins) or 0), 0, MAX_COINS)
local ECONOMY_LIMITS = table.freeze({
	maxCoins = MAX_COINS,
	maxHints = MAX_HINTS,
	maxStat = MAX_STAT,
})

local VALID_SETTINGS = {
	music = "boolean",
	sfx = "boolean",
	musicVolume = "number",
	sfxVolume = "number",
	uiAnimations = "boolean",
	reducedMotion = "boolean",
	highContrast = "boolean",
	colorblindMode = "boolean",
}

local sessions = {}
local studioProfiles = {}
local connections = {}
local cachedCatalog = nil
local initialized = false
local autosaveStarted = false
local shuttingDown = false
local shutdownComplete = false

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

local function deepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy
	for key, child in pairs(value) do
		copy[deepCopy(key, seen)] = deepCopy(child, seen)
	end
	return copy
end

local function getUserId(player)
	local userId = player and finiteNumber(player.UserId, nil)
	if not userId or (not IS_STUDIO and userId <= 0) then
		return nil
	end
	return math.floor(userId)
end

local function getKey(userId)
	return KEY_PREFIX .. tostring(userId)
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

local function getLevels()
	local levels = safeCatalogCall("GetLevels")
	if type(levels) ~= "table" then
		local publicCatalog = safeCatalogCall("GetPublicCatalog")
		levels = type(publicCatalog) == "table" and publicCatalog.levels or nil
	end
	return type(levels) == "table" and levels or {}
end

local function getLevelCount()
	local catalog = getLevelCatalog()
	local countValue = catalog and catalog.Count or nil
	if type(countValue) == "function" then
		countValue = safeCatalogCall("Count")
	end
	if tonumber(countValue) == nil then
		countValue = safeCatalogCall("GetLevelCount")
	end
	local count = clampInteger(countValue, 0, MAX_LEVEL_ENTRIES)
	if count > 0 then
		return count
	end
	return math.min(MAX_LEVEL_ENTRIES, #getLevels())
end

local function resolveLevelAndIndex(levelId)
	if levelId == nil then
		return nil, nil
	end

	local level = safeCatalogCall("GetLevel", levelId)
	local levels = getLevels()
	local resolvedIndex = safeCatalogCall("GetLevelIndex", tostring(levelId))

	if type(level) ~= "table" then
		local numericId = tonumber(levelId)
		if numericId then
			resolvedIndex = clampInteger(numericId, 1, math.max(1, #levels))
			level = safeCatalogCall("GetLevelByIndex", resolvedIndex) or levels[resolvedIndex]
		end
	end

	if type(level) == "table" then
		resolvedIndex = tonumber(resolvedIndex) or tonumber(level.index or level.levelIndex or level.catalogIndex)
		if resolvedIndex ~= nil then
			resolvedIndex = math.max(1, math.floor(resolvedIndex))
		else
			local requestedId = tostring(level.id or level.levelId or levelId)
			for index, candidate in ipairs(levels) do
				if candidate == level or tostring(candidate.id or candidate.levelId or index) == requestedId then
					resolvedIndex = index
					break
				end
			end
		end
	end

	return type(level) == "table" and level or nil, resolvedIndex
end

local function createDefaultProfile(now)
	return {
		progression = {
			unlockedLevel = 1,
			xp = 0,
			tutorialCompleted = false,
			levelProgress = {},
		},
		inventory = {
			hints = STARTING_HINTS,
			coins = STARTING_COINS,
		},
		stats = {
			totalPuzzlesCompleted = 0,
			totalWordsFound = 0,
			totalHintsUsed = 0,
			totalMistakes = 0,
			perfectSolves = 0,
			totalPlaySeconds = 0,
			modeClears = {},
		},
		daily = {
			lastCompletedDay = -1,
			currentStreak = 0,
			bestStreak = 0,
			totalCompleted = 0,
		},
		settings = {
			music = true,
			sfx = true,
			musicVolume = 0.65,
			sfxVolume = 0.8,
			uiAnimations = true,
			reducedMotion = false,
			highContrast = false,
			colorblindMode = false,
		},
		rewards = {
			lastClaimDay = -1,
			totalClaims = 0,
		},
		achievements = {},
		cosmetics = {
			ownedThemes = {
				Default = true,
			},
			equippedTheme = "Default",
			ownedTrails = { Default = true },
			equippedTrail = "Default",
			ownedBackgrounds = { Default = true },
			equippedBackground = "Default",
			ownedUIStyles = { Default = true },
			equippedUIStyle = "Default",
		},
		idempotency = {
			roundCompletions = {},
			shopPurchases = {},
		},
		meta = {
			createdAt = now or os.time(),
		},
	}
end

local function sanitizeBoolean(value, fallback)
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

local function sanitizeLevelProgress(source)
	local result = {}
	local count = 0
	if type(source) ~= "table" then
		return result
	end

	for rawLevelId, rawEntry in pairs(source) do
		if count >= MAX_LEVEL_ENTRIES then
			break
		end

		local levelId = tostring(rawLevelId or "")
		if levelId ~= "" and #levelId <= MAX_STRING_KEY_LENGTH and type(rawEntry) == "table" then
			local bestTimeMs = clampInteger(rawEntry.bestTimeMs, 0, MAX_ELAPSED_MS)
			result[levelId] = {
				stars = clampInteger(rawEntry.stars, 0, 3),
				bestTimeMs = bestTimeMs > 0 and bestTimeMs or nil,
				clears = clampInteger(rawEntry.clears, 0, MAX_STAT),
			}
			count += 1
		end
	end
	return result
end

local function sanitizeStringMap(source, valueKind)
	local result = {}
	local count = 0
	if type(source) ~= "table" then
		return result
	end

	for rawKey, rawValue in pairs(source) do
		if count >= MAX_LEVEL_ENTRIES then
			break
		end
		local key = tostring(rawKey or "")
		if key ~= "" and #key <= MAX_STRING_KEY_LENGTH then
			if valueKind == "timestamp" then
				result[key] = clampInteger(rawValue, 0, MAX_TIMESTAMP)
			elseif valueKind == "boolean" and rawValue == true then
				result[key] = true
			end
			count += 1
		end
	end
	return result
end

local function sanitizeCompletionReceipt(rawValue)
	local rawReceipt = type(rawValue) == "table" and rawValue or nil
	local rawResult = rawReceipt and rawReceipt.result or nil
	local receipt = {
		at = clampInteger(rawReceipt and rawReceipt.at or rawValue, 0, MAX_TIMESTAMP),
	}
	if type(rawResult) == "table" then
			receipt.result = {
			mode = type(rawResult.mode) == "string" and string.sub(rawResult.mode, 1, 16) or "",
			levelId = rawResult.levelId ~= nil and string.sub(tostring(rawResult.levelId), 1, MAX_STRING_KEY_LENGTH) or nil,
			elapsedMs = clampInteger(rawResult.elapsedMs, 0, MAX_ELAPSED_MS),
			stars = clampInteger(rawResult.stars, 0, 3),
			xp = clampInteger(rawResult.xp, 0, math.min(MAX_XP, 1_000_000)),
			hintReward = clampInteger(rawResult.hintReward, 0, MAX_HINTS),
			coinReward = clampInteger(rawResult.coinReward, 0, MAX_COINS),
			mistakes = clampInteger(rawResult.mistakes, 0, 100_000),
			hintsUsed = clampInteger(rawResult.hintsUsed, 0, 100_000),
			wordsFound = clampInteger(rawResult.wordsFound, 0, math.max(1, tonumber(GameConfig.Gameplay and GameConfig.Gameplay.MaxWords) or 100)),
			dailyDayStamp = rawResult.dailyDayStamp ~= nil and clampInteger(rawResult.dailyDayStamp, 0, MAX_STAT) or nil,
			difficulty = type(rawResult.difficulty) == "string" and string.sub(rawResult.difficulty, 1, 16) or nil,
		}
	end
	return receipt
end

local function sanitizeCompletionMap(source, preserveId)
	local candidates = {}
	if type(source) ~= "table" then
		return {}
	end

	for rawKey, rawValue in pairs(source) do
		local key = tostring(rawKey or "")
		if key ~= "" and #key <= MAX_STRING_KEY_LENGTH and not string.find(key, "%c") then
			table.insert(candidates, {
				key = key,
				receipt = sanitizeCompletionReceipt(rawValue),
			})
		end
	end
	table.sort(candidates, function(left, right)
		if preserveId and (left.key == preserveId or right.key == preserveId) and left.key ~= right.key then
			return left.key == preserveId
		end
		if left.receipt.at ~= right.receipt.at then
			return left.receipt.at > right.receipt.at
		end
		return left.key < right.key
	end)

	local result = {}
	for index = 1, math.min(#candidates, MAX_COMPLETION_RECEIPTS) do
		local candidate = candidates[index]
		result[candidate.key] = candidate.receipt
	end
	return result
end

local function sanitizeShopPurchases(source, preserveId)
	local candidates = {}
	if type(source) == "table" then
		for rawKey, rawReceipt in pairs(source) do
			local key = tostring(rawKey or "")
			if key ~= "" and #key <= MAX_STRING_KEY_LENGTH and not string.find(key, "%c") then
				table.insert(candidates, {
					key = key,
					receipt = {
						at = clampInteger(type(rawReceipt) == "table" and rawReceipt.at or 0, 0, MAX_TIMESTAMP),
						productId = string.sub(tostring(type(rawReceipt) == "table" and rawReceipt.productId or ""), 1, MAX_STRING_KEY_LENGTH),
					},
				})
			end
		end
	end
	table.sort(candidates, function(left, right)
		if preserveId and (left.key == preserveId or right.key == preserveId) and left.key ~= right.key then
			return left.key == preserveId
		end
		return left.receipt.at > right.receipt.at
	end)
	local result = {}
	for index = 1, math.min(#candidates, 256) do
		result[candidates[index].key] = candidates[index].receipt
	end
	return result
end

local function normalizeProfile(rawProfile, levelCount)
	local raw = type(rawProfile) == "table" and rawProfile or {}
	local profile = createDefaultProfile(os.time())
	local progression = type(raw.progression) == "table" and raw.progression or {}
	local inventory = type(raw.inventory) == "table" and raw.inventory or {}
	local stats = type(raw.stats) == "table" and raw.stats or {}
	local settings = type(raw.settings) == "table" and raw.settings or {}
	local rewards = type(raw.rewards) == "table" and raw.rewards or {}
	local cosmetics = type(raw.cosmetics) == "table" and raw.cosmetics or {}
	local idempotency = type(raw.idempotency) == "table" and raw.idempotency or {}
	local maxUnlocked = levelCount and levelCount > 0 and levelCount or MAX_LEVEL_ENTRIES

	profile.progression.unlockedLevel = clampInteger(progression.unlockedLevel, 1, math.max(1, maxUnlocked))
	profile.progression.xp = clampInteger(progression.xp, 0, MAX_XP)
	profile.progression.tutorialCompleted = progression.tutorialCompleted == true
	profile.progression.levelProgress = sanitizeLevelProgress(progression.levelProgress)
	profile.inventory.hints = clampInteger(inventory.hints, 0, MAX_HINTS)
	profile.inventory.coins = clampInteger(inventory.coins, 0, MAX_COINS)

	profile.stats.totalPuzzlesCompleted = clampInteger(stats.totalPuzzlesCompleted, 0, MAX_STAT)
	profile.stats.totalWordsFound = clampInteger(stats.totalWordsFound, 0, MAX_STAT)
	profile.stats.totalHintsUsed = clampInteger(stats.totalHintsUsed, 0, MAX_STAT)
	profile.stats.totalMistakes = clampInteger(stats.totalMistakes, 0, MAX_STAT)
	profile.stats.perfectSolves = clampInteger(stats.perfectSolves, 0, MAX_STAT)
	profile.stats.totalPlaySeconds = clampInteger(stats.totalPlaySeconds, 0, MAX_STAT)
	local storedModeClears = type(stats.modeClears) == "table" and stats.modeClears or {}
	for modeName in pairs(GameConfig.Modes or {}) do
		profile.stats.modeClears[modeName] = clampInteger(storedModeClears[modeName], 0, MAX_STAT)
	end

	profile.daily = DailyPuzzleService.NormalizeState(raw.daily)
	profile.settings.music = sanitizeBoolean(settings.music, true)
	profile.settings.sfx = sanitizeBoolean(settings.sfx, true)
	profile.settings.musicVolume = math.clamp(finiteNumber(settings.musicVolume, 0.65), 0, 1)
	profile.settings.sfxVolume = math.clamp(finiteNumber(settings.sfxVolume, 0.8), 0, 1)
	profile.settings.uiAnimations = sanitizeBoolean(settings.uiAnimations, true)
	profile.settings.reducedMotion = sanitizeBoolean(settings.reducedMotion, false)
	profile.settings.highContrast = sanitizeBoolean(settings.highContrast, false)
	profile.settings.colorblindMode = sanitizeBoolean(settings.colorblindMode, false)
	profile.rewards.lastClaimDay = clampInteger(rewards.lastClaimDay, -1, MAX_STAT)
	profile.rewards.totalClaims = clampInteger(rewards.totalClaims, 0, MAX_STAT)
	profile.achievements = sanitizeStringMap(raw.achievements, "timestamp")

	profile.cosmetics.ownedThemes = sanitizeStringMap(cosmetics.ownedThemes, "boolean")
	profile.cosmetics.ownedThemes.Default = true
	local equippedTheme = tostring(cosmetics.equippedTheme or "Default")
	if #equippedTheme > MAX_STRING_KEY_LENGTH or profile.cosmetics.ownedThemes[equippedTheme] ~= true then
		equippedTheme = "Default"
	end
	profile.cosmetics.equippedTheme = equippedTheme
	for _, spec in ipairs({
		{ owned = "ownedTrails", equipped = "equippedTrail" },
		{ owned = "ownedBackgrounds", equipped = "equippedBackground" },
		{ owned = "ownedUIStyles", equipped = "equippedUIStyle" },
	}) do
		profile.cosmetics[spec.owned] = sanitizeStringMap(cosmetics[spec.owned], "boolean")
		profile.cosmetics[spec.owned].Default = true
		local equipped = tostring(cosmetics[spec.equipped] or "Default")
		if #equipped > MAX_STRING_KEY_LENGTH or profile.cosmetics[spec.owned][equipped] ~= true then
			equipped = "Default"
		end
		profile.cosmetics[spec.equipped] = equipped
	end

	profile.idempotency.roundCompletions = sanitizeCompletionMap(idempotency.roundCompletions)
	profile.idempotency.shopPurchases = sanitizeShopPurchases(idempotency.shopPurchases)
	profile.meta.createdAt = clampInteger(type(raw.meta) == "table" and raw.meta.createdAt or nil, 0, MAX_TIMESTAMP)
	if profile.meta.createdAt <= 0 then
		profile.meta.createdAt = os.time()
	end

	return profile
end

local function calculateTotalStars(profile)
	local total = 0
	for _, entry in pairs(profile.progression.levelProgress or {}) do
		total += clampInteger(type(entry) == "table" and entry.stars or 0, 0, 3)
	end
	return total
end

local function getRankData(xp)
	local resolver = GameConfig.GetRankFromXp
	if type(resolver) == "function" then
		local ok, rank, rankXp, xpToNextRank = pcall(resolver, xp)
		if ok then
			return math.max(1, math.floor(tonumber(rank) or 1)), math.max(0, math.floor(tonumber(rankXp) or 0)), math.max(1, math.floor(tonumber(xpToNextRank) or 100))
		end
	end
	return 1, math.max(0, math.floor(tonumber(xp) or 0)), 100
end

local function getPendingPlaySeconds(session)
	local accountedAt = finiteNumber(session.playtimeAccountedAt, os.clock())
	local observedAt = os.clock()
	if session.playtimeEndedAt ~= nil then
		observedAt = math.min(observedAt, finiteNumber(session.playtimeEndedAt, observedAt))
	end
	return math.max(0, math.floor(observedAt - accountedAt))
end

local function accruePlaytime(session)
	local elapsed = getPendingPlaySeconds(session)
	if elapsed <= 0 then
		return
	end
	session.profile.stats.totalPlaySeconds = math.min(
		MAX_STAT,
		session.profile.stats.totalPlaySeconds + elapsed
	)
	session.playtimeAccountedAt += elapsed
	session.dirty = true
	session.dirtyReasons.playtime = true
end

local function buildSnapshot(session)
	local profile = session.profile
	local rank, rankXp, xpToNextRank = getRankData(profile.progression.xp)
	local dailyIdentity = DailyPuzzleService.GetIdentity()
	local stats = deepCopy(profile.stats)
	stats.totalPlaySeconds = math.min(MAX_STAT, stats.totalPlaySeconds + getPendingPlaySeconds(session))

	return {
		schemaVersion = SCHEMA_VERSION,
		revision = session.revision or 0,
		progression = {
			unlockedLevel = profile.progression.unlockedLevel,
			xp = profile.progression.xp,
			rank = rank,
			rankXp = rankXp,
			xpToNextRank = xpToNextRank,
			tutorialCompleted = profile.progression.tutorialCompleted,
			totalStars = calculateTotalStars(profile),
			levelProgress = deepCopy(profile.progression.levelProgress),
		},
		inventory = deepCopy(profile.inventory),
		stats = stats,
		daily = {
			lastCompletedDay = profile.daily.lastCompletedDay,
			currentStreak = profile.daily.currentStreak,
			bestStreak = profile.daily.bestStreak,
			totalCompleted = profile.daily.totalCompleted,
			completedToday = profile.daily.lastCompletedDay == dailyIdentity.dayStamp,
			dayStamp = dailyIdentity.dayStamp,
			levelId = dailyIdentity.levelId,
			levelIndex = dailyIdentity.levelIndex,
			resetTimestamp = dailyIdentity.resetTimestamp,
			secondsUntilReset = dailyIdentity.secondsUntilReset,
		},
		settings = deepCopy(profile.settings),
		rewards = {
			lastClaimDay = profile.rewards.lastClaimDay,
			totalClaims = profile.rewards.totalClaims,
			claimedToday = profile.rewards.lastClaimDay == dailyIdentity.dayStamp,
			dayStamp = dailyIdentity.dayStamp,
			resetTimestamp = dailyIdentity.resetTimestamp,
		},
		achievements = deepCopy(profile.achievements),
		cosmetics = deepCopy(profile.cosmetics),
	}
end

local function ensureValue(parent, className, name)
	local current = parent:FindFirstChild(name)
	if current and not current:IsA(className) then
		current:Destroy()
		current = nil
	end
	if not current then
		current = Instance.new(className)
		current.Name = name
		current.Parent = parent
	end
	return current
end

local function syncMirrors(session)
	local player = session.player
	if not (player and player.Parent) then
		return
	end

	local profile = session.profile
	local rank = getRankData(profile.progression.xp)
	local totalStars = calculateTotalStars(profile)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and not leaderstats:IsA("Folder") then
		leaderstats:Destroy()
		leaderstats = nil
	end
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end
	ensureValue(leaderstats, "IntValue", "Rank").Value = rank
	ensureValue(leaderstats, "IntValue", "Stars").Value = totalStars

	local dataFolder = player:FindFirstChild("Data")
	if dataFolder and not dataFolder:IsA("Folder") then
		dataFolder:Destroy()
		dataFolder = nil
	end
	if not dataFolder then
		dataFolder = Instance.new("Folder")
		dataFolder.Name = "Data"
		dataFolder.Parent = player
	end
	ensureValue(dataFolder, "IntValue", "XP").Value = profile.progression.xp
	ensureValue(dataFolder, "IntValue", "UnlockedLevel").Value = profile.progression.unlockedLevel
	ensureValue(dataFolder, "IntValue", "HintsAvailable").Value = profile.inventory.hints
	ensureValue(dataFolder, "IntValue", "Coins").Value = profile.inventory.coins
	ensureValue(dataFolder, "IntValue", "TotalStars").Value = totalStars
	ensureValue(dataFolder, "BoolValue", "TutorialCompleted").Value = profile.progression.tutorialCompleted
end

local function protectedUpdateAsync(key, transform)
	local lastError = "unknown_error"
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return DATA_STORE:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result
		end

		lastError = tostring(result)
		if attempt < MAX_ATTEMPTS then
			local delaySeconds = math.min(8, RETRY_BASE_SECONDS * (2 ^ (attempt - 1)))
			task.wait(delaySeconds + (math.random() * 0.2))
		end
	end
	return false, lastError
end

local function acquireMutationLock(session, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while session.mutationLocked do
		if session.released or os.clock() >= deadline then
			return false
		end
		task.wait(0.03)
	end
	if session.released then
		return false
	end
	session.mutationLocked = true
	return true
end

local function abandonRelease(session, reason)
	warn(string.format(
		"[DataService] release abandoned for %d after %d outer attempt(s): %s; the remote lease will expire naturally",
		session.userId,
		session.releaseRetryCount or 0,
		tostring(reason or "release_budget_exhausted")
	))
	session.released = true
	session.releasing = false
	session.releaseRetryScheduled = false
	session.status = "released"
	if sessions[session.userId] == session then
		sessions[session.userId] = nil
	end
end

local function hasReleaseBudget(session)
	return (session.releaseRetryCount or 0) < MAX_OUTER_RELEASE_ATTEMPTS
		and os.clock() < finiteNumber(session.releaseDeadline, 0)
end

local function queueRequestedRelease(session)
	if session.released or session.releasing or session.releaseRetryScheduled or not session.releaseRequested then
		return
	end
	if not hasReleaseBudget(session) then
		abandonRelease(session, "release_retry_budget_exhausted")
		return
	end
	session.releaseRetryScheduled = true
	local callback = function()
		session.releaseRetryScheduled = false
		if sessions[session.userId] == session and session.releaseRequested and not session.released and not session.releasing then
			DataService.ReleasePlayer(session.player)
		end
	end
	local delaySeconds = math.max(0, finiteNumber(session.releaseRetryAt, 0) - os.clock())
	if delaySeconds > 0 then
		task.delay(delaySeconds, callback)
	else
		task.defer(callback)
	end
end

local function releaseMutationLock(session)
	session.mutationLocked = false
	queueRequestedRelease(session)
end

local function markDirty(session, reason)
	session.dirty = true
	if type(reason) == "string" and reason ~= "" then
		session.dirtyReasons[reason] = true
	end
end

local function getReadySession(player)
	local userId = getUserId(player)
	local session = userId and sessions[userId] or nil
	if session
		and session.status == "ready"
		and not session.released
		and not session.releasing
		and not session.releaseRequested
	then
		return session
	end
	return nil
end

local function invalidateSession(session, reason)
	session.status = "failed"
	session.error = tostring(reason or "profile_invalidated")
	local player = session.player
	if player and player.Parent == Players then
		task.defer(function()
			if player.Parent == Players then
				player:Kick("Your data session changed and was closed to protect your progress. Please rejoin.")
			end
		end)
	end
end

local function commitSessionLocked(session, reason, releaseLease)
	accruePlaytime(session)
	local levelCount = getLevelCount()
	local profilePayload = normalizeProfile(session.profile, levelCount)
	local preparedAt = os.time()

	if session.memoryOnly then
		studioProfiles[session.userId] = deepCopy(profilePayload)
		session.profile = profilePayload
		session.revision = (session.revision or 0) + 1
		session.dirty = false
		session.dirtyReasons = {}
		session.lastSaveAt = preparedAt
		return true
	end

	local committedEnvelope = nil
	local rejectionReason = nil
	local ok, result = protectedUpdateAsync(getKey(session.userId), function(storedValue)
		committedEnvelope = nil
		rejectionReason = nil
		local callbackNow = os.time()
		if type(storedValue) ~= "table" then
			rejectionReason = "missing_profile"
			return nil
		end
		if storedValue.schemaVersion ~= SCHEMA_VERSION or type(storedValue.profile) ~= "table" then
			rejectionReason = "schema_mismatch"
			return nil
		end

		local lease = type(storedValue.lease) == "table" and storedValue.lease or nil
		if not lease or tostring(lease.token or "") ~= session.token then
			rejectionReason = "lease_lost"
			return nil
		end

		local revision = clampInteger(storedValue.revision, 0, MAX_STAT) + 1
		local nextLease = nil
		if not releaseLease then
			nextLease = {
				token = session.token,
				jobId = game.JobId,
				expiresAt = callbackNow + SESSION_LEASE_SECONDS,
			}
		end
		committedEnvelope = {
			schemaVersion = SCHEMA_VERSION,
			revision = revision,
			updatedAt = callbackNow,
			profile = deepCopy(profilePayload),
			lease = nextLease,
		}
		return committedEnvelope
	end)

	if not ok then
		warn(string.format("[DataService] %s save failed for %d: %s", tostring(reason or "manual"), session.userId, tostring(result)))
		return false, "save_failed"
	end
	if not committedEnvelope then
		warn(string.format("[DataService] %s save rejected for %d: %s", tostring(reason or "manual"), session.userId, tostring(rejectionReason or "unknown")))
		if rejectionReason == "lease_lost" or rejectionReason == "schema_mismatch" or rejectionReason == "missing_profile" then
			invalidateSession(session, rejectionReason)
		end
		return false, rejectionReason or "save_rejected"
	end

	session.profile = profilePayload
	session.revision = committedEnvelope.revision
	session.dirty = false
	session.dirtyReasons = {}
	session.lastSaveAt = committedEnvelope.updatedAt
	return true
end

local function releaseUncertainLease(session)
	if session.memoryOnly then
		return true
	end
	local ok, result = protectedUpdateAsync(getKey(session.userId), function(storedValue)
		if type(storedValue) ~= "table" then
			return nil
		end
		local lease = type(storedValue.lease) == "table" and storedValue.lease or nil
		if not lease or tostring(lease.token or "") ~= session.token then
			return nil
		end
		local releasedEnvelope = deepCopy(storedValue)
		releasedEnvelope.lease = nil
		releasedEnvelope.updatedAt = os.time()
		return releasedEnvelope
	end)
	if not ok then
		warn(string.format("[DataService] uncertain lease cleanup failed for %d: %s", session.userId, tostring(result)))
		return false, "save_failed"
	end
	return true
end

local function mutateProfile(player, reason, mutator)
	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready."
	end
	if not acquireMutationLock(session) then
		return false, "Profile is busy."
	end

	local before = deepCopy(session.profile)
	local ok, mutationResult = pcall(mutator, session.profile, session)
	if not ok then
		session.profile = before
		releaseMutationLock(session)
		warn("[DataService] Profile mutation failed:", mutationResult)
		return false, "Profile update failed."
	end

	session.profile = normalizeProfile(session.profile, getLevelCount())
	markDirty(session, reason)
	syncMirrors(session)
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot, mutationResult
end

local function unlockAchievement(profile, achievementId)
	if type(achievementId) ~= "string" or achievementId == "" then
		return false
	end
	if type(GameConfig.Achievements) == "table" and GameConfig.Achievements[achievementId] == nil then
		return false
	end
	if profile.achievements[achievementId] ~= nil then
		return false
	end
	profile.achievements[achievementId] = os.time()
	local milestoneXp = clampInteger(progressionConfig.AchievementXp, 0, 100_000)
	profile.progression.xp = math.clamp(profile.progression.xp + milestoneXp, 0, MAX_XP)
	return true
end

function DataService.Init()
	if initialized then
		return
	end
	initialized = true

	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		task.spawn(DataService.LoadPlayer, player)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		DataService.ReleasePlayer(player)
	end))

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.LoadPlayer, player)
	end

	DataService.StartAutosave()
	game:BindToClose(function()
		DataService.Shutdown()
	end)
end

function DataService.LoadPlayer(player)
	local userId = getUserId(player)
	if not userId then
		return false, "Invalid player."
	end
	if shuttingDown then
		return false, "Server is shutting down."
	end

	local existing = sessions[userId]
	if existing and existing.status == "ready" and not existing.released and not existing.releaseRequested then
		return true, buildSnapshot(existing)
	end
	if existing and not existing.released and existing.releaseRequested then
		return false, "Profile is still releasing."
	end
	if existing and existing.status == "loading" then
		local deadline = os.clock() + 45
		while existing.status == "loading" and os.clock() < deadline do
			task.wait(0.05)
		end
		if existing.status == "ready" and not existing.released then
			return true, buildSnapshot(existing)
		end
		return false, existing.error or "Profile load timed out."
	end

	local session
	if existing
		and existing.status == "failed"
		and existing.error == "data_store_unavailable"
		and existing.player == player
		and not existing.released
		and not existing.releaseRequested
	then
		-- An UpdateAsync can commit and still lose its response. Reusing this token
		-- lets a bootstrap retry reclaim that same lease instead of blocking itself.
		session = existing
		session.status = "loading"
		session.error = nil
	else
		session = {
			userId = userId,
			player = player,
			token = HttpService:GenerateGUID(false),
			status = "loading",
			profile = nil,
			revision = 0,
			dirty = false,
			dirtyReasons = {},
			mutationLocked = false,
			memoryOnly = IS_STUDIO,
			released = false,
			releaseRequested = false,
			releaseRetryScheduled = false,
			releaseRetryCount = 0,
			releaseRetryAt = 0,
			releaseDeadline = nil,
			releasing = false,
			lastSaveAt = 0,
			playtimeAccountedAt = os.clock(),
			playtimeEndedAt = nil,
		}
		sessions[userId] = session
	end

	if IS_STUDIO then
		local memoryProfile = studioProfiles[userId] or createDefaultProfile(os.time())
		session.profile = normalizeProfile(deepCopy(memoryProfile), getLevelCount())
		session.status = "ready"
		session.dirty = true
		syncMirrors(session)
		local snapshot = buildSnapshot(session)
		if session.releaseRequested or shuttingDown or player.Parent ~= Players then
			task.spawn(DataService.ReleasePlayer, player)
		end
		return true, snapshot
	end

	local acquiredEnvelope = nil
	local rejectionReason = nil
	local levelCount = getLevelCount()
	local ok, result = protectedUpdateAsync(getKey(userId), function(storedValue)
		acquiredEnvelope = nil
		rejectionReason = nil
		local callbackNow = os.time()
		local envelope
		if storedValue == nil then
			envelope = {
				schemaVersion = SCHEMA_VERSION,
				revision = 0,
				updatedAt = callbackNow,
				profile = createDefaultProfile(callbackNow),
			}
		elseif type(storedValue) ~= "table" or storedValue.schemaVersion ~= SCHEMA_VERSION or type(storedValue.profile) ~= "table" then
			rejectionReason = "schema_mismatch"
			return nil
		else
			envelope = storedValue
		end

		local lease = type(envelope.lease) == "table" and envelope.lease or nil
		local leaseToken = lease and tostring(lease.token or "") or ""
		local leaseExpiresAt = lease and clampInteger(lease.expiresAt, 0, MAX_TIMESTAMP) or 0
		if leaseToken ~= "" and leaseToken ~= session.token and leaseExpiresAt > callbackNow then
			rejectionReason = "profile_in_use"
			return nil
		end

		acquiredEnvelope = {
			schemaVersion = SCHEMA_VERSION,
			revision = clampInteger(envelope.revision, 0, MAX_STAT),
			updatedAt = callbackNow,
			profile = normalizeProfile(envelope.profile, levelCount),
			lease = {
				token = session.token,
				jobId = game.JobId,
				expiresAt = callbackNow + SESSION_LEASE_SECONDS,
			},
		}
		return acquiredEnvelope
	end)

	if not ok or not acquiredEnvelope then
		local errorCode = not ok and "data_store_unavailable" or (rejectionReason or "load_rejected")
		session.status = "failed"
		session.error = errorCode
		warn(string.format("[DataService] Refusing disposable profile for %s (%d): %s", tostring(player.Name), userId, tostring(result or errorCode)))
		if session.releaseRequested or player.Parent ~= Players then
			task.spawn(DataService.ReleasePlayer, player)
		end
		-- Do not create or mutate a disposable default. Leave this session closed so
		-- the client's explicit error screen can retry GetBootstrap safely.
		return false, errorCode
	end

	session.profile = acquiredEnvelope.profile
	session.revision = acquiredEnvelope.revision
	session.status = "ready"
	session.lastSaveAt = acquiredEnvelope.updatedAt
	syncMirrors(session)
	local snapshot = buildSnapshot(session)
	if session.releaseRequested or shuttingDown or player.Parent ~= Players then
		task.spawn(DataService.ReleasePlayer, player)
	end
	return true, snapshot
end

function DataService.IsReady(player)
	return getReadySession(player) ~= nil
end

function DataService.GetSnapshot(player)
	local session = getReadySession(player)
	return session and buildSnapshot(session) or nil
end

function DataService.GetMutableProfile(player)
	local session = getReadySession(player)
	if not session then
		return nil
	end
	-- Nested writes cannot be observed automatically, so retrieving this escape hatch
	-- conservatively marks the profile dirty. Prefer the focused APIs above.
	markDirty(session, "mutable_profile")
	return session.profile
end

function DataService.UpdateSetting(player, settingName, value)
	local expectedType = type(settingName) == "string" and VALID_SETTINGS[settingName] or nil
	if not expectedType or type(value) ~= expectedType then
		return false, "Invalid setting."
	end
	if expectedType == "number" then
		value = math.floor(math.clamp(finiteNumber(value, 0), 0, 1) * 20 + 0.5) / 20
	end
	return mutateProfile(player, "setting", function(profile)
		profile.settings[settingName] = value
	end)
end

function DataService.CompleteTutorial(player)
	return mutateProfile(player, "tutorial", function(profile)
		profile.progression.tutorialCompleted = true
	end)
end

function DataService.RecordWordFound(player)
	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready."
	end
	if not acquireMutationLock(session) then
		return false, "Profile is busy."
	end

	session.profile.stats.totalWordsFound = math.min(MAX_STAT, session.profile.stats.totalWordsFound + 1)
	unlockAchievement(session.profile, "FirstFind")
	markDirty(session, "word_found")
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot
end

function DataService.SpendHint(player)
	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready."
	end
	if not acquireMutationLock(session) then
		return false, "Profile is busy."
	end

	if session.profile.inventory.hints <= 0 then
		releaseMutationLock(session)
		return false, "No hints available."
	end

	session.profile.inventory.hints -= 1
	session.profile.stats.totalHintsUsed = math.min(MAX_STAT, session.profile.stats.totalHintsUsed + 1)
	markDirty(session, "hint_spent")
	syncMirrors(session)
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot
end

function DataService.RetryRoundCompletion(player, completionId)
	if type(completionId) ~= "string"
		or completionId == ""
		or #completionId > MAX_STRING_KEY_LENGTH
		or string.find(completionId, "%c")
	then
		return false, "Invalid completion ID.", nil
	end

	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready.", nil
	end
	if not acquireMutationLock(session, 15) then
		return false, "Profile is busy.", nil
	end

	local receipt = session.profile.idempotency.roundCompletions[completionId]
	if receipt == nil then
		releaseMutationLock(session)
		return nil, nil, nil
	end
	if session.dirty then
		local committed, commitError = commitSessionLocked(session, "round_completion_retry", false)
		if not committed then
			releaseMutationLock(session)
			return false, commitError or "Round reward could not be saved.", nil
		end
		receipt = session.profile.idempotency.roundCompletions[completionId]
	end

	local snapshot = buildSnapshot(session)
	local receiptCopy = deepCopy(receipt)
	releaseMutationLock(session)
	return true, snapshot, receiptCopy
end

function DataService.ApplyRoundCompletion(player, result)
	if type(result) ~= "table" then
		return false, "Invalid round result.", false
	end

	local completionId = type(result.completionId) == "string" and result.completionId or ""
	if completionId == "" or #completionId > MAX_STRING_KEY_LENGTH or string.find(completionId, "%c") then
		return false, "Invalid completion ID.", false
	end
	local receiptFound, retrySnapshotOrError, priorReceipt = DataService.RetryRoundCompletion(player, completionId)
	if receiptFound == true then
		return true, retrySnapshotOrError, false, priorReceipt
	elseif receiptFound == false then
		return false, retrySnapshotOrError, false
	end
	local mode = type(result.mode) == "string" and result.mode or ""
	local modeConfig = type(GameConfig.Modes) == "table" and GameConfig.Modes[mode] or nil
	if type(modeConfig) ~= "table" then
		return false, "Invalid game mode.", false
	end

	local levelId = result.levelId ~= nil and tostring(result.levelId) or nil
	if levelId and (levelId == "" or #levelId > MAX_STRING_KEY_LENGTH) then
		return false, "Invalid level ID.", false
	end
	local _, levelIndex = resolveLevelAndIndex(levelId)
	if modeConfig.tracksLevelProgress == true and not levelIndex then
		return false, "Unknown level.", false
	end

	local normalizedResult = {
		completionId = completionId,
		mode = mode,
		levelId = levelId,
		levelIndex = levelIndex,
		elapsedMs = clampInteger(result.elapsedMs, 0, MAX_ELAPSED_MS),
		stars = clampInteger(result.stars, 0, 3),
		xp = clampInteger(result.xp, 0, math.min(MAX_XP, 1_000_000)),
		hintReward = clampInteger(result.hintReward, 0, MAX_HINTS),
		coinReward = clampInteger(result.coinReward, 0, MAX_COINS),
		mistakes = clampInteger(result.mistakes, 0, 100_000),
		hintsUsed = clampInteger(result.hintsUsed, 0, 100_000),
		wordsFound = clampInteger(result.wordsFound, 0, math.max(1, tonumber(GameConfig.Gameplay and GameConfig.Gameplay.MaxWords) or 100)),
		dailyDayStamp = result.dailyDayStamp ~= nil and clampInteger(result.dailyDayStamp, 0, MAX_STAT) or nil,
		difficulty = type(result.difficulty) == "string" and string.sub(result.difficulty, 1, 16) or nil,
	}

	if mode == "Daily" then
		local today = DailyPuzzleService.GetUtcDayStamp()
		normalizedResult.dailyDayStamp = normalizedResult.dailyDayStamp or today
		if normalizedResult.dailyDayStamp ~= today then
			return false, "Daily puzzle is no longer current.", false
		end
	end

	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready.", false
	end
	if not acquireMutationLock(session, 15) then
		return false, "Profile is busy.", false
	end

	if session.profile.idempotency.roundCompletions[completionId] ~= nil then
		if session.dirty then
			local committed, commitError = commitSessionLocked(session, "round_completion_retry", false)
			if not committed then
				releaseMutationLock(session)
				return false, commitError or "Round reward could not be saved.", false
			end
		end
		local snapshot = buildSnapshot(session)
		local receipt = deepCopy(session.profile.idempotency.roundCompletions[completionId])
		releaseMutationLock(session)
		return true, snapshot, false, receipt
	end
	if modeConfig.tracksLevelProgress == true and normalizedResult.levelIndex > session.profile.progression.unlockedLevel then
		releaseMutationLock(session)
		return false, "Level is locked.", false
	end
	if mode == "Daily" and session.profile.daily.lastCompletedDay >= normalizedResult.dailyDayStamp then
		local snapshot = buildSnapshot(session)
		releaseMutationLock(session)
		return true, snapshot, false
	end

	-- The in-memory gate in RewardService protects the current server. Rechecking
	-- durable receipt timestamps here carries the same limit across reconnects and
	-- server hops without adding another profile structure or another write.
	local rewardGuard = type(GameConfig.Gameplay) == "table" and GameConfig.Gameplay.RewardGuard or nil
	rewardGuard = type(rewardGuard) == "table" and rewardGuard or {}
	local rewardWindowSeconds = math.clamp(finiteNumber(rewardGuard.WindowSeconds, 60), 10, 3600)
	local maximumRankedCompletions = math.clamp(
		math.floor(finiteNumber(rewardGuard.MaxRankedCompletionsPerWindow, 6)),
		1,
		100
	)
	local rewardCutoff = os.time() - rewardWindowSeconds
	local recentRankedCompletions = 0
	for _, existingReceipt in pairs(session.profile.idempotency.roundCompletions) do
		if type(existingReceipt) == "table" and finiteNumber(existingReceipt.at, 0) > rewardCutoff then
			recentRankedCompletions += 1
		end
	end
	if recentRankedCompletions >= maximumRankedCompletions then
		local snapshot = buildSnapshot(session)
		releaseMutationLock(session)
		return true, snapshot, false, nil, "reward_velocity_limited"
	end

	local profile = session.profile
	profile.idempotency.roundCompletions[completionId] = {
		at = os.time(),
		result = deepCopy(normalizedResult),
	}
	profile.idempotency.roundCompletions = sanitizeCompletionMap(
		profile.idempotency.roundCompletions,
		completionId
	)
	profile.stats.totalPuzzlesCompleted = math.min(MAX_STAT, profile.stats.totalPuzzlesCompleted + 1)
	profile.stats.totalMistakes = math.min(MAX_STAT, profile.stats.totalMistakes + normalizedResult.mistakes)
	profile.stats.modeClears[mode] = math.min(MAX_STAT, (profile.stats.modeClears[mode] or 0) + 1)
	if normalizedResult.stars >= 3 and normalizedResult.hintsUsed <= 0 then
		profile.stats.perfectSolves = math.min(MAX_STAT, profile.stats.perfectSolves + 1)
	end
	profile.progression.xp = math.clamp(profile.progression.xp + normalizedResult.xp, 0, MAX_XP)
	profile.inventory.hints = math.clamp(profile.inventory.hints + normalizedResult.hintReward, 0, MAX_HINTS)
	profile.inventory.coins = math.clamp(profile.inventory.coins + normalizedResult.coinReward, 0, MAX_COINS)

	if modeConfig.tracksLevelProgress == true and levelId then
		local levelKey = tostring(levelId)
		local levelProgress = profile.progression.levelProgress[levelKey] or {
			stars = 0,
			bestTimeMs = nil,
			clears = 0,
		}
		levelProgress.stars = math.max(levelProgress.stars or 0, normalizedResult.stars)
		if normalizedResult.elapsedMs > 0 then
			local previousBest = tonumber(levelProgress.bestTimeMs)
			if not previousBest or previousBest <= 0 or normalizedResult.elapsedMs < previousBest then
				levelProgress.bestTimeMs = normalizedResult.elapsedMs
			end
		end
		levelProgress.clears = math.min(MAX_STAT, clampInteger(levelProgress.clears, 0, MAX_STAT) + 1)
		profile.progression.levelProgress[levelKey] = levelProgress

		local catalogCount = getLevelCount()
		local nextUnlocked = normalizedResult.levelIndex + 1
		if catalogCount > 0 then
			nextUnlocked = math.min(catalogCount, nextUnlocked)
		end
		profile.progression.unlockedLevel = math.max(profile.progression.unlockedLevel, nextUnlocked)
	end

	if mode == "Daily" then
		DailyPuzzleService.ApplyCompletion(profile.daily, normalizedResult.dailyDayStamp)
	end

	unlockAchievement(profile, "FirstClear")
	if normalizedResult.stars >= 3 and normalizedResult.hintsUsed <= 0 then
		unlockAchievement(profile, "PerfectSolve")
	end
	if profile.stats.totalPuzzlesCompleted >= 10 then
		unlockAchievement(profile, "TenClears")
	end
	if profile.daily.currentStreak >= 7 then
		unlockAchievement(profile, "DailySeven")
	end

	markDirty(session, "round_completion")
	local committed, commitError = commitSessionLocked(session, "round_completion", false)
	if not committed then
		-- Keep the in-memory receipt and mutation pending. UpdateAsync failures can be
		-- ambiguous (the backend may have committed before the response was lost), so
		-- rolling back and later saving the old profile could erase the receipt and
		-- make the same completion grantable twice. A retry writes the identical state.
		markDirty(session, "round_completion_retry")
		releaseMutationLock(session)
		return false, commitError or "Round reward could not be saved.", false
	end

	syncMirrors(session)
	local snapshot = buildSnapshot(session)
	local receipt = deepCopy(session.profile.idempotency.roundCompletions[completionId])
	releaseMutationLock(session)
	return true, snapshot, true, receipt
end

local function commitEconomyMutation(session, reason)
	local committed, commitError = commitSessionLocked(session, reason, false)
	if not committed then
		markDirty(session, reason .. "_retry")
		return false, commitError
	end
	syncMirrors(session)
	return true
end

function DataService.ClaimDailyReward(player, coinReward, hintReward)
	local today = DailyPuzzleService.GetUtcDayStamp()
	coinReward = clampInteger(coinReward, 0, MAX_COINS)
	hintReward = clampInteger(hintReward, 0, MAX_HINTS)
	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready.", false
	end
	if not acquireMutationLock(session, 15) then
		return false, "Profile is busy.", false
	end
	local applied = EconomyProfile.ApplyDailyReward(session.profile, today, coinReward, hintReward, ECONOMY_LIMITS)
	if not applied then
		if session.dirty then
			local committed, commitError = commitEconomyMutation(session, "daily_reward")
			if not committed then
				releaseMutationLock(session)
				return false, commitError or "Daily reward could not be saved.", false
			end
		end
		local snapshot = buildSnapshot(session)
		releaseMutationLock(session)
		return true, snapshot, false
	end
	markDirty(session, "daily_reward")
	local committed, commitError = commitEconomyMutation(session, "daily_reward")
	if not committed then
		releaseMutationLock(session)
		return false, commitError or "Daily reward could not be saved.", false
	end
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot, true
end

function DataService.ApplyShopPurchase(player, product, requestId)
	if type(product) ~= "table" or product.disabled == true or product.kind == "CoinPack" then
		return false, "This item is not available.", false
	end
	requestId = type(requestId) == "string" and requestId or ""
	local productId = type(product.id) == "string" and product.id or ""
	if requestId == "" or #requestId > MAX_STRING_KEY_LENGTH or string.find(requestId, "%c")
		or productId == "" or #productId > MAX_STRING_KEY_LENGTH
	then
		return false, "Invalid purchase request.", false
	end
	local price = clampInteger(product.coinPrice, 0, MAX_COINS)
	local kind = tostring(product.kind or "")
	local itemId = product.itemId ~= nil and tostring(product.itemId) or nil
	local cosmeticFields = EconomyProfile.GetCosmeticFields(kind)
	if kind ~= "Hints" and (not cosmeticFields or not itemId or itemId == "" or #itemId > MAX_STRING_KEY_LENGTH) then
		return false, "Invalid shop item.", false
	end

	local session = getReadySession(player)
	if not session then return false, "Profile is not ready.", false end
	if not acquireMutationLock(session, 15) then return false, "Profile is busy.", false end
	local outcome = EconomyProfile.ApplyPurchase(session.profile, {
		kind = kind,
		itemId = itemId,
		amount = clampInteger(product.amount, 1, MAX_HINTS),
		coinPrice = price,
		productId = productId,
	}, requestId, os.time(), ECONOMY_LIMITS)
	if outcome == "already_applied" or outcome == "already_owned" then
		if session.dirty then
			local committed, commitError = commitEconomyMutation(session, "shop_purchase")
			if not committed then
				releaseMutationLock(session)
				return false, commitError or "Purchase could not be saved.", false
			end
		end
		local snapshot = buildSnapshot(session)
		releaseMutationLock(session)
		return true, snapshot, false
	end
	if outcome == "insufficient_funds" then
		releaseMutationLock(session)
		return false, "Not enough coins.", false
	end
	if outcome ~= "applied" then
		releaseMutationLock(session)
		return false, "Invalid shop item.", false
	end
	session.profile.idempotency.shopPurchases = sanitizeShopPurchases(session.profile.idempotency.shopPurchases, requestId)
	markDirty(session, "shop_purchase")
	local committed, commitError = commitEconomyMutation(session, "shop_purchase")
	if not committed then
		releaseMutationLock(session)
		return false, commitError or "Purchase could not be saved.", false
	end
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot, true
end

function DataService.EquipCosmetic(player, kind, itemId)
	local fields = EconomyProfile.GetCosmeticFields(kind)
	if not fields or type(itemId) ~= "string" or itemId == "" or #itemId > MAX_STRING_KEY_LENGTH then
		return false, "Invalid cosmetic."
	end
	local session = getReadySession(player)
	if not session then return false, "Profile is not ready." end
	if not acquireMutationLock(session) then return false, "Profile is busy." end
	local equipped, equipError = EconomyProfile.EquipCosmetic(session.profile, kind, itemId)
	if not equipped then
		releaseMutationLock(session)
		return false, equipError
	end
	markDirty(session, "cosmetic_equipped")
	syncMirrors(session)
	local snapshot = buildSnapshot(session)
	releaseMutationLock(session)
	return true, snapshot
end

function DataService.SavePlayer(player, reason)
	local session = getReadySession(player)
	if not session then
		return false, "Profile is not ready."
	end
	if session.releasing or session.releaseRequested then
		return false, "Profile is releasing."
	end
	if not acquireMutationLock(session, 15) then
		return false, "Profile is busy."
	end

	local success, saveError = commitSessionLocked(session, reason or "manual", false)
	if success then
		syncMirrors(session)
	end
	local response = success and buildSnapshot(session) or saveError
	releaseMutationLock(session)
	return success, response
end

function DataService.ReleasePlayer(player)
	local userId = getUserId(player)
	local session = userId and sessions[userId] or nil
	if not session or session.released then
		return true
	end
	local releaseRequestedAt = os.clock()
	session.releaseRequested = true
	session.playtimeEndedAt = session.playtimeEndedAt or releaseRequestedAt
	if session.status == "loading" then
		-- Never turn an unfinished load into a save of defaults. The loading coroutine
		-- will release its acquired lease as soon as it has the real profile.
		return true
	end
	session.releaseDeadline = session.releaseDeadline or (releaseRequestedAt + RELEASE_RETRY_WINDOW_SECONDS)
	if session.status == "failed" and session.error == "data_store_unavailable" then
		if not hasReleaseBudget(session) then
			abandonRelease(session, "uncertain_lease_cleanup_budget_exhausted")
			return false, "release_retry_exhausted"
		end
		session.releaseRetryCount += 1
		session.releasing = true
		local cleaned, cleanupError = releaseUncertainLease(session)
		session.releasing = false
		if not cleaned then
			session.releaseRetryAt = os.clock() + math.min(8, 0.5 * (2 ^ (session.releaseRetryCount - 1)))
			queueRequestedRelease(session)
			return false, cleanupError
		end
		session.released = true
		session.status = "released"
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		return true
	end
	if session.status ~= "ready" then
		session.released = true
		if sessions[userId] == session then
			sessions[userId] = nil
		end
		return true
	end
	if not hasReleaseBudget(session) then
		abandonRelease(session, "profile_release_budget_exhausted")
		return false, "release_retry_exhausted"
	end
	if session.releasing then
		local deadline = os.clock() + 15
		while session.releasing and not session.released and os.clock() < deadline do
			task.wait(0.05)
		end
		if session.released then
			return true, nil
		end
		return false, "release_timeout"
	end

	if not acquireMutationLock(session, 15) then
		session.releaseRetryAt = os.clock() + 0.25
		queueRequestedRelease(session)
		return false, "profile_busy"
	end
	session.releasing = true
	session.releaseRetryCount += 1
	local success, releaseError = commitSessionLocked(session, "release", true)
	if not success and releaseError == "save_failed" then
		session.releasing = false
		session.releaseRetryAt = os.clock() + math.min(8, 0.5 * (2 ^ (session.releaseRetryCount - 1)))
		releaseMutationLock(session)
		return false, releaseError
	end
	session.released = true
	session.status = "released"
	session.releasing = false
	releaseMutationLock(session)
	if sessions[userId] == session then
		sessions[userId] = nil
	end
	return success, releaseError
end

function DataService.StartAutosave()
	if autosaveStarted then
		return
	end
	autosaveStarted = true

	task.spawn(function()
		while not shuttingDown do
			task.wait(AUTO_SAVE_SECONDS)
			if shuttingDown then
				break
			end
			for _, session in pairs(sessions) do
				if session.status == "ready" and not session.releasing and not session.released and not session.releaseRequested then
					task.spawn(DataService.SavePlayer, session.player, session.dirty and "autosave_dirty" or "lease_heartbeat")
				end
			end
		end
	end)
end

function DataService.Shutdown()
	if shutdownComplete then
		return
	end
	if shuttingDown then
		local deadline = os.clock() + SHUTDOWN_BUDGET_SECONDS
		while not shutdownComplete and os.clock() < deadline do
			task.wait(0.05)
		end
		return
	end
	shuttingDown = true

	local pending = 0
	local deadline = os.clock() + SHUTDOWN_BUDGET_SECONDS
	for _, session in pairs(sessions) do
		local uncertainLease = session.status == "failed" and session.error == "data_store_unavailable"
		if not session.released and (session.status == "ready" or session.status == "loading" or uncertainLease) then
			pending += 1
			task.spawn(function()
				if session.status == "loading" then
					-- Route shutdown through the same entrypoint so the first release
					-- request also freezes this session's playtime clock.
					DataService.ReleasePlayer(session.player)
					while session.status == "loading" and os.clock() < deadline do
						task.wait(0.05)
					end
				end
				if session.status == "ready" or (session.status == "failed" and session.error == "data_store_unavailable") then
					DataService.ReleasePlayer(session.player)
					while not session.released and os.clock() < deadline do
						task.wait(0.05)
					end
				end
				pending -= 1
			end)
		end
	end

	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	shutdownComplete = true
end

return DataService
