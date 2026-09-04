local module = {}

function module.create(env)
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

return module
