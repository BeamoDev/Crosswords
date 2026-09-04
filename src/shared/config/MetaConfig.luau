local MetaConfig = {}

MetaConfig.GROUP = {
	Id = 34241464,
	RewardHints = 2,
	RewardXp = 0,
}

MetaConfig.DEFAULTS = {
	StartingHints = 0,
	Settings = {
		SFX = true,
		Music = true,
	},
}

MetaConfig.HINT_PRODUCT_IDS = {
	[1] = 3573028208,
	[5] = 3573028342,
	[25] = 3573028459,
}

MetaConfig.TIMED_PRODUCT_IDS = {
	TimeBoost = 3573028604,
	FreezeTime = 3573028785,
}

MetaConfig.DAILY_REWARD = {
	BaseXp = 0,
	StepXp = 0,
	MaxXp = 0,
	HintEvery = 1,
	HintAmount = 1,
}

MetaConfig.GIFT = {
	HintReward = 1,
}

MetaConfig.LEADERBOARD = {
	SolvesStoreName = "WordSearchSolves_v1",
	RefreshInterval = 300,
	WriteInterval = 60,
}

return MetaConfig
