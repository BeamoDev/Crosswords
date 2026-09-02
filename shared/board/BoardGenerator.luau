local BoardGenerator = {}

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

	assert(#resolvedDirections > 0, "BoardGenerator.generate requires at least one valid direction.")
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

local function resolveGridDimensions(definition, words)
	local fallbackSize = calculateGridSize(words)
	local baseWidth = math.max(5, math.floor(tonumber(definition.gridWidth or definition.gridSize) or fallbackSize))
	local baseHeight = math.max(5, math.floor(tonumber(definition.gridHeight or definition.gridSize) or fallbackSize))
	local maxGridWidth = tonumber(definition.maxGridWidth or definition.maxGridSize)
	local maxGridHeight = tonumber(definition.maxGridHeight or definition.maxGridSize)

	if maxGridWidth ~= nil then
		maxGridWidth = math.max(baseWidth, math.floor(maxGridWidth))
	end
	if maxGridHeight ~= nil then
		maxGridHeight = math.max(baseHeight, math.floor(maxGridHeight))
	end

	return baseWidth, baseHeight, maxGridWidth, maxGridHeight
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
			for _ = 1, 48 do
				local row = randomObject:NextInteger(1, height)
				local column = randomObject:NextInteger(1, width)
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

function BoardGenerator.generate(definition, seed)
	local words = sanitizeWords(definition)
	local directions = resolveDirections(definition)
	assert(#words > 0, "BoardGenerator.generate requires at least one word.")

	local baseGridWidth, baseGridHeight, maxGridWidth, maxGridHeight = resolveGridDimensions(definition, words)
	local chosenSeed = seed or definition.seed or math.max(1, DateTime.now().UnixTimestampMillis % 2147483647)
	local maxWidthExpansion = maxGridWidth and math.max(0, maxGridWidth - baseGridWidth) or 4
	local maxHeightExpansion = maxGridHeight and math.max(0, maxGridHeight - baseGridHeight) or 4
	local maxExpansion = math.max(maxWidthExpansion, maxHeightExpansion)

	for expansion = 0, maxExpansion do
		local width = baseGridWidth + math.min(expansion, maxWidthExpansion)
		local height = baseGridHeight + math.min(expansion, maxHeightExpansion)

		for attempt = 0, 11 do
			local randomObject = Random.new(chosenSeed + expansion * 7919 + attempt * 193)
			local generated = tryGenerate(words, height, width, randomObject, directions)

			if generated then
				return {
					level = definition.level,
					title = definition.title or "Word Search",
					subtitle = definition.subtitle or "",
					seed = chosenSeed,
					gridSize = math.max(width, height),
					gridWidth = width,
					gridHeight = height,
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

return BoardGenerator
