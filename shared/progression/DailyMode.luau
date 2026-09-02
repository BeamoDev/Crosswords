local DailyMode = {}

local DAY_SECONDS = 24 * 60 * 60
local MIN_BASE_LEVEL = 5

function DailyMode.GetCurrentDayStamp(unixTimestamp)
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	return math.floor(resolvedTimestamp / DAY_SECONDS)
end

function DailyMode.GetNextResetTimestamp(unixTimestamp)
	local dayStamp = DailyMode.GetCurrentDayStamp(unixTimestamp)
	return (dayStamp + 1) * DAY_SECONDS
end

function DailyMode.GetSecondsUntilReset(unixTimestamp)
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	return math.max(0, DailyMode.GetNextResetTimestamp(resolvedTimestamp) - resolvedTimestamp)
end

function DailyMode.GetDailyIdentity(levelCount, unixTimestamp)
	local resolvedLevelCount = math.max(1, math.floor(tonumber(levelCount) or 1))
	local resolvedTimestamp = math.floor(tonumber(unixTimestamp) or os.time())
	local dayStamp = DailyMode.GetCurrentDayStamp(resolvedTimestamp)
	local minimumLevel = math.min(MIN_BASE_LEVEL, resolvedLevelCount)
	local span = math.max(1, resolvedLevelCount - minimumLevel + 1)
	local level = minimumLevel + ((dayStamp * 17 + 11) % span)
	local seed = ((dayStamp * 104729 + 9187) % 2147483646) + 1

	return {
		dayStamp = dayStamp,
		level = level,
		seed = seed,
		resetTimestamp = DailyMode.GetNextResetTimestamp(resolvedTimestamp),
		secondsUntilReset = DailyMode.GetSecondsUntilReset(resolvedTimestamp),
	}
end

return DailyMode
