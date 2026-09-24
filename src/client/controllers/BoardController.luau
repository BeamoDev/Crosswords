local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local shared = ReplicatedStorage:WaitForChild("shared")
local Engine = require(shared.puzzle.PuzzleEngine)
local Effects = require(shared.ui.UIEffects)
local Score = require(shared.config.ProgressionConfig).Score

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
local TILE_CELL_SCALE = 0.76
local SELECTION_GREY = Color3.fromRGB(164, 170, 179)
local HINT_GOLD = Color3.fromRGB(255, 199, 55)
local TILE_WHITE = Color3.fromRGB(255, 255, 255)
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
		timedOriginalPosition = ui.timed and ui.timed.Position,
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
	return self.puzzle ~= nil and not self.completed and not self.timeExpired and not self.busy and not self.entering and self.callbacks.canInteract()
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
	if self.adjacent then
		-- Gaps do not select a side neighbour while crossing a diagonal corner.
		local x = offset.X / size.X * self.width - (column - 0.5)
		local y = offset.Y / size.Y * self.height - (row - 0.5)
		if math.abs(x) > TILE_CELL_SCALE / 2 or math.abs(y) > TILE_CELL_SCALE / 2 then return nil end
	end
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
	if self.adjacent then
		local group = self.lines[name]
		if not group then
			group = Instance.new("Frame")
			group.Name, group.BackgroundTransparency, group.BorderSizePixel = name, 1, 0
			group.Size = UDim2.fromScale(1, 1)
			group.ZIndex, group.Parent = self.grid.ZIndex + 2, self.grid
			self.lines[name] = group
		end
		local cellSize = math.min(self.grid.AbsoluteSize.X / self.width, self.grid.AbsoluteSize.Y / self.height)
		local thickness = cellSize * 0.16
		for index = 1, #cells - 1 do
			local segment = group:FindFirstChild("Segment" .. index)
			local created = segment == nil
			if not segment then
				segment = Instance.new("Frame")
				segment.Name, segment.BorderSizePixel = "Segment" .. index, 0
				segment.AnchorPoint = Vector2.new(0.5, 0.5)
				segment.ZIndex, segment.Parent = group.ZIndex, group
				roundCorner(segment, 100)
				local core = Instance.new("Frame")
				core.Name, core.BorderSizePixel = "Core", 0
				core.AnchorPoint, core.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
				core.Size = UDim2.fromScale(0.96, 0.52)
				core.ZIndex, core.Parent = segment.ZIndex, segment
				roundCorner(core, 100)
			end
			local first, last = self:Center(cells[index]), self:Center(cells[math.min(index + 1, #cells)])
			local delta = last - first
			segment.Position = UDim2.fromOffset((first.X + last.X) / 2, (first.Y + last.Y) / 2)
			-- Bridge tile edges instead of drawing a bar through the glyphs.
			local edgeDistance = cellSize * TILE_CELL_SCALE * 0.5 * delta.Magnitude
				/ math.max(1, math.abs(delta.X), math.abs(delta.Y))
			segment.Size = UDim2.fromOffset(math.max(thickness, delta.Magnitude - edgeDistance * 1.6), thickness)
			segment.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			if created and name == "Selection" then Effects.RevealLink(segment) end
			if not (name:sub(1, 5) == "Hint_" and self.hintPulses[name:sub(6)]) then
				segment.BackgroundColor3 = color
				segment:FindFirstChild("Core").BackgroundColor3 = color
				segment.BackgroundTransparency = name:sub(1, 6) == "Found_" and 0 or transparency
			end
		end
		for _, child in ipairs(group:GetChildren()) do
			local index = tonumber(child.Name:match("^Segment(%d+)$"))
			if index and index > #cells - 1 then child:Destroy() end
		end
		group.Visible = true
		return group
	end
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
		if placed then self:Line("Found_" .. word, self.submittedPaths and self.submittedPaths[word] or placed.path, self.wordColors[word], 0.18) end
	end
	for word in pairs(self.hinted) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed and not self.found[word] then
			local existing = self.lines["Hint_" .. word]
			local transparency = not self.adjacent and self.hintPulses[word] and existing.BackgroundTransparency or 0.30
			local line = self:Line("Hint_" .. word, placed.path, Color3.fromRGB(255, 224, 107), transparency)
			if visible and not self.hintPulses[word] then
				if self.adjacent then
					local cancels = {}
					for _, segment in ipairs(line:GetChildren()) do
						table.insert(cancels, Effects.PulseHint(segment, HINT_GOLD))
						table.insert(cancels, Effects.PulseHint(segment:FindFirstChild("Core"), HINT_GOLD))
					end
					for _, cell in ipairs(placed.path) do
						local face = self.tileFaces[cell.row][cell.column]:FindFirstChild("WhiteFace")
						table.insert(cancels, Effects.PulseHint(face, HINT_GOLD))
					end
					self.hintPulses[word] = function() for _, cancel in ipairs(cancels) do cancel() end end
				else self.hintPulses[word] = Effects.PulseHint(line) end
			end
		end
	end
	if self.startCell then self:Line("Selection", self.selection, self.selectionColor, 0.25) end
	if self.adjacent then self:RefreshTiles() end
end

function BoardController:RefreshTiles()
	local selected = {}
	self.solvedCells = {}
	for word in pairs(self.found) do
		for _, cell in ipairs(self.puzzle.placedWordsByWord[word].path) do self.solvedCells[cell.row .. ":" .. cell.column] = word end
	end
	for _, cell in ipairs(self.selection) do selected[cell.row .. ":" .. cell.column] = true end
	for row, tiles in ipairs(self.tiles) do
		for column, tile in ipairs(tiles) do
			local plate = self.tileFaces and self.tileFaces[row] and self.tileFaces[row][column]
			if plate then
				local active = selected[row .. ":" .. column]
				local solved = self.solvedCells[row .. ":" .. column]
				local highlighted = active or solved ~= nil
				plate.BackgroundColor3 = TILE_WHITE
				self.tileFeedback[row][column]:Set(highlighted == true, not self.entering,
					active and self.selectionColor or (solved and self.wordColors[solved]))
				tile.TextColor3 = solved and TILE_WHITE or Color3.fromRGB(24, 28, 22)
				local border = plate:FindFirstChildOfClass("UIStroke")
				if border then
					local cursor = self.keyboardCursorVisible and self.cursor and self.cursor.row == row and self.cursor.column == column
					border.Color = cursor and SELECTION_GREY or Color3.new(0, 0, 0)
					border.Transparency = cursor and 0.1 or 0.82
					border.Thickness = cursor and 2 or 1
				end
			end
		end
	end
end

function BoardController:Cancel()
	if self.selectionMotion then self.selectionMotion:Cancel() end
	self.startCell, self.activeInput, self.inputType = nil, nil, nil
	self.lastPointerPosition = nil
	self.selection = {}
	self:RefreshLines()
end

function BoardController:ClearWrongFeedback()
	if self.cancelWrongFeedback then self.cancelWrongFeedback() self.cancelWrongFeedback = nil end
end

function BoardController:Begin(position, input)
	if not self:Interactive() then return false end
	if self.callbacks.blocksPointer and self.callbacks.blocksPointer(position) then return false end
	local cell = self:CellAt(position, false)
	if not cell then return false end
	self:ClearWrongFeedback()
	self:Cancel()
	self.startCell, self.cursor = cell, cell
	self.keyboardCursorVisible = false
	self.activeInput, self.inputType = input, input.UserInputType
	self.lastPointerPosition = position
	self.selection = { cell }
	self.selectionColor = self.adjacent and SELECTION_GREY or self:NextLineColor()
	self:RefreshLines()
	return true
end

function BoardController:MoveToCell(cell)
	if not self.startCell then return end
	if self.adjacent then
		if Engine.ExtendAdjacentPath(self.selection, cell) then self:RefreshLines() end
		return
	end
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
	if self.adjacent and self.lastPointerPosition then
		local start = self.lastPointerPosition
		local dx, dy = position.X - start.X, position.Y - start.Y
		local size = self.grid.AbsoluteSize
		local steps = math.clamp(math.ceil(math.max(math.abs(dx) / math.max(1, size.X / self.width),
			math.abs(dy) / math.max(1, size.Y / self.height)) * 4), 1, 128)
		for index = 1, steps do
			local cell = self:CellAt(Vector2.new(start.X + dx * index / steps, start.Y + dy * index / steps), false)
			if cell then self:MoveToCell(cell) end
		end
		self.lastPointerPosition = position
		return
	end
	local cell = self:CellAt(position, not self.adjacent)
	if cell then self:MoveToCell(cell) end
end

function BoardController:Finish()
	if not self.startCell then return end
	local cells, color = self.selection, self.selectionColor
	self:Cancel()
	if not self:Interactive() or #cells < 2 then return end
	local spelling = self.adjacent and Engine.ReadAdjacentWord(self.puzzle.letters, cells)
	if self.adjacent and (not spelling or #spelling < 3) then
		return
	end
	for _, word in ipairs(self.puzzle.words) do
		local placed = self.puzzle.placedWordsByWord[word]
		if placed and (self.adjacent and Engine.MatchesStrand(self.puzzle, word, cells)
			or not self.adjacent and Engine.PathsMatch(cells, placed.path, true)) then
			if self.found[word] then return end
			local generation = self.generation
			if not self.adjacent then self.wordColors[word] = color end
			self.submittedPaths = self.submittedPaths or {}
			self.submittedPaths[word] = cells
			self.busy = true
			task.spawn(function()
				local ok, err = pcall(self.callbacks.submit, word, cells)
				if not ok then warn("[BoardController] Word submission failed:", err) end
				if generation == self.generation then self.busy = false end
			end)
			return
		end
	end
	if self.adjacent then
		local bonus = Engine.ReadBonusWord(self.puzzle, cells)
		if bonus then
			if self.bonusWords[bonus] or self.found[bonus] then return end
			self.bonusPaths[bonus] = cells
			local generation = self.generation
			self.busy = true
			task.spawn(function()
				local ok, err = pcall(self.callbacks.submit, bonus, cells)
				if not ok then warn("[BoardController] Bonus submission failed:", err) end
				if generation == self.generation then self.busy = false end
			end)
			return
		end
	end
	local line = self:Line("Selection", cells, Color3.fromRGB(255, 63, 83), 0.12)
	self:ClearWrongFeedback()
	if self.adjacent then
		local faces, letters = {}, {}
		for _, cell in ipairs(cells) do
			table.insert(faces, self.tileFaces[cell.row][cell.column])
			table.insert(letters, self.tiles[cell.row][cell.column])
		end
		self.cancelWrongFeedback = Effects.WrongWord(line, faces, letters)
	else self.cancelWrongFeedback = Effects.WrongWord(line) end
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
	self.keyboardCursorVisible = true
	self:MoveToCell(self.cursor)
	if self.adjacent then self:RefreshTiles() end
end

function BoardController:ActivateCell(cell)
	if not self:Interactive() then return end
	self.cursor = cell
	if self.startCell then
		self:MoveToCell(cell)
		self:Finish()
	else
		self:ClearWrongFeedback()
		self.startCell = cell
		self.selection = { cell }
		self.selectionColor = self.adjacent and SELECTION_GREY or self:NextLineColor()
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
	self:ClearWrongFeedback()
	self.solo = solo == true or mode == "Mini" or mode == "Jumbo" or mode == "Hardcore" or mode == "Tutorial"
	for _, cancel in pairs(self.scoreEffects or {}) do cancel() end
	self.scoreEffects, self.duelScores = {}, {}
	if self.cancelEntrance then self.cancelEntrance() end
	self.generation += 1
	self.entering = true
	self.busy = false
	self:Cancel()
	self:StopHintPulses()
	for _, row in pairs(self.tileFeedback or {}) do
		for _, feedback in pairs(row) do feedback:Destroy() end
	end
	for _, row in pairs(self.rows) do row:Destroy() end
	for _, child in ipairs(self.grid:GetChildren()) do child:Destroy() end
	self.rows, self.tiles, self.lines, self.found, self.hinted, self.members = {}, {}, {}, {}, {}, {}
	self.tileFaces, self.tileShadows, self.tileFeedback = {}, {}, {}
	self.wordColors, self.colorIndex, self.portraitColors, self.selectionMotion = {}, 0, {}, nil
	self.puzzle, self.mode, self.completed, self.timeExpired = puzzle, mode, false, false
	self:UpdateScore(0, true)
	self.adjacent, self.submittedPaths, self.keyboardCursorVisible = puzzle.rules == "Strands", {}, false
	self.bonusWords, self.bonusPaths = {}, {}
	self.grid.Size = UDim2.fromScale(self.adjacent and 0.98 or 0.94, self.adjacent and 0.98 or 0.94)
	self.grid.Position = UDim2.fromScale(0.5, 0.5)
	self.height = #puzzle.letters
	self.width = #puzzle.letters[1]
	local aspect = self.width / self.height
	local constraint = self.ui.boardPanel:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not constraint then
		constraint = Instance.new("UIAspectRatioConstraint")
		constraint.Parent = self.ui.boardPanel
	end
	constraint.AspectRatio = self.adjacent and 1 or aspect
	if self.adjacent then
		-- The authored square frame owns its position and size.
	elseif math.abs(aspect - 1) < 0.01 then
		self.ui.boardPanel.Position = UDim2.fromScale(0.387, 0.5)
		self.ui.wordPanel.Position = UDim2.fromScale(0.667, 0.5)
	else
		self.ui.boardPanel.Position = UDim2.fromScale(0.39, 0.5)
		self.ui.wordPanel.Position = UDim2.fromScale(0.75, 0.5)
	end
	if self.ui.title then
		self.ui.title.Text = mode == "Duel" and "1V1" or mode == "Timed" and "TIMED"
			or (mode == "Mini" or mode == "Jumbo" or mode == "Hardcore") and string.upper(mode) or "THEMES"
		if self.adjacent then
			self.ui.title.Text = mode == "Duel" and "1V1 STRANDS" or mode == "Standard" and "STRANDS" or string.upper(mode)
		end
	end
	if self.ui.subtitle then
		self.ui.subtitle.Visible = mode ~= "Duel" and mode ~= "Timed"
		self.ui.subtitle.Text = mode == "Hardcore" and "One wrong word ends the round" or puzzle.title or puzzle.subtitle or ""
		if self.adjacent then
			self.ui.subtitle.Text = (puzzle.clue or puzzle.title or "Find the theme") .. (mode == "Hardcore" and " | One mistake ends the round" or "")
		end
	end
	if self.ui.duel then self.ui.duel.Visible = mode == "Duel" end
	if self.ui.timed then
		self.ui.timed.Visible = true
		self.ui.timed.Position = mode == "Duel" and UDim2.fromScale(0.5, 0.03) or self.timedOriginalPosition
	end
	if not self.adjacent then self:BuildGridLines() end
	if self.adjacent then
		-- Fit all letters inside the authored frame, with no tray or footer.
		local xScale, yScale = math.min(1, aspect), math.min(1, 1 / aspect)
		self.grid.Size = UDim2.fromScale(0.98 * xScale, 0.98 * yScale)
	end
	for row = 1, self.height do
		self.tiles[row] = {}
		self.tileFaces[row], self.tileShadows[row], self.tileFeedback[row] = {}, {}, {}
		for column = 1, self.width do
			local cell = { row = row, column = column }
			local tile = Instance.new("TextButton")
			tile.Name = string.format("Cell_%d_%d", row, column)
			tile.BackgroundTransparency = 1
			tile.AutoButtonColor = false
			tile.Text = puzzle.letters[row][column]
			tile.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
			tile.TextColor3 = Color3.fromRGB(13, 43, 65)
			tile.TextScaled = true
			tile.Selectable = true
			-- More whitespace around each glyph; full cells still handle pointer selection.
			tile.AnchorPoint = Vector2.new(0.5, 0.5)
			tile.Size = UDim2.fromScale(LETTER_CELL_SCALE / self.width, LETTER_CELL_SCALE / self.height)
			tile.Position = UDim2.fromScale((column - 0.5) / self.width, (row - 0.5) / self.height)
			tile.ZIndex = self.grid.ZIndex + (self.adjacent and 3 or 2)
			tile.Parent = self.grid
			if self.adjacent then
				tile.Size = UDim2.fromScale(0.54 / self.width, 0.54 / self.height)
				local textSize = Instance.new("UITextSizeConstraint")
				textSize.MaxTextSize, textSize.MinTextSize, textSize.Parent = 56, 12, tile
				local face = Instance.new("Frame")
				face.Name, face.BorderSizePixel = string.format("TileFace_%d_%d", row, column), 0
				face.AnchorPoint, face.Position = tile.AnchorPoint, tile.Position
				face.Size = UDim2.fromScale(TILE_CELL_SCALE / self.width, TILE_CELL_SCALE / self.height)
				face.BackgroundColor3 = TILE_WHITE
				face.ZIndex, face.Parent = self.grid.ZIndex + 1, self.grid
				self.tileFaces[row][column] = face
				local corner = Instance.new("UICorner")
				corner.CornerRadius, corner.Parent = UDim.new(0.16, 0), face
				local shadow = Instance.new("Frame")
				shadow.Name, shadow.BorderSizePixel = "TileShadow", 0
				shadow.AnchorPoint, shadow.Position, shadow.Size = face.AnchorPoint,
					face.Position + UDim2.fromScale(0, 0.035 * TILE_CELL_SCALE / self.height), face.Size
				shadow.BackgroundColor3, shadow.BackgroundTransparency = Color3.new(0, 0, 0), 0.86
				shadow.ZIndex, shadow.Parent = self.grid.ZIndex, self.grid
				corner:Clone().Parent = shadow
				self.tileShadows[row][column] = shadow
				local gradient = Instance.new("UIGradient")
				gradient.Name, gradient.Rotation, gradient.Enabled = "SelectionGradient", 90, true
				gradient.Color = ColorSequence.new(Color3.fromRGB(207, 255, 77), Color3.fromRGB(66, 211, 0))
				gradient.Parent = face
				local veil = Instance.new("Frame")
				veil.Name, veil.BackgroundColor3, veil.BorderSizePixel = "WhiteFace", TILE_WHITE, 0
				veil.BackgroundTransparency = 0
				veil.Size, veil.ZIndex, veil.Parent = UDim2.fromScale(1, 1), face.ZIndex, face
				corner:Clone().Parent = veil
				local shine = Instance.new("Frame")
				shine.Name, shine.BackgroundTransparency, shine.BorderSizePixel = "SelectionShine", 1, 0
				shine.Position, shine.Size = UDim2.fromScale(0.045, 0.045), UDim2.fromScale(0.91, 0.91)
				shine.ZIndex, shine.Parent = face.ZIndex, face
				corner:Clone().Parent = shine
				local shineBorder = Instance.new("UIStroke")
				shineBorder.Color, shineBorder.Thickness, shineBorder.Transparency = Color3.fromRGB(239, 255, 168), 1.5, 1
				shineBorder.Parent = shine
				local border = Instance.new("UIStroke")
				border.Thickness, border.Color, border.Transparency, border.Parent = 1, Color3.new(0, 0, 0), 0.82, face
				self.tileFeedback[row][column] = Effects.CreateTileFeedback(face, tile)
			end
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
	end, self.tileFaces, self.tileShadows)
	self.callbacks.playSound("Appear")
end

-- Update only from accepted server progress, never from a local drag guess.
function BoardController:UpdateScore(points, reset)
	points = type(points) == "number" and points == points and math.abs(points) < math.huge and math.max(0, math.floor(points)) or 0
	if not reset and self.score == points then return end
	local previousLevel = Score.Level(self.score or 0)
	self.score = points
	local level = Score.Level(points)
	local label, badge = self.ui.scoreText, self.ui.scoreLevel
	if label then label.Text = string.format("Score: %d", points) end
	if badge then
		badge.Text = string.format("%s Level %d", utf8.char(0x1F451), level)
		local colors = {Color3.fromRGB(183,112,55), Color3.fromRGB(180,190,207), Color3.fromRGB(255,202,63), Color3.fromRGB(95,222,255)}
		badge.TextColor3 = colors[math.min(#colors, math.floor((level - 1) / 5) + 1)]
		if not reset and level > previousLevel then Effects.Pulse(badge, 1.06) end
	end
end

function BoardController:Progress(members)
	if not self.puzzle then return end
	local oldFound, newWords = self.found, {}
	local oldBonus = self.bonusWords or {}
	self.bonusWords = {}
	self.members = members
	self.found, self.hinted = {}, {}
	for _, member in ipairs(members) do
		if member.userId == Players.LocalPlayer.UserId then
			self:UpdateScore(member.score or 0)
			self.found = table.clone(member.foundWords or {})
			self.bonusWords = table.clone(member.bonusWords or {})
			self.hinted = table.clone(member.hintedWords or {})
		end
	end
	for word in pairs(self.bonusWords) do
		local path = self.bonusPaths[word]
		if not oldBonus[word] and path then
			local tiles = {}
			for _, cell in ipairs(path) do table.insert(tiles, self.tiles[cell.row][cell.column]) end
			Effects.BonusWordFound(tiles)
			self.callbacks.playSound("NotificationHigh")
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
			row.Visible = true
			if self.adjacent then setWordText(row, word, false) end
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
			local path = self.submittedPaths and self.submittedPaths[word] or placed.path
			for _, cell in ipairs(path) do table.insert(tiles, self.tiles[cell.row][cell.column]) end
			if self.adjacent then
				local faces = {}
				for _, cell in ipairs(path) do table.insert(faces, self.tileFaces[cell.row][cell.column]) end
				Effects.PopIn(self.rows[word])
				Effects.WordFound(tiles[#tiles], tiles, self.rows[word], self.wordColors[word], faces)
			else Effects.WordFound(self.lines["Found_" .. word], tiles, self.rows[word], self.wordColors[word]) end
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
