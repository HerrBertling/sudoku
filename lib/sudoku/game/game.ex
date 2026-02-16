defmodule Sudoku.Game do
  use Ash.Domain

  resources do
    resource Sudoku.Game.Board do
      define :new_game, action: :new_game, args: [:difficulty]
      define :place_number, action: :place_number, args: [:board, :row, :col, :value]
      define :select_cell, action: :select_cell, args: [:board, :row, :col]
    end
  end
end
