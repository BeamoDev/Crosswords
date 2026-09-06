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

local function createGrid(height, width)
	local grid = {}

	for row = 1, height do
		grid[row] = {}
		for column = 1, width do
			grid[row][column] = nil
		end
	end

	return grid
end

local function canPlaceWord(grid, height, width, word, startRow, startColumn, directionRow, directionColumn)
	local path = {}

	for index = 1, #word do
		local row = startRow + directionRow * (index - 1)
		local column = startColumn + directionColumn * (index - 1)

		if row < 1 or row > height or column < 1 or column > width then
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

local function fillGrid(grid, height, width, randomObject)
	for row = 1, height do
		for column = 1, width do
			if grid[row][column] == nil then
				local letterIndex = randomObject:NextInteger(1, #ALPHABET)
				grid[row][column] = string.sub(ALPHABET, letterIndex, letterIndex)
			end
		end
	end
end

local function tryGenerate(words, height, width, randomObject, directions)
	local grid = createGrid(height, width)
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
			-- Visit only starts that fit this word, in a seeded order. This avoids
			-- wasting attempts beyond an edge on compact or densely filled boards.
			local dr, dc = direction[1] * (#word - 1), direction[2] * (#word - 1)
			local minRow, maxRow = 1 - math.min(0, dr), height - math.max(0, dr)
			local minColumn, maxColumn = 1 - math.min(0, dc), width - math.max(0, dc)
			local columns = maxColumn - minColumn + 1
			local starts = math.max(0, maxRow - minRow + 1) * math.max(0, columns)
			local offset = starts > 0 and randomObject:NextInteger(0, starts - 1) or 0
			for index = 0, starts - 1 do
				local cell = (index + offset) % starts
				local row = minRow + math.floor(cell / columns)
				local column = minColumn + cell % columns
				local path = canPlaceWord(grid, height, width, word, row, column, direction[1], direction[2])

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

	fillGrid(grid, height, width, randomObject)

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
	local baseGridWidth = definition.gridWidth or baseGridSize
	local maxGridSize = tonumber(definition.maxGridSize)
	if maxGridSize ~= nil then
		maxGridSize = math.max(5, math.floor(maxGridSize))
	end
	local chosenSeed = seed or definition.seed or math.max(1, DateTime.now().UnixTimestampMillis % 2147483647)
	local maxExpansion = maxGridSize and math.max(0, maxGridSize - baseGridSize) or 4

	for expansion = 0, maxExpansion do
		local size = baseGridSize + expansion
		local width = baseGridWidth + expansion

		for attempt = 0, 11 do
			local randomObject = RandomClass.new(chosenSeed + expansion * 7919 + attempt * 193)
			local generated = tryGenerate(words, size, width, randomObject, directions)

			if generated then
				return {
					level = definition.level,
					title = definition.title or "Word Search",
					subtitle = definition.subtitle or "",
					seed = chosenSeed,
					gridSize = size,
					gridWidth = width,
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


-- Every public mode has explicit settings; unknown and retired modes never fall back.
local Catalog
if script then
	Catalog = require(script.Parent.Parent:WaitForChild("content"):WaitForChild("PuzzleCatalog"))
else
	Catalog = require("../content/PuzzleCatalog")
end
local MODE_SETTINGS = {
	Standard = { size = 12, count = 10, maxCount = 12, minLength = 3, maxLength = 10, directions = { "E", "S", "SE", "SW" } },
	Mini = { size = 6, count = 5, minLength = 3, maxLength = 5, directions = { "E", "S" } },
	Jumbo = { size = 16, count = 20, minLength = 3, maxLength = 14, directions = DEFAULT_DIRECTIONS },
	Hardcore = { size = 12, count = 12, minLength = 5, maxLength = 11, directions = DEFAULT_DIRECTIONS },
	Duel = { size = 11, count = 10, minLength = 3, maxLength = 10, directions = { "E", "S", "SE", "SW" } },
	Timed = { size = 12, count = 10, minLength = 3, maxLength = 10, directions = DEFAULT_DIRECTIONS },
}

function PuzzleGenerator.BuildTutorialDefinition(seed)
	return { level = 1, title = "Animals", gridSize = 4, maxGridSize = 4,
		words = { "CAT", "DOG" }, directions = { "E" }, seed = seed }
end

local function buildFromSettings(level, settings, themes, seed)
	local randomObject = RandomClass.new(seed or 1)
	local count = settings.maxCount and randomObject:NextInteger(settings.count, settings.maxCount) or settings.count
	local candidates = {}
	for _, theme in ipairs(themes) do
		local words, seen = {}, {}
		for _, raw in ipairs(theme.words) do
			local word = string.upper(raw:gsub("%s+", ""))
			if #word >= settings.minLength and #word <= settings.maxLength and not seen[word] then
				seen[word] = true
				table.insert(words, word)
			end
		end
		if #words >= count then table.insert(candidates, { title = theme.title, words = words }) end
	end
	assert(#candidates > 0, "No word pool fits this difficulty")
	local selected = candidates[randomObject:NextInteger(1, #candidates)]
	for i = #selected.words, 2, -1 do
		local j = randomObject:NextInteger(1, i)
		selected.words[i], selected.words[j] = selected.words[j], selected.words[i]
	end
	local words = {}
	for i = 1, count do words[i] = selected.words[i] end
	local width = settings.rectangularWidth or settings.size
	return { level = level, title = selected.title, gridSize = settings.size, gridWidth = width, maxGridSize = settings.size,
		words = words, directions = table.clone(settings.directions), seed = seed }
end

function PuzzleGenerator.BuildDefinition(level, mode, seed)
	local settings = assert(MODE_SETTINGS[mode], "Unsupported puzzle mode: " .. tostring(mode))
	return buildFromSettings(level, settings, Catalog.GetThemes(), seed)
end

PuzzleGenerator.BeginnerSolves = 10
local BEGINNER_CLASSIC = { size = 9, count = 7, minLength = 3, maxLength = 6,
	directions = { "E", "S", "SE" } }
function PuzzleGenerator.BuildClassicDefinition(_members, seed, beginnerSolves)
	if type(beginnerSolves) == "number" and beginnerSolves < PuzzleGenerator.BeginnerSolves then
		return buildFromSettings(1, BEGINNER_CLASSIC, Catalog.BeginnerThemes, seed)
	end
	return PuzzleGenerator.BuildDefinition(1, "Standard", seed)
end

PuzzleGenerator.Generate = PuzzleGenerator.generate
return PuzzleGenerator
