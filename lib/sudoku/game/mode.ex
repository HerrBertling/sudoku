defmodule Sudoku.Game.Mode do
  @moduledoc """
  Whether a puzzle is being played or still being entered by hand.

  Not to be confused with **input mode**, which is what a typed digit means
  right now — Normal, Corner, Centre or Highlight. This one is the coarser
  question: is there a puzzle here yet?

  See `Sudoku.Game.Difficulty` for why these live in a type.
  """

  use Ash.Type.Enum, values: [:playing, :manual_entry]
end
