local TweenService = game:GetService("TweenService")

-- General GUI helpers.
local Gui = {}

function Gui.create(className, props)
	local instance = Instance.new(className)
	instance.Name = props.Name or className

	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Name" then
			instance[key] = value
		end
	end

	instance.Parent = props.Parent
	return instance
end

function Gui.findDescendantByNames(root, names, className)
	if not root then
		return nil
	end

	for _, name in ipairs(names or {}) do
		local descendant = root:FindFirstChild(name, true)
		if descendant and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

function Gui.findPath(root, path, className)
	local current = root

	for _, name in ipairs(path or {}) do
		current = current and current:FindFirstChild(name) or nil
	end

	if current and (not className or current:IsA(className)) then
		return current
	end

	return nil
end

function Gui.findFirstPath(root, paths, className)
	for _, path in ipairs(paths or {}) do
		local found = Gui.findPath(root, path, className)
		if found then
			return found
		end
	end

	return nil
end

function Gui.waitForDescendantByNames(root, names, className)
	local found = Gui.findDescendantByNames(root, names, className)
	if found then
		return found
	end

	while root and root.Parent do
		root.DescendantAdded:Wait()
		found = Gui.findDescendantByNames(root, names, className)
		if found then
			return found
		end
	end

	return nil
end

function Gui.findTextObject(root, names)
	if not root then
		return nil
	end

	local named = Gui.findDescendantByNames(root, names, nil)
	if named and (named:IsA("TextLabel") or named:IsA("TextButton")) then
		return named
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end

	return root:FindFirstChildWhichIsA("TextLabel", true) or root:FindFirstChildWhichIsA("TextButton", true)
end

function Gui.findImageObject(root, names)
	if not root then
		return nil
	end

	local named = Gui.findDescendantByNames(root, names, nil)
	if named and (named:IsA("ImageLabel") or named:IsA("ImageButton")) then
		return named
	end

	return root:FindFirstChildWhichIsA("ImageLabel", true) or root:FindFirstChildWhichIsA("ImageButton", true)
end

function Gui.ensureScaleController(guiObject)
	local scaleController = guiObject:FindFirstChild("ScaleController")
	if scaleController and scaleController:IsA("UIScale") then
		return scaleController
	end

	return Gui.create("UIScale", {
		Name = "ScaleController",
		Scale = 1,
		Parent = guiObject,
	})
end

function Gui.tween(
	instance,
	properties,
	durationOrInfo,
	defaultDuration,
	defaultEasingStyle,
	defaultEasingDirection,
	tweenService
)
	if typeof(instance) ~= "Instance" then
		return nil
	end
	if instance.Parent == nil then
		return nil
	end

	local tweenInfo = durationOrInfo
	if typeof(durationOrInfo) ~= "TweenInfo" then
		tweenInfo = TweenInfo.new(
			durationOrInfo or defaultDuration,
			defaultEasingStyle,
			defaultEasingDirection
		)
	end

	local success, animation = pcall(function()
		return tweenService:Create(instance, tweenInfo, properties)
	end)
	if not success then
		return nil
	end

	animation:Play()
	return animation
end

function Gui.bindButtonHoverSound(button, playSound)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("WordSearchHoverSfxBound") then
		return
	end

	button:SetAttribute("WordSearchHoverSfxBound", true)
	button.MouseEnter:Connect(function()
		if playSound then
			playSound("Hover")
		end
	end)
end

function Gui.findButtonLike(root)
	if not root then
		return nil
	end

	if root:IsA("GuiButton") then
		return root
	end

	local directButton = root:FindFirstChild("Button")
	if directButton and directButton:IsA("GuiButton") then
		return directButton
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == "Button" and descendant:IsA("GuiButton") then
			return descendant
		end
	end

	return root:FindFirstChildWhichIsA("GuiButton", true)
end

function Gui.findBarContainer(root)
	if not root then
		return nil
	end

	local direct = root:FindFirstChild("ProgressBar") or root:FindFirstChild("Bar")
	if direct and direct:IsA("GuiObject") then
		return direct
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") and child:FindFirstChild("Fill") then
			return child
		end
	end

	return nil
end

function Gui.setBarFillAlpha(barFill, bar, alpha)
	local clampedAlpha = math.clamp(alpha or 0, 0, 1)
	if barFill and barFill:IsA("GuiObject") then
		barFill.Size = UDim2.new(clampedAlpha, 0, 1, 0)
		return
	end

	if bar and bar:IsA("GuiObject") then
		bar.Size = UDim2.new(clampedAlpha, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
	end
end

function Gui.setVisible(node, visible)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

function Gui.setText(node, value, fallbackNames)
	if not node then
		return
	end

	if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
		node.Text = tostring(value or "")
		return
	end

	local label = Gui.findTextObject(node, fallbackNames or { "TextLabel", "Label", "Data", "Value", "Amount" })
	if label then
		label.Text = tostring(value or "")
	end
end


local Components = { Gui = Gui }

-- Exact authored Home/Game binding. The surrounding HUD and modal assets stay authored.
local Experience = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("config"):WaitForChild("ProgressionConfig")).Experience
local Effects = require(game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("ui"):WaitForChild("UIEffects"))
local InterfaceController = {}
local TweenService = game:GetService("TweenService")

local function path(root, names)
	for _, name in ipairs(names) do root = root and root:FindFirstChild(name) end
	return root
end

local function required(root, names)
	local value = path(root, names)
	assert(value, "Missing authored HUD path: " .. table.concat(names, "."))
	return value
end

local function text(parent, name, value, position, size)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Text = value
	label.TextColor3 = Color3.fromRGB(17, 44, 67)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Position = position
	label.Size = size
	label.ZIndex = 52
	label.Parent = parent
	return label
end

local function button(parent, name, value, position, size)
	local control = Instance.new("TextButton")
	control.Name = name
	control.Text = value
	control.TextScaled = true
	control.Font = Enum.Font.GothamBold
	control.TextColor3 = Color3.fromRGB(17, 44, 67)
	control.BackgroundColor3 = Color3.fromRGB(224, 239, 255)
	control.Position = position
	control.Size = size
	control.ZIndex = 53
	control.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = control
	return control
end

function InterfaceController.Bind(hud)
	local tutorialFrame = hud:FindFirstChild("Tutorial")
	if tutorialFrame then tutorialFrame.Visible = false end
	local ui = {
		screenGui = hud,
		home = required(hud, { "Home" }),
		game = required(hud, { "Game" }),
		frames = hud:FindFirstChild("Frames"),
	}
	ui.modes = required(ui.home, { "Gamemodes" })
	ui.standard = required(ui.modes, { "Standard" })
	ui.homeTilePreviews = {}
	for _, preview in ipairs({
		{ "Standard", 5, Color3.fromRGB(88, 224, 255), 0 },
		{ "Mini", 3, Color3.fromRGB(119, 222, 176), 0.25 },
	}) do
		local frame = path(ui.modes:FindFirstChild(preview[1]), { "CanvasGroup", "Frame1" })
		local animation = Effects.CreateHomeTilePreview(frame, preview[2], preview[3], preview[4])
		if animation then table.insert(ui.homeTilePreviews, animation) end
	end
	local jumboPreview = Effects.CreateJumboPreview(path(ui.modes:FindFirstChild("Jumbo"), { "CanvasGroup", "Frame1" }))
	if jumboPreview then table.insert(ui.homeTilePreviews, jumboPreview) end
	ui.play = required(ui.standard, { "Play" })
	ui.waiting = required(ui.standard, { "Waiting" })
	ui.buttonBar = required(ui.home, { "ButtonBar" })
	ui.boardPanel = ui.game:FindFirstChild("BOARDINFO") or ui.game:FindFirstChild("BoardInfo")
		or required(ui.game, { "BoardPanel" })
	ui.wordPanel = required(ui.game, { "WordPanel" })
	ui.words = required(ui.wordPanel, { "Words" })
	ui.wordList = required(ui.wordPanel, { "Container", "ScrollingFrame" })
	local scorePanel = ui.game:FindFirstChild("Score")
	ui.scoreText = path(scorePanel, { "Score" })
	ui.scoreLevel = path(scorePanel, { "Level", "Label" }) or path(scorePanel, { "Level", "label" })
	ui.title = ui.game:FindFirstChild("Title")
	ui.subtitle = ui.game:FindFirstChild("Subtitle")
	ui.hint = required(ui.game, { "Hint" })
	ui.hintBadge = path(ui.hint, { "Owned" })
	ui.hintCount = path(ui.hintBadge, { "TextLabel" })
	if ui.hintBadge then ui.hintBadge.Visible = false end
	ui.exit = ui.game:FindFirstChild("Exit")
	ui.duel = ui.game:FindFirstChild("OneVsOneMode")
	ui.timed = ui.game:FindFirstChild("TimedMode")
	ui.timedTimeLeft = path(ui.timed, { "TimeLeft" })
	InterfaceController.UpdateTimedTimer(ui, nil, nil)
	ui.home.Visible, ui.game.Visible = true, false
	if ui.duel then ui.duel.Visible = false end
	if ui.timed then ui.timed.Visible = true end
	ui.wordList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ui.wordList.CanvasSize = UDim2.new()
	ui.wordList.ScrollingDirection = Enum.ScrollingDirection.Y
	local wordLayout = ui.wordList:FindFirstChildOfClass("UIListLayout")
	if wordLayout then wordLayout.SortOrder = Enum.SortOrder.LayoutOrder end
	-- Preserve the authored UIListLayout, corners, strokes and sizes.
	local icon = ui.home:FindFirstChild("GameIcon")
	if icon then
		local base = icon.Rotation
		icon.Rotation = base - 2
		TweenService:Create(icon, TweenInfo.new(6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = base + 2 }):Play()
	end
	local waitingStroke = path(ui.waiting, { "Frame", "UIStroke" })
	if waitingStroke then
		waitingStroke.Thickness = 2
		TweenService:Create(waitingStroke, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = 1 }):Play()
	end
	if ui.duel then
		for _, name in ipairs({ "YouWinRate", "EnemyWinRate" }) do
			local node = ui.duel:FindFirstChild(name)
			if node then node.Visible = false end
		end
	end
	ui.queue = required(hud, { "Queue" })
	ui.queueContainer = required(ui.queue, { "Container" })
	ui.queueSubtitle = required(ui.queue, { "Subtitle" })
	ui.queueLeave = required(ui.queue, { "Exit" })
	ui.queueSolo = ui.queue:FindFirstChild("Solo")
	ui.queueTemplate = game:GetService("ReplicatedStorage"):WaitForChild("Assets"):WaitForChild("PlayerTemplate")
	ui.queueEntries = {}
	ui.queuePortraitRandom = Random.new()
	ui.queue.Visible = false
	for _, screen in ipairs({ ui.home, ui.game, ui.queue }) do Effects.AnimatePattern(screen:FindFirstChild("Pattern"), screen == ui.home) end
	ui.queueSubtitle.Text = "Standard Mode (15s)"
	local queueLayout = ui.queueContainer:FindFirstChildOfClass("UIGridLayout")
	if queueLayout then queueLayout.SortOrder = Enum.SortOrder.LayoutOrder end
	local pause = Instance.new("Frame")
	pause.Name = "RoundPause"
	pause.Size = UDim2.fromScale(1, 1)
	pause.BackgroundColor3 = Color3.new(1, 1, 1)
	pause.BackgroundTransparency = 0.08
	pause.ZIndex = 50
	pause.Active = true
	pause.Visible = false
	pause.Parent = hud
	ui.pause = pause
	text(pause, "Title", "PAUSED", UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.4, 0.1))
	ui.resume = button(pause, "Resume", "Resume", UDim2.fromScale(0.35, 0.46), UDim2.fromScale(0.3, 0.09))
	ui.leaveRound = button(pause, "Leave", "Leave round", UDim2.fromScale(0.35, 0.58), UDim2.fromScale(0.3, 0.09))
	for _, root in ipairs({ ui.home, ui.queue, pause }) do Effects.ApplyToAll(root) end
	if ui.frames then Effects.ApplyToAll(ui.frames) end
	Effects.Init(ui.hint)
	if ui.exit then Effects.Init(ui.exit) end
	return ui
end

function InterfaceController.StepHomePreviews(ui, dt, available)
	for _, animation in ipairs(ui.homeTilePreviews or {}) do animation:Step(dt, available) end
end

function InterfaceController.UpdateQueue(ui, members)
	local players = game:GetService("Players")
	if not members or #members == 0 then ui.queuePalette = nil end
	ui.queuePalette = ui.queuePalette or Effects.NewPortraitPalette(ui.queuePortraitRandom)
	local present = {}
	for index, member in ipairs(members or {}) do
		local userId = member.userId
		present[userId] = true
		local entry = ui.queueEntries[userId]
		if not entry then
			entry = ui.queueTemplate:Clone()
			entry.Name = "QueuePlayer_" .. userId
			entry.Visible = true
			entry.Parent = ui.queueContainer
			ui.queueEntries[userId] = entry
			Effects.PopIn(entry)
			local portrait = entry:FindFirstChild("YouMugshot")
			if portrait and (portrait:IsA("ImageLabel") or portrait:IsA("ImageButton")) then
				-- Choose once per queued card; roster refreshes retain the same color.
				local color = ui.queuePalette.Next()
				portrait.BackgroundColor3, portrait.BackgroundTransparency = color, 0
				local stroke = portrait:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.3) end
				portrait.Image = ""
				Effects.SetPortraitImage(portrait, member.thumbnailImage)
				if not member.isBot then task.spawn(function()
					local ok, image = pcall(players.GetUserThumbnailAsync, players, userId,
						Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
					if ok and entry.Parent and ui.queueEntries[userId] == entry then Effects.SetPortraitImage(portrait, image) end
				end) end
			end
		end
		entry.LayoutOrder = index
		local title = entry:FindFirstChild("Title")
		if title and (title:IsA("TextLabel") or title:IsA("TextButton")) then
			title.Text = member.displayName or member.name or tostring(userId)
		end
		local level = path(entry, { "Star", "Level" })
		if level then level.Text = tostring(member.level or 1) end
	end
	for userId, entry in pairs(ui.queueEntries) do
		if not present[userId] then
			ui.queueEntries[userId] = nil
			entry:Destroy()
		end
	end
end

function InterfaceController.UpdateQueueTimer(ui, seconds)
	ui.queueSubtitle.Text = string.format("Standard Mode (%ds)", math.max(0, math.ceil(seconds)))
end

-- Every gameplay mode displays its server-owned round deadline here.
-- Passing nil clears stale time without starting a local countdown.
function InterfaceController.UpdateTimedTimer(ui, remaining, duration)
	local valid = type(remaining) == "number" and remaining == remaining and math.abs(remaining) < math.huge
		and type(duration) == "number" and duration > 0 and duration < math.huge
	local seconds = valid and math.clamp(remaining, 0, duration) or 0
	local label = ui.timedTimeLeft
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		local rounded = math.ceil(seconds)
		label.Text = valid and string.format("%02d:%02d", math.floor(rounded / 60), rounded % 60) or "--:--"
	end
end

-- Keep a level-up flourish running while newer snapshots update its final target.
local function updateLevelFill(ui, root, fill, star, currentLevel, xp, requiredXp)
	local previous = ui.levelBarFeedback[root]
	if previous and previous.fill ~= fill then
		if previous.animation then previous.animation:Cancel() end
		previous = nil
	end
	if previous and previous.level == currentLevel and previous.xp == xp and previous.required == requiredXp then return end
	local gainedLevel = previous and currentLevel > previous.level
	local gainedXp = previous and (gainedLevel or (currentLevel == previous.level and xp > previous.xp))
	if previous and previous.celebrating and currentLevel >= previous.level then
		previous.level, previous.xp, previous.required = currentLevel, xp, requiredXp
		return
	end
	if previous and previous.animation then previous.animation:Cancel() end
	local state = {
		fill = fill, level = currentLevel, xp = xp, required = requiredXp,
		green = previous and previous.green or fill.BackgroundColor3,
		celebrating = gainedLevel == true,
	}
	ui.levelBarFeedback[root] = state
	local function valid()
		return ui.levelBarFeedback[root] == state and fill.Parent ~= nil and path(root, { "FillBar", "Fill" }) == fill
	end
	local function tween(duration, properties)
		state.animation = TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), properties)
		state.animation:Play()
	end
	local function settle()
		if not valid() then return end
		state.celebrating = false
		tween(0.5, {
			Size = UDim2.fromScale(math.clamp(state.xp / math.max(1, state.required), 0.1, 1), 1),
			BackgroundColor3 = state.green,
		})
	end
	if gainedLevel then
		local gold = Color3.fromRGB(255, 211, 92)
		tween(0.35, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = gold })
		if star then Effects.Pulse(star, 1.12) Effects.SoftHighlight(star, gold) end
		task.delay(0.47, function()
			if not valid() then return end
			tween(0.4, { Size = UDim2.fromScale(0.1, 1), BackgroundColor3 = state.green })
			task.delay(0.4, settle)
		end)
	else
		settle()
		if gainedXp then Effects.SoftHighlight(fill, state.green:Lerp(Color3.new(1, 1, 1), 0.45)) end
	end
end

-- Shared by the Home/Game bars and the authored outcome progress bar.
function InterfaceController.UpdateProgressFill(ui, root, progression)
	progression = progression or {}
	local level, xp = progression.level or 1, progression.xp or 0
	local required = progression.xpToNextLevel or Experience.RequiredForLevel(level)
	ui.levelBarFeedback = ui.levelBarFeedback or setmetatable({}, { __mode = "k" })
	local fill = root and path(root, { "FillBar", "Fill" })
	if fill then
		if fill.Size.X.Scale < 0.1 then fill.Size = UDim2.fromScale(0.1, 1) end
		updateLevelFill(ui, root, fill, root:FindFirstChild("Star"), level, xp, required)
	end
	return level, xp, required
end

-- One cancellable presentation shared by normal and Duel outcomes.
local outcomeSequences = setmetatable({}, { __mode = "k" })

function InterfaceController.CancelOutcome(frame)
	local sequence = frame and outcomeSequences[frame]
	if sequence then sequence.cancel() end
end

function InterfaceController.OutcomeButtonsReady(frame)
	local sequence = frame and outcomeSequences[frame]
	return not sequence or sequence.ready == true
end

local function totalExperience(progression)
	progression = progression or {}
	return Experience.TotalForLevel(progression.level or 1) + math.max(0, progression.xp or 0)
end

local function progressionAt(total)
	local level, xp, required = Experience.Resolve(math.max(0, total))
	return { level = level, xp = xp, xpToNextLevel = required }
end

function InterfaceController.UpdateOutcome(frame, progression)
	local sequence = frame and outcomeSequences[frame]
	if not sequence then return false end
	local total = math.max(sequence.targetTotal, totalExperience(progression))
	if total ~= sequence.targetTotal then
		sequence.targetTotal = total
		if sequence.barStarted then sequence.drawProgress() end
	end
	return true
end

function InterfaceController.OutcomeWords(found, total, duration)
	local words = string.format("%d/%d Words", found, total)
	if type(duration) ~= "number" or duration ~= duration or duration == math.huge then return words end
	if duration > 1800 then return words .. ": Scenic route!" end
	local seconds = math.max(0, math.floor(duration))
	return string.format("%s in %02d:%02d", words, math.floor(seconds / 60), seconds % 60)
end

function InterfaceController.PlayOutcome(owner, frame, result, progression)
	InterfaceController.CancelOutcome(frame)
	local awarded = math.max(0, math.floor(result.xpEarned or 0))
	local startTotal = result.beforeProgression and totalExperience(result.beforeProgression)
		or math.max(0, totalExperience(progression) - awarded)
	local before = progressionAt(startTotal)
	local sequence = { ready = false, targetTotal = math.max(startTotal + awarded, totalExperience(progression)),
		tweens = {}, originals = {}, connections = {}, barRevision = 0 }
	outcomeSequences[frame] = sequence
	local function valid() return outcomeSequences[frame] == sequence and frame.Parent ~= nil end
	local function later(seconds, callback)
		task.delay(seconds, function() if valid() and frame.Visible then callback() end end)
	end
	local function tween(node, seconds, properties, bounce)
		local animation = TweenService:Create(node, TweenInfo.new(seconds,
			bounce and Enum.EasingStyle.Back or Enum.EasingStyle.Sine, Enum.EasingDirection.Out), properties)
		table.insert(sequence.tweens, animation)
		animation:Play()
	end
	local function prepare(name, scaleIn)
		local node = frame:FindFirstChild(name)
		if not node or not node:IsA("GuiObject") then return nil end
		local original = { node = node, visible = node.Visible, active = node.Active, selectable = node.Selectable }
		if node:IsA("TextLabel") or node:IsA("TextButton") then original.alpha = node.TextTransparency end
		if scaleIn then
			original.scale = node:FindFirstChildOfClass("UIScale")
			original.created = not original.scale
			if not original.scale then
				original.scale = Instance.new("UIScale")
				original.scale.Name, original.scale.Parent = "OutcomeScale", node
			end
			original.size = original.scale.Scale
		end
		node.Visible = false
		if node:IsA("GuiButton") then node.Active, node.Selectable = false, false end
		table.insert(sequence.originals, original)
		return original
	end
	local words, xp = prepare("Words"), prepare("XPWon", true)
	local bar, current = prepare("FillBar", true), prepare("CurrentXP")
	local buttons = {}
	for _, name in ipairs({ "Play", "Rematch", "Home" }) do
		local button = prepare(name, true)
		if button then table.insert(buttons, button) end
	end
	local function reveal(original, fromScale)
		if not original then return end
		local node = original.node
		if node.Name == "Rematch" and frame:GetAttribute("RematchAvailable") ~= true then return end
		node.Visible = true
		if original.alpha ~= nil then
			node.TextTransparency = 1
			tween(node, 0.25, { TextTransparency = original.alpha })
		end
		if original.scale then
			original.scale.Scale = original.size * (fromScale or 0.8)
			tween(original.scale, 0.34, { Scale = original.size }, true)
		end
	end
	local function count(original, value, duration, format, eased)
		if not original then return end
		reveal(original)
		original.node.Text = format(0)
		local steps = math.min(30, value)
		for index = 1, steps do
			later(duration * index / steps, function()
				local fraction = index / steps
				if eased then fraction = 1 - (1 - fraction) ^ 3 end
				original.node.Text = format(math.floor(value * fraction + 0.5))
			end)
		end
	end
	owner.levelBarFeedback = owner.levelBarFeedback or setmetatable({}, { __mode = "k" })
	local fill = path(frame, { "FillBar", "Fill" })
	local previous = owner.levelBarFeedback[frame]
	if previous and previous.animation then previous.animation:Cancel() end
	local green = previous and previous.green or (fill and fill.BackgroundColor3)
	if fill then
		fill.Size, fill.BackgroundColor3 = UDim2.fromScale(math.clamp(before.xp / before.xpToNextLevel, 0.1, 1), 1), green
		owner.levelBarFeedback[frame] = { fill = fill, level = before.level, xp = before.xp,
			required = before.xpToNextLevel, green = green }
	end
	if current then current.node.Text = string.format("Level %d | %d / %d XP", before.level, before.xp, before.xpToNextLevel) end
	local function popButtons()
		local revision = sequence.barRevision
		for index, button in ipairs(buttons) do
			later((index - 1) * 0.10, function()
				if sequence.barRevision == revision then reveal(button, 0) end
			end)
		end
		later(0.35 + #buttons * 0.10, function()
			if sequence.barRevision ~= revision then return end
			sequence.ready = true
			for _, original in ipairs(sequence.originals) do
				if original.scale and original.scale.Parent then
					if original.created then original.scale:Destroy() else original.scale.Scale = original.size end
				end
			end
			for _, button in ipairs(buttons) do
				button.node.Active, button.node.Selectable = button.active, button.selectable
			end
		end)
	end
	sequence.drawProgress = function()
		if not valid() then return end
		local target = progressionAt(sequence.targetTotal)
		local feedback = owner.levelBarFeedback[frame]
		local levelUp = feedback and (feedback.celebrating or target.level > feedback.level)
		InterfaceController.UpdateProgressFill(owner, frame, target)
		if current then current.node.Text = string.format("Level %d | %d / %d XP", target.level, target.xp, target.xpToNextLevel) end
		if not sequence.ready then
			for _, button in ipairs(buttons) do button.node.Visible = false end
			sequence.barRevision += 1
			local revision = sequence.barRevision
			later(levelUp and 1.40 or 0.55, function()
				if sequence.barRevision == revision then popButtons() end
			end)
		end
	end
	sequence.cancel = function()
		if outcomeSequences[frame] ~= sequence then return end
		outcomeSequences[frame] = nil
		for _, animation in ipairs(sequence.tweens) do animation:Cancel() end
		for _, connection in ipairs(sequence.connections) do connection:Disconnect() end
		local feedback = owner.levelBarFeedback[frame]
		if feedback and feedback.animation then feedback.animation:Cancel() end
		owner.levelBarFeedback[frame] = nil
		if fill and fill.Parent then fill.BackgroundColor3 = green end
		for _, original in ipairs(sequence.originals) do
			local node = original.node
			if node.Parent then
				node.Visible, node.Active, node.Selectable = original.visible, original.active, original.selectable
				if original.alpha ~= nil then node.TextTransparency = original.alpha end
				if original.scale then
					if original.created then original.scale:Destroy()
					elseif original.scale.Parent then original.scale.Scale = original.size end
				end
			end
		end
	end
	table.insert(sequence.connections, frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then sequence.cancel() end
	end))
	table.insert(sequence.connections, frame.Destroying:Connect(sequence.cancel))
	local found = math.max(0, math.floor(result.words or result.foundCount or 0))
	local total = math.max(found, math.floor(result.total or result.wordCount or 0))
	local wordDuration = math.clamp(found * 0.08, 0.45, 1.05)
	later(0.30, function()
		count(words, found, wordDuration, function(n) return InterfaceController.OutcomeWords(n, total, n == found and result.duration or nil) end)
		later(wordDuration + 0.12, function()
			count(xp, awarded, 0.80, function(n) return string.format("+%d XP", n) end, true)
			later(0.95, function()
				reveal(bar, 0.94)
				reveal(current)
				later(0.30, function() sequence.barStarted = true sequence.drawProgress() end)
			end)
		end)
	end)
end

function InterfaceController.UpdateLevelBars(ui, progression)
	progression = progression or {}
	local currentLevel = progression.level or 1
	local xp, requiredXp = progression.xp or 0, progression.xpToNextLevel or Experience.RequiredForLevel(currentLevel)
	ui.levelBarFeedback = ui.levelBarFeedback or setmetatable({}, { __mode = "k" })
	local rewardLevel = currentLevel + (currentLevel % 2 == 0 and 2 or 1)
	local rewardHints = Experience.HintsForLevel(rewardLevel)
	for _, root in ipairs({ ui.home:FindFirstChild("LevelBar"), ui.game:FindFirstChild("LevelBar") }) do
		if root then
			local label = root:FindFirstChild("XP")
			if label then label.Text = string.format("%d / %d XP", xp, requiredXp) end
			local star = root:FindFirstChild("Star")
			local level = star and (star:FindFirstChild("TextLabel") or star:FindFirstChild("Level") or star:FindFirstChildWhichIsA("TextLabel", true))
			if not level and star then
				level = text(star, "Level", "", UDim2.fromScale(0.18, 0.18), UDim2.fromScale(0.64, 0.64))
				level.ZIndex = star.ZIndex + 1
			end
			if level then level.Text = tostring(currentLevel) end
			local nextTitle = root:FindFirstChild("NextLevelTitle")
			if nextTitle then
				nextTitle.Visible = root ~= ui.game:FindFirstChild("LevelBar")
				nextTitle.Text = string.format("LEVEL %d REWARD", rewardLevel)
			end
			local rewardTitle = root:FindFirstChild("NextLevelRewardTitle")
			if rewardTitle then
				rewardTitle.Visible = root ~= ui.game:FindFirstChild("LevelBar")
				rewardTitle.Text = string.format("+%d Hint%s", rewardHints, rewardHints == 1 and "" or "s")
			end
			local rewardIcon = root:FindFirstChild("NextLevelRewardIcon")
			if rewardIcon then rewardIcon.Visible = root ~= ui.game:FindFirstChild("LevelBar") end
			local fill = path(root, { "FillBar", "Fill" })
			if fill then
				if fill.Size.X.Scale < 0.1 then
					fill.Size = UDim2.new(0.1, 0, fill.Size.Y.Scale, fill.Size.Y.Offset)
				end
				updateLevelFill(ui, root, fill, star, currentLevel, xp, requiredXp)
			end
		end
	end
end

InterfaceController.Path = path
InterfaceController.Components = Components
return InterfaceController
