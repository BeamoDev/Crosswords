local GameController = {}
local started = false

function GameController.Start()
	if started then return end
	started = true
	local StarterPlayer = game:GetService("StarterPlayer")
	if script:IsDescendantOf(StarterPlayer:WaitForChild("StarterPlayerScripts")) then return end

	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	local SoundService = game:GetService("SoundService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("Main")
	assert(hud:IsA("ScreenGui"), "PlayerGui.Main must be the authored ScreenGui")
	-- ClientBootstrap mounts this single authored StarterGui interface for every device.
	hud.Enabled = false
	hud.ResetOnSpawn = false
	local groupIntro = playerGui:WaitForChild("GroupIntro", 15)
	if groupIntro and groupIntro:IsA("ScreenGui") then
		groupIntro.ResetOnSpawn = false
		groupIntro.Enabled = true
	end
	local client = script.Parent.Parent
	local shared = ReplicatedStorage:WaitForChild("shared")
	local Contract = require(shared:WaitForChild("network"):WaitForChild("NetworkContract"))
	local Config = require(shared:WaitForChild("config"):WaitForChild("ProgressionConfig"))
	local GameConfig = require(shared:WaitForChild("config"):WaitForChild("GameConfig"))
	local Effects = require(shared:WaitForChild("ui"):WaitForChild("UIEffects"))
	local Interface = require(script.Parent:WaitForChild("InterfaceController"))
	local Board = require(script.Parent:WaitForChild("BoardController"))
	local Meta = require(script.Parent:WaitForChild("ProgressionController"))
	local Duels = require(client:WaitForChild("features"):WaitForChild("Duels"))
	local Input = require(client:WaitForChild("systems"):WaitForChild("Input"))
	local Audio = require(client:WaitForChild("systems"):WaitForChild("Audio"))
	local Social = require(client:WaitForChild("features"):WaitForChild("Social"))
	local Tutorial = require(client:WaitForChild("features"):WaitForChild("Tutorial"))
	Audio.SetEnabled(false)
	local ui = Interface.Bind(hud)
	local folder = ReplicatedStorage:WaitForChild(Contract.FolderName)
	local action = folder:WaitForChild(Contract.QueueAction)
	local queueUpdated = folder:WaitForChild(Contract.QueueUpdated)
	local roundUpdated = folder:WaitForChild(Contract.RoundUpdated)
	local getBootstrap = folder:WaitForChild(Contract.GetBootstrap)
	local stateUpdated = folder:WaitForChild(Contract.StateUpdated)
	local useHint = folder:WaitForChild(Contract.UseHint)
	local state = {
		snapshot = {}, profileVersion = -1, queueRevision = -1, roundRevision = -1,
		ready = false, introComplete = false, queued = false, round = nil, mode = nil, pending = false,
		duelActive = false, duelStarted = false, ignoredRounds = {}, queue = {}, transitioning = false, roundVisible = false,
		firstPuzzleCompleted = false,
	}
	local board, meta, duel, tutorial
	local applyRound, applyQueue, maybeStartTutorial, maybeShowOutcome, outcomePlay, outcomeHome
	local function tutorialRequired()
		return not state.ready or (state.snapshot.tutorial and not state.snapshot.tutorial.completed
			and not (tutorial and tutorial.finished))
	end
	local function playSound(name)
		if state.snapshot.settings and state.snapshot.settings.SFX == false then return end
		local sfx = SoundService:FindFirstChild("SFX")
		local sound = sfx and sfx:FindFirstChild(name, true)
		if sound and sound:IsA("Sound") then sound:Play() end
	end
	local function modalVisible()
		if meta and meta.hintPurchasePending then return true end
		if not ui.frames or (ui.frames:IsA("GuiObject") and not ui.frames.Visible) then return false end
		for _, frame in ipairs(ui.frames:GetChildren()) do
			if frame:IsA("GuiObject") and frame.Visible then return true end
		end
		return false
	end
	local function canInteract()
		return hud.Enabled and state.introComplete and state.ready and not state.pending and not state.transitioning and ui.game.Visible and not ui.pause.Visible and not ui.queue.Visible
			and (not board or not board.timeExpired) and not modalVisible() and (not tutorial or not tutorial:IsActive() or tutorial:CanUseBoard()) and (state.mode ~= "Duel" or state.duelStarted)
	end
	local function updateModePlay(control, level, requiredLevel)
		if not control then return end
		local locked = level < requiredLevel
		local icon = control:FindFirstChild("Locked")
		if icon and icon:IsA("GuiObject") then icon.Visible = locked end
		local value = locked and ("Level " .. requiredLevel) or "PLAY"
		local label = control:FindFirstChild("TextLabel") or control:FindFirstChild("Textlabel")
		if label then
			label.Text = value
			if not locked then label.TextColor3 = Color3.new(1, 1, 1) end
			label.Position = UDim2.fromScale(locked and 0.634 or 0.5, 0.5)
			label.Size = UDim2.fromScale(0.587, 0.6)
			label.TextXAlignment = locked and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center
		elseif control:IsA("TextButton") then
			control.Text = value
			if not locked then control.TextColor3 = Color3.new(1, 1, 1) end
		end
	end
	local function applySnapshot(snapshot)
		if type(snapshot) ~= "table" then return end
		local version = snapshot.meta and snapshot.meta.snapshotVersion or 0
		if version < state.profileVersion then return end
		state.profileVersion, state.snapshot, state.ready = version, snapshot, true
		Interface.UpdateLevelBars(ui, snapshot.progression)
		local hints = snapshot.hints or 0
		if ui.hintCount then ui.hintCount.Text = tostring(hints) end
		if ui.hintBadge then ui.hintBadge.Visible = hints > 0 end
		local level = snapshot.progression and snapshot.progression.level or 1
		for name, requiredLevel in pairs(Config.Experience.ModeLevels) do
			local card = ui.modes:FindFirstChild(name)
			updateModePlay(card and card:FindFirstChild("Play"), level, requiredLevel)
		end
		Audio.SetEnabled(state.introComplete and (not snapshot.settings or snapshot.settings.Music ~= false))
		if meta then meta:applySnapshot(snapshot) end
		if duel then duel:updateOutcome(snapshot) end
		if maybeStartTutorial then maybeStartTutorial() end
	end
	local function invoke(payload)
		local ok, result = pcall(action.InvokeServer, action, payload)
		if not ok or type(result) ~= "table" then
			return nil
		end
		if result.snapshot then applySnapshot(result.snapshot) end
		if result.queue then applyQueue(result.queue) end
		if result.round then applyRound(result.round) end
		return result
	end
	local function hideModals()
		if not ui.frames then return end
		for _, child in ipairs(ui.frames:GetChildren()) do
			if child:IsA("GuiObject") then
				if meta then meta:setModalFrameVisible(child, false, true) else child.Visible = false end
			end
		end
	end
	local cancelTransition, presentationVersion = nil, 0
	local function cancelPresentation()
		presentationVersion += 1
		if cancelTransition then cancelTransition() cancelTransition = nil end
		state.transitioning = false
	end
	local function setHomeView()
		state.roundVisible = false
		Interface.UpdateQueue(ui, {})
		board:Cancel()
		ui.pause.Visible, ui.queue.Visible, ui.game.Visible, ui.home.Visible = false, false, false, true
		state.mode, state.round, state.queued = nil, nil, false
		state.duelId, state.duelActive, state.duelStarted = nil, false, false
	end
	local function showHome()
		cancelPresentation()
		setHomeView()
	end
	local function returnHomeAnimated(onComplete)
		cancelPresentation()
		local generation = presentationVersion
		state.transitioning, state.roundVisible = true, false
		board:Cancel()
		hideModals()
		ui.pause.Visible = false
		cancelTransition = Effects.TransitionToHome(hud, ui.game.Visible and ui.game or nil, function()
			if generation ~= presentationVersion then return nil end
			setHomeView()
			return ui.home
		end, function(success, err)
			if generation ~= presentationVersion then return end
			cancelTransition, state.transitioning = nil, false
			if not success then
				warn("[GameController] Home transition failed:", err)
				showHome()
			end
			if onComplete then onComplete() end
		end)
	end
	local function revealGame(mountGame)
		local generation = presentationVersion
		state.transitioning = true
		board:Cancel()
		cancelTransition = Effects.TransitionToGame(hud, function()
			if generation ~= presentationVersion then return nil end
			return mountGame()
		end, function(success, err)
			if generation ~= presentationVersion then return end
			cancelTransition, state.transitioning = nil, false
			if not success then
				warn("[GameController] Game reveal failed:", err)
				showHome()
			elseif maybeShowOutcome then maybeShowOutcome() end
		end)
	end
	local function openGame()
		Interface.UpdateQueue(ui, {})
		hideModals()
		ui.home.Visible, ui.queue.Visible, ui.pause.Visible, ui.game.Visible = false, false, false, true
	end
	local function pause()
		if state.pending or state.transitioning or modalVisible() or not hud.Enabled or not ui.game.Visible or tutorialRequired() or (tutorial and tutorial:IsActive()) then return end
		board:Cancel()
		ui.pause.Visible = true
	end
	board = Board.new(ui, {
		canInteract = canInteract,
		blocksPointer = function(position) return tutorial and tutorial:BlocksPointer(position) end,
		playSound = playSound,
		invalidSelection = function(path)
			if state.mode == "Hardcore" and state.round then
				invoke({ action = "Word", roundId = state.round.id, word = "", path = path })
			end
		end,
		submit = function(word, path)
			if tutorial and tutorial:IsActive() then
				tutorial:Submit(word, path)
			elseif state.round then
				invoke({ action = "Word", roundId = state.round.id, word = word, path = path })
			elseif state.mode == "Duel" and state.duelStarted then
				duel:reportWordFound(word, 0, path)
			end
		end,
	})
	maybeShowOutcome = function()
		local round = state.round
		if not round or not state.roundVisible or state.transitioning or not meta
			or state.mode == "Duel" or state.mode == "Tutorial" or (tutorial and tutorial:IsActive())
			or state.outcomeScheduled == round.id or state.outcomeShown == round.id then return end
		local mine
		for _, member in ipairs(round.members or {}) do
			if member.userId == player.UserId then mine = member break end
		end
		if not mine or (not mine.completed and not mine.failed) then return end
		if mine.completed and (state.roundStartProgression.solves or 0) == 0 then
			state.firstPuzzleCompleted = true
			meta:queueVerifyPrompt(state.snapshot)
		end
		state.outcomeScheduled = round.id
		local generation, roundId = presentationVersion, round.id
		task.delay(0.55, function()
			if generation ~= presentationVersion or not state.round or state.round.id ~= roundId
				or state.ignoredRounds[roundId] or state.transitioning or not ui.game.Visible
				or (tutorial and tutorial:IsActive()) then return end
			state.outcomeShown = roundId
			ui.pause.Visible = false
			board:Cancel()
			meta:showGameOutcome({ roundId = roundId, mode = round.mode, theme = round.puzzle.title or round.puzzle.subtitle,
				timedOut = mine.timedOut, failed = mine.failed, words = mine.count or #round.puzzle.words, total = #round.puzzle.words, duration = mine.duration, xpEarned = mine.xpEarned or 0, beforeProgression = state.roundStartProgression }, state.snapshot)
		end)
	end
	local function applyRoundProgress()
		if not state.roundVisible or not state.round then return end
		board:Progress(state.round.members or {})
		for _, member in ipairs(state.round.members or {}) do
			if member.userId == player.UserId and member.failed then
				board.completed = true
				board:Cancel()
				if ui.subtitle then ui.subtitle.Text = member.timedOut and "Time's up!" or "Wrong word!" end
			end
		end
		maybeShowOutcome()
	end
	applyRound = function(round)
		if tutorialRequired() or (tutorial and tutorial:IsActive()) then return end
		if round.error then
			showHome()
			return
		end
		if type(round.id) ~= "string" or state.ignoredRounds[round.id] then return end
		if not state.round or state.round.id ~= round.id then
			if not round.puzzle then return end
			cancelPresentation()
			state.round, state.roundRevision, state.mode, state.queued = round, round.revision or 0, round.mode, false
			state.roundStartProgression = table.clone(state.snapshot.progression or {})
			state.roundVisible = false
			state.outcomeShown, state.outcomeScheduled = nil, nil
			local generation = presentationVersion
			local function mountGame()
				if generation ~= presentationVersion or not state.round or state.round.id ~= round.id then return nil end
				openGame()
				board:Build(state.round.puzzle, state.mode, state.round.solo)
				state.roundVisible = true
				applyRoundProgress()
				return ui.game
			end
			revealGame(mountGame)
			return
		end
		if (round.revision or 0) < state.roundRevision then return end
		state.roundRevision = round.revision or 0
		state.round.members = round.members
		-- Keep updates that arrive while white is fading in; apply after mounting.
		applyRoundProgress()
	end
	applyQueue = function(queue)
		if (queue.revision or 0) < state.queueRevision then return end
		state.queueRevision, state.queue = queue.revision or 0, queue
		if tutorialRequired() or (tutorial and tutorial:IsActive()) then return end
		ui.waiting.Text = string.format("%d Waiting", queue.count or 0)
		local mine = false
		for _, member in ipairs(queue.members or {}) do
			if member.userId == player.UserId then mine = true break end
		end
		if mine and not state.round and not state.transitioning and not state.duelActive then
			state.queued = true
			hideModals()
			Interface.UpdateQueue(ui, queue.members)
			Interface.UpdateQueueTimer(ui, (queue.deadline or Workspace:GetServerTimeNow()) - Workspace:GetServerTimeNow())
			if not ui.queue.Visible then
				cancelPresentation()
				local generation = presentationVersion
				state.transitioning = true
				cancelTransition = Effects.TransitionToQueue(hud, function()
					if generation ~= presentationVersion then return nil end
					Interface.UpdateQueue(ui, state.queue.members or {})
					Interface.UpdateQueueTimer(ui, (state.queue.deadline or Workspace:GetServerTimeNow()) - Workspace:GetServerTimeNow())
					ui.home.Visible, ui.game.Visible, ui.queue.Visible = false, false, true
					return ui.queue
				end, function(success)
					if generation ~= presentationVersion then return end
					cancelTransition, state.transitioning = nil, false
					if not success then showHome() else applyQueue(state.queue) end
				end)
			end
		end
	end
	meta = Meta.new({
		playSound = playSound, getSnapshot = function() return state.snapshot end,
		applySnapshot = applySnapshot,
		onOutcomePlay = function(id) if outcomePlay then outcomePlay(id) end end,
		onOutcomeHome = function(id) if outcomeHome then outcomeHome(id) end end,
		isGameplayInteractionBlocked = function() return state.transitioning or ui.pause.Visible or ui.queue.Visible or tutorialRequired() or (tutorial and tutorial:IsActive()) end,
		isGameViewActive = function() return ui.game.Visible end,
		canShowVerifyPrompt = function()
			return state.ready and state.introComplete and hud.Enabled and ui.home.Visible
				and not state.pending and not state.transitioning and not ui.queue.Visible and not ui.game.Visible
				and not ui.pause.Visible and not modalVisible() and not tutorialRequired()
				and tutorial ~= nil and not tutorial:IsActive()
		end,
		isVerifyPromptTestUser = function()
			return player.UserId == GameConfig.Tutorial.ReplayUserId and tutorial ~= nil and tutorial.finished == true
		end,
		hasCompletedFirstPuzzle = function() return state.firstPuzzleCompleted end,
	})
	meta:bind(hud)
	hideModals()
	if ui.frames and ui.frames:IsA("GuiObject") then ui.frames.Visible = true end
	local function applyDuelProgress()
		if not state.roundVisible or state.mode ~= "Duel" then return end
		board:Progress(state.duelMembers)
		local function count(words)
			local n = 0
			for _ in pairs(words) do n += 1 end
			return n
		end
		board:DuelScores(count(state.duelMembers[1].foundWords), count(state.duelMembers[2].foundWords))
	end
	duel = Duels.new({
		getSnapshot = function() return state.snapshot end,
		getSolvesText = function(userId)
			local other = Players:GetPlayerByUserId(userId)
			local stats = other and other:FindFirstChild("leaderstats")
			local level = stats and stats:FindFirstChild("Level")
			return "Level " .. tostring(level and level.Value or 1)
		end,
		onCountdown = function(payload)
			cancelPresentation()
			state.roundVisible = false
			state.round, state.queued = nil, false
			state.mode, state.duelActive, state.duelStarted = "Duel", true, false
			state.roundStartProgression = table.clone(state.snapshot.progression or {})
			state.duelId, state.opponentId = payload.matchId, payload.opponentId
			state.duelResultId, state.duelRemaining = nil, nil
			state.duelTimer = {timeLimit = payload.timeLimit}
			state.opponentName = payload.opponentName
			state.myDuelStats, state.opponentDuelStats = payload.myDuelStats, payload.opponentDuelStats
			state.duelMembers = {
				{ userId = player.UserId, foundWords = {}, hintedWords = {} },
				{ userId = payload.opponentId, foundWords = {}, hintedWords = {},
					isBot = payload.opponentIsBot == true, thumbnailImage = payload.opponentThumbnailImage },
			}
			revealGame(function()
				if state.duelId ~= payload.matchId then return nil end
				openGame()
				board:Build(payload.puzzleData, "Duel")
				board:DuelPlayers(payload.opponentId, payload.opponentName, payload.opponentThumbnailImage, state.myDuelStats, state.opponentDuelStats)
				state.roundVisible = true
				applyDuelProgress()
				return ui.game
			end)
		end,
		onStart = function(payload)
			if state.duelActive and state.duelId == payload.matchId then
				state.duelStarted = true
				state.duelTimer = {expiresAt = payload.expiresAt, timeLimit = payload.timeLimit}
			end
		end,
		onProgress = function(payload)
			if state.mode ~= "Duel" or state.duelId ~= payload.matchId then return end
			state.duelMembers[1].score = payload.myScore or 0
			state.duelMembers[1].foundWords = payload.myFoundWords or {}
			state.duelMembers[1].bonusWords = payload.myBonusWords or {}
			state.duelMembers[2].foundWords = payload.opponentFoundWords or {}
			applyDuelProgress()
		end,
		onResult = function(payload)
			if state.duelId ~= payload.matchId or state.duelResultId == payload.matchId then return true end
			state.duelResultId = payload.matchId
			if payload.score ~= nil then state.duelMembers[1].score = payload.score end
			if state.roundVisible then applyDuelProgress() end
			payload = table.clone(payload)
			payload.beforeProgression = state.roundStartProgression
			state.myDuelStats, state.opponentDuelStats = payload.myDuelStats, payload.opponentDuelStats
			if state.roundVisible then board:DuelWinRates(state.myDuelStats, state.opponentDuelStats) end
			state.duelRemaining = math.max(0, (state.duelTimer.timeLimit or 0) - (payload.duration or 0))
			state.duelStarted, state.duelActive = false, false
			board:Cancel()
			if payload.isWinner then playSound("Victory") end
			local generation = presentationVersion
			local function showResult()
				if generation ~= presentationVersion or state.duelId ~= payload.matchId then return end
				if state.transitioning then task.delay(0.1, showResult) return end
				if not state.roundVisible or not ui.game.Visible then return end
				duel:showOutcome(payload)
			end
			task.delay(0.55, showResult)
			return true
		end,
		onReturnHome = function(matchId)
			if state.transitioning or (matchId and matchId ~= state.duelId) then return end
			returnHomeAnimated()
		end,
	})
	duel:bind(hud, meta)
	local duelButton = ui.buttonBar:FindFirstChild("Duel")
	if duelButton then duelButton.Activated:Connect(function()
		if state.ready and not state.pending and not state.transitioning and not tutorialRequired() and not tutorial:IsActive() then duel:showLobby() end
	end) end
	local function startMode(mode)
		if not state.ready or state.pending or state.transitioning or not ui.home.Visible or tutorialRequired()
			or (tutorial and tutorial:IsActive()) then return end
		local required = Config.Experience.ModeLevels[mode]
		if mode ~= "Standard" and not required then return end
		if required and (state.snapshot.progression.level or 1) < required then return end
		state.pending = true
		invoke(mode == "Standard" and { action = "Join" } or { action = "StartSolo", mode = mode })
		state.pending = false
	end
	ui.play.Activated:Connect(function()
		if tutorial and tutorial:IsActive() then tutorial:Play() return end
		startMode("Standard")
	end)
	for mode in pairs(Config.Experience.ModeLevels) do
		local card = ui.modes:FindFirstChild(mode)
		local play = card and card:FindFirstChild("Play")
		if play and play:IsA("GuiButton") then play.Activated:Connect(function() startMode(mode) end) end
	end
	if ui.queueSolo then ui.queueSolo.Activated:Connect(function()
		if state.pending or state.transitioning or not ui.queue.Visible then return end
		state.pending = true
		invoke({ action = "StartSolo", mode = "Standard" })
		state.pending = false
	end) end
	ui.queueLeave.Activated:Connect(function()
		if state.pending or state.transitioning or not ui.queue.Visible then return end
		state.pending = true
		local result = invoke({ action = "LeaveQueue" })
		state.pending = false
		if result and result.success and not result.round then returnHomeAnimated() end
	end)
	ui.resume.Activated:Connect(function()
		ui.pause.Visible = false
	end)
	local function exitRound(onComplete)
		onComplete = type(onComplete) == "function" and onComplete or nil
		if state.pending or state.transitioning or not ui.game.Visible or tutorialRequired()
			or (tutorial and tutorial:IsActive()) then return end
		state.pending = true
		if state.mode == "Duel" then
			duel:abandon()
			state.duelId, state.duelActive, state.duelStarted = nil, false, false
			returnHomeAnimated(onComplete)
		elseif state.round then
			local id = state.round.id
			local result = invoke({ action = "Exit", roundId = id })
			if result and result.success then
				state.ignoredRounds[id] = true
				returnHomeAnimated(onComplete)
			end
		else returnHomeAnimated(onComplete) end
		state.pending = false
	end
	local function validOutcome(id)
		return state.round and state.round.id == id and state.outcomeShown == id
			and not state.pending and not state.transitioning
	end
	outcomeHome = function(id)
		if validOutcome(id) then exitRound() end
	end
	outcomePlay = function(id)
		if not validOutcome(id) then return end
		local mode, generation = state.mode, presentationVersion
		state.pending = true
		local exited = invoke({ action = "Exit", roundId = id })
		if generation ~= presentationVersion or not state.round or state.round.id ~= id then
			state.pending = false
			return
		end
		if not exited or not exited.success then state.pending = false return end
		local solo = state.round and state.round.solo
		state.ignoredRounds[id] = true
		cancelPresentation()
		state.round, state.roundVisible, state.mode, state.queued = nil, false, nil, false
		board:Cancel()
		hideModals()
		ui.pause.Visible = false
		-- Keep the finished board visible until the next view mounts under white.
		-- Queue/round replies already own their single entrance transition.
		invoke(mode == "Standard" and not solo and { action = "Join" } or { action = "StartSolo", mode = mode })
		state.pending = false
		if not state.round and not state.queued and not state.transitioning then
			-- The old round has exited; a rejected/failed replay must leave a usable view.
			returnHomeAnimated()
		end
	end
	if ui.exit then ui.exit.Activated:Connect(exitRound) end
	ui.leaveRound.Activated:Connect(exitRound)
	ui.hint.Activated:Connect(function()
		if tutorial and tutorial:IsActive() then tutorial:Hint() return end
		if not canInteract() or state.pending or board.completed then return end
		local hasTarget = false
		for _, word in ipairs(board.puzzle.words) do
			if not board.found[word] and not board.hinted[word] then hasTarget = true break end
		end
		if not hasTarget then return end
		state.pending = true
		local hints = state.snapshot.hints or 0
		if hints < 1 then
			board:Cancel()
			meta:promptHintPurchase()
		elseif state.round then
			invoke({ action = "Hint", roundId = state.round.id })
		elseif state.mode == "Duel" then
			local ok, result = pcall(useHint.InvokeServer, useHint, { mode = "Duel" })
			if ok and type(result) == "table" then
				if result.snapshot then applySnapshot(result.snapshot) end
				if result.success and result.boardState then
					local words = {}
					for _, word in ipairs(result.boardState.hintedWords or {}) do words[word] = true end
					state.duelMembers[1].hintedWords = words
					board:Progress(state.duelMembers)
				end
			end
		end
		state.pending = false
	end)
	tutorial = Tutorial.new(ui, board, {
		remote = folder:WaitForChild(Contract.TutorialAction),
		showHome = function() hideModals() showHome() end,
		returnHomeAnimated = returnHomeAnimated,
		openGame = function() cancelPresentation() state.mode = "Tutorial" openGame() end,
		applySnapshot = applySnapshot,
		restore = function()
			applyQueue(state.queue)
			Interface.UpdateLevelBars(ui, state.snapshot.progression)
			meta:queueVerifyPrompt(state.snapshot)
		end,
	})
	maybeStartTutorial = function()
		if state.ready and state.introComplete then tutorial:Start(state.snapshot) end
	end
	Input.bind(board, pause)
	queueUpdated.OnClientEvent:Connect(applyQueue)
	roundUpdated.OnClientEvent:Connect(applyRound)
	stateUpdated.OnClientEvent:Connect(applySnapshot)
	local hintWobble = Effects.CreateHintWobble(ui.hint)
	local lastTimer, lastTimerBucket, lastTimerLimit
	RunService.Heartbeat:Connect(function(dt)
		Interface.StepHomePreviews(ui, dt, hud.Enabled and ui.home.Visible and not state.transitioning and not modalVisible())
		hintWobble:Step(dt, canInteract() and not board.entering and not board.completed and not board.startCell)
		if ui.queue.Visible then
			local deadline = state.queue.deadline
			local seconds = deadline and math.max(0, math.ceil(deadline - Workspace:GetServerTimeNow())) or 0
			Interface.UpdateQueueTimer(ui, seconds)
		end
		if ui.game.Visible then
			if tutorial then tutorial:Tick(Workspace:GetServerTimeNow()) end
			local timer = state.mode == "Duel" and state.duelTimer or (tutorial and tutorial:IsActive() and tutorial.round or state.round)
			if timer and timer.expiresAt and timer.timeLimit then
				local remaining = timer.expiresAt - Workspace:GetServerTimeNow()
				for _, member in ipairs(timer.members or {}) do
					if member.userId == player.UserId and (member.completed or member.failed) then remaining = timer.timeLimit - (member.duration or timer.timeLimit) end
				end
				if state.mode == "Duel" and state.duelRemaining then remaining = state.duelRemaining end
				local bucket = math.ceil(math.max(0, remaining) * 5)
				if timer ~= lastTimer or bucket ~= lastTimerBucket or timer.timeLimit ~= lastTimerLimit then
					Interface.UpdateTimedTimer(ui, remaining, timer.timeLimit)
					lastTimer, lastTimerBucket, lastTimerLimit = timer, bucket, timer.timeLimit
				end
				board.timeExpired = remaining <= 0
				if board.timeExpired and board.startCell then board:Cancel() end
			else
				Interface.UpdateTimedTimer(ui, timer and timer.timeLimit, timer and timer.timeLimit)
			end
		end
		if board.startCell and not canInteract() then board:Cancel() end
	end)
	Interface.UpdateLevelBars(ui, { level = 1, xp = 0, xpToNextLevel = Config.Experience.RequiredForLevel(1) })
	ui.waiting.Text = "0 Waiting"
	for name, level in pairs(Config.Experience.ModeLevels) do
		local card = ui.modes:FindFirstChild(name)
		updateModePlay(card and card:FindFirstChild("Play"), 1, level)
	end
	Audio.Initialize()
	require(client:WaitForChild("systems"):WaitForChild("Device")).Init({ playerGui = playerGui })
	Social.AutoRejoin.Init()
	Social.FavouritePrompt.Init()
	task.spawn(function() require(client:WaitForChild("systems"):WaitForChild("Camera")).ApplyJoinCamera({ PartName = "CamPart", FieldOfView = 40, Owner = hud }) end)
	task.spawn(function()
		repeat
			local ok, snapshot = pcall(getBootstrap.InvokeServer, getBootstrap)
			if ok and type(snapshot) == "table" then applySnapshot(snapshot) end
			if not state.ready then task.wait(1) end
		until state.ready or not hud.Parent
		if hud.Parent then invoke({ action = "Sync" }) end
	end)
	local preloadRoots = { hud }
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then table.insert(preloadRoots, assets) end
	Social.GroupIntro:Play(groupIntro, preloadRoots, function()
		if not hud.Parent then return end
		state.introComplete = true
		hud.Enabled = true
		maybeStartTutorial()
		Audio.SetEnabled(not state.snapshot.settings or state.snapshot.settings.Music ~= false)
	end, {
		shouldFinish = function() return state.ready end,
		finishTimeout = 12,
	})
end

return GameController
