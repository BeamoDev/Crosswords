--[[
	DailyPuzzleService

	Pure, server-side UTC daily-puzzle helpers. This module never writes player data.

	Public API (dot calls):
		GetUtcDayStamp(timestamp?) -> number
		GetSecondsUntilReset(timestamp?) -> number
		GetIdentity(timestamp?) -> identity
		NormalizeState(state?) -> stateCopy
		IsCompletedToday(state?, timestamp?) -> boolean
		GetStreakAfterCompletion(state?, dayStamp?) -> stateCopy, wasNewCompletion
		ApplyCompletion(state, dayStamp?) -> state, wasNewCompletion
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local serverFolder = script.Parent.Parent.Parent
local contentFolder = assert(serverFolder:WaitForChild("content", 10), "Word Search server content folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))

local DailyPuzzleService = {}

local SECONDS_PER_DAY = 24 * 60 * 60
local MAX_COUNTER = 1_000_000_000
local cachedCatalog = nil

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

	warn("[DailyPuzzleService] LevelCatalog could not be loaded:", result)
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

	-- Also tolerate catalogs implemented with colon-style methods.
	ok, result = pcall(method, catalog, ...)
	if ok then
		return result
	end

	return nil
end

local function getEligibleLevels()
	local rotation = type(GameConfig.DailyRotation) == "table" and GameConfig.DailyRotation or nil
	local rotationIds = rotation and rotation.LevelIds or nil
	if type(rotationIds) == "table" and #rotationIds > 0 then
		local pinned = {}
		for _, levelId in ipairs(rotationIds) do
			local level = safeCatalogCall("GetLevel", tostring(levelId))
			if type(level) == "table" and level.dailyEligible ~= false then
				table.insert(pinned, level)
			end
		end
		return pinned, true
	end

	local dailyLevels = safeCatalogCall("GetDailyLevels")
	local source = type(dailyLevels) == "table" and dailyLevels or safeCatalogCall("GetLevels")
	if type(source) ~= "table" then
		local publicCatalog = safeCatalogCall("GetPublicCatalog")
		source = type(publicCatalog) == "table" and publicCatalog.levels or nil
	end
	local eligible = {}
	local sourceResolved = type(source) == "table"

	if type(source) == "table" then
		for _, level in ipairs(source) do
			if type(level) == "table" and level.dailyEligible ~= false then
				table.insert(eligible, level)
			end
		end
	end

	return eligible, sourceResolved
end

local function resolveCatalogCount(levels, sourceResolved)
	if #levels > 0 then
		return #levels
	end
	if sourceResolved then
		return 0
	end

	local catalog = getLevelCatalog()
	if not catalog then
		return 0
	end

	local countValue = catalog.Count
	if type(countValue) == "function" then
		countValue = safeCatalogCall("Count")
	end
	if tonumber(countValue) == nil then
		countValue = safeCatalogCall("GetLevelCount")
	end
	return clampInteger(countValue, 0, 100_000)
end

local function resolveLevelAt(index, eligibleLevels, allowCatalogFallback)
	if eligibleLevels[index] then
		return eligibleLevels[index]
	end
	if not allowCatalogFallback then
		return nil
	end

	local level = safeCatalogCall("GetLevelByIndex", index) or safeCatalogCall("GetLevel", index)
	return type(level) == "table" and level or nil
end

local function stableHash(text)
	-- Small deterministic hash kept within Random's safe positive integer range.
	local hash = 5381
	for index = 1, #text do
		hash = (hash * 33 + string.byte(text, index)) % 2_147_483_647
	end
	return math.max(1, hash)
end

function DailyPuzzleService.GetUtcDayStamp(timestamp)
	local resolvedTimestamp = finiteNumber(timestamp, os.time())
	return math.max(0, math.floor(resolvedTimestamp / SECONDS_PER_DAY))
end

function DailyPuzzleService.GetSecondsUntilReset(timestamp)
	local resolvedTimestamp = finiteNumber(timestamp, os.time())
	local dayStamp = DailyPuzzleService.GetUtcDayStamp(resolvedTimestamp)
	return math.max(0, math.floor(((dayStamp + 1) * SECONDS_PER_DAY) - resolvedTimestamp))
end

function DailyPuzzleService.GetIdentity(timestamp)
	local resolvedTimestamp = finiteNumber(timestamp, os.time())
	local dayStamp = DailyPuzzleService.GetUtcDayStamp(resolvedTimestamp)
	local eligibleLevels, eligibilityResolved = getEligibleLevels()
	local count = resolveCatalogCount(eligibleLevels, eligibilityResolved)
	local selectionIndex = count > 0 and ((dayStamp % count) + 1) or 1
	local level = resolveLevelAt(selectionIndex, eligibleLevels, not eligibilityResolved)
	local levelId = level and tostring(level.id or level.levelId or selectionIndex) or tostring(selectionIndex)
	local levelIndex = tonumber(level and (level.index or level.levelIndex or level.catalogIndex))
		or tonumber(safeCatalogCall("GetLevelIndex", levelId))
		or selectionIndex
	levelIndex = math.max(1, math.floor(levelIndex))
	local rotation = type(GameConfig.DailyRotation) == "table" and GameConfig.DailyRotation or {}
	local revision = tostring(rotation.Revision or GameConfig.ContentRevision or "1")
	local fullLevel = safeCatalogCall("GetLevel", levelId)
	local generatedSeed = stableHash(string.format("%s:%d:%s", revision, dayStamp, levelId))
	local seed = type(fullLevel) == "table" and fullLevel.kind == "Authored"
		and clampInteger(fullLevel.seed, 1, 2_147_483_647)
		or generatedSeed

	return {
		dayStamp = dayStamp,
		resetTimestamp = (dayStamp + 1) * SECONDS_PER_DAY,
		secondsUntilReset = DailyPuzzleService.GetSecondsUntilReset(resolvedTimestamp),
		levelIndex = levelIndex,
		levelId = levelId,
		level = level,
		seed = seed,
		contentRevision = revision,
		rotationRevision = revision,
	}
end

function DailyPuzzleService.GetPublicIdentity(timestamp)
	local identity = DailyPuzzleService.GetIdentity(timestamp)
	return {
		dayStamp = identity.dayStamp,
		resetTimestamp = identity.resetTimestamp,
		secondsUntilReset = identity.secondsUntilReset,
		levelIndex = identity.levelIndex,
		levelId = identity.levelId,
		rotationRevision = identity.rotationRevision,
	}
end

function DailyPuzzleService.NormalizeState(state)
	state = type(state) == "table" and state or {}
	return {
		lastCompletedDay = clampInteger(state.lastCompletedDay, -1, MAX_COUNTER),
		currentStreak = clampInteger(state.currentStreak, 0, MAX_COUNTER),
		bestStreak = clampInteger(state.bestStreak, 0, MAX_COUNTER),
		totalCompleted = clampInteger(state.totalCompleted, 0, MAX_COUNTER),
	}
end

function DailyPuzzleService.IsCompletedToday(state, timestamp)
	local normalized = DailyPuzzleService.NormalizeState(state)
	return normalized.lastCompletedDay == DailyPuzzleService.GetUtcDayStamp(timestamp)
end

function DailyPuzzleService.GetStreakAfterCompletion(state, dayStamp)
	local normalized = DailyPuzzleService.NormalizeState(state)
	local resolvedDayStamp = dayStamp == nil
		and DailyPuzzleService.GetUtcDayStamp()
		or clampInteger(dayStamp, 0, MAX_COUNTER)

	if normalized.lastCompletedDay >= resolvedDayStamp then
		return normalized, false
	end

	if normalized.lastCompletedDay == resolvedDayStamp - 1 then
		normalized.currentStreak = math.min(MAX_COUNTER, normalized.currentStreak + 1)
	else
		normalized.currentStreak = 1
	end

	normalized.lastCompletedDay = resolvedDayStamp
	normalized.bestStreak = math.max(normalized.bestStreak, normalized.currentStreak)
	normalized.totalCompleted = math.min(MAX_COUNTER, normalized.totalCompleted + 1)
	return normalized, true
end

function DailyPuzzleService.ApplyCompletion(state, dayStamp)
	if type(state) ~= "table" then
		return DailyPuzzleService.GetStreakAfterCompletion(nil, dayStamp)
	end

	local updated, wasNewCompletion = DailyPuzzleService.GetStreakAfterCompletion(state, dayStamp)
	for key in pairs(state) do
		state[key] = nil
	end
	for key, value in pairs(updated) do
		state[key] = value
	end
	return state, wasNewCompletion
end

return table.freeze(DailyPuzzleService)
