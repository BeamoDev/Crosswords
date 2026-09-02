local InterfaceBootstrap = {}

local function isGameplayHudScreenGui(gui)
	return gui and gui:IsA("ScreenGui") and gui.Name == "HUD"
end

function InterfaceBootstrap.findHUD(playerGui, timeoutSeconds)
	local timeoutAt = tick() + math.max(0.1, tonumber(timeoutSeconds) or 10)

	repeat
		local directHUD = playerGui:FindFirstChild("HUD")
		if isGameplayHudScreenGui(directHUD) then
			return directHUD
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

function InterfaceBootstrap.removeExistingHUDs(_playerGui)
end

function InterfaceBootstrap.ensurePlatformHUD(playerGui, _interfacesFolder, _userInputService)
	if not playerGui then
		return nil
	end

	return InterfaceBootstrap.findHUD(playerGui, 1)
end

return InterfaceBootstrap
