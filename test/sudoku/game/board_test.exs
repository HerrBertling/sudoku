defmodule Sudoku.Game.BoardTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.Board
  alias Sudoku.Game.Puzzle

  @blank String.duplicate("0", 81)

  # The canonical Wikipedia puzzle and its one solution.
  @givens "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
  @solution "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

  defp cell(board, position), do: Board.cell_at(board, position)
  defp value(board, position), do: cell(board, position).value

  # The solution with `blanks` positions emptied and everything else a given —
  # a board that only needs those squares filled in to be finished.
  defp nearly_solved(blanks) do
    @solution
    |> Puzzle.decode()
    |> Enum.map(fn c ->
      if {c.row, c.col} in blanks, do: %{c | value: nil, given: false}, else: c
    end)
    |> Board.new()
  end

  describe "new/2" do
    test "builds a board from cells" do
      cells = Puzzle.decode(@givens)
      board = Board.new(cells)

      assert board.cells == cells
      assert board.status == :playing
      assert board.difficulty == :custom
      assert is_binary(board.id)
    end

    test "builds a board from a puzzle's givens" do
      board = Board.new(@givens)

      assert board.cells == Puzzle.decode(@givens)
      assert value(board, {0, 0}) == 5
      assert cell(board, {0, 0}).given
      assert value(board, {0, 2}) == nil
      refute cell(board, {0, 2}).given
    end

    test "takes the difficulty it is given" do
      assert Board.new(@givens, difficulty: :hard).difficulty == :hard
    end

    test "mints a fresh id for every board" do
      refute Board.new(@blank).id == Board.new(@blank).id
    end

    test "a board built from a solved grid is already complete" do
      assert Board.new(@solution).status == :complete
      assert Board.complete?(Board.new(@solution))
    end
  end

  describe "cell_at/2" do
    test "finds the cell at a position" do
      board = Board.new(@givens)

      assert %{row: 1, col: 4, value: 9} = Board.cell_at(board, {1, 4})
    end

    test "is nil off the grid" do
      assert Board.cell_at(Board.new(@blank), {9, 0}) == nil
    end
  end

  describe "status/1" do
    test "a grid with an empty square is still being played" do
      cells = Puzzle.decode(@givens)

      assert Board.status(cells) == :playing
    end

    test "a full grid with a conflict is still being played" do
      cells =
        @solution
        |> Puzzle.decode()
        |> Enum.map(fn c -> if {c.row, c.col} == {0, 0}, do: %{c | valid: false}, else: c end)

      assert Board.status(cells) == :playing
    end

    test "a full, conflict-free grid is complete" do
      assert Board.status(Puzzle.decode(@solution)) == :complete
    end
  end

  describe "place/3 at one position" do
    test "writes the digit" do
      {board, refusals} = Board.place(Board.new(@givens), {0, 2}, 4)

      assert refusals == []
      assert value(board, {0, 2}) == 4
    end

    test "nil empties the square again" do
      board = Board.new(@givens)
      {board, []} = Board.place(board, {0, 2}, 4)
      {board, []} = Board.place(board, {0, 2}, nil)

      assert value(board, {0, 2}) == nil
    end

    test "flags a conflict on both squares" do
      # r0c1 is a given 3, so a second 3 in that row collides with it.
      {board, []} = Board.place(Board.new(@givens), {0, 2}, 3)

      refute cell(board, {0, 2}).valid
      refute cell(board, {0, 1}).valid
      assert cell(board, {0, 0}).valid
    end

    test "clears a conflict once the offending digit goes" do
      board = Board.new(@givens)
      {board, []} = Board.place(board, {0, 2}, 3)
      {board, []} = Board.place(board, {0, 2}, nil)

      assert cell(board, {0, 1}).valid
    end
  end

  describe "place/3 across many positions" do
    test "writes the digit everywhere in one call" do
      positions = [{0, 2}, {0, 3}, {0, 5}]
      {board, refusals} = Board.place(Board.new(@givens), positions, 4)

      assert refusals == []
      assert Enum.map(positions, &value(board, &1)) == [4, 4, 4]
    end

    test "a list of one behaves like a bare position" do
      {board, refusals} = Board.place(Board.new(@givens), [{0, 2}], 4)

      assert refusals == []
      assert value(board, {0, 2}) == 4
    end

    test "an empty list of positions changes nothing" do
      board = Board.new(@givens)

      assert Board.place(board, [], 4) == {board, []}
    end

    test "the whole sweep is validated together" do
      # Three 4s down one column: every one of them conflicts with the others,
      # and they are all judged in the same pass.
      {board, []} = Board.place(Board.new(@blank), [{0, 0}, {1, 0}, {2, 0}], 4)

      refute cell(board, {0, 0}).valid
      refute cell(board, {1, 0}).valid
      refute cell(board, {2, 0}).valid
    end
  end

  describe "place/3 refusals" do
    test "a given is refused and named" do
      {board, refusals} = Board.place(Board.new(@givens), {0, 0}, 4)

      assert refusals == [{{0, 0}, :given}]
      assert value(board, {0, 0}) == 5
    end

    test "a sweep writes what it can and reports the rest" do
      # r0c0 and r0c1 are givens; r0c2 and r0c3 are not.
      positions = [{0, 0}, {0, 1}, {0, 2}, {0, 3}]
      {board, refusals} = Board.place(Board.new(@givens), positions, 4)

      assert refusals == [{{0, 0}, :given}, {{0, 1}, :given}]
      assert value(board, {0, 0}) == 5
      assert value(board, {0, 1}) == 3
      assert value(board, {0, 2}) == 4
      assert value(board, {0, 3}) == 4
    end

    test "refusals come back in the order they were asked for" do
      {_board, refusals} = Board.place(Board.new(@givens), [{0, 1}, {0, 2}, {0, 0}], 4)

      assert refusals == [{{0, 1}, :given}, {{0, 0}, :given}]
    end

    test "a position off the grid is refused rather than silently dropped" do
      {board, refusals} = Board.place(Board.new(@blank), [{9, 9}, {0, 0}], 4)

      assert refusals == [{{9, 9}, :no_cell}]
      assert value(board, {0, 0}) == 4
    end

    test "a finished board refuses every position and stays as it is" do
      board = nearly_solved([{8, 8}])
      {board, []} = Board.place(board, {8, 8}, 9)
      assert Board.complete?(board)

      {unchanged, refusals} = Board.place(board, [{8, 8}, {0, 0}], 1)

      assert unchanged == board
      assert refusals == [{{8, 8}, :complete}, {{0, 0}, :complete}]
    end
  end

  describe "completion" do
    test "filling the last square completes the board" do
      board = nearly_solved([{8, 8}])
      refute Board.complete?(board)

      {board, []} = Board.place(board, {8, 8}, 9)

      assert board.status == :complete
      assert Board.complete?(board)
    end

    test "a wrong last digit leaves the board in play" do
      board = nearly_solved([{8, 8}])
      {board, []} = Board.place(board, {8, 8}, 1)

      assert board.status == :playing
      refute Board.complete?(board)
    end

    test "a sweep that fills the last squares completes the board" do
      board = nearly_solved([{8, 6}, {8, 7}, {8, 8}])
      {board, []} = Board.place(board, [{8, 6}, {8, 7}], 1)
      refute Board.complete?(board)

      # Undo that, then finish properly.
      {board, []} = Board.place(board, [{8, 6}, {8, 7}], nil)
      {board, []} = Board.place(board, {8, 6}, 1)
      {board, []} = Board.place(board, {8, 7}, 7)
      {board, []} = Board.place(board, {8, 8}, 9)

      assert Board.complete?(board)
    end

    test "a finished board will not even be rubbed out" do
      board = nearly_solved([{8, 8}])
      {board, []} = Board.place(board, {8, 8}, 9)
      assert Board.complete?(board)

      # Nothing may be written to a finished board — not even a rubbing out.
      {board, refusals} = Board.place(board, {8, 8}, nil)

      assert refusals == [{{8, 8}, :complete}]
      assert Board.complete?(board)
    end
  end

  describe "the create actions" do
    test "new_game deals a puzzle at the requested difficulty" do
      board = Sudoku.Game.new_game!(:hard)

      assert board.difficulty == :hard
      assert board.status == :playing
      assert is_binary(board.id)
      assert length(board.cells) == 81
      assert Enum.any?(board.cells, & &1.given)
      assert Enum.any?(board.cells, &is_nil(&1.value))
    end

    test "new_game gives every board an id of its own" do
      refute Sudoku.Game.new_game!(:easy).id == Sudoku.Game.new_game!(:easy).id
    end

    test "new_game refuses a difficulty the generator does not deal" do
      # Not a difficulty at all, and one that exists but is never generated.
      assert {:error, %Ash.Error.Invalid{}} = Sudoku.Game.new_game(:fiendish)
      assert {:error, %Ash.Error.Invalid{}} = Sudoku.Game.new_game(:custom)
    end

    test "new_game takes the difficulty as a string, as the browser sends it" do
      assert Sudoku.Game.new_game!("hard").difficulty == :hard
    end

    test "blank_board is a grid with nothing on it" do
      board = Sudoku.Game.blank_board!()

      assert board.difficulty == :custom
      assert Enum.all?(board.cells, &(is_nil(&1.value) and not &1.given))
    end

    test "board_from_givens lays the puzzle out and nothing else" do
      board = Sudoku.Game.board_from_givens!(@givens, %{difficulty: :medium})

      assert board.difficulty == :medium
      assert value(board, {0, 0}) == 5
      assert cell(board, {0, 0}).given
      assert value(board, {0, 2}) == nil
    end

    test "board_from_givens refuses a string that is not a puzzle" do
      assert {:error, %Ash.Error.Invalid{}} = Sudoku.Game.board_from_givens("530070000")
    end
  end

  describe "the :place action" do
    test "hands back the board and its refusals" do
      board = Board.new(@givens)

      assert %{board: updated, refusals: [{{0, 0}, :given}]} =
               Sudoku.Game.place!(board, [{0, 0}, {0, 2}], 4)

      assert value(updated, {0, 2}) == 4
    end
  end
end
