defmodule SudokuWeb.GameLive do
  use SudokuWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    board = Sudoku.Game.new_game!(:medium)
    {:ok, assign(socket, board: board, page_title: "Sudoku", highlighted_number: nil, excluded_candidates: %{}, mode: :playing, solution_count: nil)}
  end

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

    board = %Sudoku.Game.Board{
      id: Ash.UUID.generate(),
      cells: cells,
      status: if(Enum.all?(cells, & &1.value) && Enum.all?(cells, & &1.valid), do: :complete, else: :playing),
      difficulty: String.to_existing_atom(difficulty),
      selected_row: nil,
      selected_col: nil
    }

    excluded =
      case params do
        %{"excluded" => exc} when is_map(exc) ->
          Map.new(exc, fn {key, vals} ->
            {key, MapSet.new(vals)}
          end)

        _ ->
          %{}
      end

    mode =
      case params do
        %{"mode" => "manual_entry"} -> :manual_entry
        _ -> :playing
      end

    solution_count = if mode == :manual_entry, do: compute_solution_count(board), else: nil

    {:noreply, assign(socket, board: board, excluded_candidates: excluded, mode: mode, solution_count: solution_count)}
  end

  def handle_event("select_cell", %{"row" => row, "col" => col}, socket) do
    row = String.to_integer(row)
    col = String.to_integer(col)
    board = Sudoku.Game.select_cell!(socket.assigns.board, row, col)
    {:noreply, assign(socket, board: board)}
  end

  def handle_event("place_number", %{"number" => number}, socket) do
    board = socket.assigns.board

    with row when not is_nil(row) <- board.selected_row,
         col when not is_nil(col) <- board.selected_col do
      value = if number == "clear", do: nil, else: String.to_integer(number)

      case Sudoku.Game.place_number(board, row, col, value) do
        {:ok, new_board} ->
          key = "#{row},#{col}"
          excluded = Map.delete(socket.assigns.excluded_candidates, key)

          socket =
            if socket.assigns.mode == :manual_entry do
              solution_count = compute_solution_count(new_board)
              assign(socket, board: new_board, excluded_candidates: excluded, solution_count: solution_count)
            else
              socket
              |> assign(board: new_board, excluded_candidates: excluded)
              |> push_save(new_board, excluded)
            end

          {:noreply, socket}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_candidate", %{"row" => row, "col" => col, "number" => number}, socket) do
    row = String.to_integer(row)
    col = String.to_integer(col)
    number = String.to_integer(number)
    key = "#{row},#{col}"

    excluded = socket.assigns.excluded_candidates
    cell_excluded = Map.get(excluded, key, MapSet.new())

    cell_excluded =
      if number in cell_excluded,
        do: MapSet.delete(cell_excluded, number),
        else: MapSet.put(cell_excluded, number)

    excluded =
      if MapSet.size(cell_excluded) == 0,
        do: Map.delete(excluded, key),
        else: Map.put(excluded, key, cell_excluded)

    {:noreply,
     socket
     |> assign(excluded_candidates: excluded)
     |> push_save(socket.assigns.board, excluded)}
  end

  def handle_event("keydown", %{"key" => key}, socket) when key in ~w(1 2 3 4 5 6 7 8 9) do
    handle_event("place_number", %{"number" => key}, socket)
  end

  def handle_event("keydown", %{"key" => key}, socket) when key in ~w(Backspace Delete) do
    handle_event("place_number", %{"number" => "clear"}, socket)
  end

  def handle_event("keydown", %{"key" => "Arrow" <> _ = key}, socket) do
    board = socket.assigns.board
    row = board.selected_row || 0
    col = board.selected_col || 0

    {new_row, new_col} =
      case key do
        "ArrowUp" -> {Integer.mod(row - 1, 9), col}
        "ArrowDown" -> {Integer.mod(row + 1, 9), col}
        "ArrowLeft" -> {row, Integer.mod(col - 1, 9)}
        "ArrowRight" -> {row, Integer.mod(col + 1, 9)}
      end

    board = Sudoku.Game.select_cell!(board, new_row, new_col)
    {:noreply, assign(socket, board: board)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_highlight", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)

    highlighted =
      if socket.assigns.highlighted_number == number, do: nil, else: number

    {:noreply, assign(socket, highlighted_number: highlighted)}
  end

  def handle_event("new_game", %{"difficulty" => difficulty}, socket) do
    board = Sudoku.Game.new_game!(String.to_existing_atom(difficulty))
    excluded = %{}
    {:noreply, socket |> assign(board: board, highlighted_number: nil, excluded_candidates: excluded, mode: :playing, solution_count: nil) |> push_save(board, excluded)}
  end

  def handle_event("start_manual_entry", _params, socket) do
    cells =
      for row <- 0..8, col <- 0..8 do
        %Sudoku.Game.Cell{row: row, col: col, value: nil, given: false, valid: true}
      end

    board = %Sudoku.Game.Board{
      id: Ash.UUID.generate(),
      cells: cells,
      status: :playing,
      difficulty: :custom,
      selected_row: nil,
      selected_col: nil
    }

    {:noreply, assign(socket, board: board, mode: :manual_entry, highlighted_number: nil, excluded_candidates: %{}, solution_count: 0)}
  end

  def handle_event("finalize_board", _params, socket) do
    board = socket.assigns.board

    cells =
      Enum.map(board.cells, fn c ->
        if c.value, do: %{c | given: true}, else: c
      end)

    board = %{board | cells: cells}
    excluded = %{}

    {:noreply,
     socket
     |> assign(board: board, mode: :playing, excluded_candidates: excluded, solution_count: nil)
     |> push_save(board, excluded)}
  end

  defp cell_classes(cell, board, blocked_cells) do
    base = "flex items-center justify-center aspect-square cursor-pointer select-none border border-base-300 transition-colors"

    selected =
      if cell.row == board.selected_row && cell.col == board.selected_col,
        do: " bg-primary/20",
        else: ""

    highlighted =
      if cell.row == board.selected_row || cell.col == board.selected_col ||
           (board.selected_row && board.selected_col &&
              div(cell.row, 3) == div(board.selected_row, 3) &&
              div(cell.col, 3) == div(board.selected_col, 3)),
        do: " bg-base-200",
        else: ""

    blocked =
      if {cell.row, cell.col} in blocked_cells,
        do: " !bg-warning/20",
        else: ""

    # Selected > blocked > highlighted
    bg =
      cond do
        selected != "" -> selected
        blocked != "" -> blocked
        true -> highlighted
      end

    given = if cell.given, do: " font-bold text-base-content", else: " text-primary"

    invalid =
      if cell.value && !cell.valid,
        do: " !text-error !bg-error/10",
        else: ""

    # Thicker borders for 3x3 box boundaries
    border_right = if rem(cell.col, 3) == 2 && cell.col != 8, do: " !border-r-2 !border-r-base-content", else: ""
    border_bottom = if rem(cell.row, 3) == 2 && cell.row != 8, do: " !border-b-2 !border-b-base-content", else: ""
    border_left = if cell.col == 0, do: "", else: ""
    border_top = if cell.row == 0, do: "", else: ""

    base <> bg <> given <> invalid <> border_right <> border_bottom <> border_left <> border_top
  end

  defp blocked_cells_for(nil, _board, _excluded), do: MapSet.new()

  defp blocked_cells_for(number, board, excluded) do
    # Cells blocked by Sudoku constraints
    sources = Enum.filter(board.cells, &(&1.value == number))

    constraint_blocked =
      sources
      |> Enum.flat_map(fn src ->
        box_row = div(src.row, 3)
        box_col = div(src.col, 3)

        board.cells
        |> Enum.filter(fn c ->
          c.row == src.row || c.col == src.col ||
            (div(c.row, 3) == box_row && div(c.col, 3) == box_col)
        end)
        |> Enum.map(&{&1.row, &1.col})
      end)
      |> MapSet.new()

    # Cells where user manually excluded this number
    user_blocked =
      excluded
      |> Enum.filter(fn {_key, vals} -> number in vals end)
      |> Enum.map(fn {key, _vals} ->
        [r, c] = String.split(key, ",") |> Enum.map(&String.to_integer/1)
        {r, c}
      end)
      |> MapSet.new()

    MapSet.union(constraint_blocked, user_blocked)
  end

  # Returns {possible_by_rules, visible_candidates} where possible_by_rules
  # is before user exclusions and visible_candidates is after.
  defp cell_candidates(cell, board, excluded) do
    if cell.value || cell.given do
      {MapSet.new(), MapSet.new()}
    else
      filled = board.cells |> Enum.filter(& &1.value)
      box_row = div(cell.row, 3)
      box_col = div(cell.col, 3)

      used =
        filled
        |> Enum.filter(fn c ->
          c.row == cell.row || c.col == cell.col ||
            (div(c.row, 3) == box_row && div(c.col, 3) == box_col)
        end)
        |> Enum.map(& &1.value)
        |> MapSet.new()

      possible = MapSet.difference(MapSet.new(1..9), used)
      cell_excluded = Map.get(excluded, "#{cell.row},#{cell.col}", MapSet.new())
      {possible, MapSet.difference(possible, cell_excluded)}
    end
  end

  defp excluded?(cell, number, excluded) do
    cell_excluded = Map.get(excluded, "#{cell.row},#{cell.col}", MapSet.new())
    number in cell_excluded
  end

  defp compute_solution_count(board) do
    grid =
      for row <- 0..8 do
        for col <- 0..8 do
          cell = Enum.find(board.cells, &(&1.row == row && &1.col == col))
          cell.value || 0
        end
      end

    Sudoku.Game.Solver.count_solutions(grid, 2)
  end

  defp push_save(socket, board, excluded, mode \\ :playing) do
    push_event(socket, "save_board", %{
      difficulty: board.difficulty,
      mode: mode,
      cells:
        Enum.map(board.cells, fn c ->
          %{row: c.row, col: c.col, value: c.value, given: c.given, valid: c.valid}
        end),
      excluded:
        Map.new(excluded, fn {key, vals} -> {key, MapSet.to_list(vals)} end)
    })
  end
end
