defmodule Sudoku.Game.Board do
  @moduledoc """
  The 81 cells as a playable whole, plus its difficulty and whether it is
  finished.

  A board is never persisted — it lives for as long as somebody is looking at
  it, and storage keeps the puzzle's givens and the working state instead. So
  this is a resource that exists only to model behaviour: actions over a
  struct, with `Ash.DataLayer.Simple` underneath and nothing to read back.

  ## Interface

  Construction and the one write:

    * `new/2` — a board from cells, or from a puzzle's givens.
    * `place/3` — write a digit at one position or many, in a single pass.

  Questions a caller can ask a board it is holding:

    * `cell_at/2` — the cell at a position.
    * `status/1` — the completion rule, applied to a list of cells.
    * `complete?/1` — whether this board is finished.

  Boards reach the rest of the app through `Sudoku.Game`, which is where a
  caller outside the domain should go: `new_game!/1` deals a puzzle,
  `blank_board!/0` and `board_from_givens!/1` build one from a puzzle's
  definition, and `place!/3` writes to one. Those are create actions, so the
  attributes' constraints hold for every board the domain hands out. `new/2`
  stays the in-process constructor the other domain modules build on, where
  there is nothing to validate and no changeset to pay for.

  The queries are plain functions on purpose: a renderer asks `complete?/1`
  and `cell_at/2` on every frame, and a predicate should not cost an action.

  ## Placing a digit

  `place/3` takes a **position** or a list of them and writes `value` to all of
  them at once. A sweep across a selection is one call, one pass of
  `Sudoku.Game.Validator`, and one status derivation, however many cells are
  involved.

  It never fails. Some squares cannot take a digit — a given is part of the
  puzzle, and a finished board is finished — and a sweep across a selection is
  *expected* to run into them, so refusing the whole move would be wrong. It
  writes what it can and hands back what it would not touch, with a reason per
  position, so a caller can report them, ignore them, or treat any of them as
  an error of its own.
  """

  use Ash.Resource,
    domain: Sudoku.Game,
    data_layer: Ash.DataLayer.Simple

  alias Sudoku.Game.Cell
  alias Sudoku.Game.Puzzle
  alias Sudoku.Game.Validator

  # A grid with no givens at all — where entering a puzzle by hand starts.
  @blank_givens String.duplicate("0", 81)

  @typedoc """
  A square's coordinates, as everywhere else in the domain.
  """
  @type position :: {0..8, 0..8}

  @typedoc """
  Why `place/3` left a position alone:

    * `:complete` — the board is already finished, so nothing may be written.
    * `:given` — the square is a given and belongs to the puzzle.
    * `:no_cell` — the position is not on this board.
  """
  @type reason :: :complete | :given | :no_cell

  @type refusal :: {position(), reason()}

  actions do
    create :new_game do
      description "A freshly generated puzzle at the requested difficulty."
      accept []

      argument :difficulty, :atom do
        default :medium
        constraints one_of: [:easy, :medium, :hard]
      end

      change Sudoku.Game.Board.Changes.DealPuzzle
    end

    create :from_givens do
      description "A board over a puzzle's givens and nothing else — no entries, no marks."
      accept []

      argument :givens, :string do
        default @blank_givens
        constraints match: ~r/^[0-9]{81}$/
      end

      argument :difficulty, :atom do
        default :custom
        constraints one_of: [:easy, :medium, :hard, :custom]
      end

      change Sudoku.Game.Board.Changes.DecodeGivens
    end

    action :place, :map do
      # `instance_of` is deliberately left off the board field. It would make
      # the return value "loadable", and Ash then hands the bare result map to
      # `Ash.Type.Map.load/4`, which only accepts a list — an upstream bug as
      # of ash 3.27. Nothing here needs loading; the constraint only described
      # a shape the `run` below already guarantees.
      constraints fields: [
                    board: [type: :struct],
                    refusals: [type: {:array, :term}]
                  ]

      argument :board, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      argument :positions, {:array, :term}, allow_nil?: false
      argument :value, :integer

      run fn input, _context ->
        {board, refusals} =
          place(input.arguments.board, input.arguments.positions, input.arguments.value)

        {:ok, %{board: board, refusals: refusals}}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :cells, {:array, Cell} do
      allow_nil? false
      default []
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:playing, :complete]
      default :playing
      public? true
    end

    attribute :difficulty, :atom do
      constraints one_of: [:easy, :medium, :hard, :custom]
      default :medium
      public? true
    end
  end

  @doc """
  A board over `cells` — either a list of `Sudoku.Game.Cell` structs or a
  puzzle's givens as a `Sudoku.Game.Puzzle` string.

  The cells are taken as they stand, conflict flags and all; only the
  completion status is derived. Options:

    * `:difficulty` — `:easy`, `:medium`, `:hard` or `:custom` (default
      `:custom`, since a board assembled from cells is usually somebody else's
      puzzle coming back from storage).
  """
  @spec new([Cell.t()] | String.t(), keyword()) :: t()
  def new(cells_or_givens, opts \\ [])

  def new(givens, opts) when is_binary(givens), do: new(Puzzle.decode(givens), opts)

  # The struct only exists once Ash has finished building this module, so it is
  # assembled by name rather than written as a literal.
  def new(cells, opts) when is_list(cells) do
    struct(__MODULE__,
      id: Ash.UUID.generate(),
      cells: cells,
      status: status(cells),
      difficulty: Keyword.get(opts, :difficulty, :custom)
    )
  end

  @doc """
  Writes `value` — a digit, or `nil` to empty the square — at `positions`,
  which is one `{row, col}` position or a list of them.

  Returns `{board, refusals}`. Every position the board would not write to is
  in `refusals` as `{position, reason}`; the rest are written, validated and
  reflected in the board's status in a single pass.

      {board, []} = Board.place(board, {0, 0}, 5)
      {board, [{{0, 3}, :given}]} = Board.place(board, [{0, 1}, {0, 3}], 5)
  """
  @spec place(t(), position() | [position()], 1..9 | nil) :: {t(), [refusal()]}
  def place(board, positions, value) when is_struct(board, __MODULE__) do
    positions = List.wrap(positions)

    if complete?(board) do
      {board, Enum.map(positions, &{&1, :complete})}
    else
      {writable, refusals} = sort_positions(board, positions)
      {write(board, writable, value), refusals}
    end
  end

  @doc """
  The cell at `position`, or `nil` if the position is not on this board.
  """
  @spec cell_at(t(), position()) :: Cell.t() | nil
  def cell_at(board, {row, col}) when is_struct(board, __MODULE__) do
    Enum.find(board.cells, &(&1.row == row and &1.col == col))
  end

  @doc """
  Whether this board is finished.
  """
  @spec complete?(t()) :: boolean()
  def complete?(board) when is_struct(board, __MODULE__), do: board.status == :complete

  @doc """
  The completion rule: a grid is complete once every square holds a digit and
  no square conflicts with another.

  Takes cells rather than a board so that cells arriving from somewhere else —
  storage, an undo step — can be judged before they are wrapped in one.
  """
  @spec status([Cell.t()]) :: :playing | :complete
  def status(cells) when is_list(cells) do
    if Enum.all?(cells, & &1.value) and Enum.all?(cells, & &1.valid),
      do: :complete,
      else: :playing
  end

  # Splits the requested positions into the ones this board will write and the
  # ones it refuses, so the write itself sees only squares it can touch.
  defp sort_positions(board, positions) do
    by_position = Map.new(board.cells, &{{&1.row, &1.col}, &1})

    {writable, refusals} =
      Enum.reduce(positions, {[], []}, fn position, {writable, refusals} ->
        case Map.get(by_position, position) do
          nil -> {writable, [{position, :no_cell} | refusals]}
          %{given: true} -> {writable, [{position, :given} | refusals]}
          _cell -> {[position | writable], refusals}
        end
      end)

    {MapSet.new(writable), Enum.reverse(refusals)}
  end

  # One map over the cells, one validation and one status derivation, whether
  # this is a single digit or a sweep across a selection.
  defp write(board, positions, value) do
    if MapSet.size(positions) == 0 do
      board
    else
      cells =
        board.cells
        |> Enum.map(fn cell ->
          if MapSet.member?(positions, {cell.row, cell.col}),
            do: %{cell | value: value},
            else: cell
        end)
        |> Validator.validate_cells()

      %{board | cells: cells, status: status(cells)}
    end
  end
end
