local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local View = {}
View.__index = View
local Z = 900
local READ_TIME_SECONDS = 2
local CLOSE_TIME = 0.14
local OPEN_TIME = 0.22
local DIM_TRANSPARENCY = 0.32
local OVERSCAN = 0.75 -- 50% farther beyond each edge than the previous 0.5 margin.

-- Kingdom Wars' four-panel mask: shared integer edges prevent seams/overlap.
function View.Mask(width, height, x, y, w, h, padding)
	local left = math.clamp(math.floor(x - padding), 0, width)
	local top = math.clamp(math.floor(y - padding), 0, height)
	local right = math.clamp(math.ceil(x + w + padding), left, width)
	local bottom = math.clamp(math.ceil(y + h + padding), top, height)
	return {
		{ 0, 0, width, top }, { 0, top, left, bottom - top },
		{ right, top, width - right, bottom - top }, { 0, bottom, width, height - bottom },
	}, { left, top, right - left, bottom - top }
end

-- Fill only the outside of each quarter-circle inside the rectangular opening.
-- Disjoint pixel rows avoid doubled dimming; fractional edge coverage softens the arc.
function View.CornerMask(opening, radius)
	local x, y, width, height = table.unpack(opening)
	radius = math.max(0, math.floor(math.min(radius, width / 2, height / 2)))
	local pieces = {}
	local function add(left, top, w, coverage)
		if w > 0 and coverage > 0 then table.insert(pieces, { left, top, w, 1, coverage }) end
	end
	for row = 0, radius - 1 do
		local distance = radius - row - 0.5
		local inset = radius - math.sqrt(radius * radius - distance * distance)
		local solid = math.floor(inset)
		local edge = inset - solid
		for _, top in ipairs({ y + row, y + height - row - 1 }) do
			add(x, top, solid, 1)
			add(x + width - solid, top, solid, 1)
			add(x + solid, top, 1, edge)
			add(x + width - solid - 1, top, 1, edge)
		end
	end
	return pieces
end

local function rectangle(parent, name, transparency)
	local node = Instance.new("TextButton")
	node.Name, node.Text = name, ""
	node.AutoButtonColor, node.Selectable = false, false
	node.BackgroundColor3, node.BackgroundTransparency = Color3.new(0, 0, 0), transparency
	node.BorderSizePixel, node.ZIndex = 0, Z
	node.Parent = parent
	return node
end

function View.new(ui, advance, skip)
	local self = setmetatable({ ui = ui, connections = {}, zIndexes = {}, selections = {}, token = 0, advance = advance }, View)
	self.frame = ui.screenGui:FindFirstChild("Tutorial")
	assert(self.frame and self.frame:IsA("GuiObject"), "Missing Main.Tutorial")
	self.content = assert(self.frame:FindFirstChild("Content"), "Missing Tutorial.Content")
	self.title = assert(self.content:FindFirstChild("Title"), "Missing Tutorial.Content.Title")
	self.paragraph = assert(self.content:FindFirstChild("Paragraph"), "Missing Tutorial.Content.Paragraph")
	self.skip = assert(self.frame:FindFirstChild("Skip"), "Missing Tutorial.Skip")
	self.icon = self.frame:FindFirstChild("Icon")
	self.original = { anchor = self.frame.AnchorPoint, size = self.frame.Size,
		iconPosition = self.icon and self.icon.Position }
	self.scale = self.frame:FindFirstChild("PopScale")
	self.original.scale = self.scale and self.scale.Scale
	self.paragraph.TextWrapped = true
	self.frame.Visible = false
	table.insert(self.connections, self.skip.Activated:Connect(skip))
	return self
end

function View:Start()
	self.active = true
	self.root = Instance.new("Frame")
	self.root.Name, self.root.BackgroundTransparency = "TutorialSpotlight", 1
	self.root.Position, self.root.Size = UDim2.fromScale(-OVERSCAN, -OVERSCAN), UDim2.fromScale(1 + 2 * OVERSCAN, 1 + 2 * OVERSCAN)
	self.root.BorderSizePixel, self.root.ZIndex = 0, Z
	self.root.Parent = self.ui.screenGui
	self.panels, self.cornerPanels, self.cornerBounds, self.cornerCoverage = {}, {}, nil, {}
	self.maskOpacity = 0
	for _, name in ipairs({ "Top", "Left", "Right", "Bottom" }) do
		table.insert(self.panels, rectangle(self.root, name, 1))
	end
	self.cover = rectangle(self.root, "OpeningInputBlocker", 1)
	self.maskDriver = Instance.new("NumberValue")
	self.maskDriver.Name, self.maskDriver.Value, self.maskDriver.Parent = "MaskOpacity", 0, self.root
	self.maskChanged = self.maskDriver.Changed:Connect(function(value)
		self.maskOpacity = value
		for _, panel in ipairs(self.panels) do panel.BackgroundTransparency = 1 - (1 - DIM_TRANSPARENCY) * value end
		for index, panel in ipairs(self.cornerPanels) do
			panel.BackgroundTransparency = 1 - (1 - DIM_TRANSPARENCY) * value * (self.cornerCoverage[index] or 0)
		end
	end)
	for _, node in ipairs(self.ui.screenGui:GetDescendants()) do
		if node:IsA("GuiButton") then self.selections[node] = node.Selectable node.Selectable = false end
	end
	local objects = self.frame:GetDescendants()
	table.insert(objects, self.frame)
	for _, node in ipairs(objects) do
		if node:IsA("GuiObject") then
			self.zIndexes[node] = node.ZIndex
			node.ZIndex = Z + 1 + math.clamp(node.ZIndex, 0, 60)
		end
	end
	self.frame.Visible = true
	self.frame.AnchorPoint = self.original.anchor
	self.render = RunService.RenderStepped:Connect(function(dt) self:Layout() end)
end


function View:LayoutCorners(opening, padding)
	-- Twice the padding rounds the opening without touching the actual target.
	local radius = math.min(24, padding * 2)
	local previous = self.cornerBounds
	if previous and previous[1] == opening[1] and previous[2] == opening[2]
		and previous[3] == opening[3] and previous[4] == opening[4] and previous[5] == radius then return end
	self.cornerBounds = { opening[1], opening[2], opening[3], opening[4], radius }
	local pieces = View.CornerMask(opening, radius)
	for index, piece in ipairs(pieces) do
		local panel = self.cornerPanels[index]
		if not panel then
			panel = rectangle(self.root, "RoundedCorner_" .. index, DIM_TRANSPARENCY)
			self.cornerPanels[index] = panel
		end
		panel.Position = UDim2.fromOffset(piece[1], piece[2])
		panel.Size = UDim2.fromOffset(piece[3], piece[4])
		self.cornerCoverage[index] = piece[5]
		panel.BackgroundTransparency = 1 - (1 - DIM_TRANSPARENCY) * piece[5] * self.maskOpacity
		panel.Visible = true
	end
	for index = #pieces + 1, #self.cornerPanels do self.cornerPanels[index].Visible = false end
end

function View:Layout(placeWhileHidden)
	local root, target = self.root, self.target
	if not self.active or not root or not root.Parent then return end
	local origin, size = root.AbsolutePosition, root.AbsoluteSize
	local hasTarget = target ~= nil and target.Parent ~= nil
	local p = hasTarget and target.AbsolutePosition or (origin + size / 2)
	local s = hasTarget and target.AbsoluteSize or Vector2.new(0, 0)
	local padding = hasTarget and math.max(8, math.min(s.X, s.Y) * 0.04) or 0
	for _, panel in ipairs(self.panels) do panel.Visible = hasTarget end
	if hasTarget then
		local panels, opening = View.Mask(math.floor(size.X + 0.5), math.floor(size.Y + 0.5),
			p.X - origin.X, p.Y - origin.Y, s.X, s.Y, padding)
		for index, rect in ipairs(panels) do
			self.panels[index].Position = UDim2.fromOffset(rect[1], rect[2])
			self.panels[index].Size = UDim2.fromOffset(rect[3], rect[4])
		end
		self:LayoutCorners(opening, padding)
		self.cover.Position = UDim2.fromOffset(opening[1], opening[2])
		self.cover.Size = UDim2.fromOffset(opening[3], opening[4])
		self.cover.Visible = self.transitioning or not self.allowTarget
	else
		self.cornerBounds = nil
		for _, panel in ipairs(self.cornerPanels) do panel.Visible = false end
		-- No highlighted opening or dimming on congratulations; still block stray clicks.
		self.cover.Position, self.cover.Size = UDim2.fromScale(0, 0), UDim2.fromScale(1, 1)
		self.cover.Visible = true
	end
	-- Let the active transition own position while shrinking, growing or sliding.
	if self.transitioning and not placeWhileHidden then return end
	-- Recover the authored viewport independently of the extra dark coverage.
	local viewport = size / (1 + 2 * OVERSCAN)
	local screenOrigin = origin + viewport * OVERSCAN
	local safeTarget = { p.X - screenOrigin.X - padding, p.Y - screenOrigin.Y - padding,
		s.X + padding * 2, s.Y + padding * 2 }
	local frameSize = self.frame.AbsoluteSize
	-- Include the character when it extends outside the authored Tutorial.
	local insetLeft, insetTop, extraRight, extraBottom = 0, 0, 0, 0
	if self.icon and self.icon.Visible then
		local relative = self.icon.AbsolutePosition - self.frame.AbsolutePosition
		-- Reserve the resting icon bounds so its talking bob does not move the whole panel.
		local bobOffset = self.icon.Position.Y.Offset - self.original.iconPosition.Y.Offset
		relative -= Vector2.new(0, bobOffset * (self.scale and self.scale.Scale or 1))
		insetLeft, insetTop = math.max(0, -relative.X), math.max(0, -relative.Y)
		extraRight = math.max(0, relative.X + self.icon.AbsoluteSize.X - frameSize.X)
		extraBottom = math.max(0, relative.Y + self.icon.AbsoluteSize.Y - frameSize.Y)
	end
	if self.transitioning and self.fullBounds then
		local cached = self.fullBounds
		local factor = (self.scale and self.original.scale or 1) / cached.scale
		frameSize = cached.size * factor
		insetLeft, insetTop = cached.left * factor, cached.top * factor
		extraRight, extraBottom = cached.right * factor, cached.bottom * factor
	elseif frameSize.X > 0 and frameSize.Y > 0 then
		self.fullBounds = { size = frameSize, left = insetLeft, top = insetTop,
			right = extraRight, bottom = extraBottom, scale = self.scale and self.scale.Scale or 1 }
	end
	local fw, fh = frameSize.X + insetLeft + extraRight, frameSize.Y + insetTop + extraBottom
	local hintStep = hasTarget and target == self.ui.hint
	local x, y = 0.5, hintStep and 0.2 or 0.862
	if hasTarget and not hintStep and not self.centered then
		local left = viewport.X * 0.5 - frameSize.X * self.frame.AnchorPoint.X - insetLeft
		local top = viewport.Y * 0.862 - frameSize.Y * self.frame.AnchorPoint.Y - insetTop
		local tx, ty, tw, th = table.unpack(safeTarget)
		if left < tx + tw and left + fw > tx and top < ty + th and top + fh > ty then x = 0.4 end
	end
	self.frame.Position = UDim2.fromScale(self.centered and 0.5 or x, y)
end

function View:UpdateSelections()
	local focusTarget = self.focusTarget or self.target
	for _, node in ipairs(self.ui.screenGui:GetDescendants()) do
		if node:IsA("GuiButton") and not node:IsDescendantOf(self.root) then
			if self.selections[node] == nil then self.selections[node] = node.Selectable end
			node.Selectable = node == self.skip
				or (self.allowTarget and not self.typing and not self.transitioning and focusTarget
					and (node == focusTarget or node:IsDescendantOf(focusTarget))) or false
		end
	end
end

function View:FinishTyping()
	self.token += 1
	self.typing = false
	self.paragraph.MaxVisibleGraphemes = -1
	if self.bob then self.bob:Cancel() self.bob = nil end
	if self.icon then self.icon.Position = self.original.iconPosition end
	if self.active then self:UpdateSelections() end
end

function View:FadeMask(opacity, duration)
	if self.maskTween then self.maskTween:Cancel() end
	self.maskTween = TweenService:Create(self.maskDriver, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = opacity })
	self.maskTween:Play()
end

-- Keep the transparent input blocker while the normal screen transition runs.
function View:Suspend()
	self.frame.Visible = false
	self.target, self.allowTarget, self.hasStep = nil, false, false
	self:Layout(true)
end

function View:CancelTransition()
	if self.maskTween then self.maskTween:Cancel() self.maskTween = nil end
	if self.frameTween then self.frameTween:Cancel() self.frameTween = nil end
	if self.scaleTween then self.scaleTween:Cancel() self.scaleTween = nil end
end

function View:TweenFrame(size, scale, duration, direction, position)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, direction)
	local goal = { Size = size }
	if position then goal.Position = position end
	local tween = TweenService:Create(self.frame, info, goal)
	self.frameTween = tween
	if self.scale then
		self.scaleTween = TweenService:Create(self.scale, info, { Scale = scale })
		self.scaleTween:Play()
	end
	tween:Play()
	tween.Completed:Wait()
end

function View:Show(title, message, target, autoAdvance, allowTarget, focusTarget, centered)
	if not self.active then return end
	self:FinishTyping() -- invalidates the old typewriter and reading timer
	self:CancelTransition()
	if not self.transitioning then self:Layout() end -- remember the full-size footprint
	self.transitioning = true
	self:UpdateSelections()
	local token = self.token
	local hadStep = self.hasStep
	local slide = self.ui.hint ~= nil and (target == self.ui.hint or self.target == self.ui.hint)
	local previousPosition = self.frame.Position
	self.hasStep = true
	task.spawn(function()
		if not self.active or token ~= self.token then return end
		if hadStep then
			self:FadeMask(0, CLOSE_TIME)
			self:TweenFrame(UDim2.fromScale(0, 0), 0, CLOSE_TIME, Enum.EasingDirection.In)
			if not self.active or token ~= self.token then return end
		end
		self.frame.Size = UDim2.fromScale(0, 0)
		self.target, self.allowTarget, self.focusTarget, self.centered = target, allowTarget, focusTarget, centered == true
		if self.scale then self.scale.Scale = self.original.scale end
		self.title.Text = title
		self.paragraph.RichText = false
		self.paragraph.Text = message
		self.paragraph.MaxVisibleGraphemes = 0
		self:Layout(true)
		local destination = self.frame.Position
		if slide then self.frame.Position = previousPosition end
		self.frame.Visible = true
		self:FadeMask(target and 1 or 0, OPEN_TIME)
		local openScale = self.scale and self.scale.Scale or 1
		if self.scale then self.scale.Scale = 0 end
		self:TweenFrame(self.original.size, openScale, OPEN_TIME, Enum.EasingDirection.Out, slide and destination or nil)
		if not self.active or token ~= self.token then return end
		self.frameTween, self.scaleTween = nil, nil
		self.transitioning, self.typing = false, true
		if self.icon then
			self.bob = TweenService:Create(self.icon, TweenInfo.new(0.09, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = self.original.iconPosition + UDim2.fromOffset(0, -4) })
			self.bob:Play()
		end
		self:UpdateSelections()
		local count = utf8.len(message) or #message
		for index = 1, count do
			if not self.active or token ~= self.token then return end
			self.paragraph.MaxVisibleGraphemes = index
			task.wait(0.022)
		end
		if self.active and token == self.token then
			self:FinishTyping()
			if autoAdvance then
				local readToken = self.token
				task.delay(READ_TIME_SECONDS, function()
					if self.active and readToken == self.token then self.advance() end
				end)
			end
		end
	end)
end

function View:Collapse(onCollapsed)
	if not self.active then return end
	self:FinishTyping()
	self:CancelTransition()
	self.transitioning = true
	self:UpdateSelections()
	local token = self.token
	task.spawn(function()
		if not self.active or token ~= self.token then return end
		self:FadeMask(0, CLOSE_TIME)
		self:TweenFrame(UDim2.fromScale(0, 0), 0, CLOSE_TIME, Enum.EasingDirection.In)
		-- Skip or another step may cancel this final animation.
		if self.active and token == self.token then onCollapsed() end
	end)
end

function View:BlocksPointer(position)
	if not self.active then return false end
	local point = Vector2.new(position.X, position.Y)
	if not self.ui.screenGui.IgnoreGuiInset then point -= GuiService:GetGuiInset() end
	local p, s = self.frame.AbsolutePosition, self.frame.AbsoluteSize
	if point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y then return true end
	if self.transitioning or self.typing or not self.allowTarget or not self.target or not self.target.Parent then return true end
	p, s = self.target.AbsolutePosition, self.target.AbsoluteSize
	return point.X < p.X or point.Y < p.Y or point.X > p.X + s.X or point.Y > p.Y + s.Y
end

-- Skip releases input immediately; a short, passive copy finishes the visual fade.
function View:FadeOutCopy()
	if not self.root or self.maskOpacity <= 0 then return end
	local ghost = Instance.new("Frame")
	ghost.Name, ghost.BackgroundTransparency, ghost.Active = "TutorialSpotlightFade", 1, false
	ghost.Position, ghost.Size, ghost.ZIndex = self.root.Position, self.root.Size, Z
	ghost.Parent = self.root.Parent
	for _, group in ipairs({ self.panels, self.cornerPanels }) do
		for _, panel in ipairs(group) do
			if panel.Visible and panel.BackgroundTransparency < 1 then
				local copy = Instance.new("Frame")
				copy.BorderSizePixel, copy.Active, copy.Selectable, copy.ZIndex = 0, false, false, Z
				copy.Position, copy.Size = panel.Position, panel.Size
				copy.BackgroundColor3, copy.BackgroundTransparency = panel.BackgroundColor3, panel.BackgroundTransparency
				copy.Parent = ghost
				TweenService:Create(copy, TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = 1 }):Play()
			end
		end
	end
	task.delay(CLOSE_TIME, function() ghost:Destroy() end)
end

function View:Celebrate()
	if self.cancelConfetti then self.cancelConfetti() end
	local layer = Instance.new("Frame")
	layer.Name, layer.BackgroundTransparency = "TutorialConfetti", 1
	layer.Size, layer.ZIndex = UDim2.fromScale(1, 1), Z + 1
	layer.Active, layer.Parent = false, self.ui.screenGui
	local animations, live = {}, true
	local function cancel()
		if not live then return end
		live = false
		for _, animation in ipairs(animations) do animation:Cancel() end
		layer:Destroy()
	end
	self.cancelConfetti = cancel
	for index = 1, 32 do
		local piece = Instance.new("Frame")
		piece.BorderSizePixel, piece.Active = 0, false
		piece.Size = UDim2.fromOffset(6 + index % 5, 10 + index % 7)
		piece.Position = UDim2.fromScale((index % 8 + 0.5) / 8, -0.08)
		piece.Rotation, piece.ZIndex = index * 37, Z + 1
		piece.BackgroundColor3 = Color3.fromHSV((index * 0.618) % 1, 0.65, 1)
		piece.Parent = layer
		local animation = TweenService:Create(piece, TweenInfo.new(1.4 + (index % 4) * 0.15,
			Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, (index % 5) * 0.06), {
			Position = UDim2.fromScale((index % 8 + 0.5) / 8 + (index % 3 - 1) * 0.12, 1.05),
			Rotation = piece.Rotation + 180, BackgroundTransparency = 1 })
		table.insert(animations, animation)
		animation:Play()
	end
	task.delay(2.2, cancel)
end

function View:Close()
	if self.cancelConfetti then self.cancelConfetti() self.cancelConfetti = nil end
	self.active = false
	self:FinishTyping()
	self:CancelTransition()
	self.transitioning = false
	if self.render then self.render:Disconnect() self.render = nil end
	self:FadeOutCopy()
	if self.maskChanged then self.maskChanged:Disconnect() self.maskChanged = nil end
	if self.root then self.root:Destroy() self.root = nil end
	self.frame.Visible = false
	self.frame.Position, self.frame.AnchorPoint, self.frame.Size = UDim2.fromScale(0.5, 0.862), self.original.anchor, self.original.size
	if self.scale then self.scale.Scale = self.original.scale end
	for node, index in pairs(self.zIndexes) do if node.Parent then node.ZIndex = index end end
	for node, selectable in pairs(self.selections) do if node.Parent then node.Selectable = selectable end end
	self.zIndexes, self.selections = {}, {}
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.connections = {}
end

return View
