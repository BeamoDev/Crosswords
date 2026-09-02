local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PuzzleGenerator = {}

local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
local PuzzleValidator = require(assert(script.Parent:WaitForChild("PuzzleValidator", 10), "Word Search PuzzleValidator is missing"))

local MODULUS = 2147483647
local MAX_SEED = PuzzleValidator.MaxSeed
local DEFAULT_FILLER_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local DEFAULT_GENERATION_ATTEMPTS = 16
local DEFAULT_FILL_ATTEMPTS = 16
local DEFAULT_SEARCH_NODES = 100000

-- These are checked only in generated filler, never against a declared target.
-- Keeping the list local avoids making sensitive terms part of public catalog data.
local BLOCKED_FILLER_SEQUENCES = {
	"FUCK",
	"SHIT",
	"CUNT",
	"PORN",
	"NAZI",
}

local DeterministicRandom = {}
DeterministicRandom.__index = DeterministicRandom

function DeterministicRandom.new(seed)
	return setmetatable({
		state = math.clamp(math.floor(tonumber(seed) or 1), 1, MAX_SEED),
	}, DeterministicRandom)
end

function DeterministicRandom:NextInteger(minimum, maximum)
	self.state = (self.state * 48271) % MODULUS
	local span = maximum - minimum + 1
	return minimum + (self.state % span)
end

local function mixSeed(seed, salt)
	local mixed = ((seed * 48271) + (salt * 69621) + 17) % MAX_SEED
	return math.floor(mixed) + 1
end

local function cloneArray(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
end

local function clonePath(path)
	local result = {}
	for index, point in ipairs(path or {}) do
		result[index] = {
			row = point.row,
			column = point.column,
		}
	end
	return result
end

local function createGrid(width, height)
	local grid = {}
	local usage = {}
	for row = 1, height do
		grid[row] = table.create(width)
		usage[row] = table.create(width, 0)
	end
	return grid, usage
end

local function cloneGrid(grid, width, height)
	local result = {}
	for row = 1, height do
		result[row] = {}
		for column = 1, width do
			result[row][column] = grid[row][column]
		end
	end
	return result
end

local function shuffle(values, randomObject)
	for index = #values, 2, -1 do
		local swapIndex = randomObject:NextInteger(1, index)
		values[index], values[swapIndex] = values[swapIndex], values[index]
	end
end

local function makeTargetId(levelId, word)
	return string.format("%s:%s", levelId, string.lower(word))
end

local function buildPath(startRow, startColumn, rowStep, columnStep, length)
	local path = table.create(length)
	for index = 1, length do
		path[index] = {
			row = startRow + rowStep * (index - 1),
			column = startColumn + columnStep * (index - 1),
		}
	end
	return path
end

local function enumerateCandidates(word, definition)
	local candidates = {}
	for _, directionName in ipairs(definition.directions) do
		local rowStep, columnStep = PuzzleValidator.GetDirectionStep(directionName)
		for row = 1, definition.height do
			for column = 1, definition.width do
				local endRow = row + rowStep * (#word - 1)
				local endColumn = column + columnStep * (#word - 1)
				if endRow >= 1 and endRow <= definition.height and endColumn >= 1 and endColumn <= definition.width then
					table.insert(candidates, {
						direction = directionName,
						path = buildPath(row, column, rowStep, columnStep, #word),
					})
				end
			end
		end
	end
	return candidates
end

local function canPlace(grid, word, path)
	for index, point in ipairs(path) do
		local existing = grid[point.row][point.column]
		if existing ~= nil and existing ~= string.sub(word, index, index) then
			return false
		end
	end
	return true
end

local function place(grid, usage, word, path)
	for index, point in ipairs(path) do
		grid[point.row][point.column] = string.sub(word, index, index)
		usage[point.row][point.column] += 1
	end
end

local function remove(grid, usage, path)
	for _, point in ipairs(path) do
		usage[point.row][point.column] -= 1
		if usage[point.row][point.column] == 0 then
			grid[point.row][point.column] = nil
		end
	end
end

local function placeAllWords(definition, seed)
	local records = {}
	for index, word in ipairs(definition.words) do
		records[index] = {
			originalIndex = index,
			word = word,
			candidates = enumerateCandidates(word, definition),
		}
	end

	table.sort(records, function(left, right)
		if #left.candidates ~= #right.candidates then
			return #left.candidates < #right.candidates
		end
		if #left.word ~= #right.word then
			return #left.word > #right.word
		end
		if left.word ~= right.word then
			return left.word < right.word
		end
		return left.originalIndex < right.originalIndex
	end)

	local randomObject = DeterministicRandom.new(seed)
	for _, record in ipairs(records) do
		shuffle(record.candidates, randomObject)
	end

	local grid, usage = createGrid(definition.width, definition.height)
	local placements = table.create(#records)
	local visitedNodes = 0
	local exhaustedBudget = false

	local function search(recordIndex)
		if recordIndex > #records then
			return true
		end

		local record = records[recordIndex]
		for _, candidate in ipairs(record.candidates) do
			visitedNodes += 1
			if visitedNodes > DEFAULT_SEARCH_NODES then
				exhaustedBudget = true
				return false
			end

			if canPlace(grid, record.word, candidate.path) then
				place(grid, usage, record.word, candidate.path)
				placements[record.originalIndex] = {
					id = makeTargetId(definition.id, record.word),
					word = record.word,
					direction = candidate.direction,
					path = clonePath(candidate.path),
				}

				if search(recordIndex + 1) then
					return true
				end

				placements[record.originalIndex] = nil
				remove(grid, usage, candidate.path)
				if exhaustedBudget then
					return false
				end
			end
		end

		return false
	end

	if not search(1) then
		return nil, nil, exhaustedBudget and "search budget exhausted" or "no valid placement"
	end

	return grid, placements
end

local function fillGrid(baseGrid, definition, seed)
	local grid = cloneGrid(baseGrid, definition.width, definition.height)
	local randomObject = DeterministicRandom.new(seed)
	local alphabet = definition.fillerAlphabet or DEFAULT_FILLER_ALPHABET

	for row = 1, definition.height do
		for column = 1, definition.width do
			if grid[row][column] == nil then
				local letterIndex = randomObject:NextInteger(1, #alphabet)
				grid[row][column] = string.sub(alphabet, letterIndex, letterIndex)
			end
		end
	end

	return grid
end

local function gridToRowsAndLetters(grid, width, height)
	local rows = {}
	local letters = {}
	for row = 1, height do
		local rowLetters = {}
		for column = 1, width do
			rowLetters[column] = grid[row][column]
		end
		letters[row] = rowLetters
		rows[row] = table.concat(rowLetters)
	end
	return rows, letters
end

local function containsBlockedFillerSequence(rows, width, height, declaredWordSet)
	for _, blockedWord in ipairs(BLOCKED_FILLER_SEQUENCES) do
		if not declaredWordSet[blockedWord]
			and #PuzzleValidator.FindOccurrences(rows, width, height, blockedWord) > 0 then
			return true
		end
	end
	return false
end

local function targetsAreUnique(rows, definition, targets)
	local physicalPaths = {}
	for _, target in ipairs(targets) do
		local targetPathKey = PuzzleValidator.GetUndirectedPathKey(target.path)
		if not targetPathKey or physicalPaths[targetPathKey] then
			return false
		end
		physicalPaths[targetPathKey] = true
		local occurrences = PuzzleValidator.FindOccurrences(rows, definition.width, definition.height, target.word)
		if #occurrences ~= 1
			or PuzzleValidator.GetUndirectedPathKey(occurrences[1]) ~= targetPathKey then
			return false
		end
	end
	return true
end

local function buildPlacedWord(target)
	local first = target.path[1]
	local last = target.path[#target.path]
	local path = clonePath(target.path)
	return {
		id = target.id,
		targetId = target.id,
		word = target.word,
		direction = target.direction,
		directionKey = target.direction,
		startRow = first.row,
		startColumn = first.column,
		endRow = last.row,
		endColumn = last.column,
		path = path,
	}
end

local function compilePublicPuzzle(definition, seed, rows, letters, sourceTargets)
	local targets = {}
	local placedWords = {}
	local placedWordsByWord = {}
	local targetsById = {}

	for index, sourceTarget in ipairs(sourceTargets) do
		local target = {
			id = sourceTarget.id,
			word = sourceTarget.word,
			direction = sourceTarget.direction or PuzzleValidator.GetDirectionNameFromPath(sourceTarget.path),
			path = clonePath(sourceTarget.path),
		}
		targets[index] = target
		targetsById[target.id] = target

		local placedWord = buildPlacedWord(target)
		placedWords[index] = placedWord
		placedWordsByWord[target.word] = placedWord
	end

	local compiled = {
		schemaVersion = GameConfig.SchemaVersion,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
		id = definition.id,
		levelId = definition.id,
		revision = definition.revision,
		kind = definition.kind,
		chapterId = definition.chapterId,
		catalogIndex = definition.catalogIndex,
		order = definition.order,
		title = definition.title,
		subtitle = definition.description,
		description = definition.description,
		difficulty = definition.difficulty,
		seed = seed,
		width = definition.width,
		height = definition.height,
		gridWidth = definition.width,
		gridHeight = definition.height,
		gridSize = math.max(definition.width, definition.height),
		timeLimitSeconds = definition.timeLimitSeconds,
		directions = cloneArray(definition.directions),
		words = cloneArray(definition.words),
		rows = cloneArray(rows),
		letters = letters,
		targets = targets,
		targetsById = targetsById,
		placedWords = placedWords,
		placedWordsByWord = placedWordsByWord,
	}
	compiled.boardHash = PuzzleValidator.ComputeBoardHash(compiled)
	return compiled
end

local function compileAuthored(definition)
	local rows = cloneArray(definition.grid)
	local letters = {}
	for row = 1, definition.height do
		letters[row] = {}
		for column = 1, definition.width do
			letters[row][column] = string.sub(rows[row], column, column)
		end
	end

	local targets = {}
	for index, target in ipairs(definition.targets) do
		targets[index] = {
			id = target.id,
			word = target.word,
			direction = target.direction or PuzzleValidator.GetDirectionNameFromPath(target.path),
			path = clonePath(target.path),
		}
	end

	return compilePublicPuzzle(definition, definition.seed, rows, letters, targets)
end

local function compileGenerated(definition, seed)
	local declaredWordSet = {}
	for _, word in ipairs(definition.words) do
		declaredWordSet[word] = true
	end

	local lastPlacementError = "no valid placement"
	for generationAttempt = 1, DEFAULT_GENERATION_ATTEMPTS do
		local placementSeed = mixSeed(seed, generationAttempt * 101)
		local baseGrid, targets, placementError = placeAllWords(definition, placementSeed)
		if baseGrid and targets then
			local hasCoverage = PuzzleValidator.ValidateDirectionCoverage(targets, definition.difficulty)
			if hasCoverage then
				for fillAttempt = 1, DEFAULT_FILL_ATTEMPTS do
					local fillSeed = mixSeed(seed, generationAttempt * 1009 + fillAttempt * 9176)
					local filledGrid = fillGrid(baseGrid, definition, fillSeed)
					local rows, letters = gridToRowsAndLetters(filledGrid, definition.width, definition.height)
					if targetsAreUnique(rows, definition, targets)
						and not containsBlockedFillerSequence(rows, definition.width, definition.height, declaredWordSet) then
						return compilePublicPuzzle(definition, seed, rows, letters, targets)
					end
				end
				lastPlacementError = "filler produced duplicate target or blocked occurrences"
			else
				lastPlacementError = "placement did not satisfy difficulty direction coverage"
			end
		else
			lastPlacementError = placementError or lastPlacementError
		end
	end

	return nil, string.format(
		"Unable to generate level %s within %d deterministic attempts: %s",
		definition.id,
		DEFAULT_GENERATION_ATTEMPTS,
		lastPlacementError
	)
end

function PuzzleGenerator.Generate(definition, seedOverride)
	local validDefinition, definitionError = PuzzleValidator.ValidateDefinition(definition)
	if not validDefinition then
		return nil, definitionError
	end

	if seedOverride ~= nil then
		if type(seedOverride) ~= "number"
			or seedOverride ~= seedOverride
			or seedOverride <= -math.huge
			or seedOverride >= math.huge
			or seedOverride % 1 ~= 0
			or seedOverride < 1
			or seedOverride > MAX_SEED then
			return nil, string.format("seedOverride must be an integer from 1 to %d", MAX_SEED)
		end
		if definition.kind == "Authored" and seedOverride ~= definition.seed then
			return nil, "Authored definitions do not accept a different seedOverride"
		end
	end

	local seed = seedOverride or definition.seed
	local compiled, compileError
	if definition.kind == "Authored" then
		compiled = compileAuthored(definition)
	else
		compiled, compileError = compileGenerated(definition, seed)
	end
	if not compiled then
		return nil, compileError or "Puzzle compilation failed"
	end

	local validCompiled, compiledError = PuzzleValidator.ValidateCompiled(compiled)
	if not validCompiled then
		return nil, string.format("Generated puzzle failed validation: %s", compiledError)
	end

	return compiled
end

PuzzleGenerator.GenerationAttemptLimit = DEFAULT_GENERATION_ATTEMPTS
PuzzleGenerator.FillAttemptLimit = DEFAULT_FILL_ATTEMPTS
PuzzleGenerator.SearchNodeLimit = DEFAULT_SEARCH_NODES

return table.freeze(PuzzleGenerator)
