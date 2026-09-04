local WordBank = require(script.Parent:WaitForChild("WordBank"))

local function cloneArray(values)
	local result = {}

	for index, value in ipairs(values) do
		result[index] = value
	end

	return result
end

local function appendUnique(target, seen, word)
	if not seen[word] then
		seen[word] = true
		table.insert(target, word)
	end
end

local function buildPool(sources, minLength, maxLength)
	local pool = {}
	local seen = {}

	for _, source in ipairs(sources) do
		for _, word in ipairs(source) do
			if #word >= minLength and #word <= maxLength then
				appendUnique(pool, seen, word)
			end
		end
	end

	return pool
end

local function interpolateInt(minValue, maxValue, offset, total)
	if minValue == maxValue or total <= 1 then
		return minValue
	end

	local alpha = (offset - 1) / (total - 1)
	return math.floor(minValue + (maxValue - minValue) * alpha + 0.5)
end

local function shuffle(values, randomObject)
	local result = cloneArray(values)

	for index = #result, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end

	return result
end

local function wordsOverlap(candidate, chosenWords)
	for _, existing in ipairs(chosenWords) do
		if existing == candidate then
			return true
		end

		if string.find(existing, candidate, 1, true) or string.find(candidate, existing, 1, true) then
			return true
		end
	end

	return false
end

local function chooseWords(pool, wordCount, seed)
	local randomObject = Random.new(seed)
	local orderedPool = shuffle(pool, randomObject)
	local chosenWords = {}

	for _, candidate in ipairs(orderedPool) do
		if not wordsOverlap(candidate, chosenWords) then
			table.insert(chosenWords, candidate)
		end

		if #chosenWords >= wordCount then
			return chosenWords
		end
	end

	for _, candidate in ipairs(orderedPool) do
		if not table.find(chosenWords, candidate) then
			table.insert(chosenWords, candidate)
		end

		if #chosenWords >= wordCount then
			return chosenWords
		end
	end

	error(string.format("Unable to choose %d unique words from a pool of %d.", wordCount, #pool))
end

local LEVEL_TIERS = {
	{
		name = "Very Easy",
		packName = "VeryEasy",
		stages = {
			{
				count = 2,
				subtitle = "Starter lanes",
				gridMin = 5,
				gridMax = 5,
				wordMin = 2,
				wordMax = 2,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Tiny stretch",
				gridMin = 5,
				gridMax = 5,
				wordMin = 3,
				wordMax = 3,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 2,
				subtitle = "Wide open",
				gridMin = 5,
				gridMax = 6,
				wordMin = 2,
				wordMax = 3,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Longer look",
				gridMin = 6,
				gridMax = 6,
				wordMin = 3,
				wordMax = 3,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Steady search",
				gridMin = 6,
				gridMax = 6,
				wordMin = 3,
				wordMax = 4,
				minLength = 3,
				maxLength = 4,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy },
			},
			{
				count = 1,
				subtitle = "Crowded lane",
				gridMin = 6,
				gridMax = 6,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Bigger board",
				gridMin = 6,
				gridMax = 7,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "First diagonals",
				gridMin = 7,
				gridMax = 7,
				wordMin = 4,
				wordMax = 4,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Diagonal warmup",
				gridMin = 7,
				gridMax = 7,
				wordMin = 4,
				wordMax = 5,
				minLength = 3,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "Cross search",
				gridMin = 7,
				gridMax = 7,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Open corners",
				gridMin = 7,
				gridMax = 8,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 1,
				subtitle = "Denser sweep",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Warmup finish",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 2,
				subtitle = "Packed finish",
				gridMin = 8,
				gridMax = 8,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 3,
				subtitle = "Ready for Easy",
				gridMin = 8,
				gridMax = 9,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
		},
	},
	{
		name = "Easy",
		packName = "Easy",
		stages = {
			{
				count = 5,
				subtitle = "Diagonal warmup",
				gridMin = 7,
				gridMax = 8,
				wordMin = 5,
				wordMax = 5,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE" },
				sources = { WordBank.BabyEasy, WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Open corners",
				gridMin = 8,
				gridMax = 8,
				wordMin = 5,
				wordMax = 6,
				minLength = 4,
				maxLength = 5,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Search sweep",
				gridMin = 8,
				gridMax = 9,
				wordMin = 6,
				wordMax = 6,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy },
			},
			{
				count = 5,
				subtitle = "Denser lanes",
				gridMin = 9,
				gridMax = 9,
				wordMin = 6,
				wordMax = 7,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Packed corners",
				gridMin = 9,
				gridMax = 10,
				wordMin = 7,
				wordMax = 8,
				minLength = 4,
				maxLength = 6,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
		},
	},
	{
		name = "Hard",
		packName = "Hard",
		stages = {
			{
				count = 5,
				subtitle = "Climb begins",
				gridMin = 10,
				gridMax = 10,
				wordMin = 8,
				wordMax = 8,
				minLength = 5,
				maxLength = 6,
				directions = { "E", "S", "SE" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Dense lanes",
				gridMin = 10,
				gridMax = 11,
				wordMin = 8,
				wordMax = 9,
				minLength = 5,
				maxLength = 7,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium },
			},
			{
				count = 5,
				subtitle = "Crowded middle",
				gridMin = 11,
				gridMax = 11,
				wordMin = 9,
				wordMax = 9,
				minLength = 5,
				maxLength = 7,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Easy, WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Longer clues",
				gridMin = 11,
				gridMax = 12,
				wordMin = 9,
				wordMax = 10,
				minLength = 5,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Sharp search",
				gridMin = 12,
				gridMax = 12,
				wordMin = 10,
				wordMax = 10,
				minLength = 6,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
		},
	},
	{
		name = "Very Hard",
		packName = "VeryHard",
		stages = {
			{
				count = 5,
				subtitle = "Heavy boards",
				gridMin = 12,
				gridMax = 13,
				wordMin = 10,
				wordMax = 11,
				minLength = 6,
				maxLength = 8,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Big sweeps",
				gridMin = 13,
				gridMax = 13,
				wordMin = 11,
				wordMax = 11,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Dense giants",
				gridMin = 13,
				gridMax = 14,
				wordMin = 11,
				wordMax = 12,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Final climb",
				gridMin = 14,
				gridMax = 14,
				wordMin = 12,
				wordMax = 12,
				minLength = 6,
				maxLength = 9,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Master boards",
				gridMin = 14,
				gridMax = 15,
				wordMin = 12,
				wordMax = 13,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Medium, WordBank.Hard },
			},
		},
	},
	{
		name = "Expert",
		packName = "Expert",
		stages = {
			{
				count = 5,
				subtitle = "Endgame opens",
				gridMin = 15,
				gridMax = 15,
				wordMin = 13,
				wordMax = 13,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Longer sweeps",
				gridMin = 15,
				gridMax = 16,
				wordMin = 13,
				wordMax = 14,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Tight spacing",
				gridMin = 16,
				gridMax = 16,
				wordMin = 14,
				wordMax = 14,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Heavy search",
				gridMin = 16,
				gridMax = 17,
				wordMin = 14,
				wordMax = 15,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Brutal finish",
				gridMin = 17,
				gridMax = 17,
				wordMin = 15,
				wordMax = 15,
				minLength = 7,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
		},
	},
	{
		name = "Master",
		packName = "Master",
		stages = {
			{
				count = 5,
				subtitle = "Master rise",
				gridMin = 17,
				gridMax = 18,
				wordMin = 15,
				wordMax = 16,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Packed giant boards",
				gridMin = 18,
				gridMax = 18,
				wordMin = 16,
				wordMax = 16,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Needle hunt",
				gridMin = 18,
				gridMax = 19,
				wordMin = 16,
				wordMax = 17,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Massive density",
				gridMin = 19,
				gridMax = 19,
				wordMin = 17,
				wordMax = 17,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
			{
				count = 5,
				subtitle = "Final gauntlet",
				gridMin = 19,
				gridMax = 20,
				wordMin = 17,
				wordMax = 18,
				minLength = 8,
				maxLength = 10,
				directions = { "E", "S", "SE", "SW" },
				sources = { WordBank.Hard },
			},
		},
	},
}

local Levels = {}

for _, tier in ipairs(LEVEL_TIERS) do
	local tierStartLevel = #Levels + 1

	for stageIndex, stage in ipairs(tier.stages) do
		local pool = buildPool(stage.sources, stage.minLength, stage.maxLength)
		assert(#pool >= stage.wordMax, string.format("Word pool too small for %s stage %d.", tier.name, stageIndex))

		for offset = 1, stage.count do
			local levelNumber = #Levels + 1
			local tierLevelNumber = levelNumber - tierStartLevel + 1
			local wordCount = interpolateInt(stage.wordMin, stage.wordMax, offset, stage.count)
			local gridSize = math.max(
				interpolateInt(stage.gridMin, stage.gridMax, offset, stage.count),
				stage.maxLength + 1
			)
			local seed = 4100 + levelNumber * 977 + stageIndex * 131
			local words = chooseWords(pool, wordCount, seed)
			local directions = cloneArray(stage.directions)
			local subtitle = string.format("%s - %s", tier.name, stage.subtitle)

			-- Board 1 is a deliberate onboarding board: two familiar words,
			-- a smaller grid, and left-to-right placement only.
			if levelNumber == 1 then
				gridSize = 4
				words = { "CAT", "DOG" }
				directions = { "E" }
				subtitle = "Very Easy - First steps"
			end

			table.insert(Levels, {
				level = levelNumber,
				title = string.format("Level %d", levelNumber),
				subtitle = subtitle,
				tier = tier.name,
				pack = tier.packName or tier.name,
				tierLevel = tierLevelNumber,
				packLevel = tierLevelNumber,
				gridSize = gridSize,
				words = words,
				directions = directions,
				seed = seed,
			})
		end
	end
end

return Levels
