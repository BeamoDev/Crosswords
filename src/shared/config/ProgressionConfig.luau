local Daily = {}

local DAY_SECONDS = 24 * 60 * 60
local MIN_BASE_LEVEL = 5

function Daily.GetCurrentDayStamp(unixTimestamp)
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	return math.floor(resolvedTimestamp / DAY_SECONDS)
end

function Daily.GetNextResetTimestamp(unixTimestamp)
	local dayStamp = Daily.GetCurrentDayStamp(unixTimestamp)
	return (dayStamp + 1) * DAY_SECONDS
end

function Daily.GetSecondsUntilReset(unixTimestamp)
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	return math.max(0, Daily.GetNextResetTimestamp(resolvedTimestamp) - resolvedTimestamp)
end

function Daily.GetDailyIdentity(levelCount, unixTimestamp)
	local resolvedLevelCount = math.max(1, math.floor(tonumber(levelCount) or 1))
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	local dayStamp = Daily.GetCurrentDayStamp(resolvedTimestamp)
	local minimumLevel = math.min(MIN_BASE_LEVEL, resolvedLevelCount)
	local span = math.max(1, resolvedLevelCount - minimumLevel + 1)
	local level = minimumLevel + ((dayStamp * 17 + 11) % span)
	local seed = ((dayStamp * 104729 + 9187) % 2147483646) + 1

	return {
		dayStamp = dayStamp,
		level = level,
		seed = seed,
		resetTimestamp = Daily.GetNextResetTimestamp(resolvedTimestamp),
		secondsUntilReset = Daily.GetSecondsUntilReset(resolvedTimestamp),
	}
end


-- Gift milestone progression.
local Gift = {}

Gift.EarlyMilestones = { 3, 8, 20 }
Gift.RepeatingStart = 20
Gift.RepeatingInterval = 25

local function normalizeMilestoneValue(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getHighestKnownMilestoneAtOrBelow(value)
	local claimed = normalizeMilestoneValue(value)
	local highestMilestone = 0

	for _, milestone in ipairs(Gift.EarlyMilestones) do
		if claimed >= milestone then
			highestMilestone = milestone
		else
			break
		end
	end

	if claimed < Gift.RepeatingStart then
		return highestMilestone
	end

	local repeatedMilestone = Gift.RepeatingStart
		+ (math.floor((claimed - Gift.RepeatingStart) / Gift.RepeatingInterval) * Gift.RepeatingInterval)

	return math.max(highestMilestone, repeatedMilestone)
end

function Gift.NormalizeClaimMilestone(claimedMilestone)
	return getHighestKnownMilestoneAtOrBelow(claimedMilestone)
end

function Gift.GetLatestEarnedMilestone(totalCompleted)
	return getHighestKnownMilestoneAtOrBelow(totalCompleted)
end

function Gift.GetNextMilestone(lastClaimedMilestone)
	local claimed = Gift.NormalizeClaimMilestone(lastClaimedMilestone)

	for _, milestone in ipairs(Gift.EarlyMilestones) do
		if claimed < milestone then
			return milestone
		end
	end

	return math.max(Gift.RepeatingStart, claimed) + Gift.RepeatingInterval
end

function Gift.GetProgressState(totalCompleted, lastClaimedMilestone)
	local completed = normalizeMilestoneValue(totalCompleted)
	local claimedMilestone = Gift.NormalizeClaimMilestone(lastClaimedMilestone)
	local nextMilestone = Gift.GetNextMilestone(claimedMilestone)
	local previousMilestone = claimedMilestone

	local threshold = math.max(1, nextMilestone - previousMilestone)
	local progressWithinTier = math.clamp(completed - previousMilestone, 0, threshold)
	local ready = completed >= nextMilestone

	return {
		ready = ready,
		winsRemaining = ready and 0 or math.max(0, nextMilestone - completed),
		fillAlpha = ready and 1 or (progressWithinTier / threshold),
		nextMilestone = nextMilestone,
	}
end

function Gift.ResolveClaimMilestone(totalCompleted, lastClaimedMilestone)
	local progressState = Gift.GetProgressState(totalCompleted, lastClaimedMilestone)
	if progressState.ready ~= true then
		return nil
	end

	return progressState.nextMilestone
end


-- Hint-based star awards and durable slot resolution.
local Levels
if script then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = ReplicatedStorage:WaitForChild("shared")
	Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("PuzzleCatalog"))
else
	Levels = require("../content/PuzzleCatalog")
end

local Stars = {}

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)

local function clampClassicLevel(level)
	return math.clamp(math.max(1, math.floor(tonumber(level) or 1)), 1, MAX_CLASSIC_LEVEL)
end

local function getBoardInfo(mode, level)
	if mode == "Classic" or mode == "Daily" or mode == "Freeplay" or mode == "Backwards" or mode == "Fog" or mode == "OneLife" or mode == "Mega" then
		return Levels[clampClassicLevel(level)]
	end

	return Levels[clampClassicLevel(level)]
end

function Stars.GetModeBucket(mode)
	return tostring(mode or "Classic")
end

function Stars.GetPackName(mode, level)
	local safeMode = tostring(mode or "Classic")
	if safeMode == "Classic" then
		local boardInfo = getBoardInfo(safeMode, level)
		return tostring((boardInfo and (boardInfo.pack or boardInfo.tier)) or "Classic")
	end

	return safeMode
end

function Stars.GetEntryKey(mode, level, metadata)
	local safeMode = tostring(mode or "Classic")
	if safeMode == "Classic" then
		local boardInfo = getBoardInfo(safeMode, level)
		local packLevel = math.max(1, math.floor(tonumber(boardInfo and (boardInfo.packLevel or boardInfo.tierLevel) or level) or 1))
		return string.format("%02d", packLevel)
	end

	if safeMode == "Daily" then
		local dayStamp = math.max(0, math.floor(tonumber(metadata and metadata.dayStamp) or 0))
		if dayStamp > 0 then
			return tostring(dayStamp)
		end
	end

	return string.format("%03d", clampClassicLevel(level))
end

function Stars.ResolveSlot(mode, level, metadata)
	local safeMode = tostring(mode or "Classic")
	return {
		mode = Stars.GetModeBucket(safeMode),
		pack = Stars.GetPackName(safeMode, level),
		entry = Stars.GetEntryKey(safeMode, level, metadata),
	}
end

function Stars.CalculateAward(_mode, _level, hintsUsed, cleared)
	if cleared ~= true then
		return 0
	end

	local safeHintsUsed = math.max(0, math.floor(tonumber(hintsUsed) or 0))
	if safeHintsUsed == 0 then
		return 3
	elseif safeHintsUsed == 1 then
		return 2
	end

	return 1
end


-- Session playtime reward schedule.
local TimedRewards = {}

TimedRewards.Rewards = {
	{ rewardType = "hints", amount = 1, playtimeSeconds = 600 },
	{ rewardType = "pieces", amount = 10, playtimeSeconds = 1050 },
	{ rewardType = "hints", amount = 1, playtimeSeconds = 1350 },
	{ rewardType = "pieces", amount = 15, playtimeSeconds = 1650 },
	{ rewardType = "hints", amount = 2, playtimeSeconds = 1950 },
	{ rewardType = "pieces", amount = 20, playtimeSeconds = 2250 },
	{ rewardType = "hints", amount = 2, playtimeSeconds = 2700 },
}

function TimedRewards.GetReward(index)
	return TimedRewards.Rewards[index]
end

function TimedRewards.GetRewardValueName(index)
	return "Reward" .. tostring(index)
end

function TimedRewards.GetRewardCount()
	return #TimedRewards.Rewards
end

function TimedRewards.GetRewardDescription(reward)
	if not reward then
		return ""
	end

	local label = reward.rewardType == "hints" and "Hint" or "Puzzle Piece"
	if reward.amount ~= 1 then
		label = label .. "s"
	end

	return string.format("%d %s", reward.amount, label)
end


return {
	Daily = Daily,
	Gift = Gift,
	Stars = Stars,
	TimedRewards = TimedRewards,
}
