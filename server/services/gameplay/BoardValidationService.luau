local BoardValidationService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local PuzzleEconomy = require(sharedFolder:WaitForChild("config"):WaitForChild("PuzzleEconomy"))
local DefinitionBuilder = require(sharedFolder:WaitForChild("board"):WaitForChild("DefinitionBuilder"))
local BoardGenerator = require(sharedFolder:WaitForChild("board"):WaitForChild("BoardGenerator"))
local utilFolder = script.Parent.Parent.Parent:WaitForChild("utils")
local WordPathUtils = require(utilFolder:WaitForChild("WordPathUtils"))

local MIN_WORD_FOUND_INTERVAL = 0.12
local MIN_HINT_INTERVAL = 0.12
local MIN_BOARD_CLEAR_INTERVAL = 0.45
local PENDING_CLEAR_WINDOW = 6
local DEFAULT_MODE = "Classic"
local ACTIVE_MODES = {
	Classic = true,
	Tiny = true,
	Mega = true,
	Hardcore = true,
}

local boardCache = {}
local runtimeByUserId = {}
local normalizeWord = WordPathUtils.NormalizeWord
local sanitizePath = WordPathUtils.SanitizePath
local pathsMatch = WordPathUtils.PathsMatch

local function getNow()
	return Workspace.DistributedGameTime
end

local function getRuntime(userId)
	local runtime = runtimeByUserId[userId]
	if runtime then
		return runtime
	end

	runtime = {
		board = nil,
		pendingClear = nil,
		pendingClearExpiresAt = 0,
		lastWordFoundAt = -math.huge,
		lastHintAt = -math.huge,
		lastBoardClearAt = -math.huge,
	}
	runtimeByUserId[userId] = runtime
	return runtime
end

local function normalizeMode(mode)
	local normalized = tostring(mode or DEFAULT_MODE)
	if ACTIVE_MODES[normalized] then
		return normalized
	end

	return DEFAULT_MODE
end

local function getBoardKey(mode, seed)
	return string.format("%s:%d:%d", normalizeMode(mode), 1, seed)
end

local function getBoardInfo(mode, seed)
	seed = math.max(1, math.floor(tonumber(seed) or 1))
	mode = normalizeMode(mode)

	local key = getBoardKey(mode, seed)
	if boardCache[key] then
		return boardCache[key]
	end

	local definition = DefinitionBuilder.BuildDefinition(1, mode, seed)
	if not definition then
		return nil
	end

	local ok, generated = pcall(function()
		return BoardGenerator.generate(definition, seed)
	end)
	if not ok or type(generated) ~= "table" then
		warn(string.format("[BoardValidationService] Failed to generate board %s: %s", key, tostring(generated)))
		return nil
	end
	local gridWidth = math.max(
		1,
		math.floor(tonumber(generated.gridWidth) or tonumber(definition.gridWidth) or tonumber(generated.gridSize) or tonumber(definition.gridSize) or 1)
	)
	local gridHeight = math.max(
		1,
		math.floor(tonumber(generated.gridHeight) or tonumber(definition.gridHeight) or tonumber(generated.gridSize) or tonumber(definition.gridSize) or 1)
	)

	local wordLookup = {}
	local wordPaths = {}
	for _, word in ipairs(generated.words or {}) do
		wordLookup[word] = true
	end
	for _, placedWord in ipairs(generated.placedWords or {}) do
		local normalizedPlacedWord = normalizeWord(placedWord.word)
		local sanitizedPlacedPath = sanitizePath(placedWord.path)
		if normalizedPlacedWord and sanitizedPlacedPath then
			wordPaths[normalizedPlacedWord] = sanitizedPlacedPath
		end
	end

	local boardInfo = {
		key = key,
		mode = mode,
		level = 1,
		seed = seed,
		gridSize = math.max(gridWidth, gridHeight),
		gridWidth = gridWidth,
		gridHeight = gridHeight,
		words = table.clone(generated.words or {}),
		wordLookup = wordLookup,
		wordPaths = wordPaths,
		wordCount = #(generated.words or {}),
	}
	boardCache[key] = boardInfo
	return boardInfo
end

local function getIdentityFromBoardState(boardState)
	if type(boardState) ~= "table" then
		return nil
	end

	local mode = DEFAULT_MODE
	if boardState.mode ~= nil then
		local requestedMode = tostring(boardState.mode)
		if not ACTIVE_MODES[requestedMode] then
			return nil
		end
		mode = requestedMode
	end

	return {
		mode = mode,
		level = 1,
		seed = math.max(1, math.floor(tonumber(boardState.seed) or 1)),
	}
end

local function sameBoardIdentity(left, right)
	local leftIdentity = getIdentityFromBoardState(left)
	local rightIdentity = getIdentityFromBoardState(right)
	if not leftIdentity or not rightIdentity then
		return false
	end

	return leftIdentity.mode == rightIdentity.mode
		and leftIdentity.seed == rightIdentity.seed
end

local function serializeWordSet(wordSet, orderedWords)
	local serialized = {}

	for _, word in ipairs(orderedWords or {}) do
		if wordSet[word] then
			table.insert(serialized, word)
		end
	end

	return serialized
end

local function buildWordSet(boardInfo, words)
	local result = {}
	local count = 0

	for _, word in ipairs(words or {}) do
		if boardInfo.wordLookup[word] and not result[word] then
			result[word] = true
			count += 1
		end
	end

	return result, count
end

local function countWordSet(wordSet)
	local count = 0
	for _ in pairs(wordSet or {}) do
		count += 1
	end
	return count
end

local function buildHintSet(boardInfo, words, foundWords)
	local result = {}

	for _, word in ipairs(words or {}) do
		if boardInfo.wordLookup[word] and not foundWords[word] then
			result[word] = true
		end
	end

	return result
end

local function buildValidatedBoardState(session, sourceBoardState)
	sourceBoardState = type(sourceBoardState) == "table" and sourceBoardState or {}

	local puzzlesCleared = math.max(0, math.floor(tonumber(sourceBoardState.puzzlesCleared) or 0))
	local sessionScore = math.max(0, math.floor(tonumber(sourceBoardState.sessionScore) or 0))
	local streak = math.max(0, math.floor(tonumber(sourceBoardState.streak) or 0))

	return {
		mode = session.mode,
		level = 1,
		seed = session.seed,
		foundWords = serializeWordSet(session.foundWords, session.boardInfo.words),
		hintedWords = serializeWordSet(session.hintedWords, session.boardInfo.words),
		hintUses = math.max(0, math.floor(tonumber(session.hintUses) or 0)),
		sessionScore = sessionScore,
		puzzlesCleared = puzzlesCleared,
		streak = streak,
	}
end

local function getEarliestStartedAtServerTime(...)
	local earliest = nil

	for index = 1, select("#", ...) do
		local boardState = select(index, ...)
		local candidate = tonumber(type(boardState) == "table" and boardState.startedAtServerTime or nil)
		if candidate and candidate >= 0 then
			earliest = earliest and math.min(earliest, candidate) or candidate
		end
	end

	return earliest
end

local function applyHydrationToSession(session, hydrationState, storedBoardState, incomingBoardState)
	if not session or type(hydrationState) ~= "table" or not session.boardInfo then
		return
	end

	local boardInfo = session.boardInfo
	local hydratedFoundWords = buildWordSet(boardInfo, hydrationState.foundWords)
	local mergedHintWords = {}

	for word in pairs(session.foundWords or {}) do
		hydratedFoundWords[word] = true
	end

	session.foundWords = hydratedFoundWords
	session.foundCount = countWordSet(session.foundWords)

	for word in pairs(session.hintedWords or {}) do
		table.insert(mergedHintWords, word)
	end
	for _, word in ipairs(hydrationState.hintedWords or {}) do
		table.insert(mergedHintWords, word)
	end

	session.hintedWords = buildHintSet(boardInfo, mergedHintWords, session.foundWords)
	session.hintUses = math.max(
		math.floor(tonumber(session.hintUses) or 0),
		math.floor(tonumber(hydrationState.hintUses) or 0)
	)

	local hydratedStartedAt = getEarliestStartedAtServerTime(hydrationState, storedBoardState, incomingBoardState)
	if hydratedStartedAt then
		session.boardStartedAt = math.min(session.boardStartedAt or hydratedStartedAt, hydratedStartedAt)
	end

	session.justCompleted = session.foundCount >= boardInfo.wordCount
end

local function createBoardSession(boardInfo, hydrationState)
	local foundWords, foundCount = buildWordSet(boardInfo, hydrationState and hydrationState.foundWords or nil)
	local hintedWords = buildHintSet(boardInfo, hydrationState and hydrationState.hintedWords or nil, foundWords)
	local justCompleted = foundCount >= boardInfo.wordCount
	local boardStartedAt = getEarliestStartedAtServerTime(hydrationState) or getNow()
	local hintUses = math.max(0, math.floor(tonumber(hydrationState and hydrationState.hintUses) or 0))

	return {
		key = boardInfo.key,
		mode = boardInfo.mode,
		level = 1,
		seed = boardInfo.seed,
		boardInfo = boardInfo,
		foundWords = foundWords,
		foundCount = foundCount,
		hintedWords = hintedWords,
		hintUses = hintUses,
		boardStartedAt = boardStartedAt,
		justCompleted = justCompleted,
		clearAwarded = false,
	}
end

local function getBoardProgressCount(boardState, fieldName)
	if type(boardState) ~= "table" or type(boardState[fieldName]) ~= "table" then
		return 0
	end

	return #boardState[fieldName]
end

local function getHydrationState(storedBoardState, incomingBoardState)
	if sameBoardIdentity(storedBoardState, incomingBoardState) then
		local storedFoundCount = getBoardProgressCount(storedBoardState, "foundWords")
		local incomingFoundCount = getBoardProgressCount(incomingBoardState, "foundWords")
		if storedFoundCount > incomingFoundCount then
			return storedBoardState
		end
		if incomingFoundCount > storedFoundCount then
			return incomingBoardState
		end

		local storedHintCount = getBoardProgressCount(storedBoardState, "hintedWords")
		local incomingHintCount = getBoardProgressCount(incomingBoardState, "hintedWords")
		if storedHintCount >= incomingHintCount then
			return storedBoardState
		end

		return incomingBoardState
	end

	if getIdentityFromBoardState(incomingBoardState) then
		return incomingBoardState
	end

	if getIdentityFromBoardState(storedBoardState) then
		return storedBoardState
	end

	return nil
end

local function setPendingClear(runtime, session)
	if not session or session.clearAwarded or not session.justCompleted then
		return
	end

	runtime.pendingClear = session
	runtime.pendingClearExpiresAt = getNow() + PENDING_CLEAR_WINDOW
end

local function prunePendingClear(runtime)
	if runtime.pendingClear and getNow() > (runtime.pendingClearExpiresAt or 0) then
		runtime.pendingClear = nil
		runtime.pendingClearExpiresAt = 0
	end
end

local function ensureBoardSession(player, storedBoardState, incomingBoardState)
	local runtime = getRuntime(player.UserId)
	prunePendingClear(runtime)

	local identity = getIdentityFromBoardState(incomingBoardState) or getIdentityFromBoardState(storedBoardState)
	if not identity then
		runtime.board = nil
		return nil
	end

	local boardInfo = getBoardInfo(identity.mode, identity.seed)
	if not boardInfo then
		return nil
	end

	local hydrationState = getHydrationState(storedBoardState, incomingBoardState)
	local hydratedStartedAt = getEarliestStartedAtServerTime(storedBoardState, incomingBoardState, hydrationState)

	if runtime.board and runtime.board.key == boardInfo.key then
		applyHydrationToSession(runtime.board, hydrationState, storedBoardState, incomingBoardState)
		if hydratedStartedAt then
			runtime.board.boardStartedAt = math.min(runtime.board.boardStartedAt or hydratedStartedAt, hydratedStartedAt)
		end
		if runtime.board.justCompleted then
			setPendingClear(runtime, runtime.board)
		end
		return runtime.board
	end

	setPendingClear(runtime, runtime.board)
	runtime.board = createBoardSession(boardInfo, hydrationState)
	if hydratedStartedAt then
		runtime.board.boardStartedAt = math.min(runtime.board.boardStartedAt or hydratedStartedAt, hydratedStartedAt)
	end
	if runtime.board.justCompleted then
		setPendingClear(runtime, runtime.board)
	end
	return runtime.board
end

local function calculatePuzzleReward(session)
	local reward = (session.boardInfo.gridSize * 0.45) + (session.boardInfo.wordCount * 0.9)
	return PuzzleEconomy.ScaleCompletionReward(math.max(1, math.floor(reward + 0.5)))
end

local function getMinimumBoardClearAge(session)
	return math.max(2.5, session.boardInfo.wordCount * 0.32)
end

function BoardValidationService.ProcessBoardState(player, storedBoardState, incomingBoardState)
	local session = ensureBoardSession(player, storedBoardState, incomingBoardState)
	if not session then
		return nil
	end

	return buildValidatedBoardState(session, incomingBoardState or storedBoardState)
end

function BoardValidationService.ValidateWordFound(player, storedBoardState, incomingBoardState, claimedWord, claimedPath)
	local runtime = getRuntime(player.UserId)
	local now = getNow()
	if now - runtime.lastWordFoundAt < MIN_WORD_FOUND_INTERVAL then
		return {
			accepted = false,
		}
	end
	runtime.lastWordFoundAt = now

	local session = ensureBoardSession(player, storedBoardState, incomingBoardState)
	if not session then
		return {
			accepted = false,
		}
	end

	local word = normalizeWord(claimedWord)
	if not word or not session.boardInfo.wordLookup[word] or session.foundWords[word] then
		return {
			accepted = false,
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
		}
	end
	if not pathsMatch(session.boardInfo.wordPaths and session.boardInfo.wordPaths[word], claimedPath) then
		return {
			accepted = false,
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
		}
	end

	session.foundWords[word] = true
	session.foundCount += 1
	session.hintedWords[word] = nil
	session.justCompleted = session.foundCount >= session.boardInfo.wordCount

	if session.justCompleted then
		setPendingClear(runtime, session)
	end

	return {
		accepted = true,
		word = word,
		mode = session.mode,
		level = 1,
		boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
	}
end

function BoardValidationService.ValidateHintUsed(player, storedBoardState, incomingBoardState, claimedWord)
	local runtime = getRuntime(player.UserId)
	local now = getNow()
	if now - runtime.lastHintAt < MIN_HINT_INTERVAL then
		return {
			accepted = false,
		}
	end
	runtime.lastHintAt = now

	local session = ensureBoardSession(player, storedBoardState, incomingBoardState)
	if not session then
		return {
			accepted = false,
		}
	end

	local word = normalizeWord(claimedWord)
	if not word or not session.boardInfo.wordLookup[word] or session.foundWords[word] then
		return {
			accepted = false,
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
		}
	end

	session.hintedWords[word] = true
	session.hintUses = math.max(0, math.floor(tonumber(session.hintUses) or 0) + 1)

	return {
		accepted = true,
		word = word,
		mode = session.mode,
		level = 1,
		boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
	}
end

function BoardValidationService.ValidateBoardCleared(player, storedBoardState, incomingBoardState)
	local runtime = getRuntime(player.UserId)
	local now = getNow()
	if now - runtime.lastBoardClearAt < MIN_BOARD_CLEAR_INTERVAL then
		return {
			accepted = false,
			reason = "rate_limited",
		}
	end
	runtime.lastBoardClearAt = now

	prunePendingClear(runtime)

	local activeSession = ensureBoardSession(player, storedBoardState, incomingBoardState)
	local session = activeSession
	if runtime.pendingClear and not runtime.pendingClear.clearAwarded then
		if not activeSession or runtime.pendingClear.key == activeSession.key then
			session = runtime.pendingClear
		end
	end
	if not session then
		return {
			accepted = false,
			reason = "missing_session",
		}
	end

	if not session.justCompleted or session.foundCount < session.boardInfo.wordCount then
		return {
			accepted = false,
			reason = "incomplete",
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
		}
	end

	if now - session.boardStartedAt < getMinimumBoardClearAge(session) then
		return {
			accepted = false,
			reason = "too_fast",
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
		}
	end

	session.clearAwarded = true

	if runtime.pendingClear == session then
		runtime.pendingClear = nil
		runtime.pendingClearExpiresAt = 0
	end
	if runtime.board == session then
		runtime.board = nil
	end

	return {
		accepted = true,
		mode = session.mode,
		level = 1,
		reward = calculatePuzzleReward(session),
		clearTimeMillis = math.max(0, math.floor((now - session.boardStartedAt) * 1000)),
	}
end

function BoardValidationService.ClearBoardState(player)
	local runtime = getRuntime(player.UserId)
	prunePendingClear(runtime)

	if runtime.board then
		setPendingClear(runtime, runtime.board)
		runtime.board = nil
	end
end

function BoardValidationService.ClearPlayer(player)
	if not player then
		return
	end

	runtimeByUserId[player.UserId] = nil
end

function BoardValidationService.GetBoardInfoFromState(boardState)
	local identity = getIdentityFromBoardState(boardState)
	if not identity then
		return nil
	end

	return getBoardInfo(identity.mode, identity.seed)
end

return BoardValidationService
