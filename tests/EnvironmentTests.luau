local fs, luau, rbx = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local checks = 0
local function check(value, reason) assert(value, reason) checks += 1 end
local function signal()
	local event = { listeners = {} }
	function event:Connect(fn)
		local connection = { active = true, fn = fn }
		function connection:Disconnect() self.active = false end
		table.insert(self.listeners, connection)
		return connection
	end
	function event:Fire(...) for _, c in ipairs(self.listeners) do if c.active then c.fn(...) end end end
	function event:Count() local count = 0 for _, c in ipairs(self.listeners) do if c.active then count += 1 end end return count end
	return event
end
local methods = {}
local meta = { __index = function(self, key) return methods[key] or self.props[key] end, __newindex = function(self, key, value)
	if key == "Parent" then
		if self.props.Parent then table.remove(self.props.Parent.children, table.find(self.props.Parent.children, self)) end
		if value then table.insert(value.children, self) end
	end
	self.props[key] = value
end }
local function instance(class)
	return setmetatable({ props = { ClassName = class, Destroying = signal() }, children = {}, attributes = {}, events = {} }, meta)
end
function methods:IsA(class) return self.ClassName == class or (class == "BasePart" and self.ClassName == "Part") end
function methods:FindFirstChild(name) for _, child in ipairs(self.children) do if child.Name == name then return child end end end
function methods:FindFirstChildOfClass(class) for _, child in ipairs(self.children) do if child:IsA(class) then return child end end end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:SetAttribute(name, value) self.attributes[name] = value if self.events[name] then self.events[name]:Fire() end end
function methods:GetAttributeChangedSignal(name) self.events[name] = self.events[name] or signal() return self.events[name] end
function methods:Destroy() self.Destroying:Fire() self.Parent = nil end
local function near(a, b) return math.abs(a - b) < 0.001 end
local function poseNear(a, b)
	return (a.Position - b.Position).Magnitude < 0.001 and (a.LookVector - b.LookVector).Magnitude < 0.0001 and (a.UpVector - b.UpVector).Magnitude < 0.0001
end
local storage, workspace, terrain = instance("ReplicatedStorage"), instance("Workspace"), instance("Terrain")
workspace.Terrain = terrain terrain.Parent = workspace
local authoredClouds = instance("Clouds") authoredClouds.Name = "Clouds" authoredClouds.Parent = terrain
local sky = instance("Sky")
local lighting = instance("Lighting") sky.Parent = lighting
lighting.TimeOfDay = "00:00:00"
local heartbeat = signal()
local services = { HttpService = {}, Players = {}, ServerStorage = instance("ServerStorage"), TeleportService = {},
	Lighting = lighting, Workspace = workspace, ReplicatedStorage = storage, RunService = { Heartbeat = heartbeat } }
local environment = { game = { GetService = function(_, name) return assert(services[name], name) end },
	Instance = { new = instance }, Color3 = rbx.Color3, CFrame = rbx.CFrame, Vector3 = rbx.Vector3 }
local operations = luau.load(fs.readFile("src/server/systems/Operations.luau"), { environment = environment })()
local part = operations.InitEnvironment()
check(part.Parent == workspace and part.Name == "CamPart", "Server creates the workspace camera anchor")
check(part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery and not part.CastShadow and part.Transparency == 1, "Camera anchor stays invisible and noninteractive")
check((part.CFrame.Position - rbx.Vector3.new(-225.271, 136.93, -519.269)).Magnitude < 0.001, "Exact requested camera position")
local x, y, z = part.CFrame:ToOrientation()
check(near(math.deg(x), 15.309) and near(math.deg(y), 40.884) and near(math.deg(z), 0), "Requested rotation uses Studio Orientation order")
check(poseNear(storage:GetAttribute("CamPartCFrame"), part.CFrame), "Server publishes the anchor pose outside streamed Workspace")
check(terrain:FindFirstChildOfClass("Clouds") == authoredClouds and authoredClouds.Enabled, "Existing Terrain Clouds are reused and enabled")
check(lighting:FindFirstChildOfClass("Sky") == sky, "Authored sky assets remain in place")
check(lighting.TimeOfDay == "12:15:00", "Server starts in daylight even if authored time was night")
check(operations.InitEnvironment() == part and #workspace.children == 2 and heartbeat:Count() == 1, "Repeated startup never adds anchors or cycle loops")
local firstCover, firstDensity, firstBrightness = authoredClouds.Cover, authoredClouds.Density, lighting.Brightness
heartbeat:Fire(0.1)
check(authoredClouds.Cover == firstCover, "Replication updates are throttled instead of running every frame")
local minHour, maxHour = 24, 0
local variedCover, variedDensity, variedBrightness, smooth, bounded = false, false, false, true, true
local previousCover = authoredClouds.Cover
for _ = 1, 8640 do
	heartbeat:Fire(0.25)
	local hour, minute, second = lighting.TimeOfDay:match("(%d+):(%d+):(%d+)")
	local time = tonumber(hour) + tonumber(minute) / 60 + tonumber(second) / 3600
	minHour, maxHour = math.min(minHour, time), math.max(maxHour, time)
	bounded = bounded and time >= 11 and time <= 15.5 and authoredClouds.Cover >= 0 and authoredClouds.Cover <= 1
		and authoredClouds.Density >= 0 and authoredClouds.Density <= 1 and lighting.Brightness >= 2
	smooth = smooth and math.abs(authoredClouds.Cover - previousCover) < 0.002
	previousCover = authoredClouds.Cover
	variedCover = variedCover or math.abs(firstCover - authoredClouds.Cover) > 0.1
	variedDensity = variedDensity or math.abs(firstDensity - authoredClouds.Density) > 0.1
	variedBrightness = variedBrightness or math.abs(firstBrightness - lighting.Brightness) > 0.2
end
check(bounded and minHour < 11.01 and maxHour > 15.49, "Three full cycles remain daylight with bounded clouds and brightness")
check(variedCover and variedDensity and variedBrightness, "Cloud cover, density and lighting all change over time")
check(smooth, "Cloud transitions remain smooth at every preset and cycle boundary")
heartbeat:Fire(9000)
check(lighting.TimeOfDay:match("^(%d+)") ~= "00", "Long server stalls do not reset to midnight")
operations.StopEnvironment()
local stoppedCover = authoredClouds.Cover
heartbeat:Fire(90)
check(heartbeat:Count() == 0 and authoredClouds.Cover == stoppedCover, "Shutdown stops environment updates")
authoredClouds:Destroy()
check(operations.InitEnvironment() == part and terrain:FindFirstChildOfClass("Clouds") ~= nil and #terrain.children == 1, "Restart reuses the anchor and creates Clouds when absent")
operations.StopEnvironment()

local function newClient(withCamera)
	local view = withCamera and { CameraType = rbx.Enum.CameraType.Custom } or nil
	local clientWorkspace = { CurrentCamera = view } -- No streamed part or Workspace lookup is available.
	local render = { bindings = {} }
	function render:BindToRenderStep(name, priority, fn) self.bindings[name] = { fn = fn, priority = priority } end
	function render:UnbindFromRenderStep(name) self.bindings[name] = nil end
	function render:Step() for _, binding in pairs(self.bindings) do binding.fn() end end
	local clientServices = { Workspace = clientWorkspace, ReplicatedStorage = storage, RunService = render }
	local controller = luau.load(fs.readFile("src/client/systems/Camera.luau"), { environment = {
		game = { GetService = function(_, name) return assert(clientServices[name], name) end }, Enum = rbx.Enum, CFrame = rbx.CFrame,
	} })()
	local owner = instance("ScreenGui")
	controller.ApplyJoinCamera({ PartName = "CamPart", FieldOfView = 40, Owner = owner })
	return controller, clientWorkspace, render, owner
end
local serverPose = storage:GetAttribute("CamPartCFrame")
storage:SetAttribute("CamPartCFrame", nil)
local camera, view, render, owner = newClient(true)
check(view.CurrentCamera.CameraType == rbx.Enum.CameraType.Custom, "Client safely waits for server pose replication")
storage:SetAttribute("CamPartCFrame", serverPose)
check(view.CurrentCamera.CameraType == rbx.Enum.CameraType.Scriptable and poseNear(view.CurrentCamera.CFrame, serverPose), "Late server pose locks the camera without needing the streamed part")
check(view.CurrentCamera.FieldOfView == 40 and poseNear(view.CurrentCamera.Focus, serverPose * rbx.CFrame.new(0, 0, -100)), "Camera retains FOV with focus ahead of the sky view")
local second, secondView, secondRender, secondOwner = newClient(false)
secondView.CurrentCamera = { CameraType = rbx.Enum.CameraType.Custom }
secondRender:Step()
check(poseNear(secondView.CurrentCamera.CFrame, view.CurrentCamera.CFrame), "Late cameras and joining clients receive the same server view")
view.CurrentCamera = { CameraType = rbx.Enum.CameraType.Custom, CFrame = rbx.CFrame.new() }
render:Step()
check(view.CurrentCamera.CameraType == rbx.Enum.CameraType.Scriptable and poseNear(view.CurrentCamera.CFrame, serverPose), "Respawn or CurrentCamera replacement reapplies the fixed view")
view.CurrentCamera.CFrame = rbx.CFrame.new(100, 100, 100)
render:Step()
check(poseNear(view.CurrentCamera.CFrame, serverPose), "Mouse/touch/controller camera changes cannot move the fixed view")
check(render.bindings.WordHuntFixedCamera.priority > rbx.Enum.RenderPriority.Camera.Value, "Fixed view applies after default camera controls")
camera.ApplyJoinCamera({ Owner = owner })
check(owner.Destroying:Count() == 1 and storage:GetAttributeChangedSignal("CamPartCFrame"):Count() == 2, "Repeated camera setup keeps one listener per player")
owner:Destroy()
check(next(render.bindings) == nil and storage:GetAttributeChangedSignal("CamPartCFrame"):Count() == 1, "Removing Main disconnects camera ownership")
secondOwner:Destroy()
check(next(secondRender.bindings) == nil and storage:GetAttributeChangedSignal("CamPartCFrame"):Count() == 0, "All camera owners clean up independently")
-- Execute the real bootstraps with no terrain/character requirement. The server
-- deliberately stops at its first unrelated service, after the safety setup.
local function character(withRoot)
	local model = instance("Model")
	model.ChildAdded = signal()
	if withRoot then
		local root = instance("Part")
		root.Name, root.Parent, root.Anchored = "HumanoidRootPart", model, false
		root.AssemblyLinearVelocity = rbx.Vector3.new(0, -100, 0)
		root.AssemblyAngularVelocity = rbx.Vector3.new(1, 2, 3)
	end
	return model
end
local function playerWithCharacter(model)
	local player = instance("Player")
	player.Character, player.CharacterAdded = model, signal()
	return player
end
local function stopped(root)
	return root.Anchored and root.AssemblyLinearVelocity == rbx.Vector3.zero
		and root.AssemblyAngularVelocity == rbx.Vector3.zero
end
local existingPlayer = playerWithCharacter(character(true))
local serverPlayers = { PlayerAdded = signal(), CharacterAutoLoads = true,
	GetPlayers = function() return { existingPlayer } end }
local ok, err = pcall(luau.load(fs.readFile("src/server/ServerBootstrap.server.luau"), { environment = {
	game = { GetService = function(_, name)
		if name == "Players" then return serverPlayers end
		error("stop after early character safety")
	end }, Vector3 = rbx.Vector3,
} }))
check(not ok and tostring(err):find("stop after early character safety"), "Server safety runs before other startup dependencies")
check(serverPlayers.CharacterAutoLoads == false, "Server disables spawning before any startup wait")
check(stopped(existingPlayer.Character:FindFirstChild("HumanoidRootPart")), "Server immediately anchors an existing falling character")
serverPlayers.PlayerAdded:Fire(existingPlayer)
check(existingPlayer.CharacterAdded:Count() == 1, "Early server setup does not bind an existing player twice")
local joiningPlayer = playerWithCharacter(nil)
serverPlayers.PlayerAdded:Fire(joiningPlayer)
local lateCharacter = character(false)
joiningPlayer.CharacterAdded:Fire(lateCharacter)
local lateRoot = instance("Part") lateRoot.Name, lateRoot.Parent = "HumanoidRootPart", lateCharacter
lateCharacter.ChildAdded:Fire(lateRoot)
check(stopped(lateRoot), "An explicitly spawned character with a late root is protected")
lateRoot:Destroy()
local replacementRoot = instance("Part") replacementRoot.Name, replacementRoot.Parent = "HumanoidRootPart", lateCharacter
lateCharacter.ChildAdded:Fire(replacementRoot)
check(stopped(replacementRoot), "A replaced root is protected without waiting for appearance loading")

function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
function methods:Clone()
	local clone = instance(self.ClassName)
	for key, value in pairs(self.props) do if key ~= "Parent" then clone[key] = value end end
	for _, child in ipairs(self.children) do child:Clone().Parent = clone end
	return clone
end
local function runClient(hasCharacter, existingScreens)
	local localPlayer = playerWithCharacter(hasCharacter and character(true) or nil)
	local gui = instance("PlayerGui") gui.Name, gui.Parent = "PlayerGui", localPlayer
	local starter = instance("StarterGui")
	for _, name in ipairs({ "Main", "GroupIntro" }) do
		local screen = instance("ScreenGui") screen.Name, screen.Parent = name, starter
		screen.Enabled, screen.ResetOnSpawn = true, true
		local authoredChild = instance("Frame") authoredChild.Name, authoredChild.Parent = "Authored", screen
		if existingScreens then screen:Clone().Parent = gui end
	end
	local oldMain = gui:FindFirstChild("Main")
	local started, waited = false, false
	local path = { WaitForChild = function(self) return self end }
	luau.load(fs.readFile("src/client/ClientBootstrap.local.luau"), { environment = {
		game = {
			GetService = function(_, name) return name == "Players" and { LocalPlayer = localPlayer } or starter end,
			IsLoaded = function() return false end,
			Loaded = { Wait = function()
				waited = true
				check(localPlayer.CharacterAdded:Count() == 1, "Client subscribes before waiting for replication")
				if hasCharacter then check(stopped(localPlayer.Character:FindFirstChild("HumanoidRootPart")), "Client stops existing motion before loading UI") end
			end },
		}, script = { Parent = path }, Vector3 = rbx.Vector3,
		require = function() return { Start = function() started = true end } end,
	} })()
	check(waited and started and #gui.children == 2, "Characterless startup mounts two authored screens then starts gameplay")
	local main, intro = gui:FindFirstChild("Main"), gui:FindFirstChild("GroupIntro")
	check(not main.Enabled and intro.Enabled and not main.ResetOnSpawn and not intro.ResetOnSpawn, "Intro precedes Main and both screens persist")
	check(main:FindFirstChild("Authored") and intro:FindFirstChild("Authored"), "Authored descendants are retained")
	check(starter:FindFirstChild("Main").Enabled and starter:FindFirstChild("Main").ResetOnSpawn, "Source templates are unchanged")
	if existingScreens then check(main == oldMain, "Already-mounted Main is reused without duplicate UI") end
	local spawned = character(false)
	localPlayer.CharacterAdded:Fire(spawned)
	local root = instance("Part") root.Name, root.Parent = "HumanoidRootPart", spawned
	spawned.ChildAdded:Fire(root)
	check(stopped(root), "Client fallback protects later manually spawned roots")
end
runClient(false, false)
runClient(true, true)

do
	local musicSound
	local audio = luau.load(fs.readFile("src/client/systems/Audio.luau"), {environment={
		game={GetService=function() return workspace end},
		Instance={new=function()
			local sound = { Ended=signal(), IsPlaying=false, playCalls=0, TimePosition=0 }
			function sound:Play() self.playCalls += 1 self.IsPlaying=true self.TimePosition=0 end
			musicSound=sound
			return sound
		end},
	}})()
	audio.SetEnabled(false)
	audio.Initialize()
	check(musicSound.playCalls == 0, "Music waits for intro/profile readiness")
	audio.SetEnabled(true)
	musicSound.TimePosition=37
	for _ = 1, 20 do audio.SetEnabled(true) end
	check(musicSound.playCalls == 1 and musicSound.TimePosition == 37, "Repeated hint/profile updates never replay or rewind music")
	audio.SetEnabled(false)
	check(musicSound.Volume == 0, "Music Off still mutes playback")
	audio.SetEnabled(true)
	check(musicSound.Volume == 0.2 and musicSound.playCalls == 1 and musicSound.TimePosition == 37, "Unmuting a playing track preserves its position")
	musicSound.IsPlaying=false
	musicSound.Ended:Fire()
	check(musicSound.playCalls == 2 and musicSound.SoundId == "rbxassetid://133244468349763", "Track end still advances the playlist")
	audio.SetEnabled(false)
	musicSound.IsPlaying=false
	musicSound.Ended:Fire()
	audio.SetEnabled(true)
	check(musicSound.playCalls == 3 and musicSound.IsPlaying, "Re-enabling music after it ended while muted restarts playback")
end

print("ENVIRONMENT_TESTS_PASSED=" .. checks)
