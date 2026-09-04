local GiftProgress = {}

GiftProgress.EarlyMilestones = { 3, 8, 20 }
GiftProgress.RepeatingStart = 20
GiftProgress.RepeatingInterval = 25

local function normalizeMilestoneValue(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getHighestKnownMilestoneAtOrBelow(value)
	local claimed = normalizeMilestoneValue(value)
	local highestMilestone = 0

	for _, milestone in ipairs(GiftProgress.EarlyMilestones) do
		if claimed >= milestone then
			highestMilestone = milestone
		else
			break
		end
	end

	if claimed < GiftProgress.RepeatingStart then
		return highestMilestone
	end

	local repeatedMilestone = GiftProgress.RepeatingStart
		+ (math.floor((claimed - GiftProgress.RepeatingStart) / GiftProgress.RepeatingInterval) * GiftProgress.RepeatingInterval)

	return math.max(highestMilestone, repeatedMilestone)
end

function GiftProgress.NormalizeClaimMilestone(claimedMilestone)
	return getHighestKnownMilestoneAtOrBelow(claimedMilestone)
end

function GiftProgress.GetLatestEarnedMilestone(totalCompleted)
	return getHighestKnownMilestoneAtOrBelow(totalCompleted)
end

function GiftProgress.GetNextMilestone(lastClaimedMilestone)
	local claimed = GiftProgress.NormalizeClaimMilestone(lastClaimedMilestone)

	for _, milestone in ipairs(GiftProgress.EarlyMilestones) do
		if claimed < milestone then
			return milestone
		end
	end

	return math.max(GiftProgress.RepeatingStart, claimed) + GiftProgress.RepeatingInterval
end

function GiftProgress.GetProgressState(totalCompleted, lastClaimedMilestone)
	local completed = normalizeMilestoneValue(totalCompleted)
	local claimedMilestone = GiftProgress.NormalizeClaimMilestone(lastClaimedMilestone)
	local nextMilestone = GiftProgress.GetNextMilestone(claimedMilestone)
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

function GiftProgress.ResolveClaimMilestone(totalCompleted, lastClaimedMilestone)
	local progressState = GiftProgress.GetProgressState(totalCompleted, lastClaimedMilestone)
	if progressState.ready ~= true then
		return nil
	end

	return progressState.nextMilestone
end

return GiftProgress
