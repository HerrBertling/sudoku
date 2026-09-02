---
status: accepted
---

# Elapsed time belongs to the Sitting, not the Game

A **Game** is a puzzle in the library — its name, difficulty and givens — and a
**Sitting** is one attempt at it. Time spent is the player's, not the puzzle's, so
elapsed time is a property of a Sitting: two Sittings on the same Game each keep
their own clock, and loading a save does not resume a clock from some earlier
attempt.

## Considered options

Elapsed time as a property of the **Game** — total time this puzzle has cost you,
accumulating across every Sitting, the way a correspondence chess game accumulates
think-time. This is the more obvious reading, and it is what the code did: the
`saved_puzzles` table carried an `elapsed_seconds` column and loading a save
resumed the clock where it left off.

It was rejected because it cannot answer the question that decided the whole
domain model: can the same Game be played in two Sittings? If it can, then
everything the player accumulates — entries, pencil marks, time — is per-Sitting,
and the clock is simply the first place that becomes obvious. Making the clock the
one exception would have left the model incoherent for the sake of a number nobody
asked for.

## Consequences

`elapsed_seconds` is dropped from storage. Nothing was deployed and the puzzle
library held a handful of rows, so no migration path was built for it.

The two ways a Sitting gets written down had disagreed about this: SQLite
persisted the clock, while the browser mirror deliberately did not — *"a refresh
has always started the timer again, and only a saved puzzle remembers elapsed
time."* This decision makes the browser's behaviour the correct one and removes
the disagreement, rather than fixing the mirror to match the database.

A player who saves, closes the tab and returns tomorrow sees the clock at zero.
That is the intended behaviour, not a bug: they are starting a new Sitting.
