local TweenService = game:GetService("TweenService")

local UIEffects = {}

local BUTTON_STATE = {}

local HOVER_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PULSE_UP_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_DOWN_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local function playTween(instance, properties, tweenInfo)
	local animation = TweenService:Create(instance, tweenInfo, properties)
	animation:Play()
	return animation
end

local function getOrCreateScaleController(guiObject)
	local scaleController = guiObject:FindFirstChild("ScaleController")
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
	state.hoverBrightness = options and options.hoverBrightness or state.hoverBrightness
	state.hoverScale = options and options.hoverScale or state.hoverScale
	state.pressScale = options and options.pressScale or state.pressScale
	state.baseColor = options and options.baseColor or button.BackgroundColor3

	local function canAnimate()
		return button.Parent ~= nil and button:GetAttribute("ButtonEnabled") ~= false
	end

	button.MouseEnter:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.hoverScale }, HOVER_TWEEN)
		playTween(button, { BackgroundColor3 = brighten(state.baseColor, state.hoverBrightness) }, HOVER_TWEEN)
	end)

	button.MouseLeave:Connect(function()
		playTween(state.scaleController, { Scale = 1 }, HOVER_TWEEN)
		playTween(button, {
			BackgroundColor3 = canAnimate() and state.baseColor or button.BackgroundColor3,
		}, HOVER_TWEEN)
	end)

	button.MouseButton1Down:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.pressScale }, PRESS_TWEEN)
	end)

	button.MouseButton1Up:Connect(function()
		if not canAnimate() then
			return
		end

		playTween(state.scaleController, { Scale = state.hoverScale }, PRESS_TWEEN)
	end)

	button.Destroying:Connect(function()
		BUTTON_STATE[button] = nil
	end)
end

function UIEffects.Pulse(guiObject, peakScale, settleScale)
	if not guiObject then
		return
	end

	local scaleController = getOrCreateScaleController(guiObject)
	local targetPeak = peakScale or 1.06
	local targetSettle = settleScale or 1

	scaleController.Scale = targetSettle
	playTween(scaleController, { Scale = targetPeak }, PULSE_UP_TWEEN)

	task.delay(0.16, function()
		if scaleController.Parent then
			playTween(scaleController, { Scale = targetSettle }, PULSE_DOWN_TWEEN)
		end
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

return UIEffects
