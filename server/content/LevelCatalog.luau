local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelCatalog = {}

local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))

local DIRECTION_PROFILES = {
	Easy = { "E", "S" },
	Medium = { "E", "S", "SE", "SW" },
	Hard = { "E", "S", "SE", "SW", "W", "N" },
	Expert = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" },
}

local function cloneArray(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
end

local function deepFreeze(value)
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end

	for _, child in pairs(value) do
		if type(child) == "table" then
			deepFreeze(child)
		end
	end

	return table.freeze(value)
end

local function makeGenerated(chapterId, order, id, title, description, difficulty, width, height, timeLimitSeconds, seed, words)
	return {
		schemaVersion = GameConfig.SchemaVersion,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
		id = id,
		revision = 1,
		kind = "Generated",
		chapterId = chapterId,
		order = order,
		title = title,
		description = description,
		difficulty = difficulty,
		width = width,
		height = height,
		timeLimitSeconds = timeLimitSeconds,
		seed = seed,
		directions = cloneArray(DIRECTION_PROFILES[difficulty]),
		words = cloneArray(words),
	}
end

local function makeAuthored(chapterId, order, id, title, description, difficulty, width, height, timeLimitSeconds, seed, words, grid, targets)
	return {
		schemaVersion = GameConfig.SchemaVersion,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
		id = id,
		revision = 1,
		kind = "Authored",
		chapterId = chapterId,
		order = order,
		title = title,
		description = description,
		difficulty = difficulty,
		width = width,
		height = height,
		timeLimitSeconds = timeLimitSeconds,
		seed = seed,
		directions = cloneArray(DIRECTION_PROFILES[difficulty]),
		words = cloneArray(words),
		grid = cloneArray(grid),
		targets = targets,
	}
end

local chapters = {
	{
		id = "Animals",
		title = "Animals",
		description = "Friendly pets, wild creatures, and ocean animals.",
		order = 1,
	},
	{
		id = "Food",
		title = "Food",
		description = "Fruit, snacks, meals, and bakery favorites.",
		order = 2,
	},
	{
		id = "Nature",
		title = "Nature",
		description = "Forests, weather, landscapes, and natural wonders.",
		order = 3,
	},
	{
		id = "Roblox",
		title = "Roblox",
		description = "Familiar building, scripting, and adventure terms.",
		order = 4,
	},
	{
		id = "Space",
		title = "Space",
		description = "Planets, spacecraft, and deep-space discoveries.",
		order = 5,
	},
	{
		id = "Expert",
		title = "Expert",
		description = "Large boards, long words, and every direction.",
		order = 6,
	},
}

local levels = {
	makeAuthored(
		"Animals",
		1,
		"animals-friendly-pets",
		"Friendly Pets",
		"Meet four familiar animals on a hand-crafted starter board.",
		"Easy",
		8,
		8,
		75,
		110101,
		{ "CAT", "DOG", "BIRD", "FISH" },
		{
			"CATQBZXM",
			"ZXQWIPLK",
			"DOGVRXQK",
			"QXZWDPKL",
			"FISHMVBN",
			"XJQZNVBR",
			"QXKPZVBN",
			"ZXQHNVBR",
		},
		{
			{
				id = "animals-friendly-pets:cat",
				word = "CAT",
				path = { { row = 1, column = 1 }, { row = 1, column = 2 }, { row = 1, column = 3 } },
			},
			{
				id = "animals-friendly-pets:dog",
				word = "DOG",
				path = { { row = 3, column = 1 }, { row = 3, column = 2 }, { row = 3, column = 3 } },
			},
			{
				id = "animals-friendly-pets:bird",
				word = "BIRD",
				path = { { row = 1, column = 5 }, { row = 2, column = 5 }, { row = 3, column = 5 }, { row = 4, column = 5 } },
			},
			{
				id = "animals-friendly-pets:fish",
				word = "FISH",
				path = { { row = 5, column = 1 }, { row = 5, column = 2 }, { row = 5, column = 3 }, { row = 5, column = 4 } },
			},
		}
	),
	makeGenerated("Animals", 2, "animals-pond-and-farm", "Pond and Farm", "Search the sunny farmyard in simple forward lanes.", "Easy", 8, 8, 85, 110202, {
		"LION", "BEAR", "FROG", "DUCK", "GOAT",
	}),
	makeGenerated("Animals", 3, "animals-wild-trails", "Wild Trails", "Diagonal tracks lead toward animals from every habitat.", "Medium", 9, 9, 110, 110303, {
		"MONKEY", "RABBIT", "TURTLE", "PARROT", "OTTER", "BADGER",
	}),
	makeGenerated("Animals", 4, "animals-great-migration", "Great Migration", "Long animal names cross a busy reserve in reverse and diagonal lanes.", "Hard", 11, 10, 145, 110404, {
		"ELEPHANT", "GIRAFFE", "CHEETAH", "DOLPHIN", "PANTHER", "WALRUS", "BUFFALO",
	}),

	makeGenerated("Food", 1, "food-market-basket", "Market Basket", "Pick out everyday foods from tidy rows and columns.", "Easy", 8, 8, 85, 220101, {
		"APPLE", "BREAD", "PEACH", "GRAPE", "RICE",
	}),
	makeGenerated("Food", 2, "food-cafe-corner", "Cafe Corner", "A cozy cafe introduces crossing diagonal words.", "Medium", 9, 9, 110, 220202, {
		"COOKIE", "CARROT", "MUFFIN", "NOODLE", "WAFFLE", "SALAD",
	}),
	makeGenerated("Food", 3, "food-snack-festival", "Snack Festival", "Festival favorites run forward, backward, and diagonally.", "Hard", 11, 11, 145, 220303, {
		"AVOCADO", "POPCORN", "PANCAKE", "CUPCAKE", "BURGER", "PRETZEL", "COCONUT",
	}),
	makeGenerated("Food", 4, "food-master-kitchen", "Master Kitchen", "A packed kitchen serves the chapter's longest menu.", "Hard", 12, 12, 165, 220404, {
		"SPAGHETTI", "CHOCOLATE", "SANDWICH", "CINNAMON", "BROCCOLI", "PINEAPPLE", "CROISSANT",
	}),

	makeGenerated("Nature", 1, "nature-garden-walk", "Garden Walk", "Begin outdoors with short words in clear forward paths.", "Easy", 8, 8, 85, 330101, {
		"TREE", "RAIN", "ROCK", "LEAF", "CLOUD",
	}),
	makeGenerated("Nature", 2, "nature-river-valley", "River Valley", "Follow the river through meadows and diagonal trails.", "Medium", 9, 9, 115, 330202, {
		"FOREST", "RIVER", "MEADOW", "FLOWER", "VALLEY", "SUNSET",
	}),
	makeGenerated("Nature", 3, "nature-wild-horizon", "Wild Horizon", "Mountains and storms hide along challenging reverse routes.", "Hard", 11, 11, 150, 330303, {
		"MOUNTAIN", "WATERFALL", "RAINBOW", "THUNDER", "GLACIER", "CANYON", "HORIZON",
	}),
	makeGenerated("Nature", 4, "nature-force-of-nature", "Force of Nature", "Extreme weather fills a dense wilderness board.", "Hard", 12, 12, 170, 330404, {
		"VOLCANO", "BLIZZARD", "EVERGREEN", "WILDLIFE", "WOODLAND", "AVALANCHE", "LIGHTNING",
	}),

	makeGenerated("Roblox", 1, "roblox-first-spawn", "First Spawn", "Find the words every new Roblox adventurer meets.", "Easy", 8, 8, 85, 440101, {
		"OBBY", "BRICK", "BADGE", "SPAWN", "AVATAR",
	}),
	makeGenerated("Roblox", 2, "roblox-creator-studio", "Creator Studio", "Build and script through crossing creator vocabulary.", "Medium", 9, 9, 115, 440202, {
		"TYCOON", "STUDIO", "SCRIPT", "SERVER", "PLAYER", "LUAU",
	}),
	makeGenerated("Roblox", 3, "roblox-checkpoint-rush", "Checkpoint Rush", "Long gameplay terms can now face backward.", "Hard", 12, 12, 155, 440303, {
		"CHECKPOINT", "LEADERBOARD", "HUMANOID", "TOOLBOX", "BACKPACK", "TELEPORT", "PARTICLE",
	}),
	makeGenerated("Roblox", 4, "roblox-engine-room", "Engine Room", "Use every direction to master advanced Studio terms.", "Expert", 18, 18, 230, 440404, {
		"REPLICATEDSTORAGE", "REMOTEEVENT", "MODULESCRIPT", "DATASTORE", "WORKSPACE", "CHARACTER", "ANIMATION", "ATTRIBUTE", "COLLECTION",
	}),

	makeGenerated("Space", 1, "space-night-sky", "Night Sky", "Look up and spot simple space words.", "Easy", 8, 8, 85, 550101, {
		"MOON", "STAR", "MARS", "COMET", "ORBIT",
	}),
	makeGenerated("Space", 2, "space-launch-day", "Launch Day", "Rockets and planets cross the launch window.", "Medium", 9, 9, 115, 550202, {
		"PLANET", "ROCKET", "NEBULA", "SATURN", "COSMOS", "METEOR",
	}),
	makeGenerated("Space", 3, "space-orbital-station", "Orbital Station", "Navigate a station filled with reverse flight paths.", "Hard", 11, 11, 155, 550303, {
		"ASTEROID", "GRAVITY", "SHUTTLE", "THRUSTER", "LANDING", "COMMAND", "CAPSULE",
	}),
	makeGenerated("Space", 4, "space-deep-universe", "Deep Universe", "Every direction opens across a vast star field.", "Expert", 14, 14, 205, 550404, {
		"CONSTELLATION", "ASTRONAUT", "SATELLITE", "TELESCOPE", "SPACECRAFT", "SUPERNOVA", "GALAXY", "ECLIPSE", "UNIVERSE",
	}),

	makeGenerated("Expert", 1, "expert-word-architect", "Word Architect", "Long academic words test deliberate scanning in every direction.", "Expert", 14, 14, 220, 660101, {
		"LABYRINTH", "ENCYCLOPEDIA", "KALEIDOSCOPE", "ARCHAEOLOGY", "PHILOSOPHY", "CURIOSITY", "MAGNITUDE", "PERSEVERE",
	}),
	makeGenerated("Expert", 2, "expert-science-vault", "Science Vault", "Unlock a dense vault of scientific vocabulary.", "Expert", 14, 14, 225, 660202, {
		"QUANTUM", "MOLECULE", "TELESCOPE", "GRAVITY", "SPECTRUM", "VELOCITY", "CHEMISTRY", "ELECTRON", "NEBULA", "CRYSTAL",
	}),
	makeGenerated("Expert", 3, "expert-language-lab", "Language Lab", "Grammar and wordcraft collide across the full compass.", "Expert", 15, 15, 240, 660303, {
		"VOCABULARY", "CONSONANT", "SYLLABLE", "THESAURUS", "ANAGRAM", "LEXICON", "METAPHOR", "NARRATIVE", "PUNCTUATION", "LANGUAGE",
	}),
	makeGenerated("Expert", 4, "expert-grand-finale", "Grand Finale", "Complete the catalog's largest test of focus and endurance.", "Expert", 16, 16, 270, 660404, {
		"CHAMPIONSHIP", "EXPLORATION", "DISCOVERY", "ADVENTURE", "KNOWLEDGE", "STRATEGY", "VICTORIOUS", "ENDURANCE", "MASTERY", "TRIUMPH", "LEGENDARY", "CHALLENGE",
	}),
}

local levelById = {}
local levelIndexById = {}
local chapterById = {}

for _, chapter in ipairs(chapters) do
	chapter.levelIds = {}
	chapterById[chapter.id] = chapter
end

for index, level in ipairs(levels) do
	assert(levelById[level.id] == nil, string.format("Duplicate level id %s", level.id))
	local chapter = chapterById[level.chapterId]
	assert(chapter ~= nil, string.format("Unknown chapter %s", tostring(level.chapterId)))
	assert(level.width <= GameConfig.Gameplay.MaxGridWidth and level.height <= GameConfig.Gameplay.MaxGridHeight, "Catalog grid exceeds GameConfig")
	assert(#level.words <= GameConfig.Gameplay.MaxWords, "Catalog word count exceeds GameConfig")

	level.catalogIndex = index
	levelById[level.id] = level
	levelIndexById[level.id] = index
	table.insert(chapter.levelIds, level.id)
end

local publicChapters = {}
for index, chapter in ipairs(chapters) do
	publicChapters[index] = {
		id = chapter.id,
		title = chapter.title,
		description = chapter.description,
		order = chapter.order,
		levelIds = cloneArray(chapter.levelIds),
	}
end

local publicLevels = {}
for index, level in ipairs(levels) do
	publicLevels[index] = {
		id = level.id,
		index = index,
		revision = level.revision,
		kind = level.kind,
		chapterId = level.chapterId,
		order = level.order,
		title = level.title,
		description = level.description,
		difficulty = level.difficulty,
		width = level.width,
		height = level.height,
		wordCount = #level.words,
		timeLimitSeconds = level.timeLimitSeconds,
		dailyEligible = level.dailyEligible ~= false,
	}
end

local publicDailyLevels = {}
for _, level in ipairs(publicLevels) do
	if level.dailyEligible then
		table.insert(publicDailyLevels, level)
	end
end

local publicCatalog = {
	schemaVersion = GameConfig.SchemaVersion,
	contentRevision = GameConfig.ContentRevision,
	generatorVersion = GameConfig.GeneratorVersion,
	chapters = publicChapters,
	levels = publicLevels,
}

deepFreeze(levels)
deepFreeze(chapters)
deepFreeze(publicCatalog)
deepFreeze(publicDailyLevels)

function LevelCatalog.GetLevel(id)
	if type(id) ~= "string" then
		return nil
	end
	return levelById[id]
end

function LevelCatalog.GetLevelByIndex(index)
	if type(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		return nil
	end
	return levels[index]
end

function LevelCatalog.GetLevelIndex(id)
	if type(id) ~= "string" then
		return nil
	end
	return levelIndexById[id]
end

function LevelCatalog.GetChapters()
	return publicChapters
end

function LevelCatalog.GetPublicCatalog()
	return publicCatalog
end

function LevelCatalog.GetLevelCount()
	return #levels
end

function LevelCatalog.GetDailyLevels()
	return publicDailyLevels
end

LevelCatalog.SchemaVersion = GameConfig.SchemaVersion
LevelCatalog.ContentRevision = GameConfig.ContentRevision
LevelCatalog.GeneratorVersion = GameConfig.GeneratorVersion

return table.freeze(LevelCatalog)
