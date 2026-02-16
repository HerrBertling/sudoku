defmodule SudokuWeb.GameLive do
  use SudokuWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    board = Sudoku.Game.new_game!(:medium)
    {:ok, assign(socket, board: board, page_title: "Sudoku")}
  end

  @impl true
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
        {:ok, new_board} -> {:noreply, assign(socket, board: new_board)}
        {:error, _} -> {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
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

  def handle_event("new_game", %{"difficulty" => difficulty}, socket) do
    board = Sudoku.Game.new_game!(String.to_existing_atom(difficulty))
    {:noreply, assign(socket, board: board)}
  end

  defp cell_classes(cell, board) do
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

    # Selected takes priority over highlighted
    bg = if selected != "", do: selected, else: highlighted

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

  defp candidates(cell, board) do
    if cell.value || cell.given do
      MapSet.new()
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

      MapSet.difference(MapSet.new(1..9), used)
    end
  end
end
