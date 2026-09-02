defmodule SudokuWeb.GameLive do
  use SudokuWeb, :live_view

  alias Sudoku.Game.Board
  alias Sudoku.Game.Play
  alias Sudoku.Game.Position
  alias Sudoku.Game.Puzzle
  alias Sudoku.Game.SavedState

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_tick()

    {:ok,
     assign(socket,
       play: Play.new(Sudoku.Game.new_game!(:medium)),
       page_title: "Sudoku",
       show_saves: false,
       search_term: "",
       only_custom: false,
       saved_puzzles: list_saves("", false),
       save_form: save_form()
     )}
  end

  # ── Persistence: localStorage restore ────────────────────────────────────

  # The browser hands back whatever it was given, so what it hands back may be
  # from an older game than this one. `SavedState` is what judges it; a payload
  # this version cannot read is dropped rather than guessed at.
  @impl true
  def handle_event("restore_board", payload, socket) do
    case SavedState.from_payload(payload) do
      {:ok, state} -> {:noreply, act(socket, SavedState.resume_intent(state))}
      {:error, _refusal} -> {:noreply, push_event(socket, "clear_board", %{})}
    end
  end

  # ── Board interaction ────────────────────────────────────────────────────

  # A plain click starts a new selection; Ctrl/Cmd/Shift adds to or removes
  # from the one already there.
  def handle_event("select_cell", %{"row" => row, "col" => col} = params, socket) do
    how = if params["additive"], do: :toggle, else: :replace
    {:noreply, act(socket, {:select, {to_int(row), to_int(col)}, how})}
  end

  # Dragging across the grid sweeps cells into the selection.
  def handle_event("extend_selection", %{"row" => row, "col" => col}, socket) do
    {:noreply, act(socket, {:select, {to_int(row), to_int(col)}, :extend})}
  end

  def handle_event("undo", _params, socket), do: {:noreply, act(socket, :undo)}
  def handle_event("redo", _params, socket), do: {:noreply, act(socket, :redo)}

  def handle_event("input_number", %{"number" => "clear"}, socket),
    do: {:noreply, act(socket, :clear)}

  def handle_event("input_number", %{"number" => number}, socket),
    do: {:noreply, act(socket, {:digit, String.to_integer(number)})}

  def handle_event("set_input_mode", %{"mode" => mode}, socket),
    do: {:noreply, act(socket, {:input_mode, String.to_existing_atom(mode)})}

  # ── Keyboard ─────────────────────────────────────────────────────────────

  # Keystrokes aimed at a text box are not moves.
  def handle_event("keydown", %{"inField" => true}, socket), do: {:noreply, socket}

  # Undo/redo answer to both the Mac and the Windows convention.
  # Unmodified, Z is the Normal-mode hotkey, so only claim it with Ctrl/Cmd.
  def handle_event("keydown", %{"code" => "KeyZ"} = params, socket) do
    if modified?(params),
      do: {:noreply, act(socket, :undo)},
      else: {:noreply, act(socket, {:input_mode, :normal})}
  end

  def handle_event("keydown", %{"code" => "KeyY"} = params, socket) do
    if modified?(params), do: {:noreply, act(socket, :redo)}, else: {:noreply, socket}
  end

  # Ctrl+A selects everything; adding Shift clears the selection instead.
  def handle_event("keydown", %{"code" => "KeyA"} = params, socket) do
    cond do
      not modified?(params) -> {:noreply, socket}
      params["shiftKey"] == true -> {:noreply, act(socket, :clear_selection)}
      true -> {:noreply, act(socket, :select_all)}
    end
  end

  # Cmd/Alt combos beyond those belong to the browser and the OS.
  def handle_event("keydown", %{"metaKey" => true}, socket), do: {:noreply, socket}
  def handle_event("keydown", %{"altKey" => true}, socket), do: {:noreply, socket}

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, socket |> assign(show_saves: false) |> act(:clear_selection)}
  end

  def handle_event("keydown", params, socket) do
    case params do
      %{"key" => key} when key in ~w(Backspace Delete) ->
        {:noreply, act(socket, {:clear, modifier_mode(params)})}

      %{"key" => "Arrow" <> direction} ->
        {:noreply, act(socket, {:move_cursor, arrow(direction), extending?(params)})}

      %{"key" => " "} ->
        {:noreply, act(socket, :cycle_input_mode)}

      # Z/X/C jump straight to a mode instead of cycling through with Space.
      %{"code" => code} when code in ~w(KeyZ KeyX KeyC) ->
        {:noreply, act(socket, {:input_mode, mode_for_key(code)})}

      _ ->
        case digit_from(params) do
          nil -> {:noreply, socket}
          digit -> {:noreply, act(socket, {:digit, digit, modifier_mode(params)})}
        end
    end
  end

  def handle_event("toggle_timer", _params, socket), do: {:noreply, act(socket, :toggle_timer)}

  def handle_event("check_board", _params, socket) do
    socket = act(socket, :check)

    case socket.assigns.play.check do
      :unsolvable ->
        {:noreply, put_flash(socket, :error, "This puzzle has no solution to check against.")}

      :checked ->
        wrong = socket.assigns.play.check_errors

        message =
          case MapSet.size(wrong) do
            0 -> "Everything so far matches the solution."
            1 -> "One entry can't be right — it's highlighted."
            n -> "#{n} entries can't be right — they're highlighted."
          end

        kind = if MapSet.size(wrong) == 0, do: :info, else: :error

        # Without clearing first, an earlier "all clear" toast would sit next to
        # the new complaint.
        {:noreply, socket |> clear_flash() |> put_flash(kind, message)}
    end
  end

  # ── Game lifecycle ───────────────────────────────────────────────────────

  # The difficulty arrives as a string; `Sudoku.Game.Difficulty` is what turns it
  # back into an atom, and refuses anything that is not one.
  def handle_event("new_game", %{"difficulty" => difficulty}, socket) do
    board = Sudoku.Game.new_game!(difficulty)

    {:noreply, socket |> assign(play: Play.new(board)) |> push_save()}
  end

  def handle_event("start_manual_entry", _params, socket) do
    play = Play.new(Sudoku.Game.blank_board!(), mode: :manual_entry)

    {:noreply, socket |> assign(play: play) |> push_save()}
  end

  def handle_event("finalize_board", _params, socket), do: {:noreply, act(socket, :finalize)}

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
    attrs = socket.assigns.play |> SavedState.from_play() |> SavedState.to_saved_puzzle_attrs()

    case Sudoku.Game.save_puzzle(name, attrs) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(show_saves: true, save_form: save_form())
         |> refresh_saves()
         |> push_event("reset_save_form", %{})
         |> put_flash(:info, "Saved as \"#{saved.name}\".")}

      {:error, refusal} ->
        {:noreply, put_flash(socket, :error, save_refusal(refusal))}
    end
  end

  def handle_event("load_puzzle", %{"id" => id}, socket) do
    saved = Sudoku.Game.get_saved_puzzle!(id)
    play = Sudoku.Game.resume_saved_puzzle!(saved)

    {:noreply, socket |> open(play) |> put_flash(:info, "Loaded \"#{saved.name}\".")}
  end

  # The save keeps its own progress until it is saved over.
  def handle_event("restart_puzzle", %{"id" => id}, socket) do
    saved = Sudoku.Game.get_saved_puzzle!(id)
    play = saved |> Sudoku.Game.restart_saved_puzzle!() |> Play.new()

    {:noreply,
     socket
     |> open(play)
     |> put_flash(:info, "Restarted \"#{saved.name}\" from its givens.")}
  end

  def handle_event("delete_puzzle", %{"id" => id}, socket) do
    id |> Sudoku.Game.get_saved_puzzle!() |> Sudoku.Game.delete_saved_puzzle!()
    {:noreply, refresh_saves(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, act(socket, :tick)}
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, 1000)

  # ── Driving the play ─────────────────────────────────────────────────────

  # Every intent goes through here: hand it to the game, keep what comes back,
  # and mirror it into the browser's storage when the game says the saved state
  # moved.
  defp act(socket, intent) do
    play = socket.assigns.play
    updated = Play.act(play, intent)
    socket = assign(socket, play: updated)

    if updated.revision == play.revision, do: socket, else: push_save(socket)
  end

  defp open(socket, play) do
    socket |> assign(play: play, show_saves: false) |> push_save()
  end

  # ── Keyboard decoding ────────────────────────────────────────────────────

  defp mode_for_key("KeyZ"), do: :normal
  defp mode_for_key("KeyX"), do: :corner
  defp mode_for_key("KeyC"), do: :center

  # Shift and Ctrl reach for corner/centre marks without leaving the digit row,
  # matching the convention used by SudokuPad and f-puzzles.
  defp modifier_mode(%{"shiftKey" => true}), do: :corner
  defp modifier_mode(%{"ctrlKey" => true}), do: :center
  defp modifier_mode(_params), do: nil

  defp arrow("Up"), do: :up
  defp arrow("Down"), do: :down
  defp arrow("Left"), do: :left
  defp arrow("Right"), do: :right

  defp modified?(params), do: params["ctrlKey"] == true or params["metaKey"] == true

  # Holding Shift or Ctrl while arrowing grows the selection instead of moving it.
  defp extending?(params), do: params["shiftKey"] == true or modified?(params)

  # Shift turns "1" into "!", so fall back to the physical key code.
  defp digit_from(%{"key" => key}) when key in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(key)

  defp digit_from(%{"code" => "Digit" <> d}) when d in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(d)

  defp digit_from(%{"code" => "Numpad" <> d}) when d in ~w(1 2 3 4 5 6 7 8 9),
    do: String.to_integer(d)

  defp digit_from(_params), do: nil

  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) when is_binary(value), do: String.to_integer(value)

  # ── Browser storage ──────────────────────────────────────────────────────

  # The browser keeps an opaque blob; `SavedState` decides what is in it.
  defp push_save(socket) do
    payload = socket.assigns.play |> SavedState.from_play() |> SavedState.to_payload()

    push_event(socket, "save_board", payload)
  end

  # ── The saved-puzzle library ─────────────────────────────────────────────

  defp list_saves(term, only_custom) do
    Sudoku.Game.list_saved_puzzles!(%{term: term, only_custom: only_custom})
  end

  defp refresh_saves(socket) do
    assign(socket,
      saved_puzzles: list_saves(socket.assigns.search_term, socket.assigns.only_custom)
    )
  end

  defp save_form, do: to_form(%{"name" => ""})

  # The `:save` action decides what may be saved; this only says so in words.
  defp save_refusal(error) do
    fields = error |> Map.get(:errors, []) |> Enum.map(&Map.get(&1, :field))

    cond do
      :mode in fields -> "Finalize the puzzle before saving it."
      :name in fields -> "Give the puzzle a name first."
      true -> "That puzzle could not be saved."
    end
  end

  # "12 / 51" — squares filled in, out of the squares the puzzle leaves blank.
  defp progress(puzzle) do
    {Puzzle.solved_count(puzzle.cells), Puzzle.blank_count(puzzle.givens)}
  end

  # ── Rendering helpers ────────────────────────────────────────────────────

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

  defp cell_classes(cell, play) do
    base =
      "relative flex items-center justify-center aspect-square cursor-pointer select-none border border-base-300 transition-colors"

    position = {cell.row, cell.col}
    selected? = MapSet.member?(play.selection, position)

    # Peer shading only helps when you are looking at one cell; across a
    # sweep it would light up most of the grid.
    peer? = single_selection_peer?(play, cell)

    bg =
      cond do
        selected? -> " bg-primary/20"
        position in play.blocked_cells -> " !bg-warning/20"
        peer? -> " bg-base-200"
        true -> ""
      end

    given = if cell.given, do: " font-bold text-base-content", else: " text-primary"

    invalid =
      cond do
        position in play.check_errors -> " !text-error !bg-error/20"
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

  defp single_selection_peer?(play, cell) do
    case MapSet.to_list(play.selection) do
      [selected] ->
        position = {cell.row, cell.col}
        position == selected or Position.peers?(position, selected)

      _many ->
        false
    end
  end

  defp marks_at(marks, cell) do
    marks
    |> Map.get(Position.key({cell.row, cell.col}), MapSet.new())
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

  defp difficulty_label(difficulty), do: difficulty |> to_string() |> String.capitalize()
end
