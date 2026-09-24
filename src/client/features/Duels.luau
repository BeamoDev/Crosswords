local Duels = {}
Duels.__index = Duels

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local Effects = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("ui"):WaitForChild("UIEffects"))

local player = Players.LocalPlayer
local Interface = require(script.Parent.Parent:WaitForChild("controllers"):WaitForChild("InterfaceController"))
local GuiUtils = Interface.Components.Gui
local DuelRemotes = require(ReplicatedStorage:WaitForChild("shared"):WaitForChild("network"):WaitForChild("NetworkContract")).Legacy.Duel
local findDescendantByNames = GuiUtils.findDescendantByNames
local findButtonLike = GuiUtils.findButtonLike
local setVisible = GuiUtils.setVisible

local function setModalVisible(metaUi, frame, visible, immediate)
	if metaUi and frame then
		metaUi:setModalFrameVisible(frame, visible, immediate == true)
	else
		setVisible(frame, visible)
	end
end

local setText = GuiUtils.setText

local function setThumbnail(imageObject, userId, suppliedImage)
	if imageObject and type(suppliedImage) == "string" and suppliedImage ~= "" then
		Effects.SetPortraitImage(imageObject, suppliedImage)
		return
	end
	if not (imageObject and type(userId) == "number" and userId > 0) then return end
	-- The URI follows the current account immediately; no stale async callback can repaint it.
	Effects.SetPortraitImage(imageObject, string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId))
	imageObject.ImageTransparency = 0
	local placeholder = imageObject:FindFirstChild("Profile")
	if placeholder and placeholder:IsA("GuiObject") then placeholder.Visible = false end
end

local function color3ToHex(color)
	local safeColor = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
	return string.format(
		"%02X%02X%02X",
		math.floor(safeColor.R * 255 + 0.5),
		math.floor(safeColor.G * 255 + 0.5),
		math.floor(safeColor.B * 255 + 0.5)
	)
end

local function escapeRichText(text)
	local safeText = tostring(text or "")
	safeText = safeText:gsub("&", "&amp;")
	safeText = safeText:gsub("<", "&lt;")
	safeText = safeText:gsub(">", "&gt;")
	return safeText
end

local function displayChatMessage(text, color)
	local safeColor = typeof(color) == "Color3" and color or Color3.fromRGB(69, 246, 255)
	local richText = string.format(
		"<font color=\"#%s\"><b>[1V1]</b> %s</font>",
		color3ToHex(safeColor),
		escapeRichText(text)
	)

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channels = TextChatService:FindFirstChild("TextChannels")
		local systemChannel = channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
		if systemChannel and systemChannel.DisplaySystemMessage then
			pcall(function()
				systemChannel:DisplaySystemMessage(richText)
			end)
			return
		end
	end

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = "[1V1] " .. tostring(text or ""),
			Color = safeColor,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
		})
	end)
end

function Duels.new(ctx)
	local self = setmetatable({}, Duels)
	self.ctx = ctx or {}
	self.outcomeResult, self.incomingChallengeId = nil, nil
	self.activeMatchId, self.resultMatchId = nil, nil
	self.root = nil
	self.metaUi = nil
	self.remotes = {}
	self.boundRemotes, self.lobbyConnectionsBound = {}, false
	self.elements = {}
	self.connections = {}
	self.requestConnections = {}
	self.resultConnections = {}
	self.outgoingChallengeTargetId = nil
	self.outgoingChallengeTargetName = nil
	self.pendingChallengeTargetId = nil
	self.pendingChallengeTargetName = nil
	self.challengeSendLockedUntil = 0
	self.challengeTargetCooldowns = {}
	self.inDuel = false
	self.lastPlayerData = nil
	self.renderedEntries = {}
	self.renderedEntryData = {}
	self.portraitPalette = Effects.NewPortraitPalette(Random.new())
	self.listRequestPending = false
	self.listGeneration = 0
	self.lobbyRefreshToken = 0
	return self
end

function Duels:disconnectConnections(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

function Duels:resolveRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local eventsFolder = remotesFolder and remotesFolder:FindFirstChild("Events") or nil
	local functionsFolder = remotesFolder and remotesFolder:FindFirstChild("Functions") or nil
	local duelFolder = eventsFolder and eventsFolder:FindFirstChild("Duel") or nil

	self.remotes.requestPlayerList = functionsFolder and functionsFolder:FindFirstChild(DuelRemotes.RequestPlayerList) or nil
	self.remotes.sendChallenge = duelFolder and duelFolder:FindFirstChild(DuelRemotes.SendChallenge) or nil
	self.remotes.respondChallenge = duelFolder and duelFolder:FindFirstChild(DuelRemotes.RespondChallenge) or nil
	self.remotes.reportProgress = duelFolder and duelFolder:FindFirstChild(DuelRemotes.ReportProgress) or nil
	self.remotes.reportCompletion = duelFolder and duelFolder:FindFirstChild(DuelRemotes.ReportCompletion) or nil
	self.remotes.abandon = duelFolder and duelFolder:FindFirstChild(DuelRemotes.Abandon) or nil
	self.remotes.challengeEvent = duelFolder and duelFolder:FindFirstChild(DuelRemotes.Challenge) or nil
	self.remotes.matchEvent = duelFolder and duelFolder:FindFirstChild(DuelRemotes.Match) or nil
	self.remotes.rematch = duelFolder and duelFolder:FindFirstChild(DuelRemotes.Rematch) or nil
	self.remotes.progressEvent = duelFolder and duelFolder:FindFirstChild(DuelRemotes.Progress) or nil
end

function Duels:resolveElements(root)
	self.root = root
	local frames = root and (root:FindFirstChild("Frames") or findDescendantByNames(root, { "Frames" }, nil)) or nil
	local requestRoot = frames and frames:FindFirstChild("DuelRequest")
	local outcomeRoot = frames and frames:FindFirstChild("DuelOutcome")
	local requestFrame, outcomeFrame = requestRoot, outcomeRoot
	local lobby = frames and frames:FindFirstChild("DuelLobby")
	local container = lobby and lobby:FindFirstChild("Container")
	self.elements.lobbyFrame = lobby
	self.elements.lobbyQuit = lobby and findButtonLike(lobby:FindFirstChild("Quit"))
	self.elements.lobbyList = container and container:FindFirstChild("ScrollingFrame")
	local assets, legacyAssets = ReplicatedStorage:FindFirstChild("assets"), ReplicatedStorage:FindFirstChild("Assets")
	self.elements.lobbyTemplate = (assets and assets:FindFirstChild("1v1Template")) or (legacyAssets and legacyAssets:FindFirstChild("1v1Template"))
	if self.elements.lobbyList then
		self.elements.lobbyList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		self.elements.lobbyList.CanvasSize = UDim2.new(0, 0, 0, 0)
	end
	self.elements.requestFrame = requestFrame
	self.elements.requestRoot = requestRoot
	self.elements.requestAccept = requestRoot and findButtonLike(requestRoot:FindFirstChild("Green"))
	self.elements.requestDecline = requestRoot and findButtonLike(requestRoot:FindFirstChild("Red"))
	self.elements.requestTitle = requestRoot and requestRoot:FindFirstChild("Title")
	self.elements.requestHandle = requestRoot and requestRoot:FindFirstChild("UserName")
	self.elements.requestMugshot = requestRoot and requestRoot:FindFirstChild("Mugshot")
	self.elements.outcomeFrame = outcomeFrame
	self.elements.rematch = outcomeRoot and findButtonLike(outcomeRoot:FindFirstChild("Rematch"))
	self.elements.outcomeReturn = outcomeRoot and findButtonLike(outcomeRoot:FindFirstChild("Home"))
	self.elements.outcomeTitle = outcomeRoot and outcomeRoot:FindFirstChild("Title")
	self.elements.winnerIcon = outcomeRoot and outcomeRoot:FindFirstChild("WinnerIcon")
	self.elements.loserIcon = outcomeRoot and outcomeRoot:FindFirstChild("LoserIcon")
	setVisible(self.elements.winnerIcon, false)
	setVisible(self.elements.loserIcon, false)

end

function Duels:updateRematch(available, count)
	local frame, button, home = self.elements.outcomeFrame, self.elements.rematch, self.elements.outcomeReturn
	if not frame then return end
	frame:SetAttribute("RematchAvailable", available == true)
	if button then
		if not available then button.Visible = false
		elseif Interface.OutcomeButtonsReady(frame) then button.Visible = true end
		setText(button:FindFirstChild("TextLabel"), string.format("Rematch (%d/2)", count or 0))
	end
	if home then home.Position = UDim2.fromScale(available and 0.764 or 0.5, 0.873) end
end

function Duels:bindResultButton()
	self:disconnectConnections(self.resultConnections)
	if self.elements.rematch then
		table.insert(self.resultConnections, self.elements.rematch.Activated:Connect(function()
			local result = self.outcomeResult
			if not result or self.rematchRequested or not Interface.OutcomeButtonsReady(self.elements.outcomeFrame)
				or self.elements.outcomeFrame:GetAttribute("RematchAvailable") ~= true or not self.remotes.rematch then return end
			self.rematchRequested = true
			self.remotes.rematch:FireServer(result.matchId)
		end))
	end
	if self.elements.outcomeReturn then
		table.insert(self.resultConnections, self.elements.outcomeReturn.Activated:Connect(function()
			local result = self.outcomeResult
			if not result or not Interface.OutcomeButtonsReady(self.elements.outcomeFrame) then return end
			if self.remotes.abandon then self.remotes.abandon:FireServer() end
			self.outcomeResult = nil
			setModalVisible(self.metaUi, self.elements.outcomeFrame, false, true)
			if self.ctx.onReturnHome then self.ctx.onReturnHome(result.matchId) end
		end))
	end
end

function Duels:respondToRequest(accept)
	if not self.incomingChallengeId or not self.remotes.respondChallenge then return end
	self.incomingChallengeId = nil
	setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
	self.remotes.respondChallenge:FireServer(accept == true)
end

function Duels:bindRequestButtons()
	self:disconnectConnections(self.requestConnections)
	for _, binding in ipairs({ {self.elements.requestAccept, true}, {self.elements.requestDecline, false} }) do
		local button, accept = binding[1], binding[2]
		if button then
			table.insert(self.requestConnections, button.Activated:Connect(function() self:respondToRequest(accept) end))
		end
	end
end

function Duels:getSelectedMode()
	return "Duel"
end

function Duels:showLobby()
	local frame = self.elements.lobbyFrame
	if not (self.metaUi and frame and self.elements.lobbyList) then return false end
	if not self.elements.lobbyTemplate then
		warn("[Duels] Missing ReplicatedStorage.assets/Assets.1v1Template")
		return false
	end
	if not frame.Visible then
		self:clearRenderedEntries()
		self.portraitPalette = Effects.NewPortraitPalette(Random.new())
	end
	if self.ctx.trackFunnelStep then self.ctx.trackFunnelStep("DuelLobbyOpened", { mode = "Duel" }) end
	self.metaUi:showFrame(frame)
	self:renderLobby(self.lastPlayerData or {})
	self:requestPlayerListUpdate(true)
	return true
end

function Duels:hideLobby()
	if self.metaUi then self.metaUi:hideFrame(self.elements.lobbyFrame)
	else setVisible(self.elements.lobbyFrame, false) end
end

function Duels:clearRenderedEntries()
	for _, entry in pairs(self.renderedEntries) do entry:Destroy() end
	self.renderedEntries, self.renderedEntryData = {}, {}
end

function Duels:requestLatestPlayerList()
	if not self.remotes.requestPlayerList then
		self:resolveRemotes()
		self:connectRemotes()
	end
	if not self.remotes.requestPlayerList then return self.lastPlayerData or {} end
	if self.listRequestPending then return nil end
	self.listRequestPending = true
	local generation = self.listGeneration
	local success, result = pcall(function() return self.remotes.requestPlayerList:InvokeServer() end)
	if generation ~= self.listGeneration then return nil end
	self.listRequestPending = false
	if success and type(result) == "table" then self.lastPlayerData = result end
	return self.lastPlayerData or {}
end

function Duels:canRequest(entryData)
	return entryData.userId ~= player.UserId and (entryData.userId > 0 or entryData.isBot == true)
		and self.remotes.sendChallenge ~= nil and self.remotes.matchEvent ~= nil
		and entryData.duelRequestsEnabled ~= false
		and not entryData.inMatch and not entryData.hasPending and not self.inDuel
		and not self.outgoingChallengeTargetId and not self.pendingChallengeTargetId
		and os.clock() >= (self.challengeTargetCooldowns[entryData.userId] or 0)
end

function Duels:renderLobby(playerData)
	local container, template = self.elements.lobbyList, self.elements.lobbyTemplate
	if not (container and template and type(playerData) == "table") then return end
	self.lastPlayerData = playerData
	local seen = {}
	for index, entryData in ipairs(playerData) do
		local userId = entryData.userId
		if type(userId) ~= "number" or (userId <= 0 and entryData.isBot ~= true) or userId == player.UserId or seen[userId] then continue end
		seen[userId] = true
		self.renderedEntryData[userId] = entryData
		local entry = self.renderedEntries[userId]
		if not entry or entry.Parent ~= container then
			if entry then entry:Destroy() end
			entry = template:Clone()
			entry.Name = "DuelPlayer_" .. tostring(userId)
			entry.Parent = container
			self.renderedEntries[userId] = entry
			local mugshot = entry:FindFirstChild("Mugshot")
			if mugshot then
				local color = self.portraitPalette.Next()
				mugshot.BackgroundColor3, mugshot.BackgroundTransparency = color, 0
				local stroke = mugshot:FindFirstChildOfClass("UIStroke")
				if not stroke then
					stroke = Instance.new("UIStroke")
					stroke.Name, stroke.Thickness, stroke.Parent = "UIStroke", 2, mugshot
				end
				stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.3)
			end
			local request = findButtonLike(entry:FindFirstChild("Request"))
			if request then
				request.Activated:Connect(function()
					local current = self.renderedEntryData[userId]
					if self.renderedEntries[userId] == entry and current then self:sendChallengeToPlayer(current) end
				end)
			end
		end
		entry.Visible, entry.LayoutOrder = true, index
		setText(entry:FindFirstChild("Username"), entryData.username or entryData.name or "Unknown")
		setThumbnail(entry:FindFirstChild("Mugshot"), userId, entryData.isBot and entryData.thumbnailImage or nil)
		local winRate = entry:FindFirstChild("WinRate")
		if winRate and winRate:IsA("TextLabel") then winRate.Text, winRate.Visible = Effects.DuelWinRateText(entryData.duel), true end
		local request = findButtonLike(entry:FindFirstChild("Request"))
		if request then
			local enabled = self:canRequest(entryData) == true
			request.Visible = entryData.duelRequestsEnabled ~= false
			request.Active, request.Selectable = enabled, enabled
		end
	end
	for userId, entry in pairs(self.renderedEntries) do
		if not seen[userId] then
			entry:Destroy()
			self.renderedEntries[userId], self.renderedEntryData[userId] = nil, nil
		end
	end
end

function Duels:requestPlayerListUpdate(forceFetch)
	local lobby = self.elements.lobbyFrame
	if not (lobby and lobby.Visible) then return end
	local playerData = forceFetch and self:requestLatestPlayerList() or self.lastPlayerData
	if playerData then self:renderLobby(playerData) end
end

function Duels:startLobbyRefreshLoop()
	self.lobbyRefreshToken += 1
	local refreshToken = self.lobbyRefreshToken

	task.spawn(function()
		while self.lobbyRefreshToken == refreshToken and self.root and self.root.Parent do
			-- Remotes can replicate after the first bind; recover even with the lobby closed.
			self:resolveRemotes()
			self:connectRemotes()
			if not self.inDuel then
				self:requestPlayerListUpdate(true)
			end
			task.wait(4)
		end
	end)
end

function Duels:sendChallengeToPlayer(playerData)
	if not (playerData and type(playerData.userId) == "number" and self.remotes.sendChallenge) then
		return
	end

	local now = os.clock()
	if self.challengeSendLockedUntil > now then
		return
	end

	local cooldownUntil = self.challengeTargetCooldowns[playerData.userId]
	if cooldownUntil and cooldownUntil > now then
		return
	end

	if not self:canRequest(playerData) then return end

	self.challengeSendLockedUntil = now + 0.35
	self.challengeTargetCooldowns[playerData.userId] = now + 8
	self.pendingChallengeTargetId = playerData.userId
	self.pendingChallengeTargetName = playerData.name or playerData.username or "that player"
	self:renderLobby(self.lastPlayerData or {})
	self.remotes.sendChallenge:FireServer(playerData.userId, self:getSelectedMode())
end

function Duels:showChallengeRequest(payload)
	if self.inDuel then return end
	self.incomingChallengeId = payload.challengerId
	if self.elements.requestFrame then
		if self.metaUi then
			self.metaUi:showFrame(self.elements.requestFrame)
		else
			setVisible(self.elements.requestFrame, true)
		end
	end

	setThumbnail(self.elements.requestMugshot, payload.challengerId)
	setText(self.elements.requestTitle, "1V1 REQUEST")
	setText(self.elements.requestHandle, "@" .. tostring(payload.challengerUsername or payload.challengerName or "Unknown"))

end

function Duels:updateOutcome(snapshot)
	local result, frame = self.outcomeResult, self.elements.outcomeFrame
	if not result or not frame then return end
	setText(self.elements.outcomeTitle, result.isDraw and "DRAW!" or result.isWinner and "YOU WON!" or "YOU LOST!")
	setVisible(self.elements.winnerIcon, result.isWinner == true)
	setVisible(self.elements.loserIcon, not result.isDraw and result.isWinner ~= true)
	setText(frame:FindFirstChild("LevelTheme"), tostring(result.theme or "Crosswords") .. " | 1v1")
	if Interface.UpdateOutcome(frame, snapshot and snapshot.progression) then return end
	setText(frame:FindFirstChild("Words"), Interface.OutcomeWords(result.foundCount or 0, result.wordCount or 0, result.duration))
	setText(frame:FindFirstChild("XPWon"), string.format("+%d XP", result.xpEarned or 0))
	local level, xp, required = Interface.UpdateProgressFill(self, frame, snapshot and snapshot.progression)
	setText(frame:FindFirstChild("CurrentXP"), string.format("Level %d | %d / %d XP", level, xp, required))
end

function Duels:showOutcome(payload)
	self.outcomeResult = payload
	self.rematchRequested = false
	local update = self.rematchUpdate
	if update and update.matchId == payload.matchId then self:updateRematch(update.available, update.count)
	else self:updateRematch(payload.rematchAvailable == true, 0) end
	if self.elements.outcomeFrame then
		local snapshot = self.ctx.getSnapshot and self.ctx.getSnapshot()
		Interface.PlayOutcome(self, self.elements.outcomeFrame, payload, snapshot and snapshot.progression)
	end
	self:updateOutcome(self.ctx.getSnapshot and self.ctx.getSnapshot())
	if self.metaUi and self.elements.outcomeFrame then
		self.metaUi:showFrame(self.elements.outcomeFrame)
	else
		setVisible(self.elements.outcomeFrame, true)
	end

	if payload.opponentQuit then
		displayChatMessage(string.format("%s won the 1v1. %s quit.", tostring(payload.winnerName or "Winner"), tostring(payload.loserName or "Loser")), Color3.fromRGB(69, 246, 255))
	else
		displayChatMessage(string.format("%s won the 1v1 against %s.", tostring(payload.winnerName or "Winner"), tostring(payload.loserName or "Loser")), Color3.fromRGB(69, 246, 255))
	end
end

function Duels:reportWordFound(word, answer)
	if self.remotes.reportProgress and self.inDuel then
		self.remotes.reportProgress:FireServer({
			word = word,
			answer = answer,
			matchId = self.activeMatchId,
		})
		return {success=true}
	end
	return nil
end

function Duels:reportCompletion()
	if self.remotes.reportCompletion and self.inDuel then
		self.remotes.reportCompletion:FireServer()
	end
end

function Duels:abandon()
	if self.remotes.abandon and (self.inDuel or self.resultMatchId) then
		self.remotes.abandon:FireServer()
	end
end

function Duels:isInDuel()
	return self.inDuel == true
end

function Duels:connectRemotes()
	self.boundRemotes = self.boundRemotes or {}
	if self.remotes.challengeEvent and not self.boundRemotes[self.remotes.challengeEvent] then
		self.boundRemotes[self.remotes.challengeEvent] = true
		table.insert(self.connections, self.remotes.challengeEvent.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local action = payload.action
			if action == "received" then
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				self:showChallengeRequest(payload)
			elseif action == "sent" then
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				self.outgoingChallengeTargetId = payload.targetId
				self.outgoingChallengeTargetName = payload.targetName or payload.targetUsername
				self:requestPlayerListUpdate(true)
			elseif action == "declined" then
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self:requestPlayerListUpdate(true)
			elseif action == "expired" then
				if payload.challengerId == self.incomingChallengeId then
					self.incomingChallengeId = nil
					setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
				end
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				self:requestPlayerListUpdate(true)
			elseif action == "error" then
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				self:requestPlayerListUpdate(true)
			end
		end))
	end

	if self.remotes.matchEvent and not self.boundRemotes[self.remotes.matchEvent] then
		self.boundRemotes[self.remotes.matchEvent] = true
		table.insert(self.connections, self.remotes.matchEvent.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local action = payload.action
			if action == "rematch" then
				if payload.matchId ~= self.activeMatchId then return end
				self.rematchUpdate = payload
				if self.outcomeResult and self.outcomeResult.matchId == payload.matchId then
					self:updateRematch(payload.available, payload.count)
				end
			elseif action == "countdown" then
				self.rematchUpdate, self.rematchRequested = nil, false
				self.activeMatchId, self.resultMatchId = payload.matchId, nil
				self.outcomeResult, self.incomingChallengeId = nil, nil
				self.inDuel = true
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
				setModalVisible(self.metaUi, self.elements.outcomeFrame, false, true)
				setModalVisible(self.metaUi, self.elements.lobbyFrame, false, true)
				if self.ctx.onCountdown then
					self.ctx.onCountdown(payload)
				end
			elseif action == "start" then
				if self.ctx.onStart then
					self.ctx.onStart(payload)
				end
			elseif action == "result" or action == "forfeit" then
				if payload.matchId ~= self.activeMatchId or self.resultMatchId == payload.matchId then return end
				self.resultMatchId = payload.matchId
				self.inDuel = false
				local handled = false
				if self.ctx.onResult then
					handled = self.ctx.onResult(payload) == true
				end
				if not handled then
					self:showOutcome(payload)
				end
			end
		end))
	end

	if self.remotes.progressEvent and not self.boundRemotes[self.remotes.progressEvent] then
		self.boundRemotes[self.remotes.progressEvent] = true
		table.insert(self.connections, self.remotes.progressEvent.OnClientEvent:Connect(function(payload)
			if self.ctx.onProgress then
				self.ctx.onProgress(payload)
			end
		end))
	end

	if self.lobbyConnectionsBound then return end
	self.lobbyConnectionsBound = true
	if self.elements.lobbyQuit then
		table.insert(self.connections, self.elements.lobbyQuit.Activated:Connect(function() self:hideLobby() end))
	end

	table.insert(self.connections, Players.PlayerAdded:Connect(function()
		task.defer(function()
			self:requestPlayerListUpdate(true)
		end)
	end))

	table.insert(self.connections, Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:requestPlayerListUpdate(true)
		end)
	end))
end

function Duels:bind(root, metaUi)
	if self.root then
		self:destroy()
	end
	self.metaUi = metaUi
	self:resolveRemotes()
	self:resolveElements(root)
	self:bindRequestButtons()
	self:bindResultButton()
	self:connectRemotes()
	self:startLobbyRefreshLoop()
	task.defer(function()
		self:requestPlayerListUpdate(true)
	end)
	return self
end

function Duels:destroy()
	Interface.CancelOutcome(self.elements.outcomeFrame)
	self.listGeneration += 1
	self.listRequestPending = false
	self.outcomeResult, self.incomingChallengeId = nil, nil
	self.activeMatchId, self.resultMatchId = nil, nil
	self.outgoingChallengeTargetId, self.pendingChallengeTargetId = nil, nil
	self.lobbyRefreshToken += 1
	self:disconnectConnections(self.connections)
	self:disconnectConnections(self.requestConnections)
	self:disconnectConnections(self.resultConnections)

	for userId, entry in pairs(self.renderedEntries) do
		if entry and entry.Parent then
			entry:Destroy()
		end
		self.renderedEntries[userId] = nil
		self.renderedEntryData[userId] = nil
	end

	self.root = nil
	self.metaUi = nil
	self.remotes = {}
	self.boundRemotes, self.lobbyConnectionsBound = {}, false
	self.elements = {}
	self.lastPlayerData = nil
	self.inDuel = false
end

return Duels
