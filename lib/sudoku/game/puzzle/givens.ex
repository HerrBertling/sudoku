defmodule Sudoku.Game.Puzzle.Givens do
  @moduledoc """
  A puzzle's definition as `Sudoku.Game.Puzzle` encodes it: 81 characters, one
  per square, `"0"` where the puzzle leaves a square empty.

  The shape was written out twice — once on the board that decodes it, once on
  the row that stores it — and the two had to agree by hand. Now the type is
  the agreement.
  """

  use Ash.Type.NewType, subtype_of: :string, constraints: [match: ~r/^[0-9]{81}$/]
end
