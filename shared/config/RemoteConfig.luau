local RemoteConfig = {
	FolderName = "WordSearchRevampRemotes",
	Functions = {
		GetBootstrap = "GetBootstrap",
		StartRound = "StartRound",
		SubmitSelection = "SubmitSelection",
		RequestHint = "RequestHint",
		SetPaused = "SetPaused",
		UpdateSettings = "UpdateSettings",
		CompleteTutorial = "CompleteTutorial",
	},
	Events = {
		AbandonRound = "AbandonRound",
		StateUpdated = "StateUpdated",
		ServerNotice = "ServerNotice",
	},
}

return table.freeze(RemoteConfig)
