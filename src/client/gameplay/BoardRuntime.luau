local module = {}

function module.create(env)
local player = env.player
local ReplicatedStorage = env.ReplicatedStorage or game:GetService("ReplicatedStorage")
local TextService = env.TextService
local UserInputService = env.UserInputService
local Workspace = env.Workspace

local RuntimeHelpers = env.RuntimeHelpers
local Dependencies = env.Dependencies
local ClassicLevels = env.ClassicLevels
local state = env.state
local ui = env.ui
local tiles = env.tiles
local remotes = env.remotes
local tileRenderStates = env.tileRenderStates
local dragLineVisualState = env.dragLineVisualState

local create = env.create
local destroyLineEntry = env.destroyLineEntry
local findDescendantByNames = env.findDescendantByNames
local findTextObject = env.findTextObject
local ensureScaleController = env.ensureScaleController
local tween = env.tween
local applyTextFont = env.applyTextFont
local cloneTable = env.cloneTable
local resolveModeStreakFromSnapshot = env.resolveModeStreakFromSnapshot
local playSound = env.playSound
local playAlertSound = env.playAlertSound
local ALERT_SFX_PROFILES = env.ALERT_SFX_PROFILES or {}
local COLORS = env.COLORS
local WORD_LINE_COLORS = env.WORD_LINE_COLORS
local ALERT_TOAST_COLORS = env.ALERT_TOAST_COLORS
local DEFAULT_WORD_ROW_COLOR = env.DEFAULT_WORD_ROW_COLOR
local DEFAULT_WORD_ROW_TRANSPARENCY = env.DEFAULT_WORD_ROW_TRANSPARENCY
local INACTIVE_WORD_ROW_COLOR = env.INACTIVE_WORD_ROW_COLOR
local WORD_LIST_TEXT_SIZE = env.WORD_LIST_TEXT_SIZE
local WORD_LIST_HORIZONTAL_GAP = env.WORD_LIST_HORIZONTAL_GAP
local WORD_LIST_VERTICAL_GAP = env.WORD_LIST_VERTICAL_GAP
local WORD_LIST_PADDING_X = env.WORD_LIST_PADDING_X
local WORD_LIST_PADDING_Y = env.WORD_LIST_PADDING_Y
local WORD_LIST_MIN_TEXT_SIZE = env.WORD_LIST_MIN_TEXT_SIZE
local WORD_LIST_MAX_TEXT_SIZE = env.WORD_LIST_MAX_TEXT_SIZE
local WORD_LIST_FOUND_COLOR = env.WORD_LIST_FOUND_COLOR
local WORD_LIST_PENDING_COLOR = env.WORD_LIST_PENDING_COLOR
local WORD_LIST_HINT_COLOR = env.WORD_LIST_HINT_COLOR
local WORD_LIST_PENDING_SCALE = env.WORD_LIST_PENDING_SCALE
local WORD_LIST_FOUND_SCALE = env.WORD_LIST_FOUND_SCALE
local BOARD_STROKE_VISIBLE_TRANSPARENCY = env.BOARD_STROKE_VISIBLE_TRANSPARENCY
local BOARD_STROKE_HIDDEN_TRANSPARENCY = env.BOARD_STROKE_HIDDEN_TRANSPARENCY
local MODES = env.MODES
local LAYOUT = env.LAYOUT
local ANIMATION = env.ANIMATION
local DIRECTIONS = env.DIRECTIONS
local FOG_REVEAL_RADIUS = env.FOG_REVEAL_RADIUS
local FAST_TILE_REFRESH_GRID_SIZE = env.FAST_TILE_REFRESH_GRID_SIZE
local HINT_TILE_PULSE_SPEED = env.HINT_TILE_PULSE_SPEED
local HINT_TILE_PULSE_MIN_TRANSPARENCY = env.HINT_TILE_PULSE_MIN_TRANSPARENCY
local HINT_TILE_PULSE_MAX_TRANSPARENCY = env.HINT_TILE_PULSE_MAX_TRANSPARENCY

local getModeConfig = env.getModeConfig
local getDailyModeInfo = env.getDailyModeInfo
local hasCompletedDailyToday = env.hasCompletedDailyToday
local getSnapshot = env.getSnapshot
local applySnapshot = env.applySnapshot
local trackServerAction = env.trackServerAction
local trackFunnelStep = env.trackFunnelStep
local applyLocalAction = env.applyLocalAction
local nextSeed = env.nextSeed
local showMenuView = env.showMenuView
local showGameView = env.showGameView
local setSelectedMenuMode = env.setSelectedMenuMode
local getSelectedMenuModeName = env.getSelectedMenuModeName
local getModeUnlockWins = env.getModeUnlockWins
local isModeUnlocked = env.isModeUnlocked
local isInteractionBlocked = env.isInteractionBlocked
local isGameplayInteractionBlocked = env.isGameplayInteractionBlocked
local getDragBlockReason = env.getDragBlockReason
local isGameViewDisplayed = env.isGameViewDisplayed
local refreshModeButtons = env.refreshModeButtons
local refreshActionButtons = env.refreshActionButtons
local refreshUiBindings = env.refreshUiBindings
local waitForRemote = env.waitForRemote
local syncBoardContentLayout = env.syncBoardContentLayout
local setBoardVisualTransparency = env.setBoardVisualTransparency
local tweenBoardVisualTransparency = env.tweenBoardVisualTransparency
local getFogRevealAnchors = env.getFogRevealAnchors
local isFogTileVisible = env.isFogTileVisible

local function showSummary(...)
	return env.showSummary(...)
end

local function hideSummary(...)
	return env.hideSummary(...)
end

local function enterSelectedMode(...)
	return env.enterSelectedMode(...)
end

local function showClassicLevelsFrame(...)
	return env.showClassicLevelsFrame(...)
end

local function hideClassicLevelsFrame(...)
	return env.hideClassicLevelsFrame(...)
end

local ButtonUi = setmetatable({}, {
	__index = function(_, key)
		local resolved = env.getButtonUi and env.getButtonUi() or nil
		return resolved and resolved[key] or nil
	end,
})

local chooseModeLevelIndex
local buildPuzzleDefinition
local ensureTileVisuals
local cellKey
local currentSelection
local countFoundWords
local countHintedWords
local updateWordsLabel
local updateHud
local pulseScale
local clearDrag
local resetWordListUi
local showDesktopAlert
local syncBoardProgress
local transitionToPuzzle
local loadPreparedPuzzle
local performPuzzleLoad
local startMode
local handleMenuPlayPressed
local startClassicLevelFromSelector

local function chooseModeLevelIndex(mode)
	if mode == "Classic" then
		return math.clamp(state.puzzleIndex, 1, #Dependencies.Levels)
	end

	if mode == "Daily" then
		return getDailyModeInfo().level
	end

	local progress = state.puzzlesCleared
	local baseIndex
	local spread

	if mode == "Themed" then
		baseIndex = math.clamp(2 + math.floor(progress * 0.8), 1, #Dependencies.Levels)
		spread = 3
	elseif mode == "Backwards" then
		baseIndex = math.clamp(4 + math.floor(progress * 0.95), 3, #Dependencies.Levels)
		spread = 3
	elseif mode == "Fog" then
		baseIndex = math.clamp(6 + math.floor(progress * 1.22), 4, #Dependencies.Levels)
		spread = 2
	elseif mode == "OneLife" then
		baseIndex = math.clamp(6 + math.floor(progress * 1.3) + math.floor(math.max(progress - 2, 0) * 0.25), 5, #Dependencies.Levels)
		spread = 2
	elseif mode == "Mega" then
		baseIndex = math.clamp(8 + math.floor(progress * 1.85) + math.floor(math.max(progress - 1, 0) * 0.55), 6, #Dependencies.Levels)
		spread = 2
	else
		baseIndex = math.clamp(3 + math.floor(progress * 0.85), 1, #Dependencies.Levels)
		spread = 3
	end

	local low = math.max(1, baseIndex - spread)
	local high = math.min(#Dependencies.Levels, baseIndex + 2)
	local randomObject = Random.new(nextSeed(baseIndex + progress * 17 + #mode))
	local chosenIndex = randomObject:NextInteger(low, high)

	if chosenIndex == state.puzzleIndex and high > low then
		chosenIndex = chosenIndex == high and low or (chosenIndex + 1)
	end

	return chosenIndex
end

local function buildPuzzleDefinition(index, mode, seed)
	return Dependencies.DefinitionBuilder.BuildDefinition(index, mode, seed)
end

local function ensureTileVisuals(tile)
	local background = tile:FindFirstChild("CellBackground")
	if not background then
		background = create("Frame", {
			Name = "CellBackground",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = COLORS.tile,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = tile,
		})

		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = background,
		})
	end

	local hoverStroke = background:FindFirstChild("HoverStroke")
	if not hoverStroke then
		hoverStroke = create("UIStroke", {
			Name = "HoverStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = COLORS.tileHoverStroke,
			Thickness = 2,
			Transparency = 1,
			Parent = background,
		})
	end

	local letterLabel = tile:FindFirstChild("LetterLabel")
	if not letterLabel then
		letterLabel = create("TextLabel", {
			Name = "LetterLabel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			Text = "",
			TextColor3 = COLORS.tileText,
			TextScaled = true,
			ZIndex = 8,
			Parent = tile,
		})

		create("UITextSizeConstraint", {
			MaxTextSize = 256,
			MinTextSize = 12,
			Parent = letterLabel,
		})
	end

	applyTextFont(letterLabel, Enum.Font.GothamBold)

	local scaleController = tile:FindFirstChild("ScaleController")
	if not scaleController then
		scaleController = create("UIScale", {
			Name = "ScaleController",
			Scale = 1,
			Parent = tile,
		})
	end

	return background, letterLabel, scaleController, hoverStroke
end

local function getHintTilePulseTransparency()
	local alpha = (math.sin(tick() * HINT_TILE_PULSE_SPEED) + 1) * 0.5
	return HINT_TILE_PULSE_MIN_TRANSPARENCY
		+ ((HINT_TILE_PULSE_MAX_TRANSPARENCY - HINT_TILE_PULSE_MIN_TRANSPARENCY) * alpha)
end

cellKey = function(row, column)
	return string.format("%d:%d", row, column)
end

local function sign(value)
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	end

	return 0
end

local function getLineSequence(startRow, startColumn, endRow, endColumn)
	local rowDelta = endRow - startRow
	local columnDelta = endColumn - startColumn

	if rowDelta ~= 0 and columnDelta ~= 0 and math.abs(rowDelta) ~= math.abs(columnDelta) then
		return nil
	end

	local rowStep = sign(rowDelta)
	local columnStep = sign(columnDelta)
	local length = math.max(math.abs(rowDelta), math.abs(columnDelta)) + 1
	local points = {}

	for index = 0, length - 1 do
		points[index + 1] = {
			row = startRow + rowStep * index,
			column = startColumn + columnStep * index,
		}
	end

	return points
end

currentSelection = function()
	if not state.dragStart or not state.dragTarget then
		return nil
	end

	return getLineSequence(
		state.dragStart.row,
		state.dragStart.column,
		state.dragTarget.row,
		state.dragTarget.column
	)
end

local function pathMatches(selection, path)
	if #selection ~= #path then
		return false
	end

	local forwardMatch = true
	for index = 1, #selection do
		local left = selection[index]
		local right = path[index]
		if left.row ~= right.row or left.column ~= right.column then
			forwardMatch = false
			break
		end
	end

	if forwardMatch then
		return true
	end

	for index = 1, #selection do
		local left = selection[index]
		local right = path[#path - index + 1]
		if left.row ~= right.row or left.column ~= right.column then
			return false
		end
	end

	return true
end

local function setStatus(text, color)
	return
end

local function getWordColor(word)
	return state.wordColors[word] or COLORS.foundLine
end

local function assignWordColors()
	state.wordColors = {}

	for index, word in ipairs(state.currentPuzzle.words) do
		state.wordColors[word] = WORD_LINE_COLORS[((index - 1) % #WORD_LINE_COLORS) + 1]
	end
end

countFoundWords = function()
	local foundCount = 0

	if not state.currentPuzzle then
		return foundCount
	end

	for _, word in ipairs(state.currentPuzzle.words) do
		if state.foundWords[word] then
			foundCount += 1
		end
	end

	return foundCount
end

countHintedWords = function()
	local hintedCount = 0

	if not state.currentPuzzle then
		return hintedCount
	end

	for _, word in ipairs(state.currentPuzzle.words) do
		if state.hintedWords[word] then
			hintedCount += 1
		end
	end

	return hintedCount
end

local function autoScrollWordListToRemainingWord()
	local scroll = ui.wordListScroll
	if not (scroll and scroll:IsA("ScrollingFrame") and state.currentPuzzle and type(ui.wordRows) == "table") then
		return
	end

	local firstRemainingRow = nil
	local firstRemainingIndex = nil

	for index, word in ipairs(state.currentPuzzle.words) do
		if state.foundWords[word] ~= true then
			local rowData = ui.wordRows[word]
			if rowData and rowData.row and rowData.row.Parent == scroll then
				firstRemainingRow = rowData.row
				firstRemainingIndex = index
				break
			end
		end
	end

	if not firstRemainingRow then
		return
	end

	local viewportHeight = scroll.AbsoluteSize.Y
	local canvasHeight = scroll.AbsoluteCanvasSize.Y
	if viewportHeight <= 0 or canvasHeight <= viewportHeight then
		return
	end

	local currentY = scroll.CanvasPosition.Y
	local rowTop = firstRemainingRow.AbsolutePosition.Y - scroll.AbsolutePosition.Y + currentY
	local rowBottom = rowTop + firstRemainingRow.AbsoluteSize.Y
	local preferredOffset = math.floor(viewportHeight * 0.22)
	local targetY = math.max(0, math.min(canvasHeight - viewportHeight, rowTop - preferredOffset))
	local completedBefore = math.max(0, (firstRemainingIndex or 1) - 1)
	local shouldScroll = completedBefore >= 2 and math.abs(targetY - currentY) > 6

	if rowTop < currentY + 8 or rowBottom > currentY + viewportHeight - 12 then
		shouldScroll = math.abs(targetY - currentY) > 4
	end

	if not shouldScroll then
		return
	end

	if ui.wordListScrollTween then
		ui.wordListScrollTween:Cancel()
		ui.wordListScrollTween = nil
	end

	ui.wordListScrollTween = tween(scroll, {
		CanvasPosition = Vector2.new(scroll.CanvasPosition.X, targetY),
	}, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
end

local function addScore(amount)
	if amount <= 0 then
		return
	end

	state.sessionScore += amount

	if ui.scoreChipScale then
		pulseScale(ui.scoreChipScale, 1.08, 1, 0)
	end

	if updateHud then
		updateHud()
	end
end

local function createFallbackWordRow(word)
	local row = create("TextLabel", {
		Name = "WordRow_" .. word,
		AnchorPoint = Vector2.new(0, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 0, 0, 0),
		Text = RuntimeHelpers.getWordListDisplayText(word),
		TextColor3 = WORD_LIST_PENDING_COLOR,
		TextSize = WORD_LIST_TEXT_SIZE,
		TextTransparency = 0.06,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = ui.wordListScroll,
	})
	applyTextFont(row, Enum.Font.GothamBold)

	return row, row, nil
end

local function createWordRowData(word, layoutOrder)
	local row, label, dot = createFallbackWordRow(word)

	if label then
		label.Text = RuntimeHelpers.getWordListDisplayText(word)
		if label:IsA("TextLabel") or label:IsA("TextButton") then
			applyTextFont(label, Enum.Font.GothamBold)
		end
	end

	local scaleController = ensureScaleController(row)
	row.LayoutOrder = layoutOrder or 1

	return {
		row = row,
		dot = dot,
		label = label,
		strike = nil,
		scale = scaleController,
		baseLabelPosition = label and label.Position or nil,
		baseDotPosition = dot and dot.Position or nil,
		baseStrikePosition = nil,
	}
end

local function measureWordRowLabel(text, textSize, isTouchLayout)
	local resolvedTextSize = textSize or WORD_LIST_TEXT_SIZE
	local textBounds = TextService:GetTextSize(
		tostring(text or ""),
		resolvedTextSize,
		Enum.Font.GothamBold,
		Vector2.new(2000, 200)
	)

	local horizontalPadding = math.max(
		isTouchLayout and 10 or 8,
		math.floor(resolvedTextSize * (isTouchLayout and 0.52 or 0.42))
	)
	local verticalPadding = math.max(
		isTouchLayout and 4 or 3,
		math.floor(resolvedTextSize * (isTouchLayout and 0.18 or 0.15))
	)
	return math.max(24, textBounds.X + horizontalPadding), math.max(20, textBounds.Y + verticalPadding)
end

local function layoutWordLabels()
	if not (ui.wordListScroll and ui.wordListScroll:IsA("GuiObject") and state.currentPuzzle and type(ui.wordRows) == "table") then
		return
	end

	local words = state.currentPuzzle.words
	local wordCount = #words
	if wordCount <= 0 then
		return
	end

	local isTouchLayout = UserInputService and UserInputService.TouchEnabled == true and UserInputService.KeyboardEnabled ~= true
	local containerWidth = math.max(120, ui.wordListScroll.AbsoluteSize.X)
	local containerHeight = math.max(40, ui.wordListScroll.AbsoluteSize.Y)
	local horizontalPadding = math.max(6, math.floor(math.max(WORD_LIST_PADDING_X * 0.85, containerWidth * (isTouchLayout and 0.026 or 0.032))))
	local verticalPadding = math.max(3, math.floor(math.max(WORD_LIST_PADDING_Y * 0.7, containerHeight * (isTouchLayout and 0.05 or 0.075))))
	local availableWidth = math.max(60, containerWidth - (horizontalPadding * 2))
	local availableHeight = math.max(28, containerHeight - (verticalPadding * 2))
	local hardMinimumTextSize = isTouchLayout and 10 or 11
	local preferredMinimumTextSize = math.max(
		hardMinimumTextSize,
		WORD_LIST_MIN_TEXT_SIZE
			- (wordCount >= 24 and 6 or (wordCount >= 18 and 4 or (wordCount >= 14 and 2 or 0)))
	)
	local dynamicAreaSize = math.floor(math.sqrt((availableWidth * availableHeight) / math.max(1, wordCount)) * (isTouchLayout and 0.44 or 0.48))
	local maxCandidateSize = math.max(
		preferredMinimumTextSize,
		math.min(
			WORD_LIST_MAX_TEXT_SIZE,
			math.max(dynamicAreaSize, math.floor(containerHeight * (isTouchLayout and 0.22 or 0.27)))
		)
	)
	local bestFitLayout = nil
	local bestFitScore = -math.huge
	local bestOverflowLayout = nil
	local bestOverflowScore = -math.huge

	for candidateSize = maxCandidateSize, hardMinimumTextSize, -1 do
		local horizontalGap = math.max(
			isTouchLayout and 10 or 8,
			math.floor(math.max(WORD_LIST_HORIZONTAL_GAP * (isTouchLayout and 0.52 or 0.7), candidateSize * (isTouchLayout and 0.3 or 0.26)))
		)
		local verticalGap = math.max(
			isTouchLayout and 7 or 5,
			math.floor(math.max(WORD_LIST_VERTICAL_GAP * (isTouchLayout and 0.75 or 0.85), candidateSize * (isTouchLayout and 0.22 or 0.18)))
		)
		local wordMetrics = {}
		for _, word in ipairs(words) do
			local rowData = ui.wordRows[word]
			local label = rowData and rowData.label
			if not label then
				continue
			end

			local width, height = measureWordRowLabel(label.Text, candidateSize, isTouchLayout)
			wordMetrics[word] = {
				width = width,
				height = height,
			}
		end

		local rows = {}
		local currentRow = {
			items = {},
			width = 0,
			height = 0,
		}

		for _, word in ipairs(words) do
			local metrics = wordMetrics[word]
			if metrics then
				local projectedWidth = metrics.width
				if #currentRow.items > 0 then
					projectedWidth += currentRow.width + horizontalGap
				end

				if #currentRow.items > 0 and projectedWidth > availableWidth then
					table.insert(rows, currentRow)
					currentRow = {
						items = {},
						width = 0,
						height = 0,
					}
					projectedWidth = metrics.width
				end

				table.insert(currentRow.items, {
					word = word,
					width = metrics.width,
					height = metrics.height,
				})
				currentRow.width = projectedWidth
				currentRow.height = math.max(currentRow.height, metrics.height)
			end
		end

		if #currentRow.items > 0 then
			table.insert(rows, currentRow)
		end

		local totalHeight = 0
		local widestRow = 0
		for rowIndex, row in ipairs(rows) do
			if rowIndex > 1 then
				totalHeight += verticalGap
			end
			totalHeight += row.height
			widestRow = math.max(widestRow, row.width)
		end

		if #rows > 0 then
			local overflow = math.max(0, totalHeight - availableHeight)
			local fillX = math.clamp(widestRow / availableWidth, 0, 1)
			local fillY = math.clamp(math.min(totalHeight, availableHeight) / availableHeight, 0, 1)
			local targetRowFill = isTouchLayout and 0.82 or 0.87
			local fillScore = math.max(0, 1 - math.abs(fillX - targetRowFill) * 2.2)
			local rowBalanceScore = 0
			local rowTightnessPenalty = 0
			for _, row in ipairs(rows) do
				local rowFill = math.clamp(row.width / availableWidth, 0, 1)
				if #row.items > 1 then
					rowBalanceScore += math.max(0, 1 - math.abs(rowFill - targetRowFill) * 2.4)
					rowTightnessPenalty += math.max(0, rowFill - (isTouchLayout and 0.9 or 0.94)) * 42
				else
					rowBalanceScore += 0.4
				end
			end
			rowBalanceScore = rowBalanceScore / math.max(1, #rows)
			local score = (candidateSize * 4.9)
				+ (fillScore * 12)
				+ (rowBalanceScore * 18)
				+ (fillY * 12)
				- (#rows * 1.2)
				- rowTightnessPenalty
				- (overflow * 0.42)
			local layout = {
				textSize = candidateSize,
				horizontalGap = horizontalGap,
				verticalGap = verticalGap,
				horizontalPadding = horizontalPadding,
				verticalPadding = verticalPadding,
				rows = rows,
				totalHeight = totalHeight,
				widestRow = widestRow,
				overflow = overflow,
			}

			if overflow <= 0 then
				score += 60
				if score > bestFitScore then
					bestFitScore = score
					bestFitLayout = layout
				end
			elseif score > bestOverflowScore then
				bestOverflowScore = score
				bestOverflowLayout = layout
			end
		end
	end

	local bestLayout = bestFitLayout or bestOverflowLayout
	if not bestLayout then
		bestLayout = {
			textSize = preferredMinimumTextSize,
			horizontalGap = math.max(
				isTouchLayout and 10 or 8,
				math.floor(math.max(WORD_LIST_HORIZONTAL_GAP * (isTouchLayout and 0.52 or 0.7), preferredMinimumTextSize * (isTouchLayout and 0.3 or 0.26)))
			),
			verticalGap = math.max(
				isTouchLayout and 7 or 5,
				math.floor(math.max(WORD_LIST_VERTICAL_GAP * (isTouchLayout and 0.75 or 0.85), preferredMinimumTextSize * (isTouchLayout and 0.22 or 0.18)))
			),
			horizontalPadding = horizontalPadding,
			verticalPadding = verticalPadding,
			rows = {},
			totalHeight = 0,
			widestRow = 0,
			overflow = 0,
		}
	end

	local contentHeight = bestLayout.totalHeight + (bestLayout.verticalPadding * 2)
	local currentY = bestLayout.verticalPadding
	if bestLayout.totalHeight < availableHeight then
		currentY += math.floor((availableHeight - bestLayout.totalHeight) * 0.5)
	end

	for _, row in ipairs(bestLayout.rows) do
		local currentX = bestLayout.horizontalPadding
		local extraGap = 0
		if row.width < availableWidth then
			local slackWidth = availableWidth - row.width
			if #row.items > 1 then
				local maxExtraGap = math.max(0, math.floor(bestLayout.textSize * (isTouchLayout and 0.45 or 0.32)))
				extraGap = math.min(maxExtraGap, math.floor(slackWidth / (#row.items - 1)))
				currentX += math.floor((slackWidth - (extraGap * (#row.items - 1))) * 0.5)
			else
				currentX += math.floor(slackWidth * 0.5)
			end
		end

		for itemIndex, item in ipairs(row.items) do
			local rowData = ui.wordRows[item.word]
			local label = rowData and rowData.label
			if label then
				label.TextSize = bestLayout.textSize
				label.AnchorPoint = Vector2.new(0, 0)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Center
				label.Position = UDim2.new(0, currentX, 0, currentY + math.floor((row.height - item.height) * 0.5))
				label.Size = UDim2.new(0, item.width, 0, item.height)
				rowData.baseLabelPosition = label.Position
			end
			currentX += item.width
			if itemIndex < #row.items then
				currentX += bestLayout.horizontalGap + extraGap
			end
		end

		currentY += row.height + bestLayout.verticalGap
	end

	if ui.wordListScroll:IsA("ScrollingFrame") then
		local shouldScroll = (bestLayout.overflow or 0) > 0
		ui.wordListScroll.ScrollingEnabled = shouldScroll
		ui.wordListScroll.CanvasSize = UDim2.new(0, 0, 0, shouldScroll and math.max(containerHeight, contentHeight) or containerHeight)
	end
end

updateWordsLabel = function()
	if ui.wordPanel and ui.wordPanel:IsA("GuiObject") then
		ui.wordPanel.Visible = true
	end
	if ui.wordListScroll and ui.wordListScroll:IsA("GuiObject") then
		ui.wordListScroll.Visible = state.wordRowsRevealPending ~= true
	end
	if ui.wordPanelTitleLabel and ui.wordPanelTitleLabel:IsA("GuiObject") then
		ui.wordPanelTitleLabel.Visible = true
	end
	if ui.wordPanelCountLabel and ui.wordPanelCountLabel:IsA("GuiObject") then
		ui.wordPanelCountLabel.Visible = state.wordRowsRevealPending ~= true
	end
	if ui.progressLabel and ui.progressLabel:IsA("GuiObject") then
		ui.progressLabel.Visible = true
	end
	if ui.subtitleLabel and ui.subtitleLabel:IsA("GuiObject") then
		ui.subtitleLabel.Visible = true
	end
	if ui.progressCounterLabel and ui.progressCounterLabel:IsA("GuiObject") then
		ui.progressCounterLabel.Visible = true
	end

	if not state.currentPuzzle then
		if ui.wordListScrollTween then
			ui.wordListScrollTween:Cancel()
			ui.wordListScrollTween = nil
		end
		if ui.progressLabel then
			ui.progressLabel.Text = ""
		end
		if ui.subtitleLabel then
			ui.subtitleLabel.Text = ""
		end
		if ui.progressCounterLabel then
			ui.progressCounterLabel.Text = ""
		end
		if ui.wordPanelCountLabel then
			ui.wordPanelCountLabel.Text = ""
		end
		if ui.wordListScroll and ui.wordListScroll:IsA("ScrollingFrame") then
			ui.wordListScroll.CanvasPosition = Vector2.new(0, 0)
		end
		return
	end

	if state.wordRowsRevealPending then
		resetWordListUi()
	end

	if state.wordRowsRevealPending ~= true and ui.wordRowsToken ~= state.boardToken then
		ui.wordRowsToken = state.boardToken
		ui.wordRows = {}

		if ui.wordListScroll then
			if ui.wordListScrollTween then
				ui.wordListScrollTween:Cancel()
				ui.wordListScrollTween = nil
			end
			if ui.wordListScroll:IsA("ScrollingFrame") then
				ui.wordListScroll.CanvasPosition = Vector2.new(0, 0)
			end
			for _, child in ipairs(ui.wordListScroll:GetChildren()) do
				if child:IsA("GuiObject") and string.sub(child.Name, 1, 8) == "WordRow_" then
					child:Destroy()
				end
			end

			for index, word in ipairs(state.currentPuzzle.words) do
				ui.wordRows[word] = createWordRowData(word, index)
			end
		end
	end
	layoutWordLabels()

	if ui.progressLabel then
		ui.progressLabel.Text = string.upper(state.currentPuzzle.title or "Word Search")
	end
	if ui.subtitleLabel then
		ui.subtitleLabel.Text = RuntimeHelpers.getPuzzleSubtitleText()
	end
	if ui.progressCounterLabel then
		ui.progressCounterLabel.Text = string.format("%d / %d WORDS", countFoundWords(), #state.currentPuzzle.words)
	end

	if ui.wordPanelCountLabel then
		ui.wordPanelCountLabel.Text = state.wordRowsRevealPending and "" or string.format("%d / %d FOUND", countFoundWords(), #state.currentPuzzle.words)
	end

	if state.wordRowsRevealPending then
		return
	end

	for _, word in ipairs(state.currentPuzzle.words) do
		local rowData = ui.wordRows and ui.wordRows[word]
		local found = state.foundWords[word] == true

		if rowData then
			local wasFound = rowData.row:GetAttribute("FoundState") == true
			local hinted = state.hintedWords[word] == true
			rowData.row:SetAttribute("FoundState", found)
			if rowData.label then
				rowData.label.Text = RuntimeHelpers.getWordListDisplayText(word)
				rowData.label.TextColor3 = found and WORD_LIST_FOUND_COLOR or (hinted and WORD_LIST_HINT_COLOR or WORD_LIST_PENDING_COLOR)
				rowData.label.TextTransparency = found and 0.7 or 0
			end

			if found then
				if rowData.scale and rowData.scale.Parent then
					rowData.scale.Scale = WORD_LIST_FOUND_SCALE
				end
				if not wasFound then
					pulseScale(rowData.scale, 1.06, 1, 0)
				end
			else
				if rowData.scale and rowData.scale.Parent then
					rowData.scale.Scale = WORD_LIST_PENDING_SCALE
				end
			end
		end
	end

	autoScrollWordListToRemainingWord()
end

function RuntimeHelpers.updateCountdownLetterScatter(active, shuffleStep)
	local shouldScramble = active == true
	if not state.currentPuzzle then
		return
	end

	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	local alphabetLength = #alphabet
	local tickBucket = math.max(0, math.floor(tonumber(shuffleStep) or (os.clock() * 12)))

	for row, rowTiles in pairs(tiles) do
		for column, tile in pairs(rowTiles) do
			if tile then
				local _, letterLabel = ensureTileVisuals(tile)
				local originalLetter = state.currentPuzzle.letters
					and state.currentPuzzle.letters[row]
					and state.currentPuzzle.letters[row][column]
					or ""

				if shouldScramble and originalLetter ~= "" then
					local randomIndex = ((tickBucket + (row * 7) + (column * 11)) % alphabetLength) + 1
					local randomLetter = string.sub(alphabet, randomIndex, randomIndex)
					if randomLetter == originalLetter then
						randomIndex = (randomIndex % alphabetLength) + 1
						randomLetter = string.sub(alphabet, randomIndex, randomIndex)
					end
					letterLabel.Text = randomLetter
				else
					letterLabel.Text = originalLetter
				end

				letterLabel.Position = UDim2.fromScale(0.5, 0.5)
				letterLabel.Rotation = 0
			end
		end
	end
end

updateHud = function()
	if not ui.screenGui then
		return
	end

	local modeConfig = getModeConfig()
	local levelNumber = state.currentPuzzle and (state.currentPuzzle.level or state.puzzleIndex) or state.puzzleIndex
	local secondaryText
	if state.duelActive then
		secondaryText = "FIRST TO CLEAR WINS"
	elseif state.mode == "Classic" then
		secondaryText = string.format("LEVEL %d / %d", levelNumber, #Dependencies.Levels)
	elseif state.mode == "Daily" then
		secondaryText = "25 X 25 DAILY"
	else
		secondaryText = string.format("BOARD %d", state.puzzlesCleared + 1)
	end

	if ui.modeChipLabel then
		ui.modeChipLabel.Text = string.upper(state.duelActive and "1V1" or modeConfig.label)
		ui.modeChip.BackgroundColor3 = modeConfig.accent
	end

	if ui.gameTitleLabel then
		ui.gameTitleLabel.Text = RuntimeHelpers.getGameplayTitle()
	end

	RuntimeHelpers.refreshDuelModeUi()

	if ui.secondaryChipLabel then
		ui.secondaryChipLabel.Text = secondaryText
		ui.secondaryChip.BackgroundColor3 = COLORS.chipSoft
	end

	if ui.scoreChipLabel then
		ui.scoreChipLabel.Text = string.format("SCORE %d", state.sessionScore)
	end

	if ui.rewardChipLabel then
		ui.rewardChipLabel.Text = string.format("WINS %d  /  STREAK %d", state.totalStars, state.streak)
	end

	if ui.streakRoot and ui.streakRoot:IsA("GuiObject") then
		ui.streakRoot.Visible = isGameViewDisplayed() and not state.duelActive
	end
	if ui.streakLabel then
		ui.streakLabel.Text = tostring(math.max(0, math.floor(tonumber(state.streak) or 0)))
	end

	if ui.progressCounterLabel and state.currentPuzzle then
		ui.progressCounterLabel.Text = string.format("%d / %d WORDS", countFoundWords(), #state.currentPuzzle.words)
	end

	if refreshModeButtons then
		refreshModeButtons()
	end

	if refreshActionButtons then
		refreshActionButtons()
	end
end

local function getTileCenter(row, column)
	local tile = tiles[row] and tiles[row][column]
	if not tile then
		return nil
	end

	local position = tile.AbsolutePosition
	local size = tile.AbsoluteSize
	return Vector2.new(position.X + size.X * 0.5, position.Y + size.Y * 0.5)
end

local function getBoardTileRoot()
	return ui.tileLayer or ui.puzzleGrid or ui.boardContent
end

local function getGridCellFromScreenPosition(position)
	local puzzle = state.currentPuzzle
	local gridSize = puzzle and math.max(1, math.floor(tonumber(puzzle.gridSize) or 1)) or 0
	local boardTileRoot = getBoardTileRoot()
	if gridSize <= 0 or not (boardTileRoot and boardTileRoot:IsA("GuiObject")) then
		return nil
	end

	local rootPosition = boardTileRoot.AbsolutePosition
	local rootSize = boardTileRoot.AbsoluteSize
	if rootSize.X <= 0 or rootSize.Y <= 0 then
		return nil
	end

	local localX = position.X - rootPosition.X
	local localY = position.Y - rootPosition.Y
	if localX < 0 or localY < 0 or localX > rootSize.X or localY > rootSize.Y then
		return nil
	end

	local column = math.clamp(math.floor((localX / rootSize.X) * gridSize) + 1, 1, gridSize)
	local row = math.clamp(math.floor((localY / rootSize.Y) * gridSize) + 1, 1, gridSize)
	if tiles[row] and tiles[row][column] then
		return {
			row = row,
			column = column,
		}
	end

	return nil
end

local function getPathThickness(path)
	if not path or #path == 0 then
		return 20
	end

	local tile = tiles[path[1].row] and tiles[path[1].row][path[1].column]
	if not tile then
		return 20
	end

	return math.max(18, math.floor(tile.AbsoluteSize.Y * 0.78))
end

local function toLineLayerPoint(screenPoint)
	local layerPosition = ui.lineLayer.AbsolutePosition
	return Vector2.new(screenPoint.X - layerPosition.X, screenPoint.Y - layerPosition.Y)
end

local function getTilePitch(row, column)
	local center = getTileCenter(row, column)
	local tile = tiles[row] and tiles[row][column]

	if not center or not tile then
		return 1, 1
	end

	local rightCenter = getTileCenter(row, column + 1) or getTileCenter(row, column - 1)
	local downCenter = getTileCenter(row + 1, column) or getTileCenter(row - 1, column)
	local xPitch = rightCenter and math.abs(rightCenter.X - center.X) or (tile.AbsoluteSize.X + 4)
	local yPitch = downCenter and math.abs(downCenter.Y - center.Y) or (tile.AbsoluteSize.Y + 4)

	return xPitch, yPitch
end

local function maxStepsInDirection(startRow, startColumn, rowStep, columnStep)
	local size = state.currentPuzzle.gridSize
	local maxSteps = math.huge

	if rowStep > 0 then
		maxSteps = math.min(maxSteps, size - startRow)
	elseif rowStep < 0 then
		maxSteps = math.min(maxSteps, startRow - 1)
	end

	if columnStep > 0 then
		maxSteps = math.min(maxSteps, size - startColumn)
	elseif columnStep < 0 then
		maxSteps = math.min(maxSteps, startColumn - 1)
	end

	if maxSteps == math.huge then
		return 0
	end

	return maxSteps
end

local function snapTargetFromPosition(position)
	if not state.dragStart then
		return nil
	end

	local startRow = state.dragStart.row
	local startColumn = state.dragStart.column
	local startCenter = getTileCenter(startRow, startColumn)

	if not startCenter then
		return state.dragStart
	end

	local hoveredTile = tileFromScreenPosition(position)
	if hoveredTile and getLineSequence(startRow, startColumn, hoveredTile.row, hoveredTile.column) then
		return hoveredTile
	end

	local xPitch, yPitch = getTilePitch(startRow, startColumn)
	local scaledX = (position.X - startCenter.X) / math.max(xPitch, 1)
	local scaledY = (position.Y - startCenter.Y) / math.max(yPitch, 1)
	local distance = math.max(math.abs(scaledX), math.abs(scaledY))

	if distance < 0.45 then
		return {
			row = startRow,
			column = startColumn,
		}
	end

	local directions = {
		{ -1, 0 },
		{ -1, 1 },
		{ 0, 1 },
		{ 1, 1 },
		{ 1, 0 },
		{ 1, -1 },
		{ 0, -1 },
		{ -1, -1 },
	}

	local bestTarget = {
		row = startRow,
		column = startColumn,
	}
	local bestScore = math.huge

	for _, direction in ipairs(directions) do
		local rowStep = direction[1]
		local columnStep = direction[2]

		if rowStep ~= 0 and sign(scaledY) ~= rowStep and math.abs(scaledY) > 0.35 then
			continue
		end

		if columnStep ~= 0 and sign(scaledX) ~= columnStep and math.abs(scaledX) > 0.35 then
			continue
		end

		local rawSteps
		local orthError

		if rowStep == 0 then
			rawSteps = math.abs(scaledX)
			orthError = math.abs(scaledY)
		elseif columnStep == 0 then
			rawSteps = math.abs(scaledY)
			orthError = math.abs(scaledX)
		else
			rawSteps = (math.abs(scaledX) + math.abs(scaledY)) * 0.5
			orthError = math.abs(math.abs(scaledX) - math.abs(scaledY))
		end

		local maxSteps = maxStepsInDirection(startRow, startColumn, rowStep, columnStep)
		local steps = math.clamp(math.floor(rawSteps + 0.5), 0, maxSteps)
		local score = orthError + math.abs(rawSteps - steps) * 0.35

		if score < bestScore then
			bestScore = score
			bestTarget = {
				row = startRow + rowStep * steps,
				column = startColumn + columnStep * steps,
			}
		end
	end

	return bestTarget
end

local function positionLineFromPoints(lineFrame, glowFrame, firstCenter, lastCenter, color, thickness, style)
	if not firstCenter or not lastCenter then
		lineFrame.Visible = false
		if glowFrame then
			glowFrame.Visible = false
		end
		return
	end

	local localFirst = toLineLayerPoint(firstCenter)
	local localLast = toLineLayerPoint(lastCenter)

	local delta = localLast - localFirst
	local midpoint = localFirst + delta * 0.5
	local rotation = math.deg(math.atan2(delta.Y, delta.X))
	local length = math.max(delta.Magnitude + thickness, thickness)
	local lineTransparency = style and style.lineTransparency or 0.08
	local glowTransparency = style and style.glowTransparency or 0.55
	local useTween = not (style and style.instant)
	local animationDuration = style and style.duration or 0.12
	local showGlow = glowFrame ~= nil and not (style and style.showGlow == false)

	lineFrame.Visible = true
	if useTween then
		tween(lineFrame, {
			BackgroundColor3 = color,
			BackgroundTransparency = lineTransparency,
			Position = UDim2.fromOffset(midpoint.X, midpoint.Y),
			Rotation = rotation,
			Size = UDim2.fromOffset(length, thickness),
		}, animationDuration)
	else
		lineFrame.BackgroundColor3 = color
		lineFrame.BackgroundTransparency = lineTransparency
		lineFrame.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
		lineFrame.Rotation = rotation
		lineFrame.Size = UDim2.fromOffset(length, thickness)
	end

	if showGlow then
		glowFrame.Visible = true
		if useTween then
			tween(glowFrame, {
				BackgroundColor3 = color,
				BackgroundTransparency = glowTransparency,
				Position = UDim2.fromOffset(midpoint.X, midpoint.Y),
				Rotation = rotation,
				Size = UDim2.fromOffset(length + 10, thickness + 10),
			}, animationDuration)
		else
			glowFrame.BackgroundColor3 = color
			glowFrame.BackgroundTransparency = glowTransparency
			glowFrame.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
			glowFrame.Rotation = rotation
			glowFrame.Size = UDim2.fromOffset(length + 10, thickness + 10)
		end
	elseif glowFrame then
		glowFrame.Visible = false
	end
end

local function getPathSignature(path)
	if not path or #path == 0 then
		return ""
	end

	local first = path[1]
	local last = path[#path]
	return string.format("%d:%d:%d:%d:%d", first.row, first.column, last.row, last.column, #path)
end

local function positionLine(lineFrame, glowFrame, path, color, thickness, style)
	if not path or #path < 1 then
		lineFrame.Visible = false
		if glowFrame then
			glowFrame.Visible = false
		end
		return
	end

	local first = path[1]
	local last = path[#path]
	local firstCenter = getTileCenter(first.row, first.column)
	local lastCenter = getTileCenter(last.row, last.column)

	positionLineFromPoints(lineFrame, glowFrame, firstCenter, lastCenter, color, thickness, style)
end

local function clearPersistentLines()
	for _, entry in pairs(ui.foundLineEntries or {}) do
		destroyLineEntry(entry)
	end

	ui.foundLineEntries = {}

	for _, entry in pairs(ui.hintLineEntries or {}) do
		destroyLineEntry(entry)
	end

	ui.hintLineEntries = {}
end

local function createRoundedLineFrame(parent, name, color, zIndex, transparency)
	local frame = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		ZIndex = zIndex,
		Parent = parent,
	})

	create("UICorner", {
		Name = name .. "Corner",
		CornerRadius = UDim.new(1, 0),
		Parent = frame,
	})

	create("UIScale", {
		Name = "ScaleController",
		Scale = 1,
		Parent = frame,
	})

	return frame
end

local function createPersistentLine(path, color, lineTransparency, glowTransparency, options)
	local glow = createRoundedLineFrame(ui.persistentLineLayer, "PersistentLineGlow", color, LAYOUT.PersistentLineGlowZIndex, glowTransparency or 0.55)
	local line = createRoundedLineFrame(ui.persistentLineLayer, "PersistentLine", color, LAYOUT.PersistentLineZIndex, lineTransparency or 0.2)
	local initialPath = path

	if options and options.collapsed and path and #path > 0 then
		initialPath = { path[1], path[1] }
	end

	positionLine(line, glow, initialPath, color, getPathThickness(path), {
		lineTransparency = lineTransparency,
		glowTransparency = glowTransparency,
		instant = true,
	})

	return {
		glow = glow,
		line = line,
		pathSignature = getPathSignature(path),
		animationToken = 0,
		flashToken = 0,
	}
end

local function createDragLineObjects()
	ui.dragGlow = createRoundedLineFrame(ui.lineLayer, "DragGlow", COLORS.dragLine, LAYOUT.DragGlowZIndex, 1)
	ui.dragLine = createRoundedLineFrame(ui.lineLayer, "DragLine", COLORS.dragLine, LAYOUT.DragLineZIndex, 1)
end

local function pulseLineFrame(lineFrame, peakScale, settleScale)
	if not lineFrame then
		return
	end

	local scaleController = lineFrame:FindFirstChild("ScaleController")
	if scaleController then
		pulseScale(scaleController, peakScale, settleScale, 0)
	end
end

local function startHintLineFlash(entry)
	if not entry or not entry.line or not entry.line.Parent then
		return
	end

	entry.flashToken = (entry.flashToken or 0) + 1
	local token = entry.flashToken

	task.spawn(function()
		local baseTransparency = LAYOUT.HintLineTransparency
		local hiddenTransparency = 1
		local baseGlowTransparency = 0.88
		local hiddenGlowTransparency = 1
		local showLine = false

		while entry.flashToken == token and entry.line and entry.line.Parent do
			local lineTransparency = showLine and baseTransparency or hiddenTransparency
			local glowTransparency = showLine and baseGlowTransparency or hiddenGlowTransparency

			tween(entry.line, { BackgroundTransparency = lineTransparency }, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))

			if entry.glow and entry.glow.Parent then
				tween(entry.glow, { BackgroundTransparency = glowTransparency }, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
			end

			showLine = not showLine
			task.wait(0.65)
		end
	end)
end

local function animateLineDraw(entry, path, color, lineTransparency, glowTransparency, duration)
	if not entry or not entry.line or not entry.line.Parent or not path or #path == 0 then
		return
	end

	local first = path[1]
	local last = path[#path]
	local firstCenter = getTileCenter(first.row, first.column)
	local lastCenter = getTileCenter(last.row, last.column)
	if not firstCenter or not lastCenter then
		return
	end

	entry.animationToken = (entry.animationToken or 0) + 1
	local token = entry.animationToken
	local driver = Instance.new("NumberValue")
	driver.Name = "LineDrawDriver"
	driver.Value = 0

	local connection
	local function applyProgress(alpha)
		if entry.animationToken ~= token or not entry.line or not entry.line.Parent then
			return
		end

		local currentEnd = firstCenter:Lerp(lastCenter, alpha)
		positionLineFromPoints(entry.line, entry.glow, firstCenter, currentEnd, color, getPathThickness(path), {
			lineTransparency = lineTransparency,
			glowTransparency = glowTransparency,
			instant = true,
		})
	end

	applyProgress(0)
	connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
		applyProgress(driver.Value)
	end)

	local animation = tween(
		driver,
		{ Value = 1 },
		TweenInfo.new(duration or 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	)

	task.delay((duration or 0.24) + 0.04, function()
		if connection then
			connection:Disconnect()
		end

		if driver then
			driver:Destroy()
		end

		if entry.animationToken == token and entry.line and entry.line.Parent then
			positionLine(entry.line, entry.glow, path, color, getPathThickness(path), {
				lineTransparency = lineTransparency,
				glowTransparency = glowTransparency,
				instant = true,
			})
			pulseLineFrame(entry.line, 1.05, 1)
		end
	end)

	if animation == nil then
		if connection then
			connection:Disconnect()
		end
		driver:Destroy()
		positionLine(entry.line, entry.glow, path, color, getPathThickness(path), {
			lineTransparency = lineTransparency,
			glowTransparency = glowTransparency,
			instant = true,
		})
	end
end

local function refreshPersistentLines()
	ui.foundLineEntries = ui.foundLineEntries or {}
	ui.hintLineEntries = ui.hintLineEntries or {}

	local activeFoundWords = {}
	local activeHintWords = {}

	for _, placedWord in ipairs(state.currentPuzzle.placedWords) do
		if state.foundWords[placedWord.word] then
			activeFoundWords[placedWord.word] = true
			local lineColor = getWordColor(placedWord.word)

			if not ui.foundLineEntries[placedWord.word] then
		ui.foundLineEntries[placedWord.word] = createPersistentLine(placedWord.path, lineColor, LAYOUT.FoundLineTransparency, 0.92)
			else
				positionLine(
					ui.foundLineEntries[placedWord.word].line,
					ui.foundLineEntries[placedWord.word].glow,
					placedWord.path,
					lineColor,
					getPathThickness(placedWord.path),
					{
				lineTransparency = LAYOUT.FoundLineTransparency,
						glowTransparency = 0.92,
					}
				)
			end
		end
	end

	for word, entry in pairs(ui.foundLineEntries) do
		if not activeFoundWords[word] then
			destroyLineEntry(entry)
			ui.foundLineEntries[word] = nil
		end
	end

	for word in pairs(state.hintedWords) do
		if not state.foundWords[word] then
			local placedWord = state.currentPuzzle.placedWordsByWord[word]
			if placedWord and placedWord.path and #placedWord.path >= 2 then
				activeHintWords[word] = true
				local hintEntry = ui.hintLineEntries[word]
				local hintPathSignature = getPathSignature(placedWord.path)

				if not hintEntry then
		hintEntry = createPersistentLine(placedWord.path, COLORS.hintLine, LAYOUT.HintLineTransparency, 0.88, {
						collapsed = true,
					})
					hintEntry.pathSignature = ""
					ui.hintLineEntries[word] = hintEntry
				end

				if hintEntry.pathSignature ~= hintPathSignature then
					hintEntry.pathSignature = hintPathSignature
		animateLineDraw(hintEntry, placedWord.path, COLORS.hintLine, LAYOUT.HintLineTransparency, 0.88, 0.28)
					startHintLineFlash(hintEntry)
				else
					positionLine(hintEntry.line, hintEntry.glow, placedWord.path, COLORS.hintLine, getPathThickness(placedWord.path), {
				lineTransparency = LAYOUT.HintLineTransparency,
						glowTransparency = 0.88,
						duration = 0.12,
					})
					if hintEntry.line.BackgroundTransparency >= 0.95 then
						startHintLineFlash(hintEntry)
					end
				end
			end
		end
	end

	for word, entry in pairs(ui.hintLineEntries) do
		if not activeHintWords[word] then
			destroyLineEntry(entry)
			ui.hintLineEntries[word] = nil
		end
	end
end

function RuntimeHelpers.updateSmoothDragLine(deltaTime)
	local line = ui.dragLine
	if not (line and line.Parent) then
		return
	end

	if dragLineVisualState.holdVisible then
		return
	end

	if not state.dragging or not dragLineVisualState.active then
		line.Visible = false
		if ui.dragGlow then
			ui.dragGlow.Visible = false
		end
		if not state.dragging then
			dragLineVisualState.currentFirst = nil
			dragLineVisualState.currentLast = nil
		end
		return
	end

	local targetFirst = dragLineVisualState.targetFirst
	local targetLast = dragLineVisualState.targetLast
	if not (targetFirst and targetLast) then
		line.Visible = false
		if ui.dragGlow then
			ui.dragGlow.Visible = false
		end
		return
	end

	local alpha = 1 - math.exp(-math.max(0.016, tonumber(deltaTime) or (1 / 60)) * ANIMATION.DragFollowSharpness)
	if not dragLineVisualState.currentFirst or not dragLineVisualState.currentLast or not line.Visible then
		dragLineVisualState.currentFirst = targetFirst
		dragLineVisualState.currentLast = targetLast
	else
		dragLineVisualState.currentFirst = dragLineVisualState.currentFirst:Lerp(targetFirst, alpha)
		dragLineVisualState.currentLast = dragLineVisualState.currentLast:Lerp(targetLast, alpha)
	end

	positionLineFromPoints(
		line,
		ui.dragGlow,
		dragLineVisualState.currentFirst,
		dragLineVisualState.currentLast,
		dragLineVisualState.color or COLORS.dragLine,
		dragLineVisualState.thickness or 20,
		{
			instant = true,
			showGlow = true,
			lineTransparency = dragLineVisualState.lineTransparency or ANIMATION.DragLineTransparency,
			glowTransparency = dragLineVisualState.glowTransparency or ANIMATION.DragGlowTransparency,
		}
	)
end

local function selectionLookup()
	local lookup = {}
	local selection = currentSelection()

	if not selection then
		return lookup
	end

	for _, point in ipairs(selection) do
		lookup[cellKey(point.row, point.column)] = true
	end

	return lookup
end

local function getCellFromKey(key)
	local rowText, columnText = string.match(tostring(key or ""), "^(%d+):(%d+)$")
	local row = tonumber(rowText)
	local column = tonumber(columnText)
	if not row or not column then
		return nil, nil
	end

	return row, column
end

local findMatchedWord

local function refreshDragLine()
	local selection = currentSelection()
	local lineColor = COLORS.dragLine

	if selection and #selection >= 2 then
		local matchedWord = findMatchedWord(selection)
		if matchedWord then
			lineColor = getWordColor(matchedWord.word)
		end
	end

	if selection and #selection >= 2 then
		local first = selection[1]
		local last = selection[#selection]
		local firstCenter = getTileCenter(first.row, first.column)
		local lastCenter = getTileCenter(last.row, last.column)
		if firstCenter and lastCenter then
			dragLineVisualState.active = true
			dragLineVisualState.color = lineColor
			dragLineVisualState.thickness = getPathThickness(selection)
			dragLineVisualState.targetFirst = firstCenter
			dragLineVisualState.targetLast = lastCenter
			dragLineVisualState.lineTransparency = ANIMATION.DragLineTransparency
			dragLineVisualState.glowTransparency = ANIMATION.DragGlowTransparency
			RuntimeHelpers.updateSmoothDragLine(1 / 60)
			return
		end
	end

	dragLineVisualState.active = false
	dragLineVisualState.targetFirst = nil
	dragLineVisualState.targetLast = nil
	if ui.dragGlow then
		ui.dragGlow.Visible = false
	end
	if ui.dragLine then
		ui.dragLine.Visible = false
	end
end

local function refreshTileVisual(row, column, options)
	options = options or {}
	local rowTiles = tiles[row]
	local tile = rowTiles and rowTiles[column] or nil
	if not tile then
		return
	end

	local key = cellKey(row, column)
	local selected = options.selected or {}
	local fogAnchors = options.fogAnchors
	local useFastRefresh = options.useFastRefresh
	if useFastRefresh == nil then
		useFastRefresh = state.currentPuzzle and state.currentPuzzle.gridSize >= FAST_TILE_REFRESH_GRID_SIZE
	end
	local allowHoverStroke = options.allowHoverStroke
	if allowHoverStroke == nil then
		allowHoverStroke = not state.dragging
			and state.activeInput == nil
			and state.dragStart == nil
			and state.dragTarget == nil
	end
	local boardIntroAnimating = options.boardIntroAnimating == true

	local targetColor = COLORS.tile
	local targetBackgroundTransparency = 1
	local targetTextColor = COLORS.tileText
	local targetTextTransparency = isFogTileVisible(row, column, selected, fogAnchors) and 0 or 1
	local targetScale = 1
	local targetStrokeTransparency = 1
	local targetStrokeThickness = 1.5
	local targetTileZIndex = 4
	local background, letterLabel, scaleController, hoverStroke = ensureTileVisuals(tile)

	if state.foundCells[key] then
		targetColor = COLORS.tileFound
		targetTextColor = COLORS.tileTextOnLine
		targetTileZIndex = 5
	elseif selected[key] then
		targetTextColor = COLORS.tileTextOnLine
		targetTileZIndex = 12
	end

	if allowHoverStroke and state.hoveredCellKey == key then
		targetStrokeTransparency = 0.06
		targetStrokeThickness = 5
		targetTileZIndex = 13
	end

	if boardIntroAnimating then
		targetBackgroundTransparency = background.BackgroundTransparency
		targetTextTransparency = letterLabel.TextTransparency
		targetScale = scaleController.Scale
		if hoverStroke then
			targetStrokeTransparency = hoverStroke.Transparency
			targetStrokeThickness = hoverStroke.Thickness
		end
	end

	local lastState = tileRenderStates[tile]
	if useFastRefresh then
		if not lastState or lastState.tileZIndex ~= targetTileZIndex then
			tile.ZIndex = targetTileZIndex
			background.ZIndex = targetTileZIndex
			letterLabel.ZIndex = targetTileZIndex + 1
		end
		if not lastState or lastState.backgroundColor ~= targetColor then
			background.BackgroundColor3 = targetColor
		end
		if not lastState or lastState.backgroundTransparency ~= targetBackgroundTransparency then
			background.BackgroundTransparency = targetBackgroundTransparency
		end
		if not lastState or lastState.textColor ~= targetTextColor then
			letterLabel.TextColor3 = targetTextColor
		end
		if not lastState or lastState.textTransparency ~= targetTextTransparency then
			letterLabel.TextTransparency = targetTextTransparency
		end
		if not lastState or lastState.scale ~= targetScale then
			scaleController.Scale = targetScale
		end
		if hoverStroke then
			if not lastState or lastState.strokeTransparency ~= targetStrokeTransparency then
				hoverStroke.Transparency = targetStrokeTransparency
			end
			if not lastState or lastState.strokeThickness ~= targetStrokeThickness then
				hoverStroke.Thickness = targetStrokeThickness
			end
		end
	else
		tile.ZIndex = targetTileZIndex
		background.ZIndex = targetTileZIndex
		letterLabel.ZIndex = targetTileZIndex + 1

		tween(background, {
			BackgroundColor3 = targetColor,
			BackgroundTransparency = targetBackgroundTransparency,
		}, 0.08)
		tween(letterLabel, {
			TextColor3 = targetTextColor,
			TextTransparency = targetTextTransparency,
		}, 0.08)
		tween(scaleController, { Scale = targetScale }, 0.08)
		if hoverStroke then
			tween(hoverStroke, {
				Transparency = targetStrokeTransparency,
				Thickness = targetStrokeThickness,
			}, 0.08)
		end
	end

	tileRenderStates[tile] = {
		backgroundColor = targetColor,
		backgroundTransparency = targetBackgroundTransparency,
		textColor = targetTextColor,
		textTransparency = targetTextTransparency,
		scale = targetScale,
		strokeTransparency = targetStrokeTransparency,
		strokeThickness = targetStrokeThickness,
		tileZIndex = targetTileZIndex,
	}
end

local function refreshTileByKey(key)
	local row, column = getCellFromKey(key)
	if row and column then
		refreshTileVisual(row, column, {
			selected = {},
			fogAnchors = state.mode == "Fog" and getFogRevealAnchors() or nil,
			useFastRefresh = true,
			allowHoverStroke = true,
			boardIntroAnimating = state.boardIntroAnimating == true,
		})
	end
end

local function refreshSelectionDelta(previousSelection, nextSelection)
	if state.mode == "Fog" then
		RuntimeHelpers.refreshBoard()
		return
	end

	local selected = {}
	local dirty = {}
	for _, point in ipairs(nextSelection or {}) do
		local key = cellKey(point.row, point.column)
		selected[key] = true
		dirty[key] = point
	end
	for _, point in ipairs(previousSelection or {}) do
		dirty[cellKey(point.row, point.column)] = point
	end

	for _, point in pairs(dirty) do
		refreshTileVisual(point.row, point.column, {
			selected = selected,
			useFastRefresh = true,
			allowHoverStroke = false,
			boardIntroAnimating = state.boardIntroAnimating == true,
		})
	end

	refreshDragLine()
	if RuntimeHelpers.refreshBoardCursor then
		RuntimeHelpers.refreshBoardCursor()
	end
end

local function resetDragState()
	state.dragging = false
	state.activeInput = nil
	state.activeInputType = nil
	state.dragStart = nil
	state.dragStartPosition = nil
	state.dragCursorPosition = nil
	state.dragTarget = nil
	state.hoveredCellKey = nil
	state.lastDragSnapKey = nil
end

local function animateWrongSelection()
	if not ui.dragLine or not ui.dragLine.Parent then
		clearDrag()
		return
	end

	playSound("Error2")
	state.transitionBusy = true
	resetDragState()
	dragLineVisualState.holdVisible = true
	ui.dragGlow.Visible = false
	ui.dragLine.Visible = true
	ui.dragLine.BackgroundColor3 = COLORS.error
	ui.dragLine.BackgroundTransparency = 0.2
	pulseLineFrame(ui.dragLine, 1.04, 1)

	task.delay(0.1, function()
		if not ui.dragLine or not ui.dragLine.Parent then
			return
		end

		tween(ui.dragLine, { BackgroundTransparency = 1 }, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
		if ui.dragLine:FindFirstChild("ScaleController") then
			tween(ui.dragLine.ScaleController, { Scale = 0.96 }, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
		end

		task.delay(0.22, function()
			state.transitionBusy = false
			clearDrag()
		end)
	end)
end

local function keepCurrentDragLineAsFound(word, path)
	local line = ui.dragLine
	if not line or not line.Parent then
		return
	end

	dragLineVisualState.active = false
	dragLineVisualState.targetFirst = nil
	dragLineVisualState.targetLast = nil
	dragLineVisualState.currentFirst = nil
	dragLineVisualState.currentLast = nil
	line.Name = "PersistentFoundLine_" .. word
	line.Parent = ui.persistentLineLayer
		line.ZIndex = LAYOUT.PersistentLineZIndex
	line.BackgroundColor3 = getWordColor(word)
		line.BackgroundTransparency = LAYOUT.FoundLineTransparency
	line.Visible = true

	if ui.dragGlow then
		ui.dragGlow.Visible = false
		ui.dragGlow:Destroy()
	end

	positionLine(line, nil, path, getWordColor(word), getPathThickness(path), {
				lineTransparency = LAYOUT.FoundLineTransparency,
		instant = true,
		showGlow = false,
	})
	pulseLineFrame(line, 1.08, 1)

	ui.foundLineEntries[word] = {
		line = line,
		glow = nil,
	}

	createDragLineObjects()
	ui.dragGlow.Visible = false
	ui.dragLine.Visible = false
	resetDragState()
end

local function clearHint()
	state.hintCells = {}
	state.hintedWords = {}
end

local function rebuildHintCells()
	state.hintCells = {}

	for word in pairs(state.hintedWords) do
		if not state.foundWords[word] then
			local placedWord = state.currentPuzzle and state.currentPuzzle.placedWordsByWord[word]
			if placedWord then
				for _, point in ipairs(placedWord.path) do
					state.hintCells[cellKey(point.row, point.column)] = true
				end
			end
		end
	end
end

local function setHintWord(word)
	local placedWord = word and state.currentPuzzle.placedWordsByWord[word]
	if not placedWord or state.foundWords[word] then
		return false
	end

	state.hintedWords[word] = true
	rebuildHintCells()
	return true
end

local function clearHintWord(word)
	if not word then
		return
	end

	state.hintedWords[word] = nil
	rebuildHintCells()
end

local function nextHintTarget()
	local wordCount = #state.currentPuzzle.words
	if wordCount == 0 then
		return nil, nil
	end

	for offset = 1, wordCount do
		local index = ((state.hintCursorIndex + offset - 1) % wordCount) + 1
		local word = state.currentPuzzle.words[index]

		if not state.foundWords[word] and not state.hintedWords[word] then
			return index, word
		end
	end

	return nil, nil
end

local function collectMarkedWords(wordLookup)
	local words = {}
	if not state.currentPuzzle then
		return words
	end

	for _, word in ipairs(state.currentPuzzle.words) do
		if wordLookup[word] then
			table.insert(words, word)
		end
	end

	return words
end

local function applyResumeStateToCurrentPuzzle(boardState)
	if type(boardState) ~= "table" or not state.currentPuzzle then
		return
	end

	state.foundWords = {}
	state.foundCells = {}
	state.hintedWords = {}
	state.hintCells = {}
	state.hintCursorIndex = 0
	state.currentBoardHintUses = math.max(0, math.floor(tonumber(boardState.hintUses) or 0))

	for _, word in ipairs(boardState.foundWords or {}) do
		local placedWord = state.currentPuzzle.placedWordsByWord[word]
		if placedWord then
			state.foundWords[word] = true
			for _, point in ipairs(placedWord.path) do
				state.foundCells[cellKey(point.row, point.column)] = true
			end
		end
	end

	for _, word in ipairs(boardState.hintedWords or {}) do
		if not state.foundWords[word] and state.currentPuzzle.placedWordsByWord[word] then
			state.hintedWords[word] = true
		end
	end

	rebuildHintCells()

	for index, word in ipairs(state.currentPuzzle.words) do
		if state.hintedWords[word] then
			state.hintCursorIndex = index
		end
	end
end

pulseScale = function(scaleController, peakScale, settleScale, delayTime)
	task.delay(delayTime or 0, function()
		if not scaleController or not scaleController.Parent then
			return
		end

		tween(scaleController, { Scale = peakScale }, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))

		task.delay(0.22, function()
			if not scaleController or not scaleController.Parent then
				return
			end

			tween(scaleController, { Scale = settleScale }, TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		end)
	end)
end

showDesktopAlert = function(title, message, alertType, options)
	local template = ReplicatedStorage:FindFirstChild("AlertTemplate")
	local list = ui.alertsList
	if not (template and template:IsA("GuiObject") and list and list:IsA("GuiObject")) then
		return false
	end

	local toast = template:Clone()
	local toastLabel = toast:FindFirstChild("Label", true)
	local alertText = tostring(message or title or "Alert")
	local accent = (options and options.color) or ALERT_TOAST_COLORS[alertType or "info"] or ALERT_TOAST_COLORS.info
	local accentLift = 0.16
	local strokeLift = 0.32
	if alertType == "success" then
		accentLift = 0.08
		strokeLift = 0.2
	elseif alertType == "error" then
		accentLift = 0.1
		strokeLift = 0.22
	end
	local displayAccent = accent:Lerp(Color3.new(1, 1, 1), accentLift)
	local widthScale = 0.55

	if toastLabel and (toastLabel:IsA("TextLabel") or toastLabel:IsA("TextButton")) then
		toastLabel.Text = alertText
		local measureFont = toastLabel.Font
		if measureFont == Enum.Font.Unknown then
			measureFont = Enum.Font.GothamBold
		end
		local textBounds = TextService:GetTextSize(
			alertText,
			math.max(12, math.floor(toastLabel.TextSize > 0 and toastLabel.TextSize or 24)),
			measureFont,
			Vector2.new(1200, 200)
		)
		local baseWidth = math.max(1, list.AbsoluteSize.X)
		widthScale = math.clamp((textBounds.X + 72) / baseWidth, 0.55, 1)
		toastLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	if toast:IsA("GuiObject") then
		toast.Size = UDim2.new(widthScale, 0, toast.Size.Y.Scale, toast.Size.Y.Offset)
	end
	if toast:IsA("Frame") or toast:IsA("TextButton") or toast:IsA("TextLabel") then
		toast.BackgroundColor3 = displayAccent
	end
	for _, descendant in ipairs(toast:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			descendant.Color = displayAccent:Lerp(Color3.new(1, 1, 1), strokeLift)
		elseif descendant:IsA("Frame") and descendant.Name ~= "Label" then
			descendant.BackgroundColor3 = displayAccent
		end
	end

	if ui.alertsRoot and ui.alertsRoot:IsA("GuiObject") then
		ui.alertsRoot.Visible = true
	end

	toast.Visible = true
	toast.Parent = list

	playAlertSound(alertType, options)

	local originalPosition = toast.Position
	local originalTransparency = toast.BackgroundTransparency
	local toastScale = ensureScaleController(toast)
	toast.BackgroundTransparency = 1
	if toastLabel and (toastLabel:IsA("TextLabel") or toastLabel:IsA("TextButton")) then
		toastLabel.TextTransparency = 1
	end
	toast.Position = originalPosition - UDim2.fromScale(0.018, 0)
	toastScale.Scale = 0.96

	tween(toast, {
		BackgroundTransparency = originalTransparency,
		Position = originalPosition,
	}, ANIMATION.PopupIn)
	tween(toastScale, { Scale = 1 }, ANIMATION.PopupIn)
	if toastLabel and (toastLabel:IsA("TextLabel") or toastLabel:IsA("TextButton")) then
		tween(toastLabel, {
			TextTransparency = 0,
		}, ANIMATION.SoftFadeIn)
	end

	task.delay((options and options.duration) or 3.5, function()
		if not (toast and toast.Parent) then
			return
		end

		tween(toast, {
			BackgroundTransparency = 1,
			Position = originalPosition + UDim2.fromScale(0.018, 0),
		}, ANIMATION.PopupOut)
		tween(toastScale, { Scale = 0.97 }, ANIMATION.PopupOut)
		if toastLabel and (toastLabel:IsA("TextLabel") or toastLabel:IsA("TextButton")) then
			tween(toastLabel, {
				TextTransparency = 1,
			}, ANIMATION.SoftFadeOut)
		end

		task.delay(ANIMATION.PopupOut.Time + 0.02, function()
			if toast and toast.Parent then
				toast:Destroy()
			end
			if options and options.onOkay then
				options.onOkay()
			end
		end)
	end)

	return true
end

function RuntimeHelpers.calculateWordScore(word)
	return math.floor(#word * 20 * getModeConfig().wordMultiplier)
end

function RuntimeHelpers.calculatePuzzleBonus()
	if not state.currentPuzzle then
		return 0
	end

	local modeConfig = getModeConfig()
	local bonus = modeConfig.completionBonus + state.currentPuzzle.gridSize * 8 + #state.currentPuzzle.words * 22

	return math.floor(bonus)
end

RuntimeHelpers.completionToastTexts = {
	"Amazing",
	"Magnificent",
	"Great",
	"Excellent",
	"Brilliant",
	"Outstanding",
	"Superb",
	"Beautiful",
}
RuntimeHelpers.praiseBannerConfig = {
	imageId = "rbxassetid://106076395088562",
	texts = {
		"AWESOME!",
		"MAGNIFICENT!",
		"BRILLIANT!",
		"SUPERB!",
		"EXCELLENT!",
		"BEAUTIFUL!",
		"CLEAN!",
		"SMART!",
		"NICE!",
	},
	colors = {
		Color3.fromRGB(127, 88, 255),
		Color3.fromRGB(70, 178, 255),
		Color3.fromRGB(255, 104, 163),
		Color3.fromRGB(104, 231, 126),
		Color3.fromRGB(255, 205, 76),
		Color3.fromRGB(255, 132, 92),
	},
	random = Random.new(),
}

function RuntimeHelpers.getCompletionToastText()
	local indexSeed = math.max(
		1,
		math.floor(tonumber(state.seed) or 0) + math.floor(tonumber(state.puzzlesCleared) or 0) + math.floor(tonumber(state.sessionScore) or 0)
	)
	local completionToastTexts = RuntimeHelpers.completionToastTexts
	local listSize = #completionToastTexts
	return completionToastTexts[((indexSeed - 1) % listSize) + 1]
end

RuntimeHelpers.getPraiseBannerText = function()
	local praiseBannerConfig = RuntimeHelpers.praiseBannerConfig
	return praiseBannerConfig.texts[praiseBannerConfig.random:NextInteger(1, #praiseBannerConfig.texts)]
end

RuntimeHelpers.getPraiseBannerColor = function()
	local praiseBannerConfig = RuntimeHelpers.praiseBannerConfig
	return praiseBannerConfig.colors[praiseBannerConfig.random:NextInteger(1, #praiseBannerConfig.colors)]
end

function RuntimeHelpers.showRewardToast(text, color)
	local toastColor = color or ALERT_TOAST_COLORS.success
	local rewardToastRoot = ui.rewardToastRoot or ui.rewardToast
	local rewardToastLabel = ui.rewardToast
	local rewardSound = ALERT_SFX_PROFILES.reward
	if rewardToastRoot and rewardToastLabel and ui.rewardToastScale then
		playAlertSound("reward")
		local toastToken = (rewardToastRoot:GetAttribute("ToastToken") or 0) + 1
		rewardToastRoot:SetAttribute("ToastToken", toastToken)
		rewardToastLabel.Text = text
		if rewardToastLabel:IsA("GuiObject") then
			rewardToastLabel.Visible = true
		end
		if rewardToastRoot:IsA("GuiObject") then
			rewardToastRoot.BackgroundColor3 = toastColor
			rewardToastRoot.Visible = true
			rewardToastRoot.BackgroundTransparency = 0.08
			rewardToastRoot.Position = UDim2.fromScale(0.5, 0.835)
		end
		rewardToastLabel.TextTransparency = 1
		ui.rewardToastScale.Scale = 0.9

		if rewardToastRoot ~= rewardToastLabel and rewardToastRoot:IsA("GuiObject") then
			tween(rewardToastRoot, {
				Position = UDim2.fromScale(0.5, 0.815),
			}, ANIMATION.PopupIn)
		else
			tween(rewardToastLabel, {
				Position = UDim2.fromScale(0.5, 0.815),
			}, ANIMATION.PopupIn)
		end
		tween(rewardToastLabel, {
			TextTransparency = 0,
		}, ANIMATION.PopupIn)
		tween(ui.rewardToastScale, { Scale = 1 }, ANIMATION.PopupIn)

		task.delay(1.25, function()
			if not rewardToastRoot or rewardToastRoot:GetAttribute("ToastToken") ~= toastToken then
				return
			end

			if rewardToastRoot ~= rewardToastLabel and rewardToastRoot:IsA("GuiObject") then
				tween(rewardToastRoot, {
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.5, 0.795),
				}, ANIMATION.PopupOut)
			else
				tween(rewardToastLabel, {
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.5, 0.795),
				}, ANIMATION.PopupOut)
			end
			tween(rewardToastLabel, {
				TextTransparency = 1,
			}, ANIMATION.PopupOut)
			tween(ui.rewardToastScale, { Scale = 0.96 }, ANIMATION.PopupOut)

			task.delay(ANIMATION.PopupOut.Time + 0.02, function()
				if rewardToastRoot and rewardToastRoot:GetAttribute("ToastToken") == toastToken and rewardToastRoot:IsA("GuiObject") then
					rewardToastRoot.Visible = false
				elseif rewardToastLabel and rewardToastLabel:IsA("GuiObject") then
					rewardToastLabel.Visible = false
				end
			end)
		end)
		return
	end

	if showDesktopAlert(nil, text, "reward", {
		color = toastColor,
		soundName = rewardSound and rewardSound.name or "NotificationHigh",
		soundPitch = rewardSound and rewardSound.pitch or nil,
		soundVolumeScale = rewardSound and rewardSound.volumeScale or nil,
		duration = 3.5,
	}) then
		return
	end

	if not ui.rewardToast or not ui.rewardToastScale then
		return
	end

	playAlertSound("reward")
	local toastToken = (ui.rewardToast:GetAttribute("ToastToken") or 0) + 1
	ui.rewardToast:SetAttribute("ToastToken", toastToken)
	ui.rewardToast.Text = text
	ui.rewardToast.BackgroundColor3 = toastColor
	ui.rewardToast.Visible = true
	ui.rewardToast.BackgroundTransparency = 0.08
	ui.rewardToast.TextTransparency = 1
	ui.rewardToast.Position = UDim2.fromScale(0.5, 0.835)
	ui.rewardToastScale.Scale = 0.9

	tween(ui.rewardToast, {
		TextTransparency = 0,
		Position = UDim2.fromScale(0.5, 0.815),
	}, ANIMATION.PopupIn)
	tween(ui.rewardToastScale, { Scale = 1 }, ANIMATION.PopupIn)

	task.delay(1.25, function()
		if not ui.rewardToast or ui.rewardToast:GetAttribute("ToastToken") ~= toastToken then
			return
		end

		tween(ui.rewardToast, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.795),
		}, ANIMATION.PopupOut)
		tween(ui.rewardToastScale, { Scale = 0.96 }, ANIMATION.PopupOut)

		task.delay(ANIMATION.PopupOut.Time + 0.02, function()
			if ui.rewardToast then
				ui.rewardToast.Visible = false
			end
		end)
	end)
end

function RuntimeHelpers.showPraiseBanner(customText)
	local root = ui.praiseBannerRoot
	local image = ui.praiseBannerImage
	local label = ui.praiseBannerLabel
	local scaleController = ui.praiseBannerScale
	if not (root and image and label and scaleController) then
		return
	end

	local token = (root:GetAttribute("PraiseToken") or 0) + 1
	root:SetAttribute("PraiseToken", token)

	root.Visible = true
	root.Position = ui.praiseBannerStartPosition or root.Position
	image.Image = RuntimeHelpers.praiseBannerConfig.imageId
	image.ImageColor3 = RuntimeHelpers.getPraiseBannerColor()
	image.ImageTransparency = 1
	label.Text = tostring(customText or RuntimeHelpers.getPraiseBannerText())
	label.TextTransparency = 1
	scaleController.Scale = 0.86

	tween(root, {
		Position = ui.praiseBannerOpenPosition or root.Position,
	}, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	tween(image, {
		ImageTransparency = 0.04,
	}, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	tween(label, {
		TextTransparency = 0,
	}, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	tween(scaleController, { Scale = 1 }, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out))

	task.delay(1.56, function()
		if not (root and root.Parent) or root:GetAttribute("PraiseToken") ~= token then
			return
		end

		tween(root, {
			Position = ui.praiseBannerExitPosition or root.Position,
		}, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
		tween(image, {
			ImageTransparency = 1,
		}, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
		tween(label, {
			TextTransparency = 1,
		}, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
		tween(scaleController, { Scale = 0.94 }, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In))

		task.delay(0.24, function()
			if not (root and root.Parent) or root:GetAttribute("PraiseToken") ~= token then
				return
			end

			root.Visible = false
			root.Position = ui.praiseBannerStartPosition or root.Position
			scaleController.Scale = 1
		end)
	end)
end

function RuntimeHelpers.animateBoardEntrance()
	playSound("Appear")
	local accent = getModeConfig().accent or COLORS.buttonPrimary
	if ui.boardHolder and ui.boardHolder:IsA("GuiObject") then
		ui.boardHolder.BackgroundTransparency = 1
		ui.boardHolder.Rotation = -3
		tween(
			ui.boardHolder,
			{ BackgroundTransparency = 0 },
			TweenInfo.new(1.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		)
	end

	local flashParent = ui.boardContent or ui.boardHolder
	if flashParent then
		local flash = create("Frame", {
			Name = "BoardIntroFlash",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.52),
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.03, 1.03),
			ZIndex = 18,
			Parent = flashParent,
		})
		create("UICorner", {
			CornerRadius = UDim.new(0.08, 0),
			Parent = flash,
		})
		tween(flash, {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1.1, 1.1),
		}, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		task.delay(0.8, function()
			if flash and flash.Parent then
				flash:Destroy()
			end
		end)
	end

	setBoardVisualTransparency(1)
	tweenBoardVisualTransparency(0, TweenInfo.new(1.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	if ui.boardScaleController then
		ui.boardScaleController.Scale = 0.96
		tween(ui.boardScaleController, { Scale = 1.008 }, TweenInfo.new(0.92, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		task.delay(0.92, function()
			if ui.boardScaleController and ui.boardScaleController.Parent then
				tween(ui.boardScaleController, { Scale = 1 }, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
			end
		end)
	end

	if ui.boardHolder then
		tween(ui.boardHolder, { Rotation = 0 }, TweenInfo.new(1.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
	end
end

function RuntimeHelpers.clearBoard()
	if not ui.boardContent then
		return
	end

	state.boardIntroAnimating = false
	tiles = {}
	tileRenderStates = {}
	state.hoveredCellKey = nil

	for _, container in ipairs({ ui.tileLayer, ui.puzzleGrid, ui.boardContent }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("UIGridLayout") or string.sub(child.Name, 1, 5) == "Tile_" then
					child:Destroy()
				end
			end
		end
	end

	clearPersistentLines()
	if RuntimeHelpers.refreshBoardCursor then
		RuntimeHelpers.refreshBoardCursor()
	end
end

resetWordListUi = function()
	ui.wordRows = {}
	ui.wordRowsToken = 0

	if ui.wordListScroll then
		if ui.wordListScrollTween then
			ui.wordListScrollTween:Cancel()
			ui.wordListScrollTween = nil
		end
		if ui.wordListScroll:IsA("ScrollingFrame") then
			ui.wordListScroll.CanvasPosition = Vector2.new(0, 0)
		end

		for _, child in ipairs(ui.wordListScroll:GetChildren()) do
			if child:IsA("GuiObject") and string.sub(child.Name, 1, 8) == "WordRow_" then
				child:Destroy()
			end
		end
	end
end

function RuntimeHelpers.resetBoardRuntimeForFreshMode(modeName)
	local targetMode = MODES[modeName] and modeName or state.mode
	local targetModeConfig = getModeConfig(targetMode)
	local targetModeStreak = resolveModeStreakFromSnapshot(getSnapshot(), targetMode, 0)

	state.activeCountdownId += 1
	if ui.countdownFrame then
		ui.countdownFrame.Visible = false
	end
	if ui.praiseBannerRoot and ui.praiseBannerRoot:IsA("GuiObject") then
		ui.praiseBannerRoot.Visible = false
		ui.praiseBannerRoot.Position = ui.praiseBannerStartPosition or ui.praiseBannerRoot.Position
		ui.praiseBannerRoot:SetAttribute("PraiseToken", (ui.praiseBannerRoot:GetAttribute("PraiseToken") or 0) + 1)
	end
	if ui.praiseBannerScale then
		ui.praiseBannerScale.Scale = 1
	end

	clearDrag()
	clearHint()
	RuntimeHelpers.clearBoard()

	state.mode = targetMode
	state.puzzleIndex = targetMode == "Classic" and RuntimeHelpers.getClassicContinueLevel() or targetModeConfig.startIndex
	state.currentPuzzle = nil
	state.foundWords = {}
	state.foundCells = {}
	state.hintCells = {}
	state.hintedWords = {}
	state.hintCursorIndex = 0
	state.sessionScore = 0
	state.puzzlesCleared = 0
	state.streak = targetModeStreak
	state.boardStartedAt = 0
	state.lastFoundAt = 0
	state.wrongDragCount = 0
	state.pendingIntroResumeBoardState = nil
	state.gameEnded = false
	state.boardStartCountdownPending = false
	state.wordRowsRevealPending = false
	state.gameplayInputLocked = false

	resetWordListUi()
	updateWordsLabel()
	state.boardIntroAnimating = false
	state.boardVisualToken += 1
	state.boardIntroDelaySeconds = 1.12
	state.duelActive = false
	state.duelMatchId = nil
	state.duelOpponentName = ""
	state.duelSourceMode = nil
	state.duelServerStarted = false
	state.duelLocalCountdownFinished = false
	state.duelMyProgress = 0
	state.duelOpponentProgress = 0

	if ui.boardHolder and ui.boardHolder:IsA("GuiObject") then
		ui.boardHolder.BackgroundTransparency = 1
		ui.boardHolder.Rotation = 0
	end
	setBoardVisualTransparency(1)

	if ui.boardScaleController then
		ui.boardScaleController.Scale = 1
	end
end

function RuntimeHelpers.animateBoardExit(callback)
	if not next(tiles) then
		if callback then
			callback()
		end
		return
	end

	playSound("Disappear")
	clearDrag()
	state.boardIntroAnimating = false
	state.boardVisualToken += 1
	local accent = getModeConfig().accent or COLORS.buttonPrimary
	if ui.boardHolder and ui.boardHolder:IsA("GuiObject") then
		ui.boardHolder.BackgroundTransparency = 0
		ui.boardHolder.Rotation = 0
		tween(ui.boardHolder, { BackgroundTransparency = 1 }, TweenInfo.new(1.08, Enum.EasingStyle.Quint, Enum.EasingDirection.In))
	end

	local flashParent = ui.boardContent or ui.boardHolder
	if flashParent then
		local flash = create("Frame", {
			Name = "BoardExitFlash",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.34),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.02, 1.02),
			ZIndex = 18,
			Parent = flashParent,
		})
		create("UICorner", {
			CornerRadius = UDim.new(0.08, 0),
			Parent = flash,
		})
		tween(flash, {
			BackgroundTransparency = 0.84,
			Size = UDim2.fromScale(1.08, 1.08),
		}, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		task.delay(0.18, function()
			if flash and flash.Parent then
				tween(flash, {
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1.16, 1.16),
				}, TweenInfo.new(0.76, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
				task.delay(0.78, function()
					if flash and flash.Parent then
						flash:Destroy()
					end
				end)
			end
		end)
	end

	setBoardVisualTransparency(0)
	tweenBoardVisualTransparency(1, TweenInfo.new(1.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In))

	for _, entry in pairs(ui.foundLineEntries or {}) do
		if entry.line then
			tween(entry.line, { BackgroundTransparency = 1 }, 0.56)
		end
		if entry.glow then
			tween(entry.glow, { BackgroundTransparency = 1 }, 0.56)
		end
	end

	for _, entry in pairs(ui.hintLineEntries or {}) do
		if entry.line then
			tween(entry.line, { BackgroundTransparency = 1 }, 0.56)
		end
		if entry.glow then
			tween(entry.glow, { BackgroundTransparency = 1 }, 0.56)
		end
	end

	local gridSize = state.currentPuzzle and state.currentPuzzle.gridSize or 1
	local center = (gridSize + 1) * 0.5
	local maxDistance = math.max(1, (center - 1) * 2)
	local exitWaveCap = gridSize >= FAST_TILE_REFRESH_GRID_SIZE and 0.68 or 0.96
	local maxDelay = 0

	for row, rowTiles in pairs(tiles) do
		for column, tile in pairs(rowTiles) do
			local background, letterLabel, scaleController = ensureTileVisuals(tile)
			local distance = math.abs(row - center) + math.abs(column - center)
			local delayTime = (distance / maxDistance) * exitWaveCap
			maxDelay = math.max(maxDelay, delayTime)

			task.delay(delayTime, function()
				if not tile.Parent then
					return
				end

				background.BackgroundTransparency = 1
				tween(letterLabel, { TextTransparency = 1 }, TweenInfo.new(0.56, Enum.EasingStyle.Sine, Enum.EasingDirection.In))
				tween(scaleController, { Scale = 0.18 }, TweenInfo.new(0.64, Enum.EasingStyle.Quint, Enum.EasingDirection.In))
			end)
		end
	end

	if ui.boardScaleController then
		ui.boardScaleController.Scale = 1
		tween(ui.boardScaleController, { Scale = 0.84 }, TweenInfo.new(1.12, Enum.EasingStyle.Quint, Enum.EasingDirection.In))
	end

	if ui.boardHolder then
		tween(ui.boardHolder, { Rotation = 6 }, TweenInfo.new(1.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In))
	end

	task.delay(math.max(maxDelay + 0.96, 1.16), function()
		if callback then
			callback()
		end
	end)
end

function RuntimeHelpers.playPuzzleCompleteAnimation(accentColor, path, options)
	options = options or {}
	local accent = accentColor or getModeConfig().accent or COLORS.buttonPrimary
	local pulseParent = ui.boardContent or ui.boardHolder
	local centerScaleX = 0.5
	local centerScaleY = 0.5

	if pulseParent and path and #path > 0 and pulseParent.AbsoluteSize.X > 0 and pulseParent.AbsoluteSize.Y > 0 then
		local totalX = 0
		local totalY = 0
		local count = 0
		for _, point in ipairs(path) do
			local center = getTileCenter(point.row, point.column)
			if center then
				totalX += center.X
				totalY += center.Y
				count += 1
			end
		end
		if count > 0 then
			local relativeX = (totalX / count - pulseParent.AbsolutePosition.X) / pulseParent.AbsoluteSize.X
			local relativeY = (totalY / count - pulseParent.AbsolutePosition.Y) / pulseParent.AbsoluteSize.Y
			centerScaleX = math.clamp(relativeX, 0.12, 0.88)
			centerScaleY = math.clamp(relativeY, 0.12, 0.88)
		end
	end

	if ui.boardScaleController then
		local peakScale = options.hint and 1.012 or (options.final and 1.03 or 1.018)
		ui.boardScaleController.Scale = 0.992
		tween(ui.boardScaleController, { Scale = peakScale }, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))

		task.delay(0.2, function()
			if ui.boardScaleController and ui.boardScaleController.Parent then
				tween(ui.boardScaleController, { Scale = 1 }, TweenInfo.new(0.24, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
			end
		end)
	end

	if pulseParent then
		local glow = create("Frame", {
			Name = "BoardFeedbackGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BackgroundTransparency = options.hint and 0.9 or 0.84,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(centerScaleX, centerScaleY),
			Size = UDim2.fromScale(options.hint and 0.12 or 0.1, options.hint and 0.12 or 0.1),
			ZIndex = 19,
			Parent = pulseParent,
		})
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = glow,
		})

		local ring = create("Frame", {
			Name = "BoardFeedbackRing",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(centerScaleX, centerScaleY),
			Size = UDim2.fromScale(options.hint and 0.14 or 0.12, options.hint and 0.14 or 0.12),
			ZIndex = 20,
			Parent = pulseParent,
		})
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Parent = ring,
		})
		local ringStroke = create("UIStroke", {
			Color = accent:Lerp(Color3.new(1, 1, 1), options.hint and 0.2 or 0.32),
			Thickness = options.hint and 2.2 or 3,
			Transparency = options.hint and 0.3 or 0.18,
			Parent = ring,
		})

		tween(glow, {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(options.final and 0.64 or 0.44, options.final and 0.64 or 0.44),
		}, TweenInfo.new(options.final and 0.54 or 0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		tween(ring, {
			Size = UDim2.fromScale(options.final and 0.9 or 0.62, options.final and 0.9 or 0.62),
		}, TweenInfo.new(options.final and 0.64 or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		tween(ringStroke, {
			Transparency = 1,
			Thickness = 1,
		}, TweenInfo.new(options.final and 0.64 or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))

		task.delay(options.final and 0.68 or 0.54, function()
			if glow and glow.Parent then
				glow:Destroy()
			end
			if ring and ring.Parent then
				ring:Destroy()
			end
		end)
	end

	if path then
		for index, point in ipairs(path) do
			local tile = tiles[point.row] and tiles[point.row][point.column]
			task.delay(math.min(0.18, (index - 1) * 0.025), function()
				if not (tile and tile.Parent) then
					return
				end

				local _, _, scaleController = ensureTileVisuals(tile)
				local settleScale = 1
				local peakScale = options.hint and 1.03 or 1.055
				pulseScale(scaleController, peakScale, settleScale, 0)
			end)
		end
	else
		for row, rowTiles in pairs(tiles) do
			for column, tile in pairs(rowTiles) do
				local _, _, scaleController = ensureTileVisuals(tile)
				local settleScale = 1
				pulseScale(scaleController, settleScale + 0.05, settleScale, (row + column) * 0.01)
			end
		end
	end

	if not options.hint then
		for _, button in ipairs({
			ui.hintButton,
			ui.nextButton,
			}) do
			if button and button:FindFirstChild("ScaleController") then
				pulseScale(button.ScaleController, 1.06, 1, 0.05)
			end
		end

		for _, button in pairs(ui.modeButtons or {}) do
			if button and button:FindFirstChild("ScaleController") then
				pulseScale(button.ScaleController, 1.06, 1, 0.05)
			end
		end
	end
end

function RuntimeHelpers.playWinSolvedLineCelebration()
	local successColor = ALERT_TOAST_COLORS.success
	local foundEntries = ui.foundLineEntries or {}
	local celebrationIndex = 0
	local longestDelay = 0
	local hadEntry = false

	for _, placedWord in ipairs(state.currentPuzzle and state.currentPuzzle.placedWords or {}) do
		if state.foundWords[placedWord.word] then
			local entry = foundEntries[placedWord.word]
			if entry and entry.line and entry.line.Parent then
				hadEntry = true
				celebrationIndex += 1
				local stepDelay = math.min(0.24, (celebrationIndex - 1) * 0.03)
				longestDelay = math.max(longestDelay, stepDelay)

				task.delay(stepDelay, function()
					if not (entry.line and entry.line.Parent) then
						return
					end

					tween(entry.line, {
						BackgroundColor3 = successColor,
						BackgroundTransparency = math.max(0.06, LAYOUT.FoundLineTransparency - 0.1),
					}, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
					pulseLineFrame(entry.line, 1.16, 1.04)

					if entry.glow and entry.glow.Parent then
						tween(entry.glow, {
							BackgroundColor3 = successColor:Lerp(Color3.new(1, 1, 1), 0.12),
							BackgroundTransparency = 0.72,
						}, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
						pulseLineFrame(entry.glow, 1.2, 1.08)
					end
				end)
			end
		end
	end

	if ui.boardScaleController then
		task.delay(0.02, function()
			if ui.boardScaleController and ui.boardScaleController.Parent then
				pulseScale(ui.boardScaleController, 1.035, 1, 0)
			end
		end)
	end

	if not hadEntry then
		return 0.28
	end

	return longestDelay + 0.34
end

function RuntimeHelpers.refreshBoard()
	local selected = selectionLookup()
	local fogAnchors = state.mode == "Fog" and getFogRevealAnchors() or nil
	local useFastRefresh = state.currentPuzzle and state.currentPuzzle.gridSize >= FAST_TILE_REFRESH_GRID_SIZE
	local allowHoverStroke = not state.dragging
		and state.activeInput == nil
		and state.dragStart == nil
		and state.dragTarget == nil
	local boardIntroAnimating = state.boardIntroAnimating == true
	for row, rowTiles in pairs(tiles) do
		for column in pairs(rowTiles) do
			refreshTileVisual(row, column, {
				selected = selected,
				fogAnchors = fogAnchors,
				useFastRefresh = useFastRefresh,
				allowHoverStroke = allowHoverStroke,
				boardIntroAnimating = boardIntroAnimating,
			})
		end
	end

	refreshDragLine()
	if RuntimeHelpers.refreshBoardCursor then
		RuntimeHelpers.refreshBoardCursor()
	end
end

RuntimeHelpers.updateHintTilePulse = function()
	return
end

RuntimeHelpers.ensureGamepadBoardSelection = function()
	if not (state.currentPuzzle and ui.puzzleGrid) then
		return
	end

	local lastInputType = UserInputService:GetLastInputType()
	if not string.find(tostring(lastInputType), "Gamepad") then
		return
	end

	local guiService = game:GetService("GuiService")
	local selectedObject = guiService.SelectedObject
	if selectedObject and selectedObject:IsDescendantOf(ui.puzzleGrid) and string.find(selectedObject.Name or "", "^Tile_") then
		return
	end

	local targetTile = nil
	if state.dragTarget then
		targetTile = tiles[state.dragTarget.row] and tiles[state.dragTarget.row][state.dragTarget.column] or nil
	elseif type(state.hoveredCellKey) == "string" then
		local rowText, columnText = string.match(state.hoveredCellKey, "^(%d+):(%d+)$")
		local rowNumber = tonumber(rowText)
		local columnNumber = tonumber(columnText)
		if rowNumber and columnNumber then
			targetTile = tiles[rowNumber] and tiles[rowNumber][columnNumber] or nil
		end
	end

	if not targetTile then
		targetTile = tiles[1] and tiles[1][1] or nil
	end

	if targetTile then
		guiService.SelectedObject = targetTile
	end
end

RuntimeHelpers.refreshBoardCursor = function()
	local cursorRoot = ui.boardCursorRoot
	local cursorParent = cursorRoot and cursorRoot.Parent
	if not (cursorRoot and cursorParent and cursorParent:IsA("GuiObject")) then
		return
	end

	local activeInputType = state.activeInputType
	local usingGamepad = string.find(tostring(activeInputType or UserInputService:GetLastInputType()), "Gamepad") ~= nil
	local shouldShow = usingGamepad
		and state.gameViewActive
		and state.currentPuzzle ~= nil
		and not state.transitionBusy
		and not state.viewTransitionBusy
		and not state.boardIntroAnimating
		and not state.gameEnded

	if not shouldShow then
		cursorRoot.Visible = false
		ui.boardCursorTargetKey = nil
		if ui.boardCursorScale then
			ui.boardCursorScale.Scale = 1
		end
		return
	end

	local targetRow, targetColumn = nil, nil
	if state.dragging and string.find(tostring(activeInputType), "Gamepad") and state.dragTarget then
		targetRow = state.dragTarget.row
		targetColumn = state.dragTarget.column
	elseif type(state.hoveredCellKey) == "string" then
		local rowText, columnText = string.match(state.hoveredCellKey, "^(%d+):(%d+)$")
		targetRow = tonumber(rowText)
		targetColumn = tonumber(columnText)
	else
		local selectedObject = game:GetService("GuiService").SelectedObject
		if selectedObject and selectedObject:IsDescendantOf(ui.puzzleGrid) then
			local rowText, columnText = string.match(selectedObject.Name or "", "^Tile_(%d+)_(%d+)$")
			targetRow = tonumber(rowText)
			targetColumn = tonumber(columnText)
		end
	end

	local targetTile = targetRow and targetColumn and tiles[targetRow] and tiles[targetRow][targetColumn] or nil
	if not targetTile then
		cursorRoot.Visible = false
		ui.boardCursorTargetKey = nil
		if ui.boardCursorScale then
			ui.boardCursorScale.Scale = 1
		end
		return
	end

	local tileSize = targetTile.AbsoluteSize
	local tilePosition = targetTile.AbsolutePosition
	local parentPosition = cursorParent.AbsolutePosition
	local targetPosition = UDim2.fromOffset(
		(tilePosition.X - parentPosition.X) + (tileSize.X * 0.5),
		(tilePosition.Y - parentPosition.Y) + (tileSize.Y * 0.5)
	)
	local targetSize = UDim2.fromOffset(
		math.max(18, math.floor(tileSize.X * 0.8)),
		math.max(18, math.floor(tileSize.Y * 0.8))
	)
	local targetKey = string.format("%d:%d", targetRow, targetColumn)
	local targetBackgroundTransparency = state.dragging and 0.84 or 0.9
	local targetStrokeTransparency = state.dragging and 0.02 or 0.12
	local targetGlowTransparency = state.dragging and 0.9 or 0.94
	local targetScale = state.dragging and 1.06 or 1
	local targetChanged = ui.boardCursorTargetKey ~= targetKey or cursorRoot.Visible ~= true

	cursorRoot.Visible = true
	if targetChanged then
		tween(cursorRoot, {
			Position = targetPosition,
			Size = targetSize,
			BackgroundTransparency = targetBackgroundTransparency,
		}, TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		if ui.boardCursorScale then
			ui.boardCursorScale.Scale = 0.9
			tween(ui.boardCursorScale, { Scale = targetScale }, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
		end
	else
		cursorRoot.Position = targetPosition
		cursorRoot.Size = targetSize
		cursorRoot.BackgroundTransparency = targetBackgroundTransparency
		if ui.boardCursorScale then
			ui.boardCursorScale.Scale = targetScale
		end
	end

	if ui.boardCursorGlow then
		ui.boardCursorGlow.BackgroundTransparency = targetGlowTransparency
	end
	if ui.boardCursorStroke then
		ui.boardCursorStroke.Transparency = targetStrokeTransparency
	end

	ui.boardCursorTargetKey = targetKey
end

clearDrag = function()
	dragLineVisualState.active = false
	dragLineVisualState.holdVisible = false
	dragLineVisualState.targetFirst = nil
	dragLineVisualState.targetLast = nil
	dragLineVisualState.currentFirst = nil
	dragLineVisualState.currentLast = nil
	resetDragState()
	ui.dragLine.Visible = false
	ui.dragGlow.Visible = false
	ui.dragLine.BackgroundTransparency = 1
	ui.dragGlow.BackgroundTransparency = 1
	if ui.dragLine:FindFirstChild("ScaleController") then
		ui.dragLine.ScaleController.Scale = 1
	end
	if ui.dragGlow:FindFirstChild("ScaleController") then
		ui.dragGlow.ScaleController.Scale = 1
	end
	RuntimeHelpers.refreshBoard()
end

function RuntimeHelpers.isComplete()
	for _, word in ipairs(state.currentPuzzle.words) do
		if not state.foundWords[word] then
			return false
		end
	end

	return true
end

function RuntimeHelpers.buildBoardProgressPayload(includeCompletedBoard)
	if state.duelActive or not state.currentPuzzle or (state.gameEnded and not includeCompletedBoard) or (RuntimeHelpers.isComplete() and not includeCompletedBoard) then
		return nil
	end

	local payload = {
		mode = state.mode,
		level = state.puzzleIndex,
		seed = state.seed,
		foundWords = collectMarkedWords(state.foundWords),
		hintedWords = collectMarkedWords(state.hintedWords),
		hintUses = math.max(0, math.floor(tonumber(state.currentBoardHintUses) or 0)),
		sessionScore = state.sessionScore,
		puzzlesCleared = state.puzzlesCleared,
		streak = state.streak,
	}

	return payload
end

syncBoardProgress = function()
	if state.duelActive then
		return
	end

	local payload = RuntimeHelpers.buildBoardProgressPayload()
	if payload then
		trackServerAction("BoardStateUpdated", {
			boardState = payload,
		})
	else
		trackServerAction("BoardStateCleared", {})
	end
end

function RuntimeHelpers.endRunAndReturnToMenu()
	local finishedMode = state.mode
	state.activeCountdownId += 1
	state.gameEnded = true
	state.gameplayInputLocked = false
	state.resumeBoardState = nil
	state.pendingResumeBoardState = nil
	setSelectedMenuMode(finishedMode)
	if ui.countdownFrame then
		ui.countdownFrame.Visible = false
	end
	RuntimeHelpers.animateBoardExit(function()
		RuntimeHelpers.clearBoard()
		clearHint()
		state.currentPuzzle = nil
		state.foundWords = {}
		state.foundCells = {}
		state.hintCells = {}
		state.hintedWords = {}
		state.hintCursorIndex = 0
		showMenuView(true)
	end)
end

tileFromScreenPosition = function(position)
	local mappedCell = getGridCellFromScreenPosition(position)
	if mappedCell then
		return mappedCell
	end

	for row, rowTiles in pairs(tiles) do
		for column, tile in pairs(rowTiles) do
			local tilePosition = tile.AbsolutePosition
			local tileSize = tile.AbsoluteSize
			local insideX = position.X >= tilePosition.X and position.X <= tilePosition.X + tileSize.X
			local insideY = position.Y >= tilePosition.Y and position.Y <= tilePosition.Y + tileSize.Y

			if insideX and insideY then
				return {
					row = row,
					column = column,
				}
			end
		end
	end

	return nil
end

function RuntimeHelpers.updateDragTarget(position, forcedTarget)
	if not state.dragging or not state.dragStart then
		return
	end

	state.dragCursorPosition = position
	local nextTarget = forcedTarget or snapTargetFromPosition(position) or state.dragStart
	local nextKey = string.format("%d:%d", nextTarget.row, nextTarget.column)
	if nextKey == state.lastDragSnapKey then
		return
	end

	local previousSelection = currentSelection()
	local previousLength = previousSelection and #previousSelection or 1
	state.lastDragSnapKey = nextKey
	state.dragTarget = nextTarget

	local nextSelection = currentSelection()
	local nextLength = nextSelection and #nextSelection or 1
	if nextLength > previousLength then
		playSound("Plus")
	elseif nextLength < previousLength then
		playSound("Minus")
	end

	if state.currentPuzzle and state.currentPuzzle.gridSize >= FAST_TILE_REFRESH_GRID_SIZE then
		refreshSelectionDelta(previousSelection, nextSelection)
	else
		RuntimeHelpers.refreshBoard()
	end
end

function RuntimeHelpers.findPlacedWordForSelection(selection)
	for _, placedWord in ipairs(state.currentPuzzle.placedWords) do
		if not state.foundWords[placedWord.word] and pathMatches(selection, placedWord.path) then
			return placedWord
		end
	end

	return nil
end

function RuntimeHelpers.findAnyPlacedWordForSelection(selection)
	for _, placedWord in ipairs(state.currentPuzzle.placedWords) do
		if pathMatches(selection, placedWord.path) then
			return placedWord
		end
	end

	return nil
end

findMatchedWord = function(selection)
	local placedWord = RuntimeHelpers.findPlacedWordForSelection(selection)
	if not placedWord then
		return nil
	end

	return placedWord
end

function RuntimeHelpers.completeSelection()
	local selection = currentSelection()
	local postCompleteAction = nil
		local postCompleteDelay = 1

	if not selection or #selection < 2 then
		state.wrongDragCount += 1
		animateWrongSelection()
		return
	end

	local matchedWord = findMatchedWord(selection)
	if not matchedWord then
		local duplicateWord = RuntimeHelpers.findAnyPlacedWordForSelection(selection)
		if duplicateWord and state.foundWords[duplicateWord.word] then
			showDesktopAlert(nil, "You already found that word.", "info", {
				color = COLORS.textMuted,
				soundName = false,
				duration = 2,
			})
			return
		end
	end

	if not matchedWord then

		state.wrongDragCount += 1
		animateWrongSelection()
		if state.mode == "OneLife" and #selection >= 2 then
			local awardedStars = 0
			state.gameEnded = true
			state.gameplayInputLocked = true
			state.streak = 0
			updateHud()
			task.delay(0.42, function()
				applyLocalAction("BoardLost", {
					mode = state.mode,
					level = state.puzzleIndex,
					reason = "loss",
					stars = awardedStars,
				})
				RuntimeHelpers.printAwardedStars(awardedStars)
				trackServerAction("BoardLost", {
					mode = state.mode,
					level = state.puzzleIndex,
					words = state.currentPuzzle and #state.currentPuzzle.words or 0,
					reason = "loss",
					stars = awardedStars,
				})
				trackServerAction("BoardStateCleared", {})
				showSummary("YOU LOST", "One mistake ended the board.", "CONTINUE", COLORS.error, function()
					hideSummary()
					startMode(state.mode)
				end, {
					isLoss = true,
					stars = awardedStars,
					totalWins = state.totalStars,
					streak = state.streak,
					startPuzzlePieces = math.max(0, math.floor((getSnapshot().inventory and getSnapshot().inventory.puzzlePieces) or 0)),
					previewPuzzlePieces = 0,
				})
			end)
		end
		return
	end

	state.lastFoundAt = Workspace.DistributedGameTime
	state.wrongDragCount = 0
	state.foundWords[matchedWord.word] = true
	for _, point in ipairs(matchedWord.path) do
		state.foundCells[cellKey(point.row, point.column)] = true
	end

	clearHintWord(matchedWord.word)
	local foundWordCount = countFoundWords()
	local boardCompleted = RuntimeHelpers.isComplete()
	if boardCompleted then
		playSound("Victory")
	else
		playSound("NotificationHigh", {
			pitch = RuntimeHelpers.getCorrectWordSoundPitch(),
		})
	end

	local wordScore = RuntimeHelpers.calculateWordScore(matchedWord.word)
	addScore(wordScore)
	if not state.duelActive then
		applyLocalAction("WordFound")
	end
	if state.duelActive and state.duelController then
		state.duelController:reportWordFound(
			matchedWord.word,
			(foundWordCount / math.max(1, #state.currentPuzzle.words)) * 100,
			matchedWord.path
		)
	else
		trackFunnelStep("FirstWordFound_" .. tostring(state.mode), {
			mode = state.mode,
		})
		trackServerAction("WordFound", {
			mode = state.mode,
			word = matchedWord.word,
			path = matchedWord.path,
			boardState = RuntimeHelpers.buildBoardProgressPayload(),
		})
	end

	keepCurrentDragLineAsFound(matchedWord.word, matchedWord.path)
	refreshPersistentLines()
	updateWordsLabel()
	updateHud()
	if boardCompleted or (foundWordCount % 2 == 0) then
		RuntimeHelpers.showPraiseBanner()
	end

	if boardCompleted then
		if state.duelActive and state.duelController then
			state.gameEnded = true
			state.gameplayInputLocked = true
			updateHud()
			state.duelController:reportCompletion()
			RuntimeHelpers.refreshBoard()
			RuntimeHelpers.playPuzzleCompleteAnimation(getWordColor(matchedWord.word), matchedWord.path, {
				final = true,
			})
			return
		end

		local modeConfig = getModeConfig()
		local bonus = RuntimeHelpers.calculatePuzzleBonus()
		local solvesGranted = 1
		local celebrationText = RuntimeHelpers.getCompletionToastText()
		local awardedStars = RuntimeHelpers.calculateAwardedStars(true)
		local clearedBoardState = RuntimeHelpers.buildBoardProgressPayload(true)
		local startingPuzzlePieces = math.max(0, math.floor((getSnapshot().inventory and getSnapshot().inventory.puzzlePieces) or 0))
		local previousTotalWins = state.totalStars
		local previewPuzzlePieces = RuntimeHelpers.calculateAwardedPuzzlePiecesPreview()

		addScore(bonus)
		state.totalStars += solvesGranted
		state.puzzlesCleared += 1
		state.streak += 1
		if state.mode == "Classic" then
			state.savedClassicLevel = math.max(state.savedClassicLevel, math.min(#Dependencies.Levels, state.puzzleIndex + 1))
			if state.puzzleIndex < #Dependencies.Levels then
				playSound("NewLevel")
			end
		end

		if ui.rewardChipScale then
			pulseScale(ui.rewardChipScale, 1.08, 1, 0)
		end
		if ui.streakScale then
			pulseScale(ui.streakScale, 1.08, 1, 0)
		end

		applyLocalAction("BoardCleared", {
			mode = state.mode,
			level = state.puzzleIndex,
			stars = awardedStars,
			puzzlePiecesEarned = previewPuzzlePieces,
		})
		RuntimeHelpers.printAwardedStars(awardedStars)
		trackFunnelStep("BoardCleared_" .. tostring(state.mode), {
			mode = state.mode,
		})
		if state.mode == "Classic" and state.puzzleIndex <= 80 then
			trackFunnelStep(string.format("ClassicLevel_%03d_Completed", state.puzzleIndex), {
				mode = state.mode,
				level = state.puzzleIndex,
				words = #state.currentPuzzle.words,
				stars = awardedStars,
			})
		end
		trackServerAction("BoardCleared", {
			mode = state.mode,
			level = state.puzzleIndex,
			words = #state.currentPuzzle.words,
			stars = awardedStars,
			boardState = clearedBoardState,
		})

		updateHud()

		state.gameEnded = true
		state.gameplayInputLocked = true
		updateHud()
		local outcomeSummaryContext = {
			isLoss = false,
			stars = awardedStars,
			previousTotalWins = previousTotalWins,
			totalWins = state.totalStars,
			streak = state.streak,
			startPuzzlePieces = startingPuzzlePieces,
			previewPuzzlePieces = previewPuzzlePieces,
		}

		if state.mode == "Daily" then
			RuntimeHelpers.showRewardToast(celebrationText, ALERT_TOAST_COLORS.success)
			postCompleteAction = function()
				showSummary("YOU WON", "Daily complete.", "CONTINUE", ALERT_TOAST_COLORS.success, function()
					hideSummary()
					RuntimeHelpers.endRunAndReturnToMenu()
				end, outcomeSummaryContext)
			end
		elseif modeConfig.loop and state.mode ~= "Classic" then
			RuntimeHelpers.showRewardToast(celebrationText, ALERT_TOAST_COLORS.success)
			postCompleteAction = function()
				local summaryTitle = "YOU WON"
				local summaryBody = state.mode == "Themed"
					and string.upper(tostring(state.currentPuzzle and state.currentPuzzle.title or "Themed"))
					or "Board cleared."
				showSummary(summaryTitle, summaryBody, "CONTINUE", ALERT_TOAST_COLORS.success, function()
					hideSummary()
					state.gameEnded = false
					state.gameplayInputLocked = false
					transitionToPuzzle(chooseModeLevelIndex(state.mode), nextSeed(state.puzzlesCleared + state.totalStars))
				end, outcomeSummaryContext)
			end
		elseif state.puzzleIndex >= #Dependencies.Levels then
			RuntimeHelpers.showRewardToast(celebrationText, ALERT_TOAST_COLORS.success)
			postCompleteAction = function()
				showSummary("YOU WON", "All classic levels cleared.", "MENU", ALERT_TOAST_COLORS.success, function()
					hideSummary()
					RuntimeHelpers.endRunAndReturnToMenu()
				end, outcomeSummaryContext)
			end
		else
			RuntimeHelpers.showRewardToast(celebrationText, ALERT_TOAST_COLORS.success)
			postCompleteAction = function()
				showSummary("YOU WON", string.format("Level %d", state.puzzleIndex), "CONTINUE", ALERT_TOAST_COLORS.success, function()
					hideSummary()
					state.gameEnded = false
					state.gameplayInputLocked = false
					transitionToPuzzle(state.puzzleIndex + 1)
				end, outcomeSummaryContext)
			end
		end
	end

	syncBoardProgress()
	RuntimeHelpers.refreshBoard()
	RuntimeHelpers.playPuzzleCompleteAnimation(getWordColor(matchedWord.word), matchedWord.path, {
		final = boardCompleted,
	})
	if postCompleteAction then
		if boardCompleted then
			postCompleteDelay = math.max(postCompleteDelay, RuntimeHelpers.playWinSolvedLineCelebration())
		end
		task.delay(postCompleteDelay, postCompleteAction)
	end
end

function RuntimeHelpers.beginDrag(row, column, input, forcedInputType, forcedPosition)
	local resolvedInputType = forcedInputType or (input and input.UserInputType) or Enum.UserInputType.Gamepad1
	if state.dragging and state.activeInputType == resolvedInputType then
		return
	end

	local dragBlockReason = getDragBlockReason()
	if dragBlockReason then
		return
	end

	local resolvedPosition = forcedPosition
	if not resolvedPosition and input and input.Position then
		resolvedPosition = Vector2.new(input.Position.X, input.Position.Y)
	end
	if not resolvedPosition then
		resolvedPosition = getTileCenter(row, column) or Vector2.new(0, 0)
	end

	state.hoveredCellKey = nil
	state.dragging = true
	state.activeInput = input
	state.activeInputType = resolvedInputType
	state.dragStart = { row = row, column = column }
	state.dragStartPosition = resolvedPosition
	state.dragCursorPosition = state.dragStartPosition
	state.dragTarget = { row = row, column = column }
	state.lastDragSnapKey = string.format("%d:%d", row, column)
	setStatus("Drag in a straight line.", COLORS.textMuted)
	RuntimeHelpers.refreshBoard()
end

function RuntimeHelpers.tryBeginDragFromScreenPosition(position, input, forcedInputType)
	if not position then
		return false
	end

	local target = tileFromScreenPosition(position)
	if not target then
		return false
	end

	RuntimeHelpers.beginDrag(target.row, target.column, input, forcedInputType or Enum.UserInputType.Touch, position)
	return true
end

function RuntimeHelpers.showHint()
	if isGameplayInteractionBlocked() or state.gameEnded or not state.gameViewActive or state.pendingHintRequest then
		return
	end

	trackFunnelStep("HintClicked_" .. tostring(state.mode), {
		mode = state.mode,
	})

	if getModeConfig().disableHints then
		showDesktopAlert(nil, "Hints are disabled in this mode.", "info", {
			color = COLORS.textMuted,
			soundName = false,
			duration = 2.2,
		})
		return
	end

	if RuntimeHelpers.isComplete() then
		showDesktopAlert(nil, "This board is already done.", "info", {
			color = COLORS.textMuted,
			soundName = false,
			duration = 2.2,
		})
		return
	end

	if state.availableHints <= 0 then
		trackFunnelStep("HintNoInventoryPrompt", {
			mode = state.mode,
		})
		local productId = Dependencies.MetaConfig.HINT_PRODUCT_IDS and Dependencies.MetaConfig.HINT_PRODUCT_IDS[1] or nil
		if type(productId) == "number" then
			pcall(function()
				game:GetService("MarketplaceService"):PromptProductPurchase(player, productId)
			end)
		else
			showDesktopAlert(nil, "Buy hints in the shop.", "info", {
				color = COLORS.textMuted,
				soundName = false,
				duration = 2.2,
			})
		end
		return
	end

	local nextIndex, nextWord = nextHintTarget()
	if not nextWord then
		showDesktopAlert(nil, "All remaining words already have hints.", "info", {
			color = COLORS.textMuted,
			soundName = false,
			duration = 2.2,
		})
		return
	end

	local previousHintCount = math.max(0, math.floor(tonumber(state.availableHints) or 0))
	local function applyHintSuccessFromLocalState()
		state.hintCursorIndex = nextIndex
		if not setHintWord(nextWord) then
			showDesktopAlert(nil, "That word already has a hint.", "info", {
				color = COLORS.textMuted,
				soundName = false,
				duration = 2.2,
			})
			return false
		end

		state.currentBoardHintUses = math.max(0, math.floor(tonumber(state.currentBoardHintUses) or 0) + 1)
		playSound("HintShowing")
		refreshPersistentLines()
		syncBoardProgress()
		RuntimeHelpers.refreshBoard()
		local hintedWordState = state.currentPuzzle and state.currentPuzzle.placedWordsByWord and state.currentPuzzle.placedWordsByWord[nextWord]
		RuntimeHelpers.playPuzzleCompleteAnimation(COLORS.hintLine, hintedWordState and hintedWordState.path or nil, {
			hint = true,
		})
		return true
	end

	local function fallbackUseHintEvent()
		if not applyHintSuccessFromLocalState() then
			return
		end

		applyLocalAction("HintUsed")
		trackServerAction("HintUsed", {
			mode = state.mode,
			word = nextWord,
			boardState = RuntimeHelpers.buildBoardProgressPayload(),
		})
	end

	local useHintRemote = remotes.useHint
	if not useHintRemote then
		useHintRemote = waitForRemote(Dependencies.RemoteConfig.UseHint, "RemoteFunction", 1)
		remotes.useHint = useHintRemote
	end
	if not useHintRemote then
		fallbackUseHintEvent()
		return
	end

	state.pendingHintRequest = true
	local result = nil
	local ok = pcall(function()
		result = useHintRemote:InvokeServer({
			mode = state.mode,
			word = nextWord,
			boardState = RuntimeHelpers.buildBoardProgressPayload(),
		})
	end)
	state.pendingHintRequest = false

	if not ok then
		fallbackUseHintEvent()
		return
	end

	if type(result) ~= "table" or result.success ~= true then
		if type(result) == "table" and type(result.snapshot) == "table" then
			applySnapshot(result.snapshot)
		end

		local failureMessage = type(result) == "table" and tostring(result.message or "Hint could not be used.") or "Hint service unavailable."
		if failureMessage == "No hints available." then
			showDesktopAlert(nil, failureMessage, "info", {
				color = COLORS.textMuted,
				soundName = false,
				duration = 2.2,
			})
			return
		end

		fallbackUseHintEvent()
		return
	end

	if type(result.snapshot) == "table" then
		applySnapshot(result.snapshot)
	end

	local validatedBoardState = type(result.boardState) == "table" and result.boardState
		or (type(result.snapshot) == "table" and type(result.snapshot.boardState) == "table" and result.snapshot.boardState or nil)
	local appliedServerState = false
	if validatedBoardState
		and validatedBoardState.mode == state.mode
		and math.floor(tonumber(validatedBoardState.level) or 0) == state.puzzleIndex
		and math.floor(tonumber(validatedBoardState.seed) or 0) == state.seed then
		applyResumeStateToCurrentPuzzle(validatedBoardState)
		appliedServerState = true
	end

	if state.availableHints >= previousHintCount then
		applyLocalAction("HintUsed")
	end

	if appliedServerState then
		state.hintCursorIndex = nextIndex
		playSound("HintShowing")
		refreshPersistentLines()
		syncBoardProgress()
		RuntimeHelpers.refreshBoard()
		local hintedWordState = state.currentPuzzle and state.currentPuzzle.placedWordsByWord and state.currentPuzzle.placedWordsByWord[nextWord]
		RuntimeHelpers.playPuzzleCompleteAnimation(COLORS.hintLine, hintedWordState and hintedWordState.path or nil, {
			hint = true,
		})
		return
	end

	applyHintSuccessFromLocalState()
end

function RuntimeHelpers.buildBoard()
	local boardTileRoot = ui.tileLayer or ui.puzzleGrid or ui.boardContent
	if not boardTileRoot then
		return
	end

	RuntimeHelpers.clearBoard()
	syncBoardContentLayout()

	local gridSize = state.currentPuzzle.gridSize
	local buildBoardToken = state.boardToken
	state.boardVisualToken += 1
	state.boardIntroAnimating = true
	local boardVisualToken = state.boardVisualToken
	local pendingIntroResumeBoardState = type(state.pendingIntroResumeBoardState) == "table" and state.pendingIntroResumeBoardState or nil
	local introWaveDivisor = math.max(1, (gridSize - 1) * 2)
	local introWaveCap = gridSize >= FAST_TILE_REFRESH_GRID_SIZE and 0.72 or 0.96
	local introMaxDelay = 0
	local introCompletionDelay = 1.08

	create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(0, 0),
		CellSize = UDim2.fromScale(1 / gridSize, 1 / gridSize),
		FillDirectionMaxCells = gridSize,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = boardTileRoot,
	})

	for row = 1, gridSize do
		tiles[row] = {}

		for column = 1, gridSize do
			local tile = create("TextButton", {
				Name = string.format("Tile_%d_%d", row, column),
				AnchorPoint = Vector2.new(0, 0),
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				LayoutOrder = (row - 1) * gridSize + column,
				Selectable = true,
				Size = UDim2.fromScale(1, 1),
				Text = "",
				ZIndex = 4,
				Parent = boardTileRoot,
			})
			local tileCellKey = cellKey(row, column)

			local _, letterLabel, scaleController = ensureTileVisuals(tile)
			letterLabel.Text = state.currentPuzzle.letters[row][column]
			letterLabel.TextTransparency = 1
			scaleController.Scale = 0.72

			local background = tile:FindFirstChild("CellBackground")
			if background then
				background.BackgroundTransparency = 1
			end

			tile.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					RuntimeHelpers.beginDrag(row, column, input)
				end
			end)

			tile.Activated:Connect(function(inputObject)
				local inputType = inputObject and inputObject.UserInputType or UserInputService:GetLastInputType()
				if not string.find(tostring(inputType), "Gamepad") then
					return
				end
				if isGameplayInteractionBlocked() or state.gameEnded or not state.gameViewActive then
					return
				end

				local tileCenter = getTileCenter(row, column) or Vector2.new(0, 0)
				if state.dragging and string.find(tostring(state.activeInputType), "Gamepad") then
					if state.dragStart and (state.dragTarget == nil or state.dragTarget.row ~= row or state.dragTarget.column ~= column) then
						RuntimeHelpers.updateDragTarget(tileCenter, {
							row = row,
							column = column,
						})
					end
					local selection = currentSelection()
					if not selection or #selection < 2 then
						return
					end
					RuntimeHelpers.completeSelection()
					return
				end

				RuntimeHelpers.beginDrag(row, column, nil, inputType, tileCenter)
			end)

			tile.SelectionGained:Connect(function()
				if not string.find(tostring(UserInputService:GetLastInputType()), "Gamepad") then
					return
				end
				state.hoveredCellKey = tileCellKey
				if state.dragging and string.find(tostring(state.activeInputType), "Gamepad") then
					RuntimeHelpers.updateDragTarget(
						getTileCenter(row, column) or state.dragCursorPosition,
						{
							row = row,
							column = column,
						}
					)
				end
				RuntimeHelpers.refreshBoard()
			end)

			tile.SelectionLost:Connect(function()
				if not string.find(tostring(UserInputService:GetLastInputType()), "Gamepad") then
					return
				end
				if state.hoveredCellKey == tileCellKey then
					state.hoveredCellKey = nil
					RuntimeHelpers.refreshBoard()
				end
			end)

			tile.MouseEnter:Connect(function()
				if state.boardIntroAnimating then
					return
				end
				local previousHoveredCellKey = state.hoveredCellKey
				state.hoveredCellKey = tileCellKey
				if state.currentPuzzle and state.currentPuzzle.gridSize >= FAST_TILE_REFRESH_GRID_SIZE and not state.dragging then
					refreshTileByKey(previousHoveredCellKey)
					refreshTileByKey(tileCellKey)
					return
				end
				RuntimeHelpers.refreshBoard()
			end)

			tile.MouseLeave:Connect(function()
				if state.boardIntroAnimating then
					return
				end
				if state.hoveredCellKey == tileCellKey then
					state.hoveredCellKey = nil
					if state.currentPuzzle and state.currentPuzzle.gridSize >= FAST_TILE_REFRESH_GRID_SIZE and not state.dragging then
						refreshTileByKey(tileCellKey)
						return
					end
					RuntimeHelpers.refreshBoard()
				end
			end)

			tiles[row][column] = tile

			local introDelay = (((row + column) - 2) / introWaveDivisor) * introWaveCap
			introMaxDelay = math.max(introMaxDelay, introDelay)
			task.delay(introDelay, function()
				if buildBoardToken ~= state.boardToken or boardVisualToken ~= state.boardVisualToken or not tile.Parent then
					return
				end

				local delayedBackground, delayedLabel, delayedScaleController = ensureTileVisuals(tile)
				delayedBackground.BackgroundTransparency = 1
				tween(delayedLabel, {
					TextTransparency = isFogTileVisible(row, column, selectionLookup()) and 0 or 1,
				}, TweenInfo.new(0.72, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
				tween(delayedScaleController, { Scale = 1 }, TweenInfo.new(0.96, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
			end)
		end
	end

	for row = 1, gridSize do
		for column = 1, gridSize do
			local tile = tiles[row] and tiles[row][column]
			if tile then
				tile.NextSelectionUp = tiles[row - 1] and tiles[row - 1][column] or nil
				tile.NextSelectionDown = tiles[row + 1] and tiles[row + 1][column] or nil
				tile.NextSelectionLeft = tiles[row] and tiles[row][column - 1] or nil
				tile.NextSelectionRight = tiles[row] and tiles[row][column + 1] or nil
			end
		end
	end

	if string.find(tostring(UserInputService:GetLastInputType()), "Gamepad") then
		local firstTile = tiles[1] and tiles[1][1] or nil
		if firstTile then
			game:GetService("GuiService").SelectedObject = firstTile
		end
	end
	if RuntimeHelpers.ensureGamepadBoardSelection then
		RuntimeHelpers.ensureGamepadBoardSelection()
	end
	if RuntimeHelpers.refreshBoardCursor then
		RuntimeHelpers.refreshBoardCursor()
	end
	introCompletionDelay = math.max(1.08, introMaxDelay + 0.98)
	state.boardIntroDelaySeconds = introCompletionDelay

	refreshPersistentLines()
	RuntimeHelpers.refreshBoard()
	RuntimeHelpers.animateBoardEntrance()
	task.delay(introCompletionDelay, function()
		if buildBoardToken ~= state.boardToken or boardVisualToken ~= state.boardVisualToken then
			return
		end

		state.boardIntroAnimating = false

		if pendingIntroResumeBoardState and state.pendingIntroResumeBoardState == pendingIntroResumeBoardState then
			applyResumeStateToCurrentPuzzle(pendingIntroResumeBoardState)
			state.pendingIntroResumeBoardState = nil
			updateWordsLabel()
			refreshPersistentLines()
		end
		RuntimeHelpers.refreshBoard()
		if updateHud then
			updateHud()
		end
	end)
end

loadPreparedPuzzle = function(puzzleData, targetIndex, chosenSeed, resumeBoardState)
	state.gameEnded = false
	state.puzzleIndex = targetIndex
	state.seed = chosenSeed
	state.boardToken += 1
	state.currentPuzzle = puzzleData
	state.foundWords = {}
	state.foundCells = {}
	state.hintCells = {}
	state.hintedWords = {}
	state.hintCursorIndex = 0
	state.pendingIntroResumeBoardState = nil
	state.boardStartedAt = Workspace.DistributedGameTime
	state.lastFoundAt = state.boardStartedAt
	state.currentBoardHintUses = 0
	state.wrongDragCount = 0
	state.wordRowsRevealPending = true
	state.boardStartCountdownPending = not state.duelActive
	if not state.duelActive then
		state.gameplayInputLocked = true
	end
	local currentBoardToken = state.boardToken

	assignWordColors()
	if resumeBoardState
		and resumeBoardState.mode == state.mode
		and math.floor(tonumber(resumeBoardState.level) or 0) == targetIndex
		and math.floor(tonumber(resumeBoardState.seed) or 0) == chosenSeed then
		state.pendingIntroResumeBoardState = resumeBoardState
		state.wordRowsRevealPending = false
		state.boardStartCountdownPending = false
		if not state.duelActive then
			state.gameplayInputLocked = false
		end
	end
	resetWordListUi()
	updateWordsLabel()
	RuntimeHelpers.buildBoard()
	refreshPersistentLines()
	clearDrag()
	updateHud()
	syncBoardProgress()
	trackFunnelStep("BoardLoaded_" .. tostring(state.mode), {
		mode = state.mode,
		level = targetIndex,
		words = puzzleData and #puzzleData.words or 0,
	})
	RuntimeHelpers.beginBoardCountdownIfNeeded(currentBoardToken)

	if state.duelActive then
		setStatus("Finish before your opponent.", getModeConfig().accent)
	elseif state.mode == "Classic" then
		setStatus("Drag across the word in a straight line.", COLORS.textMuted)
	elseif state.mode == "Themed" then
		setStatus("Each board rolls a random theme.", getModeConfig().accent)
	elseif state.mode == "Daily" then
		setStatus("One massive board today. Clear it before reset.", getModeConfig().accent)
	elseif state.mode == "Backwards" then
		setStatus("Every word is hidden backwards on this board.", getModeConfig().accent)
	elseif state.mode == "Mega" then
		setStatus("Massive board, more words, longer sweeps.", getModeConfig().accent)
	elseif state.mode == "Fog" then
		setStatus("Only nearby letters stay visible.", getModeConfig().accent)
	elseif state.mode == "OneLife" then
		setStatus("One wrong word ends the run.", getModeConfig().accent)
	else
		setStatus("Clear the board and a new one will flip in.", getModeConfig().accent)
	end
end

performPuzzleLoad = function(index, seed)
	hideSummary()

	local targetIndex = math.clamp(index or 1, 1, #Dependencies.Levels)
	local chosenSeed = seed
	if not chosenSeed then
		if state.mode == "Classic" then
			local template = Dependencies.Levels[targetIndex]
			chosenSeed = template and template.seed or nextSeed(targetIndex)
		else
			chosenSeed = nextSeed(targetIndex)
		end
	end
	local definition = buildPuzzleDefinition(targetIndex, state.mode, chosenSeed)
	local resumeBoardState = state.pendingResumeBoardState
	state.pendingResumeBoardState = nil
	loadPreparedPuzzle(Dependencies.Generator.generate(definition, chosenSeed), targetIndex, chosenSeed, resumeBoardState)
end

function RuntimeHelpers.tryStartDuelInput()
	if not state.duelActive or not state.duelServerStarted or not state.duelLocalCountdownFinished then
		return
	end

	if state.gameEnded then
		return
	end

	state.gameplayInputLocked = false
	updateHud()
	RuntimeHelpers.refreshBoard()
end

function RuntimeHelpers.finishDuelAndReturnHome()
	local selectedMode = state.duelSourceMode or getSelectedMenuModeName()
	setSelectedMenuMode(selectedMode)
	RuntimeHelpers.resetBoardRuntimeForFreshMode(selectedMode)
	showMenuView(true)
end

function RuntimeHelpers.handleDuelMatchCountdown(payload)
	if type(payload) ~= "table" or type(payload.puzzleData) ~= "table" then
		return
	end

	local duelMode = payload.mode == "Freeplay" and "Freeplay" or "Classic"
	local duelPuzzle = cloneTable(payload.puzzleData)
	local duelLevel = math.clamp(math.floor(tonumber(payload.level or duelPuzzle.level) or 1), 1, #Dependencies.Levels)
	local duelSeed = math.max(1, math.floor(tonumber(payload.puzzleData.seed or payload.seed) or nextSeed(duelLevel)))

	RuntimeHelpers.resetBoardRuntimeForFreshMode("Duel")
	state.duelActive = true
	state.duelMatchId = payload.matchId
	state.duelOpponentName = tostring(payload.opponentName or "Opponent")
	state.duelSourceMode = duelMode
	state.duelServerStarted = false
	state.duelLocalCountdownFinished = false
	state.duelMyProgress = 0
	state.duelOpponentProgress = 0
	state.gameplayInputLocked = true
	setSelectedMenuMode(duelMode)

	showGameView(true, function()
		loadPreparedPuzzle(duelPuzzle, duelLevel, duelSeed, nil)
		local boardToken = state.boardToken
		if not state.duelActive or state.duelMatchId ~= payload.matchId or boardToken ~= state.boardToken then
			return
		end

		RuntimeHelpers.playCountdownSequence(3, nil, function()
			if not state.duelActive or state.duelMatchId ~= payload.matchId or boardToken ~= state.boardToken then
				return
			end

			state.wordRowsRevealPending = false
			updateWordsLabel()
			state.duelLocalCountdownFinished = true
			RuntimeHelpers.tryStartDuelInput()
		end)
	end)
end

function RuntimeHelpers.handleDuelMatchStart(payload)
	if type(payload) ~= "table" or payload.matchId ~= state.duelMatchId then
		return
	end

	state.duelServerStarted = true
	RuntimeHelpers.tryStartDuelInput()
end

function RuntimeHelpers.handleDuelMatchResult(payload)
	if type(payload) ~= "table" then
		return false
	end
	if not state.duelActive then
		return true
	end
	if payload.matchId ~= nil and payload.matchId ~= state.duelMatchId then
		return true
	end

	local rewardAmount = math.max(0, math.floor(tonumber(payload.myPuzzlePieces or payload.myXP) or 0))
	local awardedStars = math.clamp(math.floor(tonumber(payload.myStars) or (payload.isWinner and 3 or 0)), 0, 3)
	local opponentName = tostring(
		payload.isWinner and (payload.loserName or state.duelOpponentName or "Opponent")
			or (payload.winnerName or state.duelOpponentName or "Opponent")
	)
	local summaryBody = string.format("Vs. %s", opponentName)
	if payload.opponentQuit and payload.isWinner then
		summaryBody = string.format("%s quit the duel.", opponentName)
	elseif payload.youQuit then
		summaryBody = "You left the duel."
	end

	state.gameEnded = true
	state.gameplayInputLocked = true
	state.duelServerStarted = false
	state.duelLocalCountdownFinished = true
	state.duelActive = false
	state.duelMatchId = nil
	state.duelMyProgress = payload.isWinner and 100 or state.duelMyProgress
	state.duelOpponentProgress = payload.isWinner and state.duelOpponentProgress or 100
	if ui.countdownFrame then
		ui.countdownFrame.Visible = false
	end
	clearDrag()
	updateHud()
	RuntimeHelpers.refreshBoard()
	showSummary(payload.isWinner and "YOU WON" or "YOU LOST", summaryBody, "CONTINUE", payload.isWinner and ALERT_TOAST_COLORS.success or COLORS.error, function()
		hideSummary()
		RuntimeHelpers.finishDuelAndReturnHome()
	end, {
		isLoss = payload.isWinner ~= true,
		keepLossReward = payload.isWinner ~= true and rewardAmount > 0,
		hideGift = true,
		stars = awardedStars,
		startPuzzlePieces = math.max(0, math.floor((getSnapshot().inventory and getSnapshot().inventory.puzzlePieces) or 0)),
		previewPuzzlePieces = rewardAmount,
	})
	return true
end

transitionToPuzzle = function(index, seed, skipExit)
	if state.transitionBusy or state.viewTransitionBusy then
		return
	end

	local targetIndex = index
	if not targetIndex then
		targetIndex = state.mode == "Classic" and math.clamp(state.puzzleIndex, 1, #Dependencies.Levels) or chooseModeLevelIndex(state.mode)
	end

	local finishLoad = function()
		state.transitionBusy = false
		performPuzzleLoad(targetIndex, seed)
	end

	if skipExit or not next(tiles) then
		finishLoad()
		return
	end

	state.transitionBusy = true
	refreshUiBindings()
	clearDrag()

	RuntimeHelpers.animateBoardExit(function()
		RuntimeHelpers.clearBoard()
		finishLoad()
	end)
end

function RuntimeHelpers.beginModeRun(mode, skipExit, startingClassicLevel)
	local modeConfig = getModeConfig(mode)
	local dailyInfo = mode == "Daily" and getDailyModeInfo() or nil
	local modeStreak = resolveModeStreakFromSnapshot(getSnapshot(), mode, 0)
	local resolvedClassicLevel = startingClassicLevel
		and math.clamp(math.floor(tonumber(startingClassicLevel) or RuntimeHelpers.getClassicContinueLevel()), 1, #Dependencies.Levels)
		or nil
	state.mode = mode
	state.sessionScore = 0
	state.puzzlesCleared = 0
	state.streak = modeStreak
	state.gameEnded = false
	clearHint()
	hideSummary()
	state.boardStartCountdownPending = false
	state.gameplayInputLocked = false

	state.puzzleIndex = (mode == "Classic" and (resolvedClassicLevel or RuntimeHelpers.getClassicContinueLevel()))
		or (dailyInfo and dailyInfo.level or modeConfig.startIndex)
	updateHud()
	transitionToPuzzle(
		mode == "Classic" and state.puzzleIndex or chooseModeLevelIndex(mode),
		mode == "Daily" and dailyInfo.seed or nextSeed((mode == "Classic" and state.puzzleIndex or modeConfig.startIndex) + state.totalStars),
		skipExit
	)
end

startMode = function(mode, skipExit)
	RuntimeHelpers.beginModeRun(mode, skipExit, nil)
end

handleMenuPlayPressed = function()
	if isInteractionBlocked() then
		return
	end

	local selectedMode = getSelectedMenuModeName()
	local unlockWins = getModeUnlockWins(selectedMode)
	if unlockWins and not isModeUnlocked(selectedMode) then
		showDesktopAlert(nil, string.format("Unlocks at %d wins.", unlockWins), "error", {
			duration = 2.2,
		})
		return
	end

	if selectedMode == "Classic" and ui.levelsOverlay and ui.levelsContainer then
		showClassicLevelsFrame()
		return
	end

	playSound("Start")
	enterSelectedMode()
end

startClassicLevelFromSelector = function(levelNumber)
	local resolvedLevel = math.clamp(math.floor(tonumber(levelNumber) or 1), 1, #Dependencies.Levels)
	local unlockedLevel = ClassicLevels.getClassicUnlockedLevel(state, Dependencies)
	local continueLevel = RuntimeHelpers.getClassicContinueLevel()
	local activeClassicBoardLevel = nil
	if state.currentPuzzle ~= nil and state.mode == "Classic" and not state.gameEnded then
		activeClassicBoardLevel = math.clamp(math.floor(tonumber(state.puzzleIndex) or 1), 1, #Dependencies.Levels)
	end
	local savedClassicBoardLevel = nil
	if type(state.resumeBoardState) == "table" and state.resumeBoardState.mode == "Classic" then
		savedClassicBoardLevel = math.clamp(math.floor(tonumber(state.resumeBoardState.level) or 1), 1, #Dependencies.Levels)
	end
	local hasPendingClassicBoard = activeClassicBoardLevel ~= nil or savedClassicBoardLevel ~= nil
	local hasSelectedClassicBoard = activeClassicBoardLevel == resolvedLevel or savedClassicBoardLevel == resolvedLevel

	if resolvedLevel > unlockedLevel then
		showDesktopAlert("Locked", "Finish earlier levels first.", "info", {
			duration = 2.1,
		})
		return
	end

	if resolvedLevel == continueLevel and hasSelectedClassicBoard then
		hideClassicLevelsFrame(true, function()
			playSound("Start")
			enterSelectedMode()
		end)
		return
	end

	if hasPendingClassicBoard then
		state.resumeBoardState = nil
		state.pendingResumeBoardState = nil
		trackServerAction("BoardStateCleared", {})
	end

	RuntimeHelpers.resetBoardRuntimeForFreshMode("Classic")
	hideClassicLevelsFrame(true, function()
		playSound("Start")
		showGameView(true, function()
			RuntimeHelpers.beginModeRun("Classic", true, resolvedLevel)
		end)
	end)
end

function RuntimeHelpers.bindClassicLevelsFrameActions()
	ButtonUi.prepare(ui.levelsCloseButton, nil, 0)
	if ui.levelsCloseButton and not ui.levelsCloseButton:GetAttribute("WordSearchBound") then
		ui.levelsCloseButton:SetAttribute("WordSearchBound", true)
		ui.levelsCloseButton.Activated:Connect(function()
			hideClassicLevelsFrame(true)
		end)
	end
end

return {
	chooseModeLevelIndex = chooseModeLevelIndex,
	buildPuzzleDefinition = buildPuzzleDefinition,
	ensureTileVisuals = ensureTileVisuals,
	cellKey = cellKey,
	currentSelection = currentSelection,
	countFoundWords = countFoundWords,
	countHintedWords = countHintedWords,
	updateWordsLabel = updateWordsLabel,
	updateHud = updateHud,
	pulseScale = pulseScale,
	clearDrag = clearDrag,
	resetWordListUi = resetWordListUi,
	showDesktopAlert = showDesktopAlert,
	syncBoardProgress = syncBoardProgress,
	transitionToPuzzle = transitionToPuzzle,
	loadPreparedPuzzle = loadPreparedPuzzle,
	performPuzzleLoad = performPuzzleLoad,
	startMode = startMode,
	handleMenuPlayPressed = handleMenuPlayPressed,
	startClassicLevelFromSelector = startClassicLevelFromSelector,
	setStatus = setStatus,
	getWordColor = getWordColor,
	assignWordColors = assignWordColors,
	addScore = addScore,
	getTileCenter = getTileCenter,
	pathMatches = pathMatches,
	snapTargetFromPosition = snapTargetFromPosition,
	selectionLookup = selectionLookup,
	createDragLineObjects = createDragLineObjects,
	refreshPersistentLines = refreshPersistentLines,
	animateWrongSelection = animateWrongSelection,
	keepCurrentDragLineAsFound = keepCurrentDragLineAsFound,
	clearHint = clearHint,
	setHintWord = setHintWord,
	clearHintWord = clearHintWord,
	nextHintTarget = nextHintTarget,
	applyResumeStateToCurrentPuzzle = applyResumeStateToCurrentPuzzle,
}
end

return module
