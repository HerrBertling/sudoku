defmodule SudokuWeb.GameLive do
  use SudokuWeb, :live_view

  alias Sudoku.Game.Puzzle

  @storage_version 2

  # How many steps back Undo can reach.
  @history_limit 200

  @impl true
  def mount(_params, _session, socket) do
    board = Sudoku.Game.new_game!(:medium)
    if connected?(socket), do: schedule_tick()

    {:ok,
     assign(socket,
       board: board,
       page_title: "Sudoku",
       selection: MapSet.new(),
       cursor: nil,
       history: [],
       future: [],
       elapsed: 0,
       timer_running: true,
       check_errors: MapSet.new(),
       highlighted_number: nil,
       corner_marks: %{},
       center_marks: %{},
       input_mode: :normal,
       mode: :playing,
       solution_count: nil,
       show_saves: false,
       search_term: "",
       only_custom: false,
       saved_puzzles: list_saves("", false),
       save_form: save_form()
     )}
  end

  # ── Persistence: localStorage restore ────────────────────────────────────

  @impl true
  def handle_event("restore_board", params, socket) do
    %{"cells" => cells_data, "difficulty" => difficulty} = params

    cells =
      Enum.map(cells_data, fn c ->
        %Sudoku.Game.Cell{
          row: c["row"],
          col: c["col"],
          value: c["value"],
          given: c["given"],
          valid: c["valid"]
        }
      end)

    mode = if params["mode"] == "manual_entry", do: :manual_entry, else: :playing
    board = build_board(cells, String.to_existing_atom(difficulty))

    {:noreply,
     assign(socket,
       board: board,
       corner_marks: marks_from_json(params["corner_marks"]),
       center_marks: marks_from_json(params["center_marks"]),
       mode: mode,
       solution_count: if(mode == :manual_entry, do: solution_count(board), else: nil),
       history: [],
       future: []
     )}
  end

  # ── Board interaction ────────────────────────────────────────────────────

  # A plain click starts a new selection; Ctrl/Cmd/Shift adds to or removes
  # from the one already there.
  def handle_event("select_cell", %{"row" => row, "col" => col} = params, socket) do
    cell = {to_int(row), to_int(col)}

    selection =
      if params["additive"] do
        toggle_member(socket.assigns.selection, cell)
      else
        MapSet.new([cell])
      end

    {:noreply, assign(socket, selection: selection, cursor: cell)}
  end

  # Dragging across the grid sweeps cells into the selection.
  def handle_event("extend_selection", %{"row" => row, "col" => col}, socket) do
    cell = {to_int(row), to_int(col)}

    {:noreply,
     assign(socket,
       selection: MapSet.put(socket.assigns.selection, cell),
       cursor: cell
     )}
  end

  def handle_event("select_all", _params, socket) do
    {:noreply, assign(socket, selection: all_cells(), cursor: socket.assigns.cursor || {0, 0})}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selection: MapSet.new())}
  end

  def handle_event("undo", _params, socket), do: {:noreply, undo(socket)}
  def handle_event("redo", _params, socket), do: {:noreply, redo(socket)}

  def handle_event("input_number", %{"number" => "clear"}, socket) do
    {:noreply, clear_selected(socket, active_mode(socket))}
  end

  def handle_event("input_number", %{"number" => number}, socket) do
    {:noreply, apply_digit(socket, String.to_integer(number), active_mode(socket))}
  end

  def handle_event("set_input_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, input_mode: String.to_existing_atom(mode))}
  end

  # ── Keyboard ─────────────────────────────────────────────────────────────

  # Keystrokes aimed at a text box are not moves.
  def handle_event("keydown", %{"inField" => true}, socket), do: {:noreply, socket}

  # Undo/redo answer to both the Mac and the Windows convention.
  # Unmodified, Z is the Normal-mode hotkey, so only claim it with Ctrl/Cmd.
  def handle_event("keydown", %{"code" => "KeyZ"} = params, socket) when is_map(params) do
    if modified?(params) do
      {:noreply, undo(socket)}
    else
      {:noreply, assign(socket, input_mode: :normal)}
    end
  end

  def handle_event("keydown", %{"code" => "KeyY"} = params, socket) do
    if modified?(params), do: {:noreply, redo(socket)}, else: {:noreply, socket}
  end

  def handle_event("keydown", %{"code" => "KeyA"} = params, socket) do
    if modified?(params), do: {:noreply, select_all(socket, params)}, else: {:noreply, socket}
  end

  # Cmd/Alt combos beyond those belong to the browser and the OS.
  def handle_event("keydown", %{"metaKey" => true}, socket), do: {:noreply, socket}
  def handle_event("keydown", %{"altKey" => true}, socket), do: {:noreply, socket}

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, show_saves: false, selection: MapSet.new())}
  end

  def handle_event("keydown", params, socket) do
    case params do
      %{"key" => key} when key in ~w(Backspace Delete) ->
        {:noreply, clear_selected(socket, keyed_mode(params, socket))}

      %{"key" => "Arrow" <> _ = key} ->
        {:noreply, move_cursor(socket, key, extending?(params))}

      %{"key" => " "} ->
        {:noreply, assign(socket, input_mode: next_mode(socket.assigns.input_mode))}

      # Z/X/C jump straight to a mode instead of cycling through with Space.
      %{"code" => code} when code in ~w(KeyZ KeyX KeyC) ->
        {:noreply, assign(socket, input_mode: mode_for_key(code))}

      _ ->
        case digit_from(params) do
          nil -> {:noreply, socket}
          digit -> {:noreply, apply_digit(socket, digit, keyed_mode(params, socket))}
        end
    end
  end

  def handle_event("toggle_timer", _params, socket) do
    {:noreply, assign(socket, timer_running: !socket.assigns.timer_running)}
  end

  # Checks the entries so far against the puzzle's own solution, rather than
  # only spotting a contradiction once two entries collide.
  def handle_event("check_board", _params, socket) do
    board = socket.assigns.board

    case wrong_entries(board) do
      :unsolvable ->
        {:noreply, put_flash(socket, :error, "This puzzle has no solution to check against.")}

      wrong ->
        message =
          case MapSet.size(wrong) do
            0 -> "Everything so far matches the solution."
            1 -> "One entry can't be right — it's highlighted."
            n -> "#{n} entries can't be right — they're highlighted."
          end

        kind = if MapSet.size(wrong) == 0, do: :info, else: :error

        # Without clearing first, an earlier "all clear" toast would sit next to
        # the new complaint.
        {:noreply,
         socket
         |> assign(check_errors: wrong)
         |> clear_flash()
         |> put_flash(kind, message)}
    end
  end

  def handle_event("toggle_highlight", %{"number" => number}, socket) do
    {:noreply, toggle_highlight(socket, String.to_integer(number))}
  end

  # ── Game lifecycle ───────────────────────────────────────────────────────

  def handle_event("new_game", %{"difficulty" => difficulty}, socket) do
    board = Sudoku.Game.new_game!(String.to_existing_atom(difficulty))

    {:noreply,
     socket
     |> reset_for(board, :playing)
     |> push_save()}
  end

  def handle_event("start_manual_entry", _params, socket) do
    cells =
      for row <- 0..8, col <- 0..8 do
        %Sudoku.Game.Cell{row: row, col: col, value: nil, given: false, valid: true}
      end

    {:noreply,
     socket
     |> reset_for(build_board(cells, :custom), :manual_entry)
     |> assign(solution_count: 0)
     |> push_save()}
  end

  def handle_event("finalize_board", _params, socket) do
    board = socket.assigns.board
    cells = Enum.map(board.cells, fn c -> if c.value, do: %{c | given: true}, else: c end)

    {:noreply,
     socket
     |> assign(board: %{board | cells: cells}, mode: :playing, solution_count: nil)
     |> forget_history()
     |> push_save()}
  end

  # ── Saved puzzles (SQLite) ───────────────────────────────────────────────

  def handle_event("toggle_saves", _params, socket) do
    socket = assign(socket, show_saves: !socket.assigns.show_saves)
    {:noreply, refresh_saves(socket)}
  end

  def handle_event("filter_saves", %{"term" => term}, socket) do
    {:noreply, socket |> assign(search_term: term) |> refresh_saves()}
  end

  def handle_event("toggle_only_custom", _params, socket) do
    {:noreply, socket |> assign(only_custom: !socket.assigns.only_custom) |> refresh_saves()}
  end

  def handle_event("save_puzzle", %{"name" => name}, socket) do
    case String.trim(name) do
      "" ->
        {:noreply, put_flash(socket, :error, "Give the puzzle a name first.")}

      _name when socket.assigns.mode == :manual_entry ->
        {:noreply, put_flash(socket, :error, "Finalize the puzzle before saving it.")}

      name ->
        board = socket.assigns.board

        Sudoku.Game.save_puzzle!(name, %{
          difficulty: board.difficulty,
          givens: Puzzle.encode(board.cells),
          cells: board.cells,
          corner_marks: marks_to_json(socket.assigns.corner_marks),
          center_marks: marks_to_json(socket.assigns.center_marks),
          elapsed_seconds: socket.assigns.elapsed
        })

        {:noreply,
         socket
         |> assign(show_saves: true, save_form: save_form())
         |> refresh_saves()
         |> push_event("reset_save_form", %{})
         |> put_flash(:info, "Saved as \"#{name}\".")}
    end
  end

  def handle_event("load_puzzle", %{"id" => id}, socket) do
    saved = Sudoku.Game.get_saved_puzzle!(id)

    {:noreply,
     socket
     |> open_saved(
       saved,
       saved.cells,
       marks_from_json(saved.corner_marks),
       marks_from_json(saved.center_marks),
       saved.elapsed_seconds
     )
     |> put_flash(:info, "Loaded \"#{saved.name}\".")}
  end

  # Rebuilds the board from the stored puzzle definition, dropping every entry
  # and mark. The save keeps its own progress until it is saved over.
  def handle_event("restart_puzzle", %{"id" => id}, socket) do
    saved = Sudoku.Game.get_saved_puzzle!(id)

    {:noreply,
     socket
     |> open_saved(saved, Puzzle.decode(saved.givens), %{}, %{}, 0)
     |> put_flash(:info, "Restarted \"#{saved.name}\" from its givens.")}
  end

  def handle_event("delete_puzzle", %{"id" => id}, socket) do
    id |> Sudoku.Game.get_saved_puzzle!() |> Sudoku.Game.delete_saved_puzzle!()
    {:noreply, refresh_saves(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    schedule_tick()

    if socket.assigns.timer_running and socket.assigns.board.status == :playing do
      {:noreply, assign(socket, elapsed: socket.assigns.elapsed + 1)}
    else
      {:noreply, socket}
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, 1000)

  defp open_saved(socket, saved, cells, corner_marks, center_marks, elapsed) do
    socket
    |> assign(
      board: build_board(cells, saved.difficulty),
      corner_marks: corner_marks,
      center_marks: center_marks,
      mode: :playing,
      input_mode: :normal,
      highlighted_number: nil,
      solution_count: nil,
      show_saves: false,
      selection: MapSet.new(),
      cursor: nil,
      elapsed: elapsed,
      timer_running: true
    )
    |> forget_history()
    |> clear_check()
    |> push_save()
  end

  # ── Digit input ──────────────────────────────────────────────────────────

  defp apply_digit(socket, digit, :highlight), do: toggle_highlight(socket, digit)

  defp apply_digit(socket, digit, :normal) do
    mutate(socket, fn socket ->
      Enum.reduce(selected_cells(socket), socket, fn {row, col}, socket ->
        place_value(socket, row, col, digit)
      end)
    end)
  end

  defp apply_digit(socket, digit, mode) when mode in [:corner, :center] do
    key = if mode == :corner, do: :corner_marks, else: :center_marks
    mutate(socket, fn socket -> toggle_marks(socket, key, digit) end)
  end

  defp place_value(socket, row, col, value) do
    case Sudoku.Game.place_number(socket.assigns.board, row, col, value) do
      {:ok, board} ->
        socket
        # A confirmed digit supersedes any pencil marks in that cell.
        |> assign(board: board)
        |> drop_marks(row, col)
        |> refresh_solution_count()

      {:error, _} ->
        socket
    end
  end

  # Across a selection the digit toggles as a group: it goes onto every
  # eligible cell unless they all carry it already, in which case it comes off
  # all of them. Toggling cell by cell would just scramble a mixed selection.
  defp toggle_marks(socket, key, digit) do
    cells = Enum.filter(selected_cells(socket), &markable?(socket, &1))

    if cells == [] do
      socket
    else
      marks = socket.assigns[key]
      remove? = Enum.all?(cells, fn cell -> digit in marks_for(marks, cell) end)

      marks =
        Enum.reduce(cells, marks, fn cell, marks ->
          current = marks_for(marks, cell)

          updated =
            if remove?, do: MapSet.delete(current, digit), else: MapSet.put(current, digit)

          put_marks(marks, cell, updated)
        end)

      assign(socket, key, marks)
    end
  end

  # Marks describe what *might* go in an empty cell, so a filled or given cell
  # has nothing to mark.
  defp markable?(socket, {row, col}) do
    case cell_at(socket.assigns.board, row, col) do
      nil -> false
      cell -> not cell.given and is_nil(cell.value)
    end
  end

  defp marks_for(marks, {row, col}), do: Map.get(marks, cell_key(row, col), MapSet.new())

  defp put_marks(marks, {row, col}, set) do
    if MapSet.size(set) == 0,
      do: Map.delete(marks, cell_key(row, col)),
      else: Map.put(marks, cell_key(row, col), set)
  end

  # Clearing narrows to whatever the current mode writes: Normal empties the
  # cell outright, Corner and Centre take only their own marks with them.
  defp clear_selected(socket, :highlight), do: assign(socket, highlighted_number: nil)

  defp clear_selected(socket, :corner), do: clear_marks(socket, :corner_marks)
  defp clear_selected(socket, :center), do: clear_marks(socket, :center_marks)

  defp clear_selected(socket, :normal) do
    mutate(socket, fn socket ->
      Enum.reduce(selected_cells(socket), socket, fn {row, col}, socket ->
        place_value(socket, row, col, nil)
      end)
    end)
  end

  defp clear_marks(socket, key) do
    mutate(socket, fn socket ->
      marks =
        Enum.reduce(selected_cells(socket), socket.assigns[key], fn {row, col}, marks ->
          Map.delete(marks, cell_key(row, col))
        end)

      assign(socket, key, marks)
    end)
  end

  defp drop_marks(socket, row, col) do
    key = cell_key(row, col)

    assign(socket,
      corner_marks: Map.delete(socket.assigns.corner_marks, key),
      center_marks: Map.delete(socket.assigns.center_marks, key)
    )
  end

  # ── Undo / redo ──────────────────────────────────────────────────────────

  # Runs a change and records the state it replaced, but only when something
  # actually moved — otherwise a stray keypress would cost an Undo step.
  defp mutate(socket, fun) do
    before = snapshot(socket)
    updated = fun.(socket)

    if snapshot(updated) == before do
      updated
    else
      updated
      |> assign(
        history: [before | Enum.take(updated.assigns.history, @history_limit - 1)],
        future: []
      )
      |> clear_check()
      |> push_save()
    end
  end

  defp snapshot(socket) do
    %{
      cells: socket.assigns.board.cells,
      corner_marks: socket.assigns.corner_marks,
      center_marks: socket.assigns.center_marks
    }
  end

  defp restore(socket, snap) do
    board = socket.assigns.board

    socket
    |> assign(
      board: %{board | cells: snap.cells, status: board_status(snap.cells)},
      corner_marks: snap.corner_marks,
      center_marks: snap.center_marks
    )
    |> refresh_solution_count()
    |> clear_check()
    |> push_save()
  end

  defp undo(socket) do
    case socket.assigns.history do
      [] ->
        socket

      [previous | rest] ->
        current = snapshot(socket)

        socket
        |> restore(previous)
        |> assign(history: rest, future: [current | socket.assigns.future])
    end
  end

  defp redo(socket) do
    case socket.assigns.future do
      [] ->
        socket

      [next | rest] ->
        current = snapshot(socket)

        socket
        |> restore(next)
        |> assign(history: [current | socket.assigns.history], future: rest)
    end
  end

  defp forget_history(socket), do: assign(socket, history: [], future: [])

  defp clear_check(socket), do: assign(socket, check_errors: MapSet.new())

  # Solves from the givens alone — solving from the current board would fail
  # the moment a wrong entry made it unsolvable, which is exactly when you
  # want an answer.
  defp wrong_entries(board) do
    givens = board.cells |> Puzzle.encode() |> Puzzle.decode()

    grid =
      for row <- 0..8 do
        for col <- 0..8 do
          case cell_at_list(givens, row, col) do
            nil -> 0
            cell -> cell.value || 0
          end
        end
      end

    case Sudoku.Game.Solver.solve(grid) do
      :error ->
        :unsolvable

      {:ok, solution} ->
        for cell <- board.cells,
            not cell.given,
            not is_nil(cell.value),
            solution[{cell.row, cell.col}] != cell.value,
            into: MapSet.new() do
          {cell.row, cell.col}
        end
    end
  end

  defp cell_at_list(cells, row, col), do: Enum.find(cells, &(&1.row == row and &1.col == col))

  # mm:ss, growing to h:mm:ss only when it has to.
  defp format_elapsed(seconds) do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)
    secs = rem(seconds, 60)
    pad = &String.pad_leading(Integer.to_string(&1), 2, "0")

    if hours > 0,
      do: "#{hours}:#{pad.(minutes)}:#{pad.(secs)}",
      else: "#{pad.(minutes)}:#{pad.(secs)}"
  end

  # ── Selection ────────────────────────────────────────────────────────────

  defp selected_cells(socket), do: MapSet.to_list(socket.assigns.selection)

  defp all_cells, do: MapSet.new(for row <- 0..8, col <- 0..8, do: {row, col})

  defp toggle_member(set, member) do
    if MapSet.member?(set, member), do: MapSet.delete(set, member), else: MapSet.put(set, member)
  end

  # Ctrl+A selects everything; adding Shift clears the selection instead.
  defp select_all(socket, %{"shiftKey" => true}), do: assign(socket, selection: MapSet.new())

  defp select_all(socket, _params),
    do: assign(socket, selection: all_cells(), cursor: cursor(socket))

  defp cursor(socket), do: socket.assigns.cursor || {0, 0}

  defp modified?(params), do: params["ctrlKey"] == true or params["metaKey"] == true

  # Holding Shift or Ctrl while arrowing grows the selection instead of moving it.
  defp extending?(params), do: params["shiftKey"] == true or modified?(params)

  defp toggle_highlight(socket, number) do
    highlighted = if socket.assigns.highlighted_number == number, do: nil, else: number
    assign(socket, highlighted_number: highlighted)
  end

  defp move_cursor(socket, key, extending?) do
    {row, col} = cursor(socket)

    next =
      case key do
        "ArrowUp" -> {Integer.mod(row - 1, 9), col}
        "ArrowDown" -> {Integer.mod(row + 1, 9), col}
        "ArrowLeft" -> {row, Integer.mod(col - 1, 9)}
        "ArrowRight" -> {row, Integer.mod(col + 1, 9)}
      end

    selection =
      if extending?,
        do: MapSet.put(socket.assigns.selection, next),
        else: MapSet.new([next])

    assign(socket, selection: selection, cursor: next)
  end

  defp mode_for_key("KeyZ"), do: :normal
  defp mode_for_key("KeyX"), do: :corner
  defp mode_for_key("KeyC"), do: :center

  # Shift and Ctrl reach for corner/centre marks without leaving the digit row,
  # matching the convention used by SudokuPad and f-puzzles.
  defp keyed_mode(%{"shiftKey" => true}, socket), do: mark_mode(socket, :corner)
  defp keyed_mode(%{"ctrlKey" => true}, socket), do: mark_mode(socket, :center)
  defp keyed_mode(_params, socket), do: active_mode(socket)

  defp mark_mode(socket, mode), do: if(manual_entry?(socket), do: :normal, else: mode)

  defp active_mode(socket) do
    if manual_entry?(socket), do: :normal, else: socket.assigns.input_mode
  end

  defp manual_entry?(socket), do: socket.assigns.mode == :manual_entry

  defp next_mode(:normal), do: :corner
  defp next_mode(:corner), do: :center
  defp next_mode(:center), do: :highlight
  defp next_mode(:highlight), do: :normal

  # Shift turns "1" into "!", so fall back to the physical key code.
  defp digit_from(%{"key" => key}) when key in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(key)

  defp digit_from(%{"code" => "Digit" <> d}) when d in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(d)

  defp digit_from(%{"code" => "Numpad" <> d}) when d in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(d)

  defp digit_from(_params), do: nil

  # ── Board helpers ────────────────────────────────────────────────────────

  defp build_board(cells, difficulty) do
    %Sudoku.Game.Board{
      id: Ash.UUID.generate(),
      cells: cells,
      status: board_status(cells),
      difficulty: difficulty
    }
  end

  defp board_status(cells) do
    if Enum.all?(cells, & &1.value) and Enum.all?(cells, & &1.valid),
      do: :complete,
      else: :playing
  end

  defp reset_for(socket, board, mode) do
    socket
    |> assign(
      board: board,
      mode: mode,
      input_mode: :normal,
      highlighted_number: nil,
      corner_marks: %{},
      center_marks: %{},
      solution_count: nil,
      selection: MapSet.new(),
      cursor: nil,
      elapsed: 0,
      timer_running: true
    )
    |> forget_history()
    |> clear_check()
  end

  defp cell_at(board, row, col), do: Enum.find(board.cells, &(&1.row == row and &1.col == col))

  defp cell_key(row, col), do: "#{row},#{col}"

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  defp refresh_solution_count(socket) do
    if manual_entry?(socket),
      do: assign(socket, solution_count: solution_count(socket.assigns.board)),
      else: socket
  end

  defp solution_count(board) do
    grid =
      for row <- 0..8 do
        for col <- 0..8 do
          case cell_at(board, row, col) do
            nil -> 0
            cell -> cell.value || 0
          end
        end
      end

    Sudoku.Game.Solver.count_solutions(grid, 2)
  end

  # ── Marks serialisation ──────────────────────────────────────────────────

  defp marks_to_json(marks) do
    Map.new(marks, fn {key, digits} -> {key, digits |> MapSet.to_list() |> Enum.sort()} end)
  end

  defp marks_from_json(marks) when is_map(marks) do
    Map.new(marks, fn {key, digits} -> {key, MapSet.new(digits)} end)
  end

  defp marks_from_json(_), do: %{}

  defp list_saves(term, only_custom) do
    Sudoku.Game.list_saved_puzzles!(%{term: term, only_custom: only_custom})
  end

  defp refresh_saves(socket) do
    assign(socket,
      saved_puzzles: list_saves(socket.assigns.search_term, socket.assigns.only_custom)
    )
  end

  # "12 / 51" — squares filled in, out of the squares the puzzle leaves blank.
  defp progress(puzzle) do
    {Puzzle.solved_count(puzzle.cells), Puzzle.blank_count(puzzle.givens)}
  end

  defp save_form, do: to_form(%{"name" => ""})

  defp push_save(socket) do
    board = socket.assigns.board

    push_event(socket, "save_board", %{
      version: @storage_version,
      difficulty: board.difficulty,
      mode: socket.assigns.mode,
      cells:
        Enum.map(board.cells, fn c ->
          %{row: c.row, col: c.col, value: c.value, given: c.given, valid: c.valid}
        end),
      corner_marks: marks_to_json(socket.assigns.corner_marks),
      center_marks: marks_to_json(socket.assigns.center_marks)
    })
  end

  # ── Rendering helpers ────────────────────────────────────────────────────

  defp cell_classes(cell, assigns, blocked_cells) do
    base =
      "relative flex items-center justify-center aspect-square cursor-pointer select-none border border-base-300 transition-colors"

    position = {cell.row, cell.col}
    selected? = MapSet.member?(assigns.selection, position)

    # Peer shading only helps when you are looking at one cell; across a
    # sweep it would light up most of the grid.
    peer? = single_selection_peer?(assigns, cell)

    bg =
      cond do
        selected? -> " bg-primary/20"
        position in blocked_cells -> " !bg-warning/20"
        peer? -> " bg-base-200"
        true -> ""
      end

    given = if cell.given, do: " font-bold text-base-content", else: " text-primary"

    invalid =
      cond do
        position in assigns.check_errors -> " !text-error !bg-error/20"
        cell.value && !cell.valid -> " !text-error !bg-error/10"
        true -> ""
      end

    box_right =
      if rem(cell.col, 3) == 2 and cell.col != 8,
        do: " !border-r-2 !border-r-base-content",
        else: ""

    box_bottom =
      if rem(cell.row, 3) == 2 and cell.row != 8,
        do: " !border-b-2 !border-b-base-content",
        else: ""

    base <> bg <> given <> invalid <> box_right <> box_bottom
  end

  defp single_selection_peer?(assigns, cell) do
    case MapSet.to_list(assigns.selection) do
      [{row, col}] ->
        cell.row == row or cell.col == col or
          (div(cell.row, 3) == div(row, 3) and div(cell.col, 3) == div(col, 3))

      _many ->
        false
    end
  end

  defp blocked_cells_for(nil, _board), do: MapSet.new()

  defp blocked_cells_for(number, board) do
    board.cells
    |> Enum.filter(&(&1.value == number))
    |> Enum.flat_map(fn src ->
      box_row = div(src.row, 3)
      box_col = div(src.col, 3)

      board.cells
      |> Enum.filter(fn c ->
        c.row == src.row or c.col == src.col or
          (div(c.row, 3) == box_row and div(c.col, 3) == box_col)
      end)
      |> Enum.map(&{&1.row, &1.col})
    end)
    |> MapSet.new()
  end

  defp marks_at(marks, cell) do
    marks
    |> Map.get(cell_key(cell.row, cell.col), MapSet.new())
    |> MapSet.to_list()
    |> Enum.sort()
  end

  # Corner marks fill the four corners first, then edges, then the middle —
  # the order players expect from pen-and-paper notation.
  @corner_slots [
    "row-start-1 col-start-1",
    "row-start-1 col-start-3",
    "row-start-3 col-start-1",
    "row-start-3 col-start-3",
    "row-start-1 col-start-2",
    "row-start-3 col-start-2",
    "row-start-2 col-start-1",
    "row-start-2 col-start-3",
    "row-start-2 col-start-2"
  ]

  defp corner_slot(index), do: Enum.at(@corner_slots, index, "row-start-2 col-start-2")

  # Centre marks all share one line, so the type shrinks as the set grows.
  defp center_mark_class(count) when count <= 3, do: "text-[clamp(0.3rem,1.3cqi,0.7rem)]"
  defp center_mark_class(count) when count <= 5, do: "text-[clamp(0.25rem,1.05cqi,0.58rem)]"
  defp center_mark_class(_count), do: "text-[clamp(0.2rem,0.85cqi,0.46rem)]"

  defp mode_label(:normal), do: "Normal"
  defp mode_label(:corner), do: "Corner"
  defp mode_label(:center), do: "Centre"
  defp mode_label(:highlight), do: "Highlight"

  # How many of each digit are still to be placed.
  defp remaining_counts(board) do
    placed = board.cells |> Enum.map(& &1.value) |> Enum.frequencies()
    Map.new(1..9, fn digit -> {digit, 9 - Map.get(placed, digit, 0)} end)
  end

  defp difficulty_label(difficulty), do: difficulty |> to_string() |> String.capitalize()
end
