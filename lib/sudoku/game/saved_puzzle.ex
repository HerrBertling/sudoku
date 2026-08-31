defmodule Sudoku.Game.SavedPuzzle do
  @moduledoc """
  A Sudoku board persisted to disk so it can be reloaded later.

  Stores the full cell grid — including which cells are `given` — alongside the
  player's corner and centre pencil marks, so loading a save restores both the
  puzzle and the reasoning written on it.

  Saving under a name that already exists overwrites that save, the way saving
  a file does.
  """

  use Ash.Resource,
    domain: Sudoku.Game,
    data_layer: AshSqlite.DataLayer

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
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100, trim?: true
    end

    attribute :difficulty, :atom do
      allow_nil? false
      default :custom
      public? true
      constraints one_of: [:easy, :medium, :hard, :custom]
    end

    # The puzzle itself: 81 digits, "0" for a square left empty. Never changes
    # while the puzzle is played, so progress can always be wound back.
    attribute :givens, :string do
      allow_nil? false
      public? true
      constraints match: ~r/^[0-9]{81}$/
    end

    # The working state: the player's entries on top of the givens.
    attribute :cells, {:array, Sudoku.Game.Cell} do
      allow_nil? false
      public? true
    end

    # Pencil marks, keyed by "row,col" with a list of digits as the value.
    attribute :corner_marks, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :center_marks, :map do
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
