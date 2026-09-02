defmodule Sudoku.Game.Board.Changes.DecodeGivens do
  @moduledoc """
  Lays a puzzle's givens out as cells on the board being created — the puzzle
  as it was before anyone played it.
  """

  use Ash.Resource.Change

  alias Sudoku.Game.Board
  alias Sudoku.Game.Puzzle

  @impl true
  def change(changeset, _opts, _context) do
    difficulty = Ash.Changeset.get_argument(changeset, :difficulty)
    cells = changeset |> Ash.Changeset.get_argument(:givens) |> Puzzle.decode()

    changeset
    |> Ash.Changeset.force_change_attribute(:cells, cells)
    |> Ash.Changeset.force_change_attribute(:status, Board.status(cells))
    |> Ash.Changeset.force_change_attribute(:difficulty, difficulty)
  end
end
