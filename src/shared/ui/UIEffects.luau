local TweenService = game:GetService("TweenService")

local UIEffects = {}

function UIEffects.DuelWinRateText(stats)
	stats = type(stats) == "table" and stats or {}
	local wins, losses = math.max(0, tonumber(stats.wins) or 0), math.max(0, tonumber(stats.losses) or 0)
	return string.format("%.0f%% Win Rate", wins + losses > 0 and 100 * wins / (wins + losses) or 0)
end

-- A shuffled deck prevents duplicate portrait colours within a lobby/round.
function UIEffects.NewPortraitPalette(random)
	local bag, previous = {}, nil
	return { Next = function()
		if #bag == 0 then
			for index = 0, 29 do table.insert(bag, index) end
			for i = #bag, 2, -1 do
				local j = math.min(i, 1 + math.floor(random:NextNumber() * i))
				bag[i], bag[j] = bag[j], bag[i]
			end
			if bag[#bag] == previous then bag[1], bag[#bag] = bag[#bag], bag[1] end
		end
		local index = table.remove(bag)
		previous = index
		return Color3.fromHSV(index / 30, 0.76 + (index % 3) * 0.04, 0.94 - (index % 3) * 0.04)
	end }
end

function UIEffects.SetPortraitImage(node, image)
	if type(image) ~= "string" or image:match("^%s*$") then return end
	-- Also guard stale packets/authored copies that still contain this blank headshot.
	if tonumber(string.lower(image):match("[?&]id=(%d+)")) == 36149989 then
		if type(node.Image) == "string" and tonumber(string.lower(node.Image):match("[?&]id=(%d+)")) == 36149989 then
			node.Image = ""
		end
		return
	end
	node.Image, node.ImageTransparency = image, 0
	-- Authored placeholder overlays must not cover a resolved headshot.
	local placeholder = node:FindFirstChild("Profile")
	if placeholder and placeholder:IsA("GuiObject") then placeholder.Visible = false end
end

local BUTTON_STATE = {}
local pulseStates = setmetatable({}, { __mode = "k" })
local highlightStates = setmetatable({}, { __mode = "k" })

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_UP_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_DOWN_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local function playTween(instance, properties, tweenInfo)
	local animation = TweenService:Create(instance, tweenInfo, properties)
	animation:Play()
	return animation
end

-- Native reversing tweens keep hinted tiles and links in phase without Lua loops.
function UIEffects.PulseHint(line, color)
	local originalColor = line.BackgroundColor3
	if color then line.BackgroundColor3 = Color3.new(1, 1, 1)
	else line.BackgroundTransparency = 0.30 end
	local animation = TweenService:Create(line, TweenInfo.new(0.85, Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut, -1, true), color and {BackgroundColor3 = color} or {BackgroundTransparency = 0.78})
	animation:Play()
	local stopped, destroying = false, nil
	local function stop()
		if stopped then return end
		stopped = true
		animation:Cancel()
		if color and line.Parent then line.BackgroundColor3 = originalColor end
		if destroying then destroying:Disconnect() end
	end
	destroying = line.Destroying:Connect(stop)
	return stop
end

function UIEffects.PopIn(node)
	local scale = node:FindFirstChildOfClass("UIScale")
	local created = not scale
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name, scale.Scale, scale.Parent = "AppearanceScale", 1, node
	end
	local base = scale.Scale
	scale.Scale = base * 0.65
	local animation = playTween(scale, { Scale = base }, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	task.delay(0.3, function()
		animation:Cancel()
		if created then scale:Destroy() elseif scale.Parent then scale.Scale = base end
	end)
end

-- SizeItUp's occasional four-swing Hint cue, stepped by the existing HUD loop.
-- Rotation only: hover, press and screen transitions retain ownership of UIScale.
function UIEffects.CreateHintWobble(target)
	local random, base = Random.new(), target.Rotation
	local enabled, elapsed, delay, direction = false, nil, 0, 1
	local controller = {}
	function controller:Step(dt, available)
		local state = BUTTON_STATE[target]
		available = available and target.Parent ~= nil and target.Visible and not (state and state.transitioning)
		if enabled ~= available then
			enabled, elapsed = available, nil
			delay = random:NextNumber(3.5, 5.5)
			target.Rotation = base
		end
		if not enabled then return end
		dt = math.clamp(dt, 0, 1 / 15)
		if not elapsed then
			delay -= dt
			if delay > 0 then return end
			elapsed, direction = 0, random:NextNumber() < 0.5 and -1 or 1
		end
		elapsed += dt
		local progress = math.clamp(elapsed / 0.72, 0, 1)
		target.Rotation = base + direction * 6.5 * math.sin(math.pi * 4 * progress) * math.sin(math.pi * progress)
		if progress >= 1 then
			target.Rotation, elapsed, delay = base, nil, random:NextNumber(8, 13)
		end
	end
	function controller:Destroy()
		enabled, elapsed = false, nil
		if target.Parent then target.Rotation = base end
	end
	target.Destroying:Connect(function() controller:Destroy() end)
	return controller
end

local homePreviews = {}

-- Decorative adjacent paths on authored menu tiles; no gameplay or input state.
function UIEffects.CreateHomeTilePreview(frame, width, color, initialDelay)
	if not frame then return nil end
	if homePreviews[frame] then homePreviews[frame]:Destroy() end
	local tiles, tweens, random = {}, {}, Random.new()
	for _, tile in ipairs(frame:GetChildren()) do
		local index = tonumber(tile.Name:lower():match("^tile(%d+)$") or tile.Name:match("^(%d+)$"))
		if index and index >= 1 and index <= width * width and tile:IsA("GuiObject") then tiles[index] = tile end
	end
	for index = 1, width * width do if not tiles[index] then return nil end end
	local controller = {path = {}}
	local stopped, enabled, elapsed, cursor, fading, previous = false, false, 0, 0, false, nil
	local delay = initialDelay or 0
	local destroying
	local function paint(tile, target, duration)
		if tweens[tile] then tweens[tile]:Cancel() tweens[tile] = nil end
		local properties = {BackgroundColor3 = target}
		if tile:IsA("ImageLabel") or tile:IsA("ImageButton") then properties.ImageColor3 = target end
		if duration then
			tweens[tile] = playTween(tile, properties, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
		else
			for key, value in pairs(properties) do tile[key] = value end
		end
	end
	local function clear()
		for _, tile in pairs(tiles) do if tile.Parent then paint(tile, Color3.new(1, 1, 1)) end end
		for tile, tween in pairs(tweens) do tween:Cancel() tweens[tile] = nil end
		controller.path, elapsed, cursor, fading = {}, 0, 0, false
	end
	local function nextPath()
		local length = width == 3 and 3 or (random:NextNumber() < 0.5 and 5 or 6)
		for _ = 1, 12 do
			local path, used = {}, {}
			local current = 1 + math.floor(random:NextNumber() * width * width)
			for _ = 1, length do
				table.insert(path, current) used[current] = true
				local row, column = math.floor((current - 1) / width), (current - 1) % width
				local choices = {}
				for dr = -1, 1 do for dc = -1, 1 do
					local r, c = row + dr, column + dc
					local index = r * width + c + 1
					if r >= 0 and r < width and c >= 0 and c < width and not used[index] then table.insert(choices, index) end
				end end
				if #path == length or #choices == 0 then break end
				current = choices[1 + math.floor(random:NextNumber() * #choices)]
			end
			local signature = table.concat(path, ":")
			if #path == length and signature ~= previous then previous = signature return path end
		end
		return {}
	end
	function controller:Step(dt, available)
		if stopped then return end
		local ancestor = frame
		while available and ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then available = false end
			ancestor = ancestor.Parent
		end
		available = available and frame.Parent ~= nil
		if not available then
			if enabled then clear() end
			enabled, delay = false, initialDelay or 0
			return
		end
		enabled = true
		dt = math.clamp(dt, 0, 0.1)
		if #self.path == 0 then
			delay -= dt
			if delay > 0 then return end
			self.path, elapsed, cursor, fading = nextPath(), 0, 0, false
			if #self.path == 0 then delay = 0.5 return end
		end
		elapsed += dt
		local nextIndex = cursor + 1
		if nextIndex <= #self.path and elapsed >= (nextIndex - 1) * 0.22 then
			local tile = tiles[self.path[nextIndex]]
			if not tile.Parent then self:Destroy() return end
			paint(tile, color, 0.4)
			cursor = nextIndex
		end
		local holdEnd = (#self.path - 1) * 0.22 + 1.2
		if not fading and elapsed >= holdEnd then
			fading = true
			for _, index in ipairs(self.path) do paint(tiles[index], Color3.new(1, 1, 1), 1.0) end
		elseif fading and elapsed >= holdEnd + 1.05 then
			clear()
			delay = 0
		end
	end
	function controller:Destroy()
		if stopped then return end
		stopped = true
		clear()
		if destroying then destroying:Disconnect() end
		if homePreviews[frame] == self then homePreviews[frame] = nil end
	end
	clear()
	destroying = frame.Destroying:Connect(function() controller:Destroy() end)
	homePreviews[frame] = controller
	return controller
end

-- UIGridLayout owns resting layouts. Park it only while tiles glide between
-- layouts, avoiding the instant row reflow caused by tweening CellSize alone.
function UIEffects.CreateJumboPreview(frame)
	if not frame then return nil end
	if homePreviews[frame] then homePreviews[frame]:Destroy() end
	local layout = frame:FindFirstChildOfClass("UIGridLayout")
	if not layout then return nil end
	local tiles, originals, clones = {}, {}, {}
	for _, tile in ipairs(frame:GetChildren()) do
		local index = tonumber(tile.Name:lower():match("^tile(%d+)$") or tile.Name:match("^(%d+)$"))
		if index and index >= 1 and index <= 36 and tile:IsA("GuiObject") then tiles[index] = tile end
	end
	for index = 1, 9 do if not tiles[index] then return nil end end
	for index, tile in pairs(tiles) do
		originals[tile] = {visible=tile.Visible, order=tile.LayoutOrder, position=tile.Position, size=tile.Size, anchor=tile.AnchorPoint}
		tile.LayoutOrder = index
	end
	for index = 10, 36 do
		if not tiles[index] then
			local tile = tiles[(index - 1) % 9 + 1]:Clone()
			tile.Name, tile.LayoutOrder, tile.Visible = "Tile" .. index, index, false
			tile.Parent, tiles[index] = frame, tile
			table.insert(clones, tile)
		end
	end
	local saved = {CellSize=layout.CellSize, CellPadding=layout.CellPadding,
		FillDirection=layout.FillDirection, FillDirectionMaxCells=layout.FillDirectionMaxCells, SortOrder=layout.SortOrder}
	local parking = Instance.new("Folder")
	parking.Name, parking.Parent = "JumboLayoutParking", frame
	local controller, random, tweens, scales = {}, Random.new(), {}, {}
	local stopped, enabled, width, remaining, resizing = false, false, 3, 12, false
	local destroying
	local function cancelTweens()
		for _, tween in ipairs(tweens) do tween:Cancel() end
		table.clear(tweens)
	end
	local function clearScales()
		for tile, entry in pairs(scales) do
			if entry.created then entry.scale:Destroy() elseif entry.scale.Parent then entry.scale.Scale = entry.base end
			scales[tile] = nil
		end
	end
	local function tileScale(tile)
		if not scales[tile] then
			local scale = tile:FindFirstChildOfClass("UIScale")
			local created = not scale
			if not scale then scale = Instance.new("UIScale") scale.Name, scale.Parent = "JumboPreviewScale", tile end
			scales[tile] = {scale=scale, base=scale.Scale, created=created}
		end
		return scales[tile]
	end
	local function dimensions(count)
		local size, padding = saved.CellSize, saved.CellPadding
		local ratio = 3 / count
		local px, py = padding.X.Scale * ratio, padding.Y.Scale * ratio
		local ox, oy = padding.X.Offset * ratio, padding.Y.Offset * ratio
		return UDim2.new((3*size.X.Scale+2*padding.X.Scale-(count-1)*px)/count,
			(3*size.X.Offset+2*padding.X.Offset-(count-1)*ox)/count,
			(3*size.Y.Scale+2*padding.Y.Scale-(count-1)*py)/count,
			(3*size.Y.Offset+2*padding.Y.Offset-(count-1)*oy)/count), UDim2.new(px,ox,py,oy)
	end
	local function pose(index, count)
		local size, padding = dimensions(count)
		local column, row = (index-1)%count, math.floor((index-1)/count)
		local xAlign = layout.HorizontalAlignment == Enum.HorizontalAlignment.Center and 0.5 or layout.HorizontalAlignment == Enum.HorizontalAlignment.Right and 1 or 0
		local yAlign = layout.VerticalAlignment == Enum.VerticalAlignment.Center and 0.5 or layout.VerticalAlignment == Enum.VerticalAlignment.Bottom and 1 or 0
		return UDim2.new((1-count*size.X.Scale-(count-1)*padding.X.Scale)*xAlign+(column+0.5)*size.X.Scale+column*padding.X.Scale,
			(-count*size.X.Offset-(count-1)*padding.X.Offset)*xAlign+(column+0.5)*size.X.Offset+column*padding.X.Offset,
			(1-count*size.Y.Scale-(count-1)*padding.Y.Scale)*yAlign+(row+0.5)*size.Y.Scale+row*padding.Y.Scale,
			(-count*size.Y.Offset-(count-1)*padding.Y.Offset)*yAlign+(row+0.5)*size.Y.Offset+row*padding.Y.Offset), size
	end
	local function settle(count)
		cancelTweens()
		layout.Parent = parking
		for index, tile in ipairs(tiles) do
			tile.Visible = index <= count*count
			tile.AnchorPoint = Vector2.new(0.5,0.5)
			if tile.Visible then tile.Position, tile.Size = pose(index,count) end
		end
		clearScales()
		layout.CellSize, layout.CellPadding = dimensions(count)
		layout.FillDirection, layout.FillDirectionMaxCells, layout.SortOrder = Enum.FillDirection.Horizontal, count, Enum.SortOrder.LayoutOrder
		layout.Parent = frame
	end
	local function reset()
		width, remaining, resizing = 3, 12, false
		settle(3)
	end
	local function morph(count)
		cancelTweens()
		layout.Parent = parking
		for index, tile in ipairs(tiles) do
			local entering, leaving = index > width*width, index > count*count
			local targetPosition, targetSize = pose(math.min(index,count*count),count)
			if leaving then targetPosition, targetSize = tile.Position, tile.Size end
			if entering then
				-- New cells grow gently in their destination; existing cells glide.
				tile.AnchorPoint = Vector2.new(0.5,0.5)
				tile.Position, tile.Size = targetPosition, targetSize
			end
			local entry = tileScale(tile)
			entry.scale.Scale = entering and 0 or entry.base
			tile.Visible = true
			local info = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			table.insert(tweens, playTween(tile, {Position=targetPosition,Size=targetSize},info))
			table.insert(tweens, playTween(entry.scale, {Scale=leaving and 0 or entry.base},info))
		end
		width, resizing, remaining = count, true, 1.65
	end
	function controller:Step(dt, available)
		if stopped then return end
		local ancestor = frame
		while available and ancestor do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then available = false end
			ancestor = ancestor.Parent
		end
		available = available and frame.Parent ~= nil and (layout.Parent == frame or layout.Parent == parking)
		if not available then if enabled then reset() end enabled = false return end
		enabled = true
		remaining -= math.clamp(dt,0,0.1)
		if remaining > 0 then return end
		if resizing then
			settle(width)
			resizing, remaining = false, width == 3 and random:NextNumber(12,18) or 6
		else morph(width == 3 and 6 or 3) end
	end
	function controller:Destroy(frameDestroyed)
		if stopped then return end
		stopped = true
		cancelTweens()
		clearScales()
		if not frameDestroyed then
			for property, value in pairs(saved) do layout[property] = value end
			for tile, original in pairs(originals) do
				if tile.Parent then
					tile.Visible, tile.LayoutOrder = original.visible, original.order
					tile.AnchorPoint, tile.Position, tile.Size = original.anchor, original.position, original.size
				end
			end
			layout.Parent = frame
			for _, tile in ipairs(clones) do tile:Destroy() end
			parking:Destroy()
		end
		if destroying then destroying:Disconnect() end
		if homePreviews[frame] == self then homePreviews[frame] = nil end
	end
	reset()
	destroying = frame.Destroying:Connect(function() controller:Destroy(true) end)
	homePreviews[frame] = controller
	return controller
end

local patternLoops = {}

function UIEffects.AnimatePattern(pattern, quiet)
	if not pattern or not (pattern:IsA("ImageLabel") or pattern:IsA("ImageButton")) or patternLoops[pattern] then return end
	pattern.ImageTransparency = 0.98
	local animation = playTween(pattern, { ImageTransparency = quiet and 0.96 or 0.92 },
		TweenInfo.new(quiet and 6 or 4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true))
	patternLoops[pattern] = animation
	local connection
	connection = pattern.Destroying:Connect(function()
		animation:Cancel()
		patternLoops[pattern] = nil
		connection:Disconnect()
	end)
end

local function getOrCreateScaleController(guiObject)
	local scaleController = guiObject:FindFirstChildOfClass("UIScale")
	if scaleController and scaleController:IsA("UIScale") then
		return scaleController
	end

	scaleController = Instance.new("UIScale")
	scaleController.Name = "ScaleController"
	scaleController.Scale = 1
	scaleController.Parent = guiObject
	return scaleController
end

local function brighten(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function getState(button)
	local state = BUTTON_STATE[button]
	if state then
		return state
	end

	state = {
		baseColor = button.BackgroundColor3,
		hoverBrightness = 0.08,
		hoverScale = 1.04,
		pressScale = 0.96,
		destroyToken = 0,
	}

	BUTTON_STATE[button] = state
	return state
end

function UIEffects.SetBaseColor(button, color)
	if not button or not button:IsA("GuiButton") then
		return
	end

	local state = getState(button)
	state.baseColor = color
	if button:GetAttribute("ButtonEnabled") ~= false then
		button.BackgroundColor3 = color
	end
end

function UIEffects.Init(button, options)
	if not button or not button:IsA("GuiButton") then
		return
	end

	local state = getState(button)
	if state.initialized then
		if options and options.baseColor then
			UIEffects.SetBaseColor(button, options.baseColor)
		end
		return
	end

	state.initialized = true
	state.scaleController = getOrCreateScaleController(button)
	state.baseScale = state.scaleController.Scale
	state.hoverBrightness = options and options.hoverBrightness or state.hoverBrightness
	state.hoverScale = options and options.hoverScale or state.hoverScale
	state.pressScale = options and options.pressScale or state.pressScale
	state.baseColor = options and options.baseColor or button.BackgroundColor3

	local function canAnimate()
		return button.Parent ~= nil and not state.transitioning and button:GetAttribute("ButtonEnabled") ~= false
	end

	button.MouseEnter:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.baseScale * state.hoverScale }, HOVER_TWEEN)
		playTween(button, { BackgroundColor3 = brighten(state.baseColor, state.hoverBrightness) }, HOVER_TWEEN)
	end)

	button.MouseLeave:Connect(function()
		if state.transitioning then return end
		playTween(state.scaleController, { Scale = state.baseScale }, HOVER_TWEEN)
		playTween(button, {
			BackgroundColor3 = canAnimate() and state.baseColor or button.BackgroundColor3,
		}, HOVER_TWEEN)
	end)

	button.MouseButton1Down:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.baseScale * state.pressScale }, PRESS_TWEEN)
	end)

	button.MouseButton1Up:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.baseScale * state.hoverScale }, PRESS_TWEEN)
	end)
	button.Activated:Connect(function()
		if not canAnimate() then return end
		UIEffects.Pulse(button, state.baseScale * 1.04, state.baseScale)
	end)

	button.Destroying:Connect(function()
		BUTTON_STATE[button] = nil
	end)
end

-- One pulse per object: rapid input cannot leave delayed scale resets behind.
function UIEffects.CancelPulse(node)
	local state = pulseStates[node]
	if not state then return end
	pulseStates[node] = nil
	if state.animation then state.animation:Cancel() end
	if state.created then state.scale:Destroy()
	elseif state.scale.Parent then state.scale.Scale = state.base end
end

function UIEffects.Pulse(guiObject, peakScale, settleScale)
	if not guiObject or not guiObject.Parent then return end
	if BUTTON_STATE[guiObject] and BUTTON_STATE[guiObject].transitioning then return end
	UIEffects.CancelPulse(guiObject)
	local existing = guiObject:FindFirstChildOfClass("UIScale")
	local scale = existing or getOrCreateScaleController(guiObject)
	local base = settleScale or scale.Scale
	local state = { scale = scale, base = base, created = not existing }
	pulseStates[guiObject] = state
	-- Without an explicit settle value, peak is a multiplier of authored scale.
	local peak = settleScale and (peakScale or base * 1.06) or base * (peakScale or 1.06)
	state.animation = playTween(scale, { Scale = peak }, PULSE_UP_TWEEN)
	task.delay(0.16, function()
		if pulseStates[guiObject] ~= state then return end
		if not guiObject.Parent then UIEffects.CancelPulse(guiObject) return end
		state.animation = playTween(scale, { Scale = base }, PULSE_DOWN_TWEEN)
		task.delay(0.14, function()
			if pulseStates[guiObject] == state then UIEffects.CancelPulse(guiObject) end
		end)
	end)
end

-- Returns cleanup so rebuilding a Duel can restore authored styling immediately.
function UIEffects.ScoreChanged(label, direction)
	if not label or not label.Parent then return function() end end
	local color, rotation = label.TextColor3, label.Rotation
	local live, animation = true, nil
	local function cancel()
		if not live then return end
		live = false
		if animation then animation:Cancel() end
		UIEffects.CancelPulse(label)
		if label.Parent then label.TextColor3, label.Rotation = color, rotation end
	end
	UIEffects.Pulse(label, 1.18)
	animation = playTween(label, {TextColor3=Color3.fromRGB(43,225,58), Rotation=rotation + (direction or 1)*5}, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	task.delay(0.13, function()
		if not live or not label.Parent then cancel() return end
		animation = playTween(label, {TextColor3=color, Rotation=rotation}, TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		task.delay(0.29, cancel)
	end)
	return cancel
end

function UIEffects.CancelHighlight(node)
	local state = highlightStates[node]
	if state then state.cleanup() end
end

-- A quiet border accent: no overlay, layout changes or input interception.
function UIEffects.SoftHighlight(node, color)
	if not node or not node.Parent then return end
	local previous = highlightStates[node]
	if previous then previous.cleanup() end
	local stroke = node:FindFirstChildOfClass("UIStroke")
	local created = not stroke
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "SoftHighlight"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color, stroke.Transparency, stroke.Thickness = color, 1, 1
		stroke.Parent = node
	end
	local baseColor, baseTransparency, baseThickness = stroke.Color, stroke.Transparency, stroke.Thickness
	local state = {}
	local function cleanup()
		if highlightStates[node] ~= state then return end
		highlightStates[node] = nil
		if state.animation then state.animation:Cancel() end
		if created then stroke:Destroy()
		elseif stroke.Parent then
			stroke.Color, stroke.Transparency, stroke.Thickness = baseColor, baseTransparency, baseThickness
		end
	end
	state.cleanup = cleanup
	highlightStates[node] = state
	state.animation = playTween(stroke, { Color = color, Transparency = 0.45, Thickness = math.max(baseThickness, 1.5) },
		TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	task.delay(0.14, function()
		if highlightStates[node] ~= state then return end
		if not node.Parent or not stroke.Parent then cleanup() return end
		state.animation = playTween(stroke, { Color = baseColor, Transparency = baseTransparency, Thickness = baseThickness },
			TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		task.delay(0.65, cleanup)
	end)
end

function UIEffects.ApplyToAll(container, options)
	if not container then
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			UIEffects.Init(descendant, options)
		end
	end
end

-- Tween the endpoint instead of independently rotating/resizing the capsule,
-- so its first end stays centered on the starting letter during turns.
function UIEffects.CreateLineMotion(line)
	local driver = Instance.new("Vector3Value")
	driver.Name = "DragEndpoint"
	driver.Parent = line
	local origin, target, animation
	local function draw()
		if not origin or not line.Parent then return end
		local value = driver.Value
		local endpoint = Vector2.new(value.X, value.Y)
		local delta = endpoint - origin
		line.Position = UDim2.fromOffset((origin.X + endpoint.X) / 2, (origin.Y + endpoint.Y) / 2)
		line.Size = UDim2.fromOffset(delta.Magnitude + value.Z, value.Z)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end
	driver:GetPropertyChangedSignal("Value"):Connect(draw)
	local motion = {}
	function motion:Cancel()
		if animation then animation:Cancel() animation = nil end
		origin, target = nil, nil
	end
	function motion:Move(first, last, thickness, animate)
		local nextTarget = Vector3.new(last.X, last.Y, thickness)
		if origin == first and target == nextTarget then return end
		local continuing = origin == first and target ~= nil
		if animation then animation:Cancel() animation = nil end
		origin, target = first, nextTarget
		if animate and continuing then
			animation = playTween(driver, { Value = nextTarget },
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		else
			driver.Value = nextTarget
			draw()
		end
	end
	return motion
end

-- Each tile owns its short transitions; unchanged snapshots never restart them.
function UIEffects.CreateTileFeedback(face, letter)
	local veil = face:FindFirstChild("WhiteFace")
	local rim = face:FindFirstChild("SelectionShine"):FindFirstChildOfClass("UIStroke")
	local animations, highlighted, alive = {}, false, true
	local currentColor
	local controller = {}
	function controller:Set(value, animate, color)
		value = value == true
		if not alive then return end
		if value and color and color ~= currentColor then
			currentColor = color
			face:FindFirstChild("SelectionGradient").Color = ColorSequence.new(
				color:Lerp(Color3.new(1, 1, 1), 0.4), color:Lerp(Color3.new(0, 0, 0), 0.08))
			rim.Color = color:Lerp(Color3.new(1, 1, 1), 0.8)
		end
		if highlighted == value then return end
		highlighted = value
		for _, tween in ipairs(animations) do tween:Cancel() end
		animations = {}
		local alpha, rimAlpha = value and 1 or 0, value and 0.15 or 1
		if animate then
			local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			table.insert(animations, playTween(veil, {BackgroundTransparency = alpha}, info))
			table.insert(animations, playTween(rim, {Transparency = rimAlpha}, info))
			if value then UIEffects.Pulse(face, 1.045) UIEffects.Pulse(letter, 1.06) end
		else
			veil.BackgroundTransparency, rim.Transparency = alpha, rimAlpha
		end
	end
	function controller:Destroy()
		if not alive then return end
		alive = false
		for _, tween in ipairs(animations) do tween:Cancel() end
		UIEffects.CancelPulse(face)
		UIEffects.CancelPulse(letter)
	end
	face.Destroying:Connect(function() controller:Destroy() end)
	return controller
end

function UIEffects.RevealLink(segment)
	local scale = Instance.new("UIScale")
	scale.Name, scale.Scale, scale.Parent = "LinkReveal", 0.35, segment
	local animation = playTween(scale, {Scale = 1}, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	local connection, finished
	local function cleanup()
		if finished then return end
		finished = true
		animation:Cancel()
		if connection then connection:Disconnect() end
		scale:Destroy()
	end
	connection = segment.Destroying:Connect(cleanup)
	task.delay(0.1, cleanup)
end

-- Reveal only runtime board content, preserving the authored panel geometry.
function UIEffects.RevealBoard(grid, tiles, onComplete, faces, shadows)
	local animations, scales, letters = {}, {}, {}
	local finished = false
	local function scaleFor(node, initial)
		local scale = Instance.new("UIScale")
		scale.Name = "BoardRevealScale"
		scale.Scale = initial
		scale.Parent = node
		table.insert(scales, scale)
		return scale
	end
	local function animate(node, properties, info)
		table.insert(animations, playTween(node, properties, info))
	end
	local function cleanup()
		for _, animation in ipairs(animations) do animation:Cancel() end
		for _, scale in ipairs(scales) do scale:Destroy() end
		for _, tile in ipairs(letters) do
			if tile.Parent then tile.TextTransparency = 0 end
		end
	end
	animate(scaleFor(grid, 0.9), { Scale = 1 }, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	local height, width = #tiles, #tiles[1]
	for row, cells in ipairs(tiles) do
		for column, tile in ipairs(cells) do
			table.insert(letters, tile)
			tile.TextTransparency = 1
			local delay = (row + column - 2) / math.max(1, height + width - 2) * 0.24
			animate(tile, { TextTransparency = 0 }, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay))
			animate(scaleFor(tile, 0.6), { Scale = 1 }, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay))
			for _, layer in ipairs({ faces or {}, shadows or {} }) do
				local node = layer[row] and layer[row][column]
				if node then
					animate(scaleFor(node, 0), { Scale = 1 }, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay))
				end
			end
		end
	end
	task.delay(0.58, function()
		if finished then return end
		finished = true
		cleanup()
		if grid.Parent and onComplete then onComplete() end
	end)
	return function()
		if finished then return end
		finished = true
		cleanup()
	end
end

-- The same poses drive entry and exit, including the reversed stagger.
local GAME_POSES = {
	BOARDINFO = { -0.04, 0, 0.92, 0 }, BoardInfo = { -0.04, 0, 0.92, 0 },
	BoardPanel = { -0.04, 0, 0.92, 0 }, WordPanel = { 0.04, 0, 0.9, 0.07 },
	Title = { 0, -0.035, 0.98, 0.04 }, Subtitle = { 0, -0.035, 0.98, 0.08 },
	LevelBar = { 0, 0.06, 0.9, 0.12 }, Hint = { 0, 0, 0, 0.18 }, Exit = { 0, 0, 0, 0.23 },
}
local HOME_POSES = {
	GameIcon = { 0, -0.08, 0.35, 0 }, SelectModeLabel = { 0, -0.04, 0.7, 0.05 },
	Gamemodes = { 0, 0.07, 0.65, 0.1 }, ButtonBar = { 0, 0.09, 0.45, 0.18 },
	LevelBar = { -0.04, 0, 0.6, 0.23 },
}
local QUEUE_POSES = {
	Container = { 0, 0.06, 0.75, 0.08 }, Subtitle = { 0, -0.05, 0.6, 0 },
	Exit = { 0, 0.04, 0.3, 0.2 },
}
local function animateGame(gameFrame, reverse, onComplete, poses)
	local animations, originals = {}, {}
	local finished = false
	local menu = poses ~= nil
	poses = poses or GAME_POSES
	for _, node in ipairs(gameFrame:GetChildren()) do
		if node:IsA("GuiObject") and node.Visible and node.Name ~= "Background" and node.Name ~= "Pattern" then
			UIEffects.CancelPulse(node)
			local pose = poses[node.Name] or { 0, 0.025, 0.94, 0.12 }
			local scale = node:FindFirstChildOfClass("UIScale")
			local created = not scale
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name, scale.Scale, scale.Parent = menu and "MenuEntranceScale" or "GameEntranceScale", 1, node
			end
			local buttonState = BUTTON_STATE[node]
			local position, sizeScale = node.Position, buttonState and buttonState.baseScale or scale.Scale
			if buttonState then buttonState.transitioning = true end
			local displaced = position + UDim2.fromScale(pose[1], pose[2])
			table.insert(originals, { node = node, position = position, scale = scale, value = sizeScale, created = created })
			if not reverse then
				node.Position, scale.Scale = displaced, sizeScale * pose[3]
			end
			local direction = reverse and Enum.EasingDirection.In or Enum.EasingDirection.Out
			local delay = reverse and (0.23 - pose[4]) or pose[4]
			table.insert(animations, playTween(node, { Position = reverse and displaced or position },
				TweenInfo.new(menu and 0.45 or 0.6, Enum.EasingStyle.Quint, direction, 0, false, delay)))
			table.insert(animations, playTween(scale, { Scale = reverse and sizeScale * pose[3] or sizeScale },
				TweenInfo.new(menu and 0.45 or 0.6, Enum.EasingStyle.Back, direction, 0, false, delay)))
		end
	end
	local function cleanup()
		if finished then return end
		finished = true
		for _, animation in ipairs(animations) do animation:Cancel() end
		for _, original in ipairs(originals) do
			if BUTTON_STATE[original.node] then BUTTON_STATE[original.node].transitioning = false end
			if original.node.Parent then original.node.Position = original.position end
			if original.created then original.scale:Destroy()
			elseif original.scale.Parent then original.scale.Scale = original.value end
		end
	end
	-- Outgoing elements stay collapsed until the view switches under white.
	if not reverse then
		task.delay(menu and 0.75 or 0.9, function()
			if finished then return end
			cleanup()
			if gameFrame.Parent and onComplete then onComplete() end
		end)
	end
	return cleanup
end

function UIEffects.RevealGame(gameFrame, onComplete)
	return animateGame(gameFrame, false, onComplete)
end

function UIEffects.RevealHome(homeFrame, onComplete)
	return animateGame(homeFrame, false, onComplete, HOME_POSES)
end

function UIEffects.RevealQueue(queueFrame, onComplete)
	return animateGame(queueFrame, false, onComplete, QUEUE_POSES)
end

local function whiteOverlay(screenGui)
	local overlay = Instance.new("Frame")
	overlay.Name = "GameTransition"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromScale(2, 2)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 10000
	overlay.Active, overlay.Selectable = true, false
	overlay.Parent = screenGui
	return overlay
end

-- Change views only at full white; cancellation cannot reopen an old round.
local function transitionToPanel(screenGui, onCovered, onComplete, reveal)
	local overlay = whiteOverlay(screenGui)
	local finished, cancelReveal = false, nil
	local home, queue = screenGui:FindFirstChild("Home"), screenGui:FindFirstChild("Queue")
	local outgoing = home and home.Visible and home or (queue and queue.Visible and queue or nil)
	local restoreOutgoing = outgoing and animateGame(outgoing, true, nil, outgoing == home and HOME_POSES or QUEUE_POSES) or nil
	local animation = playTween(overlay, { BackgroundTransparency = 0 }, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
	local function cleanup()
		animation:Cancel()
		if restoreOutgoing then restoreOutgoing() restoreOutgoing = nil end
		if cancelReveal then cancelReveal() end
		overlay:Destroy()
	end
	task.delay(0.7, function()
		if finished or not overlay.Parent then return end
		overlay.BackgroundTransparency = 0
		local ok, gameFrame = pcall(onCovered)
		if finished then return end
		if not ok or not gameFrame then
			finished = true
			cleanup()
			if onComplete then onComplete(false, gameFrame) end
			return
		end
		if restoreOutgoing then restoreOutgoing() restoreOutgoing = nil end
		cancelReveal = reveal(gameFrame, function()
			if finished then return end
			finished = true
			cleanup()
			if onComplete then onComplete(true) end
		end)
		animation = playTween(overlay, { BackgroundTransparency = 1 }, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
	end)
	return function()
		if finished then return end
		finished = true
		cleanup()
	end
end

function UIEffects.TransitionToGame(screenGui, onCovered, onComplete)
	return transitionToPanel(screenGui, onCovered, onComplete, UIEffects.RevealGame)
end

function UIEffects.TransitionToQueue(screenGui, onCovered, onComplete)
	return transitionToPanel(screenGui, onCovered, onComplete, function(frame, done)
		-- Keep input locked until the 0.8-second white fade also finishes.
		return UIEffects.RevealQueue(frame, function() task.delay(0.05, done) end)
	end)
end

function UIEffects.TransitionToHome(screenGui, gameFrame, onCovered, onComplete)
	local overlay = whiteOverlay(screenGui)
	local finished = false
	local queueFrame = screenGui:FindFirstChild("Queue")
	local cancelHome
	local restoreGame = gameFrame and animateGame(gameFrame, true)
		or (queueFrame and queueFrame.Visible and animateGame(queueFrame, true, nil, QUEUE_POSES) or nil)
	local delay = gameFrame and 0.2 or 0
	local animation = playTween(overlay, { BackgroundTransparency = 0 },
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, delay))
	local function cleanup()
		animation:Cancel()
		if cancelHome then cancelHome() cancelHome = nil end
		if restoreGame then restoreGame() restoreGame = nil end
		overlay:Destroy()
	end
	task.delay(0.7 + delay, function()
		if finished or not overlay.Parent then return end
		overlay.BackgroundTransparency = 0
		local ok, homeFrame = pcall(onCovered)
		if finished then return end
		if not ok or not homeFrame then
			finished = true
			cleanup()
			if onComplete then onComplete(false, homeFrame) end
			return
		end
		-- Restore authored game geometry only after Home replaces it.
		if restoreGame then restoreGame() restoreGame = nil end
		cancelHome = UIEffects.RevealHome(homeFrame)
		animation = playTween(overlay, { BackgroundTransparency = 1 }, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
		task.delay(0.8, function()
			if finished then return end
			finished = true
			cleanup()
			if onComplete then onComplete(true) end
		end)
	end)
	return function()
		if finished then return end
		finished = true
		cleanup()
	end
end

function UIEffects.WordFound(line, tiles, wordRow, color, faces)
	if not line or not line.Parent then return end
	UIEffects.Pulse(line, 1.12)
	for index, tile in ipairs(tiles) do
		task.delay((index - 1) / math.max(1, #tiles - 1) * 0.22, function()
			if tile.Parent then UIEffects.Pulse(tile, 1.10) end
			local face = faces and faces[index]
			if face and face.Parent then UIEffects.Pulse(face, 1.07) end
		end)
	end
	if wordRow then UIEffects.SoftHighlight(wordRow, color:Lerp(Color3.new(1, 1, 1), 0.45)) end
	local wordLabel = wordRow and wordRow:FindFirstChild("Word")
	if wordLabel then UIEffects.Pulse(wordLabel, 1.08) end
	local parent, origin = line.Parent, line.Position
	for index = 1, 10 do
		local angle = index / 10 * math.pi * 2
		local distance = math.clamp(line.Size.Y.Offset * 0.9, 24, 80)
		local spark = Instance.new("Frame")
		spark.Name = "WordSpark"
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = origin
		spark.Size = UDim2.fromOffset(7, 7)
		spark.Rotation = 45
		spark.BorderSizePixel = 0
		spark.BackgroundColor3 = index % 2 == 0 and color or color:Lerp(Color3.new(1, 1, 1), 0.35)
		spark.ZIndex = line.ZIndex + 3
		spark.Parent = parent
		playTween(spark, {
			Position = origin + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance),
			Size = UDim2.fromOffset(2, 2), Rotation = 135, BackgroundTransparency = 1,
		}, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		task.delay(0.42, function() spark:Destroy() end)
	end
end

function UIEffects.BonusWordFound(tiles)
	for _, tile in ipairs(tiles) do UIEffects.Pulse(tile, 1.08) end
end

function UIEffects.WrongWord(line, faces, letters)
	if not line or not line.Parent then return end
	-- A passive snapshot leaves solved colours, hint pulses and new input intact.
	local rejected = line:Clone()
	rejected.Name = "WrongWordFeedback"
	rejected.Active, rejected.Selectable = false, false
	if faces then
		local red = Color3.fromRGB(255,63,83)
		local depth = math.max(line.ZIndex, letters[1].ZIndex) + 1
		rejected.ZIndex = depth
		for _, node in ipairs(rejected:GetDescendants()) do
			if node:IsA("GuiObject") then
				node.ZIndex, node.Active, node.Selectable = depth, false, false
				node.BackgroundColor3 = red
			end
		end
		for index, face in ipairs(faces) do
			local plate = Instance.new("Frame")
			plate.Name, plate.BorderSizePixel = "WrongTile" .. index, 0
			plate.AnchorPoint, plate.Position, plate.Size = face.AnchorPoint, face.Position, face.Size
			plate.BackgroundColor3, plate.BackgroundTransparency, plate.ZIndex = red, 0, depth + 1
			plate.Active, plate.Selectable, plate.Parent = false, false, rejected
			local corner = face:FindFirstChildOfClass("UICorner")
			if corner then corner:Clone().Parent = plate end
			local tile = letters[index]
			local label = Instance.new("TextLabel")
			label.Name, label.BackgroundTransparency = "WrongLetter" .. index, 1
			label.AnchorPoint, label.Position, label.Size = tile.AnchorPoint, tile.Position, tile.Size
			label.Text, label.FontFace, label.TextScaled = tile.Text, tile.FontFace, tile.TextScaled
			label.TextColor3, label.TextTransparency = Color3.new(1,1,1), 0
			label.ZIndex, label.Active, label.Selectable = depth + 2, false, false
			label.Parent = rejected
			local constraint = tile:FindFirstChildOfClass("UITextSizeConstraint")
			if constraint then constraint:Clone().Parent = label end
		end
	end
	rejected.Parent = line.Parent
	local origin = rejected.Position
	local shake = math.clamp(rejected.Size.Y.Offset * 0.08, 3, 8)
	local stopped, destroying, animations = false, nil, {}
	local function stop(alreadyDestroying)
		if stopped then return end
		stopped = true
		for _, animation in ipairs(animations) do animation:Cancel() end
		if destroying then destroying:Disconnect() end
		if not alreadyDestroying then rejected:Destroy() end
	end
	destroying = rejected.Destroying:Connect(function() stop(true) end)
	local function animate(target, properties, info)
		table.insert(animations, playTween(target, properties, info))
	end
	for index, offset in ipairs({ -1, 1, -0.7, 0.7, 0 }) do
		task.delay((index - 1) * 0.045, function()
			if stopped or not rejected.Parent then return end
			animate(rejected, { Position = origin + UDim2.fromOffset(offset * shake, 0) },
				TweenInfo.new(0.045, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
		end)
	end
	task.delay(0.22, function()
		if stopped or not rejected.Parent then return end
		local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		animate(rejected, { BackgroundTransparency = 1 }, info)
		for _, child in ipairs(rejected:GetDescendants()) do
			if child:IsA("GuiObject") then
				local properties = {BackgroundTransparency=1}
				if child:IsA("TextLabel") or child:IsA("TextButton") then properties.TextTransparency = 1 end
				animate(child, properties, info)
			end
		end
	end)
	task.delay(0.42, stop)
	return stop
end

return UIEffects
