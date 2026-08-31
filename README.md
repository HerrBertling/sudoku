# Sudoku

A browser-based Sudoku game built with Phoenix LiveView and the Ash Framework. Play generated puzzles or enter your own — all in real time with no page reloads.

## Features

- **Puzzle generation** with guaranteed unique solutions at three difficulty levels (easy, medium, hard)
- **Interactive board** — click, drag or arrow-key across cells, type 1–9 to place numbers, Backspace to clear
- **Multi-cell selection** — drag to sweep, `Ctrl`/`Cmd`+click to add or remove a cell, `Shift`+arrows to extend,
  `Ctrl`+`A` for the whole grid. Digits and marks apply to every selected cell at once, so one keystroke can
  mark a whole set of candidates
- **Undo/redo** — `Ctrl`/`Cmd`+`Z` and `Ctrl`+`Y`, or the on-screen buttons, over the last 200 changes
- **Check** — solves the puzzle from its givens and highlights any entry that contradicts the solution,
  rather than waiting for two entries to collide
- **Clock** — a pausable timer that is stored with a save, so resuming a puzzle picks its time back up
- **Validation** — conflicting cells are highlighted in red as you play
- **Pencil marks** — you write them, not the computer. Empty cells stay empty until you mark them:
  - **Corner marks** for "within this box, the 2 goes in this cell or that one" (Snyder notation)
  - **Centre marks** for "only these digits can go here"
- **Four input modes** — Normal, Corner, Centre and Highlight, switchable with the on-screen buttons,
  with `Z`/`X`/`C`, by pressing Space, or with modifiers: `Shift`+digit writes a corner mark,
  `Ctrl`+digit a centre mark
- **Scoped clearing** — clearing follows whatever the current mode writes. `Backspace` empties the cell,
  while `Shift`+`Backspace` takes only the corner marks and `Ctrl`+`Backspace` only the centre marks;
  the on-screen Clear button does the same for whichever mode is active
- **Number highlighting** — in Highlight mode, tap a number to shade all rows, columns, and boxes blocked for that digit
- **Remaining counts** — each number button shows how many of that digit are still unplaced, greying out when done
- **Row and column labels** around the grid, for keeping your place while transcribing from paper
- **Manual entry** — enter your own puzzle givens, with live feedback on solution count, then finalize to start solving
- **Puzzle library** — name and save any finalized board to a local SQLite database, then browse them in a
  searchable list (filter by name, or show only your own entries rather than generated games). Each row shows
  how far through you are, e.g. `12/45 filled`. Saving under an existing name overwrites that save
  - **Load** resumes a puzzle with your entries and pencil marks intact
  - **Restart** replays it from its original givens, without touching the progress you have stored
- **Local persistence** — the current board is also mirrored to localStorage, so a refresh picks up where you left off

## Getting Started

```bash
# Install dependencies and create the database
mix setup

# Start the server
mix phx.server
```

`mix setup` runs `mix ash.setup`, which creates `priv/sudoku_dev.db` and applies migrations.
Set `PORT` to run on something other than 4000.

Then visit [`localhost:4000/game`](http://localhost:4000/game) to play.

## Project Structure

```
lib/
  sudoku/
    game/
      cell.ex         # Embedded Ash resource for a single cell
      board.ex        # Board resource with game actions (new_game, place_number)
      puzzle.ex       # A puzzle's definition: its 81 givens, encoded as a string
      saved_puzzle.ex # SQLite-backed resource: a named puzzle, its working state and marks
      game.ex         # Ash domain and code interfaces
      generator.ex    # Puzzle generator with symmetry-preserving shuffles
      solver.ex       # Backtracking solver: counts solutions, and solves for Check
      validator.ex    # Row/column/box conflict detection
    repo.ex           # AshSqlite repo
  sudoku_web/
    live/
      game_live.ex        # LiveView event handling and helpers
      game_live.html.heex # Board template
```
