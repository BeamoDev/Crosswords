export type Cell = {row: number, column: number}
export type PuzzleDefinition = {
    rules: string, mode: string, level: number?, seed: number?, beginner: boolean?, tutorial: boolean?,
    gridSize: number, gridWidth: number, wordCount: number,
}
export type Entry = {
    id: string, number: number, direction: string, clue: string, length: number, path: {Cell},
    answer: string?, -- Canonical server entry only. Always absent in public puzzles.
}
export type Puzzle = {
    rules: string, mode: string?, title: string, subtitle: string?, tutorial: boolean?,
    gridSize: number, gridWidth: number, words: {string}, placedWordsByWord: {[string]: Entry},
    letters: {{string}}, -- Public: empty string is a block; single space is an open square.
}
return {}
