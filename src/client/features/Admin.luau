local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LegacyRemotes = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("network"):WaitForChild("NetworkContract")).Legacy

local Admin = {}
Admin.__index = Admin

local player = Players.LocalPlayer

local PANEL_SIZE = UDim2.fromOffset(360, 420)
local PANEL_POSITION = UDim2.new(1, -18, 0.5, 0)
local BUTTON_POSITION = UDim2.new(1, -18, 0, 78)

local function setText(node, value)
	if node and (node:IsA("TextButton") or node:IsA("TextLabel") or node:IsA("TextBox")) then
		node.Text = tostring(value or "")
	end
end

local function create(className, props)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props and props.Parent or nil
	return instance
end

local function createCorner(parent, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = parent,
	})
end

local function createStroke(parent, color, transparency)
	return create("UIStroke", {
		Color = color or Color3.fromRGB(105, 185, 255),
		Thickness = 1.4,
		Transparency = transparency or 0.15,
		Parent = parent,
	})
end

local function createButton(parent, name, text, color)
	local button = create("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = color or Color3.fromRGB(45, 59, 84),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		Parent = parent,
	})
	createCorner(button, 7)
	createStroke(button, Color3.fromRGB(128, 200, 255), 0.28)
	return button
end

local function createTextBox(parent, name, placeholder)
	local box = create("TextBox", {
		Name = name,
		BackgroundColor3 = Color3.fromRGB(21, 28, 40),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.GothamMedium,
		PlaceholderColor3 = Color3.fromRGB(170, 182, 198),
		PlaceholderText = placeholder,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		Parent = parent,
	})
	createCorner(box, 7)
	createStroke(box, Color3.fromRGB(88, 115, 150), 0.32)
	return box
end

function Admin.new(ctx)
	local self = setmetatable({}, Admin)
	self.ctx = ctx or {}
	self.root = nil
	self.remote = nil
	self.allowed = false
	self.maxClassicLevel = 150
	self.players = {}
	self.selectedUserId = nil
	self.selectedName = ""
	self.connections = {}
	self.rowConnections = {}
	self.elements = {}
	return self
end

function Admin:resolveRemote()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local functionsFolder = remotesFolder and remotesFolder:FindFirstChild("Functions")
	self.remote = functionsFolder and functionsFolder:FindFirstChild(LegacyRemotes.AdminAction) or nil
	return self.remote
end

function Admin:invoke(payload)
	local remote = self.remote or self:resolveRemote()
	if not remote then
		return nil
	end

	local result = nil
	local ok = pcall(function()
		result = remote:InvokeServer(payload)
	end)
	if not ok or type(result) ~= "table" then
		return nil
	end

	return result
end

function Admin:showAlert(message, isError)
	if self.ctx.showDesktopAlert then
		self.ctx.showDesktopAlert("Admin", tostring(message or ""), isError and "error" or "info", {
			color = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(105, 255, 152),
			duration = 2.6,
		})
	end
end

function Admin:applyState(result)
	if type(result) ~= "table" then
		return false
	end

	self.allowed = result.allowed == true
	self.maxClassicLevel = math.max(1, math.floor(tonumber(result.maxClassicLevel) or self.maxClassicLevel or 150))
	self.players = type(result.players) == "table" and result.players or self.players
	if not self.selectedUserId and self.players[1] then
		self.selectedUserId = self.players[1].userId
		self.selectedName = self.players[1].name or self.players[1].displayName or "All Players"
	end

	self:renderPlayerList()
	if self.elements.levelBox then
		self.elements.levelBox.PlaceholderText = string.format("Level 1-%d", self.maxClassicLevel)
	end
	return self.allowed
end

function Admin:createUi()
	if not self.root or self.elements.adminButton then
		return
	end

	local adminButton = createButton(self.root, "AdminMenuButton", "ADMIN", Color3.fromRGB(80, 47, 118))
	adminButton.AnchorPoint = Vector2.new(1, 0)
	adminButton.Position = BUTTON_POSITION
	adminButton.Size = UDim2.fromOffset(92, 36)
	adminButton.ZIndex = 80

	local panel = create("Frame", {
		Name = "AdminMenuPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Color3.fromRGB(15, 20, 30),
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Position = PANEL_POSITION,
		Size = PANEL_SIZE,
		Visible = false,
		ZIndex = 80,
		Parent = self.root,
	})
	createCorner(panel, 8)
	createStroke(panel, Color3.fromRGB(126, 195, 255), 0.08)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = panel,
	})

	local layout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
		Parent = panel,
	})

	local title = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Text = "Admin Menu",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 81,
		Parent = panel,
	})

	local selected = create("TextLabel", {
		Name = "SelectedPlayer",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 24),
		Text = "Selected: -",
		TextColor3 = Color3.fromRGB(196, 214, 232),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 81,
		Parent = panel,
	})

	local playerList = create("ScrollingFrame", {
		Name = "PlayerList",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(21, 28, 40),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		LayoutOrder = 3,
		ScrollBarThickness = 5,
		Size = UDim2.new(1, 0, 0, 150),
		ZIndex = 81,
		Parent = panel,
	})
	createCorner(playerList, 7)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
		Parent = playerList,
	})
	create("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = playerList,
	})

	local hintsBox = createTextBox(panel, "HintsAmount", "Hints amount")
	hintsBox.LayoutOrder = 4
	hintsBox.Size = UDim2.new(1, 0, 0, 38)
	hintsBox.ZIndex = 81

	local giveHints = createButton(panel, "GiveHints", "Give Hints", Color3.fromRGB(42, 130, 82))
	giveHints.LayoutOrder = 5
	giveHints.Size = UDim2.new(1, 0, 0, 40)
	giveHints.ZIndex = 81

	local levelBox = createTextBox(panel, "ClassicLevel", string.format("Level 1-%d", self.maxClassicLevel))
	levelBox.LayoutOrder = 6
	levelBox.Size = UDim2.new(1, 0, 0, 38)
	levelBox.ZIndex = 81

	local setLevel = createButton(panel, "SetLevel", "Set Classic Level", Color3.fromRGB(55, 97, 170))
	setLevel.LayoutOrder = 7
	setLevel.Size = UDim2.new(1, 0, 0, 40)
	setLevel.ZIndex = 81

	local refresh = createButton(panel, "RefreshPlayers", "Refresh Players", Color3.fromRGB(45, 59, 84))
	refresh.LayoutOrder = 8
	refresh.Size = UDim2.new(1, 0, 0, 34)
	refresh.ZIndex = 81

	self.elements = {
		adminButton = adminButton,
		panel = panel,
		title = title,
		selected = selected,
		playerList = playerList,
		hintsBox = hintsBox,
		giveHints = giveHints,
		levelBox = levelBox,
		setLevel = setLevel,
		refresh = refresh,
	}

	table.insert(self.connections, adminButton.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			self:refreshState()
		end
	end))
	table.insert(self.connections, refresh.MouseButton1Click:Connect(function()
		self:refreshState()
	end))
	table.insert(self.connections, giveHints.MouseButton1Click:Connect(function()
		self:runAction("giveHints", {
			amount = hintsBox.Text,
		})
	end))
	table.insert(self.connections, setLevel.MouseButton1Click:Connect(function()
		self:runAction("setLevel", {
			level = levelBox.Text,
		})
	end))

	table.insert(self.connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		panel.Size = PANEL_SIZE
	end))
end

function Admin:renderPlayerList()
	local list = self.elements.playerList
	if not list then
		return
	end

	for _, connection in ipairs(self.rowConnections) do
		connection:Disconnect()
	end
	table.clear(self.rowConnections)

	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	for index, entry in ipairs(self.players or {}) do
		local name = tostring(entry.name or entry.displayName or entry.userId or "Player")
		local displayName = tostring(entry.displayName or name)
		local buttonText = displayName == name and name or string.format("%s (@%s)", displayName, name)
		local row = createButton(list, "Player_" .. tostring(entry.userId), buttonText, entry.userId == self.selectedUserId and Color3.fromRGB(64, 103, 151) or Color3.fromRGB(32, 42, 60))
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -2, 0, 34)
		row.ZIndex = 82
		table.insert(self.rowConnections, row.MouseButton1Click:Connect(function()
			self.selectedUserId = entry.userId
			self.selectedName = name
			self:updateSelectedLabel()
			self:renderPlayerList()
		end))
	end

	self:updateSelectedLabel()
end

function Admin:updateSelectedLabel()
	local selectedText = self.selectedName ~= "" and self.selectedName or tostring(self.selectedUserId or "-")
	setText(self.elements.selected, "Selected: " .. selectedText)
end

function Admin:refreshState()
	local result = self:invoke({
		action = "state",
	})
	if not result then
		self:showAlert("Admin service unavailable.", true)
		return false
	end

	if not self:applyState(result) then
		if self.elements.adminButton then
			self.elements.adminButton.Visible = false
		end
		return false
	end

	return true
end

function Admin:runAction(action, data)
	if not self.selectedUserId then
		self:showAlert("Select a player first.", true)
		return
	end

	data = data or {}
	data.action = action
	data.targetUserId = self.selectedUserId

	local result = self:invoke(data)
	if not result then
		self:showAlert("Admin action failed.", true)
		return
	end

	self:applyState(result)
	self:showAlert(result.message or (result.success and "Done." or "Action failed."), result.success ~= true)
end

function Admin:bind(root)
	if not (root and root:IsA("ScreenGui")) then
		return
	end
	if self.root then
		self:destroy()
	end

	self.root = root
	task.spawn(function()
		local result = self:invoke({
			action = "state",
		})
		if not result or result.allowed ~= true then
			return
		end

		self:applyState(result)
		self:createUi()
		self:renderPlayerList()
	end)
end

function Admin:destroy()
	for _, connection in ipairs(self.rowConnections) do
		connection:Disconnect()
	end
	table.clear(self.rowConnections)

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)

	if self.elements.adminButton then
		self.elements.adminButton:Destroy()
	end
	if self.elements.panel then
		self.elements.panel:Destroy()
	end
	self.elements = {}
	self.root = nil
end

return Admin
