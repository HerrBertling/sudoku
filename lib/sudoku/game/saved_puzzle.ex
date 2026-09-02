defmodule Sudoku.Game.SavedPuzzle do
  @moduledoc """
  A Sudoku board persisted to disk so it can be reloaded later.

  Stores the full cell grid — including which cells are `given` — alongside the
  player's corner and centre pencil marks, so loading a save restores both the
  puzzle and the reasoning written on it.

  Saving under a name that already exists overwrites that save, the way saving
  a file does. A puzzle still being entered by hand is refused: its givens are
  only whatever has been typed so far, so there is no puzzle to keep yet.

  Two actions read a save back into something playable — `:restart` for the
  puzzle as it was set, `:resume` for the puzzle as it was left — so a caller
  never has to know that a save is givens plus a working state.
  """

  use Ash.Resource,
    domain: Sudoku.Game,
    data_layer: AshSqlite.DataLayer

  alias Sudoku.Game.SavedState

  sqlite do
    table "saved_puzzles"
    repo Sudoku.Repo
  end

  actions do
    default_accept :*
    defaults [:read, :destroy]

    create :save do
      description "Persist a board under a name, replacing any save with that name."
      accept [:name, :difficulty, :givens, :cells, :corner_marks, :center_marks, :elapsed_seconds]
      upsert? true
      upsert_identity :unique_name

      # Not stored — a save is always a puzzle being played. It is here so the
      # rule about which plays may be saved lives with the saving.
      argument :mode, Sudoku.Game.Mode, default: :playing

      validate argument_equals(:mode, :playing) do
        message "finalize the puzzle before saving it"
      end

      change set_attribute(:updated_at, &DateTime.utc_now/0)
    end

    read :search do
      description "Saves matching a name fragment, most recently updated first."

      # Ash's :string casts "" to nil unless allow_empty? is set, which would
      # turn "show everything" into a filter that matches nothing.
      argument :term, :string do
        default ""
        constraints allow_empty?: true
      end

      argument :only_custom, :boolean, default: false

      prepare build(sort: [updated_at: :desc])

      # Case-folded so searching "sud" finds "Alpha Sudoku".
      filter expr(
               is_nil(^arg(:term)) or ^arg(:term) == "" or
                 contains(string_downcase(name), string_downcase(^arg(:term)))
             )

      filter expr(^arg(:only_custom) == false or difficulty == :custom)
    end

    action :restart, :struct do
      description "The puzzle as it was set, with every entry and mark dropped."
      constraints instance_of: Sudoku.Game.Board

      argument :saved_puzzle, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      run fn input, _context ->
        saved = input.arguments.saved_puzzle

        {:ok, Sudoku.Game.board_from_givens!(saved.givens, %{difficulty: saved.difficulty})}
      end
    end

    action :resume, :struct do
      description "The puzzle as it was left — entries, marks and clock."
      constraints instance_of: Sudoku.Game.Play

      argument :saved_puzzle, :struct do
        allow_nil? false
        constraints instance_of: __MODULE__
      end

      run fn input, _context ->
        {:ok,
         input.arguments.saved_puzzle |> SavedState.from_saved_puzzle() |> SavedState.to_play()}
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :difficulty, Sudoku.Game.Difficulty do
      allow_nil? false
      default :custom
      public? true
    end

    # The puzzle itself: 81 digits, "0" for a square left empty. Never changes
    # while the puzzle is played, so progress can always be wound back.
    attribute :givens, Sudoku.Game.Puzzle.Givens do
      allow_nil? false
      public? true
    end

    # The working state: the player's entries on top of the givens.
    attribute :cells, {:array, Sudoku.Game.Cell} do
      allow_nil? false
      public? true
    end

    # Pencil marks. `Sudoku.Game.PencilMarks` is the type: it knows they are
    # keyed by `Sudoku.Game.Position.key/1` and hold digits 1-9, so a save
    # cannot write a shape the game cannot read back.
    attribute :corner_marks, Sudoku.Game.PencilMarks do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :center_marks, Sudoku.Game.PencilMarks do
      allow_nil? false
      default %{}
      public? true
    end

    # Seconds spent on this puzzle, so resuming picks the clock up where it
    # was rather than starting over.
    attribute :elapsed_seconds, :integer do
      allow_nil? false
      default 0
      public? true
      constraints min: 0
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
