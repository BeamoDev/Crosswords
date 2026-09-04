local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DeviceOrientation = {}

local TABLET_MIN_SHORTEST_SIDE = 550
local TABLET_MAX_ASPECT_RATIO = 1.7
local VIEWPORT_SETTLE_DELAY = 0.2

local state = {
	initialized = false,
	playerGui = nil,
	onViewportChanged = nil,
	viewportToken = 0,
	cameraConnection = nil,
	cameraChangedConnection = nil,
}

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end

	return Vector2.new(0, 0)
end

function DeviceOrientation.IsTablet()
	if not UserInputService.TouchEnabled then
		return false
	end

	local size = getViewportSize()
	local shortest = math.min(size.X, size.Y)
	local longest = math.max(size.X, size.Y)
	if shortest <= 0 then
		return false
	end

	local aspectRatio = longest / shortest
	return shortest >= TABLET_MIN_SHORTEST_SIDE and aspectRatio < TABLET_MAX_ASPECT_RATIO
end

function DeviceOrientation.GetDeviceClass()
	if not UserInputService.TouchEnabled then
		return "Desktop"
	end

	return DeviceOrientation.IsTablet() and "Tablet" or "Phone"
end

local function applyScreenOrientation()
	if not state.playerGui then
		return
	end

	local deviceClass = DeviceOrientation.GetDeviceClass()
	local targetOrientation = nil
	if deviceClass == "Tablet" then
		targetOrientation = Enum.ScreenOrientation.Sensor
	elseif deviceClass == "Phone" then
		targetOrientation = Enum.ScreenOrientation.Portrait
	end

	if targetOrientation then
		pcall(function()
			state.playerGui.ScreenOrientation = targetOrientation
		end)
	end
end

local function scheduleViewportChanged()
	state.viewportToken += 1
	local token = state.viewportToken

	task.delay(VIEWPORT_SETTLE_DELAY, function()
		if token ~= state.viewportToken then
			return
		end

		applyScreenOrientation()
		if state.onViewportChanged then
			state.onViewportChanged(DeviceOrientation.GetDeviceClass())
		end
	end)
end

local function bindCurrentCamera()
	if state.cameraConnection then
		state.cameraConnection:Disconnect()
		state.cameraConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		state.cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleViewportChanged)
	end
end

function DeviceOrientation.Init(options)
	if state.initialized then
		return DeviceOrientation.GetDeviceClass()
	end

	state.initialized = true
	state.playerGui = options and options.playerGui or nil
	state.onViewportChanged = options and options.onViewportChanged or nil

	applyScreenOrientation()
	bindCurrentCamera()
	state.cameraChangedConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCurrentCamera()
		scheduleViewportChanged()
	end)
	scheduleViewportChanged()

	return DeviceOrientation.GetDeviceClass()
end

return DeviceOrientation
