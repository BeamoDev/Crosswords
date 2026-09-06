local PuzzleGenerator = {}
local RandomClass = Random

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local DIRECTION_LOOKUP = {
	N = { -1, 0 },
	NE = { -1, 1 },
	E = { 0, 1 },
	SE = { 1, 1 },
	S = { 1, 0 },
	SW = { 1, -1 },
	W = { 0, -1 },
	NW = { -1, -1 },
}

local DEFAULT_DIRECTIONS = {
	DIRECTION_LOOKUP.N,
	DIRECTION_LOOKUP.NE,
	DIRECTION_LOOKUP.E,
	DIRECTION_LOOKUP.SE,
	DIRECTION_LOOKUP.S,
	DIRECTION_LOOKUP.SW,
	DIRECTION_LOOKUP.W,
	DIRECTION_LOOKUP.NW,
}

local function directionKey(direction)
	return string.format("%d:%d", direction[1], direction[2])
end

local function sanitizeWords(definition)
	local words = {}

	for _, word in ipairs(definition.words or {}) do
		local cleaned = string.upper((word:gsub("%s+", "")))
		if cleaned ~= "" then
			table.insert(words, cleaned)
		end
	end

	return words
end

local function resolveDirections(definition)
	if not definition.directions or #definition.directions == 0 then
		return DEFAULT_DIRECTIONS
	end

	local resolvedDirections = {}

	for _, direction in ipairs(definition.directions) do
		local resolvedDirection = direction
		if type(direction) == "string" then
			resolvedDirection = DIRECTION_LOOKUP[direction]
		end

		if resolvedDirection then
			table.insert(resolvedDirections, resolvedDirection)
		end
	end

	assert(#resolvedDirections > 0, "PuzzleGenerator.generate requires at least one valid direction.")
	return resolvedDirections
end

local function shuffledDirections(directions, randomObject)
	local orderedDirections = table.clone(directions)

	for index = #orderedDirections, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		orderedDirections[index], orderedDirections[swapIndex] = orderedDirections[swapIndex], orderedDirections[index]
	end

	return orderedDirections
end

local function countUniqueDirections(directionCounts)
	local uniqueCount = 0

	for _, count in pairs(directionCounts) do
		if count > 0 then
			uniqueCount += 1
		end
	end

	return uniqueCount
end

local function maxDirectionCount(directionCounts)
	local highest = 0

	for _, count in pairs(directionCounts) do
		highest = math.max(highest, count)
	end

	return highest
end

local function anyDirectionMatches(directions, predicate)
	for _, direction in ipairs(directions) do
		if predicate(direction) then
			return true
		end
	end

	return false
end

local function countPlacedWordsMatching(placedWords, predicate)
	local count = 0

	for _, wordData in ipairs(placedWords) do
		if predicate(wordData.direction) then
			count += 1
		end
	end

	return count
end

local function calculateGridSize(words)
	local longestWord = 0
	local totalLetters = 0

	for _, word in ipairs(words) do
		longestWord = math.max(longestWord, #word)
		totalLetters += #word
	end

	local densitySize = math.ceil(math.sqrt(totalLetters * 1.9))
	return math.clamp(math.max(longestWord + 1, densitySize), 8, 14)
end

local function createGrid(size)
	local grid = {}

	for row = 1, size do
		grid[row] = {}
		for column = 1, size do
			grid[row][column] = nil
		end
	end

	return grid
end

local function canPlaceWord(grid, size, word, startRow, startColumn, directionRow, directionColumn)
	local path = {}

	for index = 1, #word do
		local row = startRow + directionRow * (index - 1)
		local column = startColumn + directionColumn * (index - 1)

		if row < 1 or row > size or column < 1 or column > size then
			return nil
		end

		local expectedLetter = string.sub(word, index, index)
		local currentLetter = grid[row][column]

		if currentLetter ~= nil and currentLetter ~= expectedLetter then
			return nil
		end

		path[index] = {
			row = row,
			column = column,
		}
	end

	return path
end

local function placeWord(grid, word, path)
	for index, point in ipairs(path) do
		grid[point.row][point.column] = string.sub(word, index, index)
	end
end

local function fillGrid(grid, size, randomObject)
	for row = 1, size do
		for column = 1, size do
			if grid[row][column] == nil then
				local letterIndex = randomObject:NextInteger(1, #ALPHABET)
				grid[row][column] = string.sub(ALPHABET, letterIndex, letterIndex)
			end
		end
	end
end

local function tryGenerate(words, size, randomObject, directions)
	local grid = createGrid(size)
	local placedWords = {}
	local sortedWords = table.clone(words)
	local directionCounts = {}

	table.sort(sortedWords, function(left, right)
		return #left > #right
	end)

	for _, word in ipairs(sortedWords) do
		local placed = false
		local orderedDirections = shuffledDirections(directions, randomObject)

		table.sort(orderedDirections, function(left, right)
			return (directionCounts[directionKey(left)] or 0) < (directionCounts[directionKey(right)] or 0)
		end)

		for _, direction in ipairs(orderedDirections) do
			for _ = 1, 48 do
				local row = randomObject:NextInteger(1, size)
				local column = randomObject:NextInteger(1, size)
				local path = canPlaceWord(grid, size, word, row, column, direction[1], direction[2])

				if path then
					placeWord(grid, word, path)

					local key = directionKey(direction)
					directionCounts[key] = (directionCounts[key] or 0) + 1

					table.insert(placedWords, {
						word = word,
						startRow = path[1].row,
						startColumn = path[1].column,
						endRow = path[#path].row,
						endColumn = path[#path].column,
						path = path,
						direction = direction,
						directionKey = key,
					})

					placed = true
					break
				end
			end

			if placed then
				break
			end
		end

		if not placed then
			return nil
		end
	end

	if #directions > 1 then
		local uniqueDirections = countUniqueDirections(directionCounts)
		local desiredUniqueDirections = math.min(#directions, math.min(#sortedWords, math.max(2, math.floor(#sortedWords / 3) + 1)))
		local dominantDirectionCount = maxDirectionCount(directionCounts)
		local supportsNonHorizontal = anyDirectionMatches(directions, function(direction)
			return direction[1] ~= 0
		end)
		local supportsDiagonal = anyDirectionMatches(directions, function(direction)
			return direction[1] ~= 0 and direction[2] ~= 0
		end)
		local placedNonHorizontal = countPlacedWordsMatching(placedWords, function(direction)
			return direction[1] ~= 0
		end)
		local placedDiagonal = countPlacedWordsMatching(placedWords, function(direction)
			return direction[1] ~= 0 and direction[2] ~= 0
		end)

		if uniqueDirections < desiredUniqueDirections then
			return nil
		end

		if supportsNonHorizontal and #sortedWords >= 2 and placedNonHorizontal == 0 then
			return nil
		end

		if supportsDiagonal and #sortedWords >= 3 and placedDiagonal == 0 then
			return nil
		end

		if #sortedWords >= 4 and #directions >= 3 and dominantDirectionCount > math.ceil(#sortedWords * 0.5) then
			return nil
		end
	end

	fillGrid(grid, size, randomObject)

	local placedWordsByWord = {}
	for _, wordData in ipairs(placedWords) do
		placedWordsByWord[wordData.word] = wordData
	end

	return {
		grid = grid,
		placedWords = placedWords,
		placedWordsByWord = placedWordsByWord,
	}
end

function PuzzleGenerator.generate(definition, seed)
	local words = sanitizeWords(definition)
	local directions = resolveDirections(definition)
	assert(#words > 0, "PuzzleGenerator.generate requires at least one word.")

	local baseGridSize = definition.gridSize or calculateGridSize(words)
	local maxGridSize = tonumber(definition.maxGridSize)
	if maxGridSize ~= nil then
		maxGridSize = math.max(5, math.floor(maxGridSize))
	end
	local chosenSeed = seed or definition.seed or math.max(1, DateTime.now().UnixTimestampMillis % 2147483647)
	local maxExpansion = maxGridSize and math.max(0, maxGridSize - baseGridSize) or 4

	for expansion = 0, maxExpansion do
		local size = baseGridSize + expansion

		for attempt = 0, 11 do
			local randomObject = RandomClass.new(chosenSeed + expansion * 7919 + attempt * 193)
			local generated = tryGenerate(words, size, randomObject, directions)

			if generated then
				return {
					level = definition.level,
					title = definition.title or "Word Search",
					subtitle = definition.subtitle or "",
					seed = chosenSeed,
					gridSize = size,
					words = words,
					letters = generated.grid,
					placedWords = generated.placedWords,
					placedWordsByWord = generated.placedWordsByWord,
				}
			end
		end
	end

	error(string.format("Unable to build puzzle '%s'.", definition.title or "Word Search"))
end


-- Mode-aware puzzle definitions.
local DefinitionBuilder = {}

local Levels
local WordBank
if script then
	local sharedFolder = script.Parent.Parent
	local contentFolder = sharedFolder:WaitForChild("content")
	Levels = require(contentFolder:WaitForChild("PuzzleCatalog"))
	WordBank = require(contentFolder:WaitForChild("WordBank"))
else
	Levels = require("../content/PuzzleCatalog")
	WordBank = require("../content/WordBank")
end
local PuzzleLibrary = Levels.ModeLibraries
local ThemedModeLibrary = Levels.Themes

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

	local randomObject = RandomClass.new(
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

	local randomObject = RandomClass.new(
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

	local randomObject = RandomClass.new(
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


PuzzleGenerator.Generate = PuzzleGenerator.generate
PuzzleGenerator.BuildDefinition = DefinitionBuilder.BuildDefinition
return PuzzleGenerator
