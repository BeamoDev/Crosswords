-- Resolves server-owned round requests into compiled puzzles. Clients may request a
-- mode and an unlocked level ID, but never supply a seed, grid, words, or reward.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(shared:WaitForChild("config", 10), "Word Search config folder is missing")
local serverFolder = script.Parent.Parent.Parent
local contentFolder = assert(serverFolder:WaitForChild("content", 10), "Word Search server content folder is missing")
local puzzleFolder = assert(serverFolder:WaitForChild("puzzle", 10), "Word Search server puzzle folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))
local LevelCatalog = require(assert(contentFolder:WaitForChild("LevelCatalog", 10), "Word Search LevelCatalog is missing"))
local PuzzleGenerator = require(assert(puzzleFolder:WaitForChild("PuzzleGenerator", 10), "Word Search PuzzleGenerator is missing"))
local PuzzleValidator = require(assert(puzzleFolder:WaitForChild("PuzzleValidator", 10), "Word Search PuzzleValidator is missing"))

local PuzzleService = {}

local sequenceByUserId = {}
local compiledCache = {}

local function copyArray(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
end

local function hashText(text)
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 16777619) % 2147483647
	end
	return math.max(1, math.floor(hash))
end

local function nextServerSeed(player)
	local userId = player.UserId
	local sequence = (sequenceByUserId[userId] or 0) + 1
	sequenceByUserId[userId] = sequence
	return hashText(string.format(
		"%s:%d:%d:%s",
		game.JobId,
		userId,
		sequence,
		HttpService:GenerateGUID(false)
	))
end

local function chooseQuickLevel(snapshot, player, mode)
	local levelCount = math.max(1, LevelCatalog.GetLevelCount())
	local unlockedLevel = math.clamp(
		math.floor(tonumber(snapshot and snapshot.progression and snapshot.progression.unlockedLevel) or 1),
		1,
		levelCount
	)
	local window = math.max(1, math.floor(tonumber(GameConfig.Gameplay.QuickPlayRecentLevelWindow) or 4))
	local firstIndex = math.max(1, unlockedLevel - window + 1)
	local seed = nextServerSeed(player)
	local randomObject = Random.new(seed)
	local index = randomObject:NextInteger(firstIndex, unlockedLevel)

	if mode == "Zen" and unlockedLevel > 1 then
		index = randomObject:NextInteger(1, unlockedLevel)
	end

	return LevelCatalog.GetLevelByIndex(index), seed
end

local function resolveDefinition(player, request, snapshot, dailyIdentity)
	if request.mode == "Classic" then
		local definition = request.levelId and LevelCatalog.GetLevel(request.levelId) or LevelCatalog.GetLevelByIndex(1)
		if not definition then
			return nil, nil, "That level does not exist."
		end

		local levelIndex = LevelCatalog.GetLevelIndex(definition.id)
		local unlockedLevel = math.max(1, math.floor(tonumber(snapshot and snapshot.progression and snapshot.progression.unlockedLevel) or 1))
		if not levelIndex or levelIndex > unlockedLevel then
			return nil, nil, "That level is still locked."
		end

		return definition, definition.seed, nil
	end

	if request.mode == "Daily" then
		local identity = dailyIdentity
		if type(identity) ~= "table" or type(identity.level) ~= "table" then
			return nil, nil, "The daily puzzle is unavailable."
		end

		local definition = LevelCatalog.GetLevel(identity.levelId)
		if not definition then
			return nil, nil, "The daily puzzle could not be resolved."
		end

		return definition, identity.seed, nil
	end

	return chooseQuickLevel(snapshot, player, request.mode)
end

local function makePublicPuzzle(compiled, context)
	return {
		id = compiled.id,
		title = compiled.title,
		description = compiled.description,
		chapterId = compiled.chapterId,
		difficulty = compiled.difficulty,
		width = compiled.width,
		height = compiled.height,
		letters = compiled.letters,
		words = copyArray(compiled.words),
		timeLimit = context.timeLimit,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
	}
end

function PuzzleService.Create(player, request, snapshot, dailyIdentity)
	local definition, seed, resolveError = resolveDefinition(player, request, snapshot, dailyIdentity)
	if not definition then
		return nil, resolveError or "No puzzle is available."
	end

	-- Authored boards are immutable and therefore retain their catalog seed. Generated
	-- boards may use a server-issued seed in Quick, Daily, and Zen play.
	if definition.kind == "Authored" then
		seed = definition.seed
	end

	local validDefinition, definitionError = PuzzleValidator.ValidateDefinition(definition)
	if not validDefinition then
		warn(string.format("[PuzzleService] Rejected level %s: %s", tostring(definition.id), tostring(definitionError)))
		return nil, "This puzzle is temporarily unavailable."
	end

	-- Classic puzzles and authored boards are seed-stable. Reusing their immutable
	-- compiled representation avoids repeating the generator's backtracking work
	-- every time a player opens or restarts the same level.
	local cacheKey = (request.mode == "Classic" or definition.kind == "Authored") and definition.id or nil
	local compiled = cacheKey and compiledCache[cacheKey] or nil
	local generationError
	if not compiled then
		compiled, generationError = PuzzleGenerator.Generate(definition, seed)
		if compiled and cacheKey then
			compiledCache[cacheKey] = compiled
		end
	end
	if not compiled then
		warn(string.format("[PuzzleService] Failed to generate level %s: %s", tostring(definition.id), tostring(generationError)))
		return nil, "This puzzle could not be generated. Please retry."
	end

	local validCompiled, compiledError = PuzzleValidator.ValidateCompiled(compiled)
	if not validCompiled then
		warn(string.format("[PuzzleService] Invalid compiled level %s: %s", tostring(definition.id), tostring(compiledError)))
		return nil, "This puzzle failed its safety check. Please retry."
	end

	local timeLimit = definition.timeLimitSeconds
	if request.mode == "Zen" then
		timeLimit = nil
	end

	local context = {
		mode = request.mode,
		levelId = request.mode == "Classic" and definition.id or nil,
		sourceLevelId = definition.id,
		levelIndex = LevelCatalog.GetLevelIndex(definition.id),
		difficulty = definition.difficulty,
		seed = seed,
		timeLimit = timeLimit,
		dailyDayStamp = request.mode == "Daily" and dailyIdentity.dayStamp or nil,
		contentRevision = GameConfig.ContentRevision,
		generatorVersion = GameConfig.GeneratorVersion,
	}

	return {
		compiled = compiled,
		context = context,
		public = makePublicPuzzle(compiled, context),
	}, nil
end

function PuzzleService.GetCatalogSnapshot()
	return LevelCatalog.GetPublicCatalog()
end

function PuzzleService.ClearPlayer(player)
	if player then
		sequenceByUserId[player.UserId] = nil
	end
end

return PuzzleService
