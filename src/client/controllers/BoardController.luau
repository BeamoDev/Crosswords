local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local shared = ReplicatedStorage:WaitForChild("shared")
local Engine = require(shared.puzzle.PuzzleEngine)
local Effects = require(shared.ui.UIEffects)

local BoardController = {}
BoardController.__index = BoardController
local LINE_COLORS = {
	Color3.fromRGB(0, 183, 255), Color3.fromRGB(38, 213, 98),
	Color3.fromRGB(255, 157, 28), Color3.fromRGB(164, 91, 255),
	Color3.fromRGB(255, 77, 151), Color3.fromRGB(0, 209, 185),
	Color3.fromRGB(255, 205, 35), Color3.fromRGB(255, 94, 65),
}
local PATH_THICKNESS = 0.68 * 1.15 * 1.20
local SELECTION_SCALE = 0.85
local LETTER_CELL_SCALE = 0.60
local thumbnails = {}
local thumbnailRequests = {}

local portraitTokens = setmetatable({}, { __mode = "k" })
local function portrait(node, userId, suppliedImage)
	if not node or not (node:IsA("ImageLabel") or node:IsA("ImageButton")) then return end
	local token = {}
	portraitTokens[node] = token
	if type(suppliedImage) == "string" and suppliedImage ~= "" then
		Effects.SetPortraitImage(node, suppliedImage)
		return
	end
	-- Simulated IDs are not Roblox accounts; bots always supply verified images.
	if type(userId) ~= "number" or userId <= 0 then return end
	Effects.SetPortraitImage(node, thumbnails[userId] or ("rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150"))
	if thumbnails[userId] then return end
	local target = { node = node, token = token }
	if thumbnailRequests[userId] then
		table.insert(thumbnailRequests[userId], target)
		return
	end
	local targets = { target }
	thumbnailRequests[userId] = targets
	task.spawn(function()
		local ok, image, ready = pcall(Players.GetUserThumbnailAsync, Players, userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if ok and ready ~= false and type(image) == "string" and image ~= "" then
			thumbnails[userId] = image
			for _, entry in ipairs(targets) do
				if entry.node.Parent and portraitTokens[entry.node] == entry.token then Effects.SetPortraitImage(entry.node, image) end
			end
		end
		thumbnailRequests[userId] = nil
	end)
end

local function setWordText(row, word, found)
	local label = row and row:FindFirstChild("Word")
	if not label then return end
	local escaped = word:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	label.RichText = true
	label.Text = found and ("<s>" .. escaped .. "</s>") or escaped
end

local function setText(root, name, value)
	local node = root and root:FindFirstChild(name)
	if node and (node:IsA("TextLabel") or node:IsA("TextButton")) then node.Text = value end
end

local function roundCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

function BoardController.new(ui, callbacks)
	local self = setmetatable({
		ui = ui, callbacks = callbacks, rows = {}, tiles = {}, lines = {}, members = {},
		found = {}, hinted = {}, hintPulses = {}, selection = {}, connections = {}, generation = 0, busy = false,
		wordColors = {}, colorIndex = 0, entering = false, portraitColors = {},
		portraitPalette = Effects.NewPortraitPalette(Random.new()),
	}, BoardController)
	local grid = Instance.new("Frame")
	grid.Name = "PuzzleGrid"
	grid.BackgroundTransparency = 1
	grid.AnchorPoint = Vector2.new(0.5, 0.5)
	grid.Position = UDim2.fromScale(0.5, 0.5)
	grid.Size = UDim2.fromScale(0.94, 0.94)
	grid.ClipsDescendants = false
	grid.ZIndex = ui.boardPanel.ZIndex + 1
	grid.Parent = ui.boardPanel
	self.grid = grid
	table.insert(self.connections, grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:RefreshLines() end))
	if ui.game then
		table.insert(self.connections, ui.game:GetPropertyChangedSignal("Visible"):Connect(function() self:RefreshLines() end))
	end
	return self
end

function BoardController:Interactive()
	return self.puzzle ~= nil and not self.completed and not self.busy and not self.entering and self.callbacks.canInteract()
end

function BoardController:ScreenPoint(position)
	local point = Vector2.new(position.X, position.Y)
	if not self.ui.screenGui.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()
		point -= inset
	end
	return point
end

function BoardController:CellAt(position, clampToGrid)
	if not self.puzzle then return nil end
	local size = self.grid.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return nil end
	local offset = self:ScreenPoint(position) - self.grid.AbsolutePosition
	local row = math.floor(offset.Y / size.Y * self.height) + 1
	local column = math.floor(offset.X / size.X * self.width) + 1
	if not clampToGrid and (row < 1 or row > self.height or column < 1 or column > self.width) then return nil end
	return { row = math.clamp(row, 1, self.height), column = math.clamp(column, 1, self.width) }
end

function BoardController:Center(cell)
	return Vector2.new((cell.column - 0.5) / self.width * self.grid.AbsoluteSize.X,
		(cell.row - 0.5) / self.height * self.grid.AbsoluteSize.Y)
end

function BoardController:NextLineColor()
	self.colorIndex += 1
	-- Golden-angle hues keep long sessions varied after the initial vibrant palette.
	return LINE_COLORS[self.colorIndex] or Color3.fromHSV((self.colorIndex * 0.61803398875) % 1, 0.78, 1)
end

function BoardController:PortraitColor(userId)
	if not self.portraitColors[userId] then self.portraitColors[userId] = self.portraitPalette.Next() end
	return self.portraitColors[userId]
end

function BoardController:Line(name, cells, color, transparency)
	if #cells == 0 then return end
	local line = self.lines[name]
	if not line then
		line = Instance.new("Frame")
		line.Name = name
		line.BorderSizePixel = 0
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.ZIndex = self.grid.ZIndex + 1
		line.Parent = self.grid
		roundCorner(line, 100)
		self.lines[name] = line
	end
	local first, last = self:Center(cells[1]), self:Center(cells[#cells])
	local delta = last - first
	local thickness = math.min(self.grid.AbsoluteSize.X / self.width, self.grid.AbsoluteSize.Y / self.height) * PATH_THICKNESS
	if name == "Selection" then
		thickness *= SELECTION_SCALE
		self.selectionMotion = self.selectionMotion or Effects.CreateLineMotion(line)
		self.selectionMotion:Move(first, last, thickness, self.startCell ~= nil)
	else
		line.Position = UDim2.fromOffset((first.X + last.X) / 2, (first.Y + last.Y) / 2)
		line.Size = UDim2.fromOffset(delta.Magnitude + thickness, thickness)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency
	line.Visible = true
	return line
end

function BoardController:StopHintPulses()
	for word, cancel in pairs(self.hintPulses) do cancel() self.hintPulses[word] = nil end
end

function BoardController:RefreshLines()
	if not self.puzzle then return end
	local visible = not self.ui.game or self.ui.game.Visible
	for word, cancel in pairs(self.hintPulses) do
		if not visible or not self.hinted[word] or self.found[word] then
			cancel()
			self.hintPulses[word] = nil
		end
	end
	for _, line in pairs(self.lines) do line.Visible = false end
	for word in pairs(self.found) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed then self:Line("Found_" .. word, placed.path, self.wordColors[word], 0.18) end
	end
	for word in pairs(self.hinted) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed and not self.found[word] then
			local existing = self.lines["Hint_" .. word]
			local transparency = self.hintPulses[word] and existing.BackgroundTransparency or 0.30
			local line = self:Line("Hint_" .. word, placed.path, Color3.fromRGB(255, 224, 107), transparency)
			if visible and not self.hintPulses[word] then self.hintPulses[word] = Effects.PulseHint(line) end
		end
	end
	if self.startCell then self:Line("Selection", self.selection, self.selectionColor, 0.25) end
end

function BoardController:Cancel()
	if self.selectionMotion then self.selectionMotion:Cancel() end
	self.startCell, self.activeInput, self.inputType = nil, nil, nil
	self.selection = {}
	self:RefreshLines()
end

function BoardController:Begin(position, input)
	if not self:Interactive() then return false end
	local cell = self:CellAt(position, false)
	if not cell then return false end
	self:Cancel()
	self.startCell, self.cursor = cell, cell
	self.activeInput, self.inputType = input, input.UserInputType
	self.selection = { cell }
	self.selectionColor = self:NextLineColor()
	self:RefreshLines()
	return true
end

function BoardController:MoveToCell(cell)
	if not self.startCell then return end
	local dr, dc = cell.row - self.startCell.row, cell.column - self.startCell.column
	local sr, sc = math.sign(dr), math.sign(dc)
	if math.abs(dr) < math.abs(dc) * 0.45 then sr = 0
	elseif math.abs(dc) < math.abs(dr) * 0.45 then sc = 0 end
	local length = math.max(math.abs(dr), math.abs(dc))
	if sr ~= 0 and sc ~= 0 then length = math.floor((math.abs(dr) + math.abs(dc)) / 2 + 0.5) end
	if sr ~= 0 then length = math.min(length, sr > 0 and self.height - self.startCell.row or self.startCell.row - 1) end
	if sc ~= 0 then length = math.min(length, sc > 0 and self.width - self.startCell.column or self.startCell.column - 1) end
	self.selection = Engine.GetLineSequence(self.startCell.row, self.startCell.column,
		self.startCell.row + sr * length, self.startCell.column + sc * length) or { self.startCell }
	self:RefreshLines()
end

function BoardController:Move(position)
	if not self.startCell then return end
	if not self:Interactive() then self:Cancel() return end
	local cell = self:CellAt(position, true)
	if cell then self:MoveToCell(cell) end
end

function BoardController:Finish()
	if not self.startCell then return end
	local cells, color = self.selection, self.selectionColor
	self:Cancel()
	if not self:Interactive() or #cells < 2 then return end
	for _, word in ipairs(self.puzzle.words) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed and Engine.PathsMatch(cells, placed.path, true) then
			if self.found[word] then return end
			local generation = self.generation
			self.wordColors[word] = color
			self.busy = true
			task.spawn(function()
				local ok, err = pcall(self.callbacks.submit, word, cells)
				if not ok then warn("[BoardController] Word submission failed:", err) end
				if generation == self.generation then self.busy = false end
			end)
			return
		end
	end
	local line = self:Line("Selection", cells, Color3.fromRGB(255, 63, 83), 0.12)
	Effects.WrongWord(line)
	self:RefreshLines()
	self.callbacks.playSound("Error2")
	if self.mode == "Hardcore" and self.callbacks.invalidSelection then
		local generation = self.generation
		self.busy = true
		task.spawn(function()
			local ok, err = pcall(self.callbacks.invalidSelection, cells)
			if not ok then warn("[BoardController] Wrong selection submission failed:", err) end
			if generation == self.generation then self.busy = false end
		end)
	end
end

function BoardController:KeyboardMove(rowDelta, columnDelta)
	if not self:Interactive() then return end
	local cell = self.cursor or { row = 1, column = 1 }
	self.cursor = { row = math.clamp(cell.row + rowDelta, 1, self.height), column = math.clamp(cell.column + columnDelta, 1, self.width) }
	self:MoveToCell(self.cursor)
end

function BoardController:ActivateCell(cell)
	if not self:Interactive() then return end
	self.cursor = cell
	if self.startCell then
		self:MoveToCell(cell)
		self:Finish()
	else
		self.startCell = cell
		self.selection = { cell }
		self.selectionColor = self:NextLineColor()
		self:RefreshLines()
	end
end

function BoardController:BuildGridLines()
	local function divider(name, position, size, anchor)
		local line = Instance.new("Frame")
		line.Name = name
		line.AnchorPoint = anchor
		line.Position = position
		line.Size = size
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.fromRGB(145, 171, 190)
		line.BackgroundTransparency = 0.82
		line.Active = false
		line.Selectable = false
		line.ZIndex = self.grid.ZIndex
		line.Parent = self.grid
	end
	for row = 1, self.height - 1 do
		divider("GridRow_" .. row, UDim2.fromScale(0, row / self.height),
			UDim2.new(1, 0, 0, 1), Vector2.new(0, 0.5))
	end
	for column = 1, self.width - 1 do
		divider("GridColumn_" .. column, UDim2.fromScale(column / self.width, 0),
			UDim2.new(0, 1, 1, 0), Vector2.new(0.5, 0))
	end
end

function BoardController:Build(puzzle, mode, solo)
	self.solo = solo == true or mode == "Mini" or mode == "Jumbo" or mode == "Hardcore" or mode == "Tutorial"
	for _, cancel in pairs(self.scoreEffects or {}) do cancel() end
	self.scoreEffects, self.duelScores = {}, {}
	if self.cancelEntrance then self.cancelEntrance() end
	self.generation += 1
	self.entering = true
	self.busy = false
	self:Cancel()
	self:StopHintPulses()
	for _, row in pairs(self.rows) do row:Destroy() end
	for _, child in ipairs(self.grid:GetChildren()) do child:Destroy() end
	self.rows, self.tiles, self.lines, self.found, self.hinted, self.members = {}, {}, {}, {}, {}, {}
	self.wordColors, self.colorIndex, self.portraitColors, self.selectionMotion = {}, 0, {}, nil
	self.puzzle, self.mode, self.completed = puzzle, mode, false
	self.height = #puzzle.letters
	self.width = #puzzle.letters[1]
	local aspect = self.width / self.height
	local constraint = self.ui.boardPanel:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not constraint then
		constraint = Instance.new("UIAspectRatioConstraint")
		constraint.Parent = self.ui.boardPanel
	end
	constraint.AspectRatio = aspect
	if math.abs(aspect - 1) < 0.01 then
		self.ui.boardPanel.Position = UDim2.fromScale(0.387, 0.5)
		self.ui.wordPanel.Position = UDim2.fromScale(0.667, 0.5)
	else
		self.ui.boardPanel.Position = UDim2.fromScale(0.39, 0.5)
		self.ui.wordPanel.Position = UDim2.fromScale(0.75, 0.5)
	end
	self.ui.title.Text = mode == "Duel" and "1V1" or mode == "Timed" and "TIMED"
		or (mode == "Mini" or mode == "Jumbo" or mode == "Hardcore") and string.upper(mode) or "THEMES"
	self.ui.subtitle.Visible = mode ~= "Duel" and mode ~= "Timed"
	self.ui.subtitle.Text = mode == "Hardcore" and "One wrong word ends the round" or puzzle.title or puzzle.subtitle or ""
	if self.ui.duel then self.ui.duel.Visible = mode == "Duel" end
	if self.ui.timed then self.ui.timed.Visible = mode == "Timed" end
	self:BuildGridLines()
	for row = 1, self.height do
		self.tiles[row] = {}
		for column = 1, self.width do
			local cell = { row = row, column = column }
			local tile = Instance.new("TextButton")
			tile.Name = string.format("Cell_%d_%d", row, column)
			tile.BackgroundTransparency = 1
			tile.AutoButtonColor = false
			tile.Text = puzzle.letters[row][column]
			tile.Font = Enum.Font.GothamMedium
			tile.TextColor3 = Color3.fromRGB(13, 43, 65)
			tile.TextScaled = true
			tile.Selectable = true
			-- More whitespace around each glyph; full cells still handle pointer selection.
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Size = UDim2.fromScale(LETTER_CELL_SCALE / self.width, LETTER_CELL_SCALE / self.height)
			tile.Position = UDim2.fromScale((column - 0.5) / self.width, (row - 0.5) / self.height)
			tile.ZIndex = self.grid.ZIndex + 2
			tile.Parent = self.grid
			self.tiles[row][column] = tile
			tile.SelectionGained:Connect(function()
				self.cursor = cell
				if self.startCell then self:MoveToCell(cell) end
			end)
			tile.Activated:Connect(function()
				-- Pointer drags are handled centrally, with exact touch identity.
				local last = game:GetService("UserInputService"):GetLastInputType()
				if string.find(tostring(last), "Gamepad") then self:ActivateCell(cell) end
			end)
		end
	end
	for row = 1, self.height do
		for column = 1, self.width do
			local tile = self.tiles[row][column]
			tile.NextSelectionUp = self.tiles[math.max(1, row - 1)][column]
			tile.NextSelectionDown = self.tiles[math.min(self.height, row + 1)][column]
			tile.NextSelectionLeft = self.tiles[row][math.max(1, column - 1)]
			tile.NextSelectionRight = self.tiles[row][math.min(self.width, column + 1)]
		end
	end
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	self.exceedsTemplate = assets and assets:FindFirstChild("Exceeds")
	local template = assets and assets:FindFirstChild("WordPanelTemplate")
	assert(template and template:IsA("GuiObject"), "Missing ReplicatedStorage.Assets.WordPanelTemplate")
	self.rowBackgroundColor, self.rowBackgroundTransparency = template.BackgroundColor3, template.BackgroundTransparency
	for index, word in ipairs(puzzle.words) do
		local row = template:Clone()
		row.Name = "Word_" .. word
		row.LayoutOrder = index
		row.Visible = true
		row.Parent = self.ui.wordList
		setWordText(row, word, false)
		local line = row:FindFirstChild("BreakLine")
		if line then line.Visible = true end
		local playerTemplate = row:FindFirstChild("PlayerTemplate")
		if playerTemplate then playerTemplate.Visible = false end
		local panel = row:FindFirstChild("FoundPanel")
		if panel then
			panel.Visible = true
			for _, child in ipairs(panel:GetChildren()) do
				if child:IsA("GuiObject") then child.Visible = false end
			end
		end
		self.rows[word] = row
	end
	self.ui.words.Text = "0/" .. #puzzle.words
	self.cursor = { row = 1, column = 1 }
	self:RefreshLines()
	local generation = self.generation
	self.cancelEntrance = Effects.RevealBoard(self.grid, self.tiles, function()
		if generation == self.generation then
			self.entering = false
			self:RefreshLines()
		end
	end)
	self.callbacks.playSound("Appear")
end

function BoardController:Progress(members)
	if not self.puzzle then return end
	local oldFound, newWords = self.found, {}
	self.members = members
	self.found, self.hinted = {}, {}
	for _, member in ipairs(members) do
		if member.userId == Players.LocalPlayer.UserId then
			self.found = table.clone(member.foundWords or {})
			self.hinted = table.clone(member.hintedWords or {})
		end
	end
	local count = 0
	for wordIndex, word in ipairs(self.puzzle.words) do
		local row = self.rows[word]
		local line = row and row:FindFirstChild("BreakLine")
		local ownFound = self.found[word] == true
		if ownFound then
			count += 1
			self.wordColors[word] = self.wordColors[word] or self:NextLineColor()
			if not oldFound[word] then table.insert(newWords, word) end
		end
		if line then line.Visible = true end
		setWordText(row, word, ownFound)
		if row then
			row.LayoutOrder = ownFound and wordIndex or (#self.puzzle.words + wordIndex)
			row.BackgroundColor3 = ownFound and self.wordColors[word] or self.rowBackgroundColor
			row.BackgroundTransparency = ownFound and 0.75 or self.rowBackgroundTransparency
		end
		local panel = row and row:FindFirstChild("FoundPanel")
		local template = row and row:FindFirstChild("PlayerTemplate")
		if panel and template then
			local present, finders = {}, {}
			for rosterIndex, member in ipairs(members) do
				if not self.solo and member.foundWords and member.foundWords[word] then
					table.insert(finders, { member = member, order = (member.foundOrder or {})[word] or math.huge, rosterIndex = rosterIndex })
				end
			end
			table.sort(finders, function(left, right)
				if left.order ~= right.order then return left.order < right.order end
				return left.rosterIndex < right.rosterIndex
			end)
			local layout = panel:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
			for index = 1, math.min(3, #finders) do
				local member = finders[index].member
				local name = "Finder_" .. tostring(member.userId)
				present[name] = true
				local mugshot = panel:FindFirstChild(name)
				if not mugshot then
					mugshot = template:Clone()
					mugshot.Name, mugshot.Visible, mugshot.Parent = name, true, panel
					portrait(mugshot, member.userId, member.isBot and member.thumbnailImage or nil)
					Effects.PopIn(mugshot)
				end
				mugshot.LayoutOrder = index
				local color = self:PortraitColor(member.userId)
				mugshot.BackgroundColor3, mugshot.BackgroundTransparency = color, 0
				local stroke = mugshot:FindFirstChildOfClass("UIStroke")
				if not stroke then stroke = Instance.new("UIStroke") stroke.Parent = mugshot end
				stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.3)
			end
			for _, child in ipairs(panel:GetChildren()) do
				if string.sub(child.Name, 1, 7) == "Finder_" and not present[child.Name] then child:Destroy() end
			end
			local exceeds = panel:FindFirstChild("Exceeds")
			if #finders > 3 then
				if not exceeds then
					assert(self.exceedsTemplate, "Missing ReplicatedStorage.Assets.Exceeds")
					exceeds = self.exceedsTemplate:Clone()
					exceeds.Name, exceeds.Parent = "Exceeds", panel
					Effects.PopIn(exceeds)
				end
				exceeds.Visible, exceeds.LayoutOrder = true, 4
				local label = assert(exceeds:FindFirstChild("TextLabel"), "Missing Exceeds.TextLabel")
				label.Text = "+" .. tostring(#finders - 3)
			elseif exceeds then exceeds:Destroy() end
		end
	end
	self.completed = count == #self.puzzle.words
	self.ui.words.Text = string.format("%d/%d", count, #self.puzzle.words)
	self:RefreshLines()
	if #newWords > 0 then
		Effects.Pulse(self.ui.words, self.completed and 1.08 or 1.035)
		if self.completed then Effects.SoftHighlight(self.ui.boardPanel, Color3.fromRGB(164, 232, 207)) end
	end
	for _, word in ipairs(newWords) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed then
			local tiles = {}
			for _, cell in ipairs(placed.path) do table.insert(tiles, self.tiles[cell.row][cell.column]) end
			Effects.WordFound(self.lines["Found_" .. word], tiles, self.rows[word], self.wordColors[word])
		end
	end
	if #newWords > 0 then self.callbacks.playSound(self.completed and "Victory" or "NotificationHigh") end
end

function BoardController:DuelPlayers(opponentId, opponentName, opponentImage, myStats, opponentStats)
	for _, cancel in pairs(self.scoreEffects or {}) do cancel() end
	self.scoreEffects, self.duelScores = {}, {}
	local ui = self.ui.duel
	if not ui then return end
	portrait(ui:FindFirstChild("YouMugshot"), Players.LocalPlayer.UserId)
	portrait(ui:FindFirstChild("EnemyMugshot"), opponentId, opponentImage)
	setText(ui, "YouUsername", Players.LocalPlayer.DisplayName)
	setText(ui, "EnemyUsername", opponentName or "")
	self:DuelWinRates(myStats, opponentStats)
end

function BoardController:DuelWinRates(myStats, opponentStats)
	if not self.ui.duel then return end
	for name, stats in pairs({ YouWinRate = myStats or {}, EnemyWinRate = opponentStats or {} }) do
		local label = self.ui.duel:FindFirstChild(name)
		if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
			label.Text = Effects.DuelWinRateText(stats)
			label.Visible = true
		end
	end
end

function BoardController:DuelScores(mine, opponent)
	self.scoreEffects, self.duelScores = self.scoreEffects or {}, self.duelScores or {}
	for name, count in pairs({YouScore=mine, EnemyScore=opponent}) do
		local previous = self.duelScores[name]
		setText(self.ui.duel, name, tostring(count))
		if previous ~= nil and previous ~= count then
			if self.scoreEffects[name] then self.scoreEffects[name]() end
			local label = self.ui.duel and self.ui.duel:FindFirstChild(name)
			self.scoreEffects[name] = Effects.ScoreChanged(label, count % 2 == 0 and -1 or 1)
		end
		self.duelScores[name] = count
	end
end

BoardController.Portrait = portrait

return BoardController
