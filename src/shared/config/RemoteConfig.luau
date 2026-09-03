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
		ClaimDailyReward = "ClaimDailyReward",
		PurchaseShopItem = "PurchaseShopItem",
		EquipCosmetic = "EquipCosmetic",
	},
	Events = {
		AbandonRound = "AbandonRound",
		StateUpdated = "StateUpdated",
		ServerNotice = "ServerNotice",
	},
}

return table.freeze(RemoteConfig)
