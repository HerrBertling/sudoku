defmodule Sudoku.Game.Puzzle do
  @moduledoc """
  A puzzle's *definition* — its 81 givens — encoded as a string of digits read
  left to right, top to bottom, with `"0"` for a square the puzzle leaves empty.

  This is what makes a puzzle that puzzle, and it never changes while the puzzle
  is played. A player's progress lives on the board's cells instead. Keeping the
  two apart means a saved game can always be wound back to the puzzle it started
  as, no matter what has been written over it.
  """

  alias Sudoku.Game.Cell

  @empty "0"
  @length 81

  @doc """
  The givens of a set of cells, as an #{@length}-character string.

  Only cells flagged `given` contribute; everything the player filled in is
  left empty.
  """
  def encode(cells) do
    cells
    |> Enum.sort_by(&{&1.row, &1.col})
    |> Enum.map_join(fn
      %{given: true, value: value} when not is_nil(value) -> Integer.to_string(value)
      _cell -> @empty
    end)
  end

  @doc """
  A fresh set of cells carrying these givens and nothing else — the puzzle as
  it was before anyone played it.
  """
  def decode(givens) do
    digits = String.graphemes(givens)

    for row <- 0..8, col <- 0..8 do
      value =
        case Enum.at(digits, row * 9 + col) do
          nil -> nil
          @empty -> nil
          digit -> String.to_integer(digit)
        end

      %Cell{row: row, col: col, value: value, given: not is_nil(value), valid: true}
    end
  end

  @doc "How many squares the puzzle fills in for you."
  def given_count(givens),
    do: @length - (givens |> String.graphemes() |> Enum.count(&(&1 == @empty)))

  @doc "How many squares the player has to work out."
  def blank_count(givens), do: @length - given_count(givens)

  @doc "How many of the non-given squares currently hold a value."
  def solved_count(cells) do
    Enum.count(cells, &(not &1.given and not is_nil(&1.value)))
  end

  def length, do: @length
end
