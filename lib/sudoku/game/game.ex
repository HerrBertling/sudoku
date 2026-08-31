defmodule Sudoku.Game do
  use Ash.Domain

  resources do
    resource Sudoku.Game.Board do
      define :new_game, action: :new_game, args: [:difficulty]
      define :place_number, action: :place_number, args: [:board, :row, :col, :value]
    end

    resource Sudoku.Game.SavedPuzzle do
      define :save_puzzle, action: :save, args: [:name]
      define :list_saved_puzzles, action: :search
      define :get_saved_puzzle, action: :read, get_by: [:id]
      define :delete_saved_puzzle, action: :destroy
    end
  end
end
