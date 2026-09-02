local LevelCatalog = {}

local GameConfig
if game then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
	local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
	GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
else
	GameConfig = require("../../shared/config/GameConfig")
end

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

-- The first four levels in each chapter are intentionally hand-curated above. The
-- extended campaign is data-driven: every definition owns a deterministic word
-- list and seed, while PuzzleGenerator builds and validates the actual letter grid.
-- New bonus levels are interleaved in catalog order so players unlock variety
-- across chapters instead of grinding sixteen consecutive levels in one theme.
local EXPANSION_CONTENT = {
	Animals = {
		slug = "animals",
		titles = {
			"Safari Tracks", "Ocean Parade", "Feathered Friends", "Forest Footprints",
			"Tiny Creatures", "Arctic Expedition", "Jungle Chorus", "Desert Dwellers",
			"River Wildlife", "Night Hunters", "Island Habitat", "Mountain Herds",
			"Rainforest Rally", "Creature Kingdom", "Wildlife Atlas", "Animal Odyssey",
		},
		words = {
			"PANTHER", "JAGUAR", "GIRAFFE", "ZEBRA", "MONKEY", "RABBIT", "TURTLE", "DOLPHIN",
			"WHALE", "SHARK", "OCTOPUS", "PENGUIN", "EAGLE", "FALCON", "PARROT", "OWL",
			"FOX", "WOLF", "OTTER", "BADGER", "HAMSTER", "DONKEY", "HORSE", "SHEEP",
			"LLAMA", "CAMEL", "KOALA", "WOMBAT", "MEERKAT", "RACCOON", "SQUIRREL", "HEDGEHOG",
			"BUTTERFLY", "DRAGONFLY", "BEETLE", "SPIDER", "CRICKET", "LOBSTER", "SALMON", "SEAHORSE",
			"STINGRAY", "JELLYFISH", "CROCODILE", "ALLIGATOR", "RHINOCEROS", "HIPPOPOTAMUS", "ELEPHANT", "KANGAROO",
			"CHIMPANZEE", "FLAMINGO", "PEACOCK", "OSTRICH", "GAZELLE", "BUFFALO", "BISON", "MOOSE",
			"REINDEER", "LEOPARD", "CHEETAH", "HYENA", "GORILLA", "IGUANA",
		},
	},
	Food = {
		slug = "food",
		titles = {
			"Fruit Stand", "Garden Pantry", "Breakfast Table", "Pizza Party",
			"Bakery Window", "Street Food", "Family Feast", "Sweet Tooth",
			"Global Kitchen", "Picnic Basket", "Cafe Rush", "Harvest Dinner",
			"Chef Challenge", "Festival Flavors", "Midnight Menu", "Ultimate Banquet",
		},
		words = {
			"BANANA", "ORANGE", "STRAWBERRY", "BLUEBERRY", "RASPBERRY", "WATERMELON", "MANGO", "PAPAYA",
			"APRICOT", "PLUM", "CHERRY", "LEMON", "LIME", "ONION", "GARLIC", "POTATO",
			"TOMATO", "CUCUMBER", "LETTUCE", "SPINACH", "CABBAGE", "CELERY", "RADISH", "PUMPKIN",
			"PEPPER", "CHEESE", "YOGURT", "BUTTER", "OMELETTE", "SAUSAGE", "BACON", "CHICKEN",
			"TURKEY", "STEAK", "PASTA", "PIZZA", "TACO", "SUSHI", "CURRY", "SOUP",
			"CEREAL", "GRANOLA", "BROWNIE", "DONUT", "PUDDING", "CUSTARD", "VANILLA", "HONEY",
			"JAM", "BAGEL", "TOAST", "BISCUIT", "CRACKER", "LASAGNA", "RISOTTO", "DUMPLING",
			"MEATBALL", "SMOOTHIE", "LEMONADE", "ESPRESSO", "KETCHUP", "MUSTARD", "MAYO",
		},
	},
	Nature = {
		slug = "nature",
		titles = {
			"Coastal Path", "Desert Bloom", "Alpine Trail", "Wetland Wonders",
			"Stone and Soil", "Changing Skies", "Hidden Lagoon", "Frozen North",
			"Storm Watch", "Forest Canopy", "Island Winds", "Earth in Motion",
			"Wild Ecosystems", "Natural Forces", "Planet Wilderness", "Endless Outdoors",
		},
		words = {
			"OCEAN", "BEACH", "COAST", "ISLAND", "DESERT", "JUNGLE", "PRAIRIE", "SAVANNA",
			"TUNDRA", "CAVE", "CLIFF", "RIDGE", "SUMMIT", "CRATER", "GEYSER", "LAGOON",
			"STREAM", "CREEK", "POND", "LAKE", "MARSH", "SWAMP", "WETLAND", "CORAL",
			"REEF", "SAND", "SOIL", "MOSS", "FERN", "BLOSSOM", "PETAL", "ROOT",
			"BARK", "BRANCH", "SEED", "ACORN", "PEBBLE", "BOULDER", "GRANITE", "CRYSTAL",
			"BREEZE", "WIND", "FROST", "SNOW", "HAIL", "MIST", "FOG", "DEW",
			"DROPLET", "MONSOON", "CYCLONE", "TORNADO", "HURRICANE", "EARTHQUAKE", "ERUPTION", "GEOTHERMAL",
			"ECOSYSTEM", "HABITAT", "CANOPY", "RAINFOREST", "SUNSHINE", "MOONLIGHT", "STARLIGHT",
		},
	},
	Roblox = {
		slug = "roblox",
		titles = {
			"Obby Workshop", "Quest Hub", "Builder Basics", "Scripting Sprint",
			"Avatar Adventure", "Tycoon Toolkit", "Interface Lab", "Physics Playground",
			"Creator Challenge", "Multiplayer Mayhem", "Asset Library", "Terrain Teamwork",
			"Systems Online", "Studio Specialist", "Engine Expert", "Creator Odyssey",
		},
		words = {
			"PLATFORM", "RESPAWN", "INVENTORY", "QUEST", "PORTAL", "VEHICLE", "CAMERA", "LIGHTING",
			"TERRAIN", "MATERIAL", "TEXTURE", "MESH", "MODEL", "FOLDER", "INSTANCE", "EVENT",
			"FUNCTION", "VARIABLE", "VECTOR", "CFRAME", "PHYSICS", "COLLISION", "ANCHOR", "WELD",
			"CONSTRAINT", "RAYCAST", "PATHFINDING", "NAVIGATION", "GUI", "BUTTON", "FRAME", "CANVAS",
			"VIEWPORT", "TWEEN", "SOUND", "MUSIC", "CHAT", "TEAM", "SCORE", "COINS",
			"SHOP", "PETS", "TRADE", "CRAFTING", "SURVIVAL", "ADVENTURE", "SIMULATOR", "SPEEDRUN",
			"PARKOUR", "BATTLE", "ROUND", "LOBBY", "MATCHMAKING", "FRIENDS", "GROUP", "CREATOR",
			"PUBLISH", "PLUGIN", "ASSET", "PACKAGE", "DEBUGGER", "PROFILE", "THUMBNAIL",
		},
	},
	Space = {
		slug = "space",
		titles = {
			"Solar Survey", "Moon Mission", "Planet Patrol", "Rover Route",
			"Astronaut Academy", "Nebula Crossing", "Launch Complex", "Cosmic Signals",
			"Deep Space Probe", "Galaxy Guide", "Stellar Science", "Mission Control",
			"Interstellar Voyage", "Edge of Orbit", "Cosmic Frontier", "Universe Unbound",
		},
		words = {
			"MERCURY", "VENUS", "EARTH", "JUPITER", "URANUS", "NEPTUNE", "PLUTO", "SOLAR",
			"LUNAR", "CRATER", "VACUUM", "RADIATION", "ATMOSPHERE", "EXOPLANET", "BLACKHOLE", "PULSAR",
			"QUASAR", "DWARF", "CLUSTER", "ORBITER", "PROBE", "ROVER", "MODULE", "LAUNCH",
			"BOOSTER", "ENGINE", "FUEL", "HELMET", "SPACESUIT", "MISSION", "VOYAGE", "DOCKING",
			"PAYLOAD", "CREW", "CONTROL", "SIGNAL", "ANTENNA", "RADAR", "OBSERVATORY", "ASTRONOMY",
			"COSMOLOGY", "LIGHTYEAR", "AURORA", "MAGNETIC", "ECLIPTIC", "EQUINOX", "SOLSTICE", "ZODIAC",
			"PHOTON", "PARTICLE", "FUSION", "HELIUM", "HYDROGEN", "IMPACT", "MOONDUST", "STARFIELD",
			"MILKYWAY", "ANDROMEDA", "HORIZON", "DISCOVERY", "EXPLORER", "INTERSTELLAR",
		},
	},
	Expert = {
		slug = "expert",
		titles = {
			"Algorithm Alley", "Scholar Summit", "Logic Labyrinth", "Knowledge Matrix",
			"Precision Grid", "Vocabulary Vault", "Mastermind Map", "Abstract Arena",
			"Strategic Search", "Complexity Curve", "Grand Lexicon", "Focus Frontier",
			"Ultimate Pattern", "Expert Equation", "Impossible Index", "Word Search Legend",
		},
		words = {
			"ALGORITHM", "ARCHITECTURE", "BIODIVERSITY", "CHRONOLOGY", "CIRCUMSTANCE", "CIVILIZATION", "COMMUNICATION", "CONSTELLATION",
			"CONTEMPLATION", "CRYPTOGRAPHY", "DETERMINATION", "ELECTROMAGNET", "ENTREPRENEUR", "ENVIRONMENTAL", "EQUILIBRIUM", "EXPERIMENTAL",
			"FUNDAMENTAL", "GEOMETRICAL", "HYPOTHESIS", "IMAGINATION", "INFRASTRUCTURE", "INNOVATION", "INTERPRETATION", "JURISDICTION",
			"LITERATURE", "MATHEMATICS", "METAMORPHOSIS", "MICROSCOPE", "NAVIGATION", "OBSERVATION", "OPPORTUNITY", "ORGANIZATION",
			"PERSPECTIVE", "PHOTOGRAPHY", "PROBABILITY", "PROGRAMMING", "RECOGNITION", "RELATIONSHIP", "RESPONSIBILITY", "REVOLUTIONARY",
			"SIGNIFICANCE", "SIMULTANEOUS", "SPECTACULAR", "TECHNOLOGY", "TEMPERATURE", "TRANSFORMATION", "TRANSPARENT", "UNDERSTANDING",
			"UNIVERSAL", "VELOCITY", "VIBRATION", "ACCELERATION", "ARTICULATION", "CARTOGRAPHY", "COLLABORATION", "COMBINATION",
			"COMPUTATION", "CONFIGURATION", "COORDINATION", "DECLARATION", "DEFINITION", "DEMONSTRATION", "ENCYCLOPEDIC", "GENERALIZATION",
			"IDENTIFICATION", "IMPLEMENTATION", "INDEPENDENCE", "INTELLIGENCE", "MULTIPLICATION", "PHILOSOPHICAL", "REPRESENTATION", "STRATEGIC",
		},
	},
}

local function slugify(value)
	local slug = string.lower(value):gsub("[^a-z0-9]+", "-"):gsub("^%-", ""):gsub("%-$", "")
	return slug
end

local function getExpansionSettings(chapterId, order)
	if chapterId == "Expert" then
		local size = math.clamp(14 + math.floor((order - 5) / 5), 14, 17)
		return "Expert", size, math.min(10, 8 + math.floor((order - 3) / 4)), 220 + ((order - 5) * 7)
	end
	if order >= 15 then
		local size = 14 + math.floor((order - 15) / 3)
		return "Expert", size, order >= 18 and 10 or 9, 215 + ((order - 15) * 8)
	end
	local size = math.clamp(11 + math.floor((order - 5) / 4), 11, 13)
	return "Hard", size, order >= 9 and 8 or 7, 150 + ((order - 5) * 6)
end

local function pickExpansionWords(bank, startIndex, count, maximumLength)
	local selected = {}
	local selectedSet = {}
	for offset = 0, (#bank * 2) - 1 do
		local word = bank[((startIndex + offset - 1) % #bank) + 1]
		-- Five-letter minimums keep large generated boards readable and make an
		-- accidental second target occurrence in random filler vanishingly rare.
		if not selectedSet[word] and #word >= 5 and #word <= maximumLength then
			local conflicts = false
			for _, existing in ipairs(selected) do
				if string.find(word, existing, 1, true) or string.find(existing, word, 1, true) then
					conflicts = true
					break
				end
			end
			if not conflicts then
				selectedSet[word] = true
				table.insert(selected, word)
				if #selected >= count then
					return selected
				end
			end
		end
	end
	error(string.format("Expansion word bank could not supply %d words of length %d", count, maximumLength))
end

for order = 5, 20 do
	for chapterIndex, chapter in ipairs(chapters) do
		local content = assert(EXPANSION_CONTENT[chapter.id], "Expansion content is missing for " .. chapter.id)
		local title = assert(content.titles[order - 4], "Expansion title is missing")
		local difficulty, width, wordCount, timeLimitSeconds = getExpansionSettings(chapter.id, order)
		local startIndex = (((order - 5) * 11) + ((chapterIndex - 1) * 7)) % #content.words
		local words = pickExpansionWords(content.words, startIndex, wordCount, width)
		local levelId = string.format("%s-%02d-%s", content.slug, order, slugify(title))
		local seed = (chapterIndex * 1000000) + (order * 10007) + 73
		local description = string.format("A generated %dx%d %s challenge with %d themed words.", width, width, string.lower(difficulty), wordCount)
		table.insert(levels, makeGenerated(
			chapter.id,
			order,
			levelId,
			title,
			description,
			difficulty,
			width,
			width,
			timeLimitSeconds,
			seed,
			words
		))
	end
end

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
