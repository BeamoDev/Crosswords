local Input = {}

local function isActiveTouchInput(state, input)
	if state.activeInputType ~= Enum.UserInputType.Touch then
		return false
	end

	if input == state.activeInput then
		return true
	end

	return input.UserInputType == Enum.UserInputType.Touch
end

function Input.bind(config)
	local state = config.state
	local runtimeHelpers = config.runtimeHelpers

	config.userInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch then
			if not state.dragging and runtimeHelpers.tryBeginDragFromScreenPosition then
				runtimeHelpers.tryBeginDragFromScreenPosition(Vector2.new(input.Position.X, input.Position.Y), input)
			end
			return
		end

		if gameProcessed then
			return
		end

		if not string.find(tostring(input.UserInputType), "Gamepad") then
			return
		end

		if input.KeyCode == Enum.KeyCode.ButtonB
			and state.dragging
			and string.find(tostring(state.activeInputType), "Gamepad")
		then
			config.clearDrag()
			config.playSound("Button2")
		end
	end)

	config.userInputService.InputChanged:Connect(function(input)
		if not state.dragging then
			return
		end

		if state.activeInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement then
			runtimeHelpers.updateDragTarget(Vector2.new(input.Position.X, input.Position.Y))
		elseif isActiveTouchInput(state, input) then
			runtimeHelpers.updateDragTarget(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	config.userInputService.InputEnded:Connect(function(input)
		if not state.dragging then
			return
		end

		if state.activeInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1 then
			runtimeHelpers.completeSelection()
		elseif isActiveTouchInput(state, input) then
			runtimeHelpers.completeSelection()
		end
	end)
end

return Input
