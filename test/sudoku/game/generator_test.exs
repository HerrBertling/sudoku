defmodule Sudoku.Game.GeneratorTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.Cell
  alias Sudoku.Game.Generator
  alias Sudoku.Game.Solver

  @difficulties [:easy, :medium, :hard]

  for difficulty <- @difficulties do
    describe "generate(#{inspect(difficulty)})" do
      @describetag difficulty: difficulty

      setup do
        {:ok, cells: Generator.generate(unquote(difficulty))}
      end

      test "returns one cell per square", %{cells: cells} do
        assert length(cells) == 81

        assert Enum.map(cells, &{&1.row, &1.col}) |> Enum.sort() ==
                 for(r <- 0..8, c <- 0..8, do: {r, c})
      end

      test "has exactly one solution", %{cells: cells} do
        assert Solver.count_solutions(cells, 2) == 1
      end

      test "marks filled squares as given and blank ones as not", %{cells: cells} do
        for %Cell{value: value, given: given} <- cells do
          assert given == not is_nil(value)
        end
      end

      test "only puts digits 1-9 on the board", %{cells: cells} do
        for %Cell{value: value} <- cells, not is_nil(value) do
          assert value in 1..9
        end
      end
    end
  end

  test "harder difficulties leave fewer squares filled in" do
    given_count = fn difficulty ->
      difficulty |> Generator.generate() |> Enum.count(& &1.given)
    end

    assert given_count.(:easy) > given_count.(:medium)
    assert given_count.(:medium) > given_count.(:hard)
  end
end
