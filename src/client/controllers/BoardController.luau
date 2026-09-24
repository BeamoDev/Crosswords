local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local shared = ReplicatedStorage:WaitForChild("shared")
local Editing = require(shared.puzzle.CrosswordInput)
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

local function setText(root, name, value)
	local node = root and root:FindFirstChild(name)
	if node and (node:IsA("TextLabel") or node:IsA("TextButton")) then node.Text = value end
end

local function roundCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

-- The generated crossword and keyboard stay inside the authored board frame.
function BoardController.new(ui, callbacks)
    local self = setmetatable({ui=ui, callbacks=callbacks, rows={}, tiles={}, connections={},
        timedOriginalPosition=ui.timed and ui.timed.Position, generation=0, found={}, hinted={},
        wordColors={}, portraitColors={}, colorIndex=0, scoreEffects={},
        portraitPalette=Effects.NewPortraitPalette(Random.new())}, BoardController)
    local grid = Instance.new("Frame")
    grid.Name, grid.BackgroundTransparency = "PuzzleGrid", 1
    grid.AnchorPoint = Vector2.new(0.5, 0.5)
    grid.ZIndex, grid.Parent = ui.boardPanel.ZIndex + 1, ui.boardPanel
    self.grid = grid
    return self
end
function BoardController:Interactive()
    return self.puzzle ~= nil and not self.completed and not self.timeExpired and not self.busy
        and not self.entering and self.ui.game.Visible and self.callbacks.canInteract()
end
function BoardController:NextLineColor()
    self.colorIndex += 1
    return LINE_COLORS[(self.colorIndex - 1) % #LINE_COLORS + 1]
end
function BoardController:PortraitColor(userId)
    if not self.portraitColors[userId] then self.portraitColors[userId] = self.portraitPalette:Next() end
    return self.portraitColors[userId]
end
function BoardController:Cancel()
    self.activeInput, self.startCell = nil, nil
end
function BoardController:SelectEntry(id)
    if self.editing and self.editing:Select(id) then self.feedback = nil self:RefreshTiles() end
end
function BoardController:ActivateCell(cell)
    if not self:Interactive() then return end
    self.editing:SelectCell(cell, true)
    self.feedback = nil
    self:RefreshTiles()
end
function BoardController:KeyboardMove(dr, dc)
    if not self:Interactive() then return end
    self.editing:Move(dr, dc)
    self.feedback = nil
    self:RefreshTiles()
end
function BoardController:Key(value)
    if not self:Interactive() then return end
    self.feedback = nil
    if value == "CHECK" then self:Finish() return
    elseif value == "BACK" then self.editing:Backspace()
    elseif value == "NEXT" then self.editing:Next(1)
    elseif value == "PREV" then self.editing:Next(-1)
    elseif value == "TURN" then self.editing:SelectCell(self.editing:Cursor(), true)
    else self.editing:Type(value) end
    self:RefreshTiles()
end
function BoardController:Reject(id)
    if not self.editing or self.found[id] then return end
    self.feedback = "Not quite. Check the clue and try again."
    self.callbacks.playSound("Error2")
    local row = self.rows[id]
    if row then Effects.SoftHighlight(row, Color3.fromRGB(255, 108, 116)) end
    self:RefreshTiles()
end
function BoardController:Finish()
    if not self:Interactive() or self.found[self.editing.selected] then return end
    local answer = self.editing:Answer()
    if not answer then self.feedback = "Fill every square, then press Check." self:RefreshTiles() return end
    local id, generation = self.editing.selected, self.generation
    self.busy = true
    self:RefreshTiles()
    task.spawn(function()
        local ok, result = pcall(self.callbacks.submit, id, answer)
        if self.generation ~= generation then return end
        self.busy = false
        if not ok or result == nil then
            self.feedback = "Could not check that answer. Please try again."
        elseif result.success == false then self:Reject(id)
        end
        self:RefreshTiles()
    end)
end
function BoardController:RefreshTiles()
    if not self.editing then return end
    local selected, cursor = {}, Editing.Key(self.editing:Cursor())
    for _, cell in ipairs(self.editing:Entry().path) do selected[Editing.Key(cell)] = true end
    local solved = {}
    for _, id in ipairs(self.puzzle.words) do
        if self.found[id] then
            for _, cell in ipairs(self.puzzle.placedWordsByWord[id].path) do
                solved[Editing.Key(cell)] = self.wordColors[id]
            end
        end
    end
    for row, tiles in pairs(self.tiles) do
        for column, tile in pairs(tiles) do
            local k = row .. ":" .. column
            tile.Text = self.editing.locked[k] or self.editing.draft[k] or ""
            tile.TextColor3 = solved[k] and Color3.new(1,1,1) or Color3.fromRGB(18, 43, 63)
            tile.BackgroundColor3 = solved[k] or (k == cursor and Color3.fromRGB(255, 214, 93))
                or (selected[k] and Color3.fromRGB(194, 232, 255))
                or (self.editing.locked[k] and Color3.fromRGB(255, 239, 189)) or Color3.new(1,1,1)
            local border = tile:FindFirstChildOfClass("UIStroke")
            if border then border.Thickness = k == cursor and 2.5 or 1 end
        end
    end
    local entry = self.editing:Entry()
    if self.clueLabel then
        self.clueLabel.Text = self.feedback or (self.busy and "Checking...")
            or string.format("%d %s: %s (%d)", entry.number, entry.direction, entry.clue, entry.length)
    end
    for id, row in pairs(self.rows) do
        row.BackgroundColor3 = self.found[id] and self.wordColors[id]
            or (id == self.editing.selected and Color3.fromRGB(194,232,255)) or self.rowBackgroundColor
        row.BackgroundTransparency = (self.found[id] or id == self.editing.selected) and 0.15 or self.rowBackgroundTransparency
    end
end
-- Retained call site for shared visibility/transition ownership.
function BoardController:RefreshLines() self:RefreshTiles() end

local function button(parent, name, text, position, size)
    local value = Instance.new("TextButton")
    value.Name, value.Text, value.Position, value.Size = name, text, position, size
    value.BackgroundColor3, value.BorderSizePixel = Color3.new(1,1,1), 0
    value.TextColor3, value.TextScaled, value.AutoButtonColor = Color3.fromRGB(18,43,63), true, false
    value.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
    value.ZIndex, value.Selectable, value.Parent = parent.ZIndex + 1, true, parent
    roundCorner(value, 3)
    return value
end
function BoardController:BuildKeyboard()
    local keyboard = Instance.new("Frame")
    keyboard.Name, keyboard.BackgroundTransparency = "CrosswordKeyboard", 1
    keyboard.Position, keyboard.Size = UDim2.fromScale(0.01,0.74), UDim2.fromScale(0.98,0.25)
    keyboard.ZIndex, keyboard.Parent = self.grid.ZIndex, self.ui.boardPanel
    self.keyboard = keyboard
    for row, letters in ipairs({"QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"}) do
        local offset = (10 - #letters) / 20
        for index = 1, #letters do
            local letter = letters:sub(index,index)
            local keyButton = button(keyboard, "Key_"..letter, letter,
                UDim2.fromScale(offset + (index-1)/10, (row-1)/4), UDim2.fromScale(0.092,0.225))
            keyButton.Activated:Connect(function() self:Key(letter) end)
        end
    end
    for _, item in ipairs({{"PREV","Prev",0,0.14},{"BACK","Erase",0.42,0.18},{"NEXT","Next",0.61,0.14},{"CHECK","Check",0.76,0.24}}) do
        local keyButton = button(keyboard, "Key_"..item[1], item[2], UDim2.fromScale(item[3],0.75), UDim2.fromScale(item[4]-0.008,0.225))
        if item[1] == "CHECK" then keyButton.BackgroundColor3 = Color3.fromRGB(137,230,179) end
        keyButton.Activated:Connect(function() self:Key(item[1]) end)
    end
    -- A deliberate user tap opens the platform keyboard. Never CaptureFocus.
    local entryBox = Instance.new("TextBox")
    entryBox.Name, entryBox.Text, entryBox.PlaceholderText = "TypeAnswer", "", "Type answer"
    entryBox.Position, entryBox.Size = UDim2.fromScale(0.15,0.75), UDim2.fromScale(0.26,0.225)
    entryBox.ClearTextOnFocus, entryBox.MultiLine, entryBox.TextScaled = true, false, true
    entryBox.BackgroundColor3, entryBox.TextColor3 = Color3.new(1,1,1), Color3.fromRGB(18,43,63)
    entryBox.ZIndex, entryBox.Parent = keyboard.ZIndex + 1, keyboard
    roundCorner(entryBox,3)
    local typingEntry
    entryBox.Focused:Connect(function() typingEntry = self.editing.selected end)
    entryBox:GetPropertyChangedSignal("Text"):Connect(function()
        if self:Interactive() and entryBox:IsFocused() and typingEntry == self.editing.selected then
            self.editing:SetAnswer(entryBox.Text)
            self.feedback = nil
            self:RefreshTiles()
        end
    end)
    entryBox.FocusLost:Connect(function(enterPressed)
        if enterPressed and typingEntry == self.editing.selected then self:Finish() end
        typingEntry = nil
    end)
end
function BoardController:Build(puzzle, mode, solo)
    assert(puzzle.rules == "Crossword", "Expected a crossword snapshot")
    self.generation += 1
    if self.cancelEntrance then self.cancelEntrance() end
    for _, cancel in pairs(self.scoreEffects) do cancel() end
    self.scoreEffects, self.duelScores = {}, {}
    for _, row in pairs(self.rows) do row:Destroy() end
    for _, child in ipairs(self.grid:GetChildren()) do child:Destroy() end
    if self.keyboard then self.keyboard:Destroy() end
    if self.clueLabel then self.clueLabel:Destroy() end
    self.rows, self.tiles, self.found, self.hinted = {}, {}, {}, {}
    self.wordColors, self.portraitColors, self.colorIndex = {}, {}, 0
    self.puzzle, self.mode, self.solo = puzzle, mode, solo == true or mode == "Mini" or mode == "Jumbo" or mode == "Hardcore"
    self.completed, self.busy, self.entering, self.timeExpired, self.feedback = false, false, true, false, nil
    self.editing = Editing.new(puzzle)
    self.height, self.width = puzzle.gridSize, puzzle.gridWidth
    self:UpdateScore(0, true)
    -- Square cells fit above the keyboard, without changing authored panel geometry.
    local aspect = self.width / self.height
    local h = math.min(0.62, 0.98 / aspect)
    self.grid.Size, self.grid.Position = UDim2.fromScale(h * aspect, h), UDim2.fromScale(0.5,0.40)
    local label = Instance.new("TextLabel")
    label.Name, label.BackgroundTransparency, label.TextWrapped = "CurrentClue", 1, true
    label.Size, label.Position = UDim2.fromScale(0.98,0.08), UDim2.fromScale(0.01,0)
    label.TextScaled, label.TextColor3 = true, Color3.fromRGB(18,43,63)
    label.FontFace = Font.new("rbxasset://fonts/families/Ubuntu.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
    label.ZIndex, label.Parent, self.clueLabel = self.grid.ZIndex, self.ui.boardPanel, label
    self:BuildKeyboard()
    local numbers = {}
    for _, id in ipairs(puzzle.words) do
        local entry = puzzle.placedWordsByWord[id]
        numbers[Editing.Key(entry.path[1])] = entry.number
    end
    for row, letters in ipairs(puzzle.letters) do
        self.tiles[row] = {}
        for column, letter in ipairs(letters) do
            if letter ~= "" then
                local cell = {row=row, column=column}
                local tile = button(self.grid, "Cell_"..row.."_"..column, "",
                    UDim2.fromScale((column-1)/self.width, (row-1)/self.height), UDim2.fromScale(0.96/self.width,0.96/self.height))
                local padding = Instance.new("UIPadding")
                padding.PaddingTop, padding.PaddingBottom = UDim.new(0.16,0), UDim.new(0.04,0)
                padding.PaddingLeft, padding.PaddingRight = UDim.new(0.14,0), UDim.new(0.14,0)
                padding.Parent = tile
                local stroke = Instance.new("UIStroke")
                stroke.ApplyStrokeMode, stroke.Color, stroke.Thickness, stroke.Parent = Enum.ApplyStrokeMode.Border, Color3.fromRGB(80,100,116), 1, tile
                self.tiles[row][column] = tile
                tile.Activated:Connect(function() self:ActivateCell(cell) end)
                local number = numbers[Editing.Key(cell)]
                if number then
                    local n = Instance.new("TextLabel")
                    n.Name, n.Text, n.BackgroundTransparency = "Number", tostring(number), 1
                    n.Position, n.Size = UDim2.fromScale(-0.12,-0.16), UDim2.fromScale(0.4,0.32)
                    n.TextScaled, n.TextColor3, n.ZIndex, n.Parent = true, Color3.fromRGB(18,43,63), tile.ZIndex + 1, tile
                end
            else
                local block = Instance.new("Frame")
                block.Name, block.BorderSizePixel, block.BackgroundColor3 = "Block", 0, Color3.fromRGB(27,47,64)
                block.Position, block.Size = UDim2.fromScale((column-1)/self.width,(row-1)/self.height), UDim2.fromScale(0.96/self.width,0.96/self.height)
                block.ZIndex, block.Parent = self.grid.ZIndex, self.grid
                roundCorner(block, 2)
            end
        end
    end
    local assets = ReplicatedStorage:WaitForChild("Assets",10)
    local template = assets and assets:FindFirstChild("WordPanelTemplate")
    assert(template and template:IsA("GuiObject"), "Missing ReplicatedStorage.Assets.WordPanelTemplate")
    self.exceedsTemplate = assets:FindFirstChild("Exceeds")
    self.rowBackgroundColor, self.rowBackgroundTransparency = template.BackgroundColor3, template.BackgroundTransparency
    if self.ui.wordList:IsA("ScrollingFrame") then self.ui.wordList.AutomaticCanvasSize = Enum.AutomaticSize.Y end
    for _, id in ipairs(puzzle.words) do
        local entry = puzzle.placedWordsByWord[id]
        local row = template:Clone()
        row.Name, row.Visible, row.Parent = "Clue_"..id, true, self.ui.wordList
        row.LayoutOrder = (entry.direction == "Across" and 0 or 100) + entry.number
        -- Longer clues need room to wrap; keep the authored width and decoration.
        row.Size = UDim2.new(row.Size.X.Scale,row.Size.X.Offset,0,100)
        local wordLabel = row:FindFirstChild("Word")
        if wordLabel then
            wordLabel.RichText, wordLabel.TextWrapped, wordLabel.TextScaled = false, true, false
            wordLabel.TextScaled = true
            wordLabel.AnchorPoint, wordLabel.Position = Vector2.new(0,0), UDim2.fromScale(0.025,0.035)
            wordLabel.Size = UDim2.fromScale(0.95,0.66)
            wordLabel.TextXAlignment, wordLabel.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
            local bounds = wordLabel:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
            bounds.MinTextSize, bounds.MaxTextSize, bounds.Parent = 10, 18, wordLabel
            wordLabel.Text = string.format("%d %s  %s (%d)",entry.number,entry.direction,entry.clue,entry.length)
        end
        local divider = row:FindFirstChild("BreakLine")
        if divider then divider.Visible = true end
        local source = row:FindFirstChild("PlayerTemplate")
        if source then source.Visible = false end
        local panel = row:FindFirstChild("FoundPanel")
        if panel then for _, child in ipairs(panel:GetChildren()) do if child:IsA("GuiObject") then child.Visible = false end end end
        local hit = Instance.new("TextButton")
        hit.Name, hit.Text, hit.BackgroundTransparency, hit.AutoButtonColor = "SelectClue", "", 1, false
        hit.Size, hit.ZIndex, hit.Parent = UDim2.fromScale(1,1), row.ZIndex + 5, row
        hit.Activated:Connect(function() if self:Interactive() then self:SelectEntry(id) end end)
        self.rows[id] = row
    end
    if self.ui.title then self.ui.title.Text = mode == "Duel" and "1V1 CROSSWORDS" or mode == "Standard" and "CROSSWORDS" or string.upper(mode) end
    if self.ui.subtitle then self.ui.subtitle.Visible = mode ~= "Duel" and mode ~= "Timed" self.ui.subtitle.Text = mode == "Hardcore" and "One incorrect Check ends the round" or "Solve the Across and Down clues" end
    if self.ui.duel then self.ui.duel.Visible = mode == "Duel" end
    if self.ui.timed then self.ui.timed.Visible = true self.ui.timed.Position = mode == "Duel" and UDim2.fromScale(0.5,0.03) or self.timedOriginalPosition end
    self.ui.words.Text = "0/" .. #puzzle.words
    self:RefreshTiles()
    local generation = self.generation
    -- Sparse crossword rows contain blocks, so reveal a dense list of playable cells.
    local reveal = {}
    for _, tiles in ipairs(self.tiles) do for _, tile in pairs(tiles) do table.insert(reveal, {tile}) end end
    self.cancelEntrance = Effects.RevealBoard(self.grid, reveal, function()
        if generation == self.generation then self.entering = false self:RefreshTiles() end
    end)
    self.callbacks.playSound("Appear")
end

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
    local oldFound, revealed, count = self.found, {}, 0
    self.members, self.found, self.hinted = members, {}, {}
    for _, member in ipairs(members) do
        if member.userId == Players.LocalPlayer.UserId then
            self:UpdateScore(member.score or 0)
            self.found, self.hinted = table.clone(member.foundWords or {}), table.clone(member.hintedWords or {})
            revealed = member.revealedAnswers or {}
        end
    end
    self.editing:Apply(self.found, revealed)
    local newWords = {}
    for _, word in ipairs(self.puzzle.words) do
        local row = self.rows[word]
        if self.found[word] then
            count += 1
            self.wordColors[word] = self.wordColors[word] or self:NextLineColor()
            if not oldFound[word] then table.insert(newWords,word) end
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
    self.ui.words.Text = string.format("%d/%d",count,#self.puzzle.words)
    if self.found[self.editing.selected] and not oldFound[self.editing.selected] then self.editing:Next(1) end
    self:RefreshTiles()
    for _, id in ipairs(newWords) do Effects.PopIn(self.rows[id]) end
    if #newWords > 0 then
        Effects.Pulse(self.ui.words, self.completed and 1.08 or 1.035)
        self.callbacks.playSound(self.completed and "Victory" or "NotificationHigh")
    end
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

function BoardController:Destroy()
    self.generation += 1
    if self.cancelEntrance then self.cancelEntrance() end
    for _, cancel in pairs(self.scoreEffects) do cancel() end
    for _, connection in ipairs(self.connections) do connection:Disconnect() end
    for _, row in pairs(self.rows) do row:Destroy() end
    if self.keyboard then self.keyboard:Destroy() end
    if self.clueLabel then self.clueLabel:Destroy() end
    self.grid:Destroy()
end
BoardController.Portrait = portrait
return BoardController
