local TimedRewardsUI = {}

local PULSE_COLOR = Color3.fromRGB(255, 255, 255)
local PUZZLE_PIECE_TEXT = utf8.char(0x1F9E9)

local function isTextNode(node)
	return node and (node:IsA("TextLabel") or node:IsA("TextButton"))
end

local function isImageNode(node)
	return node and (node:IsA("ImageLabel") or node:IsA("ImageButton"))
end

local function resolveBool(value)
	if type(value) == "function" then
		local success, result = pcall(value)
		return success and result == true
	end

	return value == true
end

local function getTimedRewardIcon(ctx, reward)
	if not reward then
		return ""
	end
	if reward.rewardType == "hints" then
		return tostring(ctx.hintIconId or "")
	end
	return ""
end

local function getProjectedPlaytimeSeconds(ctx, nextRewardIndex, playtimeSeconds, threshold)
	local runtimeState = ctx.runtimeState
	if type(runtimeState) ~= "table" then
		runtimeState = {}
		ctx.runtimeState = runtimeState
	end

	local now = os.clock()
	local rewardKey = tostring(nextRewardIndex or "none")
	local clampedPlaytime = math.clamp(math.floor(tonumber(playtimeSeconds) or 0), 0, math.max(0, threshold))
	local baselinePlaytime = math.floor(tonumber(runtimeState.baselinePlaytimeSeconds) or -1)
	local baselineObservedAt = tonumber(runtimeState.baselineObservedAt) or now

	if runtimeState.rewardKey ~= rewardKey or clampedPlaytime ~= baselinePlaytime then
		runtimeState.rewardKey = rewardKey
		runtimeState.baselinePlaytimeSeconds = clampedPlaytime
		runtimeState.baselineObservedAt = now
		baselinePlaytime = clampedPlaytime
		baselineObservedAt = now
	end

	local elapsedSeconds = math.max(0, math.floor(now - baselineObservedAt))
	return math.min(math.max(0, threshold), baselinePlaytime + elapsedSeconds)
end

local function setTimedRewardCard(
	ctx,
	timerNode,
	rewardNode,
	primaryNode,
	secondaryNode,
	primaryLabelNode,
	secondaryLabelNode,
	descriptionNode,
	visible,
	state
)
	local reward = state and state.reward or nil
	local description = reward and ctx.timedRewardsConfig.GetRewardDescription(reward) or ""
	local icon = getTimedRewardIcon(ctx, reward)
	local isPiecesReward = reward and reward.rewardType == "pieces"

	if rewardNode and rewardNode:IsA("GuiObject") then
		rewardNode.Visible = visible == true
	end
	if isTextNode(timerNode) then
		timerNode.Visible = visible == true
	end
	if isTextNode(descriptionNode) then
		descriptionNode.Visible = visible == true
		ctx.setText(descriptionNode, description)
	end

	for _, node in ipairs({ primaryNode, secondaryNode }) do
		if isImageNode(node) then
			node.Visible = visible == true and not isPiecesReward and icon ~= ""
			node.Image = icon
		end
	end

	for _, node in ipairs({ primaryLabelNode, secondaryLabelNode }) do
		if isTextNode(node) then
			node.Visible = visible == true and isPiecesReward
			ctx.setText(node, isPiecesReward and PUZZLE_PIECE_TEXT or "")
		end
	end

	if not isTextNode(timerNode) then
		return
	end

	if not visible or not state then
		ctx.setText(timerNode, "00:00")
		return
	end

	if state.canClaim then
		ctx.setText(timerNode, "CLAIM")
		return
	end

	local total = math.max(0, math.floor(tonumber(state.remainingSeconds) or 0))
	ctx.setText(timerNode, string.format("%02d:%02d", math.floor(total / 60), total % 60))
end

local function ensurePulseStroke(ctx)
	local elements = ctx.elements
	local rewardNode = elements and elements.timedRewardsReward
	if not rewardNode then
		return nil
	end

	local stroke = rewardNode:FindFirstChild("TimedRewardsPulseStroke")
	if stroke and stroke:IsA("UIStroke") then
		return stroke
	end

	stroke = Instance.new("UIStroke")
	stroke.Name = "TimedRewardsPulseStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Enabled = false
	stroke.Color = PULSE_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = rewardNode
	return stroke
end

local function ensurePulseScale(ctx)
	local elements = ctx.elements
	local rewardNode = elements and elements.timedRewardsReward
	if not rewardNode then
		return nil
	end

	local scale = rewardNode:FindFirstChild("PulseScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end

	scale = Instance.new("UIScale")
	scale.Name = "PulseScale"
	scale.Scale = 1
	scale.Parent = rewardNode
	return scale
end

local function stopPulse(ctx)
	local pulse = ctx.pulseState
	if pulse.connection then
		pulse.connection:Disconnect()
		pulse.connection = nil
	end

	local stroke = pulse.stroke or ensurePulseStroke(ctx)
	if stroke then
		stroke.Enabled = false
		stroke.Color = PULSE_COLOR
		stroke.Transparency = 1
		stroke.Thickness = 1
	end

	local scale = pulse.scale or ensurePulseScale(ctx)
	if scale then
		scale.Scale = 1
	end
end

function TimedRewardsUI.GetFolder(ctx)
	local player = ctx.player
	local data = player and player:FindFirstChild("Data")
	return data and data:FindFirstChild("TimedRewards") or nil
end

function TimedRewardsUI.HasRemaining(ctx)
	local timedRewards = TimedRewardsUI.GetFolder(ctx)
	if not timedRewards then
		return true
	end

	for index = 1, ctx.timedRewardsConfig.GetRewardCount() do
		local rewardFlag = timedRewards:FindFirstChild(ctx.timedRewardsConfig.GetRewardValueName(index))
		if not (rewardFlag and rewardFlag.Value) then
			return true
		end
	end

	return false
end

function TimedRewardsUI.GetState(ctx)
	local timedRewards = TimedRewardsUI.GetFolder(ctx)
	if not timedRewards then
		return nil
	end

	local playtime = timedRewards:FindFirstChild("Playtime")
	local playtimeSeconds = math.max(0, math.floor(tonumber(playtime and playtime.Value) or 0))
	for index = 1, ctx.timedRewardsConfig.GetRewardCount() do
		local rewardFlag = timedRewards:FindFirstChild(ctx.timedRewardsConfig.GetRewardValueName(index))
		if not (rewardFlag and rewardFlag.Value) then
			local reward = ctx.timedRewardsConfig.GetReward(index)
			local threshold = math.max(0, math.floor(tonumber(reward and reward.playtimeSeconds) or 0))
			playtimeSeconds = math.min(playtimeSeconds, threshold)
			local displayPlaytimeSeconds = getProjectedPlaytimeSeconds(ctx, index, playtimeSeconds, threshold)
			local remainingSeconds = math.max(0, threshold - displayPlaytimeSeconds)
			return {
				allClaimed = false,
				canClaim = remainingSeconds <= 0,
				nextRewardIndex = index,
				reward = reward,
				remainingSeconds = remainingSeconds,
				displayPlaytimeSeconds = displayPlaytimeSeconds,
			}
		end
	end

	if type(ctx.runtimeState) == "table" then
		ctx.runtimeState.rewardKey = "all_claimed"
		ctx.runtimeState.baselinePlaytimeSeconds = nil
		ctx.runtimeState.baselineObservedAt = nil
	end

	return {
		allClaimed = true,
		canClaim = false,
		nextRewardIndex = nil,
		reward = nil,
		remainingSeconds = 0,
	}
end

function TimedRewardsUI.ApplyState(ctx, state)
	local elements = ctx.elements
	local show = ctx.show
	local canShowTimedRewards = resolveBool(ctx.canShowTimedRewards)
	local isMobile = resolveBool(ctx.isMobile)
	local hasRemainingRewards = state == nil or state.allClaimed ~= true
	local desktopCardVisible = canShowTimedRewards and hasRemainingRewards and not isMobile
	local mobileButtonVisible = hasRemainingRewards and isMobile
	local rootVisible = desktopCardVisible or mobileButtonVisible
	local mobileCanClaim = mobileButtonVisible and state and state.canClaim == true

	show(elements.timedRewards, rootVisible)
	show(elements.timedRewardsButton, mobileButtonVisible)
	show(elements.timedRewardsButtonAlert, mobileCanClaim)

	if not state then
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsTimer,
			elements and elements.timedRewardsReward,
			elements and elements.timedRewardsRewardPrimary,
			elements and elements.timedRewardsRewardSecondary,
			elements and elements.timedRewardsRewardPrimaryLabel,
			elements and elements.timedRewardsRewardSecondaryLabel,
			elements and elements.timedRewardsRewardDescription,
			desktopCardVisible,
			nil
		)
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsFrameTimer,
			elements and elements.timedRewardsFrameReward,
			elements and elements.timedRewardsFrameRewardPrimary,
			elements and elements.timedRewardsFrameRewardSecondary,
			elements and elements.timedRewardsFrameRewardPrimaryLabel,
			elements and elements.timedRewardsFrameRewardSecondaryLabel,
			elements and elements.timedRewardsFrameRewardDescription,
			true,
			nil
		)
		stopPulse(ctx)
		return
	end

	if state.allClaimed then
		show(elements.timedRewards, false)
		show(elements.timedRewardsButton, false)
		show(elements.timedRewardsButtonAlert, false)
		show(elements.timedRewardsFrame, false)
		setTimedRewardCard(
			ctx,
			elements and elements.timedRewardsTimer,
			elements and elements.timedRewardsReward,
			elements and elements.timedRewardsRewardPrimary,
			elements and elements.timedRewardsRewardSecondary,
			elements and elements.timedRewardsRewardPrimaryLabel,
			elements and elements.timedRewardsRewardSecondaryLabel,
			elements and elements.timedRewardsRewardDescription,
			false,
			nil
		)
		stopPulse(ctx)
		return
	end

	setTimedRewardCard(
		ctx,
		elements and elements.timedRewardsTimer,
		elements and elements.timedRewardsReward,
		elements and elements.timedRewardsRewardPrimary,
		elements and elements.timedRewardsRewardSecondary,
		elements and elements.timedRewardsRewardPrimaryLabel,
		elements and elements.timedRewardsRewardSecondaryLabel,
		elements and elements.timedRewardsRewardDescription,
		desktopCardVisible,
		state
	)
	setTimedRewardCard(
		ctx,
		elements and elements.timedRewardsFrameTimer,
		elements and elements.timedRewardsFrameReward,
		elements and elements.timedRewardsFrameRewardPrimary,
		elements and elements.timedRewardsFrameRewardSecondary,
		elements and elements.timedRewardsFrameRewardPrimaryLabel,
		elements and elements.timedRewardsFrameRewardSecondaryLabel,
		elements and elements.timedRewardsFrameRewardDescription,
		true,
		state
	)

	stopPulse(ctx)
end

function TimedRewardsUI.Setup(ctx)
	local player = ctx.player
	local timedRewardsConfig = ctx.timedRewardsConfig
	local dataConnections = ctx.dataConnections

	ctx.disconnectAll(dataConnections)

	local function bindTimedRewardsFolder(timedRewardsFolder)
		if not timedRewardsFolder then
			return
		end

		local playtime = timedRewardsFolder:FindFirstChild("Playtime")
		if playtime then
			table.insert(dataConnections, playtime:GetPropertyChangedSignal("Value"):Connect(function()
				ctx.onUpdate()
			end))
		end

		for index = 1, timedRewardsConfig.GetRewardCount() do
			local rewardFlag = timedRewardsFolder:FindFirstChild(timedRewardsConfig.GetRewardValueName(index))
			if rewardFlag then
				table.insert(dataConnections, rewardFlag:GetPropertyChangedSignal("Value"):Connect(function()
					ctx.onUpdate()
				end))
			end
		end

		ctx.onUpdate()
	end

	local function bindData(data)
		local timedRewardsFolder = data:FindFirstChild("TimedRewards")
		if timedRewardsFolder then
			bindTimedRewardsFolder(timedRewardsFolder)
		end
		table.insert(dataConnections, data.ChildAdded:Connect(function(child)
			if child.Name == "TimedRewards" then
				bindTimedRewardsFolder(child)
			end
		end))
		ctx.onUpdate()
	end

	local data = player:FindFirstChild("Data")
	if data then
		bindData(data)
	else
		table.insert(dataConnections, player.ChildAdded:Connect(function(child)
			if child.Name == "Data" then
				bindData(child)
			end
		end))
	end
end

function TimedRewardsUI.Claim(ctx)
	if not ctx.claimTimedRewardRemote then
		return
	end

	local result
	local success, errorMessage = pcall(function()
		result = ctx.claimTimedRewardRemote:InvokeServer()
	end)

	if not success then
		ctx.showAlert("Timed Rewards", tostring(errorMessage), false, nil, nil, "error")
		return
	end

	if type(result) == "table" and result.snapshot and ctx.applySnapshot then
		ctx.applySnapshot(result.snapshot)
	end

	if type(result) == "table" and result.success then
		TimedRewardsUI.ApplyState(ctx, result.state)
		local rewardText = ctx.timedRewardsConfig.GetRewardDescription({
			rewardType = result.rewardType,
			amount = result.rewardAmount,
		})
		ctx.showAlert("Reward Claimed", rewardText, false, nil, nil, "reward")
	elseif type(result) == "table" and result.message then
		TimedRewardsUI.ApplyState(ctx, result.state or TimedRewardsUI.GetState(ctx))
		ctx.showAlert("Timed Rewards", result.message, false, nil, nil, "info")
	else
		ctx.onUpdate()
	end
end

return TimedRewardsUI
