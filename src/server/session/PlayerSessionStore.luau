local PlayerSessionStore = {}

local sessionData = {}
local sessionStartedAt = {}

function PlayerSessionStore.GetData(userId)
	return sessionData[userId]
end

function PlayerSessionStore.SetData(userId, data)
	sessionData[userId] = data
end

function PlayerSessionStore.ClearData(userId)
	sessionData[userId] = nil
	sessionStartedAt[userId] = nil
end

function PlayerSessionStore.GetSessionStartedAt(userId)
	return sessionStartedAt[userId]
end

function PlayerSessionStore.TouchSession(userId, timestamp)
	sessionStartedAt[userId] = timestamp or os.time()
end

return PlayerSessionStore
