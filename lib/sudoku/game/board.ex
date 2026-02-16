defmodule Sudoku.Game.Board do
  use Ash.Resource,
    domain: Sudoku.Game,
    data_layer: Ash.DataLayer.Simple

  attributes do
    uuid_primary_key :id

    attribute :cells, {:array, Sudoku.Game.Cell} do
      allow_nil? false
      default []
      public? true
    end

    attribute :status, :atom do
      constraints one_of: [:playing, :complete]
      default :playing
      public? true
    end

    attribute :difficulty, :atom do
      constraints one_of: [:easy, :medium, :hard, :custom]
      default :medium
      public? true
    end

    attribute :selected_row, :integer, public?: true
    attribute :selected_col, :integer, public?: true
  end

  actions do
    default_accept :*
    defaults [:read]

    action :new_game, :struct do
      constraints instance_of: __MODULE__

      argument :difficulty, :atom do
        default :medium
        constraints one_of: [:easy, :medium, :hard]
      end

      run fn input, _context ->
        difficulty = input.arguments[:difficulty] || :medium
        cells = Sudoku.Game.Generator.generate(difficulty)

        {:ok,
         %__MODULE__{
           id: Ash.UUID.generate(),
           cells: cells,
           status: :playing,
           difficulty: difficulty,
           selected_row: nil,
           selected_col: nil
         }}
      end
    end

    action :place_number, :struct do
      constraints instance_of: __MODULE__

      argument :board, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      argument :row, :integer, allow_nil?: false
      argument :col, :integer, allow_nil?: false
      argument :value, :integer

      run fn input, _context ->
        board = input.arguments.board
        row = input.arguments.row
        col = input.arguments.col
        value = input.arguments.value

        cell = Enum.find(board.cells, &(&1.row == row && &1.col == col))

        cond do
          board.status == :complete ->
            {:error, "Game is already complete"}

          cell && cell.given ->
            {:error, "Cannot modify a given cell"}

          true ->
            cells =
              Enum.map(board.cells, fn c ->
                if c.row == row && c.col == col, do: %{c | value: value}, else: c
              end)

            cells = Sudoku.Game.Validator.validate_cells(cells)

            status =
              if Enum.all?(cells, & &1.value) && Enum.all?(cells, & &1.valid),
                do: :complete,
                else: :playing

            {:ok, %{board | cells: cells, status: status}}
        end
      end
    end

    action :select_cell, :struct do
      constraints instance_of: __MODULE__

      argument :board, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      argument :row, :integer, allow_nil?: false
      argument :col, :integer, allow_nil?: false

      run fn input, _context ->
        board = input.arguments.board
        {:ok, %{board | selected_row: input.arguments.row, selected_col: input.arguments.col}}
      end
    end
  end
end
