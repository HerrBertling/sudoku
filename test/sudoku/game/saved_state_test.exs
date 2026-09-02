defmodule Sudoku.Game.SavedStateTest do
  use Sudoku.DataCase, async: false

  alias Sudoku.Game.Cell
  alias Sudoku.Game.PencilMarks
  alias Sudoku.Game.Play
  alias Sudoku.Game.Puzzle
  alias Sudoku.Game.SavedState

  # A puzzle with one given, one entry the player made, and marks in two cells.
  defp state(overrides \\ %{}) do
    cells =
      Puzzle.decode(String.duplicate("0", 81))
      |> List.update_at(0, &%{&1 | value: 7, given: true})
      |> List.update_at(1, &%{&1 | value: 4})

    struct!(
      %SavedState{
        cells: cells,
        difficulty: :hard,
        mode: :playing,
        corner_marks: %{"0,2" => MapSet.new([2, 7])},
        center_marks: %{"4,4" => MapSet.new([1, 5, 9])},
        elapsed: 0
      },
      overrides
    )
  end

  defp unique_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  describe "the browser adapter" do
    test "a saved state survives being written down and read back" do
      state = state()

      assert {:ok, ^state} = state |> SavedState.to_payload() |> SavedState.from_payload()
    end

    test "it survives the JSON the browser actually stores" do
      state = state(%{difficulty: :custom, mode: :manual_entry})

      payload =
        state
        |> SavedState.to_payload()
        |> Jason.encode!()
        |> Jason.decode!()

      assert {:ok, ^state} = SavedState.from_payload(payload)
    end

    test "the payload carries the version, and nothing else has to know it" do
      assert %{"version" => version} = SavedState.to_payload(state())
      assert version == SavedState.version()
    end

    test "the clock is not part of what the browser keeps" do
      state = state(%{elapsed: 240})

      assert {:ok, restored} = state |> SavedState.to_payload() |> SavedState.from_payload()
      assert restored.elapsed == 0
    end

    test "a payload from another version is refused rather than guessed at" do
      payload = SavedState.to_payload(state())

      assert {:error, :unsupported_version} =
               SavedState.from_payload(%{payload | "version" => 99})

      assert {:error, :unsupported_version} =
               SavedState.from_payload(%{payload | "version" => "2"})
    end

    test "a payload from before the version check is read as the shape it is" do
      payload = state() |> SavedState.to_payload() |> Map.delete("version")

      assert {:ok, state} = SavedState.from_payload(payload)
      assert state.difficulty == :hard
      assert length(state.cells) == 81
    end

    test "a payload that is not 81 cells is refused" do
      payload = SavedState.to_payload(state())

      assert {:error, :malformed} = SavedState.from_payload(%{payload | "cells" => []})
      assert {:error, :malformed} = SavedState.from_payload(Map.delete(payload, "cells"))
      assert {:error, :malformed} = SavedState.from_payload(%{payload | "cells" => "grid"})
      assert {:error, :malformed} = SavedState.from_payload("everything")
    end

    test "a cell holding something that is not a digit is refused" do
      payload = SavedState.to_payload(state())
      cells = List.update_at(payload["cells"], 0, &%{&1 | "value" => 42})

      assert {:error, :malformed} = SavedState.from_payload(%{payload | "cells" => cells})
    end

    test "marks it cannot read cost that cell's marks, not the whole board" do
      payload = SavedState.to_payload(state())
      broken = %{"0,2" => [2, 7], "nowhere" => [3], "1,1" => "99"}

      assert {:ok, restored} = SavedState.from_payload(%{payload | "corner_marks" => broken})
      assert restored.corner_marks == %{"0,2" => MapSet.new([2, 7])}

      assert {:ok, restored} = SavedState.from_payload(%{payload | "center_marks" => nil})
      assert restored.center_marks == %{}
    end

    test "an unknown difficulty or mode falls back instead of raising" do
      payload = SavedState.to_payload(state())

      assert {:ok, restored} =
               SavedState.from_payload(%{
                 payload
                 | "difficulty" => "fiendish",
                   "mode" => "spectating"
               })

      assert restored.difficulty == :custom
      assert restored.mode == :playing
    end

    test "a difficulty that is not even a word falls back instead of raising" do
      payload = SavedState.to_payload(state())

      assert {:ok, restored} =
               SavedState.from_payload(%{payload | "difficulty" => %{"not" => "a word"}})

      assert restored.difficulty == :custom
    end
  end

  describe "the SQLite adapter" do
    test "a saved state survives a save and a load" do
      state = state(%{elapsed: 137})

      saved =
        Sudoku.Game.save_puzzle!(
          unique_name("round-trip"),
          SavedState.to_saved_puzzle_attrs(state)
        )

      loaded = saved.id |> Sudoku.Game.get_saved_puzzle!() |> SavedState.from_saved_puzzle()

      assert loaded == state
    end

    test "the save carries the puzzle definition beside the working state" do
      attrs = SavedState.to_saved_puzzle_attrs(state())

      # The given 7 is the puzzle; the player's 4 is not.
      assert String.starts_with?(attrs.givens, "70")
      assert Enum.at(attrs.cells, 1).value == 4
    end

    test "a puzzle still being entered by hand is refused" do
      state = state(%{mode: :manual_entry, elapsed: 0})

      assert {:error, %Ash.Error.Invalid{} = error} =
               Sudoku.Game.save_puzzle(
                 unique_name("unfinalized"),
                 SavedState.to_saved_puzzle_attrs(state)
               )

      assert Enum.any?(error.errors, &(&1.field == :mode))
    end

    test "a save comes back as a puzzle being played" do
      saved =
        Sudoku.Game.save_puzzle!(
          unique_name("finalized"),
          SavedState.to_saved_puzzle_attrs(state())
        )

      loaded = saved.id |> Sudoku.Game.get_saved_puzzle!() |> SavedState.from_saved_puzzle()

      assert loaded.mode == :playing
    end

    test "a row written before the marks had a type still loads" do
      cells = Puzzle.decode(String.duplicate("0", 80) <> "5")
      id = Ash.UUID.generate()
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      # Exactly the shape the hand-rolled encoders wrote: marks as a bare map of
      # "row,col" to a sorted list, cells as an array of JSON objects.
      Repo.query!(
        """
        INSERT INTO saved_puzzles
          (id, name, difficulty, givens, cells, corner_marks, center_marks,
           elapsed_seconds, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          id,
          unique_name("legacy"),
          "medium",
          Puzzle.encode(cells),
          Jason.encode!(
            Enum.map(cells, &Jason.encode!(Map.take(&1, ~w(row col value given valid)a)))
          ),
          ~s({"0,0":[2,7]}),
          ~s({"4,4":[1,5,9]}),
          61,
          now,
          now
        ]
      )

      loaded = id |> Sudoku.Game.get_saved_puzzle!() |> SavedState.from_saved_puzzle()

      assert length(loaded.cells) == 81
      assert Enum.at(loaded.cells, 80).value == 5
      assert loaded.difficulty == :medium
      assert loaded.elapsed == 61
      assert loaded.corner_marks == %{"0,0" => MapSet.new([2, 7])}
      assert loaded.center_marks == %{"4,4" => MapSet.new([1, 5, 9])}
    end
  end

  describe "the play" do
    test "what is worth keeping of a play, and nothing else" do
      play =
        Play.new(Puzzle.decode(String.duplicate("0", 81)), difficulty: :easy, elapsed: 30)
        |> Play.act({:select, {0, 0}, :replace})
        |> Play.act({:digit, 5})
        |> Play.act({:select, {1, 1}, :replace})
        |> Play.act({:digit, 3, :corner})

      state = SavedState.from_play(play)

      assert state.difficulty == :easy
      assert state.mode == :playing
      assert state.elapsed == 30
      assert state.corner_marks == %{"1,1" => MapSet.new([3])}
      assert Enum.at(state.cells, 0).value == 5
    end

    test "a play built from a saved state carries it all back" do
      play = state(%{elapsed: 90}) |> SavedState.to_play()

      assert play.board.difficulty == :hard
      assert play.mode == :playing
      assert play.elapsed == 90
      assert play.center_marks == %{"4,4" => MapSet.new([1, 5, 9])}
      assert SavedState.from_play(play) == state(%{elapsed: 90})
    end

    test "resuming adopts the board without touching this sitting's clock" do
      state = state(%{elapsed: 500})
      played = Play.act(Play.new(Puzzle.decode(String.duplicate("0", 81))), :tick)

      resumed = Play.act(played, SavedState.resume_intent(state))

      assert resumed.elapsed == 1
      assert resumed.board.difficulty == :hard
      assert resumed.corner_marks == %{"0,2" => MapSet.new([2, 7])}
      assert %{value: 7, given: true} = Enum.at(resumed.board.cells, 0)
    end
  end

  describe "the two adapters agree" do
    test "the same play written to both places reads back the same" do
      state = state(%{elapsed: 0})

      {:ok, from_browser} = state |> SavedState.to_payload() |> SavedState.from_payload()

      saved =
        Sudoku.Game.save_puzzle!(unique_name("agree"), SavedState.to_saved_puzzle_attrs(state))

      from_sqlite = saved.id |> Sudoku.Game.get_saved_puzzle!() |> SavedState.from_saved_puzzle()

      assert from_browser == from_sqlite
    end

    test "marks are written the same way at both seams" do
      state = state()
      attrs = SavedState.to_saved_puzzle_attrs(state)
      payload = SavedState.to_payload(state)

      assert attrs.corner_marks == payload["corner_marks"]
      assert attrs.corner_marks == PencilMarks.encode(state.corner_marks)
    end
  end

  test "a cell that arrives without its flags reads as an ordinary empty square" do
    cells = for row <- 0..8, col <- 0..8, do: %{"row" => row, "col" => col, "value" => nil}

    assert {:ok, restored} =
             SavedState.from_payload(%{"version" => SavedState.version(), "cells" => cells})

    assert restored.cells == for(row <- 0..8, col <- 0..8, do: %Cell{row: row, col: col})
  end
end
