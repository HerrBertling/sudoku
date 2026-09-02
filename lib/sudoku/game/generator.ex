defmodule Sudoku.Game.Generator do
  @moduledoc """
  Generates Sudoku puzzles by starting from a known valid complete board,
  applying Sudoku-preserving transformations, then removing cells based on difficulty.
  """

  alias Sudoku.Game.Cell
  alias Sudoku.Game.Solver

  @base_board [
    [5, 3, 4, 6, 7, 8, 9, 1, 2],
    [6, 7, 2, 1, 9, 5, 3, 4, 8],
    [1, 9, 8, 3, 4, 2, 5, 6, 7],
    [8, 5, 9, 7, 6, 1, 4, 2, 3],
    [4, 2, 6, 8, 5, 3, 7, 9, 1],
    [7, 1, 3, 9, 2, 4, 8, 5, 6],
    [9, 6, 1, 5, 3, 7, 2, 8, 4],
    [2, 8, 7, 4, 1, 9, 6, 3, 5],
    [3, 4, 5, 2, 8, 6, 1, 7, 9]
  ]

  @cells_to_remove %{easy: 30, medium: 45, hard: 55}

  def generate(difficulty \\ :medium) do
    board = shuffle_board(@base_board)
    removals = Map.get(@cells_to_remove, difficulty, 45)
    remove_cells(board, removals)
  end

  defp shuffle_board(board) do
    board
    |> permute_digits()
    |> swap_bands(:row)
    |> swap_bands(:col)
    |> swap_within_bands(:row)
    |> swap_within_bands(:col)
  end

  defp permute_digits(board) do
    mapping = Enum.zip(1..9, Enum.shuffle(1..9)) |> Map.new()
    Enum.map(board, fn row -> Enum.map(row, &Map.get(mapping, &1)) end)
  end

  defp swap_bands(board, :row) do
    board
    |> Enum.chunk_every(3)
    |> Enum.shuffle()
    |> Enum.concat()
  end

  defp swap_bands(board, :col) do
    board |> transpose() |> swap_bands(:row) |> transpose()
  end

  defp swap_within_bands(board, :row) do
    board
    |> Enum.chunk_every(3)
    |> Enum.flat_map(&Enum.shuffle/1)
  end

  defp swap_within_bands(board, :col) do
    board |> transpose() |> swap_within_bands(:row) |> transpose()
  end

  defp transpose(board) do
    board |> Enum.zip() |> Enum.map(&Tuple.to_list/1)
  end

  # The shuffling above is naturally row-shaped; from here on the puzzle is a
  # flat list of cells, which is what the solver and the rest of the app speak.
  defp remove_cells(board, target_removals) do
    cells =
      for {row_vals, row} <- Enum.with_index(board),
          {val, col} <- Enum.with_index(row_vals) do
        %Cell{row: row, col: col, value: val, given: true, valid: true}
      end

    shuffled = Enum.shuffle(for r <- 0..8, c <- 0..8, do: {r, c})

    remove_one_at_a_time(cells, shuffled, 0, target_removals)
  end

  defp remove_one_at_a_time(cells, _positions, removed, target) when removed >= target, do: cells
  defp remove_one_at_a_time(cells, [], _removed, _target), do: cells

  defp remove_one_at_a_time(cells, [{r, c} | rest], removed, target) do
    candidate =
      List.replace_at(cells, r * 9 + c, %Cell{
        row: r,
        col: c,
        value: nil,
        given: false,
        valid: true
      })

    if Solver.count_solutions(candidate, 2) == 1 do
      remove_one_at_a_time(candidate, rest, removed + 1, target)
    else
      remove_one_at_a_time(cells, rest, removed, target)
    end
  end
end
