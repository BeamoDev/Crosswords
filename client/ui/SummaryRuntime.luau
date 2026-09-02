local module = {}

function module.create(env)
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
		math.floor(tonumber(stats and stats.solves) or tonumber(stats and stats.boardsCleared) or 0),
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
	return false
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
		local summaryGiftDebugKey = table.concat({
			tostring(context.mode or state.mode or ""),
			tostring(totalWins),
			tostring(previousWins),
			tostring(claimedMilestone),
			tostring(giftState.nextMilestone),
			tostring(giftState.ready == true),
			string.format("%.3f", math.clamp(tonumber(giftState.fillAlpha) or 0, 0, 1)),
			tostring(giftState.winsRemaining or 0),
			tostring(context.isLoss == true),
		}, "|")
		if state.summaryGiftDebugKey ~= summaryGiftDebugKey then
			state.summaryGiftDebugKey = summaryGiftDebugKey
			print(string.format(
				"[WordSearch Gift] render mode=%s totalWins=%d previousWins=%d claimed=%d next=%d ready=%s fill=%.3f remaining=%d loss=%s",
				tostring(context.mode or state.mode or ""),
				totalWins,
				previousWins,
				claimedMilestone,
				math.max(0, math.floor(tonumber(giftState.nextMilestone) or 0)),
				tostring(giftState.ready == true),
				math.clamp(tonumber(giftState.fillAlpha) or 0, 0, 1),
				math.max(0, math.floor(tonumber(giftState.winsRemaining) or 0)),
				tostring(context.isLoss == true)
			))
		end
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
		print(string.format(
			"[WordSearch Gift] claim blocked pending=%s remote=%s forceReady=%s giftReady=%s",
			tostring(state.summaryGiftClaimPending == true),
			tostring(remotes.claimGift ~= nil),
			tostring(forceReady == true),
			tostring(ui.summaryGiftRoot and ui.summaryGiftRoot:GetAttribute("GiftReady") == true or false)
		))
		return false
	end

	if forceReady ~= true and not (ui.summaryGiftRoot and ui.summaryGiftRoot:GetAttribute("GiftReady") == true) then
		print(string.format(
			"[WordSearch Gift] claim skipped forceReady=%s giftReady=%s",
			tostring(forceReady == true),
			tostring(ui.summaryGiftRoot and ui.summaryGiftRoot:GetAttribute("GiftReady") == true or false)
		))
		return false
	end

	state.summaryGiftAutoPromptToken = 0
	state.summaryGiftClaimPending = true
	state.summaryGiftSequenceActive = true
	state.pendingGiftClaimResultCallback = type(onComplete) == "function" and onComplete or nil
	print(string.format(
		"[WordSearch Gift] claim fired forceReady=%s mode=%s totalWins=%s",
		tostring(forceReady == true),
		tostring(state.summaryOutcomeContext and state.summaryOutcomeContext.mode or state.mode or ""),
		tostring(state.summaryOutcomeContext and state.summaryOutcomeContext.totalWins or state.totalStars or 0)
	))
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
	ui.levelsOverlay = nil
	ui.levelsCard = nil
	ui.levelsContainer = nil
	ui.levelsTitleLabel = nil
	ui.levelsCloseButton = nil
	ui.levelTemplate = nil
end

refreshClassicLevelsFrame = function()
	return
end

hideClassicLevelsFrame = function(animate, onComplete)
	if onComplete then
		onComplete()
	end
end

showClassicLevelsFrame = function()
	enterSelectedMode()
end


return {
	showSummary = showSummary,
	hideSummary = hideSummary,
	refreshClassicLevelsFrame = refreshClassicLevelsFrame,
	hideClassicLevelsFrame = hideClassicLevelsFrame,
	showClassicLevelsFrame = showClassicLevelsFrame,
}
end

return module
