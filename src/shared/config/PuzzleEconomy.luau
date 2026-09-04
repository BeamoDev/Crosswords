local PuzzleEconomy = {}

PuzzleEconomy.HintPackPieceCosts = {
	[1] = 140,
	[5] = 440,
	[25] = 2000,
}

PuzzleEconomy.ModeMultipliers = {
	classic = 1.0,
	themed = 1.1,
	freeplay = 1.15,
	backwards = 1.2,
	fog = 1.3,
	onelife = 1.38,
	mega = 1.92,
	daily = 2.15,
	duel = 1.0,
}

PuzzleEconomy.CleanHintBonus = 2
PuzzleEconomy.CleanResetBonus = 1
PuzzleEconomy.HintPenalty = 3
PuzzleEconomy.HintPenaltyCap = 12
PuzzleEconomy.ResetPenalty = 2
PuzzleEconomy.ResetPenaltyCap = 8
PuzzleEconomy.BaseMinimumCompletionReward = 5
PuzzleEconomy.CompletionRewardMultiplier = 2
PuzzleEconomy.MinimumCompletionReward = PuzzleEconomy.BaseMinimumCompletionReward * PuzzleEconomy.CompletionRewardMultiplier

local function normalizeMode(mode)
	local raw = string.lower(tostring(mode or ""))
	raw = raw:gsub("%s+", "")
	raw = raw:gsub("_", "")
	return raw
end

function PuzzleEconomy.GetHintPackCost(amount)
	local resolvedAmount = math.max(0, math.floor(tonumber(amount) or 0))
	return PuzzleEconomy.HintPackPieceCosts[resolvedAmount]
end

function PuzzleEconomy.GetBasePiecesForGrid(gridSize)
	local resolvedGridSize = math.max(0, math.floor(tonumber(gridSize) or 0))
	if resolvedGridSize >= 5 then
		return math.clamp(resolvedGridSize, 5, 25)
	end

	return PuzzleEconomy.BaseMinimumCompletionReward
end

function PuzzleEconomy.ScaleCompletionReward(amount)
	local numericAmount = math.max(0, tonumber(amount) or 0)
	return math.max(
		PuzzleEconomy.MinimumCompletionReward,
		math.floor((numericAmount * PuzzleEconomy.CompletionRewardMultiplier) + 0.5)
	)
end

function PuzzleEconomy.CalculateCompletionBreakdown(ctx)
	ctx = ctx or {}

	local mode = normalizeMode(ctx.mode)
	local gridSize = math.max(0, math.floor(tonumber(ctx.gridSize) or 0))
	local timeSpent = math.max(0, tonumber(ctx.time) or 0)
	local hintsUsed = math.max(0, math.floor(tonumber(ctx.hints) or 0))
	local resetsUsed = math.max(0, math.floor(tonumber(ctx.resets) or 0))
	local basePieces = PuzzleEconomy.GetBasePiecesForGrid(gridSize)
	local modeMultiplier = PuzzleEconomy.ModeMultipliers[mode] or 1.0
	-- Solve duration is retained for diagnostics only. It never changes rewards.
	local speedBonus = 0
	local hintPenalty = math.min(hintsUsed * PuzzleEconomy.HintPenalty, PuzzleEconomy.HintPenaltyCap)
	local resetPenalty = math.min(resetsUsed * PuzzleEconomy.ResetPenalty, PuzzleEconomy.ResetPenaltyCap)
	local cleanHintBonus = hintsUsed <= 0 and PuzzleEconomy.CleanHintBonus or 0
	local cleanResetBonus = resetsUsed <= 0 and PuzzleEconomy.CleanResetBonus or 0

	local unscaledPieces = (basePieces * modeMultiplier)
		+ speedBonus
		- hintPenalty
		- resetPenalty
		+ cleanHintBonus
		+ cleanResetBonus
	local preMultiplierReward = math.max(PuzzleEconomy.BaseMinimumCompletionReward, math.floor(unscaledPieces + 0.5))
	local reward = PuzzleEconomy.ScaleCompletionReward(preMultiplierReward)

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
		completionMultiplier = PuzzleEconomy.CompletionRewardMultiplier,
		reward = reward,
	}
end

function PuzzleEconomy.CalculateCompletionPieces(ctx)
	return PuzzleEconomy.CalculateCompletionBreakdown(ctx).reward
end

return PuzzleEconomy
