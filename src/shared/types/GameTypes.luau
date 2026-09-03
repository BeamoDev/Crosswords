export type Cell = {
	row: number,
	column: number,
}

export type PuzzleDefinition = {
	id: string,
	title: string,
	description: string?,
	chapterId: string,
	difficulty: string,
	width: number,
	height: number,
	words: { string },
	directions: { string },
	seed: number,
	timeLimitSeconds: number?,
	kind: string,
	grid: { string }?,
}

export type PlacedWord = {
	id: string,
	word: string,
	path: { Cell },
}

export type CompiledPuzzle = {
	id: string,
	title: string,
	description: string?,
	chapterId: string,
	difficulty: string,
	width: number,
	height: number,
	letters: { { string } },
	words: { string },
	placedWords: { PlacedWord },
	seed: number,
	timeLimitSeconds: number?,
}

export type Settings = {
	music: boolean,
	sfx: boolean,
	musicVolume: number,
	sfxVolume: number,
	uiAnimations: boolean,
	reducedMotion: boolean,
	highContrast: boolean,
	colorblindMode: boolean,
}

return {}
