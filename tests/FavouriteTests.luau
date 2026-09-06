local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rbx = require("@lune/roblox")
local Contract = require("../src/shared/network/NetworkContract")
local checks = 0
local function check(ok, why) assert(ok, why) checks += 1 end
local function signal()
    local s = { callbacks = {} }
    function s:Connect(fn) table.insert(self.callbacks, fn) end
    function s:Fire(...) for _, fn in ipairs(self.callbacks) do fn(...) end end
    return s
end
local now, jobs = 0, {}
local function schedule(delay, thread) table.insert(jobs, { at = now + delay, thread = thread }) end
local function advance(seconds)
    local target = now + seconds
    while true do
        table.sort(jobs, function(a,b) return a.at < b.at end)
        if not jobs[1] or jobs[1].at > target then break end
        local job = table.remove(jobs, 1)
        now = job.at
        local ok, delay = coroutine.resume(job.thread)
        assert(ok, delay)
        if coroutine.status(job.thread) ~= "dead" then schedule(delay, job.thread) end
    end
    now = target
end
local players = {}
local profiles, saved, calls, attempts, snapshots = {}, {}, {}, {}, {}
local failSave, removeDuringSave = false, nil
local service
local data = {
    GetMutableData = function(p) return profiles[p] end,
    MarkFavouritePrompted = function(p)
        attempts[p] = (attempts[p] or 0) + 1
        profiles[p].account.favouritePrompted = true
        if failSave then return false end
        saved[p.UserId] = true
        if removeDuringSave then service.RemovePlayer(p) p.Parent = nil end
        return true
    end,
    GetSnapshot = function(p) return profiles[p] end,
}
local remote = { OnServerEvent = signal(), FireClient = function(_,p)
    check(saved[p.UserId], "Prompt must follow a durable save")
    calls[p] = (calls[p] or 0) + 1
end }
local state = { FireClient = function(_,p,s) snapshots[p] = s end }
service = luau.load(fs.readFile("src/server/services/FavouriteService.luau"), { environment = {
    game = { GetService = function() return players end },
    script = { Parent = { Parent = { data = { DataService = data } } } },
    require = function(m) return m end,
    task = { delay = function(seconds, fn) schedule(seconds, coroutine.create(fn)) end, wait = coroutine.yield },
} })()
service.Init(remote, state)
local function actor(id, ready)
    local p = { UserId = id, Parent = players, ready = ready ~= false }
    function p:GetAttribute() return self.ready end
    profiles[p] = { account = { favouritePrompted = saved[id] == true } }
    service.AddPlayer(p)
    return p
end
local a = actor(1)
remote.OnServerEvent:Fire(a)
advance(899)
check(not calls[a] and not attempts[a], "No prompt or save before 15 minutes")
remote.OnServerEvent:Fire(a)
service.AddPlayer(a)
advance(1)
check(calls[a] == 1 and snapshots[a].account.favouritePrompted, "15 minutes prompts once and updates snapshot")
advance(900)
remote.OnServerEvent:Fire(a)
check(calls[a] == 1, "Duplicate readiness and elapsed time cannot repeat prompt")
service.RemovePlayer(a) a.Parent = nil
local rejoined = actor(1)
remote.OnServerEvent:Fire(rejoined)
advance(900)
check(not calls[rejoined] and not attempts[rejoined], "Saved flag suppresses prompt after rejoin")
local departed = actor(2)
remote.OnServerEvent:Fire(departed)
advance(899)
service.RemovePlayer(departed) departed.Parent = nil
advance(1)
check(not calls[departed] and not attempts[departed], "Leaving before deadline neither marks nor prompts")
local loading = actor(3, false)
remote.OnServerEvent:Fire(loading)
advance(900)
check(not attempts[loading], "Failed or pending profile load cannot create default writes")
loading.ready = true
advance(30)
check(calls[loading] == 1, "Late profile load dispatches only after eligibility")
local lateClient = actor(4)
remote.OnServerEvent:Fire(lateClient, true)
advance(900)
check(not attempts[lateClient], "Reject payload and wait for actual listener readiness")
remote.OnServerEvent:Fire(lateClient)
advance(30)
check(calls[lateClient] == 1, "Late client listener receives one prompt")
local retry = actor(5)
remote.OnServerEvent:Fire(retry)
failSave = true
advance(900)
check(not calls[retry] and attempts[retry] == 1, "Failed persistence postpones prompt")
failSave = false
advance(30)
check(calls[retry] == 1 and attempts[retry] == 2, "Reserved flag still retries failed save")
local race = actor(6)
remote.OnServerEvent:Fire(race)
removeDuringSave = true
advance(900)
check(not calls[race], "Disconnect during yielded save prevents late dispatch")
removeDuringSave = nil
local shutdown = actor(7)
remote.OnServerEvent:Fire(shutdown)
service.Stop()
advance(900)
check(not attempts[shutdown], "Shutdown cancels pending timers")

local function folder(t)
    function t:WaitForChild(name) return assert(self[name], name) end
    return t
end
local clientRemote = { OnClientEvent = signal() }
local readyCount, promptCount, warnCount = 0, 0, 0
function clientRemote:FireServer()
    check(#self.OnClientEvent.callbacks == 1, "Listener connects before readiness")
    readyCount += 1
end
local storage = folder({ shared = folder({ network = folder({ NetworkContract = Contract }) }),
    [Contract.FolderName] = folder({ [Contract.FavouritePrompt] = clientRemote }) })
local avatar = { PromptSetFavorite = function(_, id, itemType, favourite)
    check(id == 1234 and itemType == rbx.Enum.AvatarItemType.Asset and favourite == true, "Native prompt targets current place as favourite")
    promptCount += 1
    error("Mock unsupported prompt")
end }
local services = { Players = { LocalPlayer = {} }, ReplicatedStorage = storage, UserInputService = {},
    ContentProvider = {}, RunService = {}, SoundService = {}, TweenService = {}, AvatarEditorService = avatar }
local social = luau.load(fs.readFile("src/client/features/Social.luau"), { environment = {
    game = { PlaceId = 1234, GetService = function(_,name) return assert(services[name], name) end },
    require = function(m) return m end, UDim2 = rbx.UDim2, Enum = rbx.Enum,
    warn = function() warnCount += 1 end,
} })()
social.FavouritePrompt.Init()
social.FavouritePrompt.Init()
clientRemote.OnClientEvent:Fire()
clientRemote.OnClientEvent:Fire()
check(readyCount == 1 and promptCount == 1 and warnCount == 1, "Init/dispatch are idempotent and platform failures stay contained")
print("FAVOURITE_TESTS_PASSED=" .. checks)