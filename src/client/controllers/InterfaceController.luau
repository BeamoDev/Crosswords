local TweenService = game:GetService("TweenService")

-- Button state and action wiring.
local Buttons = {}

function Buttons.new(config)
	local ui = config.ui
	local state = config.state
	local colors = config.colors
	local runtimeHelpers = config.runtimeHelpers
	local uiEffects = config.uiEffects
	local ensureScaleController = config.ensureScaleController
	local bindButtonHoverSound = config.bindButtonHoverSound
	local tween = config.tween
	local findButtonLike = config.findButtonLike
	local api = {}

	local function setBaseColor(button, color)
		button:SetAttribute("BaseColor", color)
		uiEffects.SetBaseColor(button, color)
	end

	local function getBaseColor(button)
		return button:GetAttribute("BaseColor") or colors.button
	end

	function api.setBaseColor(button, color)
		if not button then
			return
		end

		setBaseColor(button, color)
	end

	function api.setEnabled(button, enabled, color)
		if not button then
			return
		end

		if color then
			setBaseColor(button, color)
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)

		tween(button, {
			BackgroundColor3 = enabled and getBaseColor(button) or colors.board,
			BackgroundTransparency = enabled and 0 or 0.2,
			TextColor3 = enabled and colors.text or colors.textMuted,
		}, 0.14)

		if button:FindFirstChild("ScaleController") and not enabled then
			tween(button.ScaleController, { Scale = 1 }, 0.08)
		end
	end

	function api.setInteractivityOnly(button, enabled)
		if not button then
			return
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)

		tween(button, {
			BackgroundTransparency = enabled and 0 or 0.2,
		}, 0.14)

		if button:FindFirstChild("ScaleController") and not enabled then
			tween(button.ScaleController, { Scale = 1 }, 0.08)
		end
	end

	function api.setClickableOnly(button, enabled)
		if not button then
			return
		end

		button.Active = enabled
		button.Selectable = enabled
		button:SetAttribute("ButtonEnabled", enabled)
	end

	function api.prepare(button, color, hoverBrightness)
		if not button or not button:IsA("GuiButton") then
			return
		end

		ensureScaleController(button)
		setBaseColor(button, color or button.BackgroundColor3)
		bindButtonHoverSound(button)
		uiEffects.Init(button, {
			baseColor = color or button.BackgroundColor3,
			hoverScale = 1.04,
			pressScale = 0.96,
			hoverBrightness = hoverBrightness == nil and 0.08 or hoverBrightness,
		})
	end

	function api.wireActions()
		local function bindHintControl(button)
			if not button or not button:IsA("GuiButton") or button:GetAttribute("WordSearchBound") then
				return
			end

			button:SetAttribute("WordSearchBound", true)
			button.Activated:Connect(function()
				if runtimeHelpers.showHint then
					runtimeHelpers.showHint()
				end
			end)
		end

		bindHintControl(ui.hintButton)
		if ui.hintRoot and ui.hintRoot ~= ui.hintButton then
			bindHintControl(findButtonLike(ui.hintRoot))
			if not ui.hintRoot:IsA("GuiButton") and not ui.hintRoot:GetAttribute("WordSearchHintFrameBound") then
				ui.hintRoot:SetAttribute("WordSearchHintFrameBound", true)
				ui.hintRoot.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						if runtimeHelpers.showHint then
							runtimeHelpers.showHint()
						end
					end
				end)
			end
		end

		if ui.menuModeNextButton and not ui.menuModeNextButton:GetAttribute("WordSearchBound") then
			ui.menuModeNextButton:SetAttribute("WordSearchBound", true)
			ui.menuModeNextButton.Activated:Connect(function()
				if config.isInteractionBlocked() then
					return
				end

				state.menuModeIndex = (state.menuModeIndex % #config.modeOrder) + 1
				config.refreshModeButtons()
			end)
		end

		if ui.menuModePrevButton and not ui.menuModePrevButton:GetAttribute("WordSearchBound") then
			ui.menuModePrevButton:SetAttribute("WordSearchBound", true)
			ui.menuModePrevButton.Activated:Connect(function()
				if config.isInteractionBlocked() then
					return
				end

				state.menuModeIndex = ((state.menuModeIndex - 2) % #config.modeOrder) + 1
				config.refreshModeButtons()
			end)
		end

		if ui.menuPlayButton and not ui.menuPlayButton:GetAttribute("WordSearchBound") then
			ui.menuPlayButton:SetAttribute("WordSearchBound", true)
			ui.menuPlayButton.Activated:Connect(function()
				config.handleMenuPlayPressed()
			end)
		end

		if ui.menuDuelButton and not ui.menuDuelButton:GetAttribute("WordSearchBound") then
			ui.menuDuelButton:SetAttribute("WordSearchBound", true)
			ui.menuDuelButton.Activated:Connect(function()
				if config.isInteractionBlocked() or not state.duelController then
					return
				end

				config.playSound("OpenFrame")
				state.duelController:showLobby()
			end)
		end

		if ui.exitButton and not ui.exitButton:GetAttribute("WordSearchBound") then
			ui.exitButton:SetAttribute("WordSearchBound", true)
			ui.exitButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() then
					return
				end

				config.playSound("Button2")
				config.exitCurrentMode()
			end)
		end

		if ui.nextButton and not ui.nextButton:GetAttribute("WordSearchBound") then
			ui.nextButton:SetAttribute("WordSearchBound", true)
			ui.nextButton.Activated:Connect(function()
				if config.isGameplayInteractionBlocked() or not state.gameViewActive then
					return
				end

				config.playSound("Button2")
				if state.mode == "Classic" then
					if state.puzzleIndex < config.getLevelsCount() then
						config.transitionToPuzzle(state.puzzleIndex + 1)
					end
				else
					config.transitionToPuzzle(
						config.chooseModeLevelIndex(state.mode),
						config.nextSeed(state.sessionScore + state.puzzlesCleared + 1)
					)
				end
			end)
		end

		if ui.summaryButton and not ui.summaryButton:GetAttribute("WordSearchBound") then
			ui.summaryButton:SetAttribute("WordSearchBound", true)
			ui.summaryButton.Activated:Connect(function()
				if ui.summaryButton:GetAttribute("ButtonEnabled") == false
					or state.summaryGiftClaimPending == true
					or state.summaryGiftSequenceActive == true then
					return
				end
				config.playSound("Button2")
				if state.summaryAction then
					state.summaryAction()
				end
			end)
		end

		if ui.summaryGiftButton and not ui.summaryGiftButton:GetAttribute("WordSearchBound") then
			ui.summaryGiftButton:SetAttribute("WordSearchBound", true)
			ui.summaryGiftButton.Activated:Connect(function()
				if config.claimSummaryGift then
					config.playSound("Button2")
					config.claimSummaryGift()
				end
			end)
		end
	end

	return api
end


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


-- Menu/game view transitions.
local Transitions = {}

local function getTransitionTween(layout)
	return layout.ViewTweenSlide or layout.ViewTweenIn or layout.ViewTweenOut
end

local function getStackedTravelOffset(layout, movingFrame, referenceFrame)
	local movingHeight = movingFrame and movingFrame.AbsoluteSize.Y or 0
	local referenceHeight = referenceFrame and referenceFrame.AbsoluteSize.Y or 0
	local travelHeight = math.max(movingHeight, referenceHeight, 0)
	local overlapPixels = math.max(0, math.floor(tonumber(layout.ViewStackedOverlapPixels) or 0))
	if travelHeight <= 0 then
		travelHeight = overlapPixels
	end

	return math.max(0, travelHeight - overlapPixels)
end

local function getStackedPosition(basePosition, layout, movingFrame, referenceFrame, direction)
	local offset = getStackedTravelOffset(layout, movingFrame, referenceFrame) * direction
	return UDim2.new(
		basePosition.X.Scale,
		basePosition.X.Offset,
		basePosition.Y.Scale,
		basePosition.Y.Offset + offset
	)
end

function Transitions.showMenuView(context, animate, onComplete)
	local ui = context.ui
	local state = context.state
	local layout = context.layout
	local tween = context.tween
	local refreshUiBindings = context.refreshUiBindings
	local updateHud = context.updateHud

	if not ui.menu then
		state.gameViewActive = false
		refreshUiBindings()
		if onComplete then
			onComplete()
		end
		return
	end

	local function finish()
		state.viewTransitionBusy = false
		state.gameViewActive = false
		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
			ui.game.Size = ui.gameOpenSize or ui.game.Size
		end
		ui.menu.Visible = true
		ui.menu.Position = ui.menuOpenPosition or layout.ViewCenterPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		refreshUiBindings()
		updateHud()
		if onComplete then
			onComplete()
		end
	end

	if not animate or not ui.game then
		ui.menu.Visible = true
		ui.menu.Position = ui.menuOpenPosition or layout.ViewCenterPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
			ui.game.Size = ui.gameOpenSize or ui.game.Size
		end
		finish()
		return
	end

	local transitionTween = getTransitionTween(layout)
	local menuOpenPosition = ui.menuOpenPosition or layout.ViewCenterPosition
	local menuEntryPosition = getStackedPosition(menuOpenPosition, layout, ui.menu, ui.game, 1)
	local gameExitPosition = getStackedPosition(menuOpenPosition, layout, ui.game, ui.menu, -1)

	state.viewTransitionBusy = true
	state.gameViewActive = false
	ui.menu.Visible = true
	ui.menu.Position = menuEntryPosition
	ui.menu.Size = ui.menuOpenSize or ui.menu.Size
	ui.game.Visible = true
	ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
	ui.game.Size = ui.gameOpenSize or ui.game.Size
	refreshUiBindings()

	tween(ui.game, { Position = gameExitPosition }, transitionTween)
	tween(ui.menu, { Position = menuOpenPosition }, transitionTween)
	task.delay(transitionTween.Time + 0.02, function()
		if not state.viewTransitionBusy then
			return
		end

		if ui.game then
			ui.game.Visible = false
			ui.game.Position = layout.ViewGameHiddenPosition
		end
		ui.menu.Visible = true
		ui.menu.Position = menuOpenPosition
		ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		refreshUiBindings()
		finish()
	end)
end

function Transitions.showGameView(context, animate, onComplete)
	local ui = context.ui
	local state = context.state
	local layout = context.layout
	local tween = context.tween
	local refreshUiBindings = context.refreshUiBindings
	local updateHud = context.updateHud

	if not ui.game then
		state.gameViewActive = true
		refreshUiBindings()
		if onComplete then
			onComplete()
		end
		return
	end

	local function finish()
		state.viewTransitionBusy = false
		state.gameViewActive = true
		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
			ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		end
		ui.game.Visible = true
		ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		refreshUiBindings()
		updateHud()
		if onComplete then
			onComplete()
		end
	end

	if not animate or not ui.menu then
		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
			ui.menu.Size = ui.menuOpenSize or ui.menu.Size
		end
		ui.game.Visible = true
		ui.game.Position = ui.gameOpenPosition or layout.ViewCenterPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		finish()
		return
	end

	local transitionTween = getTransitionTween(layout)
	local menuOpenPosition = ui.menuOpenPosition or layout.ViewCenterPosition
	local gameOpenPosition = ui.gameOpenPosition or layout.ViewCenterPosition
	local menuExitPosition = getStackedPosition(gameOpenPosition, layout, ui.menu, ui.game, 1)
	local gameEntryPosition = getStackedPosition(gameOpenPosition, layout, ui.game, ui.menu, -1)

	state.viewTransitionBusy = true
	ui.menu.Visible = true
	ui.menu.Position = menuOpenPosition
	ui.menu.Size = ui.menuOpenSize or ui.menu.Size
	ui.game.Visible = true
	ui.game.Position = gameEntryPosition
	ui.game.Size = ui.gameOpenSize or ui.game.Size
	refreshUiBindings()

	tween(ui.menu, { Position = menuExitPosition }, transitionTween)
	tween(ui.game, { Position = gameOpenPosition }, transitionTween)
	task.delay(transitionTween.Time + 0.02, function()
		if not state.viewTransitionBusy then
			return
		end

		if ui.menu then
			ui.menu.Visible = false
			ui.menu.Position = layout.ViewMenuHiddenPosition
		end
		ui.game.Visible = true
		ui.game.Position = gameOpenPosition
		ui.game.Size = ui.gameOpenSize or ui.game.Size
		refreshUiBindings()
		finish()
	end)
end


-- Classic level selection components.
local ClassicLevels = {}
local LEVEL_CARD_VISUALS = {
	locked = {
		cardColor = Color3.fromRGB(46, 46, 46),
		textColor = Color3.fromRGB(232, 232, 232),
	},
	playable = {
		cardColor = Color3.fromRGB(78, 176, 92),
		textColor = Color3.fromRGB(255, 255, 255),
	},
	completed = {
		cardColor = Color3.fromRGB(38, 112, 52),
		textColor = Color3.fromRGB(255, 255, 255),
	},
}

local function applyBranchBackgroundColor(root, color)
	if not root then
		return
	end

	if root:IsA("GuiObject") then
		root.BackgroundColor3 = color
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.BackgroundColor3 = color
		end
	end
end

function ClassicLevels.getClassicLevelStarCount(state, Dependencies, levelNumber)
	local resolvedLevel = math.clamp(math.floor(tonumber(levelNumber) or 1), 1, #Dependencies.Levels)
	local slot = Dependencies.StarRules.ResolveSlot("Classic", resolvedLevel)
	local modeBucket = type(state.starProgress[slot.mode]) == "table" and state.starProgress[slot.mode] or nil
	local packBucket = modeBucket and type(modeBucket[slot.pack]) == "table" and modeBucket[slot.pack] or nil
	return math.clamp(math.floor(tonumber(packBucket and packBucket[slot.entry]) or 0), 0, 3)
end

function ClassicLevels.getHighestReachedClassicLevel(state, Dependencies)
	local savedClassicLevel = math.max(1, math.floor(tonumber(state.savedClassicLevel) or 1))
	local highestStarredLevel = 0

	for levelNumber = 1, #Dependencies.Levels do
		if ClassicLevels.getClassicLevelStarCount(state, Dependencies, levelNumber) > 0 then
			highestStarredLevel = levelNumber
		end
	end

	return math.clamp(math.max(highestStarredLevel, savedClassicLevel - 1), 0, #Dependencies.Levels)
end

function ClassicLevels.isClassicLevelCompleted(state, Dependencies, levelNumber)
	local resolvedLevel = math.clamp(math.floor(tonumber(levelNumber) or 1), 1, #Dependencies.Levels)
	return resolvedLevel <= ClassicLevels.getHighestReachedClassicLevel(state, Dependencies)
end

function ClassicLevels.getCompletedClassicLevelsCount(state, Dependencies)
	return ClassicLevels.getHighestReachedClassicLevel(state, Dependencies)
end

function ClassicLevels.getHighestCompletedClassicLevel(state, Dependencies)
	return ClassicLevels.getHighestReachedClassicLevel(state, Dependencies)
end

function ClassicLevels.getClassicUnlockedLevel(state, Dependencies)
	local savedClassicLevel = math.max(1, math.floor(tonumber(state.savedClassicLevel) or 1))
	local highestCompletedLevel = ClassicLevels.getHighestCompletedClassicLevel(state, Dependencies)
	local progressedLevel = highestCompletedLevel >= #Dependencies.Levels and #Dependencies.Levels or (highestCompletedLevel + 1)

	return math.clamp(math.max(savedClassicLevel, progressedLevel), 1, #Dependencies.Levels)
end

function ClassicLevels.getClassicContinueLevel(state, Dependencies)
	local resumeBoardState = type(state.resumeBoardState) == "table" and state.resumeBoardState or nil
	local unlockedLevel = ClassicLevels.getClassicUnlockedLevel(state, Dependencies)
	if resumeBoardState and resumeBoardState.mode == "Classic" then
		local resumeLevel = math.clamp(math.floor(tonumber(resumeBoardState.level) or unlockedLevel), 1, #Dependencies.Levels)
		if resumeLevel == unlockedLevel then
			return resumeLevel
		end
	end

	return unlockedLevel
end

function ClassicLevels.applyClassicLevelStarVisual(starNode, isEarned)
	if not starNode then
		return
	end

	if starNode:IsA("ImageLabel") or starNode:IsA("ImageButton") then
		starNode.ImageColor3 = isEarned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(75, 75, 75)
		starNode.ImageTransparency = isEarned and 0 or 0.5
	end

	if starNode:IsA("GuiObject") then
		starNode.Visible = true
	end
end

function ClassicLevels.getClassicLevelTemplate(ui, ReplicatedStorage)
	local template = ui.levelTemplate
	if template and template.Parent then
		return template
	end

	template = ReplicatedStorage:FindFirstChild("Level", true)
	if not (template and template:IsA("GuiObject")) then
		template = ReplicatedStorage:FindFirstChild("LevelTemplate", true)
	end

	if template and template:IsA("GuiObject") then
		ui.levelTemplate = template
		return template
	end

	return nil
end

function ClassicLevels.resolveClassicLevelLabel(root, findDescendantByNames)
	if not root then
		return nil
	end

	local named = findDescendantByNames(root, { "Number", "LevelNumber", "Label", "TextLabel", "Level" }, nil)
	if named and (named:IsA("TextLabel") or named:IsA("TextButton")) then
		return named
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
			and not descendant:FindFirstAncestor("Completed")
			and not descendant:FindFirstAncestor("Locked") then
			return descendant
		end
	end

	return nil
end

function ClassicLevels.getClassicLevelVisualState(isUnlocked, starCount, isCompleted)
	if isCompleted == true or starCount > 0 then
		return "completed", LEVEL_CARD_VISUALS.completed
	end

	if isUnlocked then
		return "playable", LEVEL_CARD_VISUALS.playable
	end

	return "locked", LEVEL_CARD_VISUALS.locked
end

function ClassicLevels.applyClassicLevelVisualState(entry, isUnlocked, starCount, isCompleted, findDescendantByNames)
	if type(entry) ~= "table" then
		return
	end

	local visualKey, visualState = ClassicLevels.getClassicLevelVisualState(isUnlocked, starCount, isCompleted)
	local completedNode = entry.completedNode
	local completedFrame = completedNode and (
		completedNode:FindFirstChild("Frame")
			or findDescendantByNames(completedNode, { "Frame" }, nil)
	) or nil
	local lockedNode = entry.lockedNode

	applyBranchBackgroundColor(entry.root, visualState.cardColor)
	applyBranchBackgroundColor(completedNode, visualState.cardColor)
	applyBranchBackgroundColor(completedFrame, visualState.cardColor)
	applyBranchBackgroundColor(lockedNode, LEVEL_CARD_VISUALS.locked.cardColor)

	if entry.label and (entry.label:IsA("TextLabel") or entry.label:IsA("TextButton")) then
		entry.label.TextColor3 = visualState.textColor
	end

	if completedNode and completedNode:IsA("GuiObject") then
		completedNode.Visible = visualKey == "completed"
	end

	if lockedNode and lockedNode:IsA("GuiObject") then
		lockedNode.Visible = visualKey == "locked"
		for _, descendant in ipairs(lockedNode:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.TextColor3 = LEVEL_CARD_VISUALS.locked.textColor
			end
		end
	end
end

function ClassicLevels.createClassicLevelEntry(env, levelNumber)
	local ui = env.ui
	local container = ui.levelsContainer
	if not (container and container.Parent) then
		return nil
	end

	local template = ClassicLevels.getClassicLevelTemplate(ui, env.ReplicatedStorage)
	local root
	if template then
		root = template:Clone()
		root.Visible = true
	else
		root = env.create("Frame", {
			Name = "LevelCard",
			BackgroundColor3 = Color3.fromRGB(78, 176, 92),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(100, 100),
			Visible = true,
			Parent = container,
		})
		env.create("UICorner", {
			Name = "Corner",
			CornerRadius = UDim.new(0, 10),
			Parent = root,
		})
	end

	root.Name = "Level_" .. tostring(levelNumber)
	root.LayoutOrder = levelNumber
	root:SetAttribute("WordSearchLevelEntry", true)
	root.Parent = container

	if root:IsA("GuiButton") then
		root.Text = ""
	end

	local aspect = root:FindFirstChildWhichIsA("UIAspectRatioConstraint")
	if not aspect then
		aspect = env.create("UIAspectRatioConstraint", {
			Name = "Aspect",
			AspectRatio = 1,
			Parent = root,
		})
	end

	local label = ClassicLevels.resolveClassicLevelLabel(root, env.findDescendantByNames)
	if not label then
		label = env.create("TextLabel", {
			Name = "TextLabel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.fromScale(0.68, 0.38),
			Text = "",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			ZIndex = (root.ZIndex or 1) + 1,
			Parent = root,
		})
	end

	local pressable = env.findButtonLike(root)
	if not pressable then
		pressable = env.create("TextButton", {
			Name = "Pressable",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			Text = "",
			ZIndex = (root.ZIndex or 1) + 2,
			Parent = root,
		})
	end

	local completedNode = root:FindFirstChild("Completed") or env.findDescendantByNames(root, { "Completed" }, nil)
	local lockedNode = root:FindFirstChild("Locked") or env.findDescendantByNames(root, { "Locked" }, nil)
	local starRoot = completedNode or root
	local starOne = env.findDescendantByNames(starRoot, { "StarOne" }, nil)
	local starTwo = env.findDescendantByNames(starRoot, { "StarTwo" }, nil)
	local starThree = env.findDescendantByNames(starRoot, { "StarThree" }, nil)

	if pressable and pressable:IsA("GuiButton") then
		env.ButtonUi.prepare(pressable)
		if not pressable:GetAttribute("WordSearchLevelBound") then
			pressable:SetAttribute("WordSearchLevelBound", true)
			pressable.Activated:Connect(function()
				env.startClassicLevelFromSelector(tonumber(root:GetAttribute("ClassicLevel")) or levelNumber)
			end)
		end
	end

	local entry = {
		root = root,
		label = label,
		pressable = pressable,
		completedNode = completedNode,
		lockedNode = lockedNode,
		starOne = starOne,
		starTwo = starTwo,
		starThree = starThree,
	}
	ui.levelEntries[levelNumber] = entry
	return entry
end


-- Shared client-only visual effects are replicated for authored HUD scripts too.
local UIEffects = require(
	game:GetService("ReplicatedStorage"):WaitForChild("shared"):WaitForChild("ui"):WaitForChild("UIEffects")
)

local Components = {
	Buttons = Buttons,
	Gui = Gui,
	Transitions = Transitions,
	ClassicLevels = ClassicLevels,
	Effects = UIEffects,
}


local Interface = {}

local function isGameplayHudScreenGui(gui)
	return gui
		and gui:IsA("ScreenGui")
		and (
			gui.Name == "HUD"
			or gui.Name == "Desktop"
			or gui.Name == "Mobile"
			or (gui:FindFirstChild("Game") and gui:FindFirstChild("Frames"))
		)
end

function Interface.findHUD(playerGui, timeoutSeconds)
	local timeoutAt = tick() + math.max(0.1, tonumber(timeoutSeconds) or 10)

	repeat
		local directHUD = playerGui:FindFirstChild("HUD")
		local desktopHUD = playerGui:FindFirstChild("Desktop")
		local mobileHUD = playerGui:FindFirstChild("Mobile")
		if isGameplayHudScreenGui(directHUD) then
			return directHUD
		end
		if isGameplayHudScreenGui(desktopHUD) then
			return desktopHUD
		end
		if isGameplayHudScreenGui(mobileHUD) then
			return mobileHUD
		end

		for _, child in ipairs(playerGui:GetChildren()) do
			if isGameplayHudScreenGui(child) then
				return child
			end
		end

		task.wait(0.1)
	until tick() >= timeoutAt

	return nil
end

function Interface.isMobileInterface(userInputService)
	return userInputService.TouchEnabled and not userInputService.KeyboardEnabled
end

function Interface.removeExistingHUDs(playerGui)
	for _, child in ipairs(playerGui:GetChildren()) do
		if isGameplayHudScreenGui(child) then
			child:Destroy()
		end
	end
end

function Interface.ensurePlatformHUD(playerGui, interfacesFolder, userInputService)
	if not playerGui then
		return nil
	end

	if not interfacesFolder then
		return Interface.findHUD(playerGui, 1)
	end

	local templateName = Interface.isMobileInterface(userInputService) and "Mobile" or "Desktop"
	local template = interfacesFolder:FindFirstChild(templateName)
	if not (template and template:IsA("ScreenGui")) then
		return Interface.findHUD(playerGui, 1)
	end

	Interface.removeExistingHUDs(playerGui)

	local clonedHUD = template:Clone()
	clonedHUD.Name = "HUD"
	clonedHUD.ResetOnSpawn = false
	clonedHUD.Enabled = false
	clonedHUD.Parent = playerGui
	return clonedHUD
end


-- Authored HUD discovery and binding.
local InterfaceController = {}

function InterfaceController.create(env)
local player = env.player
local UserInputService = env.UserInputService

local RuntimeHelpers = env.RuntimeHelpers
local Dependencies = env.Dependencies
local state = env.state
local ui = env.ui

local create = env.create
local waitForDescendantByNames = env.waitForDescendantByNames
local findDescendantByNames = env.findDescendantByNames
local findFirstPath = env.findFirstPath
local findTextObject = env.findTextObject
local ensureScaleController = env.ensureScaleController
local findButtonLike = env.findButtonLike
local bindButtonHoverSound = env.bindButtonHoverSound
local applyTextFont = env.applyTextFont
local getWordRowTemplate = env.getWordRowTemplate
local syncBoardContentLayout = env.syncBoardContentLayout
local createDragLineObjects = env.createDragLineObjects
local refreshPersistentLines = env.refreshPersistentLines
local ButtonUi = env.ButtonUi
local COLORS = env.COLORS
local DEFAULT_WORD_ROW_COLOR = env.DEFAULT_WORD_ROW_COLOR
local DEFAULT_WORD_ROW_TRANSPARENCY = env.DEFAULT_WORD_ROW_TRANSPARENCY
local BOARD_STROKE_HIDDEN_TRANSPARENCY = env.BOARD_STROKE_HIDDEN_TRANSPARENCY
local LAYOUT = env.LAYOUT
local DUEL_MODE_MIN_FILL_SCALE = env.DUEL_MODE_MIN_FILL_SCALE
local MODAL_PARENT_OPEN_TRANSPARENCY = env.MODAL_PARENT_OPEN_TRANSPARENCY
local updateWordsLabel = env.updateWordsLabel

local function resolveOverlayOpenTransparency(value)
	local resolved = tonumber(value)
	if resolved == nil or resolved >= 0.95 then
		return MODAL_PARENT_OPEN_TRANSPARENCY
	end

	return math.clamp(resolved, 0, 0.95)
end

local function resolveCardOpenTransparency(value, fallback)
	local resolved = tonumber(value)
	if resolved == nil or resolved >= 0.95 then
		return fallback
	end

	return math.clamp(resolved, 0, 0.95)
end

function RuntimeHelpers.bindExistingUI()
	local runtimePlayerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
	local existingGui = Dependencies.InterfaceBootstrap.findHUD(runtimePlayerGui, 15)
		or runtimePlayerGui:WaitForChild("HUD")
	local gameFrame = existingGui:FindFirstChild("Game") or waitForDescendantByNames(existingGui, { "Game" }, nil)
	local menuFrame = existingGui:FindFirstChild("Menu") or findDescendantByNames(existingGui, { "Menu" }, nil)
	local framesRoot = existingGui:FindFirstChild("Frames") or findDescendantByNames(existingGui, { "Frames" }, nil)
	local contentFrame = findDescendantByNames(gameFrame or existingGui, { "ContentFrame" }, nil)
	local boardColumn = contentFrame and findDescendantByNames(contentFrame, { "BoardColumn" }, nil) or nil
	local boardHolder = boardColumn and findDescendantByNames(boardColumn, { "BoardHolder" }, nil) or nil
	if not boardHolder then
		boardHolder = boardColumn and findDescendantByNames(boardColumn, { "BoardFrame" }, nil) or nil
	end
	if not boardHolder then
		boardHolder = waitForDescendantByNames(gameFrame or existingGui, { "Board", "BoardHolder" }, nil)
	end
	local boardFrame = boardHolder
	local gameTopBar = gameFrame and (gameFrame:FindFirstChild("TopBar") or findDescendantByNames(gameFrame, { "TopBar" }, nil)) or nil
	local gameTopBarContainer = gameTopBar and (gameTopBar:FindFirstChild("Container") or findDescendantByNames(gameTopBar, { "Container" }, nil)) or gameTopBar
	local menuActionRow = menuFrame and findDescendantByNames(menuFrame, { "ActionRow" }, nil) or nil
	local menuPlayRoot = menuActionRow and findDescendantByNames(menuActionRow, { "Play" }, nil)
		or (menuFrame and findDescendantByNames(menuFrame, { "Play" }, nil))
	local menuDuelRoot = menuActionRow and findDescendantByNames(menuActionRow, { "Duel", "Duels" }, nil)
		or (menuFrame and findDescendantByNames(menuFrame, { "Duel", "Duels" }, nil))
	local menuModeCarousel = menuFrame and findDescendantByNames(menuFrame, { "ModeCarousel" }, nil) or nil
	local hintRoot = gameTopBarContainer and (gameTopBarContainer:FindFirstChild("Hint") or findDescendantByNames(gameTopBarContainer, { "Hint" }, nil)) or nil
	if not hintRoot then
		hintRoot = gameFrame and (gameFrame:FindFirstChild("Hint") or nil) or nil
	end
	if not hintRoot then
		hintRoot = findDescendantByNames(gameFrame or existingGui, { "Hint" }, nil)
	end
	local hintButton = findButtonLike(
		(hintRoot and (hintRoot:FindFirstChild("HintButton", true) or hintRoot)) or findDescendantByNames(gameTopBarContainer or gameFrame or existingGui, { "HintButton" }, nil)
	)
	if not hintButton then
		hintButton = findButtonLike(findDescendantByNames(gameTopBarContainer or gameFrame or existingGui, { "HintButton", "Hint" }, nil))
	end
	local nextButton = findButtonLike(findDescendantByNames(gameFrame or existingGui, { "NextButton" }, nil))
	for _, retiredControlName in ipairs({ "TimedMode", "MoreTime", "Freeze", "RuntimeCombo", "TimedCombo", "Warning" }) do
		local retiredControl = findDescendantByNames(gameFrame or existingGui, { retiredControlName }, nil)
		if retiredControl and retiredControl:IsA("GuiObject") then
			retiredControl.Visible = false
			retiredControl.Active = false
		end
	end
	local duelModeRoot = RuntimeHelpers.ensureDuelModeUi(gameFrame)
	local modeBar = findDescendantByNames(gameFrame or existingGui, { "ModeBar" }, nil)
	local infoBar = findDescendantByNames(gameFrame or existingGui, { "InfoBar" }, nil)
	local previousButton = gameFrame and findDescendantByNames(gameFrame, { "PreviousButton", "Previous" }, nil) or nil
	local streakRoot = findDescendantByNames(gameFrame or existingGui, { "Streak" }, nil)
	local alertsRoot = existingGui:FindFirstChild("Alerts") or findDescendantByNames(existingGui, { "Alerts" }, nil)
	local alertsList = alertsRoot and (findDescendantByNames(alertsRoot, { "List" }, nil) or alertsRoot) or nil
	local countdownFrame = framesRoot and (framesRoot:FindFirstChild("Countdown") or framesRoot:FindFirstChild("DuelCountdown") or findDescendantByNames(framesRoot, { "Countdown", "DuelCountdown" }, nil)) or nil
	local countdownLabel = countdownFrame and (findDescendantByNames(countdownFrame, { "Label", "Countdown" }, nil) or countdownFrame:FindFirstChildWhichIsA("TextLabel", true)) or nil
	local runtimeHudRoot = nil

	ui.screenGui = existingGui
	ui.menu = menuFrame
	ui.game = gameFrame
	ui.runtimeHudRoot = runtimeHudRoot
	ui.framesRoot = framesRoot
	ui.foundLineEntries = {}
	ui.hintLineEntries = {}
	ui.modeButtons = {}
	ui.wordRows = {}
	ui.wordRowsToken = 0
	ui.wordRowTemplate = getWordRowTemplate()
	if ui.wordRowTemplate and ui.wordRowTemplate:IsA("GuiObject") then
		ui.wordRowTemplate.BackgroundColor3 = DEFAULT_WORD_ROW_COLOR
		ui.wordRowTemplate.BackgroundTransparency = DEFAULT_WORD_ROW_TRANSPARENCY
	end

	ui.topBarShell = gameTopBar
	ui.gameTopBar = gameTopBar
	ui.gameTopBarContainer = gameTopBarContainer
	ui.streakRoot = streakRoot
	ui.streakLabel = streakRoot and findTextObject(streakRoot, { "Count", "Label", "TextLabel", "Amount", "Value" }) or nil
	if not ui.streakLabel and streakRoot and streakRoot:IsA("GuiObject") then
		ui.streakLabel = create("TextLabel", {
			Name = "Count",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromScale(0.68, 0.34),
			Text = "0",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			ZIndex = (streakRoot.ZIndex or 1) + 1,
			Parent = streakRoot,
		})
	end
	ui.streakScale = streakRoot and ensureScaleController(streakRoot) or nil
	if ui.streakRoot and ui.streakRoot:IsA("GuiObject") then
		ui.streakRoot.Visible = false
	end
	ui.gameTitleLabel = gameTopBarContainer and (
		findDescendantByNames(gameTopBarContainer, { "Title", "TitleLabel", "TextLabel" }, "TextLabel")
			or findDescendantByNames(gameTopBarContainer, { "Title", "TitleLabel" }, "TextButton")
	) or nil
	ui.exitButton = findButtonLike(findDescendantByNames(gameTopBarContainer or gameTopBar, { "exit", "Exit" }, nil))
	if modeBar and modeBar:IsA("GuiObject") then
		modeBar.Visible = false
	end
	if infoBar and infoBar:IsA("GuiObject") then
		infoBar.Visible = false
	end
	if previousButton and previousButton:IsA("GuiObject") then
		previousButton.Visible = false
	end
	ui.modeBar = nil
	ui.infoBar = nil
	ui.contentFrame = contentFrame
	ui.wordPanel = findDescendantByNames(gameFrame or existingGui, { "WordPanel" }, nil)
	ui.wordPanelTitleLabel = findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "WordPanelTitleLabel" }, "TextLabel")
		or findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "WordPanelTitleLabel" }, "TextButton")
	ui.wordPanelCountLabel = findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "WordPanelCountLabel" }, "TextLabel")
		or findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "WordPanelCountLabel" }, "TextButton")
	ui.wordListScroll = findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "WordListScroll", "WordList", "WordsList" }, nil)
	ui.boardColumn = boardColumn
	ui.progressLabel = findTextObject(ui.contentFrame or gameFrame or existingGui, { "ProgressLabel" })
	ui.subtitleLabel = findTextObject(ui.contentFrame or gameFrame or existingGui, { "SubtitleLabel" })
	ui.progressCounterLabel = findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "ProgressCounterLabel" }, "TextLabel")
		or findDescendantByNames(ui.contentFrame or gameFrame or existingGui, { "ProgressCounterLabel" }, "TextButton")
	local statusCard = findDescendantByNames(gameFrame or existingGui, { "StatusCard" }, nil)
	local statusLabel = findDescendantByNames(gameFrame or existingGui, { "StatusLabel" }, nil)
	if statusCard and statusCard:IsA("GuiObject") then
		statusCard.Visible = false
	end
	if statusLabel and statusLabel:IsA("GuiObject") then
		statusLabel.Visible = false
	end
	ui.statusCard = nil
	ui.statusAccent = nil
	ui.statusLabel = nil
	ui.statusScale = nil

	ui.boardHolder = boardHolder
	ui.boardFrame = boardHolder
	ui.boardScaleController = ui.boardHolder and ensureScaleController(ui.boardHolder) or nil
	ui.boardHolderStroke = ui.boardHolder and ui.boardHolder:FindFirstChildWhichIsA("UIStroke", true) or nil
	if ui.boardHolder then
		ui.boardHolder.ClipsDescendants = true
		if ui.boardHolder:IsA("GuiObject") then
			ui.boardHolder.BackgroundTransparency = 1
		end
	end
	if ui.boardHolderStroke then
		ui.boardHolderStroke.Transparency = BOARD_STROKE_HIDDEN_TRANSPARENCY
	end
	ui.boardContent = ui.boardHolder and (ui.boardHolder:FindFirstChild("PuzzleContent") or create("Frame", {
		Name = "PuzzleContent",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = ui.boardHolder,
	})) or nil
	if ui.boardContent then
		ui.boardContent.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.boardContent.Position = UDim2.fromScale(0.5, 0.5)
		ui.boardContent.BackgroundTransparency = 1
		ui.boardContent.BorderSizePixel = 0
		ui.boardContent.ClipsDescendants = true
	end
	ui.praiseBannerRoot = ui.boardHolder and (
		ui.boardHolder:FindFirstChild("PraiseBanner")
			or findDescendantByNames(ui.boardHolder, { "PraiseBanner" }, nil)
	) or nil
	if not ui.praiseBannerRoot and ui.boardHolder then
		ui.praiseBannerRoot = create("Frame", {
			Name = "PraiseBanner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.18),
			Size = UDim2.fromScale(0.62, 0.2067),
			Visible = false,
			ZIndex = 24,
			Parent = ui.boardHolder,
		})
		create("UIAspectRatioConstraint", {
			Name = "AspectRatio",
			AspectRatio = 3,
			Parent = ui.praiseBannerRoot,
		})
		ui.praiseBannerImage = create("ImageLabel", {
			Name = "Image",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = RuntimeHelpers.praiseBannerConfig.imageId,
			ImageTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 24,
			Parent = ui.praiseBannerRoot,
		})
		ui.praiseBannerLabel = create("TextLabel", {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.46),
			Text = "",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			TextTransparency = 1,
			ZIndex = 25,
			Parent = ui.praiseBannerRoot,
		})
		applyTextFont(ui.praiseBannerLabel, Enum.Font.GothamBlack)
	end
	ui.praiseBannerImage = ui.praiseBannerImage
		or (ui.praiseBannerRoot and (ui.praiseBannerRoot:FindFirstChild("Image") or ui.praiseBannerRoot:FindFirstChildWhichIsA("ImageLabel", true))) or nil
	ui.praiseBannerLabel = ui.praiseBannerLabel
		or (ui.praiseBannerRoot and findTextObject(ui.praiseBannerRoot, { "Label", "TextLabel" })) or nil
	ui.praiseBannerScale = ui.praiseBannerRoot and ensureScaleController(ui.praiseBannerRoot) or nil
	ui.praiseBannerOpenPosition = UDim2.fromScale(0.5, 0.18)
	ui.praiseBannerStartPosition = UDim2.fromScale(0.5, 0.145)
	ui.praiseBannerExitPosition = UDim2.fromScale(0.5, 0.13)
	if ui.praiseBannerRoot then
		ui.praiseBannerRoot.Position = ui.praiseBannerStartPosition
		ui.praiseBannerRoot.Visible = false
	end
	ui.boardVisualGroup = ui.boardContent and ui.boardContent:FindFirstChild("BoardVisualGroup") or nil
	if not ui.boardVisualGroup and ui.boardContent then
		local createCanvasGroupSuccess, boardVisualGroup = pcall(function()
			return create("CanvasGroup", {
				Name = "BoardVisualGroup",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				GroupTransparency = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Parent = ui.boardContent,
			})
		end)
		if createCanvasGroupSuccess then
			ui.boardVisualGroup = boardVisualGroup
		end
	end
	if ui.boardVisualGroup then
		ui.boardVisualGroup.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.boardVisualGroup.Position = UDim2.fromScale(0.5, 0.5)
		ui.boardVisualGroup.BackgroundTransparency = 1
		ui.boardVisualGroup.BorderSizePixel = 0
		ui.boardVisualGroup.Size = UDim2.fromScale(1, 1)
		ui.boardVisualGroup.Parent = ui.boardContent
		if ui.boardVisualGroup:IsA("CanvasGroup") then
			ui.boardVisualGroup.GroupTransparency = 0
		end
	end
	ui.puzzleGrid = ui.boardContent and ((ui.boardVisualGroup and ui.boardVisualGroup:FindFirstChild("PuzzleGrid")) or ui.boardContent:FindFirstChild("PuzzleGrid") or create("Frame", {
		Name = "PuzzleGrid",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = ui.boardVisualGroup or ui.boardContent,
	})) or nil
	if ui.puzzleGrid then
		ui.puzzleGrid.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.puzzleGrid.Position = UDim2.fromScale(0.5, 0.5)
		ui.puzzleGrid.BackgroundTransparency = 1
		ui.puzzleGrid.BorderSizePixel = 0
		ui.puzzleGrid.ClipsDescendants = true
		ui.puzzleGrid.Size = UDim2.fromScale(1, 1)
		if ui.puzzleGrid.Parent ~= (ui.boardVisualGroup or ui.boardContent) then
			ui.puzzleGrid.Parent = ui.boardVisualGroup or ui.boardContent
		end

		local puzzleGridAspect = ui.puzzleGrid:FindFirstChild("PuzzleGridAspectRatio")
		if not puzzleGridAspect then
			puzzleGridAspect = create("UIAspectRatioConstraint", {
				Name = "PuzzleGridAspectRatio",
				AspectRatio = 1,
				AspectType = Enum.AspectType.FitWithinMaxSize,
				Parent = ui.puzzleGrid,
			})
		end
	end
	ui.tileLayer = ui.puzzleGrid and (ui.puzzleGrid:FindFirstChild("TileLayer") or create("Frame", {
		Name = "TileLayer",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = ui.puzzleGrid,
	})) or nil
	if ui.tileLayer then
		ui.tileLayer.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.tileLayer.Position = UDim2.fromScale(0.5, 0.5)
		ui.tileLayer.BackgroundTransparency = 1
		ui.tileLayer.BorderSizePixel = 0
		ui.tileLayer.ClipsDescendants = true
		ui.tileLayer.Size = UDim2.fromScale(1, 1)
		if ui.tileLayer.Parent ~= ui.puzzleGrid then
			ui.tileLayer.Parent = ui.puzzleGrid
		end
	end
	syncBoardContentLayout()
	ui.lineLayer = findDescendantByNames(ui.puzzleGrid or ui.boardContent, { "LineLayer" }, nil)
	if not ui.lineLayer then
		ui.lineLayer = create("Frame", {
			Name = "LineLayer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = LAYOUT.LineLayerZIndex,
			Parent = ui.puzzleGrid or ui.boardContent,
		})
	end
	if ui.puzzleGrid and ui.lineLayer.Parent ~= ui.puzzleGrid then
		ui.lineLayer.Parent = ui.puzzleGrid
	end
	if ui.lineLayer then
		ui.lineLayer.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.lineLayer.BackgroundTransparency = 1
		ui.lineLayer.BorderSizePixel = 0
		ui.lineLayer.Position = UDim2.fromScale(0.5, 0.5)
		ui.lineLayer.Size = UDim2.fromScale(1, 1)
		ui.lineLayer.ZIndex = LAYOUT.LineLayerZIndex
	end

	ui.persistentLineLayer = findDescendantByNames(ui.lineLayer, { "PersistentLineLayer" }, nil)
	if not ui.persistentLineLayer then
		ui.persistentLineLayer = create("Frame", {
			Name = "PersistentLineLayer",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = LAYOUT.PersistentLineLayerZIndex,
			Parent = ui.lineLayer,
		})
	end
	if ui.persistentLineLayer then
		if ui.persistentLineLayer.Parent ~= ui.lineLayer then
			ui.persistentLineLayer.Parent = ui.lineLayer
		end
		ui.persistentLineLayer.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.persistentLineLayer.BackgroundTransparency = 1
		ui.persistentLineLayer.BorderSizePixel = 0
		ui.persistentLineLayer.Position = UDim2.fromScale(0.5, 0.5)
		ui.persistentLineLayer.Size = UDim2.fromScale(1, 1)
		ui.persistentLineLayer.ZIndex = LAYOUT.PersistentLineLayerZIndex
		for _, child in ipairs(ui.persistentLineLayer:GetChildren()) do
			if child:IsA("Frame") then
				if string.find(child.Name, "Glow") then
					child.ZIndex = LAYOUT.PersistentLineGlowZIndex
				else
					child.ZIndex = LAYOUT.PersistentLineZIndex
				end
			end
		end
	end

	ui.dragGlow = findDescendantByNames(ui.lineLayer, { "DragGlow" }, "Frame")
	ui.dragLine = findDescendantByNames(ui.lineLayer, { "DragLine" }, "Frame")
	if not ui.dragGlow or not ui.dragLine then
		createDragLineObjects()
	end
	if ui.dragGlow then
		ui.dragGlow.ZIndex = LAYOUT.DragGlowZIndex
	end
	if ui.dragLine then
		ui.dragLine.ZIndex = LAYOUT.DragLineZIndex
	end

	ui.boardCursorRoot = findDescendantByNames(ui.puzzleGrid or ui.boardContent, { "GamepadCursor", "ConsoleCursor" }, "Frame")
	if not ui.boardCursorRoot and ui.puzzleGrid then
		ui.boardCursorRoot = create("Frame", {
			Name = "GamepadCursor",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Selectable = false,
			Size = UDim2.fromOffset(0, 0),
			Visible = false,
			ZIndex = LAYOUT.GamepadCursorZIndex,
			Parent = ui.puzzleGrid,
		})
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = ui.boardCursorRoot,
		})
		ui.boardCursorGlow = create("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 241, 138),
			BackgroundTransparency = 0.94,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Selectable = false,
			Size = UDim2.fromScale(1.2, 1.2),
			ZIndex = LAYOUT.GamepadCursorGlowZIndex,
			Parent = ui.boardCursorRoot,
		})
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = ui.boardCursorGlow,
		})
		ui.boardCursorStroke = create("UIStroke", {
			Name = "Stroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(255, 241, 138),
			Thickness = 3,
			Transparency = 0.12,
			Parent = ui.boardCursorRoot,
		})
	end
	ui.boardCursorGlow = ui.boardCursorGlow
		or (ui.boardCursorRoot and findDescendantByNames(ui.boardCursorRoot, { "Glow" }, "Frame"))
		or nil
	ui.boardCursorStroke = ui.boardCursorStroke
		or (ui.boardCursorRoot and (ui.boardCursorRoot:FindFirstChild("Stroke") or ui.boardCursorRoot:FindFirstChildWhichIsA("UIStroke")))
		or nil
	ui.boardCursorScale = ui.boardCursorRoot and ensureScaleController(ui.boardCursorRoot) or nil
	if ui.boardCursorRoot then
		ui.boardCursorRoot.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.boardCursorRoot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		ui.boardCursorRoot.BackgroundTransparency = 0.9
		ui.boardCursorRoot.BorderSizePixel = 0
		ui.boardCursorRoot.Position = UDim2.fromScale(0.5, 0.5)
		ui.boardCursorRoot.Size = UDim2.fromOffset(0, 0)
		ui.boardCursorRoot.Visible = false
		ui.boardCursorRoot.ZIndex = LAYOUT.GamepadCursorZIndex
		if ui.boardCursorRoot.Parent ~= ui.puzzleGrid then
			ui.boardCursorRoot.Parent = ui.puzzleGrid
		end
	end
	if ui.boardCursorGlow then
		ui.boardCursorGlow.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.boardCursorGlow.BackgroundColor3 = Color3.fromRGB(255, 241, 138)
		ui.boardCursorGlow.BackgroundTransparency = 0.94
		ui.boardCursorGlow.BorderSizePixel = 0
		ui.boardCursorGlow.Position = UDim2.fromScale(0.5, 0.5)
		ui.boardCursorGlow.Size = UDim2.fromScale(1.2, 1.2)
		ui.boardCursorGlow.ZIndex = LAYOUT.GamepadCursorGlowZIndex
	end
	if ui.boardCursorStroke then
		ui.boardCursorStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ui.boardCursorStroke.Color = Color3.fromRGB(255, 241, 138)
		ui.boardCursorStroke.Thickness = 3
		ui.boardCursorStroke.Transparency = 0.12
	end

	if ui.boardHolder and not ui.boardHolder:GetAttribute("WordSearchBoardResizeBound") then
		ui.boardHolder:SetAttribute("WordSearchBoardResizeBound", true)
		ui.boardHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			syncBoardContentLayout()
			if state.currentPuzzle then
				refreshPersistentLines()
				RuntimeHelpers.refreshBoard()
				if state.dragging and state.dragCursorPosition then
					RuntimeHelpers.updateDragTarget(state.dragCursorPosition)
				end
			end
		end)
	end

	ui.bottomBarShell = findDescendantByNames(gameFrame or existingGui, { "BottomBarShell" }, nil)
	ui.buttonBar = findDescendantByNames(gameFrame or existingGui, { "ButtonBar" }, nil)
	ui.hintRoot = hintRoot
	ui.hintButton = hintButton
	ui.hintLabel = nil
	if hintButton and (hintButton:IsA("TextButton") or hintButton:IsA("TextLabel")) then
		ui.hintLabel = hintButton
	elseif hintRoot then
		for _, descendant in ipairs(hintRoot:GetDescendants()) do
			if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
				and descendant.Name ~= "Amount"
				and descendant:FindFirstAncestor("Notification") == nil then
				ui.hintLabel = descendant
				break
			end
		end
	end
	ui.hintLabelBaseTransparency = ui.hintLabel
		and (ui.hintLabel:IsA("TextButton") or ui.hintLabel:IsA("TextLabel"))
		and ui.hintLabel.TextTransparency
		or 0
	ui.hintLocked = (hintRoot and findDescendantByNames(hintRoot, { "Locked" }, nil))
		or (hintButton and findDescendantByNames(hintButton, { "Locked" }, nil))
	if ui.hintLocked and ui.hintLocked:IsA("GuiObject") then
		ui.hintLocked.Visible = false
	end
	ui.nextButton = nextButton
	ui.duelModeRoot = duelModeRoot
	local duelModeTitleRoot = duelModeRoot and (
		duelModeRoot:FindFirstChild("Title")
			or findDescendantByNames(duelModeRoot, { "Title" }, nil)
	) or nil
	local duelModeOpponentRoot = duelModeRoot and (
		duelModeRoot:FindFirstChild("Opponent")
			or findDescendantByNames(duelModeRoot, { "Opponent" }, nil)
	) or nil
	ui.duelModeTitleLabel = duelModeTitleRoot and findTextObject(duelModeTitleRoot, { "Title", "Label", "TextLabel" }) or nil
	ui.duelModeOpponentLabel = duelModeOpponentRoot and findTextObject(duelModeOpponentRoot, { "Opponent", "Label", "TextLabel" }) or nil
	ui.duelModeProgressBar = duelModeRoot and (duelModeRoot:FindFirstChild("Bar") or duelModeRoot:FindFirstChild("ProgressBar") or findDescendantByNames(duelModeRoot, { "Bar", "ProgressBar" }, nil)) or nil
	ui.duelModeProgressBarFrame = ui.duelModeProgressBar and (
		ui.duelModeProgressBar:FindFirstChild("Frame")
			or findDescendantByNames(ui.duelModeProgressBar, { "Frame" }, nil)
	) or nil
	local duelModeFillRoot = ui.duelModeProgressBarFrame or ui.duelModeProgressBar
	ui.duelModeMyFill = duelModeFillRoot and (duelModeFillRoot:FindFirstChild("MyFill") or findDescendantByNames(duelModeFillRoot, { "MyFill" }, nil)) or nil
	ui.duelModeOppFill = duelModeFillRoot and (duelModeFillRoot:FindFirstChild("OppFill") or findDescendantByNames(duelModeFillRoot, { "OppFill" }, nil)) or nil
	ui.duelModeMyLabel = duelModeFillRoot and (
		duelModeFillRoot:FindFirstChild("MyLabel")
			or duelModeFillRoot:FindFirstChild("MyPercent")
			or findDescendantByNames(duelModeFillRoot, { "MyLabel", "MyPercent" }, "TextLabel")
			or findDescendantByNames(duelModeFillRoot, { "MyLabel", "MyPercent" }, "TextButton")
	) or nil
	ui.duelModeOppLabel = duelModeFillRoot and (
		duelModeFillRoot:FindFirstChild("OppLabel")
			or duelModeFillRoot:FindFirstChild("OppPercent")
			or findDescendantByNames(duelModeFillRoot, { "OppLabel", "OppPercent" }, "TextLabel")
			or findDescendantByNames(duelModeFillRoot, { "OppLabel", "OppPercent" }, "TextButton")
	) or nil
	if ui.duelModeRoot and ui.duelModeRoot:IsA("GuiObject") then
		ui.duelModeRoot.Visible = false
	end
	if ui.duelModeMyLabel then
		ui.duelModeMyLabel.Text = "0%"
	end
	if ui.duelModeOppLabel then
		ui.duelModeOppLabel.Text = "0%"
	end
	if ui.duelModeMyFill and ui.duelModeMyFill:IsA("GuiObject") then
		ui.duelModeMyFill.Size = UDim2.new(DUEL_MODE_MIN_FILL_SCALE, 0, 1, 0)
	end
	if ui.duelModeOppFill and ui.duelModeOppFill:IsA("GuiObject") then
		ui.duelModeOppFill.Size = UDim2.new(DUEL_MODE_MIN_FILL_SCALE, 0, 1, 0)
	end
	ui.alertsRoot = alertsRoot
	ui.alertsList = alertsList
	ui.countdownFrame = countdownFrame
	ui.countdownLabel = countdownLabel
	ui.countdownCard = nil
	ui.countdownCardScale = nil
	ui.countdownCardStroke = nil
	ui.countdownLabelScale = nil
	if ui.alertsRoot and ui.alertsRoot:IsA("GuiObject") then
		ui.alertsRoot.Visible = true
	end
	local rewardToastRoot = (findFirstPath and findFirstPath(gameFrame or existingGui, {
		{ "RewardToast" },
		{ "TopBar", "RewardToast" },
		{ "ContentFrame", "RewardToast" },
	}, nil))
		or findDescendantByNames(gameFrame or menuFrame or existingGui, { "RewardToast" }, nil)
	ui.rewardToastRoot = rewardToastRoot
	ui.rewardToast = rewardToastRoot and (
		(rewardToastRoot:IsA("TextLabel") or rewardToastRoot:IsA("TextButton")) and rewardToastRoot
			or (findFirstPath and findFirstPath(rewardToastRoot, {
				{ "Label" },
				{ "TextLabel" },
				{ "Text" },
			}, nil))
			or findDescendantByNames(rewardToastRoot, { "Label", "TextLabel", "Text" }, nil)
	) or nil
	if not ui.rewardToast and rewardToastRoot then
		ui.rewardToast = findTextObject(rewardToastRoot, { "Label", "TextLabel", "Text" })
	end
	if ui.rewardToast and not (ui.rewardToast:IsA("TextLabel") or ui.rewardToast:IsA("TextButton")) then
		ui.rewardToast = findTextObject(ui.rewardToast, { "Label", "TextLabel", "Text" })
	end
	local rewardToastScaleTarget = (ui.rewardToastRoot and ui.rewardToastRoot:IsA("GuiObject") and ui.rewardToastRoot) or ui.rewardToast
	ui.rewardToastScale = rewardToastScaleTarget and ensureScaleController(rewardToastScaleTarget) or nil
	if ui.rewardToastRoot and ui.rewardToastRoot:IsA("GuiObject") then
		ui.rewardToastRoot.Visible = false
	elseif ui.rewardToast and ui.rewardToast:IsA("GuiObject") then
		ui.rewardToast.Visible = false
	end
	if not ui.countdownFrame then
		ui.countdownFrame = create("Frame", {
			Name = "RuntimeCountdown",
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 90,
			Parent = framesRoot or existingGui,
		})
	else
		ui.countdownFrame.Visible = false
	end
	if ui.countdownFrame then
		ui.countdownCard = ui.countdownFrame:FindFirstChild("Card") or create("Frame", {
			Name = "Card",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(12, 18, 28),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.34, 0.26),
			ZIndex = 90,
			Parent = ui.countdownFrame,
		})
		if not ui.countdownCard:FindFirstChild("Corner") then
			create("UICorner", {
				Name = "Corner",
				CornerRadius = UDim.new(0.12, 0),
				Parent = ui.countdownCard,
			})
		end
		ui.countdownCardStroke = ui.countdownCard:FindFirstChild("Stroke")
		if not ui.countdownCardStroke then
			ui.countdownCardStroke = create("UIStroke", {
				Name = "Stroke",
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(240, 246, 255),
				Thickness = 1.5,
				Transparency = 1,
				Parent = ui.countdownCard,
			})
		end
		ui.countdownCardScale = ensureScaleController(ui.countdownCard)
	end
	if not ui.countdownLabel then
		ui.countdownLabel = create("TextLabel", {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.464, 0, 0.26, 0),
			Text = "",
			TextColor3 = COLORS.text,
			TextScaled = true,
			ZIndex = 91,
			Parent = ui.countdownFrame,
		})
	end
	if ui.countdownLabel then
		ui.countdownLabel.TextTransparency = 1
		ui.countdownLabel.TextStrokeColor3 = Color3.fromRGB(5, 8, 14)
		ui.countdownLabel.TextStrokeTransparency = 1
		ui.countdownLabelScale = ensureScaleController(ui.countdownLabel)
	end
	local summaryRoot = (findFirstPath and findFirstPath(framesRoot or existingGui, {
		{ "GameOutcome" },
		{ "SummaryOverlay" },
	}, nil))
		or findDescendantByNames(framesRoot or existingGui, { "GameOutcome", "SummaryOverlay" }, nil)
	ui.summaryOverlay = summaryRoot
	ui.summaryCard = (summaryRoot and (
		(findFirstPath and findFirstPath(summaryRoot, {
			{ "Frame" },
			{ "Card" },
			{ "Container" },
		}, nil))
			or findDescendantByNames(summaryRoot, { "Frame", "Card", "Container" }, nil)
	))
		or findDescendantByNames(framesRoot or existingGui, { "SummaryCard" }, nil)
		or summaryRoot
	ui.summaryCardScale = ui.summaryCard and ui.summaryCard:FindFirstChildWhichIsA("UIScale") or nil
	ui.summaryCardOpenSize = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
		and UDim2.fromScale(0.69, 0.69)
		or UDim2.fromScale(0.6, 0.6)
	ui.summaryCardOpenPosition = UDim2.fromScale(0.5, 0.5)
	ui.summaryOverlayOpenTransparency = resolveOverlayOpenTransparency(
		(ui.summaryOverlay ~= ui.summaryCard and ui.summaryOverlay and ui.summaryOverlay.BackgroundTransparency) or nil
	)
	ui.summaryCardOpenTransparency = resolveCardOpenTransparency(
		ui.summaryCard and ui.summaryCard.BackgroundTransparency or nil,
		0.08
	)
	ui.summaryTitleLabel = (summaryRoot and findTextObject(
		(findFirstPath and findFirstPath(summaryRoot, {
			{ "Frame", "Title" },
			{ "Title" },
			{ "Frame", "Outcome" },
			{ "Outcome" },
			{ "Frame", "Header", "Title" },
			{ "Header", "Title" },
		}, nil))
			or findDescendantByNames(summaryRoot, { "Title", "SummaryTitleLabel", "Outcome" }, nil)
			or ui.summaryCard
			or summaryRoot,
		{ "Title", "SummaryTitleLabel", "Outcome", "Label", "TextLabel" }
	))
		or (ui.summaryCard and findTextObject(ui.summaryCard, { "Title", "SummaryTitleLabel", "Outcome" }))
		or findTextObject(framesRoot or existingGui, { "SummaryTitleLabel" })
	ui.summaryBodyLabel = (summaryRoot and findTextObject(
		(findFirstPath and findFirstPath(summaryRoot, {
			{ "Frame", "Body" },
			{ "Frame", "Description" },
			{ "Frame", "Sub" },
			{ "Body" },
			{ "Description" },
			{ "Sub" },
			{ "Frame", "Container", "Body" },
			{ "Frame", "Container", "Description" },
		}, nil))
			or findDescendantByNames(summaryRoot, { "Body", "SummaryBodyLabel", "Description", "Desc", "Sub" }, nil)
			or summaryRoot,
		{ "Body", "SummaryBodyLabel", "Description", "Desc", "Sub", "Status", "Label", "TextLabel" }
	))
		or findTextObject(framesRoot or existingGui, { "SummaryBodyLabel" })
	if not ui.summaryBodyLabel and ui.summaryCard and ui.summaryCard:IsA("GuiObject") then
		ui.summaryBodyLabel = create("TextLabel", {
			Name = "SummaryBodyRuntime",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromScale(0.5, 0.2),
			Size = UDim2.fromScale(0.78, 0.16),
			Text = "",
			TextColor3 = COLORS.textMuted,
			TextScaled = true,
			TextTransparency = 1,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = (ui.summaryCard.ZIndex or 1) + 1,
			Parent = ui.summaryCard,
		})
	end
	local summaryButtonSearchRoot = ui.summaryCard or summaryRoot
	local summaryButtonRoot = (summaryButtonSearchRoot and (
		(findFirstPath and findFirstPath(summaryButtonSearchRoot, {
			{ "Frame", "Buttons", "Green" },
			{ "Frame", "Green" },
			{ "Buttons", "Green" },
			{ "Green" },
			{ "Frame", "Buttons", "Green", "Button" },
			{ "Frame", "Green", "Button" },
			{ "Buttons", "Green", "Button" },
			{ "Green", "Button" },
			{ "Frame", "Continue", "Button" },
			{ "Continue", "Button" },
			{ "Frame", "Continue" },
			{ "Continue" },
			{ "SummaryButton" },
		}, nil))
			or findDescendantByNames(summaryButtonSearchRoot, { "SummaryButton", "Continue", "Home", "Next", "Green" }, nil)
	)) or findDescendantByNames(framesRoot or existingGui, { "SummaryButton" }, nil)
	ui.summaryButton = findButtonLike(summaryButtonRoot)
	ui.summaryButtonLabel = summaryButtonRoot and (
		(findFirstPath and findFirstPath(summaryButtonRoot, {
			{ "Button", "Label" },
			{ "Button", "TextLabel" },
			{ "Label" },
			{ "TextLabel" },
		}, nil))
			or ((ui.summaryButton and ui.summaryButton.Parent and ui.summaryButton.Parent ~= summaryButtonRoot) and (
				(findFirstPath and findFirstPath(ui.summaryButton.Parent, {
					{ "Label" },
					{ "TextLabel" },
				}, nil))
					or findDescendantByNames(ui.summaryButton.Parent, { "Label", "TextLabel" }, nil)
			))
			or ((ui.summaryButton and ui.summaryButton ~= summaryButtonRoot) and (
				(findFirstPath and findFirstPath(ui.summaryButton, {
					{ "Label" },
					{ "TextLabel" },
				}, nil))
					or findDescendantByNames(ui.summaryButton, { "Label", "TextLabel" }, nil)
			))
	) or nil
	if ui.summaryButtonLabel and not (ui.summaryButtonLabel:IsA("TextLabel") or ui.summaryButtonLabel:IsA("TextButton")) then
		ui.summaryButtonLabel = findTextObject(ui.summaryButtonLabel, { "Label", "TextLabel" })
	end
	ui.summaryButtonBaseTransparency = ui.summaryButton and ui.summaryButton.BackgroundTransparency or 0
	ui.summaryStarsRoot = ui.summaryCard and findDescendantByNames(ui.summaryCard, { "Stars" }, nil) or nil
	local summaryStarsTitleRoot = ui.summaryStarsRoot and findDescendantByNames(ui.summaryStarsRoot, { "Title" }, nil) or nil
	ui.summaryStarsTitleLabel = summaryStarsTitleRoot and (
		(summaryStarsTitleRoot:IsA("TextLabel") or summaryStarsTitleRoot:IsA("TextButton")) and summaryStarsTitleRoot
			or findTextObject(summaryStarsTitleRoot, { "Title", "Label", "TextLabel" })
	) or nil
	ui.summaryStarOne = ui.summaryStarsRoot and findDescendantByNames(ui.summaryStarsRoot, { "StarOne" }, nil) or nil
	ui.summaryStarTwo = ui.summaryStarsRoot and findDescendantByNames(ui.summaryStarsRoot, { "StarTwo" }, nil) or nil
	ui.summaryStarThree = ui.summaryStarsRoot and findDescendantByNames(ui.summaryStarsRoot, { "StarThree" }, nil) or nil
	ui.summaryStarOneScale = ui.summaryStarOne and ensureScaleController(ui.summaryStarOne) or nil
	ui.summaryStarTwoScale = ui.summaryStarTwo and ensureScaleController(ui.summaryStarTwo) or nil
	ui.summaryStarThreeScale = ui.summaryStarThree and ensureScaleController(ui.summaryStarThree) or nil
	if ui.summaryStarsTitleLabel and ui.summaryStarsTitleLabel:IsA("GuiObject") then
		ui.summaryStarsTitleLabel.Visible = false
	end
	do
		local summaryCurrencyNode = ui.summaryCard and findDescendantByNames(ui.summaryCard, { "CurrencyEarnt", "CurrencyEarned" }, nil) or nil
		ui.summaryCurrencyEarnedLabel = summaryCurrencyNode
			and (summaryCurrencyNode:IsA("TextLabel") or summaryCurrencyNode:IsA("TextButton"))
			and summaryCurrencyNode
			or nil
	end
	ui.summaryGiftRoot = ui.summaryCard and findDescendantByNames(ui.summaryCard, { "Gift" }, nil) or nil
	ui.summaryGiftFill = ui.summaryGiftRoot and findDescendantByNames(ui.summaryGiftRoot, { "Fill" }, nil) or nil
	ui.summaryGiftText = ui.summaryGiftRoot and findTextObject(ui.summaryGiftRoot, { "TextLabel", "Label" }) or nil
	ui.summaryGiftIcon = ui.summaryGiftRoot and (
		findDescendantByNames(ui.summaryGiftRoot, { "ImageLabel" }, nil)
			or ui.summaryGiftRoot:FindFirstChildWhichIsA("ImageLabel", true)
	) or nil
	ui.summaryGiftButton = ui.summaryGiftRoot and findButtonLike(ui.summaryGiftRoot) or nil
	if not ui.summaryGiftButton and ui.summaryGiftRoot and ui.summaryGiftRoot:IsA("GuiObject") then
		ui.summaryGiftButton = ui.summaryGiftRoot:FindFirstChild("ClaimButton")
		if not ui.summaryGiftButton then
			ui.summaryGiftButton = create("TextButton", {
				Name = "ClaimButton",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 1),
				Text = "",
				ZIndex = (ui.summaryGiftRoot.ZIndex or 1) + 1,
				Parent = ui.summaryGiftRoot,
			})
		end
	end
	if ui.summaryOverlay and ui.summaryOverlay:IsA("GuiObject") then
		ui.summaryOverlay.Visible = false
	end
	if ui.summaryCard and ui.summaryCard ~= ui.summaryOverlay and ui.summaryCard:IsA("GuiObject") then
		ui.summaryCard.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.summaryCard.Position = ui.summaryCardOpenPosition
		ui.summaryCard.Size = UDim2.fromScale(0, 0)
		ui.summaryCard.Visible = false
	end

	RuntimeHelpers.bindClassicLevelsUi(existingGui, framesRoot)

	ui.modeChip = nil
	ui.secondaryChip = nil
	ui.scoreChip = nil
	ui.rewardChip = nil
	ui.modeChipLabel = nil
	ui.secondaryChipLabel = nil
	ui.scoreChipLabel = nil
	ui.rewardChipLabel = nil
	ui.modeChipScale = nil
	ui.secondaryChipScale = nil
	ui.scoreChipScale = nil
	ui.rewardChipScale = nil

	ui.menuActionRow = menuActionRow
	ui.menuPlayRoot = menuPlayRoot
	ui.menuPlayButton = findButtonLike(menuPlayRoot)
	ui.menuPlayLocked = menuPlayRoot and findDescendantByNames(menuPlayRoot, { "Locked" }, nil) or nil
	if ui.menuPlayLocked and ui.menuPlayLocked:IsA("GuiObject") then
		ui.menuPlayLocked.Visible = false
	end
	ui.menuDuelRoot = menuDuelRoot
	ui.menuDuelButton = findButtonLike(menuDuelRoot)
	ui.menuModeCarousel = menuModeCarousel
	ui.menuModeNextButton = findButtonLike(findDescendantByNames(menuModeCarousel, { "NextModeBtn", "Next" }, nil))
	ui.menuModePrevButton = findButtonLike(findDescendantByNames(menuModeCarousel, { "PrevModeBtn", "Previous" }, nil))
	ui.menuModePreviewImage = findDescendantByNames(menuModeCarousel, { "ModePreviewImage" }, nil)
	ui.menuModeNameLabel = menuModeCarousel and findTextObject(menuModeCarousel, { "ModeNameLabel", "TextLabel", "Title" }) or nil
	ui.menuModeSubLabel = menuModeCarousel and findTextObject(menuModeCarousel, { "SubLabel", "Subtitle", "Description" }) or nil
	ui.menuModeLocked = menuModeCarousel and findDescendantByNames(menuModeCarousel, { "Locked" }, nil) or nil
	if ui.menuModeLocked and ui.menuModeLocked:IsA("GuiObject") then
		ui.menuModeLocked.Visible = false
	end

	ButtonUi.prepare(ui.menuPlayButton)
	ButtonUi.prepare(ui.menuDuelButton)
	bindButtonHoverSound(ui.menuModeNextButton)
	bindButtonHoverSound(ui.menuModePrevButton)
	if ui.hintRoot and ui.hintRoot:IsA("GuiButton") and ui.hintRoot ~= ui.hintButton then
		ButtonUi.prepare(ui.hintRoot)
	end
	ButtonUi.prepare(ui.hintButton)
	ButtonUi.prepare(ui.nextButton, COLORS.buttonPrimary)
	ButtonUi.prepare(ui.exitButton, nil, 0)
	ButtonUi.prepare(ui.summaryButton, COLORS.buttonPrimary)

	if ui.wordListScroll then
		local runtimeWordListLayout = ui.wordListScroll:FindFirstChild("WordListLayout")
		if runtimeWordListLayout then
			runtimeWordListLayout:Destroy()
		end
		local runtimeWordListGrid = ui.wordListScroll:FindFirstChildOfClass("UIGridLayout")
		if runtimeWordListGrid then
			runtimeWordListGrid:Destroy()
		end
		local runtimeWordListList = ui.wordListScroll:FindFirstChildOfClass("UIListLayout")
		if runtimeWordListList then
			runtimeWordListList:Destroy()
		end
		if not ui.wordListScroll:GetAttribute("WordSearchResizeBound") then
			ui.wordListScroll:SetAttribute("WordSearchResizeBound", true)
			ui.wordListScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if state.currentPuzzle and updateWordsLabel then
					updateWordsLabel()
				end
			end)
		end
	end

	return true
end

return {
	bindExistingUI = RuntimeHelpers.bindExistingUI,
}
end


InterfaceController.Interface = Interface
InterfaceController.Components = Components
return InterfaceController
