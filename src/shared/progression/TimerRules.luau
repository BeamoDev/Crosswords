local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels"))

local TimerRules = {}

local BASE_TIME_LIMIT_MULTIPLIER = 2 -- If Timer was 2minutes and multi is 1.5 the total time is now  3minutes
local EXTRA_TIME_SECONDS = 120
local FREEZE_TIME_SECONDS = 30
local MAX_CLASSIC_LEVEL = math.max(1, #Levels)

local CLASSIC_LEVEL_TIME_STAGES = {
	{ minLevel = 1, maxLevel = 2, startTime = 50, endTime = 55 },
	{ minLevel = 3, maxLevel = 5, startTime = 60, endTime = 70 },
	{ minLevel = 6, maxLevel = 10, startTime = 75, endTime = 90 },
	{ minLevel = 11, maxLevel = 15, startTime = 95, endTime = 110 },
	{ minLevel = 16, maxLevel = 20, startTime = 105, endTime = 120 },
	{ minLevel = 21, maxLevel = 25, startTime = 115, endTime = 135 },
	{ minLevel = 26, maxLevel = 30, startTime = 125, endTime = 145 },
	{ minLevel = 31, maxLevel = 35, startTime = 140, endTime = 160 },
	{ minLevel = 36, maxLevel = 40, startTime = 150, endTime = 170 },
	{ minLevel = 41, maxLevel = 45, startTime = 160, endTime = 180 },
	{ minLevel = 46, maxLevel = 50, startTime = 170, endTime = 190 },
	{ minLevel = 51, maxLevel = 55, startTime = 180, endTime = 200 },
	{ minLevel = 56, maxLevel = 60, startTime = 190, endTime = 210 },
	{ minLevel = 61, maxLevel = 65, startTime = 200, endTime = 220 },
	{ minLevel = 66, maxLevel = 70, startTime = 210, endTime = 230 },
	{ minLevel = 71, maxLevel = 75, startTime = 220, endTime = 240 },
	{ minLevel = 76, maxLevel = 80, startTime = 225, endTime = 245 },
	{ minLevel = 81, maxLevel = 85, startTime = 230, endTime = 250 },
	{ minLevel = 86, maxLevel = 90, startTime = 235, endTime = 255 },
	{ minLevel = 91, maxLevel = 95, startTime = 240, endTime = 260 },
	{ minLevel = 96, maxLevel = 100, startTime = 245, endTime = 270 },
	{ minLevel = 101, maxLevel = 105, startTime = 275, endTime = 280 },
	{ minLevel = 106, maxLevel = 110, startTime = 280, endTime = 285 },
	{ minLevel = 111, maxLevel = 115, startTime = 285, endTime = 290 },
	{ minLevel = 116, maxLevel = 120, startTime = 290, endTime = 295 },
	{ minLevel = 121, maxLevel = 125, startTime = 295, endTime = 305 },
	{ minLevel = 126, maxLevel = 130, startTime = 305, endTime = 315 },
	{ minLevel = 131, maxLevel = 135, startTime = 315, endTime = 325 },
	{ minLevel = 136, maxLevel = 140, startTime = 325, endTime = 335 },
	{ minLevel = 141, maxLevel = 145, startTime = 335, endTime = 345 },
	{ minLevel = 146, maxLevel = 150, startTime = 345, endTime = 360 },
}

local MODE_TIME_FLOOR = {
	Classic = 50,
	Themed = 56,
	Freeplay = 58,
	Backwards = 68,
	Fog = 78,
	OneLife = 84,
	Mega = 160,
	Daily = 180,
	Duel = 90,
}

local MODE_TIME_CAP = {
	Classic = 360,
	Themed = 300,
	Freeplay = 285,
	Backwards = 300,
	Fog = 315,
	OneLife = 330,
	Mega = 450,
	Daily = 480,
	Duel = 180,
}

local MODE_TIME_BONUS = {
	Classic = 0,
	Themed = 10,
	Freeplay = 8,
	Backwards = 16,
	Fog = 24,
	OneLife = 30,
	Mega = 45,
	Daily = 60,
	Duel = 0,
}

local function normalizeWords(words)
	local totalLetters = 0
	local wordCount = 0

	for _, word in ipairs(words or {}) do
		if type(word) == "string" and word ~= "" then
			wordCount += 1
			totalLetters += #word
		end
	end

	return wordCount, totalLetters
end

local function interpolateInt(minValue, maxValue, current, rangeMin, rangeMax)
	if minValue == maxValue or rangeMax <= rangeMin then
		return minValue
	end

	local alpha = (current - rangeMin) / (rangeMax - rangeMin)
	return math.floor(minValue + ((maxValue - minValue) * alpha) + 0.5)
end

local function getClassicLevelTimeTarget(level)
	local safeLevel = math.clamp(math.max(1, math.floor(tonumber(level) or 1)), 1, MAX_CLASSIC_LEVEL)

	for _, stage in ipairs(CLASSIC_LEVEL_TIME_STAGES) do
		if safeLevel >= stage.minLevel and safeLevel <= stage.maxLevel then
			return interpolateInt(stage.startTime, stage.endTime, safeLevel, stage.minLevel, stage.maxLevel)
		end
	end

	local lastStage = CLASSIC_LEVEL_TIME_STAGES[#CLASSIC_LEVEL_TIME_STAGES]
	return lastStage and lastStage.endTime or 180
end

local function getComplexityTimeTarget(definition)
	local gridSize = math.max(5, math.floor(tonumber(definition and definition.gridSize) or 5))
	local wordCount, totalLetters = normalizeWords(definition and definition.words or nil)

	return 18
		+ (gridSize * 4)
		+ (wordCount * 7)
		+ math.floor(totalLetters * 0.35)
end

function TimerRules.GetBaseTimeLimit(definition, mode)
	local safeMode = tostring(mode or "Classic")
	local levelTimeTarget = getClassicLevelTimeTarget(definition and definition.level)
	local complexityTimeTarget = getComplexityTimeTarget(definition)
	local baseTimeTarget

	if safeMode == "Classic" then
		baseTimeTarget = math.floor((levelTimeTarget * 0.7) + (complexityTimeTarget * 0.3) + 0.5)
	else
		baseTimeTarget = math.max(levelTimeTarget, complexityTimeTarget) + (MODE_TIME_BONUS[safeMode] or MODE_TIME_BONUS.Classic)
	end

	local minTime = MODE_TIME_FLOOR[safeMode] or MODE_TIME_FLOOR.Classic
	local maxTime = MODE_TIME_CAP[safeMode] or MODE_TIME_CAP.Classic

	local baseTimeLimit = math.clamp(math.floor(baseTimeTarget + 0.5), minTime, maxTime)
	return math.floor((baseTimeLimit * BASE_TIME_LIMIT_MULTIPLIER) + 0.5)
end

function TimerRules.GetExtraTimeAmount(baseTime)
	baseTime = math.max(1, math.floor(tonumber(baseTime) or 1))
	return EXTRA_TIME_SECONDS
end

function TimerRules.GetFreezeDuration(baseTime)
	baseTime = math.max(1, math.floor(tonumber(baseTime) or 1))
	return FREEZE_TIME_SECONDS
end

function TimerRules.GetMaximumRemainingTime(definition, mode, timeBoostUsed)
	local baseTime = TimerRules.GetBaseTimeLimit(definition, mode)
	if timeBoostUsed then
		return baseTime + TimerRules.GetExtraTimeAmount(baseTime)
	end

	return baseTime
end

return TimerRules
