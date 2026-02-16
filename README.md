# Sudoku

A browser-based Sudoku game built with Phoenix LiveView and the Ash Framework. Play generated puzzles or enter your own — all in real time with no page reloads.

## Features

- **Puzzle generation** with guaranteed unique solutions at three difficulty levels (easy, medium, hard)
- **Interactive board** — click or use arrow keys to navigate, type 1–9 to place numbers, Backspace to clear
- **Validation** — conflicting cells are highlighted in red as you play
- **Pencil marks** — empty cells automatically show possible candidates; click a candidate to exclude it
- **Number highlighting** — tap a number button to shade all rows, columns, and boxes blocked for that digit
- **Manual entry** — enter your own puzzle givens, with live feedback on solution count, then finalize to start solving
- **Local persistence** — board state is saved to localStorage so refreshing the page picks up where you left off

## Getting Started

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server
```

Then visit [`localhost:4000/game`](http://localhost:4000/game) to play.

## Project Structure

```
lib/
  sudoku/
    game/
      cell.ex        # Embedded Ash resource for a single cell
      board.ex       # Board resource with game actions (new_game, place_number, select_cell)
      game.ex        # Ash domain and code interfaces
      generator.ex   # Puzzle generator with symmetry-preserving shuffles
      solver.ex      # Backtracking solver with MRV heuristic
      validator.ex   # Row/column/box conflict detection
  sudoku_web/
    live/
      game_live.ex        # LiveView event handling and helpers
      game_live.html.heex # Board template
```
