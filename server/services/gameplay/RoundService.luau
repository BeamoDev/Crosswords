-- Server-authoritative round state. The client only submits two endpoints after an
-- input release; this service derives the path and decides whether it matches an
-- unfound canonical target. Completion is inferred here and can be applied once.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = assert(ReplicatedStorage:WaitForChild("shared", 10), "Word Search shared folder is missing")
local configFolder = assert(shared:WaitForChild("config", 10), "Word Search config folder is missing")
local GameConfig = require(assert(configFolder:WaitForChild("GameConfig", 10), "Word Search GameConfig is missing"))

local RoundService = {}

local services = nil
local roundsByUserId = {}

local function nowClock()
	return os.clock()
end

local function nowUnixMillis()
	return DateTime.now().UnixTimestampMillis
end

local function sign(value)
	if value < 0 then
		return -1
	elseif value > 0 then
		return 1
	end
	return 0
end

local function clonePath(path)
	local result = {}
	for index, cell in ipairs(path or {}) do
		result[index] = { row = cell.row, column = cell.column }
	end
	return result
end

local function pathSignature(path)
	local parts = table.create(#path)
	for index, cell in ipairs(path) do
		parts[index] = string.format("%d:%d", cell.row, cell.column)
	end
	return table.concat(parts, "|")
end

local function reversePath(path)
	local result = table.create(#path)
	for index = #path, 1, -1 do
		table.insert(result, path[index])
	end
	return result
end

local function buildSelectionPath(startCell, endCell, width, height)
	local rowDelta = endCell.row - startCell.row
	local columnDelta = endCell.column - startCell.column
	local rowDistance = math.abs(rowDelta)
	local columnDistance = math.abs(columnDelta)

	if rowDistance == 0 and columnDistance == 0 then
		return nil
	end
	if rowDistance ~= 0 and columnDistance ~= 0 and rowDistance ~= columnDistance then
		return nil
	end

	local steps = math.max(rowDistance, columnDistance)
	if steps + 1 > math.max(GameConfig.Gameplay.MaxWordLength, width, height) then
		return nil
	end

	local rowStep = sign(rowDelta)
	local columnStep = sign(columnDelta)
	local path = table.create(steps + 1)
	for offset = 0, steps do
		local row = startCell.row + rowStep * offset
		local column = startCell.column + columnStep * offset
		if row < 1 or row > height or column < 1 or column > width then
			return nil
		end
		table.insert(path, { row = row, column = column })
	end

	return path
end

local function makeTargetLookup(compiled)
	local lookup = {}
	for index, placedWord in ipairs(compiled.placedWords or {}) do
		local path = clonePath(placedWord.path)
		local target = {
			id = tostring(placedWord.id or index),
			word = tostring(placedWord.word or compiled.words[index] or ""),
			path = path,
		}
		local forwardSignature = pathSignature(path)
		local reverseSignature = pathSignature(reversePath(path))
		assert(not lookup[forwardSignature], "Validated puzzle contains a duplicate physical target path")
		assert(not lookup[reverseSignature], "Validated puzzle contains a duplicate physical target path")
		lookup[forwardSignature] = target
		lookup[reverseSignature] = target
	end
	return lookup
end

local function getRound(player, roundId)
	local round = player and roundsByUserId[player.UserId] or nil
	if not round or round.id ~= roundId then
		return nil
	end
	return round
end

local function getElapsedSeconds(round)
	local endClock = round.pausedAt or nowClock()
	return math.max(0, endClock - round.startedAtClock - round.totalPausedSeconds)
end

local function buildProgress(round)
	return {
		foundCount = round.foundCount,
		totalWords = #round.compiled.words,
		mistakes = round.mistakes,
		hintsUsed = round.hintsUsed,
		elapsedMs = math.floor(getElapsedSeconds(round) * 1000 + 0.5),
		paused = round.pausedAt ~= nil,
	}
end

local function runRoundAction(round, callback)
	if round.actionPending then
		return {
			success = false,
			code = "action_pending",
			message = "Another round action is still being saved.",
			progress = buildProgress(round),
		}
	end

	round.actionPending = true
	local ok, response = xpcall(callback, debug.traceback)
	round.actionPending = false
	if not ok then
		error(response, 0)
	end
	return response
end

local function currentSnapshot(player)
	if services.DataService.IsReady(player) then
		return services.DataService.GetSnapshot(player)
	end
	return nil
end

local function buildRewardContext(round)
	return {
		completionId = round.id,
		mode = round.context.mode,
		levelId = round.context.levelId,
		sourceLevelId = round.context.sourceLevelId,
		levelIndex = round.context.levelIndex,
		difficulty = round.context.difficulty,
		dailyDayStamp = round.context.dailyDayStamp,
		elapsedMs = math.floor(getElapsedSeconds(round) * 1000 + 0.5),
		timeLimit = round.context.timeLimit,
		mistakes = round.mistakes,
		hintsUsed = round.hintsUsed,
		pauseCount = round.pauseCount,
		wordCount = #round.compiled.words,
	}
end

local function applyCompletion(player, round)
	local rewardContext = round.pendingRewardContext or buildRewardContext(round)
	round.pendingRewardContext = rewardContext
	round.completing = true
	local callOk, applied, rewardResult, rewardError = pcall(services.RewardService.CalculateAndApply, player, rewardContext)
	round.completing = false
	if not callOk then
		error(applied, 0)
	end
	if not applied then
		return false, nil, rewardError
	end

	round.completed = true
	round.pendingRewardContext = nil
	round.completionResult = rewardResult
	round.completionSnapshot = type(rewardResult) == "table" and rewardResult.snapshot or currentSnapshot(player)
	return true, rewardResult, nil
end

function RoundService.Init(options)
	assert(type(options) == "table", "RoundService.Init requires dependencies")
	assert(options.DataService, "RoundService requires DataService")
	assert(options.PuzzleService, "RoundService requires PuzzleService")
	assert(options.RewardService, "RoundService requires RewardService")
	assert(options.DailyPuzzleService, "RoundService requires DailyPuzzleService")
	services = options
end

function RoundService.Start(player, request)
	if not services or not services.DataService.IsReady(player) then
		return { success = false, code = "data_not_ready", message = "Player data is not ready." }
	end
	local existingRound = roundsByUserId[player.UserId]
	if existingRound and (existingRound.actionPending or existingRound.completing) then
		return { success = false, code = "round_busy", message = "The current round is still saving. Please retry." }
	end

	local snapshot = services.DataService.GetSnapshot(player)
	local dailyIdentity = services.DailyPuzzleService.GetIdentity()
	local puzzleBundle, puzzleError = services.PuzzleService.Create(player, request, snapshot, dailyIdentity)
	if not puzzleBundle then
		return { success = false, code = "puzzle_unavailable", message = puzzleError }
	end

	local roundId = HttpService:GenerateGUID(false)
	local round = {
		id = roundId,
		player = player,
		compiled = puzzleBundle.compiled,
		context = puzzleBundle.context,
		targetLookup = makeTargetLookup(puzzleBundle.compiled),
		found = {},
		hinted = {},
		hintReceipts = {},
		foundCount = 0,
		mistakes = 0,
		hintsUsed = 0,
		startedAtClock = nowClock(),
		startedAtUnixMs = nowUnixMillis(),
		totalPausedSeconds = 0,
		pausedAt = nil,
		lastSelectionAt = -math.huge,
		lastHintAt = -math.huge,
		lastPauseAt = -math.huge,
		actionPending = false,
		pauseCount = 0,
		completing = false,
		completed = false,
	}
	roundsByUserId[player.UserId] = round

	local publicRound = puzzleBundle.public
	publicRound.roundId = roundId
	publicRound.mode = request.mode
	publicRound.levelId = puzzleBundle.context.levelId
	publicRound.sourceLevelId = puzzleBundle.context.sourceLevelId
	publicRound.startedAtUnixMs = round.startedAtUnixMs
	publicRound.dailyDayStamp = puzzleBundle.context.dailyDayStamp

	return {
		success = true,
		round = publicRound,
		progress = buildProgress(round),
		snapshot = snapshot,
	}
end

function RoundService.SubmitSelection(player, request)
	local round = getRound(player, request.roundId)
	if not round then
		return { success = false, code = "round_not_found", message = "That round is no longer active." }
	end
	return runRoundAction(round, function()
		if round.completed then
			local refreshedSnapshot = currentSnapshot(player) or round.completionSnapshot
			local refreshedCompletion = round.completionResult
			if type(refreshedCompletion) == "table" then
				refreshedCompletion = table.clone(refreshedCompletion)
				refreshedCompletion.snapshot = refreshedSnapshot
			end
			return {
				success = true,
				result = "complete",
				completed = true,
				completion = refreshedCompletion,
				snapshot = refreshedSnapshot,
				progress = buildProgress(round),
			}
		end
		if round.completing then
			return { success = false, code = "round_complete", progress = buildProgress(round) }
		end
		if round.pausedAt then
			return { success = false, code = "round_paused", progress = buildProgress(round) }
		end

		local now = nowClock()
		local minimumInterval = 1 / math.max(1, GameConfig.Gameplay.MaxSelectionRate)
		if now - round.lastSelectionAt < minimumInterval then
			return { success = false, code = "rate_limited", progress = buildProgress(round) }
		end
		round.lastSelectionAt = now

		local path = buildSelectionPath(
			request.startCell,
			request.endCell,
			round.compiled.width,
			round.compiled.height
		)
		if not path then
			round.mistakes = math.min(9999, round.mistakes + 1)
			return { success = true, result = "incorrect", progress = buildProgress(round) }
		end

		local target = round.targetLookup[pathSignature(path)]
		if not target then
			round.mistakes = math.min(9999, round.mistakes + 1)
			return { success = true, result = "incorrect", progress = buildProgress(round) }
		end
		if round.found[target.id] then
			if round.pendingRewardContext and round.foundCount >= #round.compiled.words then
				local applied, rewardResult, rewardError = applyCompletion(player, round)
				if not applied then
					return {
						success = false,
						code = "reward_failed",
						message = rewardError or "Your result could not be saved. Please retry.",
						progress = buildProgress(round),
					}
				end
				return {
					success = true,
					result = "correct",
					wordId = target.id,
					word = target.word,
					path = clonePath(target.path),
					progress = buildProgress(round),
					completed = true,
					completion = rewardResult,
					snapshot = currentSnapshot(player),
				}
			end
			return {
				success = true,
				result = "duplicate",
				word = target.word,
				path = clonePath(target.path),
				progress = buildProgress(round),
			}
		end

		local recorded, recordError = services.DataService.RecordWordFound(player)
		if not recorded then
			local recordMessage = tostring(recordError or "Your progress is busy. Please retry the word.")
			local recordCode = string.find(string.lower(recordMessage), "busy", 1, true) and "profile_busy" or "data_unavailable"
			return {
				success = false,
				code = recordCode,
				message = recordMessage,
				progress = buildProgress(round),
			}
		end
		if getRound(player, request.roundId) ~= round then
			return { success = false, code = "round_not_found", message = "That round is no longer active." }
		end
		round.found[target.id] = true
		round.foundCount += 1

		local response = {
			success = true,
			result = "correct",
			wordId = target.id,
			word = target.word,
			path = clonePath(target.path),
			progress = buildProgress(round),
		}

		if round.foundCount < #round.compiled.words then
			return response
		end

		local applied, rewardResult, rewardError = applyCompletion(player, round)
		if not applied then
			response.success = false
			response.code = "reward_failed"
			response.message = rewardError or "Your result could not be saved. Please retry the final word."
			return response
		end

		response.completed = true
		response.completion = rewardResult
		response.snapshot = currentSnapshot(player)
		return response
	end)
end

function RoundService.RequestHint(player, request)
	local round = getRound(player, request.roundId)
	if not round then
		return { success = false, code = "round_not_found", message = "That round is no longer active." }
	end
	return runRoundAction(round, function()
		local cachedResponse = round.hintReceipts[request.requestId]
		if cachedResponse then
			local refreshedResponse = table.clone(cachedResponse)
			refreshedResponse.progress = buildProgress(round)
			refreshedResponse.snapshot = currentSnapshot(player) or cachedResponse.snapshot
			return refreshedResponse
		end
		if round.completed or round.completing or round.pausedAt then
			return { success = false, code = round.pausedAt and "round_paused" or "round_complete" }
		end

		local now = nowClock()
		if now - round.lastHintAt < GameConfig.Gameplay.HintCooldownSeconds then
			return { success = false, code = "rate_limited" }
		end
		round.lastHintAt = now

		local target = nil
		for _, placedWord in ipairs(round.compiled.placedWords or {}) do
			local id = tostring(placedWord.id or placedWord.word)
			if not round.found[id] and not round.hinted[id] then
				target = placedWord
				break
			end
		end
		if not target then
			return { success = false, code = "no_hint_target", message = "Every remaining word already has a hint." }
		end

		local spent, spendResult = services.DataService.SpendHint(player)
		if not spent then
			local spendMessage = tostring(spendResult or "")
			local noHints = spendMessage == "No hints available."
			local spendCode = noHints and "no_hints"
				or (string.find(string.lower(spendMessage), "busy", 1, true) and "profile_busy" or "data_unavailable")
			return {
				success = false,
				code = spendCode,
				message = noHints and "You do not have any hints left." or (spendMessage ~= "" and spendMessage or "Your progress is busy. Please retry."),
				snapshot = currentSnapshot(player),
			}
		end
		if getRound(player, request.roundId) ~= round then
			return { success = false, code = "round_not_found", message = "That round is no longer active." }
		end

		local targetId = tostring(target.id or target.word)
		round.hinted[targetId] = true
		round.hintsUsed += 1
		local firstCell = target.path and target.path[1] or nil

		local response = {
			success = true,
			word = target.word,
			cell = firstCell and { row = firstCell.row, column = firstCell.column } or nil,
			progress = buildProgress(round),
			snapshot = type(spendResult) == "table" and spendResult or currentSnapshot(player),
		}
		round.hintReceipts[request.requestId] = response
		return response
	end)
end

function RoundService.SetPaused(player, request)
	local round = getRound(player, request.roundId)
	if not round or round.completed then
		return { success = false, code = "round_not_found" }
	end
	if round.actionPending or round.completing then
		return { success = false, code = "action_pending", progress = buildProgress(round) }
	end

	local now = nowClock()
	if now - round.lastPauseAt < GameConfig.Gameplay.PauseCooldownSeconds then
		return { success = false, code = "rate_limited", progress = buildProgress(round) }
	end
	round.lastPauseAt = now

	if request.paused and not round.pausedAt then
		round.pausedAt = now
		round.pauseCount += 1
	elseif not request.paused and round.pausedAt then
		round.totalPausedSeconds += math.max(0, now - round.pausedAt)
		round.pausedAt = nil
	end

	return { success = true, progress = buildProgress(round) }
end

function RoundService.Abandon(player, roundId)
	local round = player and roundsByUserId[player.UserId] or nil
	if round and (roundId == nil or round.id == roundId) then
		if round.actionPending or round.completing then
			return false
		end
		roundsByUserId[player.UserId] = nil
		return true
	end
	return false
end

function RoundService.ClearPlayer(player)
	if player then
		roundsByUserId[player.UserId] = nil
		if services then
			services.PuzzleService.ClearPlayer(player)
			if type(services.RewardService.ClearPlayer) == "function" then
				services.RewardService.ClearPlayer(player)
			end
		end
	end
end

function RoundService.GetDebugState(player)
	local round = player and roundsByUserId[player.UserId] or nil
	if not round then
		return nil
	end
	return {
		id = round.id,
		foundCount = round.foundCount,
		mistakes = round.mistakes,
		hintsUsed = round.hintsUsed,
		completed = round.completed,
	}
end

return RoundService
