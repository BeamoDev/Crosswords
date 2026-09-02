local DefinitionBuilder = {}

local sharedFolder = script.Parent.Parent
local contentFolder = sharedFolder:WaitForChild("content")
local WordBank = require(contentFolder:WaitForChild("WordBank"))

local EASY_DIRECTIONS = { "E", "S", "SE", "SW" }
local HARDCORE_DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local WORD_LENGTH_MIN = 4
local MODE_DEFINITIONS = {
	Classic = {
		key = "Classic",
		label = "Classic",
		subtitle = "Standard 12x20 board",
		sizeProfile = "Standard",
		gridWidth = 20,
		gridHeight = 12,
		wordCount = 10,
		directions = EASY_DIRECTIONS,
		sources = { "BabyEasy", "Easy", "Medium" },
	},
	Tiny = {
		key = "Tiny",
		label = "Tiny",
		subtitle = "Compact 9x9 board",
		sizeProfile = "Tiny",
		gridWidth = 9,
		gridHeight = 9,
		wordCount = 6,
		directions = EASY_DIRECTIONS,
		sources = { "BabyEasy", "Easy" },
	},
	Mega = {
		key = "Mega",
		label = "Mega",
		subtitle = "Huge 15x25 board",
		sizeProfile = "Jumbo",
		gridWidth = 25,
		gridHeight = 15,
		wordCount = 15,
		directions = EASY_DIRECTIONS,
		sources = { "Easy", "Medium", "Hard" },
	},
	Hardcore = {
		key = "Hardcore",
		label = "Hardcore",
		subtitle = "Hard 12x20 board",
		sizeProfile = "Standard",
		gridWidth = 20,
		gridHeight = 12,
		wordCount = 14,
		directions = HARDCORE_DIRECTIONS,
		sources = { "Medium", "Hard" },
	},
}
local MAX_PROFILE_WORD_LENGTH = math.max(
	MODE_DEFINITIONS.Tiny.gridWidth,
	MODE_DEFINITIONS.Tiny.gridHeight,
	MODE_DEFINITIONS.Classic.gridWidth,
	MODE_DEFINITIONS.Classic.gridHeight,
	MODE_DEFINITIONS.Mega.gridWidth,
	MODE_DEFINITIONS.Mega.gridHeight
)
local wordPoolByMode = {}

local function normalizeWord(word)
	if type(word) ~= "string" then
		return nil
	end

	local normalized = string.upper(word:gsub("%s+", ""))
	if normalized == "" then
		return nil
	end

	return normalized
end

local function cloneArray(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
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

local function getWordPoolForMode(modeDefinition)
	local modeKey = modeDefinition and modeDefinition.key or "Classic"
	if wordPoolByMode[modeKey] then
		return wordPoolByMode[modeKey]
	end

	local seen = {}
	local filteredPool = {}
	local maxWordLength = math.max(1, math.min(modeDefinition.gridWidth, modeDefinition.gridHeight))

	for _, sourceName in ipairs(modeDefinition.sources or {}) do
		local source = WordBank[sourceName]
		for _, rawWord in ipairs(source or {}) do
			local word = normalizeWord(rawWord)
			if word
				and not seen[word]
				and #word >= WORD_LENGTH_MIN
				and #word <= math.min(MAX_PROFILE_WORD_LENGTH, maxWordLength) then
				seen[word] = true
				table.insert(filteredPool, word)
			end
		end
	end

	wordPoolByMode[modeKey] = filteredPool
	return filteredPool
end

local function chooseWords(modeDefinition, seed)
	local randomObject = Random.new(math.max(1, math.floor(tonumber(seed) or 1)))
	local shuffledPool = shuffle(getWordPoolForMode(modeDefinition), randomObject)
	local chosenWords = {}
	local fallbackWords = {}
	local targetWordCount = math.max(1, math.floor(tonumber(modeDefinition and modeDefinition.wordCount) or MODE_DEFINITIONS.Classic.wordCount))

	for _, word in ipairs(shuffledPool) do
		if wordsOverlap(word, chosenWords) then
			table.insert(fallbackWords, word)
		else
			table.insert(chosenWords, word)
		end

		if #chosenWords >= targetWordCount then
			return chosenWords
		end
	end

	for _, word in ipairs(fallbackWords) do
		table.insert(chosenWords, word)
		if #chosenWords >= targetWordCount then
			break
		end
	end

	return chosenWords
end

function DefinitionBuilder.BuildDefinition(_level, mode, seed)
	local resolvedMode = tostring(mode or "Classic")
	local modeDefinition = MODE_DEFINITIONS[resolvedMode] or MODE_DEFINITIONS.Classic
	local resolvedSeed = math.max(1, math.floor(tonumber(seed) or 1))
	local gridWidth = math.max(1, math.floor(tonumber(modeDefinition.gridWidth) or MODE_DEFINITIONS.Classic.gridWidth))
	local gridHeight = math.max(1, math.floor(tonumber(modeDefinition.gridHeight) or MODE_DEFINITIONS.Classic.gridHeight))
	local gridSize = math.max(gridWidth, gridHeight)

	return {
		level = 1,
		title = modeDefinition.label,
		subtitle = modeDefinition.subtitle,
		gridSize = gridSize,
		gridWidth = gridWidth,
		gridHeight = gridHeight,
		maxGridSize = gridSize,
		maxGridWidth = gridWidth,
		maxGridHeight = gridHeight,
		sizeProfile = modeDefinition.sizeProfile,
		words = chooseWords(modeDefinition, resolvedSeed),
		directions = cloneArray(modeDefinition.directions),
		seed = resolvedSeed,
	}
end

return DefinitionBuilder
