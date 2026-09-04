local DefinitionBuilder = {}

local sharedFolder = script.Parent.Parent
local contentFolder = sharedFolder:WaitForChild("content")
local PuzzleLibrary = require(contentFolder:WaitForChild("PuzzleLibrary"))
local ThemedModeLibrary = require(contentFolder:WaitForChild("ThemedModeLibrary"))
local Levels = require(contentFolder:WaitForChild("Levels"))
local WordBank = require(contentFolder:WaitForChild("WordBank"))

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local LARGE_MODE_GRID_SIZE = 16

local FORWARD_DIRECTION_BY_GROUP = {
	horizontal = "E",
	vertical = "S",
	diagonalDownRight = "SE",
	diagonalDownLeft = "SW",
}

local BACKWARD_DIRECTION_BY_GROUP = {
	horizontal = "W",
	vertical = "N",
	diagonalDownRight = "NW",
	diagonalDownLeft = "NE",
}

local DIRECTION_GROUP_LOOKUP = {
	E = "horizontal",
	W = "horizontal",
	S = "vertical",
	N = "vertical",
	SE = "diagonalDownRight",
	NW = "diagonalDownRight",
	SW = "diagonalDownLeft",
	NE = "diagonalDownLeft",
}

local MODE_LIBRARY_LOOKUP = {
	Themed = "Themed",
	Freeplay = "Standard",
	Backwards = "Standard",
	Fog = "Standard",
	OneLife = "Standard",
	Mega = "Mega",
	Daily = "Daily",
}

local MODE_THEME_OFFSETS = {
	Themed = 17,
	Freeplay = 31,
	Backwards = 47,
	Fog = 89,
	OneLife = 101,
	Mega = 149,
	Daily = 197,
}

local MODE_TITLE_PREFIX = {
	Freeplay = "Freeplay",
	Backwards = "Backwards",
	Fog = "Fog",
	OneLife = "One Life",
	Mega = "MEGA",
	Daily = "Daily",
}

local function cloneArray(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
end

local function cloneDefinition(definition)
	return {
		level = definition.level,
		title = definition.title,
		subtitle = definition.subtitle,
		gridSize = definition.gridSize,
		maxGridSize = definition.maxGridSize,
		words = cloneArray(definition.words),
		directions = cloneArray(definition.directions),
		seed = definition.seed,
	}
end

local function shuffle(values, randomObject)
	local result = cloneArray(values)
	for index = #result, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		result[index], result[swapIndex] = result[swapIndex], result[index]
	end
	return result
end

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

local function pushUniqueDirection(target, seen, direction)
	if direction and not seen[direction] then
		seen[direction] = true
		table.insert(target, direction)
	end
end

local function normalizeDirectionsForMode(directions, useBackwards)
	local normalized = {}
	local seen = {}
	local directionLookup = useBackwards and BACKWARD_DIRECTION_BY_GROUP or FORWARD_DIRECTION_BY_GROUP

	for _, direction in ipairs(directions or {}) do
		local group = DIRECTION_GROUP_LOOKUP[direction]
		if group then
			pushUniqueDirection(normalized, seen, directionLookup[group])
		end
	end

	if #normalized == 0 then
		local fallbackDirections = useBackwards and { "W", "N", "NW", "NE" } or { "E", "S", "SE", "SW" }
		for _, direction in ipairs(fallbackDirections) do
			pushUniqueDirection(normalized, seen, direction)
		end
	end

	return normalized
end

local function getClassicTemplate(level)
	return Levels[math.clamp(math.max(1, math.floor(tonumber(level) or 1)), 1, MAX_CLASSIC_LEVEL)]
end

local function getModeLibrary(mode)
	local libraryName = MODE_LIBRARY_LOOKUP[mode]
	local library = nil
	if libraryName == "Themed" then
		library = ThemedModeLibrary.GetThemes()
	else
		library = libraryName and PuzzleLibrary[libraryName] or nil
	end
	if type(library) == "table" and #library > 0 then
		return library
	end
	return nil
end

local function chooseThemeEntry(mode, level, seed)
	local library = getModeLibrary(mode)
	if not library then
		return nil, nil, nil
	end

	local randomObject = Random.new(
		(math.max(1, math.floor(tonumber(seed) or 1)) * 1103)
		+ (math.max(1, math.floor(tonumber(level) or 1)) * 463)
		+ ((MODE_THEME_OFFSETS[mode] or 0) * 79)
	)
	local chosenIndex = randomObject:NextInteger(1, #library)
	return library[chosenIndex], chosenIndex, library
end

local function getTargetWordCount(mode, baseDefinition)
	local baseCount = math.max(1, #(baseDefinition.words or {}))
	if mode == "Themed" then
		return math.max(8, math.min(baseCount + 4, 12))
	end
	if mode == "Mega" then
		return math.max(18, math.min(baseCount + 10, 20))
	end
	if mode == "Daily" then
		return math.max(20, math.min(baseCount + 12, 22))
	end
	if mode == "OneLife" then
		return math.max(8, math.min(baseCount + 2, 11))
	end
	return math.max(8, math.min(baseCount + 2, 10))
end

local function getLengthRange(baseDefinition, mode)
	if mode == "Mega" or mode == "Daily" then
		return 3, 32
	end

	local minLength = math.huge
	local maxLength = 0

	for _, word in ipairs(baseDefinition.words or {}) do
		local normalized = normalizeWord(word)
		if normalized then
			local length = #normalized
			minLength = math.min(minLength, length)
			maxLength = math.max(maxLength, length)
		end
	end

	if maxLength <= 0 then
		return 3, 8
	end

	return math.max(3, minLength - 1), math.max(minLength, maxLength + 1)
end

local function getDifficultySources(level, mode)
	if mode == "Mega" or mode == "Daily" then
		return {
			WordBank.BabyEasy,
			WordBank.Easy,
			WordBank.Medium,
			WordBank.Hard,
		}
	end

	level = math.max(1, math.floor(tonumber(level) or 1))
	if level <= 120 then
		return {
			WordBank.BabyEasy,
			WordBank.Easy,
		}
	end
	if level <= 300 then
		return {
			WordBank.Easy,
			WordBank.Medium,
		}
	end

	return {
		WordBank.Medium,
		WordBank.Hard,
	}
end

local function appendWords(target, seen, sourceWords, targetCount, minLength, maxLength, allowOverlap)
	for _, candidate in ipairs(sourceWords or {}) do
		local normalized = normalizeWord(candidate)
		if normalized
			and not seen[normalized]
			and (not minLength or #normalized >= minLength)
			and (not maxLength or #normalized <= maxLength)
			and (allowOverlap or not wordsOverlap(normalized, target)) then
			seen[normalized] = true
			table.insert(target, normalized)
			if #target >= targetCount then
				return true
			end
		end
	end

	return false
end

local function appendThemeNeighbors(target, seen, library, startIndex, targetCount, minLength, maxLength, allowOverlap)
	if type(library) ~= "table" or #library == 0 then
		return false
	end

	if appendWords(target, seen, library[startIndex] and library[startIndex].words or nil, targetCount, minLength, maxLength, allowOverlap) then
		return true
	end

	for offset = 1, #library - 1 do
		local nextIndex = ((startIndex - 1 + offset) % #library) + 1
		if appendWords(target, seen, library[nextIndex] and library[nextIndex].words or nil, targetCount, minLength, maxLength, allowOverlap) then
			return true
		end
	end

	return false
end

local function buildThemedWordList(level, seed, baseDefinition, themeEntry)
	local themeWords = type(themeEntry and themeEntry.words) == "table" and themeEntry.words or {}
	if #themeWords == 0 then
		return cloneArray(baseDefinition.words or {})
	end

	local randomObject = Random.new(
		(math.max(1, math.floor(tonumber(seed) or 1)) * 1361)
		+ (math.max(1, math.floor(tonumber(level) or 1)) * 887)
		+ ((MODE_THEME_OFFSETS.Themed or 0) * 41)
	)
	local orderedThemeWords = shuffle(themeWords, randomObject)
	local targetCount = math.max(1, math.min(getTargetWordCount("Themed", baseDefinition), #orderedThemeWords))
	local words = {}
	local seen = {}

	appendWords(words, seen, orderedThemeWords, targetCount, nil, nil, false)

	if #words < targetCount then
		appendWords(words, seen, orderedThemeWords, targetCount, nil, nil, true)
	end

	if #words == 0 then
		return cloneArray(baseDefinition.words or {})
	end

	return words
end

local function buildWordList(mode, level, seed, baseDefinition, themeEntry, themeIndex, themeLibrary)
	if mode == "Themed" then
		return buildThemedWordList(level, seed, baseDefinition, themeEntry)
	end

	local words = {}
	local seen = {}
	local targetCount = getTargetWordCount(mode, baseDefinition)
	local minLength, maxLength = getLengthRange(baseDefinition, mode)
	local difficultySources = getDifficultySources(level, mode)

	appendThemeNeighbors(words, seen, themeLibrary, themeIndex, targetCount, minLength, maxLength, false)

	for _, pool in ipairs(difficultySources) do
		if appendWords(words, seen, pool, targetCount, minLength, maxLength, false) then
			break
		end
	end

	if #words < targetCount then
		appendThemeNeighbors(words, seen, themeLibrary, themeIndex, targetCount, nil, nil, false)
	end

	if #words < targetCount then
		for _, pool in ipairs(difficultySources) do
			if appendWords(words, seen, pool, targetCount, nil, nil, false) then
				break
			end
		end
	end

	if #words < targetCount then
		appendWords(words, seen, baseDefinition.words, targetCount, nil, nil, false)
	end

	if #words < targetCount and themeEntry then
		appendWords(words, seen, themeEntry.words, targetCount, nil, nil, true)
	end

	if #words < targetCount then
		for _, pool in ipairs({
			WordBank.BabyEasy,
			WordBank.Easy,
			WordBank.Medium,
			WordBank.Hard,
		}) do
			if appendWords(words, seen, pool, targetCount, nil, nil, true) then
				break
			end
		end
	end

	local randomObject = Random.new(
		(math.max(1, math.floor(tonumber(seed) or 1)) * 1223)
		+ (math.max(1, math.floor(tonumber(level) or 1)) * 619)
		+ ((MODE_THEME_OFFSETS[mode] or 0) * 29)
	)
	return shuffle(words, randomObject)
end

local function getGridSize(mode, baseDefinition, themeEntry)
	if mode == "Themed" then
		local baseGridSize = math.max(5, math.floor(tonumber(baseDefinition.gridSize) or 5))
		local themeGridSize = math.max(baseGridSize, math.floor(tonumber(themeEntry and themeEntry.gridSize) or baseGridSize))
		return math.max(baseGridSize, themeGridSize)
	end
	if mode == "Mega" then
		return LARGE_MODE_GRID_SIZE
	end
	if mode == "Daily" then
		return LARGE_MODE_GRID_SIZE
	end

	local baseGridSize = math.max(5, math.floor(tonumber(baseDefinition.gridSize) or 5))
	local themeGridSize = math.max(baseGridSize, math.floor(tonumber(themeEntry and themeEntry.gridSize) or baseGridSize))
	local maxBonus = 2
	return math.max(baseGridSize, math.min(themeGridSize, baseGridSize + maxBonus))
end

local function applyModeDirections(mode, baseDirections)
	local directions = normalizeDirectionsForMode(baseDirections, mode == "Backwards")

	if mode == "OneLife" or mode == "Mega" or mode == "Daily" then
		return { "E", "S", "SE", "SW", "W", "N", "NW", "NE" }
	end

	return directions
end

function DefinitionBuilder.BuildDefinition(level, mode, seed)
	local baseTemplate = getClassicTemplate(level)
	if not baseTemplate then
		return nil
	end

	local baseDefinition = cloneDefinition(baseTemplate)
	mode = type(mode) == "string" and mode or "Classic"

	if mode == "Classic" then
		return baseDefinition
	end

	local themeEntry, themeIndex, themeLibrary = chooseThemeEntry(mode, level, seed)
	if not themeEntry then
		baseDefinition.directions = applyModeDirections(mode, baseDefinition.directions)
		if mode == "Mega" then
			baseDefinition.gridSize = LARGE_MODE_GRID_SIZE
			baseDefinition.maxGridSize = LARGE_MODE_GRID_SIZE
		elseif mode == "Daily" then
			baseDefinition.gridSize = LARGE_MODE_GRID_SIZE
			baseDefinition.maxGridSize = LARGE_MODE_GRID_SIZE
		end
		return baseDefinition
	end

	local prefix = MODE_TITLE_PREFIX[mode]
	local title = themeEntry.title or baseDefinition.title
	if mode ~= "Themed" then
		title = prefix and string.format("%s: %s", prefix, themeEntry.title) or string.format("%s: %s", mode, themeEntry.title)
	end
	local definition = {
		level = baseDefinition.level,
		title = title,
		subtitle = themeEntry.subtitle or baseDefinition.subtitle,
		gridSize = getGridSize(mode, baseDefinition, themeEntry),
		maxGridSize = (mode == "Daily" or mode == "Mega") and getGridSize(mode, baseDefinition, themeEntry) or nil,
		words = buildWordList(mode, level, seed, baseDefinition, themeEntry, themeIndex, themeLibrary),
		directions = applyModeDirections(mode, baseDefinition.directions),
		seed = math.max(1, math.floor(tonumber(seed) or baseDefinition.seed or 1)),
	}

	return definition
end

return DefinitionBuilder
