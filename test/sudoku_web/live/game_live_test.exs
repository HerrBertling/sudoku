defmodule SudokuWeb.GameLiveTest do
  use SudokuWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @board "#sudoku-game"

  defp empty_board_payload do
    cells =
      for row <- 0..8, col <- 0..8 do
        %{"row" => row, "col" => col, "value" => nil, "given" => false, "valid" => true}
      end

    %{"cells" => cells, "difficulty" => "custom", "mode" => "playing"}
  end

  # Same, but with the given digits placed, as a finalized puzzle would have.
  defp game_with_givens(conn, givens) do
    cells =
      for row <- 0..8, col <- 0..8 do
        value = Map.get(givens, {row, col})

        %{
          "row" => row,
          "col" => col,
          "value" => value,
          "given" => not is_nil(value),
          "valid" => true
        }
      end

    {:ok, view, _html} = live(conn, ~p"/game")

    render_hook(element(view, @board), "restore_board", %{
      "cells" => cells,
      "difficulty" => "custom",
      "mode" => "playing"
    })

    view
  end

  # The canonical Wikipedia puzzle, as a {row, col} => digit map of its givens.
  defp solvable_givens do
    "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reject(fn {digit, _index} -> digit == "0" end)
    |> Map.new(fn {digit, index} ->
      {{div(index, 9), rem(index, 9)}, String.to_integer(digit)}
    end)
  end

  # Starts every test from a known, completely empty grid.
  defp blank_game(conn) do
    {:ok, view, _html} = live(conn, ~p"/game")
    render_hook(element(view, @board), "restore_board", empty_board_payload())
    view
  end

  @grid "#sudoku-grid"

  # Selection is driven by the pointer hook on the grid, so tests push the same
  # events it does rather than clicking a cell.
  defp select(view, row, col, opts \\ []) do
    render_hook(element(view, @grid), "select_cell", %{
      "row" => row,
      "col" => col,
      "additive" => Keyword.get(opts, :additive, false)
    })

    view
  end

  defp sweep(view, cells) do
    [{row, col} | rest] = cells
    select(view, row, col)

    Enum.each(rest, fn {r, c} ->
      render_hook(element(view, @grid), "extend_selection", %{"row" => r, "col" => c})
    end)

    view
  end

  defp keydown(view, params) do
    render_keydown(element(view, @board), params)
    view
  end

  # The visible digits in one cell, with markup and whitespace stripped: a
  # value, or the corner marks followed by the centre marks.
  defp cell_text(view, row, col) do
    view
    |> element(~s{[data-cell="#{row},#{col}"]})
    |> render()
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/\s+/, "")
  end

  describe "empty cells" do
    test "show nothing until the player writes a mark", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      assert cell_text(view, 0, 0) == ""
    end
  end

  describe "pencil marks" do
    test "Shift+digit writes a corner mark", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "!", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "&", "code" => "Digit7", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "27"
    end

    test "Ctrl+digit writes a centre mark", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "1", "code" => "Digit1", "ctrlKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == "19"
    end

    test "corner and centre marks coexist in one cell", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "7", "code" => "Digit7", "ctrlKey" => true})

      # Corner "2" renders before the centre "7".
      assert cell_text(view, 0, 0) == "27"
      assert render(view) =~ "row-start-1 col-start-1"
    end

    test "pressing the same digit twice removes the mark", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"

      view = keydown(view, %{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == ""
    end

    test "placing a digit clears that cell's marks", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})
        |> keydown(%{"key" => "5", "code" => "Digit5"})

      assert cell_text(view, 0, 0) == "5"
    end

    test "Backspace clears the value and both kinds of mark", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})
        |> keydown(%{"key" => "Backspace", "code" => "Backspace"})

      assert cell_text(view, 0, 0) == ""
    end

    test "Shift+Backspace clears only the corner marks", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == "29"

      view = keydown(view, %{"key" => "Backspace", "code" => "Backspace", "shiftKey" => true})

      # The centre 9 survives; the corner 2 is gone.
      assert cell_text(view, 0, 0) == "9"
    end

    test "Ctrl+Backspace clears only the centre marks", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})
        |> keydown(%{"key" => "Backspace", "code" => "Backspace", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == "2"
    end

    test "a scoped clear leaves the placed digit alone", %{conn: conn} do
      view =
        conn
        |> game_with_givens(%{})
        |> select(0, 0)
        |> keydown(%{"key" => "5", "code" => "Digit5"})
        |> keydown(%{"key" => "Backspace", "code" => "Backspace", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "5"
    end

    test "plain Backspace still empties the whole cell", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})
        |> keydown(%{"key" => "Backspace", "code" => "Backspace"})

      assert cell_text(view, 0, 0) == ""
    end

    test "marks go to the selected cell only", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(3, 4)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 3, 4) == "2"
      assert cell_text(view, 0, 0) == ""
    end
  end

  describe "input modes" do
    test "the number pad writes into the active mode", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      view |> element(~s{[phx-click="set_input_mode"][phx-value-mode="corner"]}) |> render_click()
      view |> element(~s{[phx-click="input_number"][phx-value-number="4"]}) |> render_click()

      assert cell_text(view, 0, 0) == "4"

      view |> element(~s{[phx-click="set_input_mode"][phx-value-mode="normal"]}) |> render_click()
      view |> element(~s{[phx-click="input_number"][phx-value-number="6"]}) |> render_click()

      # A confirmed digit replaces the mark.
      assert cell_text(view, 0, 0) == "6"
    end

    test "highlight mode shades blocked cells instead of writing", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      view |> element(~s{[phx-click="input_number"][phx-value-number="5"]}) |> render_click()

      view
      |> element(~s{[phx-click="set_input_mode"][phx-value-mode="highlight"]})
      |> render_click()

      html =
        view |> element(~s{[phx-click="input_number"][phx-value-number="5"]}) |> render_click()

      assert html =~ "bg-warning/20"
      assert cell_text(view, 0, 0) == "5"
    end

    test "the Clear button clears only the active mode's marks", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      view |> element(~s{[phx-click="set_input_mode"][phx-value-mode="corner"]}) |> render_click()
      view |> element(~s{[phx-click="input_number"][phx-value-number="4"]}) |> render_click()

      view |> element(~s{[phx-click="set_input_mode"][phx-value-mode="center"]}) |> render_click()
      view |> element(~s{[phx-click="input_number"][phx-value-number="8"]}) |> render_click()

      assert cell_text(view, 0, 0) == "48"

      # Still in Centre mode, so Clear takes the centre 8 and leaves the corner 4.
      view |> element(~s{[phx-click="input_number"][phx-value-number="clear"]}) |> render_click()

      assert cell_text(view, 0, 0) == "4"
    end

    test "Clear in Highlight mode drops the highlight, not the cell", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      view |> element(~s{[phx-click="input_number"][phx-value-number="5"]}) |> render_click()

      view
      |> element(~s{[phx-click="set_input_mode"][phx-value-mode="highlight"]})
      |> render_click()

      view |> element(~s{[phx-click="input_number"][phx-value-number="5"]}) |> render_click()

      assert render(view) =~ "bg-warning/20"

      html =
        view
        |> element(~s{[phx-click="input_number"][phx-value-number="clear"]})
        |> render_click()

      refute html =~ "bg-warning/20"
      assert cell_text(view, 0, 0) == "5"
    end

    test "Z, X and C jump straight to a mode", %{conn: conn} do
      view = conn |> blank_game() |> select(0, 0)

      view
      |> keydown(%{"key" => "x", "code" => "KeyX"})
      |> keydown(%{"key" => "4", "code" => "Digit4"})

      assert cell_text(view, 0, 0) == "4"

      view
      |> keydown(%{"key" => "c", "code" => "KeyC"})
      |> keydown(%{"key" => "8", "code" => "Digit8"})

      assert cell_text(view, 0, 0) == "48"

      # Z returns to Normal, where a digit is placed rather than marked.
      view
      |> keydown(%{"key" => "z", "code" => "KeyZ"})
      |> keydown(%{"key" => "5", "code" => "Digit5"})

      assert cell_text(view, 0, 0) == "5"
    end

    test "Cmd combos are ignored so browser shortcuts still work", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "1", "code" => "Digit1", "metaKey" => true})

      assert cell_text(view, 0, 0) == ""
    end
  end

  describe "multi-cell selection" do
    test "a sweep marks every cell it covers at once", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> sweep([{0, 0}, {0, 1}, {0, 2}])
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"
      assert cell_text(view, 0, 1) == "2"
      assert cell_text(view, 0, 2) == "2"
      assert cell_text(view, 0, 3) == ""
    end

    test "additive clicks build up a scattered selection", %{conn: conn} do
      view = blank_game(conn)

      select(view, 0, 0)
      select(view, 4, 4, additive: true)
      select(view, 8, 8, additive: true)

      keydown(view, %{"key" => "9", "code" => "Digit9", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == "9"
      assert cell_text(view, 4, 4) == "9"
      assert cell_text(view, 8, 8) == "9"
      assert cell_text(view, 0, 1) == ""
    end

    test "an additive click on a selected cell removes it again", %{conn: conn} do
      view = blank_game(conn)

      select(view, 0, 0)
      select(view, 0, 1, additive: true)
      select(view, 0, 1, additive: true)

      keydown(view, %{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"
      assert cell_text(view, 0, 1) == ""
    end

    test "a digit already on every selected cell comes off all of them", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> sweep([{0, 0}, {0, 1}])
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"

      # Pressing it again with the same cells selected clears rather than re-adds.
      view = keydown(view, %{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == ""
      assert cell_text(view, 0, 1) == ""
    end

    test "a mixed selection fills in rather than toggling cell by cell", %{conn: conn} do
      view = blank_game(conn)

      # Only the first cell carries the 2 to begin with.
      view
      |> select(0, 0)
      |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      view
      |> sweep([{0, 0}, {0, 1}])
      |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"
      assert cell_text(view, 0, 1) == "2"
    end

    test "Shift+arrow grows the selection, a plain arrow moves it", %{conn: conn} do
      view = blank_game(conn)

      view
      |> select(0, 0)
      |> keydown(%{"key" => "ArrowRight", "code" => "ArrowRight", "shiftKey" => true})
      |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      assert cell_text(view, 0, 0) == "2"
      assert cell_text(view, 0, 1) == "2"

      view
      |> keydown(%{"key" => "ArrowRight", "code" => "ArrowRight"})
      |> keydown(%{"key" => "#", "code" => "Digit3", "shiftKey" => true})

      # The plain arrow collapsed the selection onto one cell.
      assert cell_text(view, 0, 2) == "3"
      assert cell_text(view, 0, 0) == "2"
    end

    test "Ctrl+A selects the whole grid", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> keydown(%{"key" => "a", "code" => "KeyA", "ctrlKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == "9"
      assert cell_text(view, 8, 8) == "9"
      assert cell_text(view, 4, 4) == "9"
    end
  end

  describe "undo and redo" do
    test "undo takes back a placed digit, redo puts it back", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "5", "code" => "Digit5"})

      assert cell_text(view, 0, 0) == "5"

      view |> element(~s{[phx-click="undo"]}) |> render_click()
      assert cell_text(view, 0, 0) == ""

      view |> element(~s{[phx-click="redo"]}) |> render_click()
      assert cell_text(view, 0, 0) == "5"
    end

    test "Ctrl+Z and Ctrl+Y drive the same history", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "z", "code" => "KeyZ", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == ""

      view = keydown(view, %{"key" => "y", "code" => "KeyY", "ctrlKey" => true})
      assert cell_text(view, 0, 0) == "2"
    end

    test "Cmd+Z works too", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "5", "code" => "Digit5"})
        |> keydown(%{"key" => "z", "code" => "KeyZ", "metaKey" => true})

      assert cell_text(view, 0, 0) == ""
    end

    test "undo steps back through a bulk mark in one go", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> sweep([{0, 0}, {0, 1}, {0, 2}])
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "z", "code" => "KeyZ", "ctrlKey" => true})

      assert cell_text(view, 0, 0) == ""
      assert cell_text(view, 0, 1) == ""
      assert cell_text(view, 0, 2) == ""
    end

    test "the buttons are disabled when there is nothing to undo or redo", %{conn: conn} do
      view = blank_game(conn)

      assert view |> element(~s{[phx-click="undo"]}) |> render() =~ "disabled"
      assert view |> element(~s{[phx-click="redo"]}) |> render() =~ "disabled"

      view
      |> select(0, 0)
      |> keydown(%{"key" => "5", "code" => "Digit5"})

      refute view |> element(~s{[phx-click="undo"]}) |> render() =~ "disabled"
    end

    test "a keypress that changes nothing costs no undo step", %{conn: conn} do
      # Nothing selected, so the digit lands nowhere.
      view = conn |> blank_game() |> keydown(%{"key" => "5", "code" => "Digit5"})

      assert view |> element(~s{[phx-click="undo"]}) |> render() =~ "disabled"
    end

    test "starting a new game forgets the history", %{conn: conn} do
      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "5", "code" => "Digit5"})

      view |> element(~s{[phx-click="new_game"][phx-value-difficulty="easy"]}) |> render_click()

      assert view |> element(~s{[phx-click="undo"]}) |> render() =~ "disabled"
    end
  end

  describe "check" do
    test "reports a clean board", %{conn: conn} do
      view = game_with_givens(conn, solvable_givens())

      html = view |> element(~s{[phx-click="check_board"]}) |> render_click()

      assert html =~ "Everything so far matches the solution"
    end

    test "flags an entry that contradicts the solution", %{conn: conn} do
      view = game_with_givens(conn, solvable_givens())

      # r1c3 is 4 in the solution, so a 2 there must be wrong.
      view
      |> select(0, 2)
      |> keydown(%{"key" => "2", "code" => "Digit2"})

      html = view |> element(~s{[phx-click="check_board"]}) |> render_click()

      # The apostrophe is HTML-escaped in the rendered flash.
      assert html =~ "One entry can"
      assert view |> element(~s{[data-cell="0,2"]}) |> render() =~ "bg-error/20"
    end

    test "a correct entry is not flagged", %{conn: conn} do
      view = game_with_givens(conn, solvable_givens())

      view
      |> select(0, 2)
      |> keydown(%{"key" => "4", "code" => "Digit4"})

      html = view |> element(~s{[phx-click="check_board"]}) |> render_click()

      assert html =~ "Everything so far matches the solution"
    end
  end

  describe "the clock" do
    test "starts at zero and can be paused", %{conn: conn} do
      view = blank_game(conn)

      assert render(view) =~ "00:00"

      html = view |> element(~s{[phx-click="toggle_timer"]}) |> render_click()

      assert html =~ "hero-play-micro"
    end
  end

  describe "saving and loading" do
    test "saves the current board with its marks, then loads it back", %{conn: conn} do
      name = "Test puzzle #{System.unique_integer([:positive])}"

      view =
        conn
        |> blank_game()
        |> select(0, 0)
        |> keydown(%{"key" => "5", "code" => "Digit5"})
        |> select(1, 1)
        |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})
        |> keydown(%{"key" => "9", "code" => "Digit9", "ctrlKey" => true})

      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()
      view |> form("#save-puzzle-form", %{"name" => name}) |> render_submit()

      assert render(view) =~ name

      # Replace the board, then load the save back over it.
      view |> element(~s{[phx-click="new_game"][phx-value-difficulty="easy"]}) |> render_click()

      saved = Enum.find(Sudoku.Game.list_saved_puzzles!(), &(&1.name == name))
      view |> element(~s{[phx-click="load_puzzle"][phx-value-id="#{saved.id}"]}) |> render_click()

      assert cell_text(view, 0, 0) == "5"
      assert cell_text(view, 1, 1) == "29"
    end

    test "Restart clears progress and marks back to the givens", %{conn: conn} do
      name = "Replayable #{System.unique_integer([:positive])}"

      # A puzzle whose only given is a 7 at the top-left.
      view = game_with_givens(conn, %{{0, 0} => 7})

      # Play a digit and a mark on top of it, then save that progress.
      view
      |> select(0, 1)
      |> keydown(%{"key" => "4", "code" => "Digit4"})
      |> select(0, 2)
      |> keydown(%{"key" => "@", "code" => "Digit2", "shiftKey" => true})

      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()
      view |> form("#save-puzzle-form", %{"name" => name}) |> render_submit()

      saved = Enum.find(Sudoku.Game.list_saved_puzzles!(), &(&1.name == name))
      assert cell_text(view, 0, 1) == "4"

      # Saving leaves the panel open.
      view
      |> element(~s{[phx-click="restart_puzzle"][phx-value-id="#{saved.id}"]})
      |> render_click()

      # The given survives; the entry and the mark are gone.
      assert cell_text(view, 0, 0) == "7"
      assert cell_text(view, 0, 1) == ""
      assert cell_text(view, 0, 2) == ""

      # Restarting does not touch the stored progress.
      assert Sudoku.Game.get_saved_puzzle!(saved.id).cells
             |> Enum.any?(&(&1.row == 0 and &1.col == 1 and &1.value == 4))
    end

    test "the search box filters the list", %{conn: conn} do
      keep = "Keeper #{System.unique_integer([:positive])}"
      other = "Hidden #{System.unique_integer([:positive])}"

      view = blank_game(conn)
      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()
      view |> form("#save-puzzle-form", %{"name" => keep}) |> render_submit()
      view |> form("#save-puzzle-form", %{"name" => other}) |> render_submit()

      render_change(element(view, ~s{form[phx-change="filter_saves"]}), %{"term" => "keeper"})

      kept = Enum.find(Sudoku.Game.list_saved_puzzles!(), &(&1.name == keep))
      hidden = Enum.find(Sudoku.Game.list_saved_puzzles!(), &(&1.name == other))

      # Scoped to the rows — the flash still names the last puzzle saved.
      assert has_element?(view, ~s{[phx-click="load_puzzle"][phx-value-id="#{kept.id}"]})
      refute has_element?(view, ~s{[phx-click="load_puzzle"][phx-value-id="#{hidden.id}"]})
    end

    test "a puzzle cannot be saved before it is finalized", %{conn: conn} do
      view = blank_game(conn)
      view |> element(~s{[phx-click="start_manual_entry"]}) |> render_click()
      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()

      refute has_element?(view, "#save-puzzle-form")
    end

    test "refuses a blank name", %{conn: conn} do
      view = blank_game(conn)
      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()

      html = view |> form("#save-puzzle-form", %{"name" => "   "}) |> render_submit()

      assert html =~ "Give the puzzle a name first"
    end

    test "deletes a save", %{conn: conn} do
      name = "Doomed #{System.unique_integer([:positive])}"
      view = blank_game(conn)

      view |> element(~s{[phx-click="toggle_saves"]}) |> render_click()
      view |> form("#save-puzzle-form", %{"name" => name}) |> render_submit()

      saved = Enum.find(Sudoku.Game.list_saved_puzzles!(), &(&1.name == name))

      view
      |> element(~s{[phx-click="delete_puzzle"][phx-value-id="#{saved.id}"]})
      |> render_click()

      # Scoped to the list — the "Saved as ..." flash still mentions the name.
      refute has_element?(view, ~s{[phx-click="load_puzzle"][phx-value-id="#{saved.id}"]})
      refute Enum.any?(Sudoku.Game.list_saved_puzzles!(), &(&1.id == saved.id))
    end
  end
end
