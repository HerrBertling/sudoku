defmodule Sudoku.Game.SavedPuzzleTest do
  use Sudoku.DataCase, async: false

  alias Sudoku.Game.Puzzle

  defp cells do
    for row <- 0..8, col <- 0..8 do
      %Sudoku.Game.Cell{row: row, col: col, value: nil, given: false, valid: true}
    end
  end

  # A save always carries the puzzle it started as, alongside the working state.
  defp save(name, attrs) do
    cells = attrs[:cells] || cells()

    attrs
    |> Map.new()
    |> Map.put(:cells, cells)
    |> Map.put_new_lazy(:givens, fn -> Puzzle.encode(cells) end)
    |> then(&Sudoku.Game.save_puzzle!(name, &1))
  end

  defp unique_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "saves a board and reads it back with its marks" do
    name = unique_name("puzzle")

    saved =
      save(name, %{
        difficulty: :custom,
        corner_marks: %{"0,0" => [2, 7]},
        center_marks: %{"4,4" => [1, 5, 9]}
      })

    loaded = Sudoku.Game.get_saved_puzzle!(saved.id)

    assert loaded.name == name
    assert loaded.difficulty == :custom
    assert length(loaded.cells) == 81
    assert loaded.corner_marks == %{"0,0" => [2, 7]}
    assert loaded.center_marks == %{"4,4" => [1, 5, 9]}
  end

  test "given cells survive the round trip" do
    givens = List.update_at(cells(), 0, &%{&1 | value: 5, given: true})
    saved = save(unique_name("givens"), %{cells: givens})

    assert %{value: 5, given: true} = hd(Sudoku.Game.get_saved_puzzle!(saved.id).cells)
  end

  test "saving under an existing name replaces that save rather than adding one" do
    name = unique_name("same")

    save(name, %{difficulty: :easy})
    save(name, %{difficulty: :hard})

    matching = Enum.filter(Sudoku.Game.list_saved_puzzles!(), &(&1.name == name))

    assert [%{difficulty: :hard}] = matching
  end

  test "lists saves most recently updated first" do
    older = save(unique_name("older"), %{})
    newer = save(unique_name("newer"), %{})

    ids = Enum.map(Sudoku.Game.list_saved_puzzles!(), & &1.id)

    assert Enum.find_index(ids, &(&1 == newer.id)) <
             Enum.find_index(ids, &(&1 == older.id))
  end

  test "deleting a save removes it" do
    saved = save(unique_name("gone"), %{})
    Sudoku.Game.delete_saved_puzzle!(saved)

    refute Enum.any?(Sudoku.Game.list_saved_puzzles!(), &(&1.id == saved.id))
  end

  describe "search" do
    test "an empty term returns everything" do
      save(unique_name("one"), %{})
      save(unique_name("two"), %{})

      assert length(Sudoku.Game.list_saved_puzzles!(%{term: ""})) >= 2
    end

    test "matches a name fragment regardless of case" do
      name = "Wednesday Special #{System.unique_integer([:positive])}"
      save(name, %{})

      assert [%{name: ^name}] =
               Sudoku.Game.list_saved_puzzles!(%{term: "wednesday special"})
               |> Enum.filter(&(&1.name == name))
    end

    test "excludes names that do not match" do
      save(unique_name("apples"), %{})

      assert Sudoku.Game.list_saved_puzzles!(%{term: "zzz-no-such-puzzle"}) == []
    end

    test "only_custom hides generated games" do
      custom = unique_name("mine")
      generated = unique_name("generated")

      save(custom, %{difficulty: :custom})
      save(generated, %{difficulty: :hard})

      names = Sudoku.Game.list_saved_puzzles!(%{only_custom: true}) |> Enum.map(& &1.name)

      assert custom in names
      refute generated in names
    end
  end

  describe "puzzle definition" do
    test "givens are stored separately from the working state" do
      puzzle = List.update_at(cells(), 0, &%{&1 | value: 5, given: true})
      played = List.update_at(puzzle, 1, &%{&1 | value: 9, given: false})

      saved = save(unique_name("split"), %{cells: played, givens: Puzzle.encode(puzzle)})

      # The player's 9 is in the working state but not in the puzzle.
      assert String.starts_with?(saved.givens, "50")
      assert Enum.at(saved.cells, 1).value == 9
    end

    test "decoding givens rebuilds the untouched puzzle" do
      puzzle = List.update_at(cells(), 0, &%{&1 | value: 5, given: true})
      played = List.update_at(puzzle, 1, &%{&1 | value: 9, given: false})

      saved = save(unique_name("restart"), %{cells: played, givens: Puzzle.encode(puzzle)})
      fresh = Puzzle.decode(saved.givens)

      assert %{value: 5, given: true} = Enum.at(fresh, 0)
      assert %{value: nil, given: false} = Enum.at(fresh, 1)
    end

    test "progress counts only the squares the player filled" do
      puzzle = List.update_at(cells(), 0, &%{&1 | value: 5, given: true})
      played = List.update_at(puzzle, 1, &%{&1 | value: 9, given: false})

      assert Puzzle.given_count(Puzzle.encode(puzzle)) == 1
      assert Puzzle.blank_count(Puzzle.encode(puzzle)) == 80
      assert Puzzle.solved_count(played) == 1
    end
  end

  test "a save requires a name" do
    assert {:error, _} =
             Sudoku.Game.save_puzzle("", %{cells: cells(), givens: Puzzle.encode(cells())})
  end
end
