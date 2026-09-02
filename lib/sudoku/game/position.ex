defmodule Sudoku.Game.Position do
  @moduledoc """
  Where a square sits on the grid — a `{row, col}` pair, both counted from 0 —
  and the geometry that follows from it.

  Two things about a position are needed all over the app, and both used to be
  written out wherever they were needed. The first is how a position is spelled
  as text: `"row,col"`, the key pencil marks are filed under, the string a saved
  puzzle carries to disk, and the value on each square in the DOM so the browser
  can say which cell a player touched. The second is the shape of a Sudoku:
  which squares share a row, a column or a 3x3 box with this one, and so cannot
  repeat its digit. The solver prunes candidates with it, the validator finds
  conflicts with it, and the board shades the squares around the cursor with it.

  Spelled out in each place, the two drift: a change to the key format has to be
  made in Elixir and in JavaScript at once, and the box arithmetic
  `div(row, 3) * 3 + div(col, 3)` is easy to write once and mistype twice. Here
  there is one copy of each, and callers ask instead of computing.

  Peer sets are worked out once, while this module compiles, so asking for them
  is a lookup rather than arithmetic.
  """

  @positions for row <- 0..8, col <- 0..8, do: {row, col}

  @peers (for {row, col} = position <- @positions, into: %{} do
            peers =
              for {r, c} = other <- @positions,
                  other != position,
                  r == row or c == col or
                    (div(r, 3) == div(row, 3) and div(c, 3) == div(col, 3)),
                  do: other

            {position, MapSet.new(peers)}
          end)

  @doc """
  How a position is written down: `"row,col"`.

      iex> Sudoku.Game.Position.key({4, 7})
      "4,7"
  """
  def key({row, col}), do: "#{row},#{col}"

  @doc """
  The position a key names — the other half of `key/1`.

      iex> Sudoku.Game.Position.from_key("4,7")
      {4, 7}
  """
  def from_key(key) do
    [row, col] = String.split(key, ",")
    {String.to_integer(row), String.to_integer(col)}
  end

  @doc """
  Which 3x3 box a position falls in, numbered 0-8 left to right, top to bottom.

      iex> Sudoku.Game.Position.box({4, 7})
      5
  """
  def box({row, col}), do: div(row, 3) * 3 + div(col, 3)

  @doc """
  The 20 other positions this one shares a row, a column or a box with — every
  square that cannot hold the same digit.
  """
  def peers(position), do: Map.fetch!(@peers, position)

  @doc """
  Whether two positions constrain each other. A position is not its own peer.
  """
  def peers?(position, other), do: MapSet.member?(peers(position), other)
end
