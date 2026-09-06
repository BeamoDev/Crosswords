export type DirectionName = "N" | "NE" | "E" | "SE" | "S" | "SW" | "W" | "NW"

export type Cell = {
	row: number,
	column: number,
}

export type DirectionVector = { number }

export type PuzzleDefinition = {
	level: number?,
	title: string?,
	subtitle: string?,
	gridSize: number, -- Row count; square definitions can omit gridWidth.
	gridWidth: number?,
	words: { string },
	directions: { DirectionName | DirectionVector }?,
	seed: number?,
	mode: string?,
}

export type PlacedWord = {
	word: string,
	path: { Cell },
}

export type GeneratedPuzzle = {
	level: number?,
	seed: number?,
	mode: string?,
	gridSize: number, -- Row count; square definitions can omit gridWidth.
	gridWidth: number?,
	letters: { { string } },
	words: { string },
	placedWords: { PlacedWord }?,
	placedWordsByWord: { [string]: PlacedWord }?,
}

export type BoardState = {
	mode: string,
	level: number,
	seed: number,
	foundWords: { string },
	hintedWords: { string },
	sessionScore: number?,
	puzzlesCleared: number?,
	streak: number?,
	hintUses: number?,
	startedAtServerTime: number?,
}

return {}
