local module = {}

function module.create(className, props)
	local instance = Instance.new(className)
	instance.Name = props.Name or className

	for key, value in pairs(props) do
		if key ~= "Parent" and key ~= "Name" then
			instance[key] = value
		end
	end

	instance.Parent = props.Parent
	return instance
end

function module.findDescendantByNames(root, names, className)
	if not root then
		return nil
	end

	for _, name in ipairs(names or {}) do
		local descendant = root:FindFirstChild(name, true)
		if descendant and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

function module.findPath(root, path, className)
	local current = root

	for _, name in ipairs(path or {}) do
		current = current and current:FindFirstChild(name) or nil
	end

	if current and (not className or current:IsA(className)) then
		return current
	end

	return nil
end

function module.findFirstPath(root, paths, className)
	for _, path in ipairs(paths or {}) do
		local found = module.findPath(root, path, className)
		if found then
			return found
		end
	end

	return nil
end

function module.waitForDescendantByNames(root, names, className)
	local found = module.findDescendantByNames(root, names, className)
	if found then
		return found
	end

	while root and root.Parent do
		root.DescendantAdded:Wait()
		found = module.findDescendantByNames(root, names, className)
		if found then
			return found
		end
	end

	return nil
end

function module.findTextObject(root, names)
	if not root then
		return nil
	end

	local named = module.findDescendantByNames(root, names, nil)
	if named and (named:IsA("TextLabel") or named:IsA("TextButton")) then
		return named
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end

	return root:FindFirstChildWhichIsA("TextLabel", true) or root:FindFirstChildWhichIsA("TextButton", true)
end

function module.findImageObject(root, names)
	if not root then
		return nil
	end

	local named = module.findDescendantByNames(root, names, nil)
	if named and (named:IsA("ImageLabel") or named:IsA("ImageButton")) then
		return named
	end

	return root:FindFirstChildWhichIsA("ImageLabel", true) or root:FindFirstChildWhichIsA("ImageButton", true)
end

function module.ensureScaleController(guiObject)
	local scaleController = guiObject:FindFirstChild("ScaleController")
	if scaleController and scaleController:IsA("UIScale") then
		return scaleController
	end

	return module.create("UIScale", {
		Name = "ScaleController",
		Scale = 1,
		Parent = guiObject,
	})
end

function module.tween(
	instance,
	properties,
	durationOrInfo,
	defaultDuration,
	defaultEasingStyle,
	defaultEasingDirection,
	tweenService
)
	if typeof(instance) ~= "Instance" then
		return nil
	end
	if instance.Parent == nil then
		return nil
	end

	local tweenInfo = durationOrInfo
	if typeof(durationOrInfo) ~= "TweenInfo" then
		tweenInfo = TweenInfo.new(
			durationOrInfo or defaultDuration,
			defaultEasingStyle,
			defaultEasingDirection
		)
	end

	local success, animation = pcall(function()
		return tweenService:Create(instance, tweenInfo, properties)
	end)
	if not success then
		return nil
	end

	animation:Play()
	return animation
end

function module.bindButtonHoverSound(button, playSound)
	if not button or not button:IsA("GuiButton") or button:GetAttribute("WordSearchHoverSfxBound") then
		return
	end

	button:SetAttribute("WordSearchHoverSfxBound", true)
	button.MouseEnter:Connect(function()
		if playSound then
			playSound("Hover")
		end
	end)
end

function module.findButtonLike(root)
	if not root then
		return nil
	end

	if root:IsA("GuiButton") then
		return root
	end

	local directButton = root:FindFirstChild("Button")
	if directButton and directButton:IsA("GuiButton") then
		return directButton
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == "Button" and descendant:IsA("GuiButton") then
			return descendant
		end
	end

	return root:FindFirstChildWhichIsA("GuiButton", true)
end

function module.findBarContainer(root)
	if not root then
		return nil
	end

	local direct = root:FindFirstChild("ProgressBar") or root:FindFirstChild("Bar")
	if direct and direct:IsA("GuiObject") then
		return direct
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("GuiObject") and child:FindFirstChild("Fill") then
			return child
		end
	end

	return nil
end

function module.setBarFillAlpha(barFill, bar, alpha)
	local clampedAlpha = math.clamp(alpha or 0, 0, 1)
	if barFill and barFill:IsA("GuiObject") then
		barFill.Size = UDim2.new(clampedAlpha, 0, 1, 0)
		return
	end

	if bar and bar:IsA("GuiObject") then
		bar.Size = UDim2.new(clampedAlpha, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
	end
end

function module.setVisible(node, visible)
	if node and node:IsA("GuiObject") then
		node.Visible = visible
	end
end

function module.setText(node, value, fallbackNames)
	if not node then
		return
	end

	if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
		node.Text = tostring(value or "")
		return
	end

	local label = module.findTextObject(node, fallbackNames or { "TextLabel", "Label", "Data", "Value", "Amount" })
	if label then
		label.Text = tostring(value or "")
	end
end

return module
