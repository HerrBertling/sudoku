defmodule Sudoku.Game.Solver do
  @moduledoc """
  Backtracking Sudoku solver that can count solutions up to a given limit.
  Uses constraint propagation with MRV (minimum remaining values) heuristic.

  Both entry points take the same thing every other part of the app passes
  around: a list of `%Sudoku.Game.Cell{}`. A cell whose `value` is `nil` is a
  square still to be filled; the solver ignores every other field, so the same
  list works whether it came from a puzzle, a board mid-play or a generator.
  """

  alias Sudoku.Game.Cell
  alias Sudoku.Game.Position

  @all_values MapSet.new(1..9)
  @positions for row <- 0..8, col <- 0..8, do: {row, col}

  @empty_board for position <- @positions, into: %{}, do: {position, nil}

  @doc """
  Counts the number of solutions for `cells`, stopping early once `limit` is
  reached. Returns an integer between 0 and `limit`.
  """
  def count_solutions(cells, limit \\ 2) do
    cells
    |> digits()
    |> initial_possibles()
    |> do_count(0, limit)
  end

  @doc """
  Solves `cells`, returning `{:ok, solution}` where solution maps `{row, col}`
  to its digit, or `:error` if the cells cannot be completed.

  Stops at the first solution found, so on a puzzle with more than one it
  returns whichever the search reaches first.
  """
  def solve(cells) do
    digits = digits(cells)
    placed = for {position, digit} <- digits, not is_nil(digit), into: %{}, do: {position, digit}

    case do_solve(initial_possibles(digits), placed) do
      nil -> :error
      solution -> {:ok, solution}
    end
  end

  defp do_solve(possibles, placed) do
    case pick_most_constrained(possibles) do
      nil ->
        placed

      {{row, col}, candidates} ->
        Enum.find_value(candidates, fn value ->
          do_solve(propagate(possibles, row, col, value), Map.put(placed, {row, col}, value))
        end)
    end
  end

  defp do_count(possibles, count, limit) do
    case pick_most_constrained(possibles) do
      nil ->
        count + 1

      {{row, col}, candidates} ->
        Enum.reduce_while(candidates, count, fn val, acc ->
          new_possibles = propagate(possibles, row, col, val)
          new_count = do_count(new_possibles, acc, limit)

          if new_count >= limit, do: {:halt, new_count}, else: {:cont, new_count}
        end)
    end
  end

  # Pick the empty cell with the fewest remaining candidates (MRV heuristic)
  defp pick_most_constrained(possibles) when map_size(possibles) == 0, do: nil

  defp pick_most_constrained(possibles) do
    Enum.min_by(possibles, fn {_pos, candidates} -> MapSet.size(candidates) end)
  end

  # After placing `val` at (row, col), remove it from peers and remove the cell itself
  defp propagate(possibles, row, col, val) do
    possibles = Map.delete(possibles, {row, col})

    Enum.reduce(Position.peers({row, col}), possibles, fn peer, acc ->
      case Map.fetch(acc, peer) do
        {:ok, set} -> Map.put(acc, peer, MapSet.delete(set, val))
        :error -> acc
      end
    end)
  end

  # The board as a map from position to digit, `nil` where the square is still
  # empty. Every position is present rather than only the filled ones: a map of
  # 32 keys or fewer is a flat map, which the runtime searches key by key, and
  # the candidate pass below looks up 20 peers for every empty square. Keeping
  # the map dense measured a third faster than keeping it sparse.
  defp digits(cells) do
    Enum.reduce(cells, @empty_board, fn
      %Cell{value: nil}, board -> board
      %Cell{row: row, col: col, value: value}, board -> Map.put(board, {row, col}, value)
    end)
  end

  # What each empty square could still hold, given what its peers already show.
  defp initial_possibles(digits) do
    for {position, nil} <- digits, into: %{}, do: {position, possible_values(digits, position)}
  end

  defp possible_values(digits, position) do
    used = for peer <- Position.peers(position), do: Map.get(digits, peer)

    MapSet.difference(@all_values, MapSet.new(used))
  end
end
