-- Word Search Revamp server entrypoint.
-- All progression-changing actions terminate in DataService through RoundService.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local function requireChild(parent, name)
	local child = parent:WaitForChild(name, 10)
	assert(child, string.format("[WordSearch] Missing required instance %s.%s", parent:GetFullName(), name))
	return child
end

local serverFolder = script.Parent.Parent
local shared = requireChild(ReplicatedStorage, "shared")
local configFolder = requireChild(shared, "config")
local dataFolder = requireChild(serverFolder, "data")
local servicesFolder = requireChild(serverFolder, "services")
local gameplayFolder = requireChild(servicesFolder, "gameplay")
local metaFolder = requireChild(servicesFolder, "meta")
local opsFolder = requireChild(servicesFolder, "ops")
local utilsFolder = requireChild(serverFolder, "utils")

local GameConfig = require(requireChild(configFolder, "GameConfig"))
local RemoteConfig = require(requireChild(configFolder, "RemoteConfig"))
local DataService = require(requireChild(dataFolder, "DataService"))
local DailyPuzzleService = require(requireChild(metaFolder, "DailyPuzzleService"))
local PuzzleService = require(requireChild(gameplayFolder, "PuzzleService"))
local RewardService = require(requireChild(gameplayFolder, "RewardService"))
local RoundService = require(requireChild(gameplayFolder, "RoundService"))
local RateLimiter = require(requireChild(opsFolder, "RateLimiter"))
local RemoteValidator = require(requireChild(utilsFolder, "RemoteValidator"))

local function getOrCreate(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName ~= className then
		existing:Destroy()
		existing = nil
	end
	if existing then
		return existing
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

local remoteFolder = getOrCreate(ReplicatedStorage, "Folder", RemoteConfig.FolderName)
local functions = {}
for key, name in pairs(RemoteConfig.Functions) do
	functions[key] = getOrCreate(remoteFolder, "RemoteFunction", name)
end
local events = {}
for key, name in pairs(RemoteConfig.Events) do
	events[key] = getOrCreate(remoteFolder, "RemoteEvent", name)
end

local limiter = RateLimiter.new(8, 4)

RoundService.Init({
	DataService = DataService,
	PuzzleService = PuzzleService,
	RewardService = RewardService,
	DailyPuzzleService = DailyPuzzleService,
})

local function fail(code, message)
	return { success = false, code = code, message = message }
end

local function safeInvoke(label, callback)
	local packed = table.pack(xpcall(callback, debug.traceback))
	if not packed[1] then
		warn(string.format("[WordSearch/%s] %s", label, tostring(packed[2])))
		return fail("server_error", "Something went wrong. Please try again.")
	end
	return table.unpack(packed, 2, packed.n)
end

local function sendSnapshot(player, snapshot)
	if player.Parent and type(snapshot) == "table" then
		events.StateUpdated:FireClient(player, snapshot)
	end
end

local function ensureProfile(player)
	if DataService.IsReady(player) then
		return true
	end
	local loaded = DataService.LoadPlayer(player)
	return loaded == true and DataService.IsReady(player)
end

functions.GetBootstrap.OnServerInvoke = function(player)
	return safeInvoke("GetBootstrap", function()
		if not limiter:Allow(player, "GetBootstrap", 1, 3, 0.2) then
			return fail("rate_limited", "Please wait before retrying.")
		end
		if not ensureProfile(player) then
			return fail("data_unavailable", "Your data could not be loaded safely. Retry in a moment.")
		end

		return {
			success = true,
			snapshot = DataService.GetSnapshot(player),
			catalog = PuzzleService.GetCatalogSnapshot(),
			daily = DailyPuzzleService.GetPublicIdentity(),
			contentRevision = GameConfig.ContentRevision,
		}
	end)
end

functions.StartRound.OnServerInvoke = function(player, rawRequest)
	return safeInvoke("StartRound", function()
		if not limiter:Allow(player, "StartRound", 1, 2, 0.5) then
			return fail("rate_limited", "Please wait before starting another puzzle.")
		end
		local request = RemoteValidator.StartRequest(rawRequest)
		if not request then
			return fail("invalid_request", "Invalid puzzle request.")
		end
		return RoundService.Start(player, request)
	end)
end

functions.SubmitSelection.OnServerInvoke = function(player, rawRequest)
	return safeInvoke("SubmitSelection", function()
		if not limiter:Allow(player, "SubmitSelection", 1, 12, 12) then
			return fail("rate_limited", "Selection submitted too quickly.")
		end
		local request = RemoteValidator.Selection(
			rawRequest,
			GameConfig.Gameplay.MaxGridHeight,
			GameConfig.Gameplay.MaxGridWidth
		)
		if not request then
			return fail("invalid_request", "Invalid selection.")
		end
		local result = RoundService.SubmitSelection(player, request)
		if result.completed and result.snapshot then
			sendSnapshot(player, result.snapshot)
		end
		return result
	end)
end

functions.RequestHint.OnServerInvoke = function(player, rawRequest)
	return safeInvoke("RequestHint", function()
		if not limiter:Allow(player, "RequestHint", 1, 3, 1) then
			return fail("rate_limited", "Please wait before using another hint.")
		end
		local request = RemoteValidator.HintRequest(rawRequest)
		if not request then
			return fail("invalid_request", "Invalid hint request.")
		end
		local result = RoundService.RequestHint(player, request)
		if result.snapshot then
			sendSnapshot(player, result.snapshot)
		end
		return result
	end)
end

functions.SetPaused.OnServerInvoke = function(player, rawRequest)
	return safeInvoke("SetPaused", function()
		if not limiter:Allow(player, "SetPaused", 1, 3, 1) then
			return fail("rate_limited", "Pause changed too quickly.")
		end
		local request = RemoteValidator.PauseRequest(rawRequest)
		if not request then
			return fail("invalid_request", "Invalid pause request.")
		end
		return RoundService.SetPaused(player, request)
	end)
end

functions.UpdateSettings.OnServerInvoke = function(player, rawRequest)
	return safeInvoke("UpdateSettings", function()
		if not limiter:Allow(player, "UpdateSettings", 1, 5, 2) then
			return fail("rate_limited", "Settings changed too quickly.")
		end
		local request = RemoteValidator.SettingRequest(rawRequest)
		if not request then
			return fail("invalid_request", "That setting could not be changed.")
		end
		if not DataService.IsReady(player) then
			return fail("data_unavailable", "Your progress is not ready yet.")
		end
		local success, snapshotOrMessage = DataService.UpdateSetting(player, request.name, request.value)
		if not success then
			return fail("update_failed", tostring(snapshotOrMessage or "Setting update failed."))
		end
		local snapshot = type(snapshotOrMessage) == "table" and snapshotOrMessage or DataService.GetSnapshot(player)
		sendSnapshot(player, snapshot)
		return { success = true, snapshot = snapshot }
	end)
end

functions.CompleteTutorial.OnServerInvoke = function(player)
	return safeInvoke("CompleteTutorial", function()
		if not limiter:Allow(player, "CompleteTutorial", 1, 2, 0.25) then
			return fail("rate_limited", "Please wait and try again.")
		end
		if not DataService.IsReady(player) then
			return fail("data_unavailable", "Your progress is not ready yet.")
		end
		local success, snapshotOrMessage = DataService.CompleteTutorial(player)
		if not success then
			return fail("update_failed", tostring(snapshotOrMessage or "Tutorial progress was not saved."))
		end
		local snapshot = type(snapshotOrMessage) == "table" and snapshotOrMessage or DataService.GetSnapshot(player)
		sendSnapshot(player, snapshot)
		return { success = true, snapshot = snapshot }
	end)
end

events.AbandonRound.OnServerEvent:Connect(function(player, rawRequest)
	if not limiter:Allow(player, "AbandonRound", 1, 3, 1) then
		return
	end
	local request = RemoteValidator.RoundRequest(rawRequest)
	if request then
		RoundService.Abandon(player, request.roundId)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	limiter:ClearPlayer(player)
	RoundService.ClearPlayer(player)
end)

DataService.Init()

if RunService:IsStudio() then
	task.defer(function()
		local testsFolder = serverFolder:FindFirstChild("tests")
		local testModule = testsFolder and testsFolder:FindFirstChild("PuzzleEngineTests")
		if not testModule then
			warn("[WordSearch] Puzzle self-tests were not found; continuing in Studio.")
			return
		end

		local ok, result = pcall(function()
			return require(testModule).Run()
		end)
		if not ok then
			warn("[WordSearch] Puzzle self-tests failed: " .. tostring(result))
		elseif type(result) ~= "table" or result.passed ~= result.total then
			warn("[WordSearch] Puzzle self-tests returned an incomplete result.")
		else
			print(string.format("[WordSearch] Puzzle self-tests passed (%d/%d).", result.passed, result.total))
		end
	end)
end
