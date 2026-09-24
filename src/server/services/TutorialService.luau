local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local shared = ReplicatedStorage:WaitForChild("shared")
local Generator = require(shared.puzzle.PuzzleGenerator)
local GameConfig = require(shared.config.GameConfig)
local Score = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("config"):WaitForChild("ProgressionConfig")).Score
local Workspace = game:GetService("Workspace")
local Contract = require(shared.network.NetworkContract)
local DataService = require(script.Parent.Parent.data.DataService)
local QueueState = require(script.Parent.QueueState)
local TutorialService = {}
local sessions, rates, savedCompletions = {}, {}, {}
local actions = { Sync = true, Start = true, Word = true, Hint = true, Complete = true, Skip = true }

local function handle(player, payload)
	if type(payload) ~= "table" or not Contract.IsBoundedValue(payload) or not actions[payload.action] then
		return { success = false }
	end
	if player:GetAttribute("ProfileReady") ~= true then return { success = false } end
	local action = payload.action
	local userRates = rates[player.UserId] or {}
	rates[player.UserId] = userRates
	local now = os.clock()
	local finishing = action == "Skip" or action == "Complete"
	local bucket = finishing and "Finish" or action
	if now - (userRates[bucket] or -math.huge) < (finishing and 1 or 0.15) then return { success = false } end
	userRates[bucket] = now
	local tutorialPending = DataService.IsTutorialPending(player)
	local round = sessions[player.UserId]
	if round then round:Expire(Workspace:GetServerTimeNow()) end
	if finishing then
		if savedCompletions[player.UserId] then
			return { success = true, saved = true, snapshot = DataService.GetSnapshot(player) }
		end
		if action == "Complete" and tutorialPending then
			if not round or payload.roundId ~= round.id or not round.members[player.UserId].completed then
				return { success = false, message = "Find all practice words first." }
			end
		end
		local saved = DataService.CompleteTutorial(player, action == "Skip")
		if saved then savedCompletions[player.UserId] = true end
		sessions[player.UserId] = nil
		return { success = true, saved = saved, snapshot = DataService.GetSnapshot(player) }
	end
	if not tutorialPending then return { success = true, completed = true, snapshot = DataService.GetSnapshot(player) } end
	if player:GetAttribute("RoundBusy") or player:GetAttribute("DuelBusy") then return { success = false } end
	if action == "Start" then
		if not round or round.members[player.UserId].timedOut then
			-- Practice fills a 3x3 grid with CAT, DOG and FOX; either direction is valid.
			local seed = 1739
			local puzzle = Generator.Generate(Generator.BuildTutorialDefinition(seed), seed)
			puzzle.title = "Animals"
			round = QueueState.NewRound(HttpService:GenerateGUID(false), puzzle, {
				{ userId = player.UserId, name = player.Name, displayName = player.DisplayName },
			})
			round:SetTimer(Workspace:GetServerTimeNow(), GameConfig.RoundSeconds.Tutorial)
			sessions[player.UserId] = round
		end
		return { success = true, round = round:Snapshot(true) }
	end
	if not round or payload.roundId ~= round.id then return { success = false } end
	if action == "Sync" then return {success=true, round=round:Snapshot(false)} end
	local accepted = false
	if action == "Word" then
		accepted = round:FindWord(player.UserId, payload.word, payload.path)
	elseif action == "Hint" then
		local word = round:NextHint(player.UserId)
		if word then round:MarkHint(player.UserId, word) accepted = true end
	end
	if accepted and round.members[player.UserId].completed then
		local member = round.members[player.UserId]
		member.duration = round.timeLimit - math.max(0, round.expiresAt - Workspace:GetServerTimeNow())
		member.score += Score.Completion(member.duration, round.timeLimit)
	end
	-- Practice never spends inventory, records wins, or awards XP/currency.
	return { success = accepted, round = round:Snapshot(false) }
end

function TutorialService.Init(remote)
	remote.OnServerInvoke = handle
	Players.PlayerRemoving:Connect(function(player)
		sessions[player.UserId], rates[player.UserId], savedCompletions[player.UserId] = nil, nil, nil
	end)
end

return TutorialService
