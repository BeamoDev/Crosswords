local PuzzleEngineTests = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local serverFolder = script.Parent.Parent
local sharedFolder = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(sharedFolder:WaitForChild("config", 10), "Word Search config folder is missing")
local contentFolder = assert(serverFolder:WaitForChild("content", 10), "Word Search server content folder is missing")
local puzzleFolder = assert(serverFolder:WaitForChild("puzzle", 10), "Word Search server puzzle folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
local LevelCatalog = require(assert(contentFolder:WaitForChild("LevelCatalog", 10), "Word Search LevelCatalog is missing"))
local PuzzleValidator = require(assert(puzzleFolder:WaitForChild("PuzzleValidator", 10), "Word Search PuzzleValidator is missing"))
local PuzzleGenerator = require(assert(puzzleFolder:WaitForChild("PuzzleGenerator", 10), "Word Search PuzzleGenerator is missing"))

local EXPECTED_CHAPTERS = { "Animals", "Food", "Nature", "Roblox", "Space", "Expert" }
local ALL_DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

local function deepClone(value)
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[deepClone(key)] = deepClone(child)
	end
	return result
end

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
	end
end

local function assertTruthy(value, message)
	if not value then
		error(message, 2)
	end
end

local function assertInvalidDefinition(definition, expectedFragment)
	local valid, validationError = PuzzleValidator.ValidateDefinition(definition)
	assertEqual(valid, false, "Malformed definition unexpectedly validated")
	assertTruthy(type(validationError) == "string" and validationError ~= "", "Invalid definition did not return an error string")
	if expectedFragment then
		assertTruthy(
			string.find(string.lower(validationError), string.lower(expectedFragment), 1, true) ~= nil,
			string.format("Expected validation error containing %q, got %q", expectedFragment, validationError)
		)
	end
end

local function assertSameCompiled(left, right)
	assertEqual(left.boardHash, right.boardHash, "Deterministic hashes differ")
	assertEqual(#left.rows, #right.rows, "Deterministic row counts differ")
	for row = 1, #left.rows do
		assertEqual(left.rows[row], right.rows[row], string.format("Deterministic row %d differs", row))
	end
	assertEqual(#left.targets, #right.targets, "Deterministic target counts differ")
	for index = 1, #left.targets do
		assertEqual(left.targets[index].id, right.targets[index].id, "Deterministic target IDs differ")
		assertEqual(
			PuzzleValidator.GetPathKey(left.targets[index].path),
			PuzzleValidator.GetPathKey(right.targets[index].path),
			"Deterministic target paths differ"
		)
	end
end

local function makeDirectionalCompiled(directionName)
	local width = 5
	local height = 5
	local starts = {
		N = { 4, 3 },
		NE = { 4, 2 },
		E = { 3, 2 },
		SE = { 2, 2 },
		S = { 2, 3 },
		SW = { 2, 4 },
		W = { 3, 4 },
		NW = { 4, 4 },
	}
	local rowStep, columnStep = PuzzleValidator.GetDirectionStep(directionName)
	local start = starts[directionName]
	local path = {}
	local letters = {}

	for row = 1, height do
		letters[row] = {}
		for column = 1, width do
			letters[row][column] = ((row + column) % 2 == 0) and "Q" or "X"
		end
	end

	local word = "CAT"
	for index = 1, #word do
		local row = start[1] + rowStep * (index - 1)
		local column = start[2] + columnStep * (index - 1)
		path[index] = { row = row, column = column }
		letters[row][column] = string.sub(word, index, index)
	end

	local rows = {}
	for row = 1, height do
		rows[row] = table.concat(letters[row])
	end

	local id = "fixture-direction-" .. string.lower(directionName)
	local target = {
		id = id .. ":cat",
		word = word,
		direction = directionName,
		path = path,
	}
	local compiled = {
		schemaVersion = GameConfig.SchemaVersion,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
		id = id,
		levelId = id,
		revision = 1,
		kind = "Authored",
		chapterId = "Expert",
		order = 1,
		title = "Direction Fixture",
		description = "Validates one canonical compass direction.",
		difficulty = "Expert",
		seed = 1,
		width = width,
		height = height,
		gridWidth = width,
		gridHeight = height,
		gridSize = math.max(width, height),
		timeLimitSeconds = 60,
		directions = deepClone(ALL_DIRECTIONS),
		words = { word },
		rows = rows,
		letters = letters,
		targets = { deepClone(target) },
		placedWords = { deepClone(target) },
	}
	compiled.boardHash = PuzzleValidator.ComputeBoardHash(compiled)
	return compiled
end

local TESTS = {
	{
		name = "catalog has stable complete structure",
		run = function()
			assertTruthy(LevelCatalog.GetLevelCount() >= 18, "Catalog must contain at least 18 levels")
			local chapters = LevelCatalog.GetChapters()
			assertEqual(#chapters, #EXPECTED_CHAPTERS, "Catalog chapter count differs")
			for index, expectedId in ipairs(EXPECTED_CHAPTERS) do
				assertEqual(chapters[index].id, expectedId, "Catalog chapter order differs")
				assertTruthy(#chapters[index].levelIds > 0, "Every chapter must own at least one level")
			end

			local publicCatalog = LevelCatalog.GetPublicCatalog()
			assertEqual(publicCatalog.schemaVersion, GameConfig.SchemaVersion, "Public schema version differs")
			assertEqual(publicCatalog.contentRevision, GameConfig.ContentRevision, "Public content revision differs")
			assertEqual(publicCatalog.generatorVersion, GameConfig.GeneratorVersion, "Public generator version differs")
			assertEqual(#publicCatalog.levels, LevelCatalog.GetLevelCount(), "Public level count differs")

			local dailyRotation = GameConfig.DailyRotation
			assertTruthy(type(dailyRotation) == "table", "Daily rotation manifest is missing")
			assertTruthy(type(dailyRotation.Revision) == "string" and dailyRotation.Revision ~= "", "Daily rotation revision is missing")
			assertTruthy(type(dailyRotation.LevelIds) == "table" and #dailyRotation.LevelIds > 0, "Daily rotation has no levels")
			local seenDailyIds = {}
			for _, levelId in ipairs(dailyRotation.LevelIds) do
				assertTruthy(not seenDailyIds[levelId], "Daily rotation contains duplicate level " .. tostring(levelId))
				seenDailyIds[levelId] = true
				local dailyLevel = LevelCatalog.GetLevel(levelId)
				assertTruthy(dailyLevel ~= nil, "Daily rotation references missing level " .. tostring(levelId))
				assertTruthy(dailyLevel.dailyEligible ~= false, "Daily rotation references ineligible level " .. tostring(levelId))
			end

			for index = 1, LevelCatalog.GetLevelCount() do
				local level = LevelCatalog.GetLevelByIndex(index)
				assertTruthy(level ~= nil, string.format("Level %d is missing", index))
				assertEqual(LevelCatalog.GetLevel(level.id), level, "ID lookup returned a different level")
				assertEqual(LevelCatalog.GetLevelIndex(level.id), index, "Reverse level index differs")
				local valid, validationError = PuzzleValidator.ValidateDefinition(level)
				assertTruthy(valid, string.format("Catalog level %s is invalid: %s", level.id, tostring(validationError)))
			end
		end,
	},
	{
		name = "every catalog level compiles to an exact valid board",
		run = function()
			local authoredCount = 0
			local seenDifficulties = {}
			for index = 1, LevelCatalog.GetLevelCount() do
				local level = LevelCatalog.GetLevelByIndex(index)
				local compiled, generationError = PuzzleGenerator.Generate(level)
				assertTruthy(compiled ~= nil, string.format("Level %s failed generation: %s", level.id, tostring(generationError)))
				assertEqual(compiled.width, level.width, "Generated width changed")
				assertEqual(compiled.height, level.height, "Generated height changed")
				assertEqual(#compiled.targets, #level.words, "Generator did not place every word")
				local valid, validationError = PuzzleValidator.ValidateCompiled(compiled)
				assertTruthy(valid, string.format("Compiled level %s is invalid: %s", level.id, tostring(validationError)))
				seenDifficulties[level.difficulty] = true
				if level.kind == "Authored" then
					authoredCount += 1
				end
			end
			assertTruthy(authoredCount >= 1, "Catalog requires at least one authored grid")
			for _, difficulty in ipairs({ "Easy", "Medium", "Hard", "Expert" }) do
				assertTruthy(seenDifficulties[difficulty], string.format("Catalog is missing %s difficulty", difficulty))
			end
		end,
	},
	{
		name = "generation is deterministic for fixed and overridden seeds",
		run = function()
			local definition = LevelCatalog.GetLevel("space-deep-universe")
			assertTruthy(definition ~= nil, "Determinism fixture level is missing")

			local first, firstError = PuzzleGenerator.Generate(definition)
			local second, secondError = PuzzleGenerator.Generate(definition)
			assertTruthy(first ~= nil, tostring(firstError))
			assertTruthy(second ~= nil, tostring(secondError))
			assertSameCompiled(first, second)
			assertEqual(first.boardHash, "3b5e2edd", "Default deterministic fixture changed without a generator revision")

			local overriddenA, overrideErrorA = PuzzleGenerator.Generate(definition, 1234567)
			local overriddenB, overrideErrorB = PuzzleGenerator.Generate(definition, 1234567)
			assertTruthy(overriddenA ~= nil, tostring(overrideErrorA))
			assertTruthy(overriddenB ~= nil, tostring(overrideErrorB))
			assertSameCompiled(overriddenA, overriddenB)
			assertEqual(overriddenA.seed, 1234567, "Compiled puzzle lost seed override")
			assertEqual(overriddenA.boardHash, "25b6bebd", "Override deterministic fixture changed without a generator revision")
			assertTruthy(first.boardHash ~= overriddenA.boardHash, "Different seeds unexpectedly produced the same fixture hash")
		end,
	},
	{
		name = "compiled paths support all eight compass directions",
		run = function()
			for _, directionName in ipairs(ALL_DIRECTIONS) do
				local compiled = makeDirectionalCompiled(directionName)
				local valid, validationError = PuzzleValidator.ValidateCompiled(compiled)
				assertTruthy(valid, string.format("Direction %s failed validation: %s", directionName, tostring(validationError)))
				assertEqual(
					PuzzleValidator.GetDirectionNameFromPath(compiled.targets[1].path),
					directionName,
					"Path direction was resolved incorrectly"
				)
			end
		end,
	},
	{
		name = "definitions reject duplicates and malformed or impossible data",
		run = function()
			local base = deepClone(LevelCatalog.GetLevel("animals-pond-and-farm"))

			local duplicateWords = deepClone(base)
			duplicateWords.words[2] = duplicateWords.words[1]
			assertInvalidDefinition(duplicateWords, "duplicated")

			local malformedWord = deepClone(base)
			malformedWord.words[1] = "lowercase"
			assertInvalidDefinition(malformedWord, "uppercase")

			local impossibleWord = deepClone(base)
			impossibleWord.width = 4
			impossibleWord.height = 4
			impossibleWord.words = { "PLANET" }
			assertInvalidDefinition(impossibleWord, "cannot fit")

			local duplicateDirection = deepClone(base)
			duplicateDirection.directions = { "E", "E" }
			assertInvalidDefinition(duplicateDirection, "duplicated")

			local invalidRevision = deepClone(base)
			invalidRevision.contentRevision = "stale-revision"
			assertInvalidDefinition(invalidRevision, "contentRevision")

			local generatedWithAuthoredData = deepClone(base)
			generatedWithAuthoredData.grid = { "XXXX", "XXXX", "XXXX", "XXXX" }
			assertInvalidDefinition(generatedWithAuthoredData, "cannot contain")
		end,
	},
	{
		name = "authored and compiled grids reject bad paths and duplicate occurrences",
		run = function()
			local duplicateTargetId = deepClone(LevelCatalog.GetLevel("animals-friendly-pets"))
			duplicateTargetId.targets[2].id = duplicateTargetId.targets[1].id
			assertInvalidDefinition(duplicateTargetId, "duplicated")

			local authored = deepClone(LevelCatalog.GetLevel("animals-friendly-pets"))
			authored.targets[1].path = {
				{ row = 2, column = 1 },
				{ row = 2, column = 2 },
				{ row = 2, column = 3 },
			}
			assertInvalidDefinition(authored, "does not spell")

			local compiled, generationError = PuzzleGenerator.Generate(LevelCatalog.GetLevel("animals-friendly-pets"))
			assertTruthy(compiled ~= nil, tostring(generationError))

			local mismatchedRows = deepClone(compiled)
			mismatchedRows.rows[1] = "XXXXXXXX"
			local validRows, rowsError = PuzzleValidator.ValidateCompiled(mismatchedRows)
			assertEqual(validRows, false, "Rows/letters mismatch unexpectedly validated")
			assertTruthy(type(rowsError) == "string", "Malformed compiled grid returned no error")

			local malformedPlacedPath = deepClone(compiled)
			malformedPlacedPath.placedWords[1].path[1].row = "not-a-row"
			local didNotThrow, malformedValid, malformedError = pcall(
				PuzzleValidator.ValidateCompiled,
				malformedPlacedPath
			)
			assertEqual(didNotThrow, true, "Malformed placedWords path caused the validator to throw")
			assertEqual(malformedValid, false, "Malformed placedWords path unexpectedly validated")
			assertTruthy(type(malformedError) == "string", "Malformed placedWords path returned no error")

			local duplicateOccurrence = deepClone(compiled)
			duplicateOccurrence.rows[8] = "CATXXXXX"
			for column = 1, duplicateOccurrence.width do
				duplicateOccurrence.letters[8][column] = string.sub(duplicateOccurrence.rows[8], column, column)
			end
			local validDuplicate, duplicateError = PuzzleValidator.ValidateCompiled(duplicateOccurrence)
			assertEqual(validDuplicate, false, "Duplicate target occurrence unexpectedly validated")
			assertTruthy(
				type(duplicateError) == "string" and string.find(string.lower(duplicateError), "exactly once", 1, true) ~= nil,
				"Duplicate occurrence returned the wrong validation error"
			)

			local reversePair = makeDirectionalCompiled("E")
			reversePair.id = "fixture-reverse-pair"
			reversePair.levelId = reversePair.id
			local forwardPath = {
				{ row = 3, column = 2 },
				{ row = 3, column = 3 },
				{ row = 3, column = 4 },
			}
			for index, letter in ipairs({ "D", "O", "G" }) do
				reversePair.letters[3][index + 1] = letter
			end
			reversePair.rows[3] = table.concat(reversePair.letters[3])
			reversePair.words = { "DOG", "GOD" }
			reversePair.targets = {
				{ id = "fixture-reverse-pair:dog", word = "DOG", direction = "E", path = deepClone(forwardPath) },
				{ id = "fixture-reverse-pair:god", word = "GOD", direction = "W", path = {
					{ row = 3, column = 4 },
					{ row = 3, column = 3 },
					{ row = 3, column = 2 },
				} },
			}
			reversePair.placedWords = deepClone(reversePair.targets)
			reversePair.boardHash = PuzzleValidator.ComputeBoardHash(reversePair)
			local reverseValid, reverseError = PuzzleValidator.ValidateCompiled(reversePair)
			assertEqual(reverseValid, false, "Two targets sharing a physical path unexpectedly validated")
			assertTruthy(
				type(reverseError) == "string" and string.find(string.lower(reverseError), "physical path", 1, true) ~= nil,
				"Shared reverse path returned the wrong validation error"
			)

			local palindrome = makeDirectionalCompiled("E")
			palindrome.id = "fixture-palindrome"
			palindrome.levelId = palindrome.id
			palindrome.words = { "LEVEL" }
			palindrome.rows[3] = "LEVEL"
			for column = 1, 5 do
				palindrome.letters[3][column] = string.sub("LEVEL", column, column)
			end
			palindrome.targets = { {
				id = "fixture-palindrome:level",
				word = "LEVEL",
				direction = "E",
				path = {
					{ row = 3, column = 1 },
					{ row = 3, column = 2 },
					{ row = 3, column = 3 },
					{ row = 3, column = 4 },
					{ row = 3, column = 5 },
				},
			} }
			palindrome.placedWords = deepClone(palindrome.targets)
			palindrome.boardHash = PuzzleValidator.ComputeBoardHash(palindrome)
			local palindromeValid, palindromeError = PuzzleValidator.ValidateCompiled(palindrome)
			assertTruthy(palindromeValid, "A single palindrome path should validate: " .. tostring(palindromeError))
		end,
	},
}

function PuzzleEngineTests.Run()
	local passedNames = {}
	local failures = {}

	for _, testCase in ipairs(TESTS) do
		local success, testError = xpcall(testCase.run, debug.traceback)
		if success then
			table.insert(passedNames, testCase.name)
		else
			table.insert(failures, string.format("%s\n%s", testCase.name, tostring(testError)))
		end
	end

	if #failures > 0 then
		error(string.format(
			"PuzzleEngineTests: %d/%d tests failed\n\n%s",
			#failures,
			#TESTS,
			table.concat(failures, "\n\n")
		), 2)
	end

	return {
		passed = #passedNames,
		total = #TESTS,
		tests = passedNames,
	}
end

return table.freeze(PuzzleEngineTests)
