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
		and (self.step == "FirstAcross" or self.step == "FirstDown" or self.step == "LastAcross")
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
	if self.ui.exit then self.originalExit = self.ui.exit.Visible end
	self.callbacks.openGame()
	self.view:Start()
	self:Show("Loading")
	self:Play()
end

function Tutorial:Show(step)
	if not self.active then return end
	self.step = step
	self.board:Cancel()
	local ui = self.ui
	local title, message, target, autoAdvance, allow = "", "", nil, true, false
	if step == "Loading" then
		title, message, autoAdvance = "Loading puzzle...", "Getting your first puzzle ready.", false
	elseif step == "FirstAcross" then
		title, message, target = "Your first word", "A pet that says meow. Type CAT, then press Check.", ui.boardPanel
		autoAdvance, allow = false, true
	elseif step == "TryHint" then
		title, message, target = "Use a hint", "Tap the bulb to reveal one answer for free.", ui.hint
		autoAdvance, allow = false, true
	elseif step == "FirstDown" then
		title, message, target = "Next word", "The hint reveals CAR. Shared squares help other clues. Press Check.", ui.boardPanel
		autoAdvance, allow = false, true
	elseif step == "LastAcross" then
		title, message, target = "Last word", "The colour of a ripe tomato. Type RED, then press Check.", ui.boardPanel
		autoAdvance, allow = false, true
	elseif step == "Retry" then
		title, message = "Time's up!", "Let's try the practice again."
	elseif step == "Win" then
		title, message = "Congrats!", "You found them all!"
		self.view:Celebrate()
	elseif step == "HomeCongrats" then
		title, message = "Tutorial done!", "Have fun solving crosswords!"
	end
	self.view:Show(title, message, target, autoAdvance, allow,
		((step == "FirstAcross" or step == "FirstDown" or step == "LastAcross") and ui.boardPanel or nil), false)
	local word = step == "FirstAcross" and "1A" or step == "FirstDown" and "1D" or step == "LastAcross" and "2A"
	if word then self.board:SelectEntry(word) end
end

function Tutorial:ApplyTimeout(result)
	local round = result and result.round
	local member = round and round.members and round.members[1]
	if not member or not member.timedOut then return false end
	self.round.members = round.members
	self.board.completed = true
	self:Show("Retry")
	return true
end

function Tutorial:Tick(now)
	if self.active and not self.pending and self.step == "Loading" and now >= (self.nextStartAttempt or 0) then
		self.nextStartAttempt = now + 2
		self:Play()
	end
	if not self.active or self.pending or not self.round or not self.round.expiresAt
		or now < self.round.expiresAt or now < (self.nextTimeCheck or 0) or self.step == "Retry" or self.step == "Win" or self.step == "HomeCongrats" then return end
	self.pending = true
	self.nextTimeCheck = now + 1
	local generation = self.generation
	task.spawn(function()
		local result = self:Request("Sync")
		if not self.active or generation ~= self.generation then return end
		self.pending = false
		self:ApplyTimeout(result)
	end)
end

function Tutorial:Progress()
	if not self.round then return end
	self.board:Progress(self.round.members or {})
end

function Tutorial:Advance()
	if not self.active or self.pending or self.view.typing or self.view.transitioning then return end
	if self.step == "Retry" then
		self.round = nil
		self:Show("Loading")
		self:Play()
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
	if not self.active or self.step ~= "Loading" or self.pending then return end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Start")
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if not result or not result.success or not result.round then
		self:Show("Loading")
		return
	end
	self.round = result.round
	if self.ui.exit then self.ui.exit.Visible = false end
	self.board:Build(self.round.puzzle, "Standard", true)
	self.board.grid.Visible = true
	self:Progress()
	self:Show("FirstAcross")
end

function Tutorial:Submit(word, answer)
	if not self:CanUseBoard() then return end
	local expected = self.step == "FirstAcross" and "1A" or self.step == "FirstDown" and "1D" or "2A"
	if word ~= expected then
		self:Show(self.step)
		return {success=false}
	end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Word", { word = word, answer = answer })
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if self:ApplyTimeout(result) then return end
	if result and result.round then
		self.round.members = result.round.members
		self:Progress()
		if self.board.found[word] then self:Show(word == "1A" and "TryHint" or word == "1D" and "LastAcross" or "Win") return result end
	end
	self:Show(self.step)
    return result
end

function Tutorial:Hint()
	if not self.active or self.step ~= "TryHint" or self.pending or self.view.typing or self.view.transitioning then return end
	self.pending = true
	local generation = self.generation
	local result = self:Request("Hint")
	if not self.active or generation ~= self.generation then return end
	self.pending = false
	if self:ApplyTimeout(result) then return end
	if result and result.round then
		self.round.members = result.round.members
		self:Progress()
		if self.board.hinted["1D"] then self:Show("FirstDown") return end
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
	if self.board.grid then self.board.grid.Visible = true end
	for _, row in pairs(self.board.rows) do row:Destroy() end
	self.board.rows = {}
	if self.ui.exit then self.ui.exit.Visible = self.originalExit end
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
