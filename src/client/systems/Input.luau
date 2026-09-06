local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Input = {}

function Input.bind(board, onPause)
	local connections = {}
	local function connect(signal, callback) table.insert(connections, signal:Connect(callback)) end
	connect(UserInputService.InputBegan, function(input, processed)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			if not board.activeInput then board:Begin(input.Position, input) end
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB then
			if board.startCell then board:Cancel() else onPause() end
			return
		end
		if processed or UserInputService:GetFocusedTextBox() or not board:Interactive() then return end
		local selected = GuiService.SelectedObject
		if selected and not selected:IsDescendantOf(board.grid) then return end
		local directions = {
			[Enum.KeyCode.Left] = { 0, -1 }, [Enum.KeyCode.Right] = { 0, 1 },
			[Enum.KeyCode.Up] = { -1, 0 }, [Enum.KeyCode.Down] = { 1, 0 },
			[Enum.KeyCode.A] = { 0, -1 }, [Enum.KeyCode.D] = { 0, 1 },
			[Enum.KeyCode.W] = { -1, 0 }, [Enum.KeyCode.S] = { 1, 0 },
		}
		local direction = directions[input.KeyCode]
		if direction then board:KeyboardMove(direction[1], direction[2])
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
			board:ActivateCell(board.cursor or { row = 1, column = 1 })
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if not board.activeInput then return end
		if board.inputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement then
			board:Move(input.Position)
		elseif input == board.activeInput then
			board:Move(input.Position)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if not board.activeInput then return end
		if input == board.activeInput or (board.inputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1) then
			board:Move(input.Position)
			board:Finish()
		end
	end)
	connect(UserInputService.WindowFocusReleased, function() board:Cancel() end)
	return function()
		board:Cancel()
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
end

return Input
