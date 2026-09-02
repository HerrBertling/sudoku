defmodule Sudoku.Game.PlayTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.Play
  alias Sudoku.Game.Position
  alias Sudoku.Game.Puzzle

  @blank String.duplicate("0", 81)

  # The canonical Wikipedia puzzle.
  @solvable "530070000600195000098000060800060003400803001700020006060000280000419005000080079"

  # Row 0 is missing only a 9, and the 9 in its column is already spoken for,
  # so r1c9 has nowhere to go.
  @unsolvable "123456780" <> "000000009" <> String.duplicate("0", 63)

  defp play(givens \\ @blank, opts \\ []) do
    Play.new(Puzzle.decode(givens), Keyword.put_new(opts, :difficulty, :custom))
  end

  defp select(play, positions) do
    Enum.reduce(positions, play, fn position, play ->
      Play.act(play, {:select, position, :extend})
    end)
  end

  defp corner(play, position), do: marks(play.corner_marks, position)
  defp center(play, position), do: marks(play.center_marks, position)

  defp marks(marks, position) do
    marks |> Map.get(Position.key(position), MapSet.new()) |> MapSet.to_list() |> Enum.sort()
  end

  defp value_at(play, {row, col}) do
    Enum.find_value(play.board.cells, fn c -> (c.row == row and c.col == col) && c.value end)
  end

  # A puzzle being typed in: digits are entries, not givens, until it is
  # finalized.
  defp draft(givens) do
    cells = givens |> Puzzle.decode() |> Enum.map(&%{&1 | given: false})
    Play.new(cells, difficulty: :custom, mode: :manual_entry)
  end

  describe "the group toggle" do
    test "a digit goes onto every eligible cell in the selection" do
      play =
        play()
        |> select([{0, 0}, {0, 1}, {0, 2}])
        |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == [2]
      assert corner(play, {0, 1}) == [2]
      assert corner(play, {0, 2}) == [2]
      assert corner(play, {0, 3}) == []
    end

    test "a digit already on every selected cell comes off all of them" do
      play =
        play()
        |> select([{0, 0}, {0, 1}])
        |> Play.act({:digit, 2, :corner})
        |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == []
      assert corner(play, {0, 1}) == []
    end

    test "a mixed selection fills in rather than toggling cell by cell" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 2, :corner})
        |> Play.act({:select, {0, 1}, :extend})
        |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == [2]
      assert corner(play, {0, 1}) == [2]
    end

    test "the two kinds of mark are independent" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 2, :corner})
        |> Play.act({:digit, 9, :center})

      assert corner(play, {0, 0}) == [2]
      assert center(play, {0, 0}) == [9]

      play = Play.act(play, {:clear, :corner})

      assert corner(play, {0, 0}) == []
      assert center(play, {0, 0}) == [9]
    end

    test "a value supersedes the marks in that cell" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 2, :corner})
        |> Play.act({:digit, 9, :center})
        |> Play.act({:digit, 5})

      assert value_at(play, {0, 0}) == 5
      assert corner(play, {0, 0}) == []
      assert center(play, {0, 0}) == []
    end
  end

  describe "mark eligibility" do
    test "a given cell cannot be marked" do
      play = @solvable |> play() |> select([{0, 0}]) |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == []
      assert value_at(play, {0, 0}) == 5
    end

    test "a cell holding a value cannot be marked" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 5})
        |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == []
    end

    test "the eligible cells in a mixed selection are marked, the rest left alone" do
      play =
        @solvable
        # r1c1 is a given 5, r1c3 is empty.
        |> play()
        |> select([{0, 0}, {0, 2}])
        |> Play.act({:digit, 2, :corner})

      assert corner(play, {0, 0}) == []
      assert corner(play, {0, 2}) == [2]
    end
  end

  describe "mode resolution" do
    test "a bare digit writes in the active mode" do
      play = play() |> select([{0, 0}]) |> Play.act({:input_mode, :corner})

      assert corner(Play.act(play, {:digit, 4}), {0, 0}) == [4]

      play = Play.act(play, {:input_mode, :center})
      assert center(Play.act(play, {:digit, 4}), {0, 0}) == [4]
    end

    test "a modifier overrides the active mode" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:input_mode, :center})
        |> Play.act({:digit, 4, :corner})

      assert corner(play, {0, 0}) == [4]
      assert center(play, {0, 0}) == []
    end

    test "manual entry writes values whatever the mode says" do
      play =
        play(@blank, mode: :manual_entry)
        |> select([{0, 0}])
        |> Play.act({:input_mode, :corner})
        |> Play.act({:digit, 4, :center})

      assert value_at(play, {0, 0}) == 4
      assert corner(play, {0, 0}) == []
      assert center(play, {0, 0}) == []
    end

    test "the modes cycle Normal, Corner, Centre, Highlight" do
      play = play()

      modes =
        Enum.map_reduce(1..4, play, fn _, play ->
          play = Play.act(play, :cycle_input_mode)
          {play.input_mode, play}
        end)
        |> elem(0)

      assert modes == [:corner, :center, :highlight, :normal]
    end

    test "Highlight shades the squares a digit is blocked from instead of writing" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 5})
        |> Play.act({:input_mode, :highlight})
        |> Play.act({:digit, 5})

      assert play.highlighted_number == 5
      # The square itself, its 20 peers, and nothing else.
      assert MapSet.size(play.blocked_cells) == 21
      assert MapSet.member?(play.blocked_cells, {0, 8})
      refute MapSet.member?(play.blocked_cells, {8, 8})

      # Clearing in Highlight mode drops the highlight, not the cell.
      play = Play.act(play, :clear)

      assert play.highlighted_number == nil
      assert play.blocked_cells == MapSet.new()
      assert value_at(play, {0, 0}) == 5
    end
  end

  describe "undo and redo" do
    test "undo takes back a placed digit, redo puts it back" do
      play = play() |> select([{0, 0}]) |> Play.act({:digit, 5})

      assert value_at(play, {0, 0}) == 5

      play = Play.act(play, :undo)
      assert value_at(play, {0, 0}) == nil

      play = Play.act(play, :redo)
      assert value_at(play, {0, 0}) == 5
    end

    test "a bulk mark is one step" do
      play =
        play()
        |> select([{0, 0}, {0, 1}, {0, 2}])
        |> Play.act({:digit, 2, :corner})
        |> Play.act(:undo)

      assert corner(play, {0, 0}) == []
      assert corner(play, {0, 1}) == []
      assert corner(play, {0, 2}) == []
      assert play.history == []
    end

    test "a change that moves nothing costs no history step" do
      # Nothing selected, so the digit lands nowhere.
      play = Play.act(play(), {:digit, 5})
      assert play.history == []

      # A given cell refuses the digit.
      play = @solvable |> play() |> select([{0, 0}]) |> Play.act({:digit, 5})
      assert play.history == []

      # Marking a given cell is not a change either.
      play = Play.act(play, {:digit, 3, :corner})
      assert play.history == []

      # Clearing a cell that is already empty is not a change.
      play = play() |> select([{4, 4}]) |> Play.act(:clear)
      assert play.history == []
    end

    test "undo and redo at the ends of the history do nothing" do
      play = play()

      assert Play.act(play, :undo) == play
      assert Play.act(play, :redo) == play
    end

    test "a new change abandons the redo future" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 5})
        |> Play.act(:undo)

      assert [_] = play.future

      play = Play.act(play, {:digit, 6})

      assert play.future == []
      assert value_at(play, {0, 0}) == 6
    end

    test "history survives selection and mode changes" do
      play =
        play()
        |> select([{0, 0}])
        |> Play.act({:digit, 5})
        |> Play.act({:select, {4, 4}, :replace})
        |> Play.act({:input_mode, :corner})
        |> Play.act(:undo)

      assert value_at(play, {0, 0}) == nil
    end
  end

  describe "check" do
    test "says nothing is wrong on a clean board" do
      play =
        @solvable
        # r1c3 is a 4 in the solution.
        |> play()
        |> select([{0, 2}])
        |> Play.act({:digit, 4})
        |> Play.act(:check)

      assert play.check == :checked
      assert play.check_errors == MapSet.new()
    end

    test "flags an entry that contradicts the solution" do
      play =
        @solvable
        |> play()
        |> select([{0, 2}])
        |> Play.act({:digit, 2})
        |> Play.act(:check)

      assert play.check == :checked
      assert play.check_errors == MapSet.new([{0, 2}])
    end

    test "says so when the givens have no solution to check against" do
      play = @unsolvable |> play() |> Play.act(:check)

      assert play.check == :unsolvable
    end

    test "the next change clears the verdict" do
      play =
        @solvable
        |> play()
        |> select([{0, 2}])
        |> Play.act({:digit, 2})
        |> Play.act(:check)
        |> Play.act({:digit, 4})

      assert play.check == nil
      assert play.check_errors == MapSet.new()
    end
  end

  describe "selection and cursor" do
    test "a plain select replaces, an additive select toggles" do
      play =
        play()
        |> Play.act({:select, {0, 0}, :replace})
        |> Play.act({:select, {0, 1}, :toggle})

      assert play.selection == MapSet.new([{0, 0}, {0, 1}])
      assert play.cursor == {0, 1}

      play = Play.act(play, {:select, {0, 1}, :toggle})
      assert play.selection == MapSet.new([{0, 0}])

      play = Play.act(play, {:select, {5, 5}, :replace})
      assert play.selection == MapSet.new([{5, 5}])
    end

    test "arrows move the cursor and wrap around the grid" do
      play = play() |> Play.act({:select, {0, 0}, :replace})

      play = Play.act(play, {:move_cursor, :up, false})
      assert play.cursor == {8, 0}
      assert play.selection == MapSet.new([{8, 0}])

      play = Play.act(play, {:move_cursor, :left, false})
      assert play.cursor == {8, 8}
    end

    test "an extending arrow grows the selection" do
      play =
        play()
        |> Play.act({:select, {0, 0}, :replace})
        |> Play.act({:move_cursor, :right, true})

      assert play.selection == MapSet.new([{0, 0}, {0, 1}])
    end

    test "select all takes the whole grid, clear takes none of it" do
      play = Play.act(play(), :select_all)

      assert MapSet.size(play.selection) == 81
      assert play.cursor == {0, 0}

      assert Play.act(play, :clear_selection).selection == MapSet.new()
    end
  end

  describe "regressions" do
    test "an empty manual-entry grid reports many solutions, not none", %{} do
      play = Play.new(Puzzle.decode(@blank), difficulty: :custom, mode: :manual_entry)

      # An empty grid has billions of solutions. Reporting 0 drove the red
      # "No solutions — check your entries" banner over an untouched grid.
      assert play.solution_count == 2
    end

    test "an unsolvable check clears the highlights from the previous one" do
      # A wrong entry, checked, so there is something highlighted to begin with.
      play =
        @solvable
        |> play()
        |> Play.act({:select, {0, 2}, :replace})
        |> Play.act({:digit, 2})
        |> Play.act(:check)

      assert play.check == :checked
      assert MapSet.size(play.check_errors) == 1

      # Now make the givens unsolvable and check again: with no solution to
      # compare against, the old highlights point at nothing.
      play = %{play | board: play(@unsolvable).board} |> Play.act(:check)

      assert play.check == :unsolvable
      assert MapSet.size(play.check_errors) == 0
    end
  end

  describe "manual entry" do
    test "counts the solutions as digits go in" do
      play = draft(@blank) |> select([{0, 0}]) |> Play.act({:digit, 5})

      # Counting stops at two: "more than one" is all the player needs.
      assert play.solution_count == 2

      # r1c3 is a 4 in this puzzle's only solution.
      play = draft(@solvable) |> select([{0, 2}]) |> Play.act({:digit, 4})
      assert play.solution_count == 1
    end

    test "finalizing turns the entries into givens and starts play" do
      play =
        draft(@solvable)
        |> select([{0, 2}])
        |> Play.act({:digit, 4})
        |> Play.act(:finalize)

      assert play.mode == :playing
      assert play.solution_count == nil
      assert play.history == []
      assert Enum.all?(play.board.cells, fn c -> is_nil(c.value) or c.given end)

      # What was typed in is now part of the puzzle and cannot be changed.
      play = play |> select([{0, 2}]) |> Play.act(:clear)
      assert value_at(play, {0, 2}) == 4
    end

    test "clearing a digit re-counts the solutions" do
      play =
        draft(@solvable)
        |> select([{0, 0}])
        |> Play.act(:clear)

      assert play.solution_count == 1

      play = play |> select([{0, 1}, {0, 4}, {1, 0}]) |> Play.act(:clear)
      assert play.solution_count == 2
    end
  end

  describe "the clock" do
    test "runs while the board is being played and stops when paused" do
      play = play()

      assert Play.act(play, :tick).elapsed == 1

      play = Play.act(play, :toggle_timer)
      assert Play.act(play, :tick).elapsed == 0
    end
  end

  describe "remaining counts" do
    test "count down as digits are placed" do
      play = play()
      assert play.remaining_counts[5] == 9

      play = play |> select([{0, 0}]) |> Play.act({:digit, 5})
      assert play.remaining_counts[5] == 8
      assert play.remaining_counts[4] == 9
    end
  end

  describe "resume" do
    test "adopts a board from storage without disturbing the clock" do
      play = play() |> select([{0, 0}]) |> Play.act({:digit, 5}) |> Play.act(:tick)

      resumed =
        Play.act(
          play,
          {:resume, Puzzle.decode(@solvable), difficulty: :custom, mode: :playing}
        )

      assert value_at(resumed, {0, 0}) == 5
      assert resumed.elapsed == 1
      # There is nothing to wind back to: the entries came from storage.
      assert resumed.history == []
      # Storage is where this came from, so there is nothing to write back.
      assert resumed.revision == play.revision
    end
  end
end
