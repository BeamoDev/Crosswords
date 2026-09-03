--!nocheck

-- Client-only sky presentation for the translucent Word Search HUD. Camera
-- motion is handled by one long TweenService tween, so it adds no per-frame Lua
-- callback to the input/render hot path.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EnvironmentController = {}
EnvironmentController.__index = EnvironmentController

local EFFECT_NAMES = {
	"WordSearchSkyBlur",
	"WordSearchSkyBloom",
	"WordSearchSkyColor",
	"WordSearchSkyRays",
	"WordSearchSkyAtmosphere",
}

local LIGHTING_TARGETS = {
	Ambient = Color3.fromRGB(86, 145, 215),
	Brightness = 3,
	ClockTime = 14.2,
	ColorShift_Bottom = Color3.fromRGB(8, 49, 105),
	ColorShift_Top = Color3.fromRGB(91, 190, 255),
	EnvironmentDiffuseScale = 0.82,
	EnvironmentSpecularScale = 0.92,
	ExposureCompensation = 0.28,
	GlobalShadows = true,
	OutdoorAmbient = Color3.fromRGB(151, 211, 255),
}

local function setProperties(instance, properties)
	for property, value in pairs(properties) do
		pcall(function()
			instance[property] = value
		end)
	end
end

local function createOwnedEffect(className, name, properties)
	local previous = Lighting:FindFirstChild(name)
	if previous and previous:GetAttribute("WordSearchOwned") == true then
		previous:Destroy()
	end
	local effect = Instance.new(className)
	effect.Name = name
	effect:SetAttribute("WordSearchOwned", true)
	setProperties(effect, properties)
	effect.Parent = Lighting
	return effect
end

local function disconnect(connection)
	if connection then
		connection:Disconnect()
	end
end

function EnvironmentController.new(options)
	options = options or {}
	local self = setmetatable({}, EnvironmentController)
	self._destroyed = false
	self._reducedMotion = options.reducedMotion == true
	self._camera = nil
	self._cameraOriginal = nil
	self._activeTween = nil
	self._panToken = 0
	self._connections = {}
	self._effects = {}
	self._lightingOriginal = {}
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local compactDevice = UserInputService.TouchEnabled and (viewport.X < 1000 or viewport.Y < 600)

	for property in pairs(LIGHTING_TARGETS) do
		local ok, value = pcall(function()
			return Lighting[property]
		end)
		if ok then
			self._lightingOriginal[property] = value
		end
	end
	setProperties(Lighting, LIGHTING_TARGETS)

	for _, name in ipairs(EFFECT_NAMES) do
		local previous = Lighting:FindFirstChild(name)
		if previous and previous:GetAttribute("WordSearchOwned") == true then
			previous:Destroy()
		end
	end
	table.insert(self._effects, createOwnedEffect("BlurEffect", EFFECT_NAMES[1], {
		Size = compactDevice and 7 or 11,
	}))
	table.insert(self._effects, createOwnedEffect("BloomEffect", EFFECT_NAMES[2], {
		Intensity = compactDevice and 0.32 or 0.48,
		Size = compactDevice and 24 or 38,
		Threshold = 0.86,
	}))
	table.insert(self._effects, createOwnedEffect("ColorCorrectionEffect", EFFECT_NAMES[3], {
		Brightness = 0.06,
		Contrast = 0.12,
		Saturation = 0.34,
		TintColor = Color3.fromRGB(224, 243, 255),
	}))
	table.insert(self._effects, createOwnedEffect("SunRaysEffect", EFFECT_NAMES[4], {
		Intensity = compactDevice and 0.04 or 0.075,
		Spread = 0.82,
	}))
	table.insert(self._effects, createOwnedEffect("Atmosphere", EFFECT_NAMES[5], {
		Color = Color3.fromRGB(188, 226, 255),
		Decay = Color3.fromRGB(70, 131, 207),
		Density = 0.2,
		Glare = 0.28,
		Haze = 1.35,
		Offset = 0.08,
	}))

	table.insert(self._connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:_bindCurrentCamera()
	end))
	local player = Players.LocalPlayer
	if player then
		table.insert(self._connections, player.CharacterAdded:Connect(function()
			task.defer(function()
				if not self._destroyed then
					self:_startPan()
				end
			end)
		end))
	end
	self:_bindCurrentCamera()
	return self
end

function EnvironmentController:_captureCamera(camera)
	return {
		CameraSubject = camera.CameraSubject,
		CameraType = camera.CameraType,
		CFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
		Focus = camera.Focus,
	}
end

function EnvironmentController:_restoreCamera()
	local camera = self._camera
	local original = self._cameraOriginal
	if not camera or not original then
		return
	end
	pcall(function()
		camera.CameraSubject = original.CameraSubject
		camera.CameraType = original.CameraType
		camera.CFrame = original.CFrame
		camera.FieldOfView = original.FieldOfView
		camera.Focus = original.Focus
	end)
	self._camera = nil
	self._cameraOriginal = nil
end

function EnvironmentController:_skyPosition(camera)
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 160, 0)
	end
	return camera.CFrame.Position + Vector3.new(0, 80, 0)
end

function EnvironmentController:_skyFrame(position, yaw)
	local direction = Vector3.new(math.sin(yaw) * 0.62, 0.78, -math.cos(yaw) * 0.62).Unit
	return CFrame.lookAt(position, position + direction, Vector3.yAxis)
end

function EnvironmentController:_stopPan()
	self._panToken += 1
	if self._activeTween then
		self._activeTween:Cancel()
		self._activeTween = nil
	end
end

function EnvironmentController:_startPan()
	self:_stopPan()
	local camera = self._camera
	if self._destroyed or not camera then
		return
	end

	local position = self:_skyPosition(camera)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 74
	camera.CFrame = self:_skyFrame(position, -0.34)
	camera.Focus = CFrame.new(position + Vector3.new(0, 180, -180))
	if self._reducedMotion then
		camera.CFrame = self:_skyFrame(position, 0)
		return
	end

	local token = self._panToken
	task.spawn(function()
		local targetYaw = 0.34
		while not self._destroyed and self._camera == camera and self._panToken == token do
			local tween = TweenService:Create(
				camera,
				TweenInfo.new(16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = self:_skyFrame(position, targetYaw) }
			)
			self._activeTween = tween
			tween:Play()
			tween.Completed:Wait()
			if self._activeTween == tween then
				self._activeTween = nil
			end
			targetYaw = -targetYaw
		end
	end)
end

function EnvironmentController:_bindCurrentCamera()
	if self._destroyed then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == self._camera then
		return
	end
	self:_stopPan()
	self:_restoreCamera()
	if camera then
		self._camera = camera
		self._cameraOriginal = self:_captureCamera(camera)
		self:_startPan()
	end
end

function EnvironmentController:SetReducedMotion(reducedMotion)
	reducedMotion = reducedMotion == true
	if self._reducedMotion == reducedMotion then
		return
	end
	self._reducedMotion = reducedMotion
	self:_startPan()
end

function EnvironmentController:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:_stopPan()
	for _, connection in ipairs(self._connections) do
		disconnect(connection)
	end
	table.clear(self._connections)
	self:_restoreCamera()
	for _, effect in ipairs(self._effects) do
		if effect and effect.Parent and effect:GetAttribute("WordSearchOwned") == true then
			effect:Destroy()
		end
	end
	table.clear(self._effects)
	setProperties(Lighting, self._lightingOriginal)
end

return table.freeze(EnvironmentController)
