defmodule Sudoku.Game.Play do
  @moduledoc """
  A game being played: the board, everything the player has written on top of
  it, and every rule that turns a keystroke into a new state.

  A `Board` is a puzzle plus its cells. A *play* is that board while somebody is
  sitting in front of it — the selection, the pencil marks, the input mode, the
  undo history, the clock, the last Check, and, while a puzzle is being entered
  by hand, how many solutions the grid still has. All of it is plain data, so a
  move is a function from one play to the next and needs no process, no socket
  and no browser.

  ## Interface

  Two functions:

    * `new/2` — start playing a board (or a bare list of cells).
    * `act/2` — apply one **intent** and get the next play back.

  Everything else is fields on the struct, read directly. The point is that a
  caller has one verb to learn: decode whatever the player did into an intent,
  hand it over, render what comes back.

  ## Intents

  An intent is what the player meant, not which key they hit — deciding that
  `Shift` plus the `Digit2` key means "corner-mark a 2" is the caller's job,
  because that is knowledge about keyboards, not about Sudoku.

      {:select, position, :replace | :toggle | :extend}
      :select_all
      :clear_selection
      {:move_cursor, :up | :down | :left | :right, extend?}

      {:digit, digit}                          # writes in the active mode
      {:digit, digit, :corner | :center | nil} # a modifier overrides the mode
      :clear
      {:clear, :corner | :center | nil}

      {:input_mode, :normal | :corner | :center | :highlight}
      :cycle_input_mode
      {:highlight, digit}

      :undo
      :redo
      :check
      :finalize

      :toggle_timer
      :tick

      {:resume, cells, opts}   # adopt a board handed back by storage

  ## Derived fields

  `blocked_cells` and `remaining_counts` are recomputed on every `act/2`, so a
  renderer can read them like any other field and never has to ask the module
  to work something out. They are outputs, never inputs: setting them by hand
  does nothing but get overwritten.
  """

  alias Sudoku.Game.Board
  alias Sudoku.Game.Position
  alias Sudoku.Game.Puzzle
  alias Sudoku.Game.Solver

  # How many steps back Undo can reach.
  @history_limit 200

  defstruct board: nil,
            mode: :playing,
            corner_marks: %{},
            center_marks: %{},
            selection: MapSet.new(),
            cursor: nil,
            history: [],
            future: [],
            input_mode: :normal,
            highlighted_number: nil,
            check: nil,
            check_errors: MapSet.new(),
            solution_count: nil,
            elapsed: 0,
            timer_running: true,
            blocked_cells: MapSet.new(),
            remaining_counts: %{},
            revision: 0

  @type position :: {0..8, 0..8}
  @type marks :: %{optional(String.t()) => MapSet.t(1..9)}

  @type t :: %__MODULE__{
          board: struct(),
          mode: :playing | :manual_entry,
          corner_marks: marks(),
          center_marks: marks(),
          selection: MapSet.t(position()),
          cursor: position() | nil,
          history: [map()],
          future: [map()],
          input_mode: :normal | :corner | :center | :highlight,
          highlighted_number: 1..9 | nil,
          check: nil | :checked | :unsolvable,
          check_errors: MapSet.t(position()),
          solution_count: non_neg_integer() | nil,
          elapsed: non_neg_integer(),
          timer_running: boolean(),
          blocked_cells: MapSet.t(position()),
          remaining_counts: %{(1..9) => integer()},
          revision: non_neg_integer()
        }

  @doc """
  Starts playing `board` — either a `%Sudoku.Game.Board{}` or the list of cells
  to build one from.

  Options:

    * `:difficulty` — only used when building a board from cells (default
      `:custom`)
    * `:corner_marks`, `:center_marks` — marks to start with, as maps of
      `Position.key/1` to a `MapSet` of digits
    * `:mode` — `:playing` (default) or `:manual_entry`
    * `:elapsed` — seconds already spent on this puzzle
  """
  def new(board_or_cells, opts \\ [])

  def new(%Board{} = board, opts) do
    mode = Keyword.get(opts, :mode, :playing)

    %__MODULE__{
      board: board,
      mode: mode,
      corner_marks: Keyword.get(opts, :corner_marks, %{}),
      center_marks: Keyword.get(opts, :center_marks, %{}),
      elapsed: Keyword.get(opts, :elapsed, 0),
      solution_count: if(mode == :manual_entry, do: count_solutions(board), else: nil)
    }
    |> derive()
  end

  def new(cells, opts) when is_list(cells) do
    new(Board.new(cells, difficulty: Keyword.get(opts, :difficulty, :custom)), opts)
  end

  @doc """
  Applies one intent and returns the play that follows from it.

  An intent that changes nothing — a digit with no cell selected, an Undo with
  no history — returns the play unchanged rather than failing, so a caller
  never has to ask whether a move is available before making it.
  """
  def act(%__MODULE__{} = play, intent), do: play |> step(intent) |> derive()

  # ── Selection and cursor ─────────────────────────────────────────────────

  defp step(play, {:select, position, :replace}),
    do: %{play | selection: MapSet.new([position]), cursor: position}

  defp step(play, {:select, position, :toggle}),
    do: %{play | selection: toggle_member(play.selection, position), cursor: position}

  defp step(play, {:select, position, :extend}),
    do: %{play | selection: MapSet.put(play.selection, position), cursor: position}

  defp step(play, :select_all),
    do: %{play | selection: all_positions(), cursor: cursor(play)}

  defp step(play, :clear_selection), do: %{play | selection: MapSet.new()}

  defp step(play, {:move_cursor, direction, extending?}) do
    {row, col} = cursor(play)

    next =
      case direction do
        :up -> {Integer.mod(row - 1, 9), col}
        :down -> {Integer.mod(row + 1, 9), col}
        :left -> {row, Integer.mod(col - 1, 9)}
        :right -> {row, Integer.mod(col + 1, 9)}
      end

    selection =
      if extending?, do: MapSet.put(play.selection, next), else: MapSet.new([next])

    %{play | selection: selection, cursor: next}
  end

  # ── Writing ──────────────────────────────────────────────────────────────

  defp step(play, {:digit, digit}), do: step(play, {:digit, digit, nil})

  defp step(play, {:digit, digit, override}),
    do: write(play, digit, resolve_mode(play, override))

  defp step(play, :clear), do: step(play, {:clear, nil})
  defp step(play, {:clear, override}), do: erase(play, resolve_mode(play, override))

  # ── Modes and highlighting ───────────────────────────────────────────────

  defp step(play, {:input_mode, mode}), do: %{play | input_mode: mode}
  defp step(play, :cycle_input_mode), do: %{play | input_mode: next_mode(play.input_mode)}
  defp step(play, {:highlight, digit}), do: highlight(play, digit)

  # ── History ──────────────────────────────────────────────────────────────

  defp step(play, :undo) do
    case play.history do
      [] ->
        play

      [previous | rest] ->
        current = snapshot(play)
        restored = restore(play, previous)

        %{restored | history: rest, future: [current | play.future]}
    end
  end

  defp step(play, :redo) do
    case play.future do
      [] ->
        play

      [next | rest] ->
        current = snapshot(play)
        restored = restore(play, next)

        %{restored | history: [current | play.history], future: rest}
    end
  end

  # ── Whole-game moves ─────────────────────────────────────────────────────

  defp step(play, :check), do: check(play)

  # Turns everything entered so far into givens: the grid stops being a draft
  # and becomes the puzzle being played.
  defp step(play, :finalize) do
    cells = Enum.map(play.board.cells, fn c -> if c.value, do: %{c | given: true}, else: c end)

    %{
      play
      | board: %{play.board | cells: cells},
        mode: :playing,
        solution_count: nil,
        history: [],
        future: []
    }
    |> touch()
  end

  defp step(play, :toggle_timer), do: %{play | timer_running: not play.timer_running}

  defp step(play, :tick) do
    if play.timer_running and play.board.status == :playing,
      do: %{play | elapsed: play.elapsed + 1},
      else: play
  end

  # Storage handing the board back mid-session: the cells and marks are
  # replaced, but the clock and the selection belong to this sitting and carry
  # on. Nothing is pushed back to storage — storage is where this came from.
  defp step(play, {:resume, cells_or_board, opts}) do
    mode = Keyword.get(opts, :mode, :playing)
    board = board_from(cells_or_board, Keyword.get(opts, :difficulty, :custom))

    %{
      play
      | board: board,
        mode: mode,
        corner_marks: Keyword.get(opts, :corner_marks, %{}),
        center_marks: Keyword.get(opts, :center_marks, %{}),
        history: [],
        future: [],
        solution_count: if(mode == :manual_entry, do: count_solutions(board), else: nil)
    }
  end

  # ── Digit input ──────────────────────────────────────────────────────────

  defp write(play, digit, :highlight), do: highlight(play, digit)

  defp write(play, digit, :normal), do: mutate(play, &place(&1, digit))

  defp write(play, digit, mode) when mode in [:corner, :center] do
    mutate(play, &toggle_marks(&1, marks_field(mode), digit))
  end

  # Clearing narrows to whatever the current mode writes: Normal empties the
  # cell outright, Corner and Centre take only their own marks with them.
  defp erase(play, :highlight), do: %{play | highlighted_number: nil}

  defp erase(play, mode) when mode in [:corner, :center],
    do: mutate(play, &clear_marks(&1, marks_field(mode)))

  defp erase(play, :normal), do: mutate(play, &place(&1, nil))

  # The whole selection goes to the board in one call. Board writes what it
  # can and names the squares it would not touch — a given, or any square at
  # all once the puzzle is finished — which across a sweep is ordinary rather
  # than exceptional, so the refusals just tell us which marks to leave alone.
  defp place(play, value) do
    case selected(play) do
      [] ->
        play

      positions ->
        %{board: board, refusals: refusals} =
          Sudoku.Game.place!(play.board, positions, value)

        refused = MapSet.new(refusals, fn {position, _reason} -> position end)

        %{play | board: board}
        # A confirmed digit supersedes any pencil marks in that cell.
        |> drop_marks(Enum.reject(positions, &MapSet.member?(refused, &1)))
        |> refresh_solution_count()
    end
  end

  # Across a selection the digit toggles as a group: it goes onto every
  # eligible cell unless they all carry it already, in which case it comes off
  # all of them. Toggling cell by cell would just scramble a mixed selection.
  defp toggle_marks(play, field, digit) do
    positions = Enum.filter(selected(play), &markable?(play, &1))

    if positions == [] do
      play
    else
      marks = Map.fetch!(play, field)
      remove? = Enum.all?(positions, fn position -> digit in marks_for(marks, position) end)

      marks =
        Enum.reduce(positions, marks, fn position, marks ->
          current = marks_for(marks, position)

          updated =
            if remove?, do: MapSet.delete(current, digit), else: MapSet.put(current, digit)

          put_marks(marks, position, updated)
        end)

      Map.put(play, field, marks)
    end
  end

  defp clear_marks(play, field) do
    marks =
      Enum.reduce(selected(play), Map.fetch!(play, field), fn position, marks ->
        Map.delete(marks, Position.key(position))
      end)

    Map.put(play, field, marks)
  end

  defp drop_marks(play, positions) do
    keys = Enum.map(positions, &Position.key/1)

    %{
      play
      | corner_marks: Map.drop(play.corner_marks, keys),
        center_marks: Map.drop(play.center_marks, keys)
    }
  end

  # Marks describe what *might* go in an empty cell, so a filled or given cell
  # has nothing to mark.
  defp markable?(play, position) do
    case Board.cell_at(play.board, position) do
      nil -> false
      cell -> not cell.given and is_nil(cell.value)
    end
  end

  defp marks_for(marks, position), do: Map.get(marks, Position.key(position), MapSet.new())

  defp put_marks(marks, position, set) do
    if MapSet.size(set) == 0,
      do: Map.delete(marks, Position.key(position)),
      else: Map.put(marks, Position.key(position), set)
  end

  defp marks_field(:corner), do: :corner_marks
  defp marks_field(:center), do: :center_marks

  # ── Undo / redo ──────────────────────────────────────────────────────────

  # Runs a change and records the state it replaced, but only when something
  # actually moved — otherwise a stray keypress would cost an Undo step.
  defp mutate(play, fun) do
    before = snapshot(play)
    updated = fun.(play)

    if snapshot(updated) == before do
      updated
    else
      %{
        updated
        | history: [before | Enum.take(updated.history, @history_limit - 1)],
          future: []
      }
      |> forget_check()
      |> touch()
    end
  end

  defp snapshot(play) do
    %{
      cells: play.board.cells,
      corner_marks: play.corner_marks,
      center_marks: play.center_marks
    }
  end

  defp restore(play, snap) do
    %{
      play
      | board: %{play.board | cells: snap.cells, status: Board.status(snap.cells)},
        corner_marks: snap.corner_marks,
        center_marks: snap.center_marks
    }
    |> refresh_solution_count()
    |> forget_check()
    |> touch()
  end

  # ── Modes ────────────────────────────────────────────────────────────────

  # While a puzzle is being entered by hand every digit is a given, so the mark
  # modes have nothing to write and the modifier keys fall back to Normal.
  defp resolve_mode(play, override) do
    cond do
      manual_entry?(play) -> :normal
      is_nil(override) -> play.input_mode
      true -> override
    end
  end

  defp manual_entry?(play), do: play.mode == :manual_entry

  defp next_mode(:normal), do: :corner
  defp next_mode(:corner), do: :center
  defp next_mode(:center), do: :highlight
  defp next_mode(:highlight), do: :normal

  defp highlight(play, digit) do
    highlighted = if play.highlighted_number == digit, do: nil, else: digit
    %{play | highlighted_number: highlighted}
  end

  # ── Check ────────────────────────────────────────────────────────────────

  # Checks the entries so far against the puzzle's own solution, rather than
  # only spotting a contradiction once two entries collide.
  defp check(play) do
    case wrong_entries(play.board) do
      # No solution to compare against, so the previous verdict's highlights
      # mean nothing — carrying them over would point at innocent cells.
      :unsolvable -> %{play | check: :unsolvable, check_errors: MapSet.new()}
      wrong -> %{play | check: :checked, check_errors: wrong}
    end
  end

  # Solves from the givens alone — solving from the current board would fail
  # the moment a wrong entry made it unsolvable, which is exactly when you
  # want an answer.
  defp wrong_entries(board) do
    givens = board.cells |> Puzzle.encode() |> Puzzle.decode()

    case Solver.solve(givens) do
      :error ->
        :unsolvable

      {:ok, solution} ->
        for cell <- board.cells,
            not cell.given,
            not is_nil(cell.value),
            solution[{cell.row, cell.col}] != cell.value,
            into: MapSet.new() do
          {cell.row, cell.col}
        end
    end
  end

  defp forget_check(play), do: %{play | check: nil, check_errors: MapSet.new()}

  # ── Manual entry ─────────────────────────────────────────────────────────

  defp refresh_solution_count(play) do
    if manual_entry?(play),
      do: %{play | solution_count: count_solutions(play.board)},
      else: play
  end

  defp count_solutions(board), do: Solver.count_solutions(board.cells, 2)

  # ── Board ────────────────────────────────────────────────────────────────

  defp board_from(%Board{} = board, _difficulty), do: board

  defp board_from(cells, difficulty) when is_list(cells),
    do: Board.new(cells, difficulty: difficulty)

  # ── Derived fields ───────────────────────────────────────────────────────

  defp derive(play) do
    %{
      play
      | blocked_cells: blocked_cells(play.highlighted_number, play.board),
        remaining_counts: remaining_counts(play.board)
    }
  end

  # Every square the highlighted digit cannot go in: the ones already holding
  # it, and everything those squares see.
  defp blocked_cells(nil, _board), do: MapSet.new()

  defp blocked_cells(digit, board) do
    board.cells
    |> Enum.filter(&(&1.value == digit))
    |> Enum.reduce(MapSet.new(), fn src, blocked ->
      position = {src.row, src.col}

      position
      |> Position.peers()
      |> MapSet.put(position)
      |> MapSet.union(blocked)
    end)
  end

  # How many of each digit are still to be placed.
  defp remaining_counts(board) do
    placed = board.cells |> Enum.map(& &1.value) |> Enum.frequencies()
    Map.new(1..9, fn digit -> {digit, 9 - Map.get(placed, digit, 0)} end)
  end

  # ── Small change ─────────────────────────────────────────────────────────

  defp selected(play), do: MapSet.to_list(play.selection)

  defp cursor(play), do: play.cursor || {0, 0}

  defp all_positions, do: MapSet.new(for row <- 0..8, col <- 0..8, do: {row, col})

  defp toggle_member(set, member) do
    if MapSet.member?(set, member), do: MapSet.delete(set, member), else: MapSet.put(set, member)
  end

  # Counts the changes worth writing down. A caller that mirrors the play
  # somewhere else — a browser's local storage, say — compares this before and
  # after an intent instead of guessing which intents matter.
  defp touch(play), do: %{play | revision: play.revision + 1}
end
