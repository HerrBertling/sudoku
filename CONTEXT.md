# Domain language

The words this codebase uses for Sudoku, and what each one means here. Use these
names in code, tests and commit messages; if a concept earns a new name, add it
below rather than letting a synonym spread.

## The grid

**Position** — a square's coordinates as `{row, col}`, 0-based, row first. This is
the domain's coordinate type: selections, conflict sets and solver keys are all
sets of positions. `Sudoku.Game.Position` owns the type, including how it encodes
to the `"row,col"` string used as a map key in storage and as a DOM attribute.
Never build that string by hand.

**Cell** — a square together with its contents: its position, its `value` (1–9 or
empty), whether it is a **given**, and whether it currently conflicts with another
cell. A cell knows its own state; it does not know the rules.

**Box** — one of the nine 3×3 blocks. Numbered 0–8, left to right then top to
bottom.

**Peer** — a position that constrains another: same row, same column, or same box.
Every position has exactly 20 peers, and a position is *not* its own peer. Where
the UI wants "this square and everything it sees", it adds the position itself
explicitly.

**Board** — the 81 cells as a playable whole, plus its difficulty and whether it is
finished. `Sudoku.Game.Board` owns building one — from cells or from a puzzle's
givens — writing digits into it, and answering for its own state: which cell sits
at a position, and whether it is complete.

**Refusal** — a position a placement would not write to, paired with the reason:
the square is a **given**, the board is already complete, or the position is not
on the grid. Writing a digit across a **selection** is expected to meet givens, so
a placement writes what it can and hands the refusals back rather than failing the
whole move.

## The puzzle

**Given** — a digit the puzzle supplies. Givens cannot be changed by the player and
are what makes a puzzle *that* puzzle.

**Puzzle** — the definition alone: the 81 givens, encoded as a string of digits with
`"0"` for a square left empty, read left to right then top to bottom. A puzzle never
changes while it is played. Distinct from the **working state** — the player's
entries on top of it. Keeping the two apart is what lets a game be wound back.

**Candidate** — a digit that could legally occupy an empty square, given the digits
already placed. Derived from the rules, not from the player.

**Unique solution** — the property a puzzle must have to be worth solving. Generated
puzzles preserve it while removing givens; hand-entered puzzles are checked for it
before they can be finalized.

## Playing

**Pencil mark** — a note the *player* writes in an empty cell. Never derived by the
program; a cell stays empty until the player marks it. Two kinds, and the difference
is which question they answer:

- **Centre mark** — cell-centric: "only these digits can go in this cell." Makes
  *naked* sets visible.
- **Corner mark** — digit-centric: "within this box, this digit lives in one of
  these cells." Meaningless in isolation — the information is in the group of cells
  sharing the digit. Makes *hidden* sets visible. Restricting these to digits with
  exactly two possible cells is known as Snyder notation.

**Input mode** — what a typed digit means right now: Normal writes a value, Corner
and Centre write the matching pencil mark, Highlight shades the squares blocked for
that digit. Clearing follows whatever the current mode writes.

**Selection** — the set of positions a digit or mark will apply to. A digit toggles
across a selection *as a group*: it goes onto every eligible cell unless they all
carry it already, in which case it comes off all of them.

**Manual entry** — entering a puzzle's givens by hand, with live feedback on how many
solutions the grid has. Finalizing turns the entered digits into givens and starts
play.

## Storage

**Saved puzzle** — a named puzzle kept on disk, holding both the puzzle definition
and the working state written over it, plus pencil marks and elapsed time. Saving
under an existing name replaces that save.

**Restart** — rebuilding a board from a saved puzzle's definition, discarding the
working state. The stored progress is untouched until it is saved over.

**Saved state** — the part of a **play** worth keeping when nobody is looking at
the board: its cells and difficulty, whether the puzzle is still being entered by
hand, the pencil marks and the clock. Not the selection, the undo history or the
last Check, which belong to the sitting. `Sudoku.Game.SavedState` owns the list
and both ways of writing it down — the browser's storage and a **saved puzzle**'s
row — so the two cannot drift apart, and it owns the version stamped on what the
browser keeps. `Sudoku.Game.PencilMarks` owns the mark half of that shape, and is
also the type of a saved puzzle's mark columns.

**Play** — a board while somebody is sitting in front of it: the board itself plus
the selection, both kinds of pencil mark, the input mode, the undo history, the
clock, the last Check and, during manual entry, the solution count.
`Sudoku.Game.Play` owns all of it as plain data, so a move is a function from one
play to the next. A **Board** is a puzzle and its cells; a play is a board being
played.

**Intent** — what the player meant, expressed without reference to how they said
it: "corner-mark a 2 across the selection", not "Shift plus the Digit2 key".
`Play.act/2` takes one and returns the play that follows. Deciding which key means
which intent is the web layer's job, because that is knowledge about keyboards
rather than about Sudoku.
