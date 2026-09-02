defmodule Sudoku.Game do
  use Ash.Domain

  resources do
    resource Sudoku.Game.Board do
      define :new_game, action: :new_game, args: [:difficulty]
      define :blank_board, action: :from_givens
      define :board_from_givens, action: :from_givens, args: [:givens]
      define :place, action: :place, args: [:board, :positions, :value]
    end

    resource Sudoku.Game.SavedPuzzle do
      define :save_puzzle, action: :save, args: [:name]
      define :list_saved_puzzles, action: :search
      define :get_saved_puzzle, action: :read, get_by: [:id]
      define :delete_saved_puzzle, action: :destroy
      define :restart_saved_puzzle, action: :restart, args: [:saved_puzzle]
      define :resume_saved_puzzle, action: :resume, args: [:saved_puzzle]
    end
  end
end
