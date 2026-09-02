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

**Board** — the 81 cells as a playable whole: a **Game**'s givens with a
**Sitting**'s entries written over them, and whether the result is finished. This
is what the rules apply to and what the player looks at. It belongs to neither
side on its own — it is composed from both, which is why it is never stored.

**Refusal** — a position a placement would not write to, paired with the reason:
the square is a **given**, the board is already complete, or the position is not
on the grid. Writing a digit across a **selection** is expected to meet givens, so
a placement writes what it can and hands the refusals back rather than failing the
whole move.

## The puzzle

**Given** — a digit the puzzle supplies. Givens cannot be changed by the player and
are what makes a puzzle *that* puzzle.

**Puzzle** — the definition alone: the 81 givens, encoded as a string of digits with
`"0"` for a square left empty, read left to right then top to bottom. A format, not
a thing you can point at: two identical strings are the same puzzle. A **Game** is
what gives a puzzle identity.

**Game** — a puzzle in the library: a name, a difficulty, and the **Puzzle** itself.
What was *set*, as opposed to what a player did about it. A Game has identity, and
that is the whole point of the word — it is what lets two **Sittings** be attempts
at the same thing. A Game never changes once created.

**Candidate** — a digit that could legally occupy an empty square, given the digits
already placed. Derived from the rules, not from the player.

**Unique solution** — the property a puzzle must have to be worth solving. Generated
puzzles preserve it while removing givens; hand-entered puzzles are checked for it
before they can be finalized.

## Playing

**Sitting** — one attempt at a **Game**: the entries written over its givens, the
**pencil marks**, the time spent, the **selection** and cursor, the **input mode**,
the undo history and the last **Check**. Everything here is the player's, not the
puzzle's — which is why two Sittings on the same Game are independent and do not
see each other's work, right down to having a clock each.

The line between Game and Sitting is "who put it there": the puzzle, or me.

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

**Check** — a verdict, asked for on demand: which of the player's entries contradict
the puzzle's own solution. Distinct from the conflict flags a **Cell** carries, which
only notice two entries colliding. A Check is *remembered* and goes stale — the next
change to the board invalidates it, because carrying it over would point at cells the
player has since fixed.

**Manual entry** — entering a puzzle's givens by hand, with live feedback on how many
solutions the grid has. Finalizing turns the entered digits into givens, which is the
moment a **Game** comes into existence.

**Intent** — what the player meant, expressed without reference to how they said
it: "corner-mark a 2 across the selection", not "Shift plus the Digit2 key".
Deciding which key means which intent is the web layer's job, because that is
knowledge about keyboards rather than about Sudoku.

## Storage

**Saved state** — the part of a **Sitting** worth keeping when nobody is looking at
the board: the entries, the pencil marks and the time spent. Not the selection, the
undo history or the last **Check**, which last only as long as the tab. One
definition, written down two ways — the browser's storage and a row on disk — so the
two cannot drift apart.

**Restart** — starting a *new* **Sitting** on a **Game**, discarding the one you had.
The Game is untouched: it was only ever the givens. Distinct from loading, which
resumes an existing Sitting.
