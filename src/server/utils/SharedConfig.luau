local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TableUtils = require(script.Parent.TableUtils)

local SharedConfig = {}

function SharedConfig.Resolve(configName, defaults)
	local sharedFolder = ReplicatedStorage:FindFirstChild("shared")
	local configFolder = sharedFolder and sharedFolder:FindFirstChild("config") or nil
	local configModule = configFolder and configFolder:FindFirstChild(configName) or nil
	if configModule and configModule:IsA("ModuleScript") then
		local ok, result = pcall(require, configModule)
		if ok and type(result) == "table" then
			return TableUtils.MergeDefaults(TableUtils.CloneDeep(result), TableUtils.CloneDeep(defaults or {}))
		end
	end

	return TableUtils.CloneDeep(defaults or {})
end

return SharedConfig
