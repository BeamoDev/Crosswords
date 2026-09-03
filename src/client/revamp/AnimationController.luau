--!nocheck

local TweenService = game:GetService("TweenService")

local Theme = require(assert(script.Parent:WaitForChild("Theme", 10), "Word Search Theme module is missing"))

local AnimationController = {}
AnimationController.__index = AnimationController

local function assignProperties(instance, properties)
	if not instance or instance.Parent == nil then
		return false
	end

	local ok = pcall(function()
		for property, value in pairs(properties or {}) do
			instance[property] = value
		end
	end)
	return ok
end

local function ensureScale(guiObject)
	if not guiObject then
		return nil
	end

	local scale = guiObject:FindFirstChild("RevampScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end

	scale = Instance.new("UIScale")
	scale.Name = "RevampScale"
	scale.Scale = 1
	scale.Parent = guiObject
	return scale
end

function AnimationController.new(options)
	options = options or {}
	local self = setmetatable({}, AnimationController)
	self._tweenService = options.tweenService or TweenService
	self._theme = options.theme or Theme
	self._reducedMotion = options.reducedMotion == true
	self._destroyed = false
	self._active = setmetatable({}, { __mode = "k" })
	self._sequenceTokens = setmetatable({}, { __mode = "k" })
	self._delayToken = 0
	return self
end

function AnimationController:SetReducedMotion(enabled)
	self._reducedMotion = enabled == true
	if self._reducedMotion then
		for instance in pairs(self._active) do
			self:Cancel(instance, true)
		end
	end
end

function AnimationController:IsReducedMotion()
	return self._reducedMotion
end

function AnimationController:_resolveTweenInfo(spec)
	if typeof(spec) == "TweenInfo" then
		return spec
	end
	if type(spec) == "number" then
		return TweenInfo.new(math.max(0, spec), Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end
	if type(spec) == "string" and self._theme.Motion[spec] then
		return self._theme.Motion[spec]
	end
	return self._theme.Motion.Normal
end

function AnimationController:Cancel(instance, preserveCurrent)
	local record = self._active[instance]
	if not record then
		return
	end

	self._active[instance] = nil
	if record.connection then
		record.connection:Disconnect()
	end
	if record.tween then
		pcall(function()
			record.tween:Cancel()
		end)
	end
	if preserveCurrent ~= true and record.restore then
		assignProperties(instance, record.restore)
	end
end

-- Tween(instance, goals, spec?, onComplete?)
-- `spec` accepts a TweenInfo, duration in seconds, or a Theme.Motion key.
function AnimationController:Tween(instance, goals, spec, onComplete)
	if self._destroyed or not instance or instance.Parent == nil then
		return nil
	end

	self:Cancel(instance, true)
	if self._reducedMotion then
		assignProperties(instance, goals)
		if onComplete then
			onComplete(true)
		end
		return nil
	end

	local ok, tweenObject = pcall(function()
		return self._tweenService:Create(instance, self:_resolveTweenInfo(spec), goals)
	end)
	if not ok or not tweenObject then
		assignProperties(instance, goals)
		if onComplete then
			onComplete(false)
		end
		return nil
	end

	local record = { tween = tweenObject }
	self._active[instance] = record
	record.connection = tweenObject.Completed:Connect(function(playbackState)
		if self._active[instance] == record then
			self._active[instance] = nil
		end
		if record.connection then
			record.connection:Disconnect()
			record.connection = nil
		end
		if onComplete and not self._destroyed then
			onComplete(playbackState == Enum.PlaybackState.Completed)
		end
	end)
	tweenObject:Play()
	return tweenObject
end

function AnimationController:Pop(guiObject, options, onComplete)
	if not guiObject then
		return nil
	end
	options = options or {}
	local scale = ensureScale(guiObject)
	if not scale then
		return nil
	end

	local fromScale = tonumber(options.fromScale) or 0.9
	local toScale = tonumber(options.toScale) or 1
	scale.Scale = if self._reducedMotion then toScale else fromScale
	return self:Tween(scale, { Scale = toScale }, options.tweenInfo or "ModalIn", onComplete)
end

function AnimationController:Pulse(guiObject, options, onComplete)
	if not guiObject then
		return nil
	end
	options = options or {}
	local scale = ensureScale(guiObject)
	if not scale then
		return nil
	end

	local restingScale = tonumber(options.restingScale) or 1
	local peakScale = tonumber(options.peakScale) or 1.06
	if self._reducedMotion then
		scale.Scale = restingScale
		if onComplete then
			onComplete(true)
		end
		return nil
	end

	self._sequenceTokens[scale] = (self._sequenceTokens[scale] or 0) + 1
	local token = self._sequenceTokens[scale]
	return self:Tween(scale, { Scale = peakScale }, options.upTween or "Fast", function(completed)
		if not completed or self._destroyed or self._sequenceTokens[scale] ~= token then
			return
		end
		self:Tween(scale, { Scale = restingScale }, options.downTween or "Normal", onComplete)
	end)
end

function AnimationController:Shake(guiObject, options, onComplete)
	if not guiObject or guiObject.Parent == nil then
		return
	end
	options = options or {}
	local basePosition = guiObject.Position
	local distance = math.max(1, math.floor(tonumber(options.distance) or 7))
	if self._reducedMotion then
		guiObject.Position = basePosition
		if onComplete then
			onComplete(true)
		end
		return
	end

	self._sequenceTokens[guiObject] = (self._sequenceTokens[guiObject] or 0) + 1
	local token = self._sequenceTokens[guiObject]
	task.spawn(function()
		local offsets = { -distance, distance, -math.ceil(distance * 0.6), math.ceil(distance * 0.6), 0 }
		for _, offset in ipairs(offsets) do
			if self._destroyed or guiObject.Parent == nil or self._sequenceTokens[guiObject] ~= token then
				return
			end
			local tweenObject = self:Tween(
				guiObject,
				{ Position = basePosition + UDim2.fromOffset(offset, 0) },
				TweenInfo.new(0.045, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
			)
			if tweenObject then
				tweenObject.Completed:Wait()
			end
		end
		if guiObject.Parent then
			guiObject.Position = basePosition
		end
		if onComplete and not self._destroyed then
			onComplete(true)
		end
	end)
end

-- Fade supports GuiObjects and CanvasGroups. Callers may provide an explicit
-- property name when they need ImageTransparency or TextTransparency instead.
function AnimationController:Fade(instance, visible, options, onComplete)
	if not instance then
		return nil
	end
	options = options or {}
	local property = options.property
	if not property then
		property = if instance:IsA("CanvasGroup") then "GroupTransparency" else "BackgroundTransparency"
	end
	local shownValue = tonumber(options.shownValue) or 0
	local hiddenValue = tonumber(options.hiddenValue) or 1

	if visible and instance:IsA("GuiObject") then
		instance.Visible = true
	end
	return self:Tween(instance, { [property] = if visible then shownValue else hiddenValue }, options.tweenInfo or "Normal", function(completed)
		if not visible and completed and instance.Parent and instance:IsA("GuiObject") then
			instance.Visible = false
		end
		if onComplete then
			onComplete(completed)
		end
	end)
end

function AnimationController:Delay(seconds, callback)
	self._delayToken += 1
	local token = self._delayToken
	local duration = if self._reducedMotion then 0 else math.max(0, tonumber(seconds) or 0)
	task.delay(duration, function()
		if not self._destroyed and token == self._delayToken and callback then
			callback()
		end
	end)
	return token
end

function AnimationController:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._delayToken += 1
	for instance in pairs(self._active) do
		self:Cancel(instance, true)
	end
	table.clear(self._active)
	table.clear(self._sequenceTokens)
end

return AnimationController
