local Workspace = game:GetService("Workspace")

local module = {}

function module.getCurrentCamera()
	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		return currentCamera
	end

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
	return Workspace.CurrentCamera
end

function module.getCameraPart(partName)
	local cameraPart = Workspace:FindFirstChild(partName)
	if cameraPart and cameraPart:IsA("BasePart") then
		return cameraPart
	end

	local waitedPart = Workspace:WaitForChild(partName, 10)
	if waitedPart and waitedPart:IsA("BasePart") then
		return waitedPart
	end

	return nil
end

function module.applyJoinCamera(cameraConfig)
	if type(cameraConfig) ~= "table" then
		return
	end

	local currentCamera = module.getCurrentCamera()
	local cameraPart = module.getCameraPart(cameraConfig.PartName)
	if not currentCamera or not cameraPart then
		return
	end

	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.CFrame = cameraPart.CFrame
	currentCamera.Focus = cameraPart.CFrame
	currentCamera.FieldOfView = cameraConfig.FieldOfView
end

return module
