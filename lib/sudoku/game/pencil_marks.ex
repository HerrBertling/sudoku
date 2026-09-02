defmodule Sudoku.Game.PencilMarks do
  @moduledoc """
  A set of **pencil marks** — the digits a player has written into empty cells —
  and the one description of how they are written down outside the program.

  In memory a mark set is `%{Position.key(position) => MapSet.of(1..9)}`, because
  a mark is toggled on and off and set membership is what that means. Written
  down — into the browser's storage, into a **saved puzzle**'s row — it is
  `%{"row,col" => [1, 2, 9]}`, because JSON has no set and a stored list should
  be stable enough to diff.

  Both forms used to be built by hand in the LiveView, once per direction and
  once per destination. They live here instead: this module is the only thing
  that knows a mark set is keyed by `Sudoku.Game.Position.key/1` and holds
  digits 1-9, and it is the only place that has to change if that ever stops
  being true.

  It is a module of its own rather than part of `Sudoku.Game.SavedState` because
  it is also the storage *type* of the two mark columns on
  `Sudoku.Game.SavedPuzzle`: as an `Ash.Type` it validates what goes into the
  database, which a plain helper called from the web layer could not do. The
  saved-state module owns *what a save contains*; this owns *what a mark set
  looks like*, at every seam it crosses.

  ## Reading is forgiving, writing is not

  `cast_input/2` refuses a mark set that is not keyed by a position or does not
  hold digits, so nothing malformed is ever written. `decode/1` and
  `cast_stored/2` drop what they cannot read instead of failing, so one bad key
  in an old row costs the marks in that cell rather than the whole save.
  """

  use Ash.Type

  @typedoc "Marks as the game holds them."
  @type t :: %{optional(String.t()) => MapSet.t(1..9)}

  @typedoc "Marks as they are written down."
  @type wire :: %{optional(String.t()) => [1..9]}

  @doc """
  Writes a mark set down: digit sets become sorted lists, and a cell whose marks
  have all been rubbed out drops out of the map entirely.

      iex> Sudoku.Game.PencilMarks.encode(%{"0,0" => MapSet.new([7, 2])})
      %{"0,0" => [2, 7]}
  """
  @spec encode(t() | wire()) :: wire()
  def encode(marks) when is_map(marks) do
    for {key, digits} <- marks,
        {:ok, position} <- [position(key)],
        digits = digits(digits),
        digits != [],
        into: %{},
        do: {Sudoku.Game.Position.key(position), digits}
  end

  def encode(_marks), do: %{}

  @doc """
  Reads a mark set back, dropping anything that is not a position holding
  digits.

      iex> Sudoku.Game.PencilMarks.decode(%{"0,0" => [2, 7], "nope" => [1]})
      %{"0,0" => MapSet.new([2, 7])}
  """
  @spec decode(wire() | t() | any()) :: t()
  def decode(marks) do
    marks |> encode() |> Map.new(fn {key, digits} -> {key, MapSet.new(digits)} end)
  end

  # ── Ash.Type ─────────────────────────────────────────────────────────────

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(marks, _constraints) when is_map(marks) do
    if Enum.all?(marks, &markable?/1), do: {:ok, encode(marks)}, else: :error
  end

  def cast_input(_marks, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(marks, _constraints) when is_map(marks), do: {:ok, encode(marks)}
  def cast_stored(_marks, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(marks, _constraints) when is_map(marks), do: {:ok, encode(marks)}
  def dump_to_native(_marks, _constraints), do: :error

  # ── Reading one entry ────────────────────────────────────────────────────

  defp markable?({key, digits}) do
    match?({:ok, _position}, position(key)) and digits(digits) == sorted_digits(digits)
  end

  defp sorted_digits(%MapSet{} = digits), do: digits |> MapSet.to_list() |> Enum.sort()
  defp sorted_digits(digits) when is_list(digits), do: Enum.sort(digits)
  defp sorted_digits(_digits), do: :error

  defp digits(%MapSet{} = digits), do: digits |> MapSet.to_list() |> digits()

  defp digits(digits) when is_list(digits),
    do: digits |> Enum.filter(&(is_integer(&1) and &1 in 1..9)) |> Enum.sort() |> Enum.uniq()

  defp digits(_digits), do: []

  # Deliberately not `Position.from_key/1`: that one is entitled to assume a key
  # it wrote itself, and this is reading whatever storage handed back.
  defp position(key) when is_binary(key) do
    with [row, col] <- String.split(key, ","),
         {row, ""} <- Integer.parse(row),
         {col, ""} <- Integer.parse(col),
         true <- row in 0..8 and col in 0..8 do
      {:ok, {row, col}}
    else
      _other -> :error
    end
  end

  defp position(_key), do: :error
end
