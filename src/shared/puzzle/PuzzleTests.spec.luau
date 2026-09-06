local NetworkContract
local ProgressionConfig
local PuzzleEngine
local PuzzleGenerator
local PuzzleValidator

if script then
	local sharedFolder = script.Parent.Parent
	local configFolder = sharedFolder:WaitForChild("config")
	local puzzleFolder = sharedFolder:WaitForChild("puzzle")
	NetworkContract = require(sharedFolder:WaitForChild("network"):WaitForChild("NetworkContract"))
	ProgressionConfig = require(configFolder:WaitForChild("ProgressionConfig"))
	PuzzleEngine = require(puzzleFolder:WaitForChild("PuzzleEngine"))
	PuzzleGenerator = require(puzzleFolder:WaitForChild("PuzzleGenerator"))
	PuzzleValidator = require(puzzleFolder:WaitForChild("PuzzleValidator"))
else
	if not Random then
		Random = {
			new = function(seed)
				local state = math.max(1, math.floor(tonumber(seed) or 1) % 2147483647)
				return {
					NextInteger = function(_, minimum, maximum)
						state = (state * 48271) % 2147483647
						return minimum + (state % (maximum - minimum + 1))
					end,
				}
			end,
		}
	end
	NetworkContract = require("../network/NetworkContract")
	ProgressionConfig = require("../config/ProgressionConfig")
	PuzzleEngine = require("./PuzzleEngine")
	PuzzleGenerator = require("./PuzzleGenerator")
	PuzzleValidator = require("./PuzzleValidator")
end

local PuzzleTests = {}

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual, expected, message)
	if actual ~= expected then
		error(string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)), 2)
	end
end

function PuzzleTests.Run()
	local checks = 0
	local function check(condition, message)
		expect(condition, message)
		checks += 1
	end
	local function equal(actual, expected, message)
		expectEqual(actual, expected, message)
		checks += 1
	end

	local firstDefinition = PuzzleGenerator.BuildDefinition(1, "Classic", 12345)
	equal(firstDefinition.gridSize, 4, "Board 1 grid size changed")
	equal(#firstDefinition.words, 2, "Board 1 word count changed")
	equal(firstDefinition.words[1], "CAT", "Board 1 first word changed")
	equal(firstDefinition.words[2], "DOG", "Board 1 second word changed")
	equal(#firstDefinition.directions, 1, "Board 1 direction count changed")
	equal(firstDefinition.directions[1], "E", "Board 1 direction changed")

	local definitionValid, definitionError = PuzzleValidator.ValidateDefinition(firstDefinition)
	check(definitionValid, definitionError or "Board 1 definition should validate")

	local generated = PuzzleGenerator.generate(firstDefinition, 12345)
	equal(#generated.letters, 4, "Generated Board 1 row count changed")
	equal(#generated.letters[1], 4, "Generated Board 1 column count changed")
	equal(#generated.placedWords, 2, "Generated Board 1 placement count changed")

	local diagonal = PuzzleEngine.GetLineSequence(1, 1, 3, 3)
	check(diagonal ~= nil, "Valid diagonal selection was rejected")
	equal(#diagonal, 3, "Diagonal selection length is wrong")
	check(PuzzleEngine.GetLineSequence(1, 1, 2, 3) == nil, "Bent selection was accepted")
	check(PuzzleEngine.PathsMatch(diagonal, {
		{ row = 3, column = 3 },
		{ row = 2, column = 2 },
		{ row = 1, column = 1 },
	}, true), "Client reverse-path matching changed")
	check(not PuzzleValidator.PathsMatch(diagonal, {
		{ row = 3, column = 3 },
		{ row = 2, column = 2 },
		{ row = 1, column = 1 },
	}), "Server exact-path validation accepted a reversed path")
	check(PuzzleEngine.IsComplete({ "CAT", "DOG" }, { CAT = true, DOG = true }), "Completion check rejected all found words")
	check(not PuzzleEngine.IsComplete({ "CAT", "DOG" }, { CAT = true }), "Completion check accepted a missing word")
	equal(PuzzleEngine.CalculateWordScore("CAT", 1.5), 90, "Word score changed")

	equal(ProgressionConfig.Stars.CalculateAward("Classic", 1, 0, true), 3, "Zero-hint stars changed")
	equal(ProgressionConfig.Stars.CalculateAward("Classic", 1, 1, true), 2, "One-hint stars changed")
	equal(ProgressionConfig.Stars.CalculateAward("Classic", 1, 2, true), 1, "Multi-hint stars changed")
	equal(ProgressionConfig.Stars.CalculateAward("Classic", 1, 0, false), 0, "Incomplete-board stars changed")

	local timestamp = 1800000000
	local dailyA = ProgressionConfig.Daily.GetDailyIdentity(150, timestamp)
	local dailyB = ProgressionConfig.Daily.GetDailyIdentity(150, timestamp)
	equal(dailyA.dayStamp, dailyB.dayStamp, "Daily day identity is not deterministic")
	equal(dailyA.level, dailyB.level, "Daily level identity is not deterministic")
	equal(dailyA.seed, dailyB.seed, "Daily seed is not deterministic")
	check(ProgressionConfig.TimedRewards.GetRewardCount() > 0, "Timed reward schedule is empty")

	check(NetworkContract.ValidateTrackAction("WordFound", {
		word = "CAT",
		path = {
			{ row = 1, column = 1 },
			{ row = 1, column = 2 },
			{ row = 1, column = 3 },
		},
	}), "Valid WordFound payload was rejected")
	check(not NetworkContract.ValidateTrackAction("UnknownAction", {}), "Unknown remote action was accepted")
	check(not NetworkContract.IsBoundedValue(math.huge), "Infinite remote number was accepted")
	check(not NetworkContract.IsBoundedValue(0 / 0), "NaN remote number was accepted")

	local rateState = {}
	check(NetworkContract.ConsumeRateLimit(rateState, 1, "WordFound", 10), "First action was rate-limited")
	check(not NetworkContract.ConsumeRateLimit(rateState, 1, "WordFound", 10.01), "Rapid duplicate action bypassed rate limit")
	check(NetworkContract.ConsumeRateLimit(rateState, 1, "WordFound", 10.1), "Action stayed rate-limited too long")

	return {
		passed = checks,
	}
end

if not script then
	local result = PuzzleTests.Run()
	print(string.format("PUZZLE_TESTS_PASSED=%d", result.passed))
end

return PuzzleTests
