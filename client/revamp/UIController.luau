--!nocheck

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(assert(script.Parent:WaitForChild("Theme", 10), "Word Search Theme module is missing"))
local AnimationController = require(assert(script.Parent:WaitForChild("AnimationController", 10), "Word Search AnimationController is missing"))
local AudioController = require(assert(script.Parent:WaitForChild("AudioController", 10), "Word Search AudioController is missing"))

local UIController = {}
UIController.__index = UIController

local DEFAULT_SETTINGS = {
	music = true,
	sfx = true,
	reducedMotion = false,
	highContrast = false,
}

local DEFAULT_CHAPTERS = {
	{
		id = "animals",
		title = "Animals",
		description = "Friendly creatures and wild discoveries.",
		unlocked = true,
		levels = {
			{ id = "animals_1", number = 1, stars = 0, state = "available" },
			{ id = "animals_2", number = 2, stars = 0, state = "locked" },
			{ id = "animals_3", number = 3, stars = 0, state = "locked" },
		},
	},
	{
		id = "food",
		title = "Food",
		description = "Tasty words served one board at a time.",
		unlocked = false,
		levels = {
			{ id = "food_1", number = 1, stars = 0, state = "locked" },
			{ id = "food_2", number = 2, stars = 0, state = "locked" },
		},
	},
	{
		id = "nature",
		title = "Nature",
		description = "Forests, weather, and the world outdoors.",
		unlocked = false,
		levels = { { id = "nature_1", number = 1, stars = 0, state = "locked" } },
	},
	{
		id = "space",
		title = "Space",
		description = "Planets, stars, and deep-space challenges.",
		unlocked = false,
		levels = { { id = "space_1", number = 1, stars = 0, state = "locked" } },
	},
	{
		id = "expert",
		title = "Expert",
		description = "Long words, reversals, and dense overlaps.",
		unlocked = false,
		levels = { { id = "expert_1", number = 1, stars = 0, state = "locked" } },
	},
}

local DEFAULT_GRID = {
	{ "R", "O", "B", "L", "O", "X", "Q", "T" },
	{ "P", "U", "Z", "Z", "L", "E", "A", "R" },
	{ "W", "O", "R", "D", "S", "N", "M", "E" },
	{ "G", "R", "I", "D", "F", "U", "N", "E" },
	{ "C", "O", "D", "E", "P", "L", "A", "Y" },
	{ "S", "E", "A", "R", "C", "H", "K", "S" },
	{ "H", "I", "N", "T", "D", "A", "I", "L" },
	{ "S", "T", "A", "R", "G", "A", "M", "E" },
}

local function create(className, props)
	local instance = Instance.new(className)
	instance.Name = props.Name or className
	for property, value in pairs(props) do
		if property ~= "Name" and property ~= "Parent" then
			instance[property] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function clearInstances(instances)
	for _, instance in ipairs(instances) do
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
	table.clear(instances)
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return string.format("%02d:%02d:%02d", hours, minutes, seconds % 60)
end

local function clampInteger(value, minimum, maximum)
	return math.clamp(math.floor(tonumber(value) or minimum), minimum, maximum)
end

local function cellKey(row, column)
	return tostring(row) .. ":" .. tostring(column)
end

local function normalizeSettings(settings)
	settings = settings or {}
	return {
		music = if settings.music ~= nil then settings.music == true else if settings.Music ~= nil then settings.Music == true else DEFAULT_SETTINGS.music,
		sfx = if settings.sfx ~= nil then settings.sfx == true else if settings.SFX ~= nil then settings.SFX == true else DEFAULT_SETTINGS.sfx,
		reducedMotion = if settings.reducedMotion ~= nil then settings.reducedMotion == true else if settings.ReducedMotion ~= nil then settings.ReducedMotion == true else DEFAULT_SETTINGS.reducedMotion,
		highContrast = if settings.highContrast ~= nil then settings.highContrast == true else if settings.HighContrast ~= nil then settings.HighContrast == true else DEFAULT_SETTINGS.highContrast,
	}
end

local function normalizeImageId(value)
	if type(value) == "number" and value > 0 then
		return "rbxassetid://" .. tostring(math.floor(value))
	end
	if type(value) ~= "string" or value == "" then
		return nil
	end
	if string.match(value, "^%d+$") then
		return "rbxassetid://" .. value
	end
	if string.match(value, "^rbxassetid://%d+$") or string.match(value, "^rbxthumb://") then
		return value
	end
	return nil
end

local function copySettings(settings)
	return {
		music = settings.music,
		sfx = settings.sfx,
		reducedMotion = settings.reducedMotion,
		highContrast = settings.highContrast,
	}
end

local function normalizeCell(value)
	if type(value) ~= "table" then
		return nil
	end
	local row = math.floor(tonumber(value.row or value.Row) or 0)
	local column = math.floor(tonumber(value.column or value.Column) or 0)
	if row < 1 or column < 1 then
		return nil
	end
	return { row = row, column = column }
end

local function normalizeLetters(round)
	local source = round and (round.letters or round.grid)
	if type(source) ~= "table" or #source == 0 then
		return DEFAULT_GRID
	end

	local rows = {}
	for _, sourceRow in ipairs(source) do
		local row = {}
		if type(sourceRow) == "string" then
			for index = 1, #sourceRow do
				table.insert(row, string.upper(string.sub(sourceRow, index, index)))
			end
		elseif type(sourceRow) == "table" then
			for _, letter in ipairs(sourceRow) do
				table.insert(row, string.upper(string.sub(tostring(letter or "?"), 1, 1)))
			end
		end
		if #row > 0 then
			table.insert(rows, row)
		end
	end
	return if #rows > 0 then rows else DEFAULT_GRID
end

function UIController.new(playerGui, options)
	assert(playerGui and playerGui:IsA("PlayerGui"), "UIController.new expects a PlayerGui")
	options = options or {}
	local self = setmetatable({}, UIController)
	self._options = options
	self._gameConfig = type(options.gameConfig) == "table" and options.gameConfig or {}
	self._playerGui = playerGui
	self._callbacks = {}
	self._connections = {}
	self._cameraConnections = {}
	self._levelConnections = {}
	self._cellConnections = {}
	self._dynamicInstances = {}
	self._levelInstances = {}
	self._cellInstances = {}
	self._styles = {}
	self._levelStyles = {}
	self._cellStyles = {}
	self._textRoles = {}
	self._levelTextRoles = {}
	self._cellTextRoles = {}
	self._screens = {}
	self._modals = {}
	self._refs = {}
	self._settings = normalizeSettings(options.settings)
	self._palette = Theme.GetPalette(self._settings.highContrast)
	self._usingGamepad = false
	self._layout = Theme.ResolveLayout(Vector2.new(1280, 720), false)
	self._activePage = nil
	self._activeModal = nil
	self._modalPreviousFocus = nil
	self._modalReturnName = nil
	self._modalReturnFocus = nil
	self._inputEnabled = false
	self._destroyed = false
	self._currentRound = nil
	self._chapters = DEFAULT_CHAPTERS
	self._cells = {}
	self._gridWidth = 0
	self._gridHeight = 0
	self._boardCellSize = 0
	self._boardCellGap = 0
	self._recentSelection = {}
	self._trailSelection = {}
	self._hoveredKey = nil
	self._hoveredCell = nil
	self._cellStates = {}
	self._wordRows = {}
	self._foundWords = {}
	self._expandedChapterId = nil
	self._renderedStatus = {}
	self._resultToken = 0
	self._tutorialToken = 0
	self._toastSerial = 0
	self._confirmation = nil
	self._errorRetry = nil
	self._inputEnabledEvent = Instance.new("BindableEvent")

	self._ownsAnimation = options.animationController == nil
	self._animation = options.animationController or AnimationController.new({
		reducedMotion = self._settings.reducedMotion,
	})
	self._ownsAudio = options.audioController == nil
	self._audio = options.audioController or AudioController.new({
		gameConfig = options.gameConfig,
		settings = self._settings,
	})

	self:_buildRoot()
	self:_buildLoading()
	self:_buildMenu()
	self:_buildLevels()
	self:_buildDaily()
	self:_buildGame()
	self:_buildModals()
	self:_buildToastLayer()
	self:_bindResponsiveSignals()
	self:SetCallbacks(options.callbacks or {})
	self:SetSettings(self._settings)
	self:ShowLoading("Preparing your puzzles…", 0)
	return self
end

function UIController:_track(connection, bucket)
	table.insert(bucket or self._connections, connection)
	return connection
end

function UIController:_style(instance, property, token, bucket)
	local binding = { instance = instance, property = property, token = token }
	table.insert(bucket or self._styles, binding)
	if instance and instance.Parent and self._palette[token] then
		instance[property] = self._palette[token]
	end
	return instance
end

function UIController:_registerText(textObject, role, bucket)
	table.insert(bucket or self._textRoles, { instance = textObject, role = role })
	textObject.TextSize = Theme.GetTextSize(role, self._layout)
	return textObject
end

function UIController:_corner(parent, radius)
	return create("UICorner", {
		Name = "Corner",
		CornerRadius = UDim.new(0, radius or Theme.Radii.Medium),
		Parent = parent,
	})
end

function UIController:_stroke(parent, token, thickness, bucket)
	local stroke = create("UIStroke", {
		Name = "Stroke",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = thickness or 1,
		Transparency = 0,
		Parent = parent,
	})
	self:_style(stroke, "Color", token or "Border", bucket)
	return stroke
end

function UIController:_frame(parent, name, token, props, bucket)
	props = props or {}
	props.Name = name
	props.Parent = parent
	props.BorderSizePixel = 0
	if token then
		props.BackgroundColor3 = self._palette[token]
	else
		props.BackgroundTransparency = props.BackgroundTransparency or 1
	end
	local frame = create("Frame", props)
	if token then
		self:_style(frame, "BackgroundColor3", token, bucket)
	end
	return frame
end

function UIController:_label(parent, name, text, role, token, props, bucket, textBucket)
	props = props or {}
	props.Name = name
	props.Parent = parent
	props.BackgroundTransparency = props.BackgroundTransparency == nil and 1 or props.BackgroundTransparency
	props.BorderSizePixel = 0
	props.Font = props.Font or (role == "Display" and Theme.Fonts.Display or role == "Title" and Theme.Fonts.Heading or Theme.Fonts.Body)
	props.Text = tostring(text or "")
	props.TextColor3 = self._palette[token or "Text"]
	props.TextSize = Theme.GetTextSize(role or "Body", self._layout)
	local label = create("TextLabel", props)
	self:_style(label, "TextColor3", token or "Text", bucket)
	self:_registerText(label, role or "Body", textBucket)
	return label
end

function UIController:_button(parent, name, text, token, onActivated, props, bucket, styleBucket, textBucket)
	props = props or {}
	props.Name = name
	props.Parent = parent
	props.AutoButtonColor = false
	props.BackgroundColor3 = self._palette[token or "PanelRaised"]
	props.BorderSizePixel = 0
	props.Font = props.Font or Theme.Fonts.Heading
	props.Selectable = props.Selectable ~= false
	props.Text = tostring(text or "")
	props.TextColor3 = self._palette.Text
	props.TextSize = Theme.GetTextSize("Button", self._layout)
	props.Size = props.Size or UDim2.fromOffset(220, Theme.Metrics.MinTouchTarget)
	local button = create("TextButton", props)
	button:SetAttribute("ThemeToken", token or "PanelRaised")
	self:_style(button, "BackgroundColor3", token or "PanelRaised", styleBucket)
	self:_style(button, "TextColor3", "Text", styleBucket)
	self:_registerText(button, "Button", textBucket)
	self:_corner(button, Theme.Radii.Medium)
	local border = self:_stroke(button, if token == "Accent" then "AccentHover" else "Border", 1, styleBucket)
	border.Transparency = 0.25
	local focusStroke = self:_stroke(button, "Focus", 3, styleBucket)
	focusStroke.Name = "FocusStroke"
	focusStroke.Enabled = false

	local function setHover(hovered)
		if self._destroyed or button.Parent == nil or button.Active == false then
			return
		end
		local baseToken = button:GetAttribute("ThemeToken") or "PanelRaised"
		local hoverToken = if baseToken == "Accent" then "AccentHover" else "PanelHover"
		self._animation:Tween(button, {
			BackgroundColor3 = self._palette[if hovered then hoverToken else baseToken],
		}, "Fast")
	end

	self:_track(button.MouseEnter:Connect(function()
		setHover(true)
	end), bucket)
	self:_track(button.MouseLeave:Connect(function()
		setHover(false)
	end), bucket)
	self:_track(button.SelectionGained:Connect(function()
		focusStroke.Enabled = true
		self._animation:Pulse(button, { peakScale = 1.025 })
	end), bucket)
	self:_track(button.SelectionLost:Connect(function()
		focusStroke.Enabled = false
	end), bucket)
	self:_track(button.MouseButton1Down:Connect(function()
		if button.Active then
			local scale = button:FindFirstChild("RevampScale") or create("UIScale", { Name = "RevampScale", Parent = button })
			self._animation:Tween(scale, { Scale = 0.97 }, "Fast")
		end
	end), bucket)
	self:_track(button.MouseButton1Up:Connect(function()
		local scale = button:FindFirstChild("RevampScale")
		if scale then
			self._animation:Tween(scale, { Scale = 1 }, "Fast")
		end
	end), bucket)
	self:_track(button.Activated:Connect(function()
		if not button.Active or self._destroyed then
			return
		end
		self._audio:Play("Button", { volume = 0.7 })
		if onActivated then
			onActivated()
		end
	end), bucket)
	return button
end

function UIController:_linkVertical(buttons)
	for index, button in ipairs(buttons) do
		button.NextSelectionUp = buttons[index - 1] or buttons[#buttons]
		button.NextSelectionDown = buttons[index + 1] or buttons[1]
	end
end

function UIController:_page(name)
	local page = self:_frame(self._refs.pageLayer, name, nil, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 2,
	})
	self._screens[name] = page
	return page
end

function UIController:_buildRoot()
	local screenGui = create("ScreenGui", {
		Name = self._options.name or "WordSearchRevampHUD",
		DisplayOrder = tonumber(self._options.displayOrder) or 20,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		Parent = self._playerGui,
	})
	screenGui:SetAttribute("WordSearchRevampOwned", true)
	pcall(function()
		screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	self._refs.screenGui = screenGui

	local root = self:_frame(screenGui, "AppShell", "Background", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 1,
	})
	self._refs.root = root

	local backdrop = self:_frame(root, "BackdropAccent", "AccentDark", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.12, 0.08),
		Size = UDim2.fromScale(0.5, 0.6),
		BackgroundTransparency = 0.82,
		Rotation = -12,
		ZIndex = 1,
	})
	self:_corner(backdrop, Theme.Radii.Large)

	self._refs.pageLayer = self:_frame(root, "Pages", nil, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})
	self._refs.modalLayer = self:_frame(root, "Modals", nil, {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
	})
end

function UIController:_buildLoading()
	local page = self:_page("Loading")
	local card = self:_frame(page, "LoadingCard", "Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 270),
		ZIndex = 3,
	})
	self:_corner(card, Theme.Radii.Large)
	self:_stroke(card, "Border", 1)
	create("UISizeConstraint", {
		Name = "SizeConstraint",
		MinSize = Vector2.new(280, 230),
		MaxSize = Vector2.new(520, 320),
		Parent = card,
	})

	local logo = self:_frame(card, "LogoPlaceholder", "Accent", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.fromOffset(72, 72),
		ZIndex = 4,
	})
	self:_corner(logo, Theme.Radii.Large)
	local assets = type(self._gameConfig.Assets) == "table" and self._gameConfig.Assets or {}
	local logoImage = normalizeImageId(assets.LogoImage)
	if logoImage then
		create("ImageLabel", {
			Name = "LogoImage",
			BackgroundTransparency = 1,
			Image = logoImage,
			Position = UDim2.fromScale(0, 0),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
			Parent = logo,
		})
	else
		self:_label(logo, "Letter", "W", "Display", "Text", {
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 5,
		})
	end

	self:_label(card, "Title", "WORD SEARCH", "Title", "Text", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 114),
		Size = UDim2.new(1, -40, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	self._refs.loadingMessage = self:_label(card, "Message", "Preparing your puzzles…", "Body", "TextMuted", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 156),
		Size = UDim2.new(1, -48, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	local progress = self:_frame(card, "ProgressTrack", "BackgroundRaised", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 207),
		Size = UDim2.new(1, -64, 0, 10),
		ClipsDescendants = true,
		ZIndex = 4,
	})
	self:_corner(progress, Theme.Radii.Pill)
	self._refs.loadingFill = self:_frame(progress, "Fill", "Accent", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0, 1),
		ZIndex = 5,
	})
	self:_corner(self._refs.loadingFill, Theme.Radii.Pill)
	self._refs.loadingCard = card
end

function UIController:_buildMenu()
	local page = self:_page("Menu")
	local header = self:_frame(page, "Header", "BackgroundRaised", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, Theme.Metrics.TopBarHeight),
		ZIndex = 3,
	})
	self:_style(header, "BackgroundColor3", "BackgroundRaised")
	self:_label(header, "Brand", "WORD SEARCH", "Title", "Text", {
		Position = UDim2.new(0, 24, 0, 0),
		Size = UDim2.new(0.5, -24, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	local profile = self:_frame(header, "ProfileSummary", "Panel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -24, 0.5, 0),
		Size = UDim2.fromOffset(240, 52),
		ZIndex = 4,
	})
	self:_corner(profile, Theme.Radii.Medium)
	self:_stroke(profile, "Border", 1)
	self._refs.menuProfileName = self:_label(profile, "Name", "PLAYER", "Small", "Text", {
		Position = UDim2.new(0, 14, 0, 5),
		Size = UDim2.new(1, -28, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})
	self._refs.menuProfileRank = self:_label(profile, "Rank", "Rank 1", "Caption", "Gold", {
		Position = UDim2.new(0, 14, 0, 27),
		Size = UDim2.new(1, -28, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
	})

	local body = create("ScrollingFrame", {
		Name = "Body",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.new(0, 0, 0, Theme.Metrics.TopBarHeight),
		ScrollBarImageColor3 = self._palette.BorderStrong,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = false,
		Size = UDim2.new(1, 0, 1, -Theme.Metrics.TopBarHeight),
		ZIndex = 3,
		Parent = page,
	})
	self:_style(body, "ScrollBarImageColor3", "BorderStrong")
	self._refs.menuBody = body
	local hero = self:_frame(body, "Hero", nil, {
		Position = UDim2.fromScale(0.06, 0.08),
		Size = UDim2.fromScale(0.42, 0.5),
		ZIndex = 3,
	})
	self._refs.menuHero = hero
	self:_label(hero, "Eyebrow", "A CALM DAILY CHALLENGE", "Small", "Accent", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
	})
	self:_label(hero, "Headline", "Find. Relax.\nRepeat.", "Display", "Text", {
		Position = UDim2.new(0, 0, 0, 32),
		Size = UDim2.new(1, 0, 0, 112),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})
	self:_label(hero, "Subheading", "Drag across letters, discover every word, and build your collection of stars.", "Body", "TextMuted", {
		Position = UDim2.new(0, 0, 0, 154),
		Size = UDim2.new(1, -20, 0, 62),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 4,
	})

	local actions = self:_frame(body, "Actions", "Panel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.94, 0.08),
		Size = UDim2.fromScale(0.4, 0.56),
		ZIndex = 3,
	})
	self._refs.menuActions = actions
	self:_corner(actions, Theme.Radii.Large)
	self:_stroke(actions, "Border", 1)
	local actionPadding = create("UIPadding", {
		PaddingTop = UDim.new(0, 20),
		PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 20),
		PaddingRight = UDim.new(0, 20),
		Parent = actions,
	})
	local actionLayout = create("UIListLayout", {
		Padding = UDim.new(0, 10),
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = actions,
	})
	self._refs.menuActionPadding = actionPadding
	self._refs.menuActionLayout = actionLayout

	local play = self:_button(actions, "Play", "▶  PLAY NOW", "Accent", function()
		self:_emit("onPlay")
	end, { Size = UDim2.new(1, 0, 0, 62), LayoutOrder = 1, ZIndex = 4 })
	local levels = self:_button(actions, "Levels", "LEVELS", "PanelRaised", function()
		self:_emit("onLevels")
	end, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2, ZIndex = 4 })
	local daily = self:_button(actions, "Daily", "DAILY PUZZLE", "PanelRaised", function()
		self:_emit("onDaily")
	end, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 3, ZIndex = 4 })
	local settings = self:_button(actions, "Settings", "SETTINGS", "PanelRaised", function()
		self:_emit("onSettings")
		self:ShowSettings()
	end, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 4, ZIndex = 4 })
	self._refs.menuFirstButton = play
	self:_linkVertical({ play, levels, daily, settings })

	local progressPanel = self:_frame(body, "Progress", "BackgroundRaised", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.95),
		Size = UDim2.fromScale(0.88, 0.22),
		ZIndex = 3,
	})
	self._refs.menuProgressPanel = progressPanel
	self:_corner(progressPanel, Theme.Radii.Large)
	self:_stroke(progressPanel, "Border", 1)
	local progressGrid = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(10, 10),
		CellSize = UDim2.new(0.25, -13, 1, -20),
		FillDirectionMaxCells = 4,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = progressPanel,
	})
	self._refs.menuProgressGrid = progressGrid
	local progressSpecs = {
		{ key = "Rank", title = "RANK", value = "1", token = "Gold" },
		{ key = "Stars", title = "TOTAL STARS", value = "0", token = "Gold" },
		{ key = "Solved", title = "PUZZLES SOLVED", value = "0", token = "Success" },
		{ key = "Streak", title = "DAILY STREAK", value = "0 days", token = "Accent" },
	}
	self._refs.menuProgressValues = {}
	for index, spec in ipairs(progressSpecs) do
		local card = self:_frame(progressPanel, spec.key, "Panel", { LayoutOrder = index, ZIndex = 4 })
		self:_corner(card, Theme.Radii.Medium)
		self:_label(card, "Title", spec.title, "Caption", "TextMuted", {
			Position = UDim2.new(0, 12, 0, 10), Size = UDim2.new(1, -24, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
		})
		self._refs.menuProgressValues[string.lower(spec.key)] = self:_label(card, "Value", spec.value, "Heading", spec.token, {
			Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 1, -36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
		})
	end
end

function UIController:_buildPageHeader(page, title, onBack)
	local header = self:_frame(page, "Header", "BackgroundRaised", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, Theme.Metrics.TopBarHeight),
		ZIndex = 3,
	})
	local back = self:_button(header, "Back", "‹  BACK", "PanelRaised", onBack, {
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(112, Theme.Metrics.MinTouchTarget),
		ZIndex = 4,
	})
	self:_label(header, "Title", title, "Title", "Text", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.55, 0, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	})
	return header, back
end

function UIController:_buildLevels()
	local page = self:_page("Levels")
	local header, back = self:_buildPageHeader(page, "CLASSIC LEVELS", function()
		self:_emit("onBack", "Levels")
		self:ShowMenu()
	end)
	self._refs.levelsBack = back
	self._refs.levelsStars = self:_label(header, "TotalStars", "★ 0", "Heading", "Gold", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 0),
		Size = UDim2.fromOffset(150, 42),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 4,
	})

	local scroll = create("ScrollingFrame", {
		Name = "ChapterList",
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0, 0, 0, Theme.Metrics.TopBarHeight),
		ScrollBarImageColor3 = self._palette.BorderStrong,
		ScrollBarThickness = 8,
		Size = UDim2.new(1, 0, 1, -Theme.Metrics.TopBarHeight),
		ZIndex = 3,
		Parent = page,
	})
	self:_style(scroll, "ScrollBarImageColor3", "BorderStrong")
	create("UIPadding", {
		PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 28), PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), Parent = scroll,
	})
	local layout = create("UIListLayout", {
		Padding = UDim.new(0, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	self._refs.levelsScroll = scroll
	self._refs.levelsLayout = layout
end

function UIController:_buildDaily()
	local page = self:_page("Daily")
	local _, back = self:_buildPageHeader(page, "DAILY PUZZLE", function()
		self:_emit("onBack", "Daily")
		self:ShowMenu()
	end)
	self._refs.dailyBack = back
	local card = self:_frame(page, "DailyCard", "Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromOffset(620, 440),
		ZIndex = 3,
	})
	self:_corner(card, Theme.Radii.Large)
	self:_stroke(card, "Border", 1)
	create("UISizeConstraint", { MinSize = Vector2.new(300, 390), MaxSize = Vector2.new(720, 520), Parent = card })
	self:_label(card, "Badge", "TODAY'S CHALLENGE", "Small", "Accent", {
		Position = UDim2.new(0, 28, 0, 26), Size = UDim2.new(1, -56, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	self._refs.dailyTitle = self:_label(card, "Title", "A fresh puzzle awaits", "Title", "Text", {
		Position = UDim2.new(0, 28, 0, 62), Size = UDim2.new(1, -56, 0, 44), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	self._refs.dailyDescription = self:_label(card, "Description", "Everyone gets the same board. Complete it before midnight UTC.", "Body", "TextMuted", {
		Position = UDim2.new(0, 44, 0, 112), Size = UDim2.new(1, -88, 0, 58), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	local statRow = self:_frame(card, "Stats", nil, {
		Position = UDim2.new(0, 28, 0, 190), Size = UDim2.new(1, -56, 0, 90), ZIndex = 4,
	})
	local statsGrid = create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(10, 0), CellSize = UDim2.new(1 / 3, -7, 1, 0), FillDirectionMaxCells = 3, Parent = statRow,
	})
	local statSpecs = { { "Streak", "STREAK", "0 days", "Gold" }, { "Reward", "REWARD", "+1 Hint", "Success" }, { "Reset", "RESETS IN", "--:--", "Text" } }
	for index, spec in ipairs(statSpecs) do
		local stat = self:_frame(statRow, spec[1], "BackgroundRaised", { LayoutOrder = index, ZIndex = 4 })
		self:_corner(stat, Theme.Radii.Medium)
		self:_label(stat, "Title", spec[2], "Caption", "TextMuted", { Position = UDim2.new(0, 8, 0, 10), Size = UDim2.new(1, -16, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
		self._refs["daily" .. spec[1]] = self:_label(stat, "Value", spec[3], "Heading", spec[4], { Position = UDim2.new(0, 8, 0, 34), Size = UDim2.new(1, -16, 0, 36), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	end
	self._refs.dailyStatus = self:_label(card, "Status", "Not completed today", "Body", "TextMuted", {
		Position = UDim2.new(0, 28, 0, 296), Size = UDim2.new(1, -56, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4,
	})
	self._refs.dailyPlay = self:_button(card, "PlayDaily", "PLAY DAILY PUZZLE", "Accent", function()
		self:_emit("onDailyPlay")
	end, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, -72, 0, 58), ZIndex = 4,
	})
end

function UIController:_buildGame()
	local page = self:_page("Game")
	local topBar = self:_frame(page, "TopBar", "BackgroundRaised", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.new(1, 0, 0, Theme.Metrics.TopBarHeight),
		ZIndex = 10,
	})
	self._refs.gameTopBar = topBar
	self._refs.pauseButton = self:_button(topBar, "Pause", "Ⅱ", "PanelRaised", function()
		self:_emit("onPause")
		self:ShowPause()
	end, {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(Theme.Metrics.MinTouchTarget, Theme.Metrics.MinTouchTarget), ZIndex = 11,
	})
	self._refs.gameTitle = self:_label(topBar, "Title", "Word Search", "Heading", "Text", {
		Position = UDim2.new(0, 78, 0, 8), Size = UDim2.new(0.5, -78, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
	})
	self._refs.gameSubtitle = self:_label(topBar, "Subtitle", "Classic • Easy", "Small", "TextMuted", {
		Position = UDim2.new(0, 78, 0, 37), Size = UDim2.new(0.5, -78, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11,
	})

	local timerChip = self:_frame(topBar, "Timer", "Panel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -154, 0.5, 0), Size = UDim2.fromOffset(126, 50), ZIndex = 11,
	})
	self:_corner(timerChip, Theme.Radii.Medium)
	self:_stroke(timerChip, "Border", 1)
	self:_label(timerChip, "Caption", "TIME", "Caption", "TextMuted", {
		Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12,
	})
	self._refs.gameTimer = self:_label(timerChip, "Value", "00:00", "Heading", "Text", {
		Position = UDim2.new(0, 10, 0, 19), Size = UDim2.new(1, -20, 0, 27), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12,
	})
	self._refs.timerChip = timerChip

	local progressChip = self:_frame(topBar, "Progress", "Panel", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(126, 50), ZIndex = 11,
	})
	self:_corner(progressChip, Theme.Radii.Medium)
	self:_stroke(progressChip, "Border", 1)
	self:_label(progressChip, "Caption", "FOUND", "Caption", "TextMuted", {
		Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12,
	})
	self._refs.gameProgressText = self:_label(progressChip, "Value", "0 / 0", "Heading", "Success", {
		Position = UDim2.new(0, 10, 0, 19), Size = UDim2.new(1, -20, 0, 27), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 12,
	})
	self._refs.progressChip = progressChip

	local content = self:_frame(page, "Content", nil, {
		Position = UDim2.new(0, 0, 0, Theme.Metrics.TopBarHeight),
		Size = UDim2.new(1, 0, 1, -Theme.Metrics.TopBarHeight),
		ZIndex = 3,
	})
	self._refs.gameContent = content
	local boardCard = self:_frame(content, "BoardCard", "Panel", {
		Position = UDim2.new(0, 20, 0, 20),
		Size = UDim2.new(1, -(Theme.Metrics.SidebarWidth + 60), 1, -40),
		ClipsDescendants = true,
		ZIndex = 3,
	})
	self:_corner(boardCard, Theme.Radii.Large)
	self:_stroke(boardCard, "Border", 1)
	self._refs.boardCard = boardCard

	local boardViewport = create("ScrollingFrame", {
		Name = "BoardViewport",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		Position = UDim2.new(0, 12, 0, 12),
		ScrollBarImageColor3 = self._palette.BorderStrong,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		Size = UDim2.new(1, -24, 1, -24),
		ZIndex = 4,
		Parent = boardCard,
	})
	self:_style(boardViewport, "ScrollBarImageColor3", "BorderStrong")
	self._refs.boardViewport = boardViewport
	local boardCanvas = self:_frame(boardViewport, "BoardCanvas", nil, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 4,
	})
	self._refs.boardCanvas = boardCanvas
	local cellLayer = self:_frame(boardCanvas, "CellLayer", nil, {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 4,
	})
	local cellLayout = create("UIGridLayout", {
		Name = "GridLayout",
		CellPadding = UDim2.fromOffset(4, 4),
		CellSize = UDim2.fromOffset(Theme.Metrics.MinTouchTarget, Theme.Metrics.MinTouchTarget),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 8,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = cellLayer,
	})
	self._refs.cellLayer = cellLayer
	self._refs.cellLayout = cellLayout
	local trailLayer = self:_frame(boardCanvas, "SelectionTrailLayer", nil, {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 5,
	})
	local trail = self:_frame(trailLayer, "SelectionTrail", "Accent", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 0.22,
		Visible = false,
		ZIndex = 5,
	})
	self:_corner(trail, Theme.Radii.Pill)
	self._refs.trailLayer = trailLayer
	self._refs.selectionTrail = trail

	local wordPanel = self:_frame(content, "WordPanel", "Panel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.new(0, Theme.Metrics.SidebarWidth, 1, -40),
		ZIndex = 3,
	})
	self:_corner(wordPanel, Theme.Radii.Large)
	self:_stroke(wordPanel, "Border", 1)
	self._refs.wordPanel = wordPanel
	self._refs.wordTitle = self:_label(wordPanel, "Title", "WORDS TO FIND", "Heading", "Text", {
		Position = UDim2.new(0, 18, 0, 15), Size = UDim2.new(1, -36, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	self._refs.wordCount = self:_label(wordPanel, "Count", "0 remaining", "Small", "TextMuted", {
		Position = UDim2.new(0, 18, 0, 45), Size = UDim2.new(1, -36, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4,
	})
	local wordScroll = create("ScrollingFrame", {
		Name = "WordList",
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0, 12, 0, 76),
		ScrollBarImageColor3 = self._palette.BorderStrong,
		ScrollBarThickness = 6,
		Size = UDim2.new(1, -24, 1, -216),
		ZIndex = 4,
		Parent = wordPanel,
	})
	self:_style(wordScroll, "ScrollBarImageColor3", "BorderStrong")
	create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 6), Parent = wordScroll })
	create("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wordScroll })
	self._refs.wordScroll = wordScroll

	self._refs.gameStatus = self:_label(wordPanel, "Status", "Drag across a word to begin.", "Small", "TextMuted", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -128), Size = UDim2.new(1, -36, 0, 42), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, ZIndex = 4,
	})
	local progressTrack = self:_frame(wordPanel, "ProgressTrack", "BackgroundRaised", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -92), Size = UDim2.new(1, -36, 0, 9), ClipsDescendants = true, ZIndex = 4,
	})
	self:_corner(progressTrack, Theme.Radii.Pill)
	self._refs.gameProgressFill = self:_frame(progressTrack, "Fill", "Success", {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0, 1), ZIndex = 5,
	})
	self:_corner(self._refs.gameProgressFill, Theme.Radii.Pill)
	self._refs.hintButton = self:_button(wordPanel, "Hint", "HINT  •  0", "Accent", function()
		self:_emit("onHint")
	end, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.new(1, -36, 0, 58), ZIndex = 4,
	})
end

function UIController:_modal(name, title, cardSize)
	local overlay = self:_frame(self._refs.modalLayer, name, "Overlay", {
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.28,
		Visible = false,
		ZIndex = 100,
	})
	overlay.Active = true
	local card = self:_frame(overlay, "Card", "Panel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = cardSize or UDim2.fromOffset(500, 420),
		ZIndex = 101,
	})
	self:_corner(card, Theme.Radii.Large)
	self:_stroke(card, "BorderStrong", 1)
	create("UISizeConstraint", { MinSize = Vector2.new(290, 260), MaxSize = Vector2.new(720, 700), Parent = card })
	local titleLabel = self:_label(card, "Title", title, "Title", "Text", {
		Position = UDim2.new(0, 24, 0, 20),
		Size = UDim2.new(1, -48, 0, 42),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 102,
	})
	local modal = { overlay = overlay, card = card, title = titleLabel, firstButton = nil, baseSize = cardSize or UDim2.fromOffset(500, 420) }
	self._modals[name] = modal
	return modal
end

function UIController:_buildModals()
	local pause = self:_modal("Pause", "PAUSED", UDim2.fromOffset(450, 420))
	self:_label(pause.card, "Body", "Your puzzle is waiting.", "Body", "TextMuted", {
		Position = UDim2.new(0, 28, 0, 72), Size = UDim2.new(1, -56, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	local pauseButtons = self:_frame(pause.card, "Buttons", nil, { Position = UDim2.new(0, 36, 0, 126), Size = UDim2.new(1, -72, 1, -154), ZIndex = 102 })
	create("UIListLayout", { Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = pauseButtons })
	local resume = self:_button(pauseButtons, "Resume", "RESUME", "Accent", function()
		self:_closeModal("Pause")
		self:_emit("onResume")
	end, { Size = UDim2.new(1, 0, 0, 58), LayoutOrder = 1, ZIndex = 103 })
	local restart = self:_button(pauseButtons, "Restart", "RESTART PUZZLE", "PanelRaised", function()
		self:ShowConfirmation({
			title = "Restart puzzle?",
			message = "Your progress on this board will be reset.",
			confirmText = "RESTART",
			onConfirm = function()
				self:_emit("onRestart")
			end,
		})
	end, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2, ZIndex = 103 })
	local quit = self:_button(pauseButtons, "Menu", "MAIN MENU", "PanelRaised", function()
		self:ShowConfirmation({
			title = "Return to menu?",
			message = "Your progress on this board will be lost.",
			confirmText = "LEAVE",
			onConfirm = function()
				self:_emit("onQuit")
				self:_emit("onMenu")
			end,
		})
	end, { Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 3, ZIndex = 103 })
	pause.firstButton = resume
	self:_linkVertical({ resume, restart, quit })

	local settings = self:_modal("Settings", "SETTINGS", UDim2.fromOffset(540, 520))
	self:_label(settings.card, "Body", "Choose how the game looks and feels.", "Body", "TextMuted", {
		Position = UDim2.new(0, 28, 0, 67), Size = UDim2.new(1, -56, 0, 32), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	local settingsList = self:_frame(settings.card, "SettingsList", nil, { Position = UDim2.new(0, 28, 0, 112), Size = UDim2.new(1, -56, 1, -188), ZIndex = 102 })
	create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = settingsList })
	self._refs.settingButtons = {}
	local settingSpecs = {
		{ key = "music", title = "Music", description = "Background music" },
		{ key = "sfx", title = "Sound effects", description = "Button and gameplay sounds" },
		{ key = "reducedMotion", title = "Reduced motion", description = "Minimize movement and transitions" },
		{ key = "highContrast", title = "High contrast", description = "Stronger borders and color separation" },
	}
	for index, spec in ipairs(settingSpecs) do
		local row = self:_frame(settingsList, spec.key, "BackgroundRaised", { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = index, ZIndex = 102 })
		self:_corner(row, Theme.Radii.Medium)
		self:_label(row, "Title", spec.title, "Body", "Text", { Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -128, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 103 })
		self:_label(row, "Description", spec.description, "Caption", "TextMuted", { Position = UDim2.new(0, 14, 0, 34), Size = UDim2.new(1, -128, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 103 })
		local toggle = self:_button(row, "Toggle", "ON", "Success", function()
			self:_changeSetting(spec.key, not self._settings[spec.key])
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(92, Theme.Metrics.MinTouchTarget), ZIndex = 103 })
		self._refs.settingButtons[spec.key] = toggle
	end
	local settingsClose = self:_button(settings.card, "Close", "DONE", "Accent", function()
		self:_closeModal("Settings")
		self:_emit("onSettingsClosed", copySettings(self._settings))
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.new(1, -56, 0, 54), ZIndex = 102 })
	settings.firstButton = self._refs.settingButtons.music
	self:_linkVertical({ self._refs.settingButtons.music, self._refs.settingButtons.sfx, self._refs.settingButtons.reducedMotion, self._refs.settingButtons.highContrast, settingsClose })

	local tutorial = self:_modal("Tutorial", "HOW TO PLAY", UDim2.fromOffset(590, 560))
	self:_label(tutorial.card, "Instruction", "Drag in a straight line, then release to submit the word.", "Body", "TextMuted", {
		Position = UDim2.new(0, 36, 0, 70), Size = UDim2.new(1, -72, 0, 52), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	local demo = self:_frame(tutorial.card, "Demo", "BackgroundRaised", { Position = UDim2.new(0, 34, 0, 138), Size = UDim2.new(1, -68, 0, 185), ZIndex = 102 })
	self:_corner(demo, Theme.Radii.Large)
	self:_stroke(demo, "Border", 1)
	self:_label(demo, "Prompt", "Find WORD", "Small", "Gold", { Position = UDim2.new(0, 16, 0, 20), Size = UDim2.new(1, -32, 0, 24), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 103 })
	local demoTrail = self:_frame(demo, "SelectionTrail", "Accent", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, -148, 0.62, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundTransparency = 0.18,
		Visible = false,
		ZIndex = 104,
	})
	self:_corner(demoTrail, Theme.Radii.Pill)
	self._refs.tutorialTrail = demoTrail
	local demoCells = self:_frame(demo, "Cells", nil, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(304, 58), ZIndex = 103 })
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4), Parent = demoCells })
	self._refs.tutorialCells = {}
	for index, letter in ipairs({ "W", "O", "R", "D", "S" }) do
		local cell = self:_frame(demoCells, "Cell" .. tostring(index), "BoardCell", { Size = UDim2.fromOffset(56, 56), LayoutOrder = index, ZIndex = 103 })
		self:_corner(cell, Theme.Radii.Small)
		self:_stroke(cell, "Border", 1)
		self:_label(cell, "Letter", letter, "Heading", "Text", { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 105 })
		table.insert(self._refs.tutorialCells, cell)
	end
	self._refs.tutorialStep = self:_label(tutorial.card, "Step", "1. Press and hold the first letter.", "Body", "Text", {
		Position = UDim2.new(0, 34, 0, 340), Size = UDim2.new(1, -68, 0, 54), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	local tutorialSkip = self:_button(tutorial.card, "Skip", "SKIP", "PanelRaised", function()
		self:_closeModal("Tutorial")
		self:_emit("onTutorialComplete", true)
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 34, 1, -26), Size = UDim2.new(0.42, 0, 0, 54), ZIndex = 102 })
	local tutorialDone = self:_button(tutorial.card, "Done", "GOT IT", "Accent", function()
		self:_closeModal("Tutorial")
		self:_emit("onTutorialComplete", false)
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -34, 1, -26), Size = UDim2.new(0.52, 0, 0, 54), ZIndex = 102 })
	tutorial.firstButton = tutorialDone
	tutorialSkip.NextSelectionRight = tutorialDone
	tutorialDone.NextSelectionLeft = tutorialSkip

	local results = self:_modal("Results", "PUZZLE COMPLETE", UDim2.fromOffset(660, 610))
	self._refs.resultsTitle = results.title
	self._refs.resultsSubtitle = self:_label(results.card, "Subtitle", "Great searching!", "Body", "TextMuted", {
		Position = UDim2.new(0, 28, 0, 64), Size = UDim2.new(1, -56, 0, 30), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	local stars = self:_frame(results.card, "Stars", nil, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 105), Size = UDim2.fromOffset(280, 70), ZIndex = 102 })
	self._refs.resultStarsRoot = stars
	create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 16), Parent = stars })
	self._refs.resultStars = {}
	for index = 1, 3 do
		local star = self:_label(stars, "Star" .. tostring(index), "★", "Display", "TextDisabled", { Size = UDim2.fromOffset(70, 70), LayoutOrder = index, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 103 })
		table.insert(self._refs.resultStars, star)
	end
	local resultsStats = self:_frame(results.card, "Stats", "BackgroundRaised", { Position = UDim2.new(0, 34, 0, 190), Size = UDim2.new(1, -68, 0, 232), ZIndex = 102 })
	self._refs.resultStats = resultsStats
	self:_corner(resultsStats, Theme.Radii.Large)
	local resultGrid = create("UIGridLayout", { CellPadding = UDim2.fromOffset(10, 10), CellSize = UDim2.new(0.5, -15, 0, 64), FillDirectionMaxCells = 2, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Parent = resultsStats })
	self._refs.resultStatsGrid = resultGrid
	self._refs.resultValues = {}
	for index, spec in ipairs({ { "time", "TIME" }, { "words", "WORDS" }, { "hints", "HINTS USED" }, { "mistakes", "MISTAKES" }, { "reward", "REWARD" } }) do
		local stat = self:_frame(resultsStats, spec[1], "Panel", { LayoutOrder = index, ZIndex = 103 })
		self:_corner(stat, Theme.Radii.Medium)
		self:_label(stat, "Title", spec[2], "Caption", "TextMuted", { Position = UDim2.new(0, 10, 0, 7), Size = UDim2.new(1, -20, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 104 })
		self._refs.resultValues[spec[1]] = self:_label(stat, "Value", "0", "Heading", if spec[1] == "reward" then "Gold" else "Text", { Position = UDim2.new(0, 10, 0, 27), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 104 })
	end
	local resultButtons = self:_frame(results.card, "Buttons", nil, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.new(1, -68, 0, 116), ZIndex = 102 })
	self._refs.resultButtons = resultButtons
	local resultButtonGrid = create("UIGridLayout", { CellPadding = UDim2.fromOffset(10, 10), CellSize = UDim2.new(1 / 3, -7, 0, 54), FillDirectionMaxCells = 3, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Parent = resultButtons })
	self._refs.resultButtonGrid = resultButtonGrid
	local resultMenu = self:_button(resultButtons, "Menu", "MENU", "PanelRaised", function() self:_emit("onMenu") end, { LayoutOrder = 1, ZIndex = 103 })
	local resultReplay = self:_button(resultButtons, "Replay", "REPLAY", "PanelRaised", function() self:_emit("onReplay") end, { LayoutOrder = 2, ZIndex = 103 })
	local resultNext = self:_button(resultButtons, "Next", "NEXT", "Accent", function() self:_emit("onNext") end, { LayoutOrder = 3, ZIndex = 103 })
	results.firstButton = resultNext
	resultMenu.NextSelectionRight = resultReplay
	resultReplay.NextSelectionLeft = resultMenu
	resultReplay.NextSelectionRight = resultNext
	resultNext.NextSelectionLeft = resultReplay
	self._refs.resultMenu = resultMenu
	self._refs.resultReplay = resultReplay
	self._refs.resultNext = resultNext

	local confirm = self:_modal("Confirmation", "ARE YOU SURE?", UDim2.fromOffset(500, 350))
	self._refs.confirmTitle = confirm.title
	self._refs.confirmMessage = self:_label(confirm.card, "Message", "Please confirm this action.", "Body", "TextMuted", {
		Position = UDim2.new(0, 34, 0, 82), Size = UDim2.new(1, -68, 0, 96), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	self._refs.confirmCancel = self:_button(confirm.card, "Cancel", "CANCEL", "PanelRaised", function()
		local data = self._confirmation
		self:_closeModal("Confirmation", true)
		if data and type(data.onCancel) == "function" then data.onCancel() else self:_emit("onCancel") end
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 34, 1, -28), Size = UDim2.new(0.43, 0, 0, 54), ZIndex = 102 })
	self._refs.confirmAccept = self:_button(confirm.card, "Confirm", "CONFIRM", "Accent", function()
		local data = self._confirmation
		self:_closeModal("Confirmation", true, false)
		if data and type(data.onConfirm) == "function" then data.onConfirm() else self:_emit("onConfirm") end
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -34, 1, -28), Size = UDim2.new(0.5, 0, 0, 54), ZIndex = 102 })
	confirm.firstButton = self._refs.confirmAccept
	self._refs.confirmCancel.NextSelectionRight = self._refs.confirmAccept
	self._refs.confirmAccept.NextSelectionLeft = self._refs.confirmCancel

	local errorModal = self:_modal("Error", "SOMETHING WENT WRONG", UDim2.fromOffset(540, 390))
	self._refs.errorTitle = errorModal.title
	self._refs.errorMessage = self:_label(errorModal.card, "Message", "We couldn't load the puzzle.", "Body", "TextMuted", {
		Position = UDim2.new(0, 38, 0, 82), Size = UDim2.new(1, -76, 0, 120), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 102,
	})
	self._refs.errorMenu = self:_button(errorModal.card, "Menu", "MAIN MENU", "PanelRaised", function()
		self:_closeModal("Error")
		self:_emit("onMenu")
	end, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 36, 1, -30), Size = UDim2.new(0.4, 0, 0, 54), ZIndex = 102 })
	self._refs.errorRetry = self:_button(errorModal.card, "Retry", "TRY AGAIN", "Accent", function()
		local retry = self._errorRetry
		self:_closeModal("Error")
		if type(retry) == "function" then retry() else self:_emit("onRetry") end
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -36, 1, -30), Size = UDim2.new(0.5, 0, 0, 54), ZIndex = 102 })
	errorModal.firstButton = self._refs.errorRetry
	self._refs.errorMenu.NextSelectionRight = self._refs.errorRetry
	self._refs.errorRetry.NextSelectionLeft = self._refs.errorMenu
end

function UIController:_buildToastLayer()
	local layer = self:_frame(self._refs.root, "Toasts", nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, Theme.Metrics.TopBarHeight + 16),
		Size = UDim2.fromOffset(390, 360),
		ZIndex = 200,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = layer,
	})
	self._refs.toastLayer = layer
end

function UIController:_emit(name, ...)
	local callback = self._callbacks[name]
	if type(callback) ~= "function" then
		return nil
	end
	local ok, result = xpcall(callback, debug.traceback, ...)
	if not ok then
		warn(string.format("[WordSearch UI] %s callback failed: %s", tostring(name), tostring(result)))
		return nil
	end
	return result
end

function UIController:_bindCamera()
	disconnectAll(self._cameraConnections)
	local camera = Workspace.CurrentCamera
	if not camera then
		self:_applyResponsiveLayout()
		return
	end
	self:_track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:_applyResponsiveLayout()
	end), self._cameraConnections)
	self:_applyResponsiveLayout()
end

function UIController:_bindResponsiveSignals()
	self:_track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_bindCamera()
	end))
	self:_track(UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local nowUsingGamepad = string.find(tostring(inputType), "Gamepad") ~= nil
		if nowUsingGamepad ~= self._usingGamepad then
			self._usingGamepad = nowUsingGamepad
			self:_applyResponsiveLayout()
		end
	end))
	self:_track(self._refs.boardViewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_layoutBoard()
	end))
	self:_bindCamera()
end

function UIController:_updateTextSizes(bindings)
	for _, binding in ipairs(bindings or {}) do
		if binding.instance and binding.instance.Parent then
			binding.instance.TextSize = Theme.GetTextSize(binding.role, self._layout)
		end
	end
end

function UIController:_applyStyles(bindings)
	for _, binding in ipairs(bindings or {}) do
		if binding.instance and binding.instance.Parent and self._palette[binding.token] then
			binding.instance[binding.property] = self._palette[binding.token]
		end
	end
end

function UIController:_applyResponsiveLayout()
	if self._destroyed then
		return
	end
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or self._refs.root.AbsoluteSize
	if viewport.X <= 1 or viewport.Y <= 1 then
		viewport = Vector2.new(1280, 720)
	end
	self._layout = Theme.ResolveLayout(viewport, self._usingGamepad)
	local layout = self._layout
	local compactPortrait = layout.isPortrait and viewport.X < 800

	self:_updateTextSizes(self._textRoles)
	self:_updateTextSizes(self._levelTextRoles)
	self:_updateTextSizes(self._cellTextRoles)
	self._renderedStatus.timerToken = nil

	for _, pageName in ipairs({ "Menu", "Levels", "Daily", "Game" }) do
		local page = self._screens[pageName]
		local header = page and page:FindFirstChild("Header") or (page and page:FindFirstChild("TopBar"))
		if header and header:IsA("GuiObject") then
			header.Size = UDim2.new(1, 0, 0, layout.topBarHeight)
		end
	end
	if self._refs.menuBody then
		self._refs.menuBody.Position = UDim2.new(0, 0, 0, layout.topBarHeight)
		self._refs.menuBody.Size = UDim2.new(1, 0, 1, -layout.topBarHeight)
	end
	for _, pageName in ipairs({ "Levels", "Daily" }) do
		local page = self._screens[pageName]
		local scroll = pageName == "Levels" and self._refs.levelsScroll or nil
		if scroll then
			scroll.Position = UDim2.new(0, 0, 0, layout.topBarHeight)
			scroll.Size = UDim2.new(1, 0, 1, -layout.topBarHeight)
		end
	end

	local menuHeader = self._screens.Menu and self._screens.Menu:FindFirstChild("Header")
	local menuProfile = menuHeader and menuHeader:FindFirstChild("ProfileSummary")
	local menuBrand = menuHeader and menuHeader:FindFirstChild("Brand")
	if compactPortrait then
		self._refs.menuBody.ScrollingEnabled = true
		self._refs.menuBody.CanvasSize = UDim2.fromOffset(0, 772)
		if menuBrand then
			menuBrand.Position = UDim2.new(0, 12, 0, 0)
			menuBrand.Size = UDim2.new(1, -178, 1, 0)
		end
		if menuProfile then
			menuProfile.Position = UDim2.new(1, -10, 0.5, 0)
			menuProfile.Size = UDim2.fromOffset(150, 46)
		end
		self._refs.menuHero.Position = UDim2.new(0, 16, 0, 16)
		self._refs.menuHero.Size = UDim2.new(1, -32, 0, 216)
		self._refs.menuActions.AnchorPoint = Vector2.new(0, 0)
		self._refs.menuActions.Position = UDim2.new(0, 16, 0, 244)
		self._refs.menuActions.Size = UDim2.new(1, -32, 0, 294)
		self._refs.menuProgressPanel.AnchorPoint = Vector2.new(0.5, 0)
		self._refs.menuProgressPanel.Position = UDim2.new(0.5, 0, 0, 550)
		self._refs.menuProgressPanel.Size = UDim2.new(1, -32, 0, 206)
		self._refs.menuProgressGrid.CellSize = UDim2.new(0.5, -15, 0.5, -15)
		self._refs.menuProgressGrid.FillDirectionMaxCells = 2
	else
		self._refs.menuBody.ScrollingEnabled = false
		self._refs.menuBody.CanvasPosition = Vector2.zero
		self._refs.menuBody.CanvasSize = UDim2.fromOffset(0, 0)
		if menuBrand then
			menuBrand.Position = UDim2.new(0, 24, 0, 0)
			menuBrand.Size = UDim2.new(0.5, -24, 1, 0)
		end
		if menuProfile then
			menuProfile.Position = UDim2.new(1, -24, 0.5, 0)
			menuProfile.Size = UDim2.fromOffset(240, 52)
		end
		self._refs.menuHero.Position = UDim2.fromScale(0.06, 0.08)
		self._refs.menuHero.Size = UDim2.fromScale(0.42, 0.5)
		self._refs.menuActions.AnchorPoint = Vector2.new(1, 0)
		self._refs.menuActions.Position = UDim2.fromScale(0.94, 0.08)
		self._refs.menuActions.Size = UDim2.fromScale(0.4, 0.56)
		self._refs.menuProgressPanel.AnchorPoint = Vector2.new(0.5, 1)
		self._refs.menuProgressPanel.Position = UDim2.fromScale(0.5, 0.95)
		self._refs.menuProgressPanel.Size = UDim2.fromScale(0.88, 0.22)
		self._refs.menuProgressGrid.CellSize = UDim2.new(0.25, -13, 1, -20)
		self._refs.menuProgressGrid.FillDirectionMaxCells = 4
	end

	local dailyCard = self._screens.Daily and self._screens.Daily:FindFirstChild("DailyCard")
	if dailyCard then
		if compactPortrait then
			dailyCard.Size = UDim2.new(1, -24, 1, -(layout.topBarHeight + 32))
			dailyCard.Position = UDim2.new(0.5, 0, 0.5, layout.topBarHeight * 0.5)
		else
			dailyCard.Size = UDim2.fromOffset(620, 440)
			dailyCard.Position = UDim2.fromScale(0.5, 0.56)
		end
	end

	self._refs.gameContent.Position = UDim2.new(0, 0, 0, layout.topBarHeight)
	self._refs.gameContent.Size = UDim2.new(1, 0, 1, -layout.topBarHeight)
	if compactPortrait then
		self._refs.boardCard.Position = UDim2.new(0, 10, 0, 10)
		self._refs.boardCard.Size = UDim2.new(1, -20, 0.56, -14)
		self._refs.wordPanel.AnchorPoint = Vector2.new(0, 0)
		self._refs.wordPanel.Position = UDim2.new(0, 10, 0.56, 4)
		self._refs.wordPanel.Size = UDim2.new(1, -20, 0.44, -14)
		self._refs.timerChip.Position = UDim2.new(1, -96, 0.5, 0)
		self._refs.timerChip.Size = UDim2.fromOffset(78, 48)
		self._refs.progressChip.Position = UDim2.new(1, -10, 0.5, 0)
		self._refs.progressChip.Size = UDim2.fromOffset(78, 48)
		self._refs.gameTitle.Position = UDim2.new(0, 68, 0, 7)
		self._refs.gameTitle.Size = UDim2.new(1, -260, 0, 26)
		self._refs.gameSubtitle.Position = UDim2.new(0, 68, 0, 33)
		self._refs.gameSubtitle.Size = UDim2.new(1, -260, 0, 20)
		self._refs.wordTitle.Position = UDim2.new(0, 12, 0, 7)
		self._refs.wordTitle.Size = UDim2.new(0.58, -12, 0, 28)
		self._refs.wordCount.AnchorPoint = Vector2.new(1, 0)
		self._refs.wordCount.Position = UDim2.new(1, -12, 0, 9)
		self._refs.wordCount.Size = UDim2.new(0.42, 0, 0, 24)
		self._refs.wordCount.TextXAlignment = Enum.TextXAlignment.Right
		self._refs.wordScroll.Position = UDim2.new(0, 12, 0, 40)
		self._refs.wordScroll.Size = UDim2.new(1, -24, 1, -112)
		self._refs.gameStatus.Visible = false
		self._refs.gameProgressFill.Parent.Position = UDim2.new(0, 18, 1, -62)
		self._refs.hintButton.Position = UDim2.new(0.5, 0, 1, -8)
		self._refs.hintButton.Size = UDim2.new(1, -36, 0, 46)
	else
		local sidebarWidth = layout.sidebarWidth
		local padding = layout.padding
		self._refs.boardCard.Position = UDim2.new(0, padding, 0, padding)
		self._refs.boardCard.Size = UDim2.new(1, -(sidebarWidth + padding * 3), 1, -(padding * 2))
		self._refs.wordPanel.AnchorPoint = Vector2.new(1, 0)
		self._refs.wordPanel.Position = UDim2.new(1, -padding, 0, padding)
		self._refs.wordPanel.Size = UDim2.new(0, sidebarWidth, 1, -(padding * 2))
		self._refs.timerChip.Position = UDim2.new(1, -154, 0.5, 0)
		self._refs.timerChip.Size = UDim2.fromOffset(126, 50)
		self._refs.progressChip.Position = UDim2.new(1, -14, 0.5, 0)
		self._refs.progressChip.Size = UDim2.fromOffset(126, 50)
		self._refs.gameTitle.Position = UDim2.new(0, 78, 0, 8)
		self._refs.gameTitle.Size = UDim2.new(0.5, -78, 0, 28)
		self._refs.gameSubtitle.Position = UDim2.new(0, 78, 0, 37)
		self._refs.gameSubtitle.Size = UDim2.new(0.5, -78, 0, 22)
		self._refs.wordTitle.Position = UDim2.new(0, 18, 0, 15)
		self._refs.wordTitle.Size = UDim2.new(1, -36, 0, 30)
		self._refs.wordCount.AnchorPoint = Vector2.new(0, 0)
		self._refs.wordCount.Position = UDim2.new(0, 18, 0, 45)
		self._refs.wordCount.Size = UDim2.new(1, -36, 0, 22)
		self._refs.wordCount.TextXAlignment = Enum.TextXAlignment.Left
		self._refs.wordScroll.Position = UDim2.new(0, 12, 0, 76)
		self._refs.wordScroll.Size = UDim2.new(1, -24, 1, -216)
		self._refs.gameStatus.Visible = true
		self._refs.gameProgressFill.Parent.Position = UDim2.new(0, 18, 1, -92)
		self._refs.hintButton.Position = UDim2.new(0.5, 0, 1, -20)
		self._refs.hintButton.Size = UDim2.new(1, -36, 0, 58)
	end

	if self._refs.toastLayer then
		if compactPortrait then
			self._refs.toastLayer.Position = UDim2.new(0.5, 0, 0, layout.topBarHeight + 8)
			self._refs.toastLayer.AnchorPoint = Vector2.new(0.5, 0)
			self._refs.toastLayer.Size = UDim2.new(1, -24, 0, 280)
		else
			self._refs.toastLayer.Position = UDim2.new(1, -18, 0, layout.topBarHeight + 16)
			self._refs.toastLayer.AnchorPoint = Vector2.new(1, 0)
			self._refs.toastLayer.Size = UDim2.fromOffset(390, 360)
		end
	end

	local compactModalHeight = nil
	for _, modal in pairs(self._modals) do
		if compactPortrait then
			local targetHeight = math.min(viewport.Y - 28, math.max(300, modal.baseSize.Y.Offset))
			modal.card.Size = UDim2.new(1, -24, 0, targetHeight)
			if modal == self._modals.Results then
				compactModalHeight = targetHeight
			end
		else
			modal.card.Size = modal.baseSize
		end
	end
	if compactPortrait then
		local resultHeight = compactModalHeight or math.max(300, viewport.Y - 28)
		local statsHeight = math.clamp(resultHeight - 238, 150, 220)
		self._refs.resultsTitle.Position = UDim2.new(0, 18, 0, 10)
		self._refs.resultsTitle.Size = UDim2.new(1, -36, 0, 36)
		self._refs.resultsSubtitle.Position = UDim2.new(0, 18, 0, 47)
		self._refs.resultsSubtitle.Size = UDim2.new(1, -36, 0, 26)
		self._refs.resultStarsRoot.Position = UDim2.new(0.5, 0, 0, 76)
		self._refs.resultStarsRoot.Size = UDim2.fromOffset(220, 54)
		for _, star in ipairs(self._refs.resultStars) do
			star.Size = UDim2.fromOffset(52, 52)
		end
		self._refs.resultStats.Position = UDim2.new(0, 20, 0, 138)
		self._refs.resultStats.Size = UDim2.new(1, -40, 0, statsHeight)
		self._refs.resultStatsGrid.CellSize = UDim2.new(0.5, -15, 0, math.clamp(math.floor((statsHeight - 30) / 3), 40, 64))
		self._refs.resultButtons.Position = UDim2.new(0.5, 0, 1, -16)
		self._refs.resultButtons.Size = UDim2.new(1, -40, 0, 54)
		self._refs.resultButtonGrid.CellSize = UDim2.new(1 / 3, -7, 0, 54)
	else
		self._refs.resultsTitle.Position = UDim2.new(0, 24, 0, 20)
		self._refs.resultsTitle.Size = UDim2.new(1, -48, 0, 42)
		self._refs.resultsSubtitle.Position = UDim2.new(0, 28, 0, 64)
		self._refs.resultsSubtitle.Size = UDim2.new(1, -56, 0, 30)
		self._refs.resultStarsRoot.Position = UDim2.new(0.5, 0, 0, 105)
		self._refs.resultStarsRoot.Size = UDim2.fromOffset(280, 70)
		for _, star in ipairs(self._refs.resultStars) do
			star.Size = UDim2.fromOffset(70, 70)
		end
		self._refs.resultStats.Position = UDim2.new(0, 34, 0, 190)
		self._refs.resultStats.Size = UDim2.new(1, -68, 0, 232)
		self._refs.resultStatsGrid.CellSize = UDim2.new(0.5, -15, 0, 64)
		self._refs.resultButtons.Position = UDim2.new(0.5, 0, 1, -26)
		self._refs.resultButtons.Size = UDim2.new(1, -68, 0, 116)
		self._refs.resultButtonGrid.CellSize = UDim2.new(1 / 3, -7, 0, 54)
	end

	if self._activePage == "Levels" then
		self:_renderLevels(self._chapters)
	end
	task.defer(function()
		if not self._destroyed then
			self:_layoutBoard()
		end
	end)
end

function UIController:_focus(button)
	if not self._usingGamepad or not button or not button.Parent or not button.Visible or not button.Selectable then
		return
	end
	task.defer(function()
		if not self._destroyed and button.Parent and button.Visible and button.Selectable then
			GuiService.SelectedObject = button
		end
	end)
end

function UIController:_setPage(name)
	if self._destroyed or not self._screens[name] then
		return false
	end
	self:_closeAllModals(true)
	for pageName, page in pairs(self._screens) do
		page.Visible = pageName == name
	end
	self._activePage = name
	self:SetInputEnabled(name == "Game")
	local firstButtons = {
		Menu = self._refs.menuFirstButton,
		Levels = self._refs.levelsBack,
		Daily = self._refs.dailyPlay,
		Game = self._refs.pauseButton,
	}
	self:_focus(firstButtons[name])
	return true
end

function UIController:_openModal(name)
	local modal = self._modals[name]
	if not modal or self._destroyed then
		return false
	end
	if self._activeModal and self._activeModal ~= name then
		self._modalReturnName = self._activeModal
		self._modalReturnFocus = GuiService.SelectedObject
		local old = self._modals[self._activeModal]
		if old then old.overlay.Visible = false end
	else
		self._modalPreviousFocus = GuiService.SelectedObject
	end
	self._activeModal = name
	modal.overlay.Visible = true
	modal.overlay.BackgroundTransparency = if self._settings.reducedMotion then 0.28 else 1
	modal.card.Visible = true
	self:SetInputEnabled(false)
	self._animation:Tween(modal.overlay, { BackgroundTransparency = 0.28 }, "Normal")
	self._animation:Pop(modal.card)
	self:_focus(modal.firstButton)
	return true
end

function UIController:_closeModal(name, keepInputDisabled, restoreParent)
	local modal = self._modals[name]
	if not modal then
		return
	end
	self._tutorialToken += 1
	modal.overlay.Visible = false
	if self._activeModal == name then
		self._activeModal = nil
	end
	local returnName = self._modalReturnName
	local returnFocus = self._modalReturnFocus
	self._modalReturnName = nil
	self._modalReturnFocus = nil
	if returnName and restoreParent ~= false then
		local parentModal = self._modals[returnName]
		if parentModal then
			self._activeModal = returnName
			parentModal.overlay.Visible = true
			self:SetInputEnabled(false)
			self:_focus(returnFocus or parentModal.firstButton)
			return
		end
	end
	if keepInputDisabled ~= true then
		self:SetInputEnabled(self._activePage == "Game")
	end
	local previous = self._modalPreviousFocus
	self._modalPreviousFocus = nil
	if self._usingGamepad and previous and previous.Parent and previous.Visible and previous.Selectable then
		GuiService.SelectedObject = previous
	elseif self._activePage == "Game" then
		self:_focus(self._refs.pauseButton)
	end
end

function UIController:_closeAllModals(keepInputDisabled)
	self._tutorialToken += 1
	for _, modal in pairs(self._modals) do
		modal.overlay.Visible = false
	end
	self._activeModal = nil
	self._modalPreviousFocus = nil
	self._modalReturnName = nil
	self._modalReturnFocus = nil
	if keepInputDisabled ~= true then
		self:SetInputEnabled(self._activePage == "Game")
	end
end

function UIController:SetCallbacks(callbacks)
	for name, callback in pairs(callbacks or {}) do
		if type(callback) == "function" then
			self._callbacks[name] = callback
		elseif callback == false then
			self._callbacks[name] = nil
		end
	end
	return self
end

function UIController:ShowLoading(message, progress)
	if not self:_setPage("Loading") then
		return
	end
	self._refs.loadingMessage.Text = tostring(message or "Preparing your puzzles…")
	local alpha = math.clamp(tonumber(progress) or 0, 0, 1)
	self._animation:Tween(self._refs.loadingFill, { Size = UDim2.fromScale(alpha, 1) }, "Normal")
	self._animation:Pulse(self._refs.loadingCard, { peakScale = 1.012 })
end

function UIController:ShowMenu(data)
	data = data or {}
	self:_setPage("Menu")
	self._refs.menuProfileName.Text = string.upper(tostring(data.displayName or data.username or "PLAYER"))
	self._refs.menuProfileRank.Text = "Rank " .. tostring(math.max(1, math.floor(tonumber(data.rank) or 1)))
	local values = self._refs.menuProgressValues
	values.rank.Text = tostring(math.max(1, math.floor(tonumber(data.rank) or 1)))
	values.stars.Text = tostring(math.max(0, math.floor(tonumber(data.totalStars or data.stars) or 0)))
	values.solved.Text = tostring(math.max(0, math.floor(tonumber(data.completedPuzzles or data.solved) or 0)))
	values.streak.Text = tostring(math.max(0, math.floor(tonumber(data.dailyStreak or data.streak) or 0))) .. " days"
	if data.showTutorial == true then
		task.defer(function()
			if not self._destroyed and self._activePage == "Menu" then
				self:ShowTutorial(data.tutorial)
			end
		end)
	end
end

function UIController:ShowLevels(data)
	data = data or {}
	self._chapters = type(data.chapters) == "table" and data.chapters or self._chapters or DEFAULT_CHAPTERS
	local expandedStillExists = false
	for _, chapter in ipairs(self._chapters) do
		if tostring(chapter.id) == tostring(self._expandedChapterId) and chapter.unlocked ~= false then
			expandedStillExists = true
			break
		end
	end
	if not expandedStillExists then
		self._expandedChapterId = nil
		for _, chapter in ipairs(self._chapters) do
			if chapter.unlocked ~= false then
				for _, level in ipairs(type(chapter.levels) == "table" and chapter.levels or {}) do
					if level.state == "active" then
						self._expandedChapterId = chapter.id
						break
					end
				end
			end
			if self._expandedChapterId then
				break
			end
		end
		if not self._expandedChapterId then
			for _, chapter in ipairs(self._chapters) do
				if chapter.unlocked ~= false then
					self._expandedChapterId = chapter.id
					break
				end
			end
		end
	end
	self._refs.levelsStars.Text = "★ " .. tostring(math.max(0, math.floor(tonumber(data.totalStars) or 0)))
	self:_setPage("Levels")
	self:_renderLevels(self._chapters)
end

function UIController:ShowDaily(data)
	data = data or {}
	self:_setPage("Daily")
	self._refs.dailyTitle.Text = tostring(data.title or "A fresh puzzle awaits")
	self._refs.dailyDescription.Text = tostring(data.description or "Everyone gets the same board. Complete it before midnight UTC.")
	self._refs.dailyStreak.Text = tostring(math.max(0, math.floor(tonumber(data.streak) or 0))) .. " days"
	self._refs.dailyReward.Text = tostring(data.rewardText or "+1 Hint")
	self._refs.dailyReset.Text = tostring(data.resetText or (data.secondsUntilReset and formatCountdown(data.secondsUntilReset)) or "--:--:--")
	local completed = data.completed == true
	self._refs.dailyStatus.Text = completed and "✓ Completed today" or tostring(data.statusText or "Not completed today")
	self._refs.dailyStatus.TextColor3 = self._palette[completed and "Success" or "TextMuted"]
	self._refs.dailyPlay.Text = completed and "PLAY AGAIN" or "PLAY DAILY PUZZLE"
	self._refs.dailyPlay.Active = data.available ~= false
	self._refs.dailyPlay.Selectable = data.available ~= false
	self:_focus(self._refs.dailyPlay)
end

function UIController:UpdateDailyCountdown(secondsUntilReset)
	if self._refs.dailyReset and self._refs.dailyReset.Parent then
		self._refs.dailyReset.Text = formatCountdown(secondsUntilReset)
	end
end

function UIController:_setStyleToken(instance, property, token)
	for _, bucket in ipairs({ self._styles, self._levelStyles, self._cellStyles }) do
		for _, binding in ipairs(bucket) do
			if binding.instance == instance and binding.property == property then
				binding.token = token
			end
		end
	end
	if instance and instance.Parent and self._palette[token] then
		instance[property] = self._palette[token]
	end
end

function UIController:_setButtonToken(button, token)
	if not button then
		return
	end
	button:SetAttribute("ThemeToken", token)
	self:_setStyleToken(button, "BackgroundColor3", token)
end

function UIController:_renderLevels(chapters)
	local previousCanvasPosition = self._refs.levelsScroll and self._refs.levelsScroll.CanvasPosition or Vector2.zero
	disconnectAll(self._levelConnections)
	clearInstances(self._levelInstances)
	table.clear(self._levelStyles)
	table.clear(self._levelTextRoles)
	if not self._refs.levelsScroll then
		return
	end

	local columns = math.max(2, self._layout.levelColumns)
	local chapterNavigation = {}
	self._chapterToggles = {}
	for chapterIndex, chapter in ipairs(chapters or DEFAULT_CHAPTERS) do
		local levels = type(chapter.levels) == "table" and chapter.levels or {}
		local chapterId = tostring(chapter.id or chapterIndex)
		local expanded = chapter.unlocked ~= false and tostring(self._expandedChapterId) == chapterId
		local rows = expanded and math.max(1, math.ceil(math.max(1, #levels) / columns)) or 0
		local cardHeight = expanded and (104 + (rows * 62)) or 92
		local card = self:_frame(self._refs.levelsScroll, "Chapter_" .. tostring(chapter.id or chapterIndex), "Panel", {
			Size = UDim2.new(1, -8, 0, cardHeight),
			LayoutOrder = chapterIndex,
			ZIndex = 4,
		}, self._levelStyles)
		table.insert(self._levelInstances, card)
		self:_corner(card, Theme.Radii.Large)
		self:_stroke(card, "Border", 1, self._levelStyles)
		local assets = type(self._gameConfig.Assets) == "table" and self._gameConfig.Assets or {}
		local chapterImages = type(assets.ChapterImages) == "table" and assets.ChapterImages or {}
		local chapterImage = normalizeImageId(chapterImages[chapter.id] or chapterImages[chapterIndex])
		if chapterImage then
			create("ImageLabel", {
				Name = "ChapterArtwork",
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Image = chapterImage,
				ImageTransparency = chapter.unlocked == false and 0.9 or 0.78,
				Position = UDim2.new(1, -16, 0, 8),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(72, 72),
				ZIndex = 4,
				Parent = card,
			})
		end
		self:_label(card, "Title", tostring(chapter.title or ("Chapter " .. tostring(chapterIndex))), "Heading", chapter.unlocked == false and "TextDisabled" or "Text", {
			Position = UDim2.new(0, 18, 0, 13), Size = UDim2.new(0.55, -18, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5,
		}, self._levelStyles, self._levelTextRoles)
		self:_label(card, "Description", tostring(chapter.description or ""), "Small", "TextMuted", {
			Position = UDim2.new(0, 18, 0, 43), Size = UDim2.new(0.68, -18, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5,
		}, self._levelStyles, self._levelTextRoles)
		local chapterState = chapter.unlocked == false and "LOCKED" or string.format("★ %d / %d", math.max(0, math.floor(tonumber(chapter.stars) or 0)), math.max(0, math.floor(tonumber(chapter.totalStars) or (#levels * 3))))
		self:_label(card, "State", chapterState, "Small", chapter.unlocked == false and "TextDisabled" or "Gold", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.new(0.3, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5,
		}, self._levelStyles, self._levelTextRoles)
		local toggle = self:_button(card, "Toggle", expanded and "HIDE" or "OPEN", chapter.unlocked == false and "BackgroundRaised" or (expanded and "Accent" or "PanelRaised"), function()
			if chapter.unlocked == false then
				return
			end
			self._expandedChapterId = if expanded then nil else chapter.id
			self:_renderLevels(self._chapters)
			self:_focus(self._chapterToggles[chapterId])
		end, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 38),
			Size = UDim2.fromOffset(82, 44),
			Active = chapter.unlocked ~= false,
			Selectable = chapter.unlocked ~= false,
			ZIndex = 6,
		}, self._levelConnections, self._levelStyles, self._levelTextRoles)
		self._chapterToggles[chapterId] = toggle
		table.insert(chapterNavigation, { button = toggle, firstLevel = nil, levelButtons = nil })

		if expanded then
			local levelRoot = self:_frame(card, "Levels", nil, {
				Position = UDim2.new(0, 16, 0, 92), Size = UDim2.new(1, -32, 1, -102), ZIndex = 5,
			}, self._levelStyles)
			create("UIGridLayout", {
				CellPadding = UDim2.fromOffset(8, 8),
				CellSize = UDim2.new(1 / columns, -8, 0, 54),
				FillDirectionMaxCells = columns,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = levelRoot,
			})

			local levelButtons = {}
			for levelIndex, level in ipairs(levels) do
				local stateName = tostring(level.state or (level.locked and "locked" or level.completed and "completed" or "available"))
				local locked = chapter.unlocked == false or stateName == "locked"
				local completed = stateName == "completed" or math.max(0, tonumber(level.stars) or 0) > 0
				local active = stateName == "active"
				local token = locked and "BackgroundRaised" or completed and "SuccessDark" or active and "Accent" or "PanelRaised"
				local number = level.number or levelIndex
				local stars = math.clamp(math.floor(tonumber(level.stars) or 0), 0, 3)
				local label = locked and ("LOCKED  •  " .. tostring(number))
					or completed and ("✓  " .. tostring(number) .. "   " .. string.rep("★", stars))
					or active and ("NOW  •  " .. tostring(number))
					or ("PLAY  •  " .. tostring(number))
				local button = self:_button(levelRoot, "Level_" .. tostring(level.id or levelIndex), label, token, function()
					if not locked then
						self:_emit("onLevelSelected", level.id or levelIndex, chapter.id or chapterIndex, level)
					end
				end, {
					LayoutOrder = levelIndex,
					Active = not locked,
					Selectable = not locked,
					ZIndex = 6,
				}, self._levelConnections, self._levelStyles, self._levelTextRoles)
				if locked then
					button.TextColor3 = self._palette.TextDisabled
					self:_setStyleToken(button, "TextColor3", "TextDisabled")
				end
				table.insert(levelButtons, button)
			end
			chapterNavigation[#chapterNavigation].firstLevel = levelButtons[1]
			chapterNavigation[#chapterNavigation].levelButtons = levelButtons
			for index, button in ipairs(levelButtons) do
				button.NextSelectionLeft = levelButtons[index - 1]
				button.NextSelectionRight = levelButtons[index + 1]
				button.NextSelectionUp = levelButtons[index - columns] or toggle
				button.NextSelectionDown = levelButtons[index + columns]
			end
		end
	end
	for index, navigation in ipairs(chapterNavigation) do
		navigation.button.NextSelectionUp = chapterNavigation[index - 1] and chapterNavigation[index - 1].button or self._refs.levelsBack
		navigation.button.NextSelectionDown = navigation.firstLevel or (chapterNavigation[index + 1] and chapterNavigation[index + 1].button)
		for _, levelButton in ipairs(navigation.levelButtons or {}) do
			if not levelButton.NextSelectionDown then
				levelButton.NextSelectionDown = chapterNavigation[index + 1] and chapterNavigation[index + 1].button
			end
		end
	end
	task.defer(function()
		if not self._destroyed and self._refs.levelsScroll then
			self._refs.levelsScroll.CanvasPosition = previousCanvasPosition
		end
	end)
end

function UIController:_layoutBoard()
	if self._gridWidth <= 0 or self._gridHeight <= 0 or not self._refs.boardViewport then
		return
	end
	local viewportSize = self._refs.boardViewport.AbsoluteSize
	if viewportSize.X <= 1 or viewportSize.Y <= 1 then
		return
	end
	local gap = self._layout.isCompact and 3 or 5
	local availableCellWidth = (viewportSize.X - (gap * (self._gridWidth - 1))) / self._gridWidth
	local availableCellHeight = (viewportSize.Y - (gap * (self._gridHeight - 1))) / self._gridHeight
	local fitted = math.floor(math.min(availableCellWidth, availableCellHeight))
	local cellSize = math.clamp(math.max(Theme.Metrics.MinTouchTarget, fitted), Theme.Metrics.MinTouchTarget, self._layout.isConsole and 82 or 68)
	local contentWidth = (cellSize * self._gridWidth) + (gap * (self._gridWidth - 1))
	local contentHeight = (cellSize * self._gridHeight) + (gap * (self._gridHeight - 1))
	local canvasWidth = math.max(viewportSize.X, contentWidth)
	local canvasHeight = math.max(viewportSize.Y, contentHeight)
	local left = math.floor((canvasWidth - contentWidth) * 0.5)
	local top = math.floor((canvasHeight - contentHeight) * 0.5)

	self._refs.boardViewport.CanvasSize = UDim2.fromOffset(canvasWidth, canvasHeight)
	self._refs.boardCanvas.Position = UDim2.fromOffset(left, top)
	self._refs.boardCanvas.Size = UDim2.fromOffset(contentWidth, contentHeight)
	self._refs.cellLayout.CellPadding = UDim2.fromOffset(gap, gap)
	self._refs.cellLayout.CellSize = UDim2.fromOffset(cellSize, cellSize)
	self._refs.cellLayout.FillDirectionMaxCells = self._gridWidth
	self._boardCellSize = cellSize
	self._boardCellGap = gap
	task.defer(function()
		if not self._destroyed then
			self:_updateTrail()
		end
	end)
end

function UIController:_clearBoard()
	disconnectAll(self._cellConnections)
	clearInstances(self._cellInstances)
	table.clear(self._cellStyles)
	table.clear(self._cellTextRoles)
	table.clear(self._cells)
	table.clear(self._cellStates)
	table.clear(self._wordRows)
	table.clear(self._foundWords)
	table.clear(self._recentSelection)
	table.clear(self._trailSelection)
	self._hoveredKey = nil
	self._hoveredCell = nil
	self._gridWidth = 0
	self._gridHeight = 0
	self._boardCellSize = 0
	self._boardCellGap = 0
	self._refs.selectionTrail.Visible = false
end

function UIController:_createCell(row, column, letter, layoutOrder)
	local button = create("TextButton", {
		Name = string.format("Cell_%d_%d", row, column),
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Selectable = self._inputEnabled,
		Text = "",
		ZIndex = 8,
		Parent = self._refs.cellLayer,
	})
	button:SetAttribute("GridRow", row)
	button:SetAttribute("GridColumn", column)
	table.insert(self._cellInstances, button)
	local background = self:_frame(button, "Background", "BoardCell", {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), ZIndex = 4,
	}, self._cellStyles)
	self:_corner(background, Theme.Radii.Small)
	local stroke = self:_stroke(background, "Border", 1, self._cellStyles)
	local label = self:_label(button, "Letter", letter, "BoardLetter", "Text", {
		Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = 7,
	}, self._cellStyles, self._cellTextRoles)
	create("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 30, Parent = label })
	local marker = self:_label(button, "CompletedMark", "✓", "Caption", "Text", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 1), Size = UDim2.fromOffset(16, 16), TextXAlignment = Enum.TextXAlignment.Center, Visible = false, ZIndex = 9,
	}, self._cellStyles, self._cellTextRoles)
	local cell = { row = row, column = column, button = button, background = background, stroke = stroke, label = label, marker = marker }
	self._cells[row] = self._cells[row] or {}
	self._cells[row][column] = cell
	self._cellStates[cellKey(row, column)] = {}

	self:_track(button.SelectionGained:Connect(function()
		if self._inputEnabled then
			self:SetHoveredCell(cell, false)
		end
	end), self._cellConnections)
	return cell
end

function UIController:_buildWordList(words)
	for index, wordData in ipairs(words or {}) do
		local word = string.upper(tostring(type(wordData) == "table" and (wordData.word or wordData.text or wordData.id) or wordData))
		if word == "" then
			continue
		end
		local row = self:_frame(self._refs.wordScroll, "Word_" .. word, "BackgroundRaised", {
			Size = UDim2.new(1, -6, 0, Theme.Metrics.MinTouchTarget), LayoutOrder = index, ZIndex = 5,
		}, self._cellStyles)
		table.insert(self._cellInstances, row)
		self:_corner(row, Theme.Radii.Small)
		local marker = self:_label(row, "State", "○", "Body", "TextMuted", {
			Position = UDim2.new(0, 8, 0, 0), Size = UDim2.fromOffset(28, Theme.Metrics.MinTouchTarget), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6,
		}, self._cellStyles, self._cellTextRoles)
		local label = self:_label(row, "Label", word, "Body", "Text", {
			Position = UDim2.new(0, 42, 0, 0), Size = UDim2.new(1, -52, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6,
		}, self._cellStyles, self._cellTextRoles)
		self._wordRows[word] = { root = row, marker = marker, label = label, found = false }
	end
end

function UIController:_buildBoard(round)
	self:_clearBoard()
	local letters = normalizeLetters(round)
	self._gridHeight = math.max(1, #letters)
	for _, row in ipairs(letters) do
		self._gridWidth = math.max(self._gridWidth, #row)
	end
	self._gridWidth = math.max(1, self._gridWidth)

	for row = 1, self._gridHeight do
		for column = 1, self._gridWidth do
			self:_createCell(row, column, letters[row] and letters[row][column] or "?", ((row - 1) * self._gridWidth) + column)
		end
	end
	for row = 1, self._gridHeight do
		for column = 1, self._gridWidth do
			local button = self._cells[row][column].button
			button.NextSelectionUp = self._cells[row - 1] and self._cells[row - 1][column] and self._cells[row - 1][column].button or self._refs.pauseButton
			button.NextSelectionDown = self._cells[row + 1] and self._cells[row + 1][column] and self._cells[row + 1][column].button or self._refs.hintButton
			button.NextSelectionLeft = self._cells[row][column - 1] and self._cells[row][column - 1].button or self._refs.pauseButton
			button.NextSelectionRight = self._cells[row][column + 1] and self._cells[row][column + 1].button or self._refs.hintButton
		end
	end
	local firstCell = self._cells[1] and self._cells[1][1]
	local sideCellRow = math.max(1, math.ceil(self._gridHeight * 0.5))
	local sideCell = self._cells[sideCellRow] and self._cells[sideCellRow][self._gridWidth]
	if firstCell then
		self._refs.pauseButton.NextSelectionDown = firstCell.button
		self._refs.pauseButton.NextSelectionRight = self._refs.hintButton
	end
	if sideCell then
		self._refs.hintButton.NextSelectionLeft = sideCell.button
	end
	self._refs.hintButton.NextSelectionUp = self._refs.pauseButton
	self:_buildWordList(type(round.words) == "table" and round.words or { "ROBLOX", "PUZZLE", "WORDS", "GAME" })
	self:_layoutBoard()
end

function UIController:_refreshCell(cell)
	if not cell or not cell.button.Parent then
		return
	end
	local key = cellKey(cell.row, cell.column)
	local state = self._cellStates[key] or {}
	local hovered = self._hoveredKey == key
	local backgroundToken = "BoardCell"
	local borderToken = "Border"
	local borderThickness = 1
	local borderTransparency = 0.15

	if state.flash == "incorrect" then
		backgroundToken = "BoardIncorrect"
		borderToken = "Error"
		borderThickness = 3
	elseif state.flash == "correct" then
		backgroundToken = "BoardCorrect"
		borderToken = "Success"
		borderThickness = 3
	elseif state.completed then
		backgroundToken = nil
		borderToken = "Success"
		borderThickness = 2
	elseif hovered then
		backgroundToken = "BoardCellHover"
		borderToken = "Focus"
		borderThickness = 3
	end

	cell.background.BackgroundColor3 = state.completed and state.completedColor or self._palette[backgroundToken or "BoardCorrect"]
	cell.stroke.Color = self._palette[borderToken]
	cell.stroke.Thickness = borderThickness
	cell.stroke.Transparency = borderTransparency
	cell.marker.Visible = state.completed == true
	cell.label.TextColor3 = self._palette.Text
end

function UIController:_refreshAllCells()
	for _, row in pairs(self._cells) do
		for _, cell in pairs(row) do
			self:_refreshCell(cell)
		end
	end
end

function UIController:_refreshCells(points)
	local refreshed = {}
	for _, point in ipairs(type(points) == "table" and points or {}) do
		local key = cellKey(point.row, point.column)
		if not refreshed[key] then
			refreshed[key] = true
			self:_refreshCell(self:GetCell(point.row, point.column))
		end
	end
end

function UIController:_updateTrail()
	local selection = self._trailSelection
	local trail = self._refs.selectionTrail
	if not trail or #selection < 1 then
		if trail then trail.Visible = false end
		return
	end
	local first = self:GetCell(selection[1].row, selection[1].column)
	local last = self:GetCell(selection[#selection].row, selection[#selection].column)
	if not first or not last or not first.button.Parent or not last.button.Parent then
		trail.Visible = false
		return
	end
	local canvasPosition = self._refs.boardCanvas.AbsolutePosition
	local firstCenter = first.button.AbsolutePosition - canvasPosition + (first.button.AbsoluteSize * 0.5)
	local lastCenter = last.button.AbsolutePosition - canvasPosition + (last.button.AbsoluteSize * 0.5)
	local delta = lastCenter - firstCenter
	local thickness = math.max(20, math.floor(first.button.AbsoluteSize.Y * 0.58))
	trail.Position = UDim2.fromOffset((firstCenter.X + lastCenter.X) * 0.5, (firstCenter.Y + lastCenter.Y) * 0.5)
	trail.Size = UDim2.fromOffset(delta.Magnitude + thickness, thickness)
	trail.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	trail.Visible = true
end

function UIController:ShowGame(round)
	round = type(round) == "table" and round or {}
	self._currentRound = round
	self._renderedStatus = {}
	self:_setPage("Game")
	self._refs.gameTitle.Text = tostring(round.title or "Word Search")
	local subtitleParts = {}
	if round.mode then table.insert(subtitleParts, tostring(round.mode)) end
	if round.difficulty then table.insert(subtitleParts, tostring(round.difficulty)) end
	self._refs.gameSubtitle.Text = tostring(round.subtitle or table.concat(subtitleParts, " • "))
	self:_buildBoard(round)
	self:UpdateGameStatus({
		time = round.time or round.elapsedTime or round.timeLimit,
		timeText = round.timeText,
		foundWords = round.foundWords or 0,
		totalWords = type(round.words) == "table" and #round.words or 0,
		hintsRemaining = round.hintsRemaining or round.hints,
		message = round.statusText,
	})
	self:SetInputEnabled(round.inputEnabled ~= false)
	if self._usingGamepad then
		local firstCell = self:GetCell(1, 1)
		if firstCell then
			self:SetHoveredCell(firstCell, true)
		end
	end
	if round.showTutorial == true then
		task.defer(function()
			if not self._destroyed and self._activePage == "Game" then
				self:ShowTutorial(round.tutorial)
			end
		end)
	end
end

function UIController:UpdateSelection(selection)
	local normalized = {}
	for _, value in ipairs(type(selection) == "table" and selection or {}) do
		local cell = normalizeCell(value)
		if cell and self:GetCell(cell.row, cell.column) then
			table.insert(normalized, cell)
		end
	end
	if #normalized > 0 then
		self._recentSelection = normalized
	end
	self._trailSelection = normalized
	self._refs.selectionTrail.BackgroundColor3 = self._palette.Accent
	self:_updateTrail()
end

function UIController:SetHoveredCell(cellOrRow, columnOrFocus, shouldFocus)
	local cell
	local focus = shouldFocus == true
	if type(cellOrRow) == "table" then
		cell = self:GetCell(cellOrRow.row or cellOrRow.Row, cellOrRow.column or cellOrRow.Column)
		focus = columnOrFocus == true
	elseif tonumber(cellOrRow) and tonumber(columnOrFocus) then
		cell = self:GetCell(cellOrRow, columnOrFocus)
	end
	local oldCell = self._hoveredCell
	local newKey = cell and cellKey(cell.row, cell.column) or nil
	if self._hoveredKey == newKey then
		if focus and cell and cell.button.Selectable then
			GuiService.SelectedObject = cell.button
		end
		return
	end
	self._hoveredKey = newKey
	self._hoveredCell = cell
	self:_refreshCell(oldCell)
	if cell then
		self:_refreshCell(cell)
		if focus and cell.button.Selectable then
			GuiService.SelectedObject = cell.button
		end
	end
end

function UIController:_markWordFound(word, color)
	word = string.upper(tostring(word or ""))
	if word == "" then
		return
	end
	self._foundWords[word] = true
	local row = self._wordRows[word]
	if row then
		row.found = true
		row.marker.Text = "✓"
		row.marker.TextColor3 = color or self._palette.Success
		row.label.Text = "✓  " .. word
		row.label.TextColor3 = self._palette.TextMuted
		row.root.BackgroundColor3 = self._palette.SuccessDark
		row.root.BackgroundTransparency = 0.2
		self._animation:Pulse(row.root, { peakScale = 1.035 })
	end
end

function UIController:ApplySelectionResult(result)
	result = type(result) == "table" and result or { accepted = false }
	local cells = result.cells or result.selection or self._recentSelection
	local normalized = {}
	for _, value in ipairs(type(cells) == "table" and cells or {}) do
		local cell = normalizeCell(value)
		if cell and self:GetCell(cell.row, cell.column) then
			table.insert(normalized, cell)
		end
	end
	local accepted = result.accepted == true or result.correct == true or result.valid == true or result.success == true
	self._resultToken += 1
	local resultToken = self._resultToken

	if not accepted then
		for _, point in ipairs(normalized) do
			local state = self._cellStates[cellKey(point.row, point.column)]
			if state then
				state.flash = "incorrect"
				state.flashToken = resultToken
			end
		end
		self._trailSelection = normalized
		local displayedTrail = normalized
		self._refs.selectionTrail.BackgroundColor3 = self._palette.Error
		self:_refreshCells(normalized)
		self:_updateTrail()
		self._animation:Shake(self._refs.boardCard, { distance = 6 })
		self._audio:Play("Incorrect", { volume = 0.75 })
		if result.duplicate == true then
			self:ShowToast(result.message or "That word is already complete.", "info", 1.8)
		else
			self:ShowToast(result.message or "Not a target word — try another line.", "error", 1.6)
		end
		task.delay(self._settings.reducedMotion and 0.04 or 0.28, function()
			if self._destroyed then return end
			for _, point in ipairs(normalized) do
				local state = self._cellStates[cellKey(point.row, point.column)]
				if state and state.flashToken == resultToken then
					state.flash = nil
				end
			end
			if self._trailSelection == displayedTrail then
				self._trailSelection = {}
				self._refs.selectionTrail.BackgroundColor3 = self._palette.Accent
			end
			self:_refreshCells(normalized)
			self:_updateTrail()
		end)
		return false
	end

	local completedColors = Theme.GetCompletedWordColors(self._settings.highContrast)
	local foundCount = 0
	for _ in pairs(self._foundWords) do
		foundCount += 1
	end
	local colorIndex = math.max(1, math.floor(tonumber(result.colorIndex) or (foundCount + 1)))
	local color = typeof(result.color) == "Color3" and result.color or completedColors[((colorIndex - 1) % #completedColors) + 1]
	for _, point in ipairs(normalized) do
		local state = self._cellStates[cellKey(point.row, point.column)]
		if state then
			state.completed = true
			state.completedColor = color
			state.flash = "correct"
			state.flashToken = resultToken
		end
	end
	self:_markWordFound(result.word, color)
	self._trailSelection = normalized
	local displayedTrail = normalized
	self._refs.selectionTrail.BackgroundColor3 = color
	self:_refreshCells(normalized)
	self:_updateTrail()
	self._audio:Play(result.completed == true and "Complete" or "Correct", { volume = 0.8 })
	if result.message then
		self:ShowToast(result.message, result.completed == true and "reward" or "success", 1.5)
	end

	task.delay(self._settings.reducedMotion and 0.04 or 0.32, function()
		if self._destroyed then return end
		for _, point in ipairs(normalized) do
			local state = self._cellStates[cellKey(point.row, point.column)]
			if state and state.flashToken == resultToken then
				state.flash = nil
			end
		end
		if self._trailSelection == displayedTrail then
			self._trailSelection = {}
			self._refs.selectionTrail.BackgroundColor3 = self._palette.Accent
		end
		self:_refreshCells(normalized)
		self:_updateTrail()
	end)
	return true
end

function UIController:UpdateGameStatus(status)
	status = status or {}
	local rendered = self._renderedStatus
	local timeText
	if status.timeText ~= nil then
		timeText = tostring(status.timeText)
	elseif status.time ~= nil or status.seconds ~= nil then
		timeText = formatTime(status.time or status.seconds)
	end
	if timeText ~= nil and rendered.timeText ~= timeText then
		rendered.timeText = timeText
		self._refs.gameTimer.Text = timeText
	end
	local seconds = tonumber(status.time or status.seconds)
	local timerToken = (seconds and seconds <= 10) and "Error" or "Text"
	if rendered.timerToken ~= timerToken then
		rendered.timerToken = timerToken
		self._refs.gameTimer.TextColor3 = self._palette[timerToken]
	end

	local hasProgressUpdate = status.foundWords ~= nil
		or status.found ~= nil
		or status.totalWords ~= nil
		or status.total ~= nil
		or rendered.found == nil
	if hasProgressUpdate then
		local found = tonumber(status.foundWords or status.found)
		if type(status.foundWords) == "table" then
			found = 0
			for _, value in pairs(status.foundWords) do
				if value == true then found += 1 end
			end
		end
		found = math.max(0, math.floor(found or rendered.found or 0))
		local total = math.max(0, math.floor(tonumber(status.totalWords or status.total) or rendered.total or (self._currentRound and self._currentRound.words and #self._currentRound.words) or 0))
		if rendered.found ~= found or rendered.total ~= total then
			rendered.found = found
			rendered.total = total
			self._refs.gameProgressText.Text = string.format("%d / %d", found, total)
			self._refs.wordCount.Text = string.format("%d remaining", math.max(0, total - found))
			local alpha = total > 0 and math.clamp(found / total, 0, 1) or 0
			self._animation:Tween(self._refs.gameProgressFill, { Size = UDim2.fromScale(alpha, 1) }, "Normal")
		end
	end

	if status.hintsRemaining ~= nil or status.hints ~= nil or rendered.hints == nil then
		local hints = math.max(0, math.floor(tonumber(status.hintsRemaining or status.hints) or rendered.hints or 0))
		if rendered.hints ~= hints then
			rendered.hints = hints
			self._refs.hintButton.Text = "HINT  •  " .. tostring(hints)
		end
	end
	if status.hintEnabled ~= nil or rendered.hintEnabled == nil then
		local hintEnabled = status.hintEnabled ~= false
		if rendered.hintEnabled ~= hintEnabled then
			rendered.hintEnabled = hintEnabled
			self._refs.hintButton.Active = hintEnabled
			self._refs.hintButton.Selectable = hintEnabled
		end
	end
	if status.message ~= nil then
		local message = tostring(status.message)
		if rendered.message ~= message then
			rendered.message = message
			self._refs.gameStatus.Text = message
		end
	end
	if status.inputEnabled ~= nil then
		self:SetInputEnabled(status.inputEnabled == true)
	end
	if status.foundWord then
		self:_markWordFound(status.foundWord, self._palette.Success)
	end
end

function UIController:ShowPause(data)
	data = data or {}
	local modal = self._modals.Pause
	local body = modal.card:FindFirstChild("Body")
	if body and body:IsA("TextLabel") then
		body.Text = tostring(data.message or "Your puzzle is waiting. Pausing caps this solve at two stars.")
	end
	self:_openModal("Pause")
end

function UIController:ClosePause()
	if self._activeModal == "Pause" then
		self:_closeModal("Pause")
	end
end

function UIController:_changeSetting(key, value)
	self:SetSettings({ [key] = value == true })
	self:_emit("onSettingChanged", key, self._settings[key], copySettings(self._settings))
end

function UIController:ShowSettings(settings)
	if type(settings) == "table" then
		self:SetSettings(settings)
	end
	self:_openModal("Settings")
end

function UIController:_startTutorialDemo()
	self._tutorialToken += 1
	local token = self._tutorialToken
	local demoCells = self._refs.tutorialCells
	for _, cell in ipairs(demoCells) do
		cell.BackgroundColor3 = self._palette.BoardCell
	end
	local trail = self._refs.tutorialTrail
	trail.BackgroundColor3 = self._palette.Accent
	trail.Size = UDim2.fromOffset(32, 32)
	trail.Visible = false
	if self._settings.reducedMotion then
		trail.Size = UDim2.fromOffset(212, 32)
		trail.BackgroundColor3 = self._palette.Success
		trail.Visible = true
		for index = 1, math.min(4, #demoCells) do
			demoCells[index].BackgroundColor3 = self._palette.BoardCorrect
		end
		self._refs.tutorialStep.Text = "Release on D. The completed word stays marked with a check."
		return
	end

	task.spawn(function()
		while not self._destroyed and self._activeModal == "Tutorial" and self._tutorialToken == token do
			self._refs.tutorialStep.Text = "1. Press and hold the first letter."
			trail.BackgroundColor3 = self._palette.Accent
			trail.Size = UDim2.fromOffset(32, 32)
			trail.Visible = false
			for _, cell in ipairs(demoCells) do
				cell.BackgroundColor3 = self._palette.BoardCell
			end
			task.wait(0.55)
			for index = 1, math.min(4, #demoCells) do
				if self._activeModal ~= "Tutorial" or self._tutorialToken ~= token then return end
				self._refs.tutorialStep.Text = index == 1 and "2. Hold and drag in a straight line." or "2. Keep dragging through the word."
				trail.Visible = true
				self._animation:Tween(trail, { Size = UDim2.fromOffset(32 + ((index - 1) * 60), 32) }, "Normal")
				task.wait(0.28)
			end
			if self._activeModal ~= "Tutorial" or self._tutorialToken ~= token then return end
			self._refs.tutorialStep.Text = "3. Release on D to submit WORD."
			trail.BackgroundColor3 = self._palette.Success
			for index = 1, math.min(4, #demoCells) do
				demoCells[index].BackgroundColor3 = self._palette.BoardCorrect
			end
			task.wait(1.2)
		end
	end)
end

function UIController:ShowTutorial(data)
	data = data or {}
	if data.title then self._modals.Tutorial.title.Text = tostring(data.title) end
	local instruction = self._modals.Tutorial.card:FindFirstChild("Instruction")
	if instruction and data.message then instruction.Text = tostring(data.message) end
	self:_openModal("Tutorial")
	self:_startTutorialDemo()
end

function UIController:ShowResults(data)
	data = data or {}
	self._resultToken += 1
	local token = self._resultToken
	self._refs.resultsTitle.Text = tostring(data.title or (data.success == false and "TRY AGAIN" or "PUZZLE COMPLETE"))
	self._refs.resultsSubtitle.Text = tostring(data.subtitle or (data.success == false and "Keep searching — you've got this." or "Great searching!"))
	self._refs.resultValues.time.Text = tostring(data.timeText or formatTime(data.time or data.completionTime or 0))
	self._refs.resultValues.words.Text = tostring(data.wordsText or string.format("%d / %d", math.max(0, math.floor(tonumber(data.wordsFound) or 0)), math.max(0, math.floor(tonumber(data.totalWords) or tonumber(data.wordsFound) or 0))))
	self._refs.resultValues.hints.Text = tostring(math.max(0, math.floor(tonumber(data.hintsUsed) or 0)))
	self._refs.resultValues.mistakes.Text = tostring(math.max(0, math.floor(tonumber(data.mistakes) or 0)))
	self._refs.resultValues.reward.Text = tostring(data.rewardText or (data.reward and ("+" .. tostring(data.reward))) or "+0")
	local awardedStars = math.clamp(math.floor(tonumber(data.stars) or 0), 0, 3)
	for _, star in ipairs(self._refs.resultStars) do
		self:_setStyleToken(star, "TextColor3", "TextDisabled")
	end
	local hasNext = data.hasNext ~= false
	self._refs.resultNext.Visible = hasNext
	self._refs.resultNext.Active = hasNext
	self._refs.resultNext.Selectable = hasNext
	self._modals.Results.firstButton = hasNext and self._refs.resultNext or self._refs.resultReplay
	self:_openModal("Results")
	self._audio:Play("Complete", { volume = 0.9 })

	for index, star in ipairs(self._refs.resultStars) do
		if index <= awardedStars then
			local delaySeconds = self._settings.reducedMotion and 0 or (0.16 + ((index - 1) * 0.2))
			task.delay(delaySeconds, function()
				if self._destroyed or self._resultToken ~= token or self._activeModal ~= "Results" then return end
				self:_setStyleToken(star, "TextColor3", "Gold")
				self._animation:Pop(star, { fromScale = 0.68, toScale = 1 })
				self._audio:Play("Unlock", { volume = 0.45, playbackSpeed = 0.94 + (index * 0.08) })
			end)
		end
	end
end

function UIController:ShowConfirmation(data)
	data = data or {}
	self._confirmation = data
	self._refs.confirmTitle.Text = tostring(data.title or "ARE YOU SURE?")
	self._refs.confirmMessage.Text = tostring(data.message or "Please confirm this action.")
	self._refs.confirmAccept.Text = tostring(data.confirmText or "CONFIRM")
	self._refs.confirmCancel.Text = tostring(data.cancelText or "CANCEL")
	self:_openModal("Confirmation")
end

function UIController:ShowError(title, message, onRetry)
	if type(title) == "table" then
		local data = title
		title = data.title
		message = data.message
		onRetry = data.onRetry
	end
	self._errorRetry = onRetry
	self._refs.errorTitle.Text = tostring(title or "SOMETHING WENT WRONG")
	self._refs.errorMessage.Text = tostring(message or "We couldn't load this puzzle. Please try again.")
	self._refs.errorRetry.Visible = onRetry ~= false
	self._refs.errorRetry.Active = onRetry ~= false
	self._refs.errorRetry.Selectable = onRetry ~= false
	self._modals.Error.firstButton = onRetry == false and self._refs.errorMenu or self._refs.errorRetry
	self:_openModal("Error")
end

function UIController:ShowToast(message, kind, duration)
	if type(message) == "table" then
		local data = message
		message = data.message or data.text
		kind = data.kind or data.type
		duration = data.duration
	end
	if self._destroyed then
		return nil
	end
	self._toastSerial += 1
	kind = tostring(kind or "info")
	local tokenByKind = { success = "Success", error = "Error", reward = "Gold", info = "Info" }
	local iconByKind = { success = "✓", error = "!", reward = "★", info = "i" }
	local token = tokenByKind[kind] or "Info"
	local toast = create("CanvasGroup", {
		Name = "Toast_" .. tostring(self._toastSerial),
		BackgroundColor3 = self._palette.PanelRaised,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		GroupTransparency = self._settings.reducedMotion and 0 or 1,
		LayoutOrder = self._toastSerial,
		Size = UDim2.new(1, 0, 0, 64),
		ZIndex = 201,
		Parent = self._refs.toastLayer,
	})
	self:_corner(toast, Theme.Radii.Medium)
	local stroke = create("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = self._palette[token], Thickness = 2, Parent = toast })
	self:_label(toast, "Icon", iconByKind[kind] or "i", "Heading", token, { Position = UDim2.new(0, 10, 0, 0), Size = UDim2.fromOffset(42, 64), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 202 })
	self:_label(toast, "Message", tostring(message or ""), "Body", "Text", { Position = UDim2.new(0, 56, 0, 6), Size = UDim2.new(1, -70, 1, -12), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 202 })
	self._animation:Tween(toast, { GroupTransparency = 0 }, "Normal")
	self._animation:Pop(toast, { fromScale = 0.94, toScale = 1 })
	local lifetime = math.clamp(tonumber(duration) or 2.4, 0.5, 10)
	task.delay(lifetime, function()
		if self._destroyed or not toast.Parent then return end
		self._animation:Tween(toast, { GroupTransparency = 1 }, "Normal", function()
			if toast.Parent then toast:Destroy() end
		end)
	end)
	return toast
end

function UIController:GetCell(row, column)
	row = math.floor(tonumber(row) or 0)
	column = math.floor(tonumber(column) or 0)
	return self._cells[row] and self._cells[row][column] or nil
end

function UIController:GetGridSize()
	return self._gridWidth, self._gridHeight
end

function UIController:GetCellAtPosition(position)
	if typeof(position) ~= "Vector2" or not self._refs.boardViewport or not self._refs.boardViewport.Visible then
		return nil
	end
	local bounds = self:GetBoardBounds()
	if not bounds or position.X < bounds.min.X or position.X > bounds.max.X or position.Y < bounds.min.Y or position.Y > bounds.max.Y then
		return nil
	end
	local cellSize = self._boardCellSize
	local gap = self._boardCellGap
	if cellSize <= 0 or not self._refs.boardCanvas then
		return nil
	end

	local relative = position - self._refs.boardCanvas.AbsolutePosition
	local stride = cellSize + gap
	if relative.X < 0 or relative.Y < 0 then
		return nil
	end
	local column = math.floor(relative.X / stride) + 1
	local row = math.floor(relative.Y / stride) + 1
	if row > self._gridHeight or column > self._gridWidth then
		return nil
	end
	local withinX = relative.X - ((column - 1) * stride)
	local withinY = relative.Y - ((row - 1) * stride)
	if withinX > cellSize or withinY > cellSize then
		return nil
	end
	return self:GetCell(row, column)
end

function UIController:GetBoardBounds()
	local board = self._refs.boardViewport
	if not board or not board.Parent then
		return nil
	end
	local minimum = board.AbsolutePosition
	local size = board.AbsoluteSize
	return {
		min = minimum,
		max = minimum + size,
		position = minimum,
		size = size,
		gui = board,
	}
end

function UIController:GetSelectedBoardCell()
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self._refs.cellLayer) then
		local row = selected:GetAttribute("GridRow")
		local column = selected:GetAttribute("GridColumn")
		local cell = self:GetCell(row, column)
		if cell then return cell end
	end
	if self._hoveredKey then
		local parts = string.split(self._hoveredKey, ":")
		return self:GetCell(tonumber(parts[1]), tonumber(parts[2]))
	end
	return self:GetCell(1, 1)
end

function UIController:GetGameRoot()
	return self._screens.Game
end

function UIController:GetScreenGui()
	return self._refs.screenGui
end

function UIController:IsInputEnabled()
	return self._inputEnabled == true
end

function UIController:GetInputEnabledChangedSignal()
	return self._inputEnabledEvent.Event
end

function UIController:SetInputEnabled(enabled)
	enabled = enabled == true and self._activePage == "Game" and self._activeModal == nil
	if self._inputEnabled == enabled then
		return
	end
	self._inputEnabled = enabled
	for _, row in pairs(self._cells) do
		for _, cell in pairs(row) do
			cell.button.Active = enabled
			cell.button.Selectable = enabled
		end
	end
	if not enabled then
		self:UpdateSelection({})
	end
	self._inputEnabledEvent:Fire(enabled)
end

function UIController:SetSettings(settings)
	settings = settings or {}
	local aliases = {
		music = { "music", "Music" },
		sfx = { "sfx", "SFX" },
		reducedMotion = { "reducedMotion", "ReducedMotion" },
		highContrast = { "highContrast", "HighContrast" },
	}
	for key, names in pairs(aliases) do
		for _, name in ipairs(names) do
			if settings[name] ~= nil then
				self._settings[key] = settings[name] == true
				break
			end
		end
	end
	self._palette = Theme.GetPalette(self._settings.highContrast)
	self._animation:SetReducedMotion(self._settings.reducedMotion)
	self._audio:SetSettings(self._settings)
	self:_applyStyles(self._styles)
	self:_applyStyles(self._levelStyles)
	self:_applyStyles(self._cellStyles)
	self:_updateTextSizes(self._textRoles)
	self:_updateTextSizes(self._levelTextRoles)
	self:_updateTextSizes(self._cellTextRoles)
	for key, button in pairs(self._refs.settingButtons or {}) do
		local enabled = self._settings[key] == true
		button.Text = enabled and "ON" or "OFF"
		self:_setButtonToken(button, enabled and "Success" or "PanelRaised")
	end
	self:_refreshAllCells()
	if self._refs.selectionTrail then
		self._refs.selectionTrail.BackgroundColor3 = self._palette.Accent
	end
	return copySettings(self._settings)
end

function UIController:Destroy()
	if self._destroyed then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and self._refs.screenGui and selected:IsDescendantOf(self._refs.screenGui) then
		GuiService.SelectedObject = nil
	end
	self:SetInputEnabled(false)
	self._destroyed = true
	self._tutorialToken += 1
	self._resultToken += 1
	disconnectAll(self._cameraConnections)
	disconnectAll(self._levelConnections)
	disconnectAll(self._cellConnections)
	disconnectAll(self._connections)
	clearInstances(self._levelInstances)
	clearInstances(self._cellInstances)
	if self._inputEnabledEvent then
		self._inputEnabledEvent:Destroy()
		self._inputEnabledEvent = nil
	end
	if self._ownsAnimation and self._animation then
		self._animation:Destroy()
	end
	if self._ownsAudio and self._audio then
		self._audio:Destroy()
	end
	if self._refs.screenGui then
		self._refs.screenGui:Destroy()
	end
	table.clear(self._callbacks)
	table.clear(self._screens)
	table.clear(self._modals)
	table.clear(self._refs)
end

return UIController
