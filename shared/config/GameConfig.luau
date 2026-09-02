local GameConfig = {}

-- Changing either revision deliberately invalidates an in-flight round. This keeps
-- saved progression stable when puzzle content or generation rules are updated.
GameConfig.SchemaVersion = 1
GameConfig.ContentRevision = "2026.09.02-r2"
GameConfig.GeneratorVersion = 2
GameConfig.DataStoreName = "WordSearchRevamp_v1"

-- This manifest is deliberately independent from ContentRevision. Change its
-- revision/list only immediately after a UTC rollover so mixed live servers keep
-- offering the same daily identity for the remainder of that day.
GameConfig.DailyRotation = {
	Revision = "2026.09-r1",
	LevelIds = {
		"animals-friendly-pets", "animals-pond-and-farm", "animals-wild-trails", "animals-great-migration",
		"food-market-basket", "food-cafe-corner", "food-snack-festival", "food-master-kitchen",
		"nature-garden-walk", "nature-river-valley", "nature-wild-horizon", "nature-force-of-nature",
		"roblox-first-spawn", "roblox-creator-studio", "roblox-checkpoint-rush", "roblox-engine-room",
		"space-night-sky", "space-launch-day", "space-orbital-station", "space-deep-universe",
		"expert-word-architect", "expert-science-vault", "expert-language-lab", "expert-grand-finale",
	},
}

GameConfig.Persistence = {
	AutoSaveSeconds = 60,
	SessionLeaseSeconds = 180,
	MaxAttempts = 5,
	RetryBaseSeconds = 1,
	ShutdownBudgetSeconds = 25,
}

GameConfig.Gameplay = {
	MaxGridWidth = 20,
	MaxGridHeight = 20,
	MaxWords = 20,
	MaxWordLength = 20,
	MaxSelectionRate = 12,
	HintCooldownSeconds = 0.45,
	PauseCooldownSeconds = 0.35,
	RoundStartCooldownSeconds = 0.75,
	QuickPlayRecentLevelWindow = 4,
	RewardGuard = {
		MinSolveBaseSeconds = 1.5,
		MinSecondsPerWord = 0.3,
		WindowSeconds = 60,
		MaxRankedCompletionsPerWindow = 6,
	},
}

GameConfig.Progression = {
	StartingHints = 3,
	XpByDifficulty = {
		Easy = 45,
		Medium = 65,
		Hard = 90,
		Expert = 125,
	},
	StarXpBonus = 15,
	DailyXpBonus = 40,
	DailyHintReward = 1,
	AchievementXp = 50,
	MaxXp = 100000000,
	MaxHints = 999,
}

GameConfig.Modes = {
	Classic = {
		label = "Classic Levels",
		description = "Curated puzzles with stars and permanent progress.",
		tracksLevelProgress = true,
	},
	Quick = {
		label = "Quick Play",
		description = "Jump straight into a puzzle suited to your progress.",
		tracksLevelProgress = false,
	},
	Daily = {
		label = "Daily Puzzle",
		description = "The same challenge for everyone, refreshed at midnight UTC.",
		tracksLevelProgress = false,
	},
	Zen = {
		label = "Zen Mode",
		description = "A relaxed random puzzle with no timer pressure.",
		tracksLevelProgress = false,
	},
}

GameConfig.Achievements = {
	FirstFind = { title = "First Find", description = "Find your first word." },
	FirstClear = { title = "Puzzle Starter", description = "Complete your first puzzle." },
	PerfectSolve = { title = "Sharp Eyes", description = "Earn three stars without a hint." },
	TenClears = { title = "Word Hunter", description = "Complete ten puzzles." },
	DailySeven = { title = "Daily Devotion", description = "Reach a seven-day daily streak." },
}

-- Empty IDs are intentional placeholders. AudioController first reuses matching
-- Sounds already present under SoundService/SFX or SoundService/Music.
GameConfig.Assets = {
	LogoImage = "",
	ChapterImages = {},
	Sounds = {
		Button = "",
		Correct = "",
		Incorrect = "",
		Complete = "",
		Hint = "",
		Unlock = "",
		Music = "",
	},
}

function GameConfig.GetRankFromXp(xp)
	local remaining = math.clamp(math.floor(tonumber(xp) or 0), 0, GameConfig.Progression.MaxXp)
	local rank = 1
	local requirement = 100

	while remaining >= requirement and rank < 999 do
		remaining -= requirement
		rank += 1
		requirement = 100 + ((rank - 1) * 50)
	end

	return rank, remaining, requirement
end

return table.freeze(GameConfig)
