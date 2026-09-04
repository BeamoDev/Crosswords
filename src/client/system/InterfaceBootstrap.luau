local InterfaceBootstrap = {}

local function isGameplayHudScreenGui(gui)
	return gui
		and gui:IsA("ScreenGui")
		and (
			gui.Name == "HUD"
			or gui.Name == "Desktop"
			or gui.Name == "Mobile"
			or (gui:FindFirstChild("Game") and gui:FindFirstChild("Frames"))
		)
end

function InterfaceBootstrap.findHUD(playerGui, timeoutSeconds)
	local timeoutAt = tick() + math.max(0.1, tonumber(timeoutSeconds) or 10)

	repeat
		local directHUD = playerGui:FindFirstChild("HUD")
		local desktopHUD = playerGui:FindFirstChild("Desktop")
		local mobileHUD = playerGui:FindFirstChild("Mobile")
		if isGameplayHudScreenGui(directHUD) then
			return directHUD
		end
		if isGameplayHudScreenGui(desktopHUD) then
			return desktopHUD
		end
		if isGameplayHudScreenGui(mobileHUD) then
			return mobileHUD
		end

		for _, child in ipairs(playerGui:GetChildren()) do
			if isGameplayHudScreenGui(child) then
				return child
			end
		end

		task.wait(0.1)
	until tick() >= timeoutAt

	return nil
end

function InterfaceBootstrap.isMobileInterface(userInputService)
	return userInputService.TouchEnabled and not userInputService.KeyboardEnabled
end

function InterfaceBootstrap.removeExistingHUDs(playerGui)
	for _, child in ipairs(playerGui:GetChildren()) do
		if isGameplayHudScreenGui(child) then
			child:Destroy()
		end
	end
end

function InterfaceBootstrap.ensurePlatformHUD(playerGui, interfacesFolder, userInputService)
	if not playerGui then
		return nil
	end

	if not interfacesFolder then
		return InterfaceBootstrap.findHUD(playerGui, 1)
	end

	local templateName = InterfaceBootstrap.isMobileInterface(userInputService) and "Mobile" or "Desktop"
	local template = interfacesFolder:FindFirstChild(templateName)
	if not (template and template:IsA("ScreenGui")) then
		return InterfaceBootstrap.findHUD(playerGui, 1)
	end

	InterfaceBootstrap.removeExistingHUDs(playerGui)

	local clonedHUD = template:Clone()
	clonedHUD.Name = "HUD"
	clonedHUD.ResetOnSpawn = false
	clonedHUD.Enabled = false
	clonedHUD.Parent = playerGui
	return clonedHUD
end

return InterfaceBootstrap
