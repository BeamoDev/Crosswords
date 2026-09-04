local module = {}
local LEVEL_CARD_VISUALS = {
	locked = {
		cardColor = Color3.fromRGB(46, 46, 46),
		textColor = Color3.fromRGB(232, 232, 232),
	},
	playable = {
		cardColor = Color3.fromRGB(78, 176, 92),
		textColor = Color3.fromRGB(255, 255, 255),
	},
	completed = {
		cardColor = Color3.fromRGB(38, 112, 52),
		textColor = Color3.fromRGB(255, 255, 255),
	},
}

local function applyBranchBackgroundColor(root, color)
	if not root then
		return
	end

	if root:IsA("GuiObject") then
		root.BackgroundColor3 = color
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.BackgroundColor3 = color
		end
	end
end

function module.getClassicLevelStarCount(state, Dependencies, levelNumber)
	local resolvedLevel = math.clamp(math.floor(tonumber(levelNumber) or 1), 1, #Dependencies.Levels)
	local slot = Dependencies.StarRules.ResolveSlot("Classic", resolvedLevel)
	local modeBucket = type(state.starProgress[slot.mode]) == "table" and state.starProgress[slot.mode] or nil
	local packBucket = modeBucket and type(modeBucket[slot.pack]) == "table" and modeBucket[slot.pack] or nil
	return math.clamp(math.floor(tonumber(packBucket and packBucket[slot.entry]) or 0), 0, 3)
end

function module.getHighestReachedClassicLevel(state, Dependencies)
	local savedClassicLevel = math.max(1, math.floor(tonumber(state.savedClassicLevel) or 1))
	local highestStarredLevel = 0

	for levelNumber = 1, #Dependencies.Levels do
		if module.getClassicLevelStarCount(state, Dependencies, levelNumber) > 0 then
			highestStarredLevel = levelNumber
		end
	end

	return math.clamp(math.max(highestStarredLevel, savedClassicLevel - 1), 0, #Dependencies.Levels)
end

function module.isClassicLevelCompleted(state, Dependencies, levelNumber)
	local resolvedLevel = math.clamp(math.floor(tonumber(levelNumber) or 1), 1, #Dependencies.Levels)
	return resolvedLevel <= module.getHighestReachedClassicLevel(state, Dependencies)
end

function module.getCompletedClassicLevelsCount(state, Dependencies)
	return module.getHighestReachedClassicLevel(state, Dependencies)
end

function module.getHighestCompletedClassicLevel(state, Dependencies)
	return module.getHighestReachedClassicLevel(state, Dependencies)
end

function module.getClassicUnlockedLevel(state, Dependencies)
	local savedClassicLevel = math.max(1, math.floor(tonumber(state.savedClassicLevel) or 1))
	local highestCompletedLevel = module.getHighestCompletedClassicLevel(state, Dependencies)
	local progressedLevel = highestCompletedLevel >= #Dependencies.Levels and #Dependencies.Levels or (highestCompletedLevel + 1)

	return math.clamp(math.max(savedClassicLevel, progressedLevel), 1, #Dependencies.Levels)
end

function module.getClassicContinueLevel(state, Dependencies)
	local resumeBoardState = type(state.resumeBoardState) == "table" and state.resumeBoardState or nil
	local unlockedLevel = module.getClassicUnlockedLevel(state, Dependencies)
	if resumeBoardState and resumeBoardState.mode == "Classic" then
		local resumeLevel = math.clamp(math.floor(tonumber(resumeBoardState.level) or unlockedLevel), 1, #Dependencies.Levels)
		if resumeLevel == unlockedLevel then
			return resumeLevel
		end
	end

	return unlockedLevel
end

function module.applyClassicLevelStarVisual(starNode, isEarned)
	if not starNode then
		return
	end

	if starNode:IsA("ImageLabel") or starNode:IsA("ImageButton") then
		starNode.ImageColor3 = isEarned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(75, 75, 75)
		starNode.ImageTransparency = isEarned and 0 or 0.5
	end

	if starNode:IsA("GuiObject") then
		starNode.Visible = true
	end
end

function module.getClassicLevelTemplate(ui, ReplicatedStorage)
	local template = ui.levelTemplate
	if template and template.Parent then
		return template
	end

	template = ReplicatedStorage:FindFirstChild("Level", true)
	if not (template and template:IsA("GuiObject")) then
		template = ReplicatedStorage:FindFirstChild("LevelTemplate", true)
	end

	if template and template:IsA("GuiObject") then
		ui.levelTemplate = template
		return template
	end

	return nil
end

function module.resolveClassicLevelLabel(root, findDescendantByNames)
	if not root then
		return nil
	end

	local named = findDescendantByNames(root, { "Number", "LevelNumber", "Label", "TextLabel", "Level" }, nil)
	if named and (named:IsA("TextLabel") or named:IsA("TextButton")) then
		return named
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
			and not descendant:FindFirstAncestor("Completed")
			and not descendant:FindFirstAncestor("Locked") then
			return descendant
		end
	end

	return nil
end

function module.getClassicLevelVisualState(isUnlocked, starCount, isCompleted)
	if isCompleted == true or starCount > 0 then
		return "completed", LEVEL_CARD_VISUALS.completed
	end

	if isUnlocked then
		return "playable", LEVEL_CARD_VISUALS.playable
	end

	return "locked", LEVEL_CARD_VISUALS.locked
end

function module.applyClassicLevelVisualState(entry, isUnlocked, starCount, isCompleted, findDescendantByNames)
	if type(entry) ~= "table" then
		return
	end

	local visualKey, visualState = module.getClassicLevelVisualState(isUnlocked, starCount, isCompleted)
	local completedNode = entry.completedNode
	local completedFrame = completedNode and (
		completedNode:FindFirstChild("Frame")
			or findDescendantByNames(completedNode, { "Frame" }, nil)
	) or nil
	local lockedNode = entry.lockedNode

	applyBranchBackgroundColor(entry.root, visualState.cardColor)
	applyBranchBackgroundColor(completedNode, visualState.cardColor)
	applyBranchBackgroundColor(completedFrame, visualState.cardColor)
	applyBranchBackgroundColor(lockedNode, LEVEL_CARD_VISUALS.locked.cardColor)

	if entry.label and (entry.label:IsA("TextLabel") or entry.label:IsA("TextButton")) then
		entry.label.TextColor3 = visualState.textColor
	end

	if completedNode and completedNode:IsA("GuiObject") then
		completedNode.Visible = visualKey == "completed"
	end

	if lockedNode and lockedNode:IsA("GuiObject") then
		lockedNode.Visible = visualKey == "locked"
		for _, descendant in ipairs(lockedNode:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.TextColor3 = LEVEL_CARD_VISUALS.locked.textColor
			end
		end
	end
end

function module.createClassicLevelEntry(env, levelNumber)
	local ui = env.ui
	local container = ui.levelsContainer
	if not (container and container.Parent) then
		return nil
	end

	local template = module.getClassicLevelTemplate(ui, env.ReplicatedStorage)
	local root
	if template then
		root = template:Clone()
		root.Visible = true
	else
		root = env.create("Frame", {
			Name = "LevelCard",
			BackgroundColor3 = Color3.fromRGB(78, 176, 92),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(100, 100),
			Visible = true,
			Parent = container,
		})
		env.create("UICorner", {
			Name = "Corner",
			CornerRadius = UDim.new(0, 10),
			Parent = root,
		})
	end

	root.Name = "Level_" .. tostring(levelNumber)
	root.LayoutOrder = levelNumber
	root:SetAttribute("WordSearchLevelEntry", true)
	root.Parent = container

	if root:IsA("GuiButton") then
		root.Text = ""
	end

	local aspect = root:FindFirstChildWhichIsA("UIAspectRatioConstraint")
	if not aspect then
		aspect = env.create("UIAspectRatioConstraint", {
			Name = "Aspect",
			AspectRatio = 1,
			Parent = root,
		})
	end

	local label = module.resolveClassicLevelLabel(root, env.findDescendantByNames)
	if not label then
		label = env.create("TextLabel", {
			Name = "TextLabel",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.38),
			Size = UDim2.fromScale(0.68, 0.38),
			Text = "",
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextScaled = true,
			Font = Enum.Font.GothamBold,
			ZIndex = (root.ZIndex or 1) + 1,
			Parent = root,
		})
	end

	local pressable = env.findButtonLike(root)
	if not pressable then
		pressable = env.create("TextButton", {
			Name = "Pressable",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			Text = "",
			ZIndex = (root.ZIndex or 1) + 2,
			Parent = root,
		})
	end

	local completedNode = root:FindFirstChild("Completed") or env.findDescendantByNames(root, { "Completed" }, nil)
	local lockedNode = root:FindFirstChild("Locked") or env.findDescendantByNames(root, { "Locked" }, nil)
	local starRoot = completedNode or root
	local starOne = env.findDescendantByNames(starRoot, { "StarOne" }, nil)
	local starTwo = env.findDescendantByNames(starRoot, { "StarTwo" }, nil)
	local starThree = env.findDescendantByNames(starRoot, { "StarThree" }, nil)

	if pressable and pressable:IsA("GuiButton") then
		env.ButtonUi.prepare(pressable)
		if not pressable:GetAttribute("WordSearchLevelBound") then
			pressable:SetAttribute("WordSearchLevelBound", true)
			pressable.Activated:Connect(function()
				env.startClassicLevelFromSelector(tonumber(root:GetAttribute("ClassicLevel")) or levelNumber)
			end)
		end
	end

	local entry = {
		root = root,
		label = label,
		pressable = pressable,
		completedNode = completedNode,
		lockedNode = lockedNode,
		starOne = starOne,
		starTwo = starTwo,
		starThree = starThree,
	}
	ui.levelEntries[levelNumber] = entry
	return entry
end

return module
