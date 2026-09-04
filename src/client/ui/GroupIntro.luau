local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GroupIntro = {}

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local CONFIG = {
	iconIntroSize = isMobile and UDim2.fromScale(0.46, 0.24) or UDim2.fromScale(0.52, 0.29),
	ghostIntroSize = isMobile and UDim2.fromScale(0.58, 0.3) or UDim2.fromScale(0.63, 0.355),
	ghostPulseSize = isMobile and UDim2.fromScale(0.64, 0.34) or UDim2.fromScale(0.7, 0.4),
	iconPulseSize = isMobile and UDim2.fromScale(0.57, 0.3) or UDim2.fromScale(0.57, 0.32),
	iconOutroSize = UDim2.fromScale(0, 0),
	barIntroSize = isMobile and UDim2.fromScale(0.82, 0.035) or UDim2.fromScale(0.631, 0.02),
	introTime = 0.6,
	barIntroTime = 0.35,
	outroTime = 0.4,
	preloadBatchTimeout = 2.5,
}

local introPlaying = false
local fillTween = nil

local function createTween(object, tweenInfo, properties)
	if not object or object.Parent == nil then
		return nil
	end

	local tween = TweenService:Create(object, tweenInfo, properties)
	tween:Play()
	return tween
end

local function playIntroSound(name)
	local folder = SoundService:FindFirstChild("GroupIntro")
	local sound = folder and folder:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function playIconLoop(icon)
	local basePosition = icon.Position
	local baseRotation = icon.Rotation
	local baseSize = icon.Size
	local startedAt = tick()

	local connection = RunService.RenderStepped:Connect(function()
		if not icon.Parent then
			return
		end

		local elapsed = tick() - startedAt
		local xOffset = math.sin(elapsed * 0.7) * 0.004
		local yOffset = math.cos(elapsed * 1.05) * 0.012
		local scalePulse = 1 + math.sin(elapsed * 0.9) * 0.012

		icon.Position = basePosition + UDim2.fromScale(xOffset, yOffset)
		icon.Rotation = baseRotation + math.sin(elapsed * 0.82) * 4
		icon.Size = UDim2.new(
			baseSize.X.Scale * scalePulse,
			baseSize.X.Offset * scalePulse,
			baseSize.Y.Scale * scalePulse,
			baseSize.Y.Offset * scalePulse
		)
	end)

	return {
		basePosition = basePosition,
		baseRotation = baseRotation,
		baseSize = baseSize,
		stop = function(preserveCurrent)
			if connection then
				connection:Disconnect()
				connection = nil
			end

			if icon.Parent and not preserveCurrent then
				icon.Size = baseSize
				icon.Position = basePosition
				icon.Rotation = baseRotation
			end
		end,
	}
end

local function playGhostLoop(icon)
	local basePosition = icon.Position
	local baseRotation = icon.Rotation
	local baseSize = icon.Size
	local baseTransparency = icon.ImageTransparency
	local startedAt = tick()

	local connection = RunService.RenderStepped:Connect(function()
		if not icon.Parent then
			return
		end

		local elapsed = tick() - startedAt
		local xOffset = math.cos(elapsed * 0.52) * 0.007
		local yOffset = math.sin(elapsed * 0.66) * 0.016
		local scalePulse = 1.04 + math.sin(elapsed * 0.74) * 0.03

		icon.Position = basePosition + UDim2.fromScale(xOffset, yOffset)
		icon.Rotation = baseRotation + math.sin(elapsed * 0.6) * 6
		icon.Size = UDim2.new(
			baseSize.X.Scale * scalePulse,
			baseSize.X.Offset * scalePulse,
			baseSize.Y.Scale * scalePulse,
			baseSize.Y.Offset * scalePulse
		)
		icon.ImageTransparency = math.clamp(baseTransparency + 0.04 + math.sin(elapsed * 0.88) * 0.04, 0, 1)
	end)

	return {
		basePosition = basePosition,
		baseRotation = baseRotation,
		baseSize = baseSize,
		stop = function(preserveCurrent)
			if connection then
				connection:Disconnect()
				connection = nil
			end

			if icon.Parent and not preserveCurrent then
				icon.Position = basePosition
				icon.Rotation = baseRotation
				icon.Size = baseSize
				icon.ImageTransparency = baseTransparency
			end
		end,
	}
end

local function updateStatus(statusLabel, percent)
	if statusLabel then
		statusLabel.Text = string.format("Loading %d%%", percent)
	end
end

local function tweenFillBar(fillBar, alpha, duration)
	if not fillBar then
		return
	end

	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end

	fillTween = TweenService:Create(
		fillBar,
		TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(alpha, 0, 1, 0) }
	)
	fillTween:Play()
end

local function findRootGui(instance)
	local current = instance

	while current do
		if current:IsA("LayerCollector") then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function findIntroFrame(root)
	if not root then
		return nil
	end

	if root:IsA("GuiObject") then
		return root
	end

	local frame = root:FindFirstChild("Frame")
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Name == "Frame" then
			return descendant
		end
	end

	return nil
end

local function findBarContainer(parentFrame)
	for _, child in ipairs(parentFrame:GetChildren()) do
		if child:IsA("GuiObject") and child:FindFirstChild("Fill") then
			return child
		end
	end

	local progressBar = parentFrame:FindFirstChild("ProgressBar")
	if progressBar and progressBar:IsA("GuiObject") then
		return progressBar
	end

	local frame = parentFrame:FindFirstChild("Frame")
	if frame and frame:IsA("GuiObject") and frame:FindFirstChild("Fill") then
		return frame
	end

	return nil
end

local function findPatternImage(root)
	if not root then
		return nil
	end

	local pattern = root:FindFirstChild("Pattern", true)
	if pattern and (pattern:IsA("ImageLabel") or pattern:IsA("ImageButton")) then
		return pattern
	end

	return nil
end

local function showGuiTree(node)
	local current = node

	while current do
		if current:IsA("GuiObject") then
			current.Visible = true
		elseif current:IsA("ScreenGui") then
			current.Enabled = true
		end

		current = current.Parent
	end
end

local function collectPreloadTargets(roots)
	local seen = {}
	local targets = {}

	local function add(target)
		if type(target) == "string" then
			if target == "" then
				return
			end
		elseif typeof(target) == "Instance" then
			local className = target.ClassName
			if className == "ImageLabel" or className == "ImageButton" then
				if target.Image == "" then
					return
				end
			elseif className == "Decal" or className == "Texture" then
				if target.Texture == "" then
					return
				end
			elseif className == "Sound" then
				if target.SoundId == "" then
					return
				end
			elseif className == "Animation" then
				if target.AnimationId == "" then
					return
				end
			elseif className == "ShirtGraphic" then
				if target.Graphic == "" then
					return
				end
			elseif className == "MeshPart" then
				if target.MeshId == "" and target.TextureID == "" then
					return
				end
			elseif className == "SpecialMesh" then
				if target.MeshId == "" and target.TextureId == "" then
					return
				end
			elseif className == "SurfaceAppearance" then
				if target.ColorMap == "" and target.MetalnessMap == "" and target.NormalMap == "" and target.RoughnessMap == "" then
					return
				end
			end
		else
			return
		end

		if not target or seen[target] then
			return
		end

		seen[target] = true
		table.insert(targets, target)
	end

	local function scan(root)
		if not root then
			return
		end

		add(root)
		if typeof(root) ~= "Instance" then
			return
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ImageLabel")
				or descendant:IsA("ImageButton")
				or descendant:IsA("Decal")
				or descendant:IsA("Texture")
				or descendant:IsA("MeshPart")
				or descendant:IsA("SpecialMesh")
				or descendant:IsA("Sound")
				or descendant:IsA("Animation")
				or descendant:IsA("ShirtGraphic")
				or descendant:IsA("SurfaceAppearance") then
				add(descendant)
			end
		end
	end

	for _, root in ipairs(roots or {}) do
		scan(root)
	end

	return targets
end

local function preloadWithStatus(roots, statusLabel, fillBar)
	local targets = collectPreloadTargets(roots)
	local total = #targets

	if total == 0 then
		updateStatus(statusLabel, 100)
		tweenFillBar(fillBar, 1, 0.2)
		return
	end

	local loaded = 0
	local batchSize = 25

	local function preloadBatch(batch)
		local completed = false

		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
			completed = true
		end)

		local deadline = tick() + math.max(0.5, tonumber(CONFIG.preloadBatchTimeout) or 2.5)
		while completed ~= true and tick() < deadline do
			task.wait()
		end
	end

	updateStatus(statusLabel, 0)
	tweenFillBar(fillBar, 0, 0.2)

	for index = 1, total, batchSize do
		local batch = {}

		for batchIndex = index, math.min(index + batchSize - 1, total) do
			table.insert(batch, targets[batchIndex])
		end

		preloadBatch(batch)

		loaded += #batch
		local percent = math.clamp(math.floor((loaded / total) * 100 + 0.5), 0, 100)
		updateStatus(statusLabel, percent)
		tweenFillBar(fillBar, percent / 100, 0.16)
		task.wait()
	end

	updateStatus(statusLabel, 100)
	tweenFillBar(fillBar, 1, 0.2)
end

function GroupIntro:SetProgress(_target)
end

function GroupIntro:Play(groupIntroRoot, preloadRoots, onComplete, options)
	if groupIntroRoot then
		showGuiTree(groupIntroRoot)
		if groupIntroRoot:IsA("ScreenGui") then
			groupIntroRoot.Enabled = true
		end
	end

	if introPlaying then
		return
	end

	introPlaying = true

	local parentFrame = findIntroFrame(groupIntroRoot)
	local rootGui = findRootGui(groupIntroRoot) or (parentFrame and findRootGui(parentFrame))
	local groupIcon = parentFrame and (parentFrame:FindFirstChild("Icon") or parentFrame:FindFirstChild("GroupIcon"))
	local progressBar = parentFrame and findBarContainer(parentFrame)
	local fillBar = progressBar and progressBar:FindFirstChild("Fill")
	local statusLabel = parentFrame and parentFrame:FindFirstChild("Status")
	local patternImage = parentFrame and findPatternImage(parentFrame)

	if rootGui and rootGui:IsA("ScreenGui") then
		rootGui.Enabled = true
	end

	if not (parentFrame and groupIcon and progressBar and fillBar) then
		if rootGui and rootGui:IsA("ScreenGui") then
			rootGui.Enabled = false
		end
		introPlaying = false
		if onComplete then
			pcall(onComplete)
		end
		return
	end

	local ghostIcon = groupIcon:Clone()
	ghostIcon.Name = "IntroGhost"
	ghostIcon.AnchorPoint = groupIcon.AnchorPoint
	ghostIcon.Position = groupIcon.Position
	ghostIcon.Size = UDim2.fromScale(0, 0)
	ghostIcon.ImageTransparency = 0.72
	ghostIcon.BackgroundTransparency = 1
	ghostIcon.ZIndex = math.max(groupIcon.ZIndex - 1, 1)
	ghostIcon.Parent = parentFrame

	groupIcon.Size = UDim2.fromScale(0, 0)
	progressBar.Size = UDim2.fromScale(0, 0)
	fillBar.Size = UDim2.new(0, 0, 1, 0)
	showGuiTree(parentFrame)

	if rootGui and rootGui:IsA("ScreenGui") then
		rootGui.Enabled = true
	end

	if groupIntroRoot and groupIntroRoot:IsA("GuiObject") then
		groupIntroRoot.BackgroundTransparency = 0
	end
	parentFrame.BackgroundTransparency = 0
	parentFrame.Visible = true
	groupIcon.Visible = true
	progressBar.Visible = true
	fillBar.Visible = true
	if patternImage then
		patternImage.Visible = true
		patternImage.ImageTransparency = 1
	end

	if statusLabel then
		statusLabel.Visible = true
		statusLabel.TextTransparency = 0
	end

	updateStatus(statusLabel, 0)
	playIntroSound("Theme")

	task.spawn(function()
		playIntroSound("Whoosh")

		createTween(ghostIcon, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = CONFIG.ghostIntroSize,
			ImageTransparency = 0.84,
		})

		local iconIntroTween = createTween(groupIcon, TweenInfo.new(CONFIG.introTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = CONFIG.iconIntroSize,
		})
		if iconIntroTween then
			iconIntroTween.Completed:Wait()
		end

		local iconLoop = playIconLoop(groupIcon)
		local ghostLoop = playGhostLoop(ghostIcon)

		local barTween = createTween(progressBar, TweenInfo.new(CONFIG.barIntroTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = CONFIG.barIntroSize,
		})
		createTween(patternImage, TweenInfo.new(CONFIG.introTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 0.97,
		})
		if barTween then
			barTween.Completed:Wait()
		end

		preloadWithStatus(preloadRoots or {}, statusLabel, fillBar)
		task.wait(0.2)
		local shouldFinish = type(options) == "table" and options.shouldFinish or nil
		local finishTimeout = math.max(0, tonumber(type(options) == "table" and options.finishTimeout or nil) or 12)
		local waitStartedAt = tick()
		while type(shouldFinish) == "function" and shouldFinish() ~= true and (tick() - waitStartedAt) < finishTimeout do
			task.wait(0.05)
		end

		playIntroSound("EndSFX")
		iconLoop.stop(true)
		ghostLoop.stop(true)

		createTween(groupIcon, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = iconLoop.basePosition,
			Size = CONFIG.iconPulseSize,
			Rotation = 0,
		})
		createTween(ghostIcon, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = ghostLoop.basePosition,
			Size = CONFIG.ghostPulseSize,
			ImageTransparency = 0.97,
			Rotation = ghostLoop.baseRotation,
		})
		task.wait(0.16)

		local outroInfo = TweenInfo.new(CONFIG.outroTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		createTween(progressBar, outroInfo, { Size = UDim2.fromScale(0, 0), BackgroundTransparency = 1 })
		createTween(patternImage, outroInfo, { ImageTransparency = 1 })
		createTween(groupIcon, outroInfo, {
			Position = iconLoop.basePosition,
			Size = CONFIG.iconOutroSize,
			Rotation = 0,
		})
		createTween(ghostIcon, outroInfo, {
			Position = ghostLoop.basePosition,
			Size = CONFIG.iconOutroSize,
			ImageTransparency = 1,
			Rotation = ghostLoop.baseRotation,
		})
		if statusLabel then
			createTween(statusLabel, outroInfo, { TextTransparency = 1 })
		end

		task.wait(CONFIG.outroTime + 0.05)

		if ghostIcon.Parent then
			ghostIcon:Destroy()
		end

		if rootGui and rootGui:IsA("ScreenGui") then
			rootGui.Enabled = false
		elseif groupIntroRoot and groupIntroRoot:IsA("GuiObject") then
			groupIntroRoot.Visible = false
		end

		introPlaying = false

		if onComplete then
			pcall(onComplete)
		end
	end)
end

return GroupIntro
