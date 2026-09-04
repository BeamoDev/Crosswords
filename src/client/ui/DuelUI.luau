local DuelUI = {}
DuelUI.__index = DuelUI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local GuiUtils = require(script.Parent:WaitForChild("GuiUtils"))
local findDescendantByNames = GuiUtils.findDescendantByNames
local findFirstPath = GuiUtils.findFirstPath
local findButtonLike = GuiUtils.findButtonLike
local findTextObject = GuiUtils.findTextObject
local findImageObject = GuiUtils.findImageObject
local setVisible = GuiUtils.setVisible

local function setModalVisible(metaUi, frame, visible, immediate)
	if metaUi and frame then
		metaUi:setModalFrameVisible(frame, visible, immediate == true)
	else
		setVisible(frame, visible)
	end
end

local setText = GuiUtils.setText

local function setThumbnail(imageObject, userId)
	if not (imageObject and type(userId) == "number") then
		return
	end

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if success and imageObject.Parent then
			imageObject.Image = content
		end
	end)
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

local function ensureListLayout(container)
	if not (container and container:IsA("GuiObject")) then
		return nil
	end

	local layout = container:FindFirstChildWhichIsA("UIListLayout")
	if layout then
		return layout
	end

	layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container
	return layout
end

local function setVisibleRecursive(root, visible)
	if not root then
		return
	end

	if root:IsA("GuiObject") then
		root.Visible = visible
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.Visible = visible
		end
	end
end

function DuelUI.new(ctx)
	local self = setmetatable({}, DuelUI)
	self.ctx = ctx or {}
	self.root = nil
	self.metaUi = nil
	self.remotes = {}
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
	self.lastRenderedFingerprint = nil
	self.renderedEntries = {}
	self.renderedEntryData = {}
	self.lobbyRefreshToken = 0
	return self
end

function DuelUI:disconnectConnections(list)
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

function DuelUI:resolveRemotes()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local eventsFolder = remotesFolder and remotesFolder:FindFirstChild("Events") or nil
	local functionsFolder = remotesFolder and remotesFolder:FindFirstChild("Functions") or nil
	local duelFolder = eventsFolder and eventsFolder:FindFirstChild("Duel") or nil

	self.remotes.requestPlayerList = functionsFolder and functionsFolder:FindFirstChild("RequestPlayerList") or nil
	self.remotes.sendChallenge = duelFolder and duelFolder:FindFirstChild("SendChallenge") or nil
	self.remotes.respondChallenge = duelFolder and duelFolder:FindFirstChild("RespondChallenge") or nil
	self.remotes.reportProgress = duelFolder and duelFolder:FindFirstChild("ReportDuelProgress") or nil
	self.remotes.reportCompletion = duelFolder and duelFolder:FindFirstChild("ReportDuelCompletion") or nil
	self.remotes.abandon = duelFolder and duelFolder:FindFirstChild("AbandonDuel") or nil
	self.remotes.challengeEvent = duelFolder and duelFolder:FindFirstChild("DuelChallenge") or nil
	self.remotes.matchEvent = duelFolder and duelFolder:FindFirstChild("DuelMatch") or nil
	self.remotes.progressEvent = duelFolder and duelFolder:FindFirstChild("DuelProgress") or nil
end

function DuelUI:resolveElements(root)
	self.root = root
	local frames = root and (root:FindFirstChild("Frames") or findDescendantByNames(root, { "Frames" }, nil)) or nil
	local customFrame = frames and (frames:FindFirstChild("CustomFrame") or findDescendantByNames(frames, { "CustomFrame" }, nil)) or nil
	local customRoot = customFrame and (customFrame:FindFirstChild("Frame") or findDescendantByNames(customFrame, { "Frame" }, nil)) or customFrame
	local requestFrame = frames and (frames:FindFirstChild("DuelRequest") or findDescendantByNames(frames, { "DuelRequest" }, nil)) or nil
	local requestRoot = requestFrame and (requestFrame:FindFirstChild("Frame") or findDescendantByNames(requestFrame, { "Frame" }, nil)) or requestFrame
	local outcomeFrame = frames and (frames:FindFirstChild("DuelOutcome") or findDescendantByNames(frames, { "DuelOutcome" }, nil)) or nil
	local outcomeRoot = outcomeFrame and (outcomeFrame:FindFirstChild("Frame") or findDescendantByNames(outcomeFrame, { "Frame" }, nil)) or outcomeFrame

	self.elements.customFrame = customFrame
	self.elements.customRoot = customRoot
	self.elements.customFrameQuit = findButtonLike(findFirstPath(customFrame, {
		{ "Frame", "Quit", "Button" },
		{ "Frame", "Quit" },
		{ "Quit", "Button" },
		{ "Quit" },
	}, nil) or nil)
		or findButtonLike(customFrame and findDescendantByNames(customFrame, { "Quit" }, nil) or nil)
	do
		local closeButtons = {}
		local function addCloseButton(button)
			if not (button and button:IsA("GuiButton")) then
				return
			end

			for _, existing in ipairs(closeButtons) do
				if existing == button then
					return
				end
			end

			table.insert(closeButtons, button)
		end

		addCloseButton(self.elements.customFrameQuit)
		if #closeButtons <= 0 then
			addCloseButton(findButtonLike(findFirstPath(customFrame, {
				{ "Frame", "Back", "Button" },
				{ "Frame", "Exit", "Button" },
				{ "Frame", "Close", "Button" },
				{ "Frame", "Buttons", "Green", "Button" },
				{ "Frame", "Green", "Button" },
				{ "Buttons", "Green", "Button" },
				{ "Green", "Button" },
				{ "Frame", "Back" },
				{ "Frame", "Exit" },
				{ "Frame", "Close" },
				{ "Frame", "Buttons", "Green" },
				{ "Frame", "Green" },
				{ "Buttons", "Green" },
				{ "Green" },
			}, nil) or nil))
			addCloseButton(findButtonLike(customFrame and findDescendantByNames(customFrame, { "Back", "Exit", "Close", "Green" }, nil) or nil))
			addCloseButton(findButtonLike(customRoot and findDescendantByNames(customRoot, { "Back", "Exit", "Close", "Green" }, nil) or nil))
		end

		self.elements.customFrameCloseButtons = closeButtons
		self.elements.customFrameClose = closeButtons[1]
	end
	self.elements.customDuelList = customRoot and findDescendantByNames(customRoot, { "DuelList" }, nil) or nil
	self.elements.customDuelSample = customRoot and findDescendantByNames(customRoot, { "DuelSample" }, nil) or nil
	self.elements.customDuelRequest = customRoot and findDescendantByNames(customRoot, { "DuelRequest" }, nil) or nil
	self.elements.customDuelRequestMugshot = findImageObject(self.elements.customDuelRequest, { "FrameMugshot", "Mugshot", "PImage", "Avatar", "Icon" })
	self.elements.customDuelRequestHandle = (self.elements.customDuelRequest and (
		findDescendantByNames(self.elements.customDuelRequest, { "UserName" }, "TextLabel")
			or findDescendantByNames(self.elements.customDuelRequest, { "UserName" }, "TextButton")
			or findDescendantByNames(self.elements.customDuelRequest, { "Username" }, "TextLabel")
			or findDescendantByNames(self.elements.customDuelRequest, { "Username" }, "TextButton")
	)) or findTextObject(self.elements.customDuelRequest, { "Handle" })
	self.elements.customDuelRequestSolves = findTextObject(self.elements.customDuelRequest, { "Solves" })
	self.elements.requestFrame = requestFrame
	self.elements.requestRoot = requestRoot
	self.elements.requestAccept = findButtonLike(findDescendantByNames(requestRoot, { "Green", "Accept" }, nil))
	self.elements.requestDecline = findButtonLike(findDescendantByNames(requestRoot, { "Red", "Decline" }, nil))
	self.elements.requestName = findTextObject(requestRoot, { "PlayerName", "PName", "Name" })
	self.elements.requestHandle = (requestRoot and (
		findDescendantByNames(requestRoot, { "UserName" }, "TextLabel")
			or findDescendantByNames(requestRoot, { "UserName" }, "TextButton")
			or findDescendantByNames(requestRoot, { "Username" }, "TextLabel")
			or findDescendantByNames(requestRoot, { "Username" }, "TextButton")
	)) or findTextObject(requestRoot, { "Handle" })
	self.elements.requestSolves = findTextObject(requestRoot, { "Solves" })
	self.elements.requestMugshot = findImageObject(requestRoot, { "FrameMugshot", "Mugshot", "PImage", "Avatar", "Icon" })
	self.elements.outcomeFrame = outcomeFrame
	self.elements.outcomeRoot = outcomeRoot
	self.elements.outcomeReturn = findButtonLike(findDescendantByNames(outcomeRoot, { "Green", "Return", "Home", "Continue" }, nil))
	self.elements.outcomeText = findTextObject(outcomeRoot, { "Outcome" })
	self.elements.outcomeXP = findTextObject(outcomeRoot, { "XP", "XPAmount" })

	ensureListLayout(self.elements.customDuelList)
	if self.elements.customDuelSample then
		self.elements.customDuelSample.Visible = false
	end
	if self.elements.customFrameQuit and self.elements.customFrameQuit:IsA("GuiObject") then
		self.elements.customFrameQuit.Visible = false
	end
end

function DuelUI:bindResultButton()
	self:disconnectConnections(self.resultConnections)

	if self.elements.outcomeReturn then
		table.insert(self.resultConnections, self.elements.outcomeReturn.Activated:Connect(function()
			setText(self.elements.outcomeReturn, "HOME")
			setModalVisible(self.metaUi, self.elements.outcomeFrame, false, true)
			if self.ctx.onReturnHome then
				self.ctx.onReturnHome()
			end
		end))
	end
end

function DuelUI:bindRequestButtons()
	self:disconnectConnections(self.requestConnections)

	if self.elements.requestAccept then
		table.insert(self.requestConnections, self.elements.requestAccept.Activated:Connect(function()
			setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
			if self.remotes.respondChallenge then
				self.remotes.respondChallenge:FireServer(true)
			end
		end))
	end

	if self.elements.requestDecline then
		table.insert(self.requestConnections, self.elements.requestDecline.Activated:Connect(function()
			setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
			if self.remotes.respondChallenge then
				self.remotes.respondChallenge:FireServer(false)
			end
		end))
	end
end

function DuelUI:getSelectedMode()
	local requestedMode = self.ctx.getSelectedMode and self.ctx.getSelectedMode() or "Classic"
	if requestedMode == "Freeplay" then
		return "Freeplay"
	end
	return "Classic"
end

function DuelUI:showLobby()
	if not (self.metaUi and self.elements.customFrame and self.elements.customDuelList) then
		return false
	end

	if self.ctx.trackFunnelStep then
		self.ctx.trackFunnelStep("DuelLobbyOpened", {
			mode = self:getSelectedMode(),
		})
	end

	self.metaUi:showCustomPrompt({
		title = "1V1",
		showTitle = true,
		showSub = false,
		duelList = true,
		green = {
			visible = false,
		},
		red = {
			visible = false,
		},
	})
	if self.elements.customFrameQuit and self.elements.customFrameQuit:IsA("GuiObject") then
		self.elements.customFrameQuit.Visible = true
	end

	if self.elements.customDuelList and self.elements.customDuelList:IsA("GuiObject") then
		self.elements.customDuelList.Visible = true
	end
	if self.elements.customDuelSample and self.elements.customDuelSample:IsA("GuiObject") then
		self.elements.customDuelSample.Visible = false
	end
	self:restoreRenderedEntries(self.lastPlayerData or {})
	self.lastRenderedFingerprint = nil
	self:requestPlayerListUpdate(true)

	return true
end

function DuelUI:hideLobby()
	if self.elements.customFrameQuit and self.elements.customFrameQuit:IsA("GuiObject") then
		self.elements.customFrameQuit.Visible = false
	end
	if self.metaUi then
		self.metaUi:hideFrame(self.elements.customFrame)
	else
		setVisible(self.elements.customFrame, false)
	end
end

function DuelUI:clearRenderedEntries()
	local container = self.elements.customDuelList
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child ~= self.elements.customDuelSample and child:GetAttribute("WordSearchDuelEntry") == true then
			child:Destroy()
		end
	end
	self.renderedEntries = {}
	self.renderedEntryData = {}
end

function DuelUI:buildPlayerFingerprint(playerData)
	if type(playerData) ~= "table" or #playerData == 0 then
		return "empty"
	end

	local parts = {}
	for _, entry in ipairs(playerData) do
		table.insert(parts, string.format(
			"%s:%s:%s",
			tostring(entry.userId),
			tostring(entry.inMatch == true),
			tostring(entry.hasPending == true)
		))
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

function DuelUI:requestLatestPlayerList()
	if not self.remotes.requestPlayerList then
		return {}
	end

	local success, result = pcall(function()
		return self.remotes.requestPlayerList:InvokeServer()
	end)
	if success and type(result) == "table" then
		self.lastPlayerData = result
		return result
	end

	return self.lastPlayerData or {}
end

function DuelUI:styleSampleButton(button, playerData)
	if not (button and button:IsA("GuiButton")) then
		return
	end

	local enabled = not playerData.inMatch and not playerData.hasPending and self.outgoingChallengeTargetId == nil
	button.Active = enabled
	button.Selectable = enabled

	local cooldownState = findDescendantByNames(button, { "Cooldown" }, "GuiObject")
	local inDuelState = findDescendantByNames(button, { "InDuel" }, "GuiObject")
	local unavailableState = findDescendantByNames(button, { "Unavailable", "InvitesOff" }, "GuiObject")

	setVisible(cooldownState, false)
	setVisible(inDuelState, false)
	setVisible(unavailableState, false)

	local stroke = button:FindFirstChildWhichIsA("UIStroke", true)
	if stroke then
		stroke.Enabled = false
		stroke.Transparency = 1
		if button:GetAttribute("DuelHoverBound") ~= true then
			button:SetAttribute("DuelHoverBound", true)
			button.MouseEnter:Connect(function()
				if button.Active then
					stroke.Enabled = true
					TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Transparency = 0,
					}):Play()
				end
			end)
			button.MouseLeave:Connect(function()
				stroke.Enabled = false
				stroke.Transparency = 1
			end)
		end
	end
end

function DuelUI:getOrCreatePlayerEntry(entryData, layoutOrder)
	local container = self.elements.customDuelList
	local template = self.elements.customDuelSample
	if not (container and type(entryData) == "table" and type(entryData.userId) == "number") then
		return nil
	end

	local entry = self.renderedEntries[entryData.userId]
	if entry and entry.Parent ~= container then
		entry = nil
	end

	if not entry then
		entry = template and template:Clone() or Instance.new("Frame")
		entry.Name = tostring(entryData.username or entryData.name or ("Player_" .. tostring(entryData.userId)))
		entry:SetAttribute("WordSearchDuelEntry", true)
		entry.Parent = container
		self.renderedEntries[entryData.userId] = entry

		local rowButton = if entry:IsA("GuiButton")
			then entry
			else findButtonLike(entry)
		if rowButton then
			rowButton:SetAttribute("DuelUserId", entryData.userId)
			rowButton.Activated:Connect(function()
				local latestEntryData = self.renderedEntryData[entryData.userId]
				if latestEntryData then
					self:sendChallengeToPlayer(latestEntryData)
				end
			end)
		end
	end

	if entry:IsA("GuiObject") then
		entry.Visible = true
	end
	setVisibleRecursive(entry, true)
	entry.LayoutOrder = layoutOrder
	return entry
end

function DuelUI:applyRenderedEntryState(entry, entryData, layoutOrder)
	if not (entry and entry.Parent and type(entryData) == "table") then
		return
	end

	if entry:IsA("GuiObject") then
		entry.Visible = true
	end
	setVisibleRecursive(entry, true)
	entry.LayoutOrder = layoutOrder

	local rowButton = if entry:IsA("GuiButton")
		then entry
		else findButtonLike(entry)
	local mugshot = findImageObject(entry, { "PImage", "Mugshot", "Icon", "Avatar" })
	local primaryName = findTextObject(entry, { "PName", "PlayerName", "Name", "DisplayName" })
	local username = findTextObject(entry, { "Username", "Handle" })
	local solves = findTextObject(entry, { "Solves" })
	local displayName = tostring(entryData.username or entryData.name or "Unknown")
	entry.Name = displayName

	setText(primaryName, displayName)
	if username and username ~= primaryName then
		setText(username, displayName)
		if username:IsA("GuiObject") then
			username.Visible = true
		end
	end
	setText(solves, self.ctx.getSolvesText and self.ctx.getSolvesText(entryData.userId) or "Wins: --")
	setThumbnail(mugshot, entryData.userId)
	if primaryName and primaryName:IsA("GuiObject") then
		primaryName.Visible = true
	end
	if solves and solves:IsA("GuiObject") then
		solves.Visible = true
	end
	if mugshot and mugshot:IsA("GuiObject") then
		mugshot.Visible = true
	end

	if rowButton then
		self:styleSampleButton(rowButton, entryData)
	end
end

function DuelUI:restoreRenderedEntries(playerData)
	local container = self.elements.customDuelList
	if not (container and type(playerData) == "table") then
		return
	end

	if container:IsA("GuiObject") then
		container.Visible = true
	end
	if self.elements.customDuelSample and self.elements.customDuelSample:IsA("GuiObject") then
		self.elements.customDuelSample.Visible = false
	end

	for index, entryData in ipairs(playerData) do
		local entry = self.renderedEntries[entryData.userId]
		if entry and entry.Parent == container then
			self:applyRenderedEntryState(entry, entryData, index)
		end
	end
end

function DuelUI:renderCustomList(playerData)
	local container = self.elements.customDuelList
	if not container then
		return
	end

	local nextFingerprint = self:buildPlayerFingerprint(playerData)
	if nextFingerprint == self.lastRenderedFingerprint then
		self:restoreRenderedEntries(playerData)
		return
	end
	self.lastRenderedFingerprint = nextFingerprint

	if type(playerData) ~= "table" or #playerData == 0 then
		self:clearRenderedEntries()
		return
	end

	local seenUserIds = {}

	for index, entryData in ipairs(playerData) do
		seenUserIds[entryData.userId] = true
		self.renderedEntryData[entryData.userId] = entryData
		local entry = self:getOrCreatePlayerEntry(entryData, index)
		if not entry then
			continue
		end

		self:applyRenderedEntryState(entry, entryData, index)
	end

	for userId, entry in pairs(self.renderedEntries) do
		if not seenUserIds[userId] then
			if entry and entry.Parent then
				entry:Destroy()
			end
			self.renderedEntries[userId] = nil
			self.renderedEntryData[userId] = nil
		end
	end
end

function DuelUI:requestPlayerListUpdate(forceFetch)
	local playerData = forceFetch and self:requestLatestPlayerList() or (self.lastPlayerData or self:requestLatestPlayerList())
	self:renderCustomList(playerData)
end

function DuelUI:startLobbyRefreshLoop()
	self.lobbyRefreshToken += 1
	local refreshToken = self.lobbyRefreshToken

	task.spawn(function()
		while self.lobbyRefreshToken == refreshToken and self.root and self.root.Parent do
			if not self.inDuel then
				self:requestPlayerListUpdate(true)
			end
			task.wait(4)
		end
	end)
end

function DuelUI:sendChallengeToPlayer(playerData)
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

	if self.outgoingChallengeTargetId then
		return
	end

	self.challengeSendLockedUntil = now + 0.35
	self.challengeTargetCooldowns[playerData.userId] = now + 8
	self.pendingChallengeTargetId = playerData.userId
	self.pendingChallengeTargetName = playerData.name or playerData.username or "that player"
	self.remotes.sendChallenge:FireServer(playerData.userId, self:getSelectedMode())
end

function DuelUI:showChallengeRequest(payload)
	if self.elements.requestFrame then
		if self.metaUi then
			self.metaUi:showFrame(self.elements.requestFrame)
		else
			setVisible(self.elements.requestFrame, true)
		end
	elseif self.metaUi and self.elements.customFrame then
		self.metaUi:showCustomPrompt({
			title = "1V1 REQUEST",
			showTitle = true,
			showSub = false,
			duelRequest = true,
			green = {
				visible = true,
				label = "ACCEPT",
				onClick = function()
					setModalVisible(self.metaUi, self.elements.customFrame, false, true)
					if self.remotes.respondChallenge then
						self.remotes.respondChallenge:FireServer(true)
					end
				end,
			},
			red = {
				visible = true,
				label = "DECLINE",
				onClick = function()
					setModalVisible(self.metaUi, self.elements.customFrame, false, true)
					if self.remotes.respondChallenge then
						self.remotes.respondChallenge:FireServer(false)
					end
				end,
			},
		})
		if self.elements.customFrameQuit and self.elements.customFrameQuit:IsA("GuiObject") then
			self.elements.customFrameQuit.Visible = false
		end
		setVisible(self.elements.customDuelRequest, true)
	end

	setThumbnail(self.elements.requestMugshot, payload.challengerId)
	setText(self.elements.requestName, payload.challengerName or payload.challengerUsername or "Unknown")
	setText(self.elements.requestHandle, tostring(payload.challengerUsername or "unknown"))
	setText(self.elements.requestSolves, self.ctx.getSolvesText and self.ctx.getSolvesText(payload.challengerId) or "Wins: --")
	setThumbnail(self.elements.customDuelRequestMugshot, payload.challengerId)
	setText(self.elements.customDuelRequestHandle, tostring(payload.challengerUsername or "unknown"))
	setText(self.elements.customDuelRequestSolves, self.ctx.getSolvesText and self.ctx.getSolvesText(payload.challengerId) or "Wins: --")
end

function DuelUI:showOutcome(payload)
	if self.metaUi and self.elements.outcomeFrame then
		self.metaUi:showFrame(self.elements.outcomeFrame)
	else
		setVisible(self.elements.outcomeFrame, true)
	end

	setText(self.elements.outcomeReturn, "HOME")

	if payload.isWinner then
		setText(self.elements.outcomeText, "YOU WON")
	elseif payload.youQuit then
		setText(self.elements.outcomeText, "YOU QUIT")
	else
		setText(self.elements.outcomeText, "YOU LOST")
	end
	if self.elements.outcomeText and (self.elements.outcomeText:IsA("TextLabel") or self.elements.outcomeText:IsA("TextButton")) then
		self.elements.outcomeText.TextColor3 = payload.isWinner and Color3.fromRGB(94, 194, 40) or Color3.fromRGB(255, 102, 102)
	end
	setVisible(self.elements.outcomeXP, false)
	setVisible(self.elements.outcomeXP and self.elements.outcomeXP.Parent, false)

	if payload.opponentQuit then
		displayChatMessage(string.format("%s won the 1v1. %s quit.", tostring(payload.winnerName or "Winner"), tostring(payload.loserName or "Loser")), Color3.fromRGB(69, 246, 255))
	else
		displayChatMessage(string.format("%s won the 1v1 against %s.", tostring(payload.winnerName or "Winner"), tostring(payload.loserName or "Loser")), Color3.fromRGB(69, 246, 255))
	end
end

function DuelUI:reportWordFound(word, progress, path)
	if self.remotes.reportProgress and self.inDuel then
		self.remotes.reportProgress:FireServer({
			word = word,
			progress = progress,
			path = path,
		})
	end
end

function DuelUI:reportCompletion()
	if self.remotes.reportCompletion and self.inDuel then
		self.remotes.reportCompletion:FireServer()
	end
end

function DuelUI:abandon()
	if self.remotes.abandon and self.inDuel then
		self.remotes.abandon:FireServer()
	end
end

function DuelUI:isInDuel()
	return self.inDuel == true
end

function DuelUI:connectRemotes()
	if self.remotes.challengeEvent then
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

	if self.remotes.matchEvent then
		table.insert(self.connections, self.remotes.matchEvent.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local action = payload.action
			if action == "countdown" then
				self.inDuel = true
				self.outgoingChallengeTargetId = nil
				self.outgoingChallengeTargetName = nil
				self.pendingChallengeTargetId = nil
				self.pendingChallengeTargetName = nil
				setModalVisible(self.metaUi, self.elements.requestFrame, false, true)
				setModalVisible(self.metaUi, self.elements.outcomeFrame, false, true)
				setModalVisible(self.metaUi, self.elements.customFrame, false, true)
				if self.ctx.onCountdown then
					self.ctx.onCountdown(payload)
				end
			elseif action == "start" then
				if self.ctx.onStart then
					self.ctx.onStart(payload)
				end
			elseif action == "result" or action == "forfeit" then
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

	if self.remotes.progressEvent then
		table.insert(self.connections, self.remotes.progressEvent.OnClientEvent:Connect(function(payload)
			if self.ctx.onProgress then
				self.ctx.onProgress(payload)
			end
		end))
	end

	for _, closeButton in ipairs(self.elements.customFrameCloseButtons or {}) do
		table.insert(self.connections, closeButton.Activated:Connect(function()
			self:hideLobby()
		end))
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

function DuelUI:bind(root, metaUi)
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

return DuelUI
