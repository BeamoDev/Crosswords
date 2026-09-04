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

return TimedRewards
