local Meta = {}

Meta.GROUP = {
	Id = 34241464,
	RewardHints = 2,
	RewardXp = 0,
}

Meta.DEFAULTS = {
	StartingHints = 0,
	Settings = {
		SFX = true,
		Music = true,
		DuelInvites = true,
	},
}

Meta.HINT_PRODUCT_IDS = {
	[1] = 3573028208,
	[5] = 3573028342,
	[15] = 3573028459,
	[30] = 3711566945,
}

Meta.DAILY_REWARD = {
	BaseXp = 0,
	StepXp = 0,
	MaxXp = 0,
	HintEvery = 1,
	HintAmount = 1,
}

Meta.GIFT = {
	HintReward = 1,
}

Meta.LEADERBOARD = {
	WordsFoundStoreName = "WordHuntQueueWordsFound_v1",
	DuelWinsStoreName = "WordHuntQueueDuelWins_v1",
	RefreshInterval = 300,
	WriteInterval = 60,
}


local Economy = {}

Economy.HintPackPieceCosts = {
	[1] = 140,
	[5] = 440,
	[25] = 2000,
}

Economy.ModeMultipliers = {
	standard = 1.1,
	mini = 1.0,
	jumbo = 1.92,
	hardcore = 1.38,
	duel = 1.0,
	timed = 1.0,
}

Economy.CleanHintBonus = 2
Economy.CleanResetBonus = 1
Economy.HintPenalty = 3
Economy.HintPenaltyCap = 12
Economy.ResetPenalty = 2
Economy.ResetPenaltyCap = 8
Economy.BaseMinimumCompletionReward = 5
Economy.CompletionRewardMultiplier = 2
Economy.MinimumCompletionReward = Economy.BaseMinimumCompletionReward * Economy.CompletionRewardMultiplier

local function normalizeMode(mode)
	local raw = string.lower(tostring(mode or ""))
	raw = raw:gsub("%s+", "")
	raw = raw:gsub("_", "")
	return raw
end

function Economy.GetHintPackCost(amount)
	local resolvedAmount = math.max(0, math.floor(tonumber(amount) or 0))
	return Economy.HintPackPieceCosts[resolvedAmount]
end

function Economy.GetBasePiecesForGrid(gridSize)
	local resolvedGridSize = math.max(0, math.floor(tonumber(gridSize) or 0))
	if resolvedGridSize >= 5 then
		return math.clamp(resolvedGridSize, 5, 25)
	end

	return Economy.BaseMinimumCompletionReward
end

function Economy.ScaleCompletionReward(amount)
	local numericAmount = math.max(0, tonumber(amount) or 0)
	return math.max(
		Economy.MinimumCompletionReward,
		math.floor((numericAmount * Economy.CompletionRewardMultiplier) + 0.5)
	)
end

function Economy.CalculateCompletionBreakdown(ctx)
	ctx = ctx or {}

	local mode = normalizeMode(ctx.mode)
	local gridSize = math.max(0, math.floor(tonumber(ctx.gridSize) or 0))
	local timeSpent = math.max(0, tonumber(ctx.time) or 0)
	local hintsUsed = math.max(0, math.floor(tonumber(ctx.hints) or 0))
	local resetsUsed = math.max(0, math.floor(tonumber(ctx.resets) or 0))
	local basePieces = Economy.GetBasePiecesForGrid(gridSize)
	local modeMultiplier = Economy.ModeMultipliers[mode] or 1.0
	-- Solve duration is retained for diagnostics only. It never changes rewards.
	local speedBonus = 0
	local hintPenalty = math.min(hintsUsed * Economy.HintPenalty, Economy.HintPenaltyCap)
	local resetPenalty = math.min(resetsUsed * Economy.ResetPenalty, Economy.ResetPenaltyCap)
	local cleanHintBonus = hintsUsed <= 0 and Economy.CleanHintBonus or 0
	local cleanResetBonus = resetsUsed <= 0 and Economy.CleanResetBonus or 0

	local unscaledPieces = (basePieces * modeMultiplier)
		+ speedBonus
		- hintPenalty
		- resetPenalty
		+ cleanHintBonus
		+ cleanResetBonus
	local preMultiplierReward = math.max(Economy.BaseMinimumCompletionReward, math.floor(unscaledPieces + 0.5))
	local reward = Economy.ScaleCompletionReward(preMultiplierReward)

	return {
		mode = mode,
		gridSize = gridSize,
		timeSpent = timeSpent,
		hintsUsed = hintsUsed,
		resetsUsed = resetsUsed,
		basePieces = basePieces,
		modeMultiplier = modeMultiplier,
		speedBonus = speedBonus,
		hintPenalty = hintPenalty,
		resetPenalty = resetPenalty,
		cleanHintBonus = cleanHintBonus,
		cleanResetBonus = cleanResetBonus,
		preMultiplierReward = preMultiplierReward,
		completionMultiplier = Economy.CompletionRewardMultiplier,
		reward = reward,
	}
end

function Economy.CalculateCompletionPieces(ctx)
	return Economy.CalculateCompletionBreakdown(ctx).reward
end


return {
	Meta = Meta,
	Economy = Economy,
	Bots = { Enabled = true, ServerSize = 12, MinBots = 2 },
	Tutorial = {
		-- Everyone respects saved completion/Skip except this owner testing account.
		ReplayEveryJoin = false,
		ReplayUserId = 1790165114,
	},
}
