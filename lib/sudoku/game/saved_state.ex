defmodule Sudoku.Game.SavedState do
  @moduledoc """
  The saved shape of a **play**: what survives when nobody is looking at the
  board, how it is written down, how it is read back, and what version it is.

  A play holds a great deal that belongs to the sitting rather than to the game
  — the selection, the undo history, the last Check, which digit is highlighted.
  None of that is worth keeping. What is worth keeping is the board's cells and
  difficulty, whether the puzzle is still being entered by hand, the pencil
  marks, and the clock. That list is this struct, and it is the only place it is
  written down.

  ## Two adapters, one definition

  The same saved state goes to two places, so this module has one pair of
  functions per seam and the callers have no encoding of their own:

    * the browser — `to_payload/1` and `from_payload/1`, an opaque blob
      `localStorage` keeps between visits;
    * SQLite — `to_saved_puzzle_attrs/1` and `from_saved_puzzle/1`, the columns
      of a **saved puzzle**.

  Both were previously hand-written at four call sites in the LiveView, in two
  different shapes, and the two had already drifted: `mode` went out as an atom
  and came back compared as a string, `difficulty` came back through
  `String.to_existing_atom/1`, and the version number the payload carried was
  never checked in Elixir at all. Encoding and decoding are inverses here, and
  the tests say so.

  A third pair, `from_play/1` and `to_play/1`, converts to and from the live
  `Sudoku.Game.Play`, and `resume_intent/1` exists because restoring from the
  browser *adopts* a board into the play already on screen — keeping this
  sitting's clock and selection — rather than replacing it, which is what
  loading a saved puzzle does.

  ## The version lives here

  `to_payload/1` stamps `@version` on what it writes and `from_payload/1` is the
  only thing that judges it. The browser stores the blob and hands it back
  untouched; it has no version constant of its own to fall out of step with this
  one. An unknown version is refused rather than guessed at, and the caller is
  expected to throw that payload away.

  A payload with no version at all is read as the shape that predates the check
  — it is the same shape, and refusing it would discard saves needlessly.

  The browser payload deliberately does *not* carry the clock: a refresh has
  always started the timer again, and only a saved puzzle remembers elapsed
  time.
  """

  alias Sudoku.Game.Cell
  alias Sudoku.Game.Difficulty
  alias Sudoku.Game.Mode
  alias Sudoku.Game.PencilMarks
  alias Sudoku.Game.Play
  alias Sudoku.Game.Puzzle

  # Bumped when the saved shape changes in a way an older payload cannot be read
  # as. Payloads at any other version are discarded rather than migrated.
  @version 2

  @cell_count 81

  defstruct cells: [],
            difficulty: :custom,
            mode: :playing,
            corner_marks: %{},
            center_marks: %{},
            elapsed: 0

  @type t :: %__MODULE__{
          cells: [Cell.t()],
          difficulty: :easy | :medium | :hard | :custom,
          mode: :playing | :manual_entry,
          corner_marks: PencilMarks.t(),
          center_marks: PencilMarks.t(),
          elapsed: non_neg_integer()
        }

  @typedoc "Why a payload could not be read."
  @type refusal :: :unsupported_version | :malformed

  @doc "The version `to_payload/1` stamps on what it writes."
  @spec version() :: pos_integer()
  def version, do: @version

  # ── The play ─────────────────────────────────────────────────────────────

  @doc "What is worth keeping of a play."
  @spec from_play(Play.t()) :: t()
  def from_play(%Play{} = play) do
    %__MODULE__{
      cells: play.board.cells,
      difficulty: play.board.difficulty,
      mode: play.mode,
      corner_marks: play.corner_marks,
      center_marks: play.center_marks,
      elapsed: play.elapsed
    }
  end

  @doc """
  A fresh play over this saved state — a puzzle picked up again, clock and all.
  """
  @spec to_play(t()) :: Play.t()
  def to_play(%__MODULE__{} = state) do
    Play.new(state.cells,
      difficulty: state.difficulty,
      mode: state.mode,
      corner_marks: state.corner_marks,
      center_marks: state.center_marks,
      elapsed: state.elapsed
    )
  end

  @doc """
  The intent that adopts this saved state into a play already in progress,
  leaving that sitting's clock and selection alone.
  """
  @spec resume_intent(t()) :: {:resume, [Cell.t()], keyword()}
  def resume_intent(%__MODULE__{} = state) do
    {:resume, state.cells,
     difficulty: state.difficulty,
     mode: state.mode,
     corner_marks: state.corner_marks,
     center_marks: state.center_marks}
  end

  # ── Adapter: the browser ─────────────────────────────────────────────────

  @doc """
  The saved state as the blob the browser keeps, version and all. String keys
  throughout, so what JavaScript hands back is exactly what went out.
  """
  @spec to_payload(t()) :: map()
  def to_payload(%__MODULE__{} = state) do
    %{
      "version" => @version,
      "difficulty" => Atom.to_string(state.difficulty),
      "mode" => Atom.to_string(state.mode),
      "cells" => Enum.map(state.cells, &cell_to_map/1),
      "corner_marks" => PencilMarks.encode(state.corner_marks),
      "center_marks" => PencilMarks.encode(state.center_marks)
    }
  end

  @doc """
  Reads a blob the browser handed back.

  Returns `{:error, :unsupported_version}` for a payload written by a different
  version of the game and `{:error, :malformed}` for one that is not 81 cells;
  either way the caller should discard it. Marks that cannot be read are dropped
  cell by cell rather than failing the whole payload.
  """
  @spec from_payload(map()) :: {:ok, t()} | {:error, refusal()}
  def from_payload(payload) when is_map(payload) do
    with :ok <- check_version(payload),
         {:ok, cells} <- cells_from(payload["cells"]) do
      {:ok,
       %__MODULE__{
         cells: cells,
         difficulty: difficulty(payload["difficulty"]),
         mode: mode(payload["mode"]),
         corner_marks: PencilMarks.decode(payload["corner_marks"]),
         center_marks: PencilMarks.decode(payload["center_marks"])
       }}
    end
  end

  def from_payload(_payload), do: {:error, :malformed}

  # A payload from before the server checked versions carries the same fields,
  # so it is read rather than thrown away.
  defp check_version(%{"version" => @version}), do: :ok
  defp check_version(%{"version" => _other}), do: {:error, :unsupported_version}
  defp check_version(_payload), do: :ok

  defp cells_from(cells) when is_list(cells) and length(cells) == @cell_count do
    Enum.reduce_while(cells, {:ok, []}, fn cell, {:ok, read} ->
      case cell_from_map(cell) do
        {:ok, cell} -> {:cont, {:ok, [cell | read]}}
        :error -> {:halt, {:error, :malformed}}
      end
    end)
    |> case do
      {:ok, cells} -> {:ok, Enum.reverse(cells)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp cells_from(_cells), do: {:error, :malformed}

  defp cell_to_map(%{row: row, col: col, value: value, given: given, valid: valid}) do
    %{"row" => row, "col" => col, "value" => value, "given" => given, "valid" => valid}
  end

  defp cell_from_map(%{"row" => row, "col" => col} = cell)
       when row in 0..8 and col in 0..8 do
    case cell["value"] do
      value when is_nil(value) or (is_integer(value) and value in 1..9) ->
        {:ok,
         %Cell{
           row: row,
           col: col,
           value: value,
           given: cell["given"] == true,
           valid: cell["valid"] != false
         }}

      _value ->
        :error
    end
  end

  defp cell_from_map(_cell), do: :error

  # ── Adapter: SQLite ──────────────────────────────────────────────────────

  @doc """
  The saved state as the input the `:save` action takes.

  The puzzle's definition is derived here rather than carried: a save keeps the
  givens beside the working state so it can always be restarted, and
  `Sudoku.Game.Puzzle` owns what "the givens" means.

  `mode` goes along even though nothing stores it, because the action is what
  decides whether a play in that mode may be saved at all.
  """
  @spec to_saved_puzzle_attrs(t()) :: map()
  def to_saved_puzzle_attrs(%__MODULE__{} = state) do
    %{
      difficulty: state.difficulty,
      mode: state.mode,
      givens: Puzzle.encode(state.cells),
      cells: state.cells,
      corner_marks: PencilMarks.encode(state.corner_marks),
      center_marks: PencilMarks.encode(state.center_marks),
      elapsed_seconds: state.elapsed
    }
  end

  @doc """
  The saved state a stored **saved puzzle** holds.

  A save is always a puzzle being played rather than one being entered, so it
  comes back in `:playing` mode.
  """
  @spec from_saved_puzzle(struct()) :: t()
  def from_saved_puzzle(saved) do
    %__MODULE__{
      cells: saved.cells,
      difficulty: difficulty(saved.difficulty),
      mode: :playing,
      corner_marks: PencilMarks.decode(saved.corner_marks),
      center_marks: PencilMarks.decode(saved.center_marks),
      elapsed: saved.elapsed_seconds || 0
    }
  end

  # ── Atoms crossing the seam ──────────────────────────────────────────────

  # Storage speaks strings and the game speaks atoms; the types know how to get
  # from one to the other, so this only has to say what happens when they
  # cannot. Anything unrecognised falls back rather than raising: a save is not
  # worth losing over a word the game no longer uses, and
  # `String.to_existing_atom/1` on whatever a browser hands back is a way to
  # crash a session.
  defp difficulty(value), do: known(Difficulty, value, :custom)
  defp mode(value), do: known(Mode, value, :playing)

  defp known(type, value, fallback) when is_atom(value) or is_binary(value) do
    case type.match(value) do
      {:ok, matched} -> matched
      :error -> fallback
    end
  end

  # A payload can hand back anything at all, including something `to_string/1`
  # would raise on.
  defp known(_type, _value, fallback), do: fallback
end
