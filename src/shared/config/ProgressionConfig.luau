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


local Experience = {
	PerLetter = 20,
	CompletionBonus = 120,
	BaseLevelXp = 1000,
	LevelXpIncrease = 200,
	LevelCount = 500,
	HintEvery = 2,
	ModeLevels = { Mini = 5, Jumbo = 10, Hardcore = 20 },
}

-- Shared backend dictionary, indexed by player level (not puzzle number).
-- Keep the formula fallback beyond the catalog to preserve existing progress.
Experience.Levels = {}
for level = 1, Experience.LevelCount do
	local completed = level - 1
	Experience.Levels[level] = table.freeze({
		level = level,
		totalXp = completed * Experience.BaseLevelXp + Experience.LevelXpIncrease * completed * (completed - 1) / 2,
		xpToNextLevel = Experience.BaseLevelXp + completed * Experience.LevelXpIncrease,
		rewardHints = level % Experience.HintEvery == 0 and 1 or 0,
		totalRewardHints = math.floor(level / Experience.HintEvery),
	})
end
table.freeze(Experience.Levels)

local function experienceInt(value)
	local number = tonumber(value) or 0
	if number ~= number or number == math.huge or number == -math.huge then return 0 end
	return math.max(0, math.floor(number))
end

function Experience.RequiredForLevel(level)
	local reached = math.max(1, experienceInt(level))
	local definition = Experience.Levels[reached]
	return definition and definition.xpToNextLevel or Experience.BaseLevelXp + (reached - 1) * Experience.LevelXpIncrease
end

function Experience.TotalForLevel(level)
	local reached = math.max(1, experienceInt(level))
	local definition = Experience.Levels[reached]
	if definition then return definition.totalXp end
	local completed = reached - 1
	return completed * Experience.BaseLevelXp + Experience.LevelXpIncrease * completed * (completed - 1) / 2
end

function Experience.Resolve(totalXp)
	local total = experienceInt(totalXp)
	local step = Experience.LevelXpIncrease
	local coefficient = 2 * Experience.BaseLevelXp - step
	local completed = math.floor((math.sqrt(coefficient * coefficient + 8 * step * total) - coefficient) / (2 * step))
	local level = math.max(1, completed + 1)
	-- Correct floating-point rounding at an exact cumulative threshold.
	if Experience.TotalForLevel(level) > total then level = math.max(1, level - 1)
	elseif Experience.TotalForLevel(level + 1) <= total then level += 1 end
	return level, total - Experience.TotalForLevel(level), Experience.RequiredForLevel(level)
end

function Experience.HintsForLevel(level)
	local reached = math.max(1, experienceInt(level))
	local definition = Experience.Levels[reached]
	if definition then return definition.rewardHints end
	if reached == 1 then return 0 end
	return reached % Experience.HintEvery == 0 and 1 or 0
end

function Experience.TotalHintRewards(level)
	local reached = math.max(1, experienceInt(level))
	local definition = Experience.Levels[reached]
	if definition then return definition.totalRewardHints end
	return math.floor(reached / Experience.HintEvery)
end

-- Session-only puzzle performance; unrelated to persistent XP and hint rewards.
local Score = { PerLetter = 100, HintMultiplier = 0.5, CompletionMaximum = 1000, PerLevel = 500 }
function Score.Word(word, hinted)
	return math.floor(#word * Score.PerLetter * (hinted and Score.HintMultiplier or 1))
end
function Score.Completion(duration, timeLimit)
	if type(duration) ~= "number" or duration ~= duration or type(timeLimit) ~= "number" or timeLimit <= 0 then return 0 end
	return math.floor(Score.CompletionMaximum * math.clamp(1 - duration / timeLimit, 0, 1))
end
function Score.Level(points)
	return 1 + math.floor(experienceInt(points) / Score.PerLevel)
end

return {
	Experience = Experience,
	Score = Score,
	Gift = Gift,
}
