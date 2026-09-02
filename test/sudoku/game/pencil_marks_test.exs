defmodule Sudoku.Game.PencilMarksTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.PencilMarks

  doctest Sudoku.Game.PencilMarks

  describe "writing marks down and reading them back" do
    test "a mark set survives the round trip" do
      marks = %{"0,0" => MapSet.new([2, 7]), "8,8" => MapSet.new([1, 5, 9])}

      assert marks |> PencilMarks.encode() |> PencilMarks.decode() == marks
    end

    test "digits are written in order, whatever order they were marked in" do
      assert PencilMarks.encode(%{"4,4" => MapSet.new([9, 1, 5])}) == %{"4,4" => [1, 5, 9]}
    end

    test "a cell whose marks were all rubbed out drops out" do
      assert PencilMarks.encode(%{"0,0" => MapSet.new()}) == %{}
      assert PencilMarks.decode(%{"0,0" => []}) == %{}
    end

    test "keys are the ones Position writes" do
      key = Sudoku.Game.Position.key({3, 6})

      assert PencilMarks.encode(%{key => MapSet.new([4])}) == %{"3,6" => [4]}
    end
  end

  describe "malformed marks" do
    test "a key that is not a position is dropped" do
      assert PencilMarks.decode(%{"nowhere" => [1], "9,9" => [2], "0" => [3]}) == %{}
    end

    test "digits off the keypad are dropped" do
      assert PencilMarks.decode(%{"0,0" => [0, 1, 10, "5", nil]}) == %{"0,0" => MapSet.new([1])}
    end

    test "a cell left with no readable digits is dropped" do
      assert PencilMarks.decode(%{"0,0" => ["x"], "1,1" => 5}) == %{}
    end

    test "marks that are not a map at all read as no marks" do
      assert PencilMarks.decode(nil) == %{}
      assert PencilMarks.decode([1, 2, 3]) == %{}
      assert PencilMarks.decode("0,0") == %{}
    end
  end

  describe "as the type of a saved puzzle's mark columns" do
    test "accepts marks in either form" do
      assert {:ok, %{"0,0" => [2, 7]}} = PencilMarks.cast_input(%{"0,0" => [2, 7]}, [])

      assert {:ok, %{"0,0" => [2, 7]}} =
               PencilMarks.cast_input(%{"0,0" => MapSet.new([7, 2])}, [])

      assert {:ok, %{}} = PencilMarks.cast_input(%{}, [])
      assert {:ok, nil} = PencilMarks.cast_input(nil, [])
    end

    test "refuses to store something the game could not read back" do
      assert :error = PencilMarks.cast_input(%{"nowhere" => [1]}, [])
      assert :error = PencilMarks.cast_input(%{"0,0" => [10]}, [])
      assert :error = PencilMarks.cast_input(%{"0,0" => "27"}, [])
      assert :error = PencilMarks.cast_input(%{{0, 0} => [2]}, [])
      assert :error = PencilMarks.cast_input("marks", [])
    end

    test "reads a stored row forgivingly, so one bad key costs one cell" do
      assert {:ok, %{"0,0" => [2, 7]}} =
               PencilMarks.cast_stored(%{"0,0" => [2, 7], "nowhere" => [1]}, [])
    end
  end
end
