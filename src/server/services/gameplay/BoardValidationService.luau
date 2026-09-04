local BoardValidationService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("shared")
local PuzzleEconomy = require(sharedFolder:WaitForChild("config"):WaitForChild("PuzzleEconomy"))
local DailyMode = require(sharedFolder:WaitForChild("progression"):WaitForChild("DailyMode"))
local DefinitionBuilder = require(sharedFolder:WaitForChild("board"):WaitForChild("DefinitionBuilder"))
local Levels = require(sharedFolder:WaitForChild("content"):WaitForChild("Levels"))
local BoardGenerator = require(sharedFolder:WaitForChild("board"):WaitForChild("BoardGenerator"))
local TimerRules = require(sharedFolder:WaitForChild("progression"):WaitForChild("TimerRules"))
local utilFolder = script.Parent.Parent.Parent:WaitForChild("utils")
local WordPathUtils = require(utilFolder:WaitForChild("WordPathUtils"))

local MAX_CLASSIC_LEVEL = math.max(1, #Levels)
local LARGE_MODE_GRID_SIZE = 16
local MIN_WORD_FOUND_INTERVAL = 0.12
local MIN_HINT_INTERVAL = 0.12
local MIN_BOARD_CLEAR_INTERVAL = 0.45
local PENDING_CLEAR_WINDOW = 6

local MODE_CONFIGS = {
	Classic = {
		rewardScale = 1,
		disableHints = false,
	},
	Themed = {
		rewardScale = 1.1,
		disableHints = false,
	},
	Freeplay = {
		rewardScale = 1.15,
		disableHints = false,
	},
	Backwards = {
		rewardScale = 1.2,
		disableHints = false,
	},
	Fog = {
		rewardScale = 1.3,
		disableHints = false,
	},
	OneLife = {
		rewardScale = 1.38,
		disableHints = false,
	},
	Mega = {
		rewardScale = 1.92,
		disableHints = false,
	},
	Daily = {
		rewardScale = 2.15,
		disableHints = false,
	},
}

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

local function cloneDefinition(definition)
	return {
		level = definition.level,
		title = definition.title,
		subtitle = definition.subtitle,
		gridSize = definition.gridSize,
		words = table.clone(definition.words or {}),
		directions = table.clone(definition.directions or {}),
		seed = definition.seed,
	}
end

local function normalizeDefinitionWord(word)
	if type(word) ~= "string" then
		return nil
	end

	local normalized = string.upper(word:gsub("%s+", ""))
	if normalized == "" then
		return nil
	end

	return normalized
end

local function expandDefinitionWords(definition, baseIndex, targetCount)
	local words = {}
	local seen = {}

	local function appendWords(sourceWords)
		for _, candidate in ipairs(sourceWords or {}) do
			local normalized = normalizeDefinitionWord(candidate)
			if normalized and not seen[normalized] then
				seen[normalized] = true
				table.insert(words, normalized)
				if #words >= targetCount then
					return true
				end
			end
		end

		return false
	end

	appendWords(definition.words)
	if #words >= targetCount then
		definition.words = words
		return
	end

	for offset = 1, #Levels do
		local nextIndex = baseIndex + offset
		if nextIndex <= MAX_CLASSIC_LEVEL then
			if appendWords(Levels[nextIndex].words) then
				break
			end
		end

		local previousIndex = baseIndex - offset
		if previousIndex >= 1 then
			if appendWords(Levels[previousIndex].words) then
				break
			end
		end

		if nextIndex > MAX_CLASSIC_LEVEL and previousIndex < 1 then
			break
		end
	end

	definition.words = words
end

local function applyModeToPuzzleDefinition(definition, template, level, mode)
	definition.directions = normalizeDirectionsForMode(definition.directions, mode == "Backwards")

	if mode == "OneLife" then
		definition.directions = { "E", "S", "SE", "SW", "W", "N", "NW", "NE" }
	elseif mode == "Mega" then
		definition.directions = { "E", "S", "SE", "SW", "W", "N", "NW", "NE" }
		definition.gridSize = LARGE_MODE_GRID_SIZE
		expandDefinitionWords(definition, level, math.max(18, math.min(#definition.words + 10, 20)))
	elseif mode == "Daily" then
		definition.directions = { "E", "S", "SE", "SW", "W", "N", "NW", "NE" }
		definition.gridSize = LARGE_MODE_GRID_SIZE
		expandDefinitionWords(definition, level, math.max(20, math.min(#definition.words + 12, 22)))
	end
end

local function buildPuzzleDefinition(level, mode)
	return DefinitionBuilder.BuildDefinition(level, mode, 1)
end

local function getBoardKey(mode, level, seed)
	return string.format("%s:%d:%d", tostring(mode), level, seed)
end

local function getBoardInfo(mode, level, seed)
	local modeConfig = MODE_CONFIGS[mode]
	if not modeConfig then
		return nil
	end

	level = math.clamp(math.max(1, math.floor(tonumber(level) or 1)), 1, MAX_CLASSIC_LEVEL)
	seed = math.max(1, math.floor(tonumber(seed) or 1))

	local key = getBoardKey(mode, level, seed)
	if boardCache[key] then
		return boardCache[key]
	end

	local definition = DefinitionBuilder.BuildDefinition(level, mode, seed)
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

	local wordLookup = {}
	local wordPaths = {}
	for _, word in ipairs(generated.words or {}) do
		wordLookup[word] = true
	end
	for _, placedWord in ipairs(generated.placedWords or {}) do
		local normalizedWord = normalizeWord(placedWord.word)
		local sanitizedPath = sanitizePath(placedWord.path)
		if normalizedWord and sanitizedPath then
			wordPaths[normalizedWord] = sanitizedPath
		end
	end

	local boardInfo = {
		key = key,
		mode = mode,
		level = level,
		seed = seed,
		gridSize = math.max(1, math.floor(tonumber(generated.gridSize) or definition.gridSize or 1)),
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

	local mode = type(boardState.mode) == "string" and boardState.mode or nil
	if not MODE_CONFIGS[mode] then
		return nil
	end

	if mode == "Daily" then
		local dailyIdentity = DailyMode.GetDailyIdentity(MAX_CLASSIC_LEVEL)
		local level = math.clamp(math.max(1, math.floor(tonumber(boardState.level) or 1)), 1, MAX_CLASSIC_LEVEL)
		local seed = math.max(1, math.floor(tonumber(boardState.seed) or 1))
		if level ~= dailyIdentity.level or seed ~= dailyIdentity.seed then
			return nil
		end

		return {
			mode = mode,
			level = dailyIdentity.level,
			seed = dailyIdentity.seed,
		}
	end

	return {
		mode = mode,
		level = math.clamp(math.max(1, math.floor(tonumber(boardState.level) or 1)), 1, MAX_CLASSIC_LEVEL),
		seed = math.max(1, math.floor(tonumber(boardState.seed) or 1)),
	}
end

local function sameBoardIdentity(left, right)
	if type(left) ~= "table" or type(right) ~= "table" then
		return false
	end

	return left.mode == right.mode
		and math.floor(tonumber(left.level) or 0) == math.floor(tonumber(right.level) or 0)
		and math.floor(tonumber(left.seed) or 0) == math.floor(tonumber(right.seed) or 0)
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

local function buildHintSet(boardInfo, words, foundWords, mode)
	local modeConfig = MODE_CONFIGS[mode] or MODE_CONFIGS.Classic
	if modeConfig.disableHints then
		return {}
	end

	local result = {}

	for _, word in ipairs(words or {}) do
		if boardInfo.wordLookup[word] and not foundWords[word] then
			result[word] = true
		end
	end

	return result
end

local function clampRemainingTime(session, remainingTime, timeBoostUsed)
	if not session or not session.boardInfo then
		return nil
	end

	local numericRemaining = tonumber(remainingTime)
	if not numericRemaining then
		return nil
	end

	local maxRemaining = TimerRules.GetMaximumRemainingTime(session.boardInfo, session.mode, timeBoostUsed == true)
	return math.clamp(math.max(1, math.floor(numericRemaining)), 1, math.max(1, maxRemaining))
end

local function clampFreezeTimeRemaining(session, freezeTimeRemaining)
	if not session or not session.boardInfo then
		return nil
	end

	local numericRemaining = tonumber(freezeTimeRemaining)
	if not numericRemaining then
		return nil
	end

	local maxRemaining = TimerRules.GetFreezeDuration(
		TimerRules.GetBaseTimeLimit(session.boardInfo, session.mode)
	)
	return math.clamp(numericRemaining, 0, maxRemaining)
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

local function buildValidatedBoardState(session, sourceBoardState)
	sourceBoardState = type(sourceBoardState) == "table" and sourceBoardState or {}

	local puzzlesCleared = math.max(0, math.floor(tonumber(sourceBoardState.puzzlesCleared) or 0))
	local sessionScore = math.max(0, math.floor(tonumber(sourceBoardState.sessionScore) or 0))
	local streak = math.max(0, math.floor(tonumber(sourceBoardState.streak) or 0))
	local timeBoostUsed = sourceBoardState.timeBoostUsed == true
	local freezeTimeUsed = sourceBoardState.freezeTimeUsed == true
	local freezeTimeRemaining = clampFreezeTimeRemaining(session, sourceBoardState.freezeTimeRemaining)
	local startedAtServerTime = math.max(0, tonumber(session.boardStartedAt) or getNow())
	local sourceStartedAtServerTime = tonumber(sourceBoardState.startedAtServerTime)
	local mergedHintWords = {}

	if sourceStartedAtServerTime and sourceStartedAtServerTime >= 0 then
		startedAtServerTime = math.min(startedAtServerTime, sourceStartedAtServerTime)
	end

	for word in pairs(session.hintedWords or {}) do
		table.insert(mergedHintWords, word)
	end
	for _, word in ipairs(sourceBoardState.hintedWords or {}) do
		table.insert(mergedHintWords, word)
	end

	local hintedWords = buildHintSet(session.boardInfo, mergedHintWords, session.foundWords, session.mode)

	session.hintedWords = hintedWords

	return {
		mode = session.mode,
		level = session.level,
		seed = session.seed,
		foundWords = serializeWordSet(session.foundWords, session.boardInfo.words),
		hintedWords = serializeWordSet(session.hintedWords, session.boardInfo.words),
		remainingTime = clampRemainingTime(session, sourceBoardState.remainingTime, timeBoostUsed),
		timeBoostUsed = timeBoostUsed,
		freezeTimeUsed = freezeTimeUsed,
		freezeTimeRemaining = freezeTimeRemaining,
		sessionScore = sessionScore,
		puzzlesCleared = puzzlesCleared,
		streak = streak,
		hintUses = math.max(0, math.floor(tonumber(session.hintUses) or 0)),
		startedAtServerTime = startedAtServerTime,
	}
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

	session.hintedWords = buildHintSet(boardInfo, mergedHintWords, session.foundWords, session.mode)
	session.hintUses = math.max(
		math.floor(tonumber(session.hintUses) or 0),
		math.floor(tonumber(hydrationState.hintUses) or 0)
	)
	do
		local hydratedStartedAt = getEarliestStartedAtServerTime(hydrationState, storedBoardState, incomingBoardState)
		if hydratedStartedAt then
			session.boardStartedAt = math.min(session.boardStartedAt or hydratedStartedAt, hydratedStartedAt)
		end
	end
	session.justCompleted = session.foundCount >= boardInfo.wordCount
end

local function createBoardSession(boardInfo, hydrationState)
	local foundWords, foundCount = buildWordSet(boardInfo, hydrationState and hydrationState.foundWords or nil)
	local hintedWords = buildHintSet(boardInfo, hydrationState and hydrationState.hintedWords or nil, foundWords, boardInfo.mode)
	local justCompleted = foundCount >= boardInfo.wordCount
	local boardStartedAt = getEarliestStartedAtServerTime(hydrationState) or getNow()
	local hintUses = math.max(0, math.floor(tonumber(hydrationState and hydrationState.hintUses) or 0))

	return {
		key = boardInfo.key,
		mode = boardInfo.mode,
		level = boardInfo.level,
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

local function getHydrationState(storedBoardState, incomingBoardState)
	local function getBoardProgressCount(boardState, fieldName)
		if type(boardState) ~= "table" or type(boardState[fieldName]) ~= "table" then
			return 0
		end

		return #boardState[fieldName]
	end

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

	local boardInfo = getBoardInfo(identity.mode, identity.level, identity.seed)
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
	local modeConfig = MODE_CONFIGS[session.mode] or MODE_CONFIGS.Classic
	local reward = (session.boardInfo.gridSize * 0.45 + session.boardInfo.wordCount * 0.9) * modeConfig.rewardScale
	return PuzzleEconomy.ScaleCompletionReward(math.max(1, math.floor(reward + 0.5)))
end

local function getMinimumBoardClearAge(session)
	return math.max(1.5, session.boardInfo.wordCount * 0.35)
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
		level = session.level,
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

	local modeConfig = MODE_CONFIGS[session.mode] or MODE_CONFIGS.Classic
	if modeConfig.disableHints then
		return {
			accepted = false,
			boardState = buildValidatedBoardState(session, incomingBoardState or storedBoardState),
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
		level = session.level,
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
		level = session.level,
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

	return getBoardInfo(identity.mode, identity.level, identity.seed)
end

return BoardValidationService
