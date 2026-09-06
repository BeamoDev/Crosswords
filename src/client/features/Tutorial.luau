local Players = game:GetService("Players")
local View = require(script.Parent.TutorialView)
local Tutorial = {}
Tutorial.__index = Tutorial

function Tutorial.new(ui, board, callbacks)
	local self = setmetatable({ ui = ui, board = board, callbacks = callbacks,
		active = false, finished = false, pending = false, generation = 0 }, Tutorial)
	self.view = View.new(ui, function() self:Advance() end, function() self:Finish(true) end)
	return self
end

function Tutorial:IsActive() return self.active end
function Tutorial:CanUseBoard()
	return self.active and not self.pending and not self.view.typing and not self.view.transitioning
		and (self.step == "FindCat" or self.step == "FindDog")
end
function Tutorial:BlocksPointer(position) return self.view:BlocksPointer(position) end

function Tutorial:Request(action, extra)
	local payload = extra or {}
	payload.action = action
	payload.roundId = self.round and self.round.id or nil
	local ok, result = pcall(self.callbacks.remote.InvokeServer, self.callbacks.remote, payload)
	if not ok or type(result) ~= "table" then return nil end
	return result
end

function Tutorial:Start(snapshot)
	if self.active or self.finished or not snapshot.tutorial or snapshot.tutorial.completed then return end
	self.active, self.generation = true, self.generation + 1
	self.originalExit = self.ui.exit.Visible
	self.callbacks.showHome()
	self.view:Start()
	self.ui.waiting.Text = "1 Waiting"
	self:Show("Welcome")
end

function Tutorial:WordTarget(word)
	local path = self.round.puzzle.placedWordsByWord[word].path
	local first, last = path[1], path[#path]
	local target = self.board.grid:FindFirstChild("TutorialWordTarget") or Instance.new("Frame")
	target.Name, target.BackgroundTransparency = "TutorialWordTarget", 1
	target.Active, target.Selectable = false, false
	target.Position = UDim2.fromScale((math.min(first.column, last.column) - 1) / self.board.width,
		(math.min(first.row, last.row) - 1) / self.board.height)
	target.Size = UDim2.fromScale((math.abs(last.column - first.column) + 1) / self.board.width,
		(math.abs(last.row - first.row) + 1) / self.board.height)
	target.Parent = self.board.grid
	return target
end

function Tutorial:Show(step)
	if not self.active then return end
	self.step = step
	self.board:Cancel()
	local ui = self.ui
	local title, message, target, autoAdvance, allow = "", "", nil, true, false
	if step == "Welcome" then
		title, message = "Welcome to Word Search!", "Let's find some words."
	elseif step == "Play" then
		title, message, target = "Click Play to begin", "Your first puzzle is ready!", ui.standard
		autoAdvance, allow = false, true
	elseif step == "Words" then
		title, message, target = "Your words are here!", "Find these words on the board.", ui.wordPanel
	elseif step == "FindCat" then
		title, message, target = "Drag your first word", "Connect C, A, T.", self:WordTarget("CAT")
		autoAdvance, allow = false, true
	elseif step == "TryHint" then
		title, message, target = "Use a hint", "Tap the bulb for a free clue.", ui.hint
		autoAdvance, allow = false, true
	elseif step == "FindDog" then
		title, message, target = "Drag your second word", "Connect D, O, G.", self:WordTarget("DOG")
		autoAdvance, allow = false, true
	elseif step == "Win" then
		title, message = "Congrats!", "You found them all!"
		self.view:Celebrate()
	elseif step == "HomeCongrats" then
		title, message = "Tutorial done!", "Have fun finding words!"
	end
	self.view:Show(title, message, target, autoAdvance, allow,
		(step == "Play" and ui.play) or ((step == "FindCat" or step == "FindDog") and self.board.grid or nil), step == "Welcome" or step == "Play")
end

function Tutorial:Progress()
	if not self.round then return end
	self.board:Progress(self.round.members or {})
end

function Tutorial:Advance()
	if not self.active or self.pending or self.view.typing or self.view.transitioning then return end
	if self.step == "Welcome" then
		self:Show("Play")
	elseif self.step == "Words" then
		self:Show("FindCat")
	elseif self.step == "Win" then
		self.pending = true
		local generation = self.generation
		self.view:Collapse(function()
			if not self.active or generation ~= self.generation then return end
			self.view:Suspend()
			self.callbacks.returnHomeAnimated(function()
				if not self.active or generation ~= self.generation then return end
				self.pending = false
				self:Show("HomeCongrats")
			end)
		end)
	elseif self.step == "HomeCongrats" then
		self.pending = true
		self.view:Collapse(function() self:Finish(false) end)
	end
end

function Tutorial:Play()
	if not self.active or self.step ~= "Play" or self.pending or self.view.typing or self.view.transitioning then return end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Start")
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if not result or not result.success or not result.round then
		self.view:Show("Try again", "Press PLAY to try again.", self.ui.play, false, true)
		return
	end
	self.round = result.round
	self.callbacks.openGame()
	self.ui.exit.Visible = false
	self.board:Build(self.round.puzzle, "Standard", true)
	self.board.grid.Visible = true
	self:Progress()
	self:Show("Words")
end

function Tutorial:Submit(word, path)
	if not self:CanUseBoard() then return end
	local expected = self.step == "FindCat" and "CAT" or "DOG"
	if word ~= expected then
		self.view:Show("Find " .. expected, "Find " .. expected .. " first.", self.ui.boardPanel, false, true)
		return
	end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Word", { word = word, path = path })
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if result and result.round then
		self.round.members = result.round.members
		self:Progress()
		if self.board.found[word] then self:Show(word == "CAT" and "TryHint" or "Win") return end
	end
	self.view:Show("Try again", "Connect " .. expected .. " again.", self.ui.boardPanel, false, true)
end

function Tutorial:Hint()
	if not self.active or self.step ~= "TryHint" or self.pending or self.view.typing or self.view.transitioning then return end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Hint")
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if result and result.round then
		self.round.members = result.round.members
		self:Progress()
		if self.board.hinted.DOG then self:Show("FindDog") return end
	end
	self.view:Show("Try again", "Press Hint to try again.", self.ui.hint, false, true)
end

function Tutorial:Finish(skipped)
	if not self.active or self.finished then return end
	-- Close immediately; stale remote replies cannot rebuild the tutorial.
	self.finished, self.active, self.pending = true, false, false
	self.generation += 1
	self.view:Close()
	self.board:Cancel()
	if self.board.cancelEntrance then self.board.cancelEntrance() end
	self.board.grid.Visible = true
	for _, row in pairs(self.board.rows) do row:Destroy() end
	self.board.rows = {}
	self.ui.exit.Visible = self.originalExit
	self.callbacks.showHome()
	self.callbacks.restore()
	local completionAction = skipped and "Skip" or "Complete"
	task.spawn(function()
		local attempts = 0
		repeat
			local result = self:Request(completionAction)
			if result and result.snapshot then self.callbacks.applySnapshot(result.snapshot) end
			if result and result.success and result.saved then
				return
			end
			attempts += 1
			task.wait(math.min(10, attempts * 2))
		until not Players.LocalPlayer.Parent
	end)
end

return Tutorial
