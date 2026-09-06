local TimedRewardsUI = {}

local PULSE_COLOR = Color3.fromRGB(255, 255, 255)
local PUZZLE_PIECE_TEXT = utf8.char(0x1F9E9)

local function isTextNode(node)
	return node and (node:IsA("TextLabel") or node:IsA("TextButton"))
end

local function isImageNode(node)
	return node and (node:IsA("ImageLabel") or node:IsA("ImageButton"))
end

local function resolveBool(value)
	if type(value) == "function" then
		local success, result = pcall(value)
		return success and result == true
	end

	return value == true
end

local function getTimedRewardIcon(ctx, reward)
	if not reward then
		return ""
	end
	if reward.rewardType == "hints" then
		return tostring(ctx.hintIconId or "")
	end
	return ""
end

local function getProjectedPlaytimeSeconds(ctx, nextRewardIndex, playtimeSeconds, threshold)
	local runtimeState = ctx.runtimeState
	if type(runtimeState) ~= "table" then
		runtimeState = {}
		ctx.runtimeState = runtimeState
	end

	local now = os.clock()
	local rewardKey = tostring(nextRewardIndex or "none")
	local clampedPlaytime = math.clamp(math.floor(tonumber(playtimeSeconds) or 0), 0, math.max(0, threshold))
	local baselinePlaytime = math.floor(tonumber(runtimeState.baselinePlaytimeSeconds) or -1)
	local baselineObservedAt = tonumber(runtimeState.baselineObservedAt) or now

	if runtimeState.rewardKey ~= rewardKey or clampedPlaytime ~= baselinePlaytime then
		runtimeState.rewardKey = rewardKey
		runtimeState.baselinePlaytimeSeconds = clampedPlaytime
		runtimeState.baselineObservedAt = now
		baselinePlaytime = clampedPlaytime
		baselineObservedAt = now
	end

	local elapsedSeconds = math.max(0, math.floor(now - baselineObservedAt))
	return math.min(math.max(0, threshold), baselinePlaytime + elapsedSeconds)
end

local function setTimedRewardCard(
	ctx,
	timerNode,
	rewardNode,
	primaryNode,
	secondaryNode,
	primaryLabelNode,
	secondaryLabelNode,
	descriptionNode,
	visible,
	state
)
	local reward = state and state.reward or nil
	local description = reward and ctx.timedRewardsConfig.GetRewardDescription(reward) or ""
	local icon = getTimedRewardIcon(ctx, reward)
	local isPiecesReward = reward and reward.rewardType == "pieces"

	if rewardNode and rewardNode:IsA("GuiObject") then
		rewardNode.Visible = visible == true
	end
	if isTextNode(timerNode) then
		timerNode.Visible = visible == true
	end
	if isTextNode(descriptionNode) then
		descriptionNode.Visible = visible == true
		ctx.setText(descriptionNode, description)
	end

	for _, node in ipairs({ primaryNode, secondaryNode }) do
		if isImageNode(node) then
			node.Visible = visible == true and not isPiecesReward and icon ~= ""
			node.Image = icon
		end
	end

	for _, node in ipairs({ primaryLabelNode, secondaryLabelNode }) do
		if isTextNode(node) then
			node.Visible = visible == true and isPiecesReward
			ctx.setText(node, isPiecesReward and PUZZLE_PIECE_TEXT or "")
		end
	end

	if not isTextNode(timerNode) then
		return
	end

	if not visible or not state then
		ctx.setText(timerNode, "00:00")
		return
	end

	if state.canClaim then
		ctx.setText(timerNode, "CLAIM")
		return
	end

	local total = math.max(0, math.floor(tonumber(state.remainingSeconds) or 0))
	ctx.setText(timerNode, string.format("%02d:%02d", math.floor(total / 60), total % 60))
end

local function ensurePulseStroke(ctx)
	local elements = ctx.elements
	local rewardNode = elements and elements.timedRewardsReward
	if not rewardNode then
		return nil
	end

	local stroke = rewardNode:FindFirstChild("TimedRewardsPulseStroke")
	if stroke and stroke:IsA("UIStroke") then
		return stroke
	end

	stroke = Instance.new("UIStroke")
	stroke.Name = "TimedRewardsPulseStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Enabled = false
	stroke.Color = PULSE_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = rewardNode
	return stroke
end

local function ensurePulseScale(ctx)
	local elements = ctx.elements
	local rewardNode = elements and elements.timedRewardsReward
	if not rewardNode then
		return nil
	end

	local scale = rewardNode:FindFirstChild("PulseScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end

	scale = Instance.new("UIScale")
	scale.Name = "PulseScale"
	scale.Scale = 1
	scale.Parent = rewardNode
	return scale
end

local function stopPulse(ctx)
	local pulse = ctx.pulseState
	if pulse.connection then
		pulse.connection:Disconnect()
		pulse.connection = nil
	end

	local stroke = pulse.stroke or ensurePulseStroke(ctx)
	if stroke then
		stroke.Enabled = false
		stroke.Color = PULSE_COLOR
		stroke.Transparency = 1
		stroke.Thickness = 1
	end

	local scale = pulse.scale or ensurePulseScale(ctx)
	if scale then
		scale.Scale = 1
	end
end

function TimedRewardsUI.GetFolder(ctx)
	local player = ctx.player
	local data = player and player:FindFirstChild("Data")
	return data and data:FindFirstChild("TimedRewards") or nil
end

function TimedRewardsUI.HasRemaining(ctx)
	local timedRewards = TimedRewardsUI.GetFolder(ctx)
	if not timedRewards then
		return true
	end

	for index = 1, ctx.timedRewardsConfig.GetRewardCount() do
		local rewardFlag = timedRewards:FindFirstChild(ctx.timedRewardsConfig.GetRewardValueName(index))
		if not (rewardFlag and rewardFlag.Value) then
			return true
		end
	end

	return false
end

function TimedRewardsUI.GetState(ctx)
	local timedRewards = TimedRewardsUI.GetFolder(ctx)
	if not timedRewards then
		return nil
	end

	local playtime = timedRewards:FindFirstChild("Playtime")
	local playtimeSeconds = math.max(0, math.floor(tonumber(playtime and playtime.Value) or 0))
	for index = 1, ctx.timedRewardsConfig.GetRewardCount() do
		local rewardFlag = timedRewards:FindFirstChild(ctx.timedRewardsConfig.GetRewardValueName(index))
		if not (rewardFlag and rewardFlag.Value) then
			local reward = ctx.timedRewardsConfig.GetReward(index)
			local threshold = math.max(0, math.floor(tonumber(reward and reward.playtimeSeconds) or 0))
			playtimeSeconds = math.min(playtimeSeconds, threshold)
			local displayPlaytimeSeconds = getProjectedPlaytimeSeconds(ctx, index, playtimeSeconds, threshold)
			local remainingSeconds = math.max(0, threshold - displayPlaytimeSeconds)
			return {
				allClaimed = false,
				canClaim = remainingSeconds <= 0,
				nextRewardIndex = index,
				reward = reward,
				remainingSeconds = remainingSeconds,
				displayPlaytimeSeconds = displayPlaytimeSeconds,
			}
		end
	end

	if type(ctx.runtimeState) == "table" then
		ctx.runtimeState.rewardKey = "all_claimed"
		ctx.runtimeState.baselinePlaytimeSeconds = nil
		ctx.runtimeState.baselineObservedAt = nil
	end

	return {
		allClaimed = true,
		canClaim = false,
		nextRewardIndex = nil,
		reward = nil,
		remainingSeconds = 0,
	}
end

function TimedRewardsUI.ApplyState(ctx, state)
	local elements = ctx.elements
	local show = ctx.show
	local canShowTimedRewards = resolveBool(ctx.canShowTimedRewards)
	local isMobile = resolveBool(ctx.isMobile)
	local hasRemainingRewards = state == nil or state.allClaimed ~= true
	local desktopCardVisible = canShowTimedRewards and hasRemainingRewards and not isMobile
	local mobileButtonVisible = hasRemainingRewards and isMobile
	local rootVisible = desktopCardVisible or mobileButtonVisible
	local mobileCanClaim = mobileButtonVisible and state and state.canClaim == true

	show(elements.timedRewards, rootVisible)
	show(elements.timedRewardsButton, mobileButtonVisible)
	show(elements.timedRewardsButtonAlert, mobileCanClaim)

	if not state then
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsTimer,
			elements and elements.timedRewardsReward,
			elements and elements.timedRewardsRewardPrimary,
			elements and elements.timedRewardsRewardSecondary,
			elements and elements.timedRewardsRewardPrimaryLabel,
			elements and elements.timedRewardsRewardSecondaryLabel,
			elements and elements.timedRewardsRewardDescription,
			desktopCardVisible,
			nil
		)
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsFrameTimer,
			elements and elements.timedRewardsFrameReward,
			elements and elements.timedRewardsFrameRewardPrimary,
			elements and elements.timedRewardsFrameRewardSecondary,
			elements and elements.timedRewardsFrameRewardPrimaryLabel,
			elements and elements.timedRewardsFrameRewardSecondaryLabel,
			elements and elements.timedRewardsFrameRewardDescription,
			true,
			nil
		)
		stopPulse(ctx)
		return
	end

	if state.allClaimed then
		show(elements.timedRewards, false)
		show(elements.timedRewardsButton, false)
		show(elements.timedRewardsButtonAlert, false)
		show(elements.timedRewardsFrame, false)
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsTimer,
			elements and elements.timedRewardsReward,
			elements and elements.timedRewardsRewardPrimary,
			elements and elements.timedRewardsRewardSecondary,
			elements and elements.timedRewardsRewardPrimaryLabel,
			elements and elements.timedRewardsRewardSecondaryLabel,
			elements and elements.timedRewardsRewardDescription,
			false,
			nil
		)
		stopPulse(ctx)
		return
	end

	setTimedRewardCard(
		ctx,
		elements and elements.timedRewardsTimer,
		elements and elements.timedRewardsReward,
		elements and elements.timedRewardsRewardPrimary,
		elements and elements.timedRewardsRewardSecondary,
		elements and elements.timedRewardsRewardPrimaryLabel,
		elements and elements.timedRewardsRewardSecondaryLabel,
		elements and elements.timedRewardsRewardDescription,
		desktopCardVisible,
		state
	)
	setTimedRewardCard(
		ctx,
		elements and elements.timedRewardsFrameTimer,
		elements and elements.timedRewardsFrameReward,
		elements and elements.timedRewardsFrameRewardPrimary,
		elements and elements.timedRewardsFrameRewardSecondary,
		elements and elements.timedRewardsFrameRewardPrimaryLabel,
		elements and elements.timedRewardsFrameRewardSecondaryLabel,
		elements and elements.timedRewardsFrameRewardDescription,
		true,
		state
	)

	stopPulse(ctx)
end

function TimedRewardsUI.Setup(ctx)
	local player = ctx.player
	local timedRewardsConfig = ctx.timedRewardsConfig
	local dataConnections = ctx.dataConnections

	ctx.disconnectAll(dataConnections)

	local function bindTimedRewardsFolder(timedRewardsFolder)
		if not timedRewardsFolder then
			return
		end

		local playtime = timedRewardsFolder:FindFirstChild("Playtime")
		if playtime then
			table.insert(dataConnections, playtime:GetPropertyChangedSignal("Value"):Connect(function()
				ctx.onUpdate()
			end))
		end

		for index = 1, timedRewardsConfig.GetRewardCount() do
			local rewardFlag = timedRewardsFolder:FindFirstChild(timedRewardsConfig.GetRewardValueName(index))
			if rewardFlag then
				table.insert(dataConnections, rewardFlag:GetPropertyChangedSignal("Value"):Connect(function()
					ctx.onUpdate()
				end))
			end
		end

		ctx.onUpdate()
	end

	local function bindData(data)
		local timedRewardsFolder = data:FindFirstChild("TimedRewards")
		if timedRewardsFolder then
			bindTimedRewardsFolder(timedRewardsFolder)
		end
		table.insert(dataConnections, data.ChildAdded:Connect(function(child)
			if child.Name == "TimedRewards" then
				bindTimedRewardsFolder(child)
			end
		end))
		ctx.onUpdate()
	end

	local data = player:FindFirstChild("Data")
	if data then
		bindData(data)
	else
		table.insert(dataConnections, player.ChildAdded:Connect(function(child)
			if child.Name == "Data" then
				bindData(child)
			end
		end))
	end
end

function TimedRewardsUI.Claim(ctx)
	if not ctx.claimTimedRewardRemote then
		return
	end

	local result
	local success, errorMessage = pcall(function()
		result = ctx.claimTimedRewardRemote:InvokeServer()
	end)

	if not success then
		ctx.showAlert("Timed Rewards", tostring(errorMessage), false, nil, nil, "error")
		return
	end

	if type(result) == "table" and result.snapshot and ctx.applySnapshot then
		ctx.applySnapshot(result.snapshot)
	end

	if type(result) == "table" and result.success then
		TimedRewardsUI.ApplyState(ctx, result.state)
		local rewardText = ctx.timedRewardsConfig.GetRewardDescription({
			rewardType = result.rewardType,
			amount = result.rewardAmount,
		})
		ctx.showAlert("Reward Claimed", rewardText, false, nil, nil, "reward")
	elseif type(result) == "table" and result.message then
		TimedRewardsUI.ApplyState(ctx, result.state or TimedRewardsUI.GetState(ctx))
		ctx.showAlert("Timed Rewards", result.message, false, nil, nil, "info")
	else
		ctx.onUpdate()
	end
end


-- Board outcome and Classic level-selection screen flow.
local SummaryScreen = {}

function SummaryScreen.create(env)
local player = env.player
local ReplicatedStorage = env.ReplicatedStorage

local RuntimeHelpers = env.RuntimeHelpers
local Dependencies = env.Dependencies
local ClassicLevels = env.ClassicLevels
local state = env.state
local ui = env.ui
local remotes = env.remotes

local create = env.create
local cloneTable = env.cloneTable
local findDescendantByNames = env.findDescendantByNames
local findFirstPath = env.findFirstPath
local findTextObject = env.findTextObject
local ensureScaleController = env.ensureScaleController
local findButtonLike = env.findButtonLike
local tween = env.tween
local ButtonUi = env.ButtonUi
local ANIMATION = env.ANIMATION
local COLORS = env.COLORS
local ALERT_TOAST_COLORS = env.ALERT_TOAST_COLORS
local MODAL_PARENT_OPEN_TRANSPARENCY = env.MODAL_PARENT_OPEN_TRANSPARENCY
local PUZZLE_PIECE_TEXT = env.PUZZLE_PIECE_TEXT
local playSound = env.playSound
local showDesktopAlert = env.showDesktopAlert
local getSnapshot = env.getSnapshot
local startClassicLevelFromSelector = env.startClassicLevelFromSelector
local pulseScale = env.pulseScale or function() end

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

local function enterSelectedMode(...)
	return env.enterSelectedMode(...)
end

local function bindSummaryButtons()
	if ui.summaryButton and not ui.summaryButton:GetAttribute("WordSearchBound") then
		ButtonUi.prepare(ui.summaryButton, COLORS.buttonPrimary)
		ui.summaryButton:SetAttribute("WordSearchBound", true)
		ui.summaryButton.Activated:Connect(function()
			if ui.summaryButton:GetAttribute("ButtonEnabled") == false
				or state.summaryGiftClaimPending == true
				or state.summaryGiftSequenceActive == true then
				return
			end

			playSound("Button2")
			if state.summaryAction then
				state.summaryAction()
			end
		end)
	end

	if ui.summaryGiftButton and not ui.summaryGiftButton:GetAttribute("WordSearchBound") then
		ui.summaryGiftButton:SetAttribute("WordSearchBound", true)
		ui.summaryGiftButton.Activated:Connect(function()
			playSound("Button2")
			RuntimeHelpers.claimSummaryGift()
		end)
	end
end

local function resolveSummaryButtonLabel(summaryButtonRoot)
	if not summaryButtonRoot then
		return nil
	end

	local labelNode = (findFirstPath and findFirstPath(summaryButtonRoot, {
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
		or nil
	if labelNode and not (labelNode:IsA("TextLabel") or labelNode:IsA("TextButton")) then
		labelNode = findTextObject(labelNode, { "Label", "TextLabel" })
	end

	return labelNode
end

local function bindSummaryUiIfNeeded()
	if ui.summaryOverlay and ui.summaryCard and ui.summaryTitleLabel and ui.summaryButton then
		bindSummaryButtons()
		return true
	end

	local existingGui = ui.screenGui
	if not existingGui then
		return false
	end

	local framesRoot = ui.framesRoot or existingGui:FindFirstChild("Frames") or findDescendantByNames(existingGui, { "Frames" }, nil)
	local summaryRoot = (findFirstPath and findFirstPath(framesRoot or existingGui, {
		{ "GameOutcome" },
		{ "SummaryOverlay" },
	}, nil))
		or findDescendantByNames(framesRoot or existingGui, { "GameOutcome", "SummaryOverlay" }, nil)
	if not summaryRoot then
		return false
	end

	ui.framesRoot = framesRoot or ui.framesRoot
	ui.summaryOverlay = summaryRoot
	ui.summaryCard = (findFirstPath and findFirstPath(summaryRoot, {
		{ "Frame" },
		{ "Card" },
		{ "Container" },
	}, nil))
		or findDescendantByNames(summaryRoot, { "Frame", "Card", "Container" }, nil)
		or findDescendantByNames(framesRoot or existingGui, { "SummaryCard" }, nil)
		or summaryRoot
	ui.summaryCardScale = ui.summaryCard and ensureScaleController(ui.summaryCard) or ui.summaryCardScale
	ui.summaryCardOpenSize = ui.summaryCardOpenSize or UDim2.fromScale(0.6, 0.6)
	ui.summaryCardOpenPosition = ui.summaryCardOpenPosition or UDim2.fromScale(0.5, 0.5)
	ui.summaryOverlayOpenTransparency = resolveOverlayOpenTransparency(
		(ui.summaryOverlay ~= ui.summaryCard and ui.summaryOverlay and ui.summaryOverlay.BackgroundTransparency) or nil
	)
	ui.summaryCardOpenTransparency = resolveCardOpenTransparency(
		ui.summaryCard and ui.summaryCard.BackgroundTransparency or nil,
		0.08
	)
	ui.summaryTitleLabel = findTextObject(
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
	)
	ui.summaryBodyLabel = findTextObject(
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
			or ui.summaryBodyLabel
			or summaryRoot,
		{ "Body", "SummaryBodyLabel", "Description", "Desc", "Sub", "Status", "Label", "TextLabel" }
	)
	local summaryButtonSearchRoot = ui.summaryCard or summaryRoot
	local summaryButtonRoot = (findFirstPath and findFirstPath(summaryButtonSearchRoot, {
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
	ui.summaryButton = findButtonLike(summaryButtonRoot) or ui.summaryButton
	ui.summaryButtonLabel = resolveSummaryButtonLabel(summaryButtonRoot) or ui.summaryButtonLabel
	ui.summaryButtonBaseTransparency = ui.summaryButton and ui.summaryButton.BackgroundTransparency or ui.summaryButtonBaseTransparency or 0

	bindSummaryButtons()
	return ui.summaryOverlay ~= nil and ui.summaryCard ~= nil and ui.summaryTitleLabel ~= nil and ui.summaryButton ~= nil
end

local showSummary
local hideSummary
local refreshClassicLevelsFrame
local hideClassicLevelsFrame
local showClassicLevelsFrame

RuntimeHelpers.getSummaryTotalWins = function(snapshot, fallback)
	local progressFolder = player:FindFirstChild("Data") and player.Data:FindFirstChild("Progress") or nil
	local mirroredTotalCompleted = progressFolder and progressFolder:FindFirstChild("TotalCompleted") or nil
	local stats = snapshot and snapshot.stats or nil
	local modeResults = type(stats and stats.modeResults) == "table" and stats.modeResults or nil
	local totalBucket = type(modeResults and modeResults.Total) == "table" and modeResults.Total or nil
	local fallbackWins = math.max(0, math.floor(tonumber(fallback) or 0))
	local wins = math.max(
		0,
		math.floor(tonumber(stats and stats.boardsCleared) or 0),
		math.floor(tonumber(totalBucket and totalBucket.wins) or 0),
		math.floor(tonumber(mirroredTotalCompleted and mirroredTotalCompleted.Value) or 0),
		fallbackWins
	)

	return wins
end

RuntimeHelpers.getSummaryGiftClaimMilestone = function(snapshot)
	local progressFolder = player:FindFirstChild("Data") and player.Data:FindFirstChild("Progress") or nil
	local mirroredMilestone = progressFolder and progressFolder:FindFirstChild("GiftClaimMilestone") or nil
	local progression = snapshot and snapshot.progression or nil
	return math.max(
		0,
		math.floor(tonumber(progression and progression.giftClaimMilestone) or 0),
		math.floor(tonumber(mirroredMilestone and mirroredMilestone.Value) or 0)
	)
end

RuntimeHelpers.setSummaryText = function(node, text)
	if node and (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) then
		node.Text = tostring(text or "")
	end
end

RuntimeHelpers.resetSummaryStarScales = function()
	local starScales = {
		ui.summaryStarOneScale,
		ui.summaryStarTwoScale,
		ui.summaryStarThreeScale,
	}

	for _, scaleController in ipairs(starScales) do
		if scaleController and scaleController.Parent then
			scaleController.Scale = 1
		end
	end
end

RuntimeHelpers.getSummaryOutcomeMode = function(context)
	local modeName = type(context) == "table" and tostring(context.mode or "") or ""
	if modeName ~= "" then
		return modeName
	end

	return tostring(state.mode or "")
end

RuntimeHelpers.shouldShowSummaryStarIcons = function(context)
	local modeName = RuntimeHelpers.getSummaryOutcomeMode(context)
	return modeName == "Classic" or modeName == "Duel"
end

RuntimeHelpers.getSummaryStarsTitleText = function(context)
	if type(context) ~= "table" then
		return ""
	end
	if context.starsTitleText ~= nil then
		return tostring(context.starsTitleText)
	end
	if context.isLoss == true then
		return "Keep going!"
	end

	local starCount = math.clamp(math.floor(tonumber(context.stars) or 0), 0, 3)
	if starCount >= 3 then
		return "Magnificent!"
	elseif starCount >= 2 then
		return "Great job!"
	elseif starCount >= 1 then
		return "Nice work!"
	end

	return "Good job!"
end

RuntimeHelpers.applySummaryStars = function(stars, context)
	local starCount = math.clamp(math.floor(tonumber(stars) or 0), 0, 3)
	local showStarIcons = RuntimeHelpers.shouldShowSummaryStarIcons(context)

	if ui.summaryStarsRoot and ui.summaryStarsRoot:IsA("GuiObject") then
		ui.summaryStarsRoot.Visible = showStarIcons or (ui.summaryStarsTitleLabel ~= nil)
	end

	if ui.summaryStarsTitleLabel and ui.summaryStarsTitleLabel:IsA("GuiObject") then
		ui.summaryStarsTitleLabel.Visible = not showStarIcons
		RuntimeHelpers.setSummaryText(ui.summaryStarsTitleLabel, not showStarIcons and RuntimeHelpers.getSummaryStarsTitleText(context) or "")
	end

	for _, starNode in ipairs({ ui.summaryStarOne, ui.summaryStarTwo, ui.summaryStarThree }) do
		if starNode and starNode:IsA("GuiObject") then
			starNode.Visible = showStarIcons
		end
	end

	RuntimeHelpers.resetSummaryStarScales()
	if not showStarIcons then
		return
	end

	ClassicLevels.applyClassicLevelStarVisual(ui.summaryStarOne, starCount >= 1)
	ClassicLevels.applyClassicLevelStarVisual(ui.summaryStarTwo, starCount >= 2)
	ClassicLevels.applyClassicLevelStarVisual(ui.summaryStarThree, starCount >= 3)
end

RuntimeHelpers.playSummaryStarAnimation = function(stars, animationToken)
	if not RuntimeHelpers.shouldShowSummaryStarIcons(state.summaryOutcomeContext) then
		return
	end

	local starCount = math.clamp(math.floor(tonumber(stars) or 0), 0, 3)
	if starCount <= 0 then
		return
	end

	local starScales = {
		ui.summaryStarOneScale,
		ui.summaryStarTwoScale,
		ui.summaryStarThreeScale,
	}

	for index = 1, starCount do
		local scaleController = starScales[index]
		if scaleController and scaleController.Parent then
			task.delay((index - 1) * 0.18, function()
				if animationToken ~= state.summaryStarAnimationToken then
					return
				end
				if not (ui.summaryOverlay and ui.summaryOverlay.Visible) then
					return
				end

				pulseScale(scaleController, 1.25, 1, 0)
			end)
		end
	end
end

function RuntimeHelpers.renderSummaryOutcome()
	local context = type(state.summaryOutcomeContext) == "table" and state.summaryOutcomeContext or nil
	if not context then
		if ui.summaryStarsRoot and ui.summaryStarsRoot:IsA("GuiObject") then
			ui.summaryStarsRoot.Visible = false
		end
		if ui.summaryStarsTitleLabel and ui.summaryStarsTitleLabel:IsA("GuiObject") then
			ui.summaryStarsTitleLabel.Visible = false
			RuntimeHelpers.setSummaryText(ui.summaryStarsTitleLabel, "")
		end
		RuntimeHelpers.resetSummaryStarScales()
		if ui.summaryGiftRoot and ui.summaryGiftRoot:IsA("GuiObject") then
			ui.summaryGiftRoot.Visible = false
		end
		return
	end

	local snapshot = type(state.playerData) == "table" and state.playerData or nil
	local totalWins = RuntimeHelpers.getSummaryTotalWins(snapshot, context.totalWins)
	local claimedMilestone = RuntimeHelpers.getSummaryGiftClaimMilestone(snapshot)
	local previewPuzzlePieces = math.max(
		math.floor(tonumber(Dependencies.PuzzleEconomy.MinimumCompletionReward) or 0),
		math.floor(tonumber(context.previewPuzzlePieces) or 0)
	)
	local puzzlePiecesEarned = previewPuzzlePieces

	if context.isLoss == true and context.keepLossReward ~= true then
		puzzlePiecesEarned = 0
	elseif snapshot then
		local startPieces = math.max(0, math.floor(tonumber(context.startPuzzlePieces) or 0))
		local currentPieces = math.max(0, math.floor(tonumber(snapshot.inventory and snapshot.inventory.puzzlePieces) or startPieces))
		puzzlePiecesEarned = math.max(previewPuzzlePieces, currentPieces - startPieces)
	end

	if ui.summaryBodyLabel then
		ui.summaryBodyLabel.Text = tostring(context.body or "")
	end

	if ui.summaryCurrencyEarnedLabel and ui.summaryCurrencyEarnedLabel:IsA("GuiObject") then
		ui.summaryCurrencyEarnedLabel.Visible = true
		RuntimeHelpers.setSummaryText(ui.summaryCurrencyEarnedLabel, string.format("+ %s %d", PUZZLE_PIECE_TEXT, puzzlePiecesEarned))
	end

	RuntimeHelpers.applySummaryStars(context.stars, context)

	if ui.summaryGiftRoot and ui.summaryGiftRoot:IsA("GuiObject") then
		if context.hideGift == true then
			ui.summaryGiftRoot.Visible = false
			if ui.summaryGiftButton then
				ui.summaryGiftButton.Active = false
				ui.summaryGiftButton.Selectable = false
			end
			return
		end

		local giftState = Dependencies.GiftProgress.GetProgressState(totalWins, claimedMilestone)
		local giftReady = giftState.ready == true and state.summaryGiftClaimPending ~= true
		local previousWins = math.max(
			0,
			math.floor(tonumber(context.previousTotalWins) or (context.isLoss == true and totalWins or (totalWins - 1)))
		)
		local previousGiftState = Dependencies.GiftProgress.GetProgressState(previousWins, claimedMilestone)
		local shouldAutoPromptGift = giftState.ready == true
			and context.isLoss ~= true
			and previousGiftState.ready ~= true
			and state.summaryGiftClaimPending ~= true

		ui.summaryGiftRoot.Visible = true
		ui.summaryGiftRoot:SetAttribute("GiftReady", giftReady)

		if ui.summaryGiftFill and ui.summaryGiftFill:IsA("GuiObject") then
			tween(ui.summaryGiftFill, {
				Size = UDim2.new(math.clamp(giftState.fillAlpha, 0, 1), 0, 1, 0),
			}, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end

		if ui.summaryGiftText then
			if state.summaryGiftClaimPending then
				RuntimeHelpers.setSummaryText(ui.summaryGiftText, "Claiming...")
			elseif giftState.ready then
				RuntimeHelpers.setSummaryText(ui.summaryGiftText, "Gift Ready!")
			else
				RuntimeHelpers.setSummaryText(ui.summaryGiftText, string.format("Win %d more", giftState.winsRemaining))
			end
		end

		if ui.summaryGiftButton then
			ui.summaryGiftButton.Active = giftReady
			ui.summaryGiftButton.Selectable = giftReady
		end
		if ui.summaryButton then
			ButtonUi.setClickableOnly(ui.summaryButton, state.summaryGiftSequenceActive ~= true and state.summaryGiftClaimPending ~= true)
		end

		if shouldAutoPromptGift and state.metaUiController and state.metaUiController.showGiftReward then
			state.summaryGiftSequenceActive = true
			ButtonUi.setClickableOnly(ui.summaryButton, false)
			local summaryToken = state.summaryStarAnimationToken
			if state.summaryGiftAutoPromptToken ~= summaryToken then
				state.summaryGiftAutoPromptToken = summaryToken
				task.delay(2, function()
					if state.summaryGiftAutoPromptToken ~= summaryToken then
						state.summaryGiftSequenceActive = false
						if RuntimeHelpers.renderSummaryOutcome then
							RuntimeHelpers.renderSummaryOutcome()
						end
						return
					end
					if not (ui.summaryOverlay and ui.summaryOverlay.Visible) then
						state.summaryGiftSequenceActive = false
						return
					end

					local summaryAction = state.summaryAction
					hideSummary()
					state.metaUiController:showGiftReward("Gift unlocked! Claim your reward.", function()
						if RuntimeHelpers.claimGiftReward(true, function()
							if summaryAction then
								summaryAction()
							end
						end) ~= true and summaryAction then
							state.summaryGiftSequenceActive = false
							summaryAction()
						end
					end)
				end)
			end
		end
	end
end

function RuntimeHelpers.claimGiftReward(forceReady, onComplete)
	if state.summaryGiftClaimPending or not remotes.claimGift then
		return false
	end

	if forceReady ~= true and not (ui.summaryGiftRoot and ui.summaryGiftRoot:GetAttribute("GiftReady") == true) then
		return false
	end

	state.summaryGiftAutoPromptToken = 0
	state.summaryGiftClaimPending = true
	state.summaryGiftSequenceActive = true
	state.pendingGiftClaimResultCallback = type(onComplete) == "function" and onComplete or nil
	RuntimeHelpers.renderSummaryOutcome()
	remotes.claimGift:FireServer()
	return true
end

function RuntimeHelpers.claimSummaryGift()
	if not RuntimeHelpers.claimGiftReward(false) then
		return
	end
end

showSummary = function(title, body, buttonText, accentColor, action, outcomeContext)
	if not bindSummaryUiIfNeeded() then
		warn("[WordSearch] Summary UI binding missing GameOutcome frame.")
		return
	end

	playSound("OpenFrame")
	state.summaryAction = action
	state.summaryOutcomeContext = type(outcomeContext) == "table" and cloneTable(outcomeContext) or nil
	state.summaryGiftClaimPending = false
	state.summaryGiftSequenceActive = false
	state.pendingGiftClaimResultCallback = nil
	state.summaryStarAnimationToken = (state.summaryStarAnimationToken or 0) + 1
	state.summaryGiftAutoPromptToken = 0
	if state.summaryOutcomeContext and state.summaryOutcomeContext.body == nil then
		state.summaryOutcomeContext.body = body
	end
	if state.summaryOutcomeContext and state.summaryOutcomeContext.mode == nil then
		state.summaryOutcomeContext.mode = state.duelActive and "Duel" or state.mode
	end
	ui.summaryTitleLabel.Text = title
	if ui.summaryBodyLabel then
		ui.summaryBodyLabel.Text = body
	end
	if ui.summaryButton and (ui.summaryButton:IsA("TextButton") or ui.summaryButton:IsA("TextLabel")) then
		ui.summaryButton.Text = buttonText
	end
	if ui.summaryButtonLabel then
		ui.summaryButtonLabel.Text = buttonText
	end
	ButtonUi.setBaseColor(ui.summaryButton, accentColor)
	ui.summaryOverlay.Visible = true
	if ui.summaryCard and ui.summaryCard ~= ui.summaryOverlay and ui.summaryCard:IsA("GuiObject") then
		ui.summaryCard.Visible = true
		ui.summaryCard.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.summaryCard.Position = ui.summaryCardOpenPosition or UDim2.fromScale(0.5, 0.5)
		ui.summaryCard.Size = UDim2.fromScale(0, 0)
	end
	ui.summaryOverlay.BackgroundTransparency = 1
	ui.summaryCard.BackgroundTransparency = 1
	if ui.summaryCardScale then
		ui.summaryCardScale.Scale = 0.94
	end
	ui.summaryTitleLabel.TextTransparency = 1
	if ui.summaryBodyLabel then
		ui.summaryBodyLabel.TextTransparency = 1
	end

	if ui.summaryOverlay == ui.summaryCard then
		tween(ui.summaryCard, { BackgroundTransparency = ui.summaryCardOpenTransparency or 0.08 }, ANIMATION.PopupIn)
	else
		tween(ui.summaryOverlay, { BackgroundTransparency = ui.summaryOverlayOpenTransparency or MODAL_PARENT_OPEN_TRANSPARENCY }, ANIMATION.SoftFadeIn)
		tween(ui.summaryCard, {
			BackgroundTransparency = ui.summaryCardOpenTransparency or 0.08,
			Size = ui.summaryCardOpenSize or UDim2.fromScale(0.6, 0.6),
			Position = ui.summaryCardOpenPosition or UDim2.fromScale(0.5, 0.5),
		}, ANIMATION.PopupIn)
	end
	if ui.summaryCardScale then
		tween(ui.summaryCardScale, { Scale = 1 }, ANIMATION.PopupIn)
	end
	tween(ui.summaryTitleLabel, { TextTransparency = 0 }, ANIMATION.SoftFadeIn)
	if ui.summaryBodyLabel then
		tween(ui.summaryBodyLabel, { TextTransparency = 0 }, ANIMATION.SoftFadeIn)
	end
	if state.summaryOutcomeContext and state.summaryOutcomeContext.preserveButtonTransparency == true then
		ButtonUi.setBaseColor(ui.summaryButton, accentColor)
		ButtonUi.setClickableOnly(ui.summaryButton, true)
		ui.summaryButton:SetAttribute("ButtonEnabled", true)
		ui.summaryButton.BackgroundTransparency = ui.summaryButtonBaseTransparency or ui.summaryButton.BackgroundTransparency
	else
		ButtonUi.setEnabled(ui.summaryButton, true, accentColor)
	end
	if RuntimeHelpers.renderSummaryOutcome then
		RuntimeHelpers.renderSummaryOutcome()
	end
	if state.summaryOutcomeContext and RuntimeHelpers.playSummaryStarAnimation then
		local starAnimationToken = state.summaryStarAnimationToken
		task.delay(0.16, function()
			if starAnimationToken ~= state.summaryStarAnimationToken then
				return
			end

			RuntimeHelpers.playSummaryStarAnimation(state.summaryOutcomeContext.stars, starAnimationToken)
		end)
	end
end

hideSummary = function()
	if ui.summaryOverlay and ui.summaryOverlay.Visible then
		playSound("CloseFrame")
	end

	state.summaryStarAnimationToken = (state.summaryStarAnimationToken or 0) + 1
	RuntimeHelpers.resetSummaryStarScales()

	if ui.summaryOverlay then
		tween(ui.summaryOverlay, { BackgroundTransparency = 1 }, ANIMATION.SoftFadeOut)
	end
	if ui.summaryCard and ui.summaryCard:IsA("GuiObject") and ui.summaryCard ~= ui.summaryOverlay then
		tween(ui.summaryCard, {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 0),
			Position = ui.summaryCardOpenPosition or UDim2.fromScale(0.5, 0.5),
		}, ANIMATION.PopupOut)
	end
	if ui.summaryCardScale then
		tween(ui.summaryCardScale, { Scale = 0.96 }, ANIMATION.PopupOut)
	end
	if ui.summaryTitleLabel then
		tween(ui.summaryTitleLabel, { TextTransparency = 1 }, ANIMATION.SoftFadeOut)
	end
	if ui.summaryBodyLabel then
		tween(ui.summaryBodyLabel, { TextTransparency = 1 }, ANIMATION.SoftFadeOut)
	end
	task.delay(ANIMATION.PopupOut.Time + 0.02, function()
		if ui.summaryOverlay then
			ui.summaryOverlay.Visible = false
		end
		if ui.summaryCard and ui.summaryCard ~= ui.summaryOverlay and ui.summaryCard:IsA("GuiObject") then
			ui.summaryCard.Visible = false
		end
	end)

	state.summaryAction = nil
	state.summaryOutcomeContext = nil
	state.summaryGiftClaimPending = false
	state.summaryGiftSequenceActive = false
end

function RuntimeHelpers.bindClassicLevelsUi(existingGui, framesRoot)
	local levelsOverlay = (framesRoot and (
		framesRoot:FindFirstChild("Levels")
			or findDescendantByNames(framesRoot, { "Levels" }, nil)
	)) or findDescendantByNames(existingGui, { "Levels" }, nil)
	local levelsCard = levelsOverlay and (findDescendantByNames(levelsOverlay, { "Frame" }, nil) or levelsOverlay) or nil
	local levelsContainer = levelsCard and (
		findDescendantByNames(levelsCard, { "Container", "ScrollingFrame", "List" }, nil)
	) or nil
	local levelsTitleRoot = levelsCard and levelsCard:FindFirstChild("Title") or nil
	local levelsCloseRoot = levelsCard and (
		levelsCard:FindFirstChild("Quit")
			or levelsCard:FindFirstChild("Back")
			or levelsCard:FindFirstChild("Exit")
			or levelsCard:FindFirstChild("Close")
			or findDescendantByNames(levelsCard, { "Quit", "Back", "Exit", "Close" }, nil)
	) or levelsOverlay

	ui.levelsOverlay = levelsOverlay
	ui.levelsCard = levelsCard
	ui.levelsContainer = levelsContainer
	ui.levelsTitleLabel = levelsTitleRoot and (
		(levelsTitleRoot:IsA("TextLabel") or levelsTitleRoot:IsA("TextButton")) and levelsTitleRoot
			or findTextObject(levelsTitleRoot, { "TextLabel", "Label", "Title" })
	) or nil
	ui.levelsCloseButton = levelsCloseRoot and findButtonLike(levelsCloseRoot) or nil
	ui.levelTemplate = ClassicLevels.getClassicLevelTemplate(ui, ReplicatedStorage)
	ui.levelEntries = ui.levelEntries or {}
	ui.levelsCardOpenSize = UDim2.fromScale(0.85, 0.85)
	ui.levelsCardOpenPosition = UDim2.fromScale(0.5, 0.5)
	ui.levelsOverlayOpenTransparency = resolveOverlayOpenTransparency(
		(levelsOverlay ~= levelsCard and levelsOverlay and levelsOverlay.BackgroundTransparency) or nil
	)
	ui.levelsCardOpenTransparency = resolveCardOpenTransparency(
		levelsCard and levelsCard.BackgroundTransparency or nil,
		0.08
	)

	local levelsScrollFrame = levelsContainer and (
		levelsContainer:IsA("ScrollingFrame") and levelsContainer
			or ((levelsContainer.Parent and levelsContainer.Parent:IsA("ScrollingFrame")) and levelsContainer.Parent or nil)
	) or nil

	if levelsScrollFrame then
		levelsScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		levelsScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		levelsScrollFrame.ScrollBarThickness = math.max(8, levelsScrollFrame.ScrollBarThickness)

		local levelsPadding = levelsScrollFrame:FindFirstChild("ClassicLevelsPadding")
		if not (levelsPadding and levelsPadding:IsA("UIPadding")) then
			levelsPadding = create("UIPadding", {
				Name = "ClassicLevelsPadding",
				Parent = levelsScrollFrame,
			})
		end
		if levelsPadding and levelsPadding:IsA("UIPadding") then
			levelsPadding.PaddingBottom = UDim.new(0, 72)
		end
	end

	if levelsContainer
		and not levelsContainer:FindFirstChildOfClass("UIGridLayout")
		and not levelsContainer:FindFirstChildOfClass("UIListLayout") then
		create("UIGridLayout", {
			Name = "ClassicLevelsLayout",
			CellPadding = UDim2.fromOffset(12, 12),
			CellSize = UDim2.fromOffset(94, 94),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = levelsContainer,
		})
	end

	if ui.levelsTitleLabel then
		ui.levelsTitleLabel.Text = string.format("Levels (%d/%d)", ClassicLevels.getCompletedClassicLevelsCount(state, Dependencies), #Dependencies.Levels)
	end

	if levelsOverlay and levelsOverlay:IsA("GuiObject") then
		levelsOverlay.Visible = false
		levelsOverlay.BackgroundTransparency = 1
	end

	if levelsCard and levelsCard ~= levelsOverlay and levelsCard:IsA("GuiObject") then
		levelsCard.Visible = false
		levelsCard.AnchorPoint = Vector2.new(0.5, 0.5)
		levelsCard.Position = ui.levelsCardOpenPosition
		levelsCard.Size = UDim2.fromScale(0, 0)
		levelsCard.BackgroundTransparency = ui.levelsCardOpenTransparency or levelsCard.BackgroundTransparency
	end
end

refreshClassicLevelsFrame = function()
	local container = ui.levelsContainer
	if not (container and container.Parent) then
		return
	end

	ui.levelTemplate = ClassicLevels.getClassicLevelTemplate(ui, ReplicatedStorage)
	local totalLevels = #Dependencies.Levels
	local unlockedLevel = ClassicLevels.getClassicUnlockedLevel(state, Dependencies)
	local completedCount = ClassicLevels.getCompletedClassicLevelsCount(state, Dependencies)

	for levelNumber = 1, totalLevels do
		local entry = ui.levelEntries[levelNumber]
		if not (entry and entry.root and entry.root.Parent) then
			entry = ClassicLevels.createClassicLevelEntry({
				ui = ui,
				ReplicatedStorage = ReplicatedStorage,
				create = create,
				findDescendantByNames = findDescendantByNames,
				findButtonLike = findButtonLike,
				ButtonUi = ButtonUi,
				startClassicLevelFromSelector = startClassicLevelFromSelector,
			}, levelNumber)
		end

		if entry and entry.root then
			local starCount = ClassicLevels.getClassicLevelStarCount(state, Dependencies, levelNumber)
			local isUnlocked = levelNumber <= unlockedLevel
			local isCompleted = ClassicLevels.isClassicLevelCompleted(state, Dependencies, levelNumber)

			entry.root:SetAttribute("ClassicLevel", levelNumber)
			entry.root:SetAttribute("Unlocked", isUnlocked)
			entry.root:SetAttribute("Stars", starCount)
			entry.root:SetAttribute("Completed", isCompleted)

			ClassicLevels.applyClassicLevelVisualState(entry, isUnlocked, starCount, isCompleted, findDescendantByNames)

			if entry.label and (entry.label:IsA("TextLabel") or entry.label:IsA("TextButton")) then
				entry.label.Text = tostring(levelNumber)
			end

			ClassicLevels.applyClassicLevelStarVisual(entry.starOne, starCount >= 1)
			ClassicLevels.applyClassicLevelStarVisual(entry.starTwo, starCount >= 2)
			ClassicLevels.applyClassicLevelStarVisual(entry.starThree, starCount >= 3)

			ButtonUi.setClickableOnly(entry.pressable, isUnlocked)
		end
	end

	local titleText = string.format("Levels (%d/%d)", completedCount, totalLevels)
	if ui.levelsTitleLabel then
		ui.levelsTitleLabel.Text = titleText
	end
end

hideClassicLevelsFrame = function(animate, onComplete)
	if not ui.levelsOverlay then
		if onComplete then
			onComplete()
		end
		return
	end

	if not ui.levelsOverlay.Visible then
		if onComplete then
			onComplete()
		end
		return
	end

	if animate == false then
		ui.levelsOverlay.Visible = false
		if ui.levelsCard and ui.levelsCard ~= ui.levelsOverlay and ui.levelsCard:IsA("GuiObject") then
			ui.levelsCard.Visible = false
			ui.levelsCard.Size = UDim2.fromScale(0, 0)
		end
		if onComplete then
			onComplete()
		end
		return
	end

	playSound("CloseFrame")
	tween(ui.levelsOverlay, { BackgroundTransparency = 1 }, ANIMATION.SoftFadeOut)
	if ui.levelsCard and ui.levelsCard ~= ui.levelsOverlay and ui.levelsCard:IsA("GuiObject") then
		tween(ui.levelsCard, {
			Position = ui.levelsCardOpenPosition or UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0, 0),
		}, ANIMATION.PopupOut)
	end

	task.delay(ANIMATION.PopupOut.Time + 0.02, function()
		if ui.levelsOverlay then
			ui.levelsOverlay.Visible = false
		end
		if ui.levelsCard and ui.levelsCard ~= ui.levelsOverlay and ui.levelsCard:IsA("GuiObject") then
			ui.levelsCard.Visible = false
		end
		if onComplete then
			onComplete()
		end
	end)
end

showClassicLevelsFrame = function()
	if ui.screenGui then
		RuntimeHelpers.bindClassicLevelsUi(ui.screenGui, ui.framesRoot)
		RuntimeHelpers.bindClassicLevelsFrameActions()
	end

	if not (ui.levelsOverlay and ui.levelsCard and ui.levelsContainer) then
		enterSelectedMode()
		return
	end

	refreshClassicLevelsFrame()
	playSound("OpenFrame")
	ui.levelsOverlay.Visible = true
	ui.levelsOverlay.BackgroundTransparency = 1

	if ui.levelsCard == ui.levelsOverlay then
		tween(ui.levelsCard, {
			BackgroundTransparency = ui.levelsCardOpenTransparency or 0.08,
		}, ANIMATION.PopupIn)
	else
		ui.levelsCard.Visible = true
		ui.levelsCard.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.levelsCard.Position = ui.levelsCardOpenPosition or UDim2.fromScale(0.5, 0.5)
		ui.levelsCard.Size = UDim2.fromScale(0, 0)
		ui.levelsCard.BackgroundTransparency = ui.levelsCardOpenTransparency or 0.08
		tween(ui.levelsOverlay, {
			BackgroundTransparency = ui.levelsOverlayOpenTransparency or MODAL_PARENT_OPEN_TRANSPARENCY,
		}, ANIMATION.SoftFadeIn)
		tween(ui.levelsCard, {
			Position = ui.levelsCardOpenPosition or UDim2.fromScale(0.5, 0.5),
			Size = ui.levelsCardOpenSize or UDim2.fromScale(0.6, 0.6),
		}, ANIMATION.PopupIn)
	end

	RuntimeHelpers.scrollClassicLevelsToLevel(RuntimeHelpers.getClassicContinueLevel())
end


return {
	showSummary = showSummary,
	hideSummary = hideSummary,
	refreshClassicLevelsFrame = refreshClassicLevelsFrame,
	hideClassicLevelsFrame = hideClassicLevelsFrame,
	showClassicLevelsFrame = showClassicLevelsFrame,
}
end

return {
	TimedRewards = TimedRewardsUI,
	Summary = SummaryScreen,
}
