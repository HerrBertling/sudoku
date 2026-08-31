defmodule Sudoku.Game.Solver do
  @moduledoc """
  Backtracking Sudoku solver that can count solutions up to a given limit.
  Uses constraint propagation with MRV (minimum remaining values) heuristic.
  """

  @all_values MapSet.new(1..9)

  @doc """
  Counts the number of solutions for a grid, stopping early once `limit` is reached.

  The grid is a list of 9 lists, each containing 9 integers (1-9) or 0 for empty.
  Returns an integer between 0 and `limit`.
  """
  def count_solutions(grid, limit \\ 2) do
    grid_map = grid_to_map(grid)
    possibles = initial_possibles(grid_map)
    do_count(possibles, 0, limit)
  end

  @doc """
  Solves a grid, returning `{:ok, solution}` where solution maps `{row, col}`
  to its digit, or `:error` if the grid cannot be completed.

  Stops at the first solution found, so on a puzzle with more than one it
  returns whichever the search reaches first.
  """
  def solve(grid) do
    grid_map = grid_to_map(grid)
    placed = for {position, value} <- grid_map, value != 0, into: %{}, do: {position, value}

    case do_solve(initial_possibles(grid_map), placed) do
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

    box_r = div(row, 3) * 3
    box_c = div(col, 3) * 3

    peers =
      for(c <- 0..8, c != col, do: {row, c}) ++
        for(r <- 0..8, r != row, do: {r, col}) ++
        for(
          r <- box_r..(box_r + 2),
          c <- box_c..(box_c + 2),
          {r, c} != {row, col},
          do: {r, c}
        )

    Enum.reduce(peers, possibles, fn peer, acc ->
      case Map.fetch(acc, peer) do
        {:ok, set} -> Map.put(acc, peer, MapSet.delete(set, val))
        :error -> acc
      end
    end)
  end

  defp initial_possibles(grid_map) do
    for r <- 0..8, c <- 0..8, Map.get(grid_map, {r, c}) == 0, into: %{} do
      {{r, c}, possible_values(grid_map, r, c)}
    end
  end

  defp possible_values(grid_map, row, col) do
    box_r = div(row, 3) * 3
    box_c = div(col, 3) * 3

    used =
      for(c <- 0..8, do: Map.get(grid_map, {row, c})) ++
        for(r <- 0..8, do: Map.get(grid_map, {r, col})) ++
        for(r <- box_r..(box_r + 2), c <- box_c..(box_c + 2), do: Map.get(grid_map, {r, c}))

    MapSet.difference(@all_values, MapSet.new(used))
  end

  defp grid_to_map(grid) do
    for {row_vals, r} <- Enum.with_index(grid),
        {val, c} <- Enum.with_index(row_vals),
        into: %{} do
      {{r, c}, val}
    end
  end
end
