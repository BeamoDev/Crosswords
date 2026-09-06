local Utility = {}

function Utility.GetOrCreate(parent, className, name)
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end




function Utility.CloneDeep(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = Utility.CloneDeep(child)
	end
	return copy
end

function Utility.MergeDefaults(target, defaults)
	if type(defaults) ~= "table" then
		return target
	end

	if type(target) ~= "table" then
		return Utility.CloneDeep(defaults)
	end

	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = Utility.CloneDeep(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			Utility.MergeDefaults(target[key], value)
		end
	end

	return target
end


local ReplicatedStorage = game:GetService("ReplicatedStorage")


function Utility.Resolve(configName, defaults)
	local sharedFolder = ReplicatedStorage:FindFirstChild("shared")
	local configFolder = sharedFolder and sharedFolder:FindFirstChild("config") or nil
	local configModule = configFolder and configFolder:FindFirstChild(configName) or nil
	if configModule and configModule:IsA("ModuleScript") then
		local ok, result = pcall(require, configModule)
		if ok and type(result) == "table" then
			return Utility.MergeDefaults(Utility.CloneDeep(result), Utility.CloneDeep(defaults or {}))
		end
	end

	return Utility.CloneDeep(defaults or {})
end


return Utility
