local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Input = {}
function Input.bind(board, onPause)
    local connections = {}
    table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.ButtonB then onPause() return end
        if not board:Interactive() then return end
        local selected = GuiService.SelectedObject
        if selected and not selected:IsDescendantOf(board.ui.boardPanel) and not selected:IsDescendantOf(board.ui.wordPanel) then return end
        local code = input.KeyCode
        local dpad = code == Enum.KeyCode.DPadLeft or code == Enum.KeyCode.DPadRight or code == Enum.KeyCode.DPadUp or code == Enum.KeyCode.DPadDown
        if dpad and selected then return end
        local directions = {
            [Enum.KeyCode.Left]={0,-1}, [Enum.KeyCode.Right]={0,1}, [Enum.KeyCode.Up]={-1,0}, [Enum.KeyCode.Down]={1,0},
            [Enum.KeyCode.DPadLeft]={0,-1}, [Enum.KeyCode.DPadRight]={0,1}, [Enum.KeyCode.DPadUp]={-1,0}, [Enum.KeyCode.DPadDown]={1,0},
        }
        if directions[code] then board:KeyboardMove(table.unpack(directions[code]))
        elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then board:Key("BACK")
        elseif code == Enum.KeyCode.Return or code == Enum.KeyCode.KeypadEnter then board:Key("CHECK")
        elseif code == Enum.KeyCode.Tab or code == Enum.KeyCode.ButtonR1 then board:Key("NEXT")
        elseif code == Enum.KeyCode.ButtonL1 then board:Key("PREV")
        elseif code == Enum.KeyCode.Space or code == Enum.KeyCode.ButtonX then board:Key("TURN")
        elseif code == Enum.KeyCode.ButtonA and not selected then board:Key("CHECK")
        elseif input.UserInputType == Enum.UserInputType.Keyboard and code.Name:match("^[A-Z]$") then board:Key(code.Name) end
    end))
    table.insert(connections, UserInputService.WindowFocusReleased:Connect(function() board:Cancel() end))
    return function()
        board:Cancel()
        for _, connection in ipairs(connections) do connection:Disconnect() end
    end
end
return Input
