local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Camera = {}
local RENDER_BINDING = "WordHuntFixedCamera"
local poseConnection, ownerConnection
local target, fieldOfView = nil, 40

local function apply()
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera or not target then return end
	currentCamera.CameraType = Enum.CameraType.Scriptable
	currentCamera.CFrame = target
	currentCamera.Focus = target * CFrame.new(0, 0, -100)
	currentCamera.FieldOfView = fieldOfView
end

function Camera.Stop()
	RunService:UnbindFromRenderStep(RENDER_BINDING)
	if poseConnection then poseConnection:Disconnect() end
	if ownerConnection then ownerConnection:Disconnect() end
	poseConnection, ownerConnection, target = nil, nil, nil
end

function Camera.ApplyJoinCamera(cameraConfig)
	if type(cameraConfig) ~= "table" then return end
	Camera.Stop()
	fieldOfView = cameraConfig.FieldOfView or 40
	local attribute = (cameraConfig.PartName or "CamPart") .. "CFrame"
	local function refresh()
		local pose = ReplicatedStorage:GetAttribute(attribute)
		if typeof(pose) == "CFrame" then target = pose end
		apply()
	end
	poseConnection = ReplicatedStorage:GetAttributeChangedSignal(attribute):Connect(refresh)
	if cameraConfig.Owner then ownerConnection = cameraConfig.Owner.Destroying:Connect(Camera.Stop) end
	refresh()
	-- Runs after the default camera, including after character/camera replacements.
	RunService:BindToRenderStep(RENDER_BINDING, Enum.RenderPriority.Camera.Value + 1, apply)
end

return Camera
