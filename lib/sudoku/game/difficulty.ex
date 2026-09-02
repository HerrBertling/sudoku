defmodule Sudoku.Game.Difficulty do
  @moduledoc """
  How hard a puzzle is: `:easy`, `:medium`, `:hard`, or `:custom` for one
  somebody entered by hand.

  The type owns the list, so the same four words do not have to be spelled out
  on every attribute and argument that uses them. It also casts strings —
  storage and the browser both speak strings, and `match/1` is how they get
  back to atoms without `String.to_existing_atom/1` on input from outside.
  """

  use Ash.Type.Enum, values: [:easy, :medium, :hard, :custom]

  @generated [:easy, :medium, :hard]

  @doc """
  The difficulties the generator can deal.

  `:custom` is not one of them: it is what a hand-entered puzzle gets, and there
  is nothing to generate.
  """
  @spec generated() :: [atom()]
  def generated, do: @generated
end
