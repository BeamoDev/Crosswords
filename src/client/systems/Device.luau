local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Device = {}
local TABLET_MIN_SHORTEST_SIDE = 550
local TABLET_MAX_ASPECT_RATIO = 1.7
local VIEWPORT_SETTLE_DELAY = 0.2
local deviceState = {
	initialized = false,
	playerGui = nil,
	onViewportChanged = nil,
	viewportToken = 0,
	cameraConnection = nil,
	cameraChangedConnection = nil,
}

local function getViewportSize()
	local camera = Workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(0, 0)
end

function Device.IsTablet()
	if not UserInputService.TouchEnabled then
		return false
	end

	local size = getViewportSize()
	local shortest = math.min(size.X, size.Y)
	local longest = math.max(size.X, size.Y)
	if shortest <= 0 then
		return false
	end

	return shortest >= TABLET_MIN_SHORTEST_SIDE and (longest / shortest) < TABLET_MAX_ASPECT_RATIO
end

function Device.GetDeviceClass()
	if not UserInputService.TouchEnabled then
		return "Desktop"
	end

	return Device.IsTablet() and "Tablet" or "Phone"
end

local function applyScreenOrientation()
	if not deviceState.playerGui then
		return
	end

	local deviceClass = Device.GetDeviceClass()
	local targetOrientation = deviceClass == "Tablet" and Enum.ScreenOrientation.Sensor
		or deviceClass == "Phone" and Enum.ScreenOrientation.Portrait
		or nil
	if targetOrientation then
		pcall(function()
			deviceState.playerGui.ScreenOrientation = targetOrientation
		end)
	end
end

local function scheduleViewportChanged()
	deviceState.viewportToken += 1
	local token = deviceState.viewportToken
	task.delay(VIEWPORT_SETTLE_DELAY, function()
		if token ~= deviceState.viewportToken then
			return
		end
		applyScreenOrientation()
		if deviceState.onViewportChanged then
			deviceState.onViewportChanged(Device.GetDeviceClass())
		end
	end)
end

local function bindCurrentCamera()
	if deviceState.cameraConnection then
		deviceState.cameraConnection:Disconnect()
		deviceState.cameraConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		deviceState.cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleViewportChanged)
	end
end

function Device.Init(options)
	if deviceState.initialized then
		return Device.GetDeviceClass()
	end

	deviceState.initialized = true
	deviceState.playerGui = options and options.playerGui or nil
	deviceState.onViewportChanged = options and options.onViewportChanged or nil
	applyScreenOrientation()
	bindCurrentCamera()
	deviceState.cameraChangedConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCurrentCamera()
		scheduleViewportChanged()
	end)
	scheduleViewportChanged()
	return Device.GetDeviceClass()
end

function Device.Destroy()
	deviceState.viewportToken += 1
	for _, connectionName in ipairs({ "cameraConnection", "cameraChangedConnection" }) do
		local connection = deviceState[connectionName]
		if connection then
			connection:Disconnect()
			deviceState[connectionName] = nil
		end
	end
	deviceState.initialized = false
	deviceState.playerGui = nil
	deviceState.onViewportChanged = nil
end

return Device
