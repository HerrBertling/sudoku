defmodule Sudoku.Game.Board.Changes.DealPuzzle do
  @moduledoc """
  Deals a fresh puzzle at the requested difficulty onto the board being
  created.

  The generator hands back cells; the action's job is to put them on the
  changeset and let Ash build the struct.
  """

  use Ash.Resource.Change

  alias Sudoku.Game.Board
  alias Sudoku.Game.Generator

  @impl true
  def change(changeset, _opts, _context) do
    difficulty = Ash.Changeset.get_argument(changeset, :difficulty)
    cells = Generator.generate(difficulty)

    changeset
    |> Ash.Changeset.force_change_attribute(:cells, cells)
    |> Ash.Changeset.force_change_attribute(:status, Board.status(cells))
    |> Ash.Changeset.force_change_attribute(:difficulty, difficulty)
  end
end
