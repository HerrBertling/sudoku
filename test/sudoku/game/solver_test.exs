defmodule Sudoku.Game.SolverTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.Puzzle
  alias Sudoku.Game.Solver

  # The solver speaks cells, and a givens string is the shortest way to write a
  # board down in a test. `Puzzle.decode/1` is the app's own translation.
  defp cells(givens), do: Puzzle.decode(givens)

  defp empty_board, do: String.duplicate("0", 81)

  # The puzzle and answer from the Wikipedia "Sudoku" article.
  @wikipedia "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
  @wikipedia_solution "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

  # Row 0 needs a 9 in its last square, and the 9 directly below it forbids one.
  @dead_end "123456780" <> "000000009" <> String.duplicate("0", 63)

  # The same puzzle with one given rubbed out, which leaves two answers.
  @two_solutions "530070000600195000098000060800060003400803001700020006060000280000419005000080009"

  defp to_string_grid(solution) do
    for row <- 0..8, col <- 0..8, into: "", do: Integer.to_string(solution[{row, col}])
  end

  describe "solve/1" do
    test "solves a known puzzle" do
      assert {:ok, solution} = Solver.solve(cells(@wikipedia))
      assert to_string_grid(solution) == @wikipedia_solution
    end

    test "keeps the givens it was handed" do
      assert {:ok, solution} = Solver.solve(cells(@wikipedia))

      for %{row: row, col: col, value: value} <- cells(@wikipedia), not is_nil(value) do
        assert solution[{row, col}] == value
      end
    end

    test "returns :error when no completion exists" do
      assert Solver.solve(cells(@dead_end)) == :error
    end

    test "fills an empty board rather than giving up" do
      assert {:ok, solution} = Solver.solve(cells(empty_board()))
      assert map_size(solution) == 81
    end
  end

  describe "count_solutions/2" do
    test "counts zero for a board that cannot be completed" do
      assert Solver.count_solutions(cells(@dead_end)) == 0
    end

    test "counts one for a proper puzzle" do
      assert Solver.count_solutions(cells(@wikipedia)) == 1
    end

    test "counts two when a given is missing" do
      assert Solver.count_solutions(cells(@two_solutions)) == 2
    end

    test "counts exactly two, not merely at least two, when given room to count further" do
      assert Solver.count_solutions(cells(@two_solutions), 5) == 2
    end

    test "stops at the limit instead of enumerating every solution" do
      # An empty board has billions of completions. Returning 2 promptly is the
      # only way this can finish at all.
      {microseconds, count} =
        :timer.tc(fn -> Solver.count_solutions(cells(empty_board()), 2) end)

      assert count == 2
      assert microseconds < 1_000_000
    end
  end
end
