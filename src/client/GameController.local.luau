-- The revamp client is deliberately presentation-only. Puzzle contents, round
-- validity, progression, hints, and rewards are all decided by the server.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 15)
assert(playerGui, "Word Search could not find PlayerGui")

local function waitForChild(parent, name, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 15)
	local child = parent:FindFirstChild(name)
	while not child and os.clock() < deadline do
		task.wait(0.1)
		child = parent:FindFirstChild(name)
	end
	return child
end

local function showStartupFailure(message)
	local previous = playerGui:FindFirstChild("WordSearchStartupFailure")
	if previous then
		previous:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WordSearchStartupFailure"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 10000
	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(5, 28, 67)
	background.BackgroundTransparency = 0.12
	background.BorderSizePixel = 0
	background.Parent = screen
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -48, 0, 160)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = "WORD SEARCH COULD NOT START\n\n" .. tostring(message) .. "\nPlease rejoin after the game finishes updating."
	label.TextColor3 = Color3.fromRGB(245, 246, 250)
	label.TextSize = 20
	label.TextWrapped = true
	label.Parent = background
	screen.Parent = playerGui
end

local function expectChild(parent, name, timeoutSeconds, failureMessage)
	local child = waitForChild(parent, name, timeoutSeconds)
	if not child then
		showStartupFailure(failureMessage)
		error(failureMessage, 0)
	end
	return child
end

local function requireModule(parent, name, failureMessage)
	local moduleScript = expectChild(parent, name, 15, failureMessage)
	if not moduleScript:IsA("ModuleScript") then
		showStartupFailure(failureMessage)
		error(failureMessage, 0)
	end
	local ok, result = pcall(require, moduleScript)
	if not ok then
		showStartupFailure(failureMessage)
		error(failureMessage .. ": " .. tostring(result), 0)
	end
	return result
end

local shared = expectChild(ReplicatedStorage, "shared", 15, "Word Search shared modules were not replicated.")
local configFolder = expectChild(shared, "config", 15, "Word Search config modules were not replicated.")
local GameConfig = requireModule(configFolder, "GameConfig", "Word Search GameConfig is unavailable")
local RemoteConfig = requireModule(configFolder, "RemoteConfig", "Word Search RemoteConfig is unavailable")
local revampFolder = expectChild(script.Parent, "revamp", 15, "Word Search client modules are unavailable.")

local AnimationController = requireModule(revampFolder, "AnimationController", "AnimationController is unavailable")
local AudioController = requireModule(revampFolder, "AudioController", "AudioController is unavailable")
local EnvironmentController = requireModule(revampFolder, "EnvironmentController", "EnvironmentController is unavailable")
local InputController = requireModule(revampFolder, "InputController", "InputController is unavailable")
local UIController = requireModule(revampFolder, "UIController", "UIController is unavailable")

local startupFailure = playerGui:FindFirstChild("WordSearchStartupFailure")
if startupFailure then
	startupFailure:Destroy()
end

local previousHud = playerGui:FindFirstChild("WordSearchRevampHUD")
if previousHud and previousHud:GetAttribute("WordSearchRevampOwned") == true then
	previousHud:Destroy()
end

local animation = AnimationController.new()
local environment = EnvironmentController.new()
local audio = AudioController.new({
	gameConfig = GameConfig,
})
local ui = UIController.new(playerGui, {
	name = "WordSearchRevampHUD",
	gameConfig = GameConfig,
	animationController = animation,
	audioController = audio,
})
local input = InputController.new({
	player = player,
	uiController = ui,
})
input:Bind()

local state = {
	destroyed = false,
	view = "Loading",
	functions = nil,
	events = nil,
	remoteConnectionsBound = false,
	connections = {},
	bootstrapToken = 0,
	roundToken = 0,
	snapshot = nil,
	catalog = nil,
	daily = nil,
	currentRound = nil,
	currentRequest = nil,
	lastCompletedRequest = nil,
	nextRequest = nil,
	progress = nil,
	progressReceivedAt = os.clock(),
	submissionBusy = false,
	hintBusy = false,
	startBusy = false,
	localPaused = false,
	pauseDesired = nil,
	pauseWorkerRunning = false,
	tutorialShown = false,
	pendingSettings = {},
	settingWorkers = {},
}

local loadBootstrap
local startRound
local submitSelection
local renderMenu
local requestHint
local setPauseDesired
local renderLevels
local renderDaily
local goToMenu

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function copyRequest(request)
	return {
		mode = tostring(request and request.mode or "Quick"),
		levelId = request and request.levelId or nil,
	}
end

local function responseMessage(response, fallback)
	if type(response) == "table" and type(response.message) == "string" and response.message ~= "" then
		return response.message
	end
	return fallback
end

local function invoke(name, payload)
	local remote = state.functions and state.functions[name]
	if not remote then
		return false, "The game service is not connected."
	end
	local ok, result = pcall(function()
		if payload == nil then
			return remote:InvokeServer()
		end
		return remote:InvokeServer(payload)
	end)
	if not ok then
		return false, "The server did not respond. Please try again."
	end
	if type(result) ~= "table" then
		return false, "The server returned an invalid response."
	end
	return true, result
end

local function resolveRemotes()
	local folder = waitForChild(ReplicatedStorage, RemoteConfig.FolderName, 15)
	if not folder then
		return false, "The Word Search service did not start in time."
	end

	local functions = {}
	for key, name in pairs(RemoteConfig.Functions) do
		local remote = waitForChild(folder, name, 8)
		if not remote or not remote:IsA("RemoteFunction") then
			return false, "A required game service is unavailable (" .. tostring(name) .. ")."
		end
		functions[key] = remote
	end

	local events = {}
	for key, name in pairs(RemoteConfig.Events) do
		local remote = waitForChild(folder, name, 8)
		if not remote or not remote:IsA("RemoteEvent") then
			return false, "A required game channel is unavailable (" .. tostring(name) .. ")."
		end
		events[key] = remote
	end

	state.functions = functions
	state.events = events
	return true
end

local function getInventoryHints()
	local inventory = state.snapshot and state.snapshot.inventory
	return math.max(0, math.floor(tonumber(inventory and inventory.hints) or 0))
end

local function updateProgress(progress)
	if type(progress) ~= "table" then
		return
	end
	state.progress = progress
	state.progressReceivedAt = os.clock()
	state.localPaused = progress.paused == true
	if state.currentRound then
		ui:UpdateGameStatus({
			timeText = formatTime((tonumber(progress.elapsedMs) or 0) / 1000),
			foundWords = progress.foundCount,
			totalWords = progress.totalWords,
			hintsRemaining = getInventoryHints(),
		})
	end
end

local function applySnapshot(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	state.snapshot = snapshot
	if type(snapshot.settings) == "table" then
		ui:SetSettings(snapshot.settings)
		audio:SetSettings(snapshot.settings)
		environment:SetReducedMotion(snapshot.settings.reducedMotion)
	end
	if type(snapshot.daily) == "table" then
		state.daily = snapshot.daily
	end
	if state.currentRound then
		ui:UpdateGameStatus({ hintsRemaining = getInventoryHints() })
	end
end

local function findCatalogLevel(levelId)
	if not state.catalog or type(state.catalog.levels) ~= "table" then
		return nil, nil
	end
	for index, level in ipairs(state.catalog.levels) do
		if tostring(level.id) == tostring(levelId) then
			return level, index
		end
	end
	return nil, nil
end

local function buildChapterViewModels()
	local catalog = state.catalog or {}
	local snapshot = state.snapshot or {}
	local progression = snapshot.progression or {}
	local unlockedLevel = math.max(1, math.floor(tonumber(progression.unlockedLevel) or 1))
	local savedProgress = type(progression.levelProgress) == "table" and progression.levelProgress or {}
	local levelsByChapter = {}

	for index, source in ipairs(type(catalog.levels) == "table" and catalog.levels or {}) do
		local progress = type(savedProgress[source.id]) == "table" and savedProgress[source.id] or {}
		local stars = math.clamp(math.floor(tonumber(progress.stars) or 0), 0, 3)
		local level = {
			id = source.id,
			index = source.index or index,
			number = source.order or index,
			title = source.title,
			description = source.description,
			difficulty = source.difficulty,
			stars = stars,
			locked = index > unlockedLevel,
			state = index > unlockedLevel and "locked" or (stars > 0 and "completed" or (index == unlockedLevel and "active" or "available")),
		}
		levelsByChapter[source.chapterId] = levelsByChapter[source.chapterId] or {}
		table.insert(levelsByChapter[source.chapterId], level)
	end

	local chapters = {}
	for index, source in ipairs(type(catalog.chapters) == "table" and catalog.chapters or {}) do
		local levels = levelsByChapter[source.id] or {}
		local stars = 0
		local firstCatalogIndex = math.huge
		for _, level in ipairs(levels) do
			stars += level.stars
			firstCatalogIndex = math.min(firstCatalogIndex, tonumber(level.index) or math.huge)
		end
		table.insert(chapters, {
			id = source.id,
			title = source.title,
			description = source.description,
			levels = levels,
			stars = stars,
			totalStars = #levels * 3,
			unlocked = firstCatalogIndex <= unlockedLevel,
			order = source.order or index,
		})
	end
	return chapters
end

renderMenu = function()
	if not state.snapshot then
		loadBootstrap()
		return
	end
	state.view = "Menu"
	local progression = state.snapshot.progression or {}
	local stats = state.snapshot.stats or {}
	local daily = state.snapshot.daily or {}
	local showTutorial = progression.tutorialCompleted ~= true and not state.tutorialShown
	if showTutorial then
		state.tutorialShown = true
	end
	ui:ShowMenu({
		displayName = player.DisplayName,
		rank = progression.rank,
		totalStars = progression.totalStars,
		completedPuzzles = stats.totalPuzzlesCompleted,
		dailyStreak = daily.currentStreak,
		showTutorial = showTutorial,
	})
end

renderLevels = function()
	if not state.snapshot or not state.catalog then
		loadBootstrap()
		return
	end
	state.view = "Levels"
	ui:ShowLevels({
		chapters = buildChapterViewModels(),
		totalStars = state.snapshot.progression and state.snapshot.progression.totalStars or 0,
	})
end

renderDaily = function()
	if not state.snapshot then
		loadBootstrap()
		return
	end
	state.view = "Daily"
	local daily = state.snapshot.daily or state.daily or {}
	local level = select(1, findCatalogLevel(daily.levelId))
	ui:ShowDaily({
		title = level and level.title or "Today's Word Search",
		description = (level and level.description and (level.description .. " ") or "")
			.. "The grid reshuffles each time you play.",
		streak = daily.currentStreak,
		rewardText = daily.completedToday and "Reward claimed" or "+1 Hint and bonus XP",
		secondsUntilReset = daily.resetTimestamp and math.max(0, daily.resetTimestamp - os.time()) or daily.secondsUntilReset,
		completed = daily.completedToday == true,
		available = true,
	})
end

local function abandonCurrentRound(notifyServer)
	local current = state.currentRound
	if notifyServer ~= false and current and state.events and state.events.AbandonRound then
		state.events.AbandonRound:FireServer({ roundId = current.roundId })
	end
	state.roundToken += 1
	state.currentRound = nil
	state.progress = nil
	state.submissionBusy = false
	state.hintBusy = false
	state.localPaused = false
	state.pauseDesired = nil
	input:SetRound(nil)
end

goToMenu = function()
	abandonCurrentRound()
	if state.snapshot then
		renderMenu()
	else
		loadBootstrap()
	end
end

local function computeNextRequest(round)
	local mode = tostring(round.mode or "")
	if mode == "Classic" then
		local _, index = findCatalogLevel(round.levelId or round.sourceLevelId)
		local nextLevel = index and state.catalog and state.catalog.levels and state.catalog.levels[index + 1]
		local unlocked = state.snapshot and state.snapshot.progression and tonumber(state.snapshot.progression.unlockedLevel) or 1
		if nextLevel and (index + 1) <= unlocked then
			return { mode = "Classic", levelId = nextLevel.id }
		end
		return nil
	elseif mode == "Quick" or mode == "Zen" then
		return { mode = mode }
	end
	return nil
end

local function showCompletion(response, roundToken)
	local completion = type(response.completion) == "table" and response.completion or {}
	local progress = state.progress or {}
	state.lastCompletedRequest = copyRequest(state.currentRequest)
	if response.snapshot then
		applySnapshot(response.snapshot)
	elseif type(completion.snapshot) == "table" then
		applySnapshot(completion.snapshot)
	end
	state.nextRequest = computeNextRequest(state.currentRound or {})
	input:SetRound(nil)
	ui:SetInputEnabled(false)
	local rewardText
	if completion.unranked == true then
		rewardText = "No ranked reward"
	elseif completion.applied == false then
		rewardText = "Already saved"
	else
		rewardText = "+" .. tostring(math.max(0, math.floor(tonumber(completion.xp) or 0))) .. " XP"
		if (tonumber(completion.hintReward) or 0) > 0 then
			rewardText ..= "  +" .. tostring(math.floor(completion.hintReward)) .. " Hint"
		end
	end
	task.delay(0.38, function()
		if state.destroyed or state.roundToken ~= roundToken or not state.currentRound then
			return
		end
		ui:ShowResults({
			subtitle = completion.unranked == true and (completion.message or "This solve was too fast to rank.") or nil,
			time = (tonumber(completion.elapsedMs) or tonumber(progress.elapsedMs) or 0) / 1000,
			wordsFound = progress.foundCount,
			totalWords = progress.totalWords,
			hintsUsed = completion.hintsUsed or progress.hintsUsed,
			mistakes = completion.mistakes or progress.mistakes,
			stars = completion.stars,
			rewardText = rewardText,
			hasNext = state.nextRequest ~= nil,
		})
	end)
end

submitSelection = function(selection, metadata)
	local current = state.currentRound
	if not current or state.submissionBusy or state.localPaused or current.completed then
		return
	end
	-- InputController snaps the preview to an axis or a true 45-degree diagonal.
	-- Submit that displayed path's endpoints rather than the raw pointer endpoint.
	local startCell = selection[1] or (metadata and metadata.startCell)
	local endCell = selection[#selection] or (metadata and metadata.endCell)
	if not startCell or not endCell then
		return
	end

	state.submissionBusy = true
	ui:SetInputEnabled(false)
	local token = state.roundToken
	local roundId = current.roundId
	task.spawn(function()
		local transportOk, response = invoke("SubmitSelection", {
			roundId = roundId,
			startCell = { row = startCell.row, column = startCell.column },
			endCell = { row = endCell.row, column = endCell.column },
		})
		if state.destroyed or token ~= state.roundToken or not state.currentRound then
			return
		end
		state.submissionBusy = false
		if not transportOk then
			ui:ShowToast(response, "error")
			ui:SetInputEnabled(true)
			return
		end

		updateProgress(response.progress)
		if response.snapshot then
			applySnapshot(response.snapshot)
		end
		local resultKind = response.result
		if resultKind == "correct" or resultKind == "incorrect" or resultKind == "duplicate" then
			ui:ApplySelectionResult({
				accepted = resultKind == "correct" or resultKind == "duplicate",
				duplicate = resultKind == "duplicate",
				cells = response.path or selection,
				word = response.word,
				completed = response.completed == true,
				message = resultKind == "correct" and (response.completed and "Puzzle complete!" or nil)
					or (resultKind == "duplicate" and "That word is already complete." or nil),
			})
		end

		if response.completed == true then
			state.currentRound.completed = true
			showCompletion(response, token)
			return
		end
		if response.success ~= true then
			local message = responseMessage(response, "That selection could not be submitted.")
			if response.code == "reward_failed" and resultKind == "correct" then
				message = message .. " Select the final word again to retry safely."
			end
			ui:ShowToast(message, "error", 3.2)
		end
		ui:SetInputEnabled(true)
	end)
end

startRound = function(request)
	if state.startBusy or state.destroyed then
		return
	end
	request = copyRequest(request)
	if state.currentRound then
		-- RoundService.Start replaces the old server round atomically. Only clear
		-- local state here; firing AbandonRound immediately before StartRound adds
		-- an unnecessary cross-remote race to Next/Replay/Restart transitions.
		abandonCurrentRound(false)
	else
		state.roundToken += 1
	end
	state.startBusy = true
	state.view = "Loading"
	local token = state.roundToken
	ui:ShowLoading("Building a fair puzzle...", 0.55)

	task.spawn(function()
		local transportOk, response = invoke("StartRound", request)
		if state.destroyed or token ~= state.roundToken then
			return
		end
		state.startBusy = false
		if not transportOk or response.success ~= true or type(response.round) ~= "table" then
			local message = transportOk and responseMessage(response, "This puzzle could not be started.") or response
			ui:ShowError("PUZZLE UNAVAILABLE", message, function()
				startRound(request)
			end)
			return
		end

		applySnapshot(response.snapshot)
		state.currentRound = response.round
		state.currentRequest = request
		state.nextRequest = nil
		state.view = "Game"
		state.localPaused = false
		updateProgress(response.progress)
		local round = response.round
		round.hintsRemaining = getInventoryHints()
		round.foundWords = response.progress and response.progress.foundCount or 0
		round.timeText = formatTime((response.progress and response.progress.elapsedMs or 0) / 1000)
		round.inputEnabled = true
		ui:ShowGame(round)
		input:SetRound({
			uiController = ui,
			enabled = true,
			minSelectionLength = 2,
			canInteract = function()
				return state.currentRound == round
					and not state.submissionBusy
					and not state.hintBusy
					and not state.localPaused
					and not round.completed
			end,
			onSubmitSelection = function(selection, metadata)
				submitSelection(selection, metadata)
			end,
			onHintRequested = function()
				requestHint()
			end,
			onPauseRequested = function()
				setPauseDesired(true)
				ui:ShowPause()
			end,
		})
		audio:PlayMusic()
	end)
end

requestHint = function()
	local current = state.currentRound
	if not current or current.completed or state.hintBusy or state.submissionBusy or state.localPaused then
		return
	end
	state.hintBusy = true
	ui:SetInputEnabled(false)
	local token = state.roundToken
	local requestId = HttpService:GenerateGUID(false)
	task.spawn(function()
		local transportOk, response
		for attempt = 1, 3 do
			transportOk, response = invoke("RequestHint", { roundId = current.roundId, requestId = requestId })
			if transportOk and response.success == true then
				break
			end
			local retryable = not transportOk
				or (type(response) == "table" and (response.code == "action_pending" or response.code == "rate_limited"))
			if not retryable or attempt >= 3 then
				break
			end
			local rateLimited = type(response) == "table" and response.code == "rate_limited"
			task.wait(rateLimited and 1 or 0.4)
		end
		if state.destroyed or token ~= state.roundToken or not state.currentRound then
			return
		end
		state.hintBusy = false
		if not transportOk or response.success ~= true then
			local message = transportOk and responseMessage(response, "A hint is not available right now.") or response
			ui:ShowToast(message, "error")
			if transportOk and response.snapshot then
				applySnapshot(response.snapshot)
			end
			ui:SetInputEnabled(true)
			return
		end
		applySnapshot(response.snapshot)
		updateProgress(response.progress)
		audio:Play("Hint", { volume = 0.8 })
		if response.cell then
			ui:SetHoveredCell(response.cell, true)
			ui:UpdateSelection({ response.cell })
		end
		ui:ShowToast(tostring(response.word or "The word") .. " starts here.", "info", 2.2)
		task.delay(0.9, function()
			if not state.destroyed and token == state.roundToken and state.currentRound then
				ui:UpdateSelection({})
				ui:SetInputEnabled(true)
			end
		end)
	end)
end

local function pumpPauseRequests()
	if state.pauseWorkerRunning or not state.currentRound then
		return
	end
	state.pauseWorkerRunning = true
	task.spawn(function()
		while not state.destroyed and state.currentRound and state.pauseDesired ~= nil do
			local desired = state.pauseDesired
			state.pauseDesired = nil
			local roundId = state.currentRound.roundId
			local token = state.roundToken
			local transportOk, response
			for attempt = 1, 2 do
				transportOk, response = invoke("SetPaused", { roundId = roundId, paused = desired })
				if transportOk and response.success == true then
					break
				end
				local retryable = not transportOk
					or (type(response) == "table" and (response.code == "rate_limited" or response.code == "action_pending"))
				if not retryable or state.pauseDesired ~= nil then
					break
				end
				task.wait(0.4)
			end
			if state.destroyed or token ~= state.roundToken or not state.currentRound then
				break
			end
			if transportOk and response.success == true then
				updateProgress(response.progress)
				if not desired and state.pauseDesired == nil then
					ui:SetInputEnabled(true)
				end
			else
				local message = transportOk and responseMessage(response, "Pause could not be changed.") or response
				ui:ShowToast(message, "error")
				if not desired then
					state.localPaused = true
					ui:ShowPause({ message = "The server could not resume this puzzle yet." })
				else
					state.localPaused = false
					ui:ClosePause()
					ui:SetInputEnabled(true)
				end
			end
		end
		state.pauseWorkerRunning = false
		if state.pauseDesired ~= nil then
			pumpPauseRequests()
		end
	end)
end

setPauseDesired = function(paused)
	if not state.currentRound or state.currentRound.completed then
		return
	end
	ui:SetInputEnabled(false)
	state.pauseDesired = paused == true
	pumpPauseRequests()
end

local function queueSetting(name, value)
	state.pendingSettings[name] = value == true
	if state.settingWorkers[name] then
		return
	end
	state.settingWorkers[name] = true
	task.spawn(function()
		while not state.destroyed and state.pendingSettings[name] ~= nil do
			local desired = state.pendingSettings[name]
			state.pendingSettings[name] = nil
			local transportOk, response = invoke("UpdateSettings", { name = name, value = desired })
			if transportOk and response.success == true then
				applySnapshot(response.snapshot)
			else
				local message = transportOk and responseMessage(response, "That setting could not be saved.") or response
				ui:ShowToast(message, "error")
				if state.pendingSettings[name] == nil and state.snapshot and state.snapshot.settings then
					ui:SetSettings(state.snapshot.settings)
				end
			end
		end
		state.settingWorkers[name] = nil
	end)
end

local function bindRemoteEvents()
	if state.remoteConnectionsBound or not state.events then
		return
	end
	state.remoteConnectionsBound = true
	table.insert(state.connections, state.events.StateUpdated.OnClientEvent:Connect(function(snapshot)
		if not state.destroyed then
			applySnapshot(snapshot)
		end
	end))
	table.insert(state.connections, state.events.ServerNotice.OnClientEvent:Connect(function(notice)
		if state.destroyed then
			return
		end
		if type(notice) == "table" then
			ui:ShowToast(notice.message or notice.text or "Server update received.", notice.kind or "info", notice.duration)
		else
			ui:ShowToast(tostring(notice), "info")
		end
	end))
end

loadBootstrap = function()
	if state.destroyed then
		return
	end
	state.bootstrapToken += 1
	local token = state.bootstrapToken
	state.view = "Loading"
	ui:ShowLoading("Loading your progress...", 0.2)
	task.spawn(function()
		if not state.functions then
			local connected, connectError = resolveRemotes()
			if state.destroyed or token ~= state.bootstrapToken then
				return
			end
			if not connected then
				if not state.destroyed and token == state.bootstrapToken then
					ui:ShowError("CONNECTION ERROR", connectError, loadBootstrap)
				end
				return
			end
			bindRemoteEvents()
		end
		if state.destroyed or token ~= state.bootstrapToken then
			return
		end
		ui:ShowLoading("Validating your save...", 0.65)
		local transportOk, response = invoke("GetBootstrap")
		if state.destroyed or token ~= state.bootstrapToken then
			return
		end
		if not transportOk or response.success ~= true then
			local message = transportOk and responseMessage(response, "Your progress could not be loaded safely.") or response
			ui:ShowError("SAVE UNAVAILABLE", message, loadBootstrap)
			return
		end
		state.catalog = response.catalog
		state.daily = response.daily
		applySnapshot(response.snapshot)
		renderMenu()
	end)
end

ui:SetCallbacks({
	onPlay = function()
		startRound({ mode = "Quick" })
	end,
	onLevels = renderLevels,
	onDaily = renderDaily,
	onBack = function()
		-- The view owns a built-in fallback navigation call after this callback.
		-- Deferring ensures the fallback cannot overwrite real profile values.
		task.defer(renderMenu)
	end,
	onDailyPlay = function()
		startRound({ mode = "Daily" })
	end,
	onLevelSelected = function(levelId)
		startRound({ mode = "Classic", levelId = tostring(levelId) })
	end,
	onPause = function()
		setPauseDesired(true)
	end,
	onResume = function()
		setPauseDesired(false)
	end,
	onHint = requestHint,
	onRestart = function()
		local request = state.currentRequest and copyRequest(state.currentRequest)
		if request then
			startRound(request)
		end
	end,
	onQuit = function()
		abandonCurrentRound()
	end,
	onMenu = goToMenu,
	onReplay = function()
		local request = state.lastCompletedRequest or state.currentRequest
		if request then
			startRound(copyRequest(request))
		end
	end,
	onNext = function()
		local request = state.nextRequest and copyRequest(state.nextRequest)
		if request then
			startRound(request)
		else
			ui:ShowToast("The next level is not unlocked yet.", "info", 2.2)
		end
	end,
	onSettingChanged = queueSetting,
	onTutorialComplete = function()
		task.spawn(function()
			local transportOk, response = invoke("CompleteTutorial")
			if state.destroyed then
				return
			end
			if transportOk and response.success == true then
				applySnapshot(response.snapshot)
			else
				state.tutorialShown = false
				local message = transportOk and responseMessage(response, "Tutorial progress could not be saved.") or response
				ui:ShowToast(message, "error")
			end
		end)
	end,
	onRetry = loadBootstrap,
})

task.spawn(function()
	while not state.destroyed do
		local view = state.view
		task.wait(if view == "Game" then 0.5 else 1)
		if state.destroyed then
			break
		end

		if state.view == "Daily" then
			local daily = state.snapshot and state.snapshot.daily or state.daily
			if daily and daily.resetTimestamp then
				local remaining = math.max(0, daily.resetTimestamp - os.time())
				ui:UpdateDailyCountdown(remaining)
				if remaining <= 0 then
					loadBootstrap()
				end
			end
		elseif state.view == "Game" and state.currentRound and state.progress then
			local elapsedMs = tonumber(state.progress.elapsedMs) or 0
			if not state.localPaused and not state.currentRound.completed then
				elapsedMs += math.max(0, os.clock() - state.progressReceivedAt) * 1000
			end
			ui:UpdateGameStatus({
				timeText = formatTime(elapsedMs / 1000),
				foundWords = state.progress.foundCount,
				totalWords = state.progress.totalWords,
				hintsRemaining = getInventoryHints(),
			})
		end
	end
end)

local function destroy()
	if state.destroyed then
		return
	end
	state.destroyed = true
	abandonCurrentRound()
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end
	table.clear(state.connections)
	input:Destroy()
	environment:Destroy()
	ui:Destroy()
	audio:Destroy()
	animation:Destroy()
end

table.insert(state.connections, script.Destroying:Connect(destroy))

ui:ShowLoading("Starting Word Search...", 0.08)
loadBootstrap()
