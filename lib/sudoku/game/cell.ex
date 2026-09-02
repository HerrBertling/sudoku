defmodule Sudoku.Game.Cell do
  @moduledoc """
  Represents a single cell in a 9x9 Sudoku grid.

  Each cell tracks its position (`row`, `col`), its current `value` (1-9 or nil
  if empty), whether it was part of the original puzzle (`given`), and whether
  it currently satisfies Sudoku constraints (`valid`).

  ## Struct Fields

    * `row` - Row index (0-8), required
    * `col` - Column index (0-8), required
    * `value` - The digit in this cell (1-9), or `nil` if empty
    * `given` - `true` if this cell is a pre-filled clue that cannot be edited
    * `valid` - `true` if this cell does not conflict with another cell in the
      same row, column, or 3x3 box

  ## Examples

  An empty, user-editable cell at row 0, column 4:

      iex> %Sudoku.Game.Cell{row: 0, col: 4, value: nil, given: false, valid: true}
      %Sudoku.Game.Cell{row: 0, col: 4, value: nil, given: false, valid: true}

  A pre-filled clue cell with value 7:

      iex> %Sudoku.Game.Cell{row: 2, col: 3, value: 7, given: true, valid: true}
      %Sudoku.Game.Cell{row: 2, col: 3, value: 7, given: true, valid: true}

  A cell with a conflicting value:

      iex> %Sudoku.Game.Cell{row: 1, col: 1, value: 5, given: false, valid: false}
      %Sudoku.Game.Cell{row: 1, col: 1, value: 5, given: false, valid: false}

  Cells know which 3x3 box they belong to (box index 0-8, left-to-right,
  top-to-bottom):

      iex> cell = %Sudoku.Game.Cell{row: 4, col: 7}
      iex> Sudoku.Game.Position.box({cell.row, cell.col})
      5
  """

  use Ash.Resource,
    data_layer: :embedded

  actions do
    default_accept :*
    defaults [:read, create: :*]
  end

  attributes do
    attribute :row, :integer, allow_nil?: false, public?: true, constraints: [min: 0, max: 8]
    attribute :col, :integer, allow_nil?: false, public?: true, constraints: [min: 0, max: 8]
    attribute :value, :integer, public?: true, constraints: [min: 1, max: 9]
    attribute :given, :boolean, default: false, public?: true
    attribute :valid, :boolean, default: true, public?: true
  end
end
