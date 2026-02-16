defmodule Sudoku.Game.Validator do
  @moduledoc """
  Validates Sudoku board state by checking row, column, and box constraints.
  """

  def validate_cells(cells) do
    conflicts = find_all_conflicts(cells)

    Enum.map(cells, fn cell ->
      %{cell | valid: cell.value == nil or {cell.row, cell.col} not in conflicts}
    end)
  end

  defp find_all_conflicts(cells) do
    filled = Enum.filter(cells, & &1.value)

    row_conflicts = find_group_conflicts(filled, & &1.row)
    col_conflicts = find_group_conflicts(filled, & &1.col)
    box_conflicts = find_group_conflicts(filled, fn c -> div(c.row, 3) * 3 + div(c.col, 3) end)

    MapSet.union(row_conflicts, col_conflicts) |> MapSet.union(box_conflicts)
  end

  defp find_group_conflicts(cells, group_fn) do
    cells
    |> Enum.group_by(group_fn)
    |> Enum.flat_map(fn {_group, group_cells} ->
      group_cells
      |> Enum.group_by(& &1.value)
      |> Enum.flat_map(fn
        {_value, [_single]} -> []
        {_value, duplicates} -> Enum.map(duplicates, &{&1.row, &1.col})
      end)
    end)
    |> MapSet.new()
  end
end
