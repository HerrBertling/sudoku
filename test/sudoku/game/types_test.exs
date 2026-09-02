defmodule Sudoku.Game.TypesTest do
  @moduledoc """
  The three types that exist so a value set is written down once:
  `Difficulty`, `Mode` and a puzzle's `Givens`.
  """

  use ExUnit.Case, async: true

  alias Sudoku.Game.Difficulty
  alias Sudoku.Game.Mode
  alias Sudoku.Game.Puzzle.Givens

  describe "Difficulty" do
    test "knows its own words" do
      assert Difficulty.values() == [:easy, :medium, :hard, :custom]
    end

    test "casts the strings storage and the browser speak" do
      assert Difficulty.match("hard") == {:ok, :hard}
      assert Difficulty.match(:hard) == {:ok, :hard}
    end

    test "refuses a word the game does not use" do
      assert Difficulty.match("fiendish") == :error
    end

    test "the generator deals every difficulty but :custom" do
      assert Difficulty.generated() == [:easy, :medium, :hard]
      refute :custom in Difficulty.generated()
    end
  end

  describe "Mode" do
    test "casts both ways" do
      assert Mode.match("manual_entry") == {:ok, :manual_entry}
      assert Mode.match(:playing) == {:ok, :playing}
      assert Mode.match("spectating") == :error
    end
  end

  describe "Givens" do
    # A NewType carries its own constraints, and `Ash.Type.init/2` is what
    # merges them in. Casting without that step checks nothing, which is what
    # an action does for you.
    defp cast(value) do
      {:ok, constraints} = Ash.Type.init(Givens, [])
      Ash.Type.cast_input(Givens, value, constraints)
    end

    test "takes 81 digits" do
      assert {:ok, _} = cast(String.duplicate("0", 81))
    end

    test "refuses anything else" do
      assert {:error, _} = cast(String.duplicate("0", 80))
      assert {:error, _} = cast(String.duplicate("0", 82))
      assert {:error, _} = cast(String.duplicate("x", 81))
    end
  end
end
