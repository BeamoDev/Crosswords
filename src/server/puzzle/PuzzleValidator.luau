local PuzzleValidator = {}

local GameConfig
if game then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
	local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
	GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
else
	GameConfig = require("../../shared/config/GameConfig")
end

local MAX_SEED = 2147483646
local HASH_MODULUS = 2147483647
local MIN_GRID_DIMENSION = 4
local MIN_WORD_LENGTH = 3
local MAX_TIME_LIMIT_SECONDS = 60 * 60

local DIRECTION_STEPS = {
	N = { row = -1, column = 0 },
	NE = { row = -1, column = 1 },
	E = { row = 0, column = 1 },
	SE = { row = 1, column = 1 },
	S = { row = 1, column = 0 },
	SW = { row = 1, column = -1 },
	W = { row = 0, column = -1 },
	NW = { row = -1, column = -1 },
}

local DIRECTION_NAMES = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local DIRECTIONS_BY_DIFFICULTY = {
	Easy = { "E", "S" },
	Medium = { "E", "S", "SE", "SW" },
	Hard = { "E", "S", "SE", "SW", "W", "N" },
	Expert = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" },
}

local VALID_KINDS = {
	Authored = true,
	Generated = true,
}

local function fail(message)
	return false, tostring(message)
end

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isInteger(value)
	return isFiniteNumber(value) and value % 1 == 0
end

local function isNonEmptyString(value)
	return type(value) == "string" and value ~= "" and value:match("^%s*$") == nil
end

local function isStableId(value)
	return type(value) == "string"
		and value ~= ""
		and value:match("^[a-z0-9]") ~= nil
		and value:match("[^a-z0-9_/%-%.:]") == nil
end

local function getDenseArrayLength(value)
	if type(value) ~= "table" then
		return nil
	end

	local length = #value
	local keyCount = 0
	for key in pairs(value) do
		if type(key) ~= "number" or not isInteger(key) or key < 1 or key > length then
			return nil
		end
		keyCount += 1
	end

	if keyCount ~= length then
		return nil
	end

	return length
end

local function normalizeWord(word)
	if type(word) ~= "string" then
		return nil
	end

	if word == "" or word:match("^[A-Z]+$") == nil then
		return nil
	end

	return word
end

local function directionNameFromStep(rowStep, columnStep)
	for name, step in pairs(DIRECTION_STEPS) do
		if step.row == rowStep and step.column == columnStep then
			return name
		end
	end

	return nil
end

local function directionNameFromPath(path)
	local length = getDenseArrayLength(path)
	if not length or length < 2 then
		return nil
	end

	local first = path[1]
	local second = path[2]
	if type(first) ~= "table"
		or type(second) ~= "table"
		or not isInteger(first.row)
		or not isInteger(first.column)
		or not isInteger(second.row)
		or not isInteger(second.column)
	then
		return nil
	end

	local rowStep = second.row - first.row
	local columnStep = second.column - first.column
	local directionName = directionNameFromStep(rowStep, columnStep)
	if not directionName then
		return nil
	end

	for index = 2, length do
		local previous = path[index - 1]
		local point = path[index]
		if type(previous) ~= "table"
			or type(point) ~= "table"
			or not isInteger(previous.row)
			or not isInteger(previous.column)
			or not isInteger(point.row)
			or not isInteger(point.column)
		then
			return nil
		end
		if point.row - previous.row ~= rowStep or point.column - previous.column ~= columnStep then
			return nil
		end
	end

	return directionName
end

local function pathKey(path)
	local length = getDenseArrayLength(path)
	if not length then
		return nil
	end
	local parts = {}
	for index = 1, length do
		local point = path[index]
		if type(point) ~= "table" or not isInteger(point.row) or not isInteger(point.column) then
			return nil
		end
		parts[index] = string.format("%d:%d", point.row, point.column)
	end
	return table.concat(parts, "|")
end

local function undirectedPathKey(path)
	local forward = pathKey(path)
	if not forward then
		return nil
	end
	local reverseParts = {}
	for index = #path, 1, -1 do
		local point = path[index]
		table.insert(reverseParts, string.format("%d:%d", point.row, point.column))
	end
	local reverse = table.concat(reverseParts, "|")
	return forward < reverse and forward or reverse
end

local function copyPath(path)
	local result = {}
	for index, point in ipairs(path or {}) do
		result[index] = {
			row = point.row,
			column = point.column,
		}
	end
	return result
end

local function rowsFromLetters(letters, width, height)
	if getDenseArrayLength(letters) ~= height then
		return nil, "letters must contain exactly height rows"
	end

	local rows = {}
	for row = 1, height do
		if getDenseArrayLength(letters[row]) ~= width then
			return nil, string.format("letters row %d must contain exactly width cells", row)
		end

		local characters = {}
		for column = 1, width do
			local letter = letters[row][column]
			if type(letter) ~= "string" or #letter ~= 1 or letter:match("^[A-Z]$") == nil then
				return nil, string.format("letters[%d][%d] must be one uppercase A-Z character", row, column)
			end
			characters[column] = letter
		end
		rows[row] = table.concat(characters)
	end

	return rows
end

local function validateRows(rows, width, height, fieldName)
	if getDenseArrayLength(rows) ~= height then
		return nil, string.format("%s must contain exactly %d rows", fieldName, height)
	end

	local copy = {}
	for row = 1, height do
		local value = rows[row]
		if type(value) ~= "string" or #value ~= width or value:match("^[A-Z]+$") == nil then
			return nil, string.format("%s row %d must contain exactly %d uppercase A-Z characters", fieldName, row, width)
		end
		copy[row] = value
	end

	return copy
end

local function wordFitsDirection(wordLength, width, height, directionName)
	local step = DIRECTION_STEPS[directionName]
	if not step then
		return false
	end

	if step.row == 0 then
		return wordLength <= width
	end
	if step.column == 0 then
		return wordLength <= height
	end

	return wordLength <= math.min(width, height)
end

local function validateDirectionList(directions, difficulty)
	local length = getDenseArrayLength(directions)
	if not length or length == 0 then
		return nil, "directions must be a non-empty dense array"
	end

	local expected = DIRECTIONS_BY_DIFFICULTY[difficulty]
	if not expected then
		return nil, "difficulty must be Easy, Medium, Hard, or Expert"
	end

	local actualSet = {}
	for index, directionName in ipairs(directions) do
		if type(directionName) ~= "string" or not DIRECTION_STEPS[directionName] then
			return nil, string.format("directions[%d] is not a supported direction", index)
		end
		if actualSet[directionName] then
			return nil, string.format("direction %s is duplicated", directionName)
		end
		actualSet[directionName] = true
	end

	if length ~= #expected then
		return nil, string.format("%s definitions must use the catalog direction profile", difficulty)
	end
	for _, directionName in ipairs(expected) do
		if not actualSet[directionName] then
			return nil, string.format("%s definitions must include direction %s", difficulty, directionName)
		end
	end

	return actualSet
end

local function validateWords(words, width, height, directions)
	local length = getDenseArrayLength(words)
	if not length or length == 0 then
		return nil, "words must be a non-empty dense array"
	end
	if length > GameConfig.Gameplay.MaxWords then
		return nil, string.format("word count exceeds GameConfig.Gameplay.MaxWords (%d)", GameConfig.Gameplay.MaxWords)
	end

	local directionSet = {}
	for _, directionName in ipairs(directions) do
		directionSet[directionName] = true
	end

	local seen = {}
	local copy = {}
	for index, rawWord in ipairs(words) do
		local word = normalizeWord(rawWord)
		if not word then
			return nil, string.format("words[%d] must contain uppercase A-Z characters only", index)
		end
		if #word < MIN_WORD_LENGTH or #word > GameConfig.Gameplay.MaxWordLength then
			return nil, string.format("word %s has an unsupported length", word)
		end
		if seen[word] then
			return nil, string.format("word %s is duplicated", word)
		end
		seen[word] = true

		local fits = false
		for directionName in pairs(directionSet) do
			if wordFitsDirection(#word, width, height, directionName) then
				fits = true
				break
			end
		end
		if not fits then
			return nil, string.format("word %s cannot fit this grid in any allowed direction", word)
		end

		copy[index] = word
	end

	return copy, seen
end

local function validatePath(path, word, rows, width, height, allowedDirections, label)
	if getDenseArrayLength(path) ~= #word then
		return nil, string.format("%s path length must equal the word length", label)
	end

	for index, point in ipairs(path) do
		if type(point) ~= "table"
			or not isInteger(point.row)
			or not isInteger(point.column)
			or point.row < 1
			or point.row > height
			or point.column < 1
			or point.column > width then
			return nil, string.format("%s path point %d is outside the grid or malformed", label, index)
		end
	end

	local directionName = directionNameFromPath(path)
	if not directionName or not allowedDirections[directionName] then
		return nil, string.format("%s path is not straight, contiguous, and allowed", label)
	end

	local letters = {}
	for index, point in ipairs(path) do
		letters[index] = string.sub(rows[point.row], point.column, point.column)
	end
	if table.concat(letters) ~= word then
		return nil, string.format("%s path does not spell %s", label, word)
	end

	return directionName
end

local function findOccurrences(rows, width, height, word)
	local occurrences = {}
	local seenPhysicalPaths = {}

	for row = 1, height do
		for column = 1, width do
			if string.sub(rows[row], column, column) == string.sub(word, 1, 1) then
				for _, directionName in ipairs(DIRECTION_NAMES) do
					local step = DIRECTION_STEPS[directionName]
					local endRow = row + step.row * (#word - 1)
					local endColumn = column + step.column * (#word - 1)
					if endRow >= 1 and endRow <= height and endColumn >= 1 and endColumn <= width then
						local path = {}
						local matches = true
						for index = 1, #word do
							local currentRow = row + step.row * (index - 1)
							local currentColumn = column + step.column * (index - 1)
							if string.sub(rows[currentRow], currentColumn, currentColumn) ~= string.sub(word, index, index) then
								matches = false
								break
							end
							path[index] = {
								row = currentRow,
								column = currentColumn,
							}
						end
						if matches then
							local physicalKey = undirectedPathKey(path)
							if physicalKey and not seenPhysicalPaths[physicalKey] then
								seenPhysicalPaths[physicalKey] = true
								table.insert(occurrences, path)
							end
						end
					end
				end
			end
		end
	end

	return occurrences
end

local function validateUniqueOccurrences(rows, width, height, targets)
	for _, target in ipairs(targets) do
		local occurrences = findOccurrences(rows, width, height, target.word)
		if #occurrences ~= 1 then
			return false, string.format("word %s must occur exactly once in the compiled grid (found %d)", target.word, #occurrences)
		end
		if undirectedPathKey(occurrences[1]) ~= undirectedPathKey(target.path) then
			return false, string.format("word %s canonical path does not match its grid occurrence", target.word)
		end
	end

	return true
end

local function validateDirectionCoverage(targets, difficulty)
	local targetCount = #targets
	local uniqueDirections = {}
	local uniqueCount = 0
	local hasDiagonal = false
	local hasHardReverse = false
	local hasExpertReverse = false

	for _, target in ipairs(targets) do
		local directionName = target.direction or directionNameFromPath(target.path)
		local step = directionName and DIRECTION_STEPS[directionName] or nil
		if directionName and not uniqueDirections[directionName] then
			uniqueDirections[directionName] = true
			uniqueCount += 1
		end
		if step and step.row ~= 0 and step.column ~= 0 then
			hasDiagonal = true
		end
		if directionName == "N" or directionName == "W" then
			hasHardReverse = true
		end
		if directionName == "N" or directionName == "NE" or directionName == "W" or directionName == "NW" then
			hasExpertReverse = true
		end
	end

	if difficulty == "Medium" and targetCount >= 2 and not hasDiagonal then
		return false, "Medium puzzles must place at least one diagonal target"
	end
	if difficulty == "Hard" and targetCount >= 3 then
		if not hasDiagonal then
			return false, "Hard puzzles must place at least one diagonal target"
		end
		if not hasHardReverse then
			return false, "Hard puzzles must place at least one north- or west-facing target"
		end
	end
	if difficulty == "Expert" and targetCount >= 4 then
		if not hasDiagonal or not hasExpertReverse then
			return false, "Expert puzzles must include diagonal and reverse targets"
		end
		if uniqueCount < math.min(4, targetCount) then
			return false, "Expert puzzles must use at least four unique directions"
		end
	end

	return true
end

local function computeBoardHash(puzzle)
	if type(puzzle) ~= "table" or type(puzzle.rows) ~= "table" or type(puzzle.targets) ~= "table" then
		return nil
	end

	local parts = {
		tostring(puzzle.schemaVersion),
		tostring(puzzle.contentRevision),
		tostring(puzzle.generatorVersion),
		tostring(puzzle.id),
		tostring(puzzle.revision),
		tostring(puzzle.seed),
		tostring(puzzle.width),
		tostring(puzzle.height),
		table.concat(puzzle.rows, "/"),
	}
	for _, target in ipairs(puzzle.targets) do
		table.insert(parts, tostring(target.id))
		table.insert(parts, tostring(target.word))
		table.insert(parts, pathKey(target.path) or "")
	end

	local hash = 7
	local serialized = table.concat(parts, "|")
	for index = 1, #serialized do
		hash = ((hash * 131) + string.byte(serialized, index)) % HASH_MODULUS
	end
	return string.format("%08x", hash)
end

local function validateTargetList(targets, words, wordSet, rows, width, height, allowedDirections)
	if getDenseArrayLength(targets) ~= #words then
		return nil, "targets must contain exactly one entry for every word"
	end

	local targetIds = {}
	local targetedWords = {}
	local physicalPaths = {}
	local normalizedTargets = {}
	for index, target in ipairs(targets) do
		if type(target) ~= "table" then
			return nil, string.format("targets[%d] must be a table", index)
		end
		if not isStableId(target.id) then
			return nil, string.format("targets[%d].id must be a stable lowercase ID", index)
		end
		if targetIds[target.id] then
			return nil, string.format("target id %s is duplicated", target.id)
		end
		targetIds[target.id] = true

		local word = normalizeWord(target.word)
		if not word or not wordSet[word] then
			return nil, string.format("targets[%d].word is not declared in words", index)
		end
		if word ~= words[index] then
			return nil, string.format("targets[%d].word must match words[%d]", index, index)
		end
		if targetedWords[word] then
			return nil, string.format("word %s has more than one target", word)
		end
		targetedWords[word] = true

		local directionName, pathError = validatePath(
			target.path,
			word,
			rows,
			width,
			height,
			allowedDirections,
			string.format("target %s", target.id)
		)
		if not directionName then
			return nil, pathError
		end
		if target.direction ~= nil and target.direction ~= directionName then
			return nil, string.format("target %s direction does not match its path", target.id)
		end
		local physicalKey = undirectedPathKey(target.path)
		if not physicalKey then
			return nil, string.format("target %s path is malformed", target.id)
		end
		if physicalPaths[physicalKey] then
			return nil, string.format(
				"target %s shares a physical path with target %s",
				target.id,
				physicalPaths[physicalKey]
			)
		end
		physicalPaths[physicalKey] = target.id

		normalizedTargets[index] = {
			id = target.id,
			word = word,
			direction = directionName,
			path = copyPath(target.path),
		}
	end

	for _, word in ipairs(words) do
		if not targetedWords[word] then
			return nil, string.format("word %s has no target", word)
		end
	end

	return normalizedTargets
end

local function validateCommonDefinition(definition)
	if type(definition) ~= "table" then
		return nil, "definition must be a table"
	end
	if definition.schemaVersion ~= GameConfig.SchemaVersion then
		return nil, "definition schemaVersion does not match GameConfig.SchemaVersion"
	end
	if definition.contentRevision ~= GameConfig.ContentRevision then
		return nil, "definition contentRevision does not match GameConfig.ContentRevision"
	end
	if definition.generatorVersion ~= GameConfig.GeneratorVersion then
		return nil, "definition generatorVersion does not match GameConfig.GeneratorVersion"
	end
	if not isStableId(definition.id) then
		return nil, "definition.id must be a stable lowercase ID"
	end
	if not VALID_KINDS[definition.kind] then
		return nil, "definition.kind must be Authored or Generated"
	end
	if not isNonEmptyString(definition.chapterId) then
		return nil, "definition.chapterId must be a non-empty string"
	end
	if not isInteger(definition.order) or definition.order < 1 then
		return nil, "definition.order must be a positive integer"
	end
	if not isNonEmptyString(definition.title) then
		return nil, "definition.title must be a non-empty string"
	end
	if not isNonEmptyString(definition.description) then
		return nil, "definition.description must be a non-empty string"
	end
	if not DIRECTIONS_BY_DIFFICULTY[definition.difficulty] then
		return nil, "definition.difficulty must be Easy, Medium, Hard, or Expert"
	end
	if not isInteger(definition.revision) or definition.revision < 1 then
		return nil, "definition.revision must be a positive integer"
	end
	if not isInteger(definition.width) or definition.width < MIN_GRID_DIMENSION or definition.width > GameConfig.Gameplay.MaxGridWidth then
		return nil, string.format("definition.width must be between %d and %d", MIN_GRID_DIMENSION, GameConfig.Gameplay.MaxGridWidth)
	end
	if not isInteger(definition.height) or definition.height < MIN_GRID_DIMENSION or definition.height > GameConfig.Gameplay.MaxGridHeight then
		return nil, string.format("definition.height must be between %d and %d", MIN_GRID_DIMENSION, GameConfig.Gameplay.MaxGridHeight)
	end
	if not isInteger(definition.timeLimitSeconds) or definition.timeLimitSeconds < 1 or definition.timeLimitSeconds > MAX_TIME_LIMIT_SECONDS then
		return nil, "definition.timeLimitSeconds must be a positive integer no greater than one hour"
	end
	if not isInteger(definition.seed) or definition.seed < 1 or definition.seed > MAX_SEED then
		return nil, string.format("definition.seed must be an integer from 1 to %d", MAX_SEED)
	end

	local allowedDirections, directionError = validateDirectionList(definition.directions, definition.difficulty)
	if not allowedDirections then
		return nil, directionError
	end
	local words, wordSetOrError = validateWords(definition.words, definition.width, definition.height, definition.directions)
	if not words then
		return nil, wordSetOrError
	end

	return {
		allowedDirections = allowedDirections,
		words = words,
		wordSet = wordSetOrError,
	}
end

function PuzzleValidator.ValidateDefinition(definition)
	local common, commonError = validateCommonDefinition(definition)
	if not common then
		return fail(commonError)
	end

	if definition.kind == "Generated" then
		if definition.grid ~= nil or definition.rows ~= nil or definition.targets ~= nil then
			return fail("Generated definitions cannot contain authored grid rows or targets")
		end
		if definition.seed == nil then
			return fail("Generated definitions require a deterministic seed")
		end

		if definition.fillerAlphabet ~= nil then
			if type(definition.fillerAlphabet) ~= "string"
				or #definition.fillerAlphabet < 2
				or definition.fillerAlphabet:match("^[A-Z]+$") == nil then
				return fail("fillerAlphabet must contain at least two uppercase A-Z characters")
			end
			local seenLetters = {}
			for index = 1, #definition.fillerAlphabet do
				local letter = string.sub(definition.fillerAlphabet, index, index)
				if seenLetters[letter] then
					return fail("fillerAlphabet cannot contain duplicate characters")
				end
				seenLetters[letter] = true
			end
		end

		return true
	end

	local rows, rowError = validateRows(definition.grid, definition.width, definition.height, "grid")
	if not rows then
		return fail(rowError)
	end
	local targets, targetError = validateTargetList(
		definition.targets,
		common.words,
		common.wordSet,
		rows,
		definition.width,
		definition.height,
		common.allowedDirections
	)
	if not targets then
		return fail(targetError)
	end
	local covered, coverageError = validateDirectionCoverage(targets, definition.difficulty)
	if not covered then
		return fail(coverageError)
	end

	local unique, uniqueError = validateUniqueOccurrences(rows, definition.width, definition.height, targets)
	if not unique then
		return fail(uniqueError)
	end

	return true
end

function PuzzleValidator.ValidateCompiled(compiled)
	if type(compiled) ~= "table" then
		return fail("compiled puzzle must be a table")
	end
	if compiled.schemaVersion ~= GameConfig.SchemaVersion
		or compiled.contentRevision ~= GameConfig.ContentRevision
		or compiled.generatorVersion ~= GameConfig.GeneratorVersion then
		return fail("compiled puzzle revision fields do not match GameConfig")
	end
	if not isStableId(compiled.id) or compiled.levelId ~= compiled.id then
		return fail("compiled puzzle must have matching stable id and levelId fields")
	end
	if not VALID_KINDS[compiled.kind] then
		return fail("compiled puzzle kind is invalid")
	end
	if not isInteger(compiled.revision) or compiled.revision < 1 then
		return fail("compiled puzzle revision must be a positive integer")
	end
	if not isInteger(compiled.order) or compiled.order < 1 then
		return fail("compiled puzzle order must be a positive integer")
	end
	if not isNonEmptyString(compiled.chapterId)
		or not isNonEmptyString(compiled.title)
		or not isNonEmptyString(compiled.description)
		or not DIRECTIONS_BY_DIFFICULTY[compiled.difficulty] then
		return fail("compiled puzzle metadata is malformed")
	end
	if not isInteger(compiled.width) or compiled.width < MIN_GRID_DIMENSION or compiled.width > GameConfig.Gameplay.MaxGridWidth
		or not isInteger(compiled.height) or compiled.height < MIN_GRID_DIMENSION or compiled.height > GameConfig.Gameplay.MaxGridHeight then
		return fail("compiled puzzle dimensions are invalid")
	end
	if compiled.gridWidth ~= compiled.width or compiled.gridHeight ~= compiled.height then
		return fail("compiled gridWidth/gridHeight must match width/height")
	end
	if compiled.gridSize ~= math.max(compiled.width, compiled.height) then
		return fail("compiled gridSize must equal the larger dimension")
	end
	if not isInteger(compiled.seed) or compiled.seed < 1 or compiled.seed > MAX_SEED then
		return fail("compiled puzzle seed is invalid")
	end
	if not isInteger(compiled.timeLimitSeconds) or compiled.timeLimitSeconds < 1 or compiled.timeLimitSeconds > MAX_TIME_LIMIT_SECONDS then
		return fail("compiled puzzle timeLimitSeconds is invalid")
	end

	local allowedDirections, directionError = validateDirectionList(compiled.directions, compiled.difficulty)
	if not allowedDirections then
		return fail(directionError)
	end
	local words, wordSetOrError = validateWords(compiled.words, compiled.width, compiled.height, compiled.directions)
	if not words then
		return fail(wordSetOrError)
	end
	local rows, rowError = validateRows(compiled.rows, compiled.width, compiled.height, "rows")
	if not rows then
		return fail(rowError)
	end
	local letterRows, letterError = rowsFromLetters(compiled.letters, compiled.width, compiled.height)
	if not letterRows then
		return fail(letterError)
	end
	for row = 1, compiled.height do
		if rows[row] ~= letterRows[row] then
			return fail(string.format("rows and letters disagree at row %d", row))
		end
	end

	local targets, targetError = validateTargetList(
		compiled.targets,
		words,
		wordSetOrError,
		rows,
		compiled.width,
		compiled.height,
		allowedDirections
	)
	if not targets then
		return fail(targetError)
	end
	local covered, coverageError = validateDirectionCoverage(targets, compiled.difficulty)
	if not covered then
		return fail(coverageError)
	end
	if getDenseArrayLength(compiled.placedWords) ~= #targets then
		return fail("compiled placedWords must contain exactly one entry for every target")
	end
	for index, target in ipairs(targets) do
		local placedWord = compiled.placedWords[index]
		if type(placedWord) ~= "table"
			or placedWord.id ~= target.id
			or placedWord.word ~= target.word
			or placedWord.direction ~= target.direction then
			return fail(string.format("compiled placedWords[%d] does not match its canonical target", index))
		end
		local placedDirection, placedError = validatePath(
			placedWord.path,
			placedWord.word,
			rows,
			compiled.width,
			compiled.height,
			allowedDirections,
			string.format("placedWords[%d]", index)
		)
		if not placedDirection then
			return fail(placedError)
		end
		if placedDirection ~= target.direction or pathKey(placedWord.path) ~= pathKey(target.path) then
			return fail(string.format("compiled placedWords[%d] does not match its canonical target", index))
		end
	end
	local unique, uniqueError = validateUniqueOccurrences(rows, compiled.width, compiled.height, targets)
	if not unique then
		return fail(uniqueError)
	end

	local expectedBoardHash = computeBoardHash(compiled)
	if type(compiled.boardHash) ~= "string" or compiled.boardHash ~= expectedBoardHash then
		return fail("compiled puzzle boardHash does not match its contents")
	end

	return true
end

function PuzzleValidator.GetDirectionsForDifficulty(difficulty)
	local source = DIRECTIONS_BY_DIFFICULTY[difficulty]
	if not source then
		return nil
	end
	return table.clone(source)
end

function PuzzleValidator.GetDirectionStep(directionName)
	local step = DIRECTION_STEPS[directionName]
	if not step then
		return nil
	end
	return step.row, step.column
end

function PuzzleValidator.GetDirectionNameFromPath(path)
	return directionNameFromPath(path)
end

function PuzzleValidator.GetPathKey(path)
	return pathKey(path)
end

function PuzzleValidator.GetUndirectedPathKey(path)
	return undirectedPathKey(path)
end

function PuzzleValidator.FindOccurrences(rows, width, height, word)
	return findOccurrences(rows, width, height, word)
end

function PuzzleValidator.NormalizeWord(word)
	return normalizeWord(word)
end

function PuzzleValidator.ComputeBoardHash(puzzle)
	return computeBoardHash(puzzle)
end

function PuzzleValidator.ValidateDirectionCoverage(targets, difficulty)
	if type(targets) ~= "table" or not DIRECTIONS_BY_DIFFICULTY[difficulty] then
		return false, "Direction coverage input is malformed"
	end
	return validateDirectionCoverage(targets, difficulty)
end

PuzzleValidator.MaxSeed = MAX_SEED
PuzzleValidator.DirectionNames = table.freeze(table.clone(DIRECTION_NAMES))

return table.freeze(PuzzleValidator)
