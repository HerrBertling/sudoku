defmodule Sudoku.Game.PositionTest do
  use ExUnit.Case, async: true

  alias Sudoku.Game.Position

  doctest Sudoku.Game.Position

  describe "key/1 and from_key/1" do
    test "a key spells out row then column" do
      assert Position.key({0, 0}) == "0,0"
      assert Position.key({8, 8}) == "8,8"
      assert Position.key({3, 5}) == "3,5"
    end

    test "every position on the board survives the round trip" do
      for row <- 0..8, col <- 0..8 do
        assert Position.from_key(Position.key({row, col})) == {row, col}
      end
    end

    test "reading a key back gives integers, not strings" do
      assert Position.from_key("2,7") == {2, 7}
    end
  end

  describe "box/1" do
    test "boxes are numbered left to right, top to bottom" do
      assert Position.box({0, 0}) == 0
      assert Position.box({2, 2}) == 0
      assert Position.box({0, 8}) == 2
      assert Position.box({4, 4}) == 4
      assert Position.box({4, 7}) == 5
      assert Position.box({8, 0}) == 6
      assert Position.box({8, 8}) == 8
    end

    test "each box holds exactly nine positions" do
      counts =
        for row <- 0..8, col <- 0..8, reduce: %{} do
          acc -> Map.update(acc, Position.box({row, col}), 1, &(&1 + 1))
        end

      assert counts == Map.new(0..8, &{&1, 9})
    end
  end

  describe "peers/1" do
    test "a position has exactly 20 peers" do
      for row <- 0..8, col <- 0..8 do
        assert MapSet.size(Position.peers({row, col})) == 20
      end
    end

    test "peers are the row, the column and the box, minus the position itself" do
      peers = Position.peers({4, 4})

      assert MapSet.member?(peers, {4, 0})
      assert MapSet.member?(peers, {0, 4})
      assert MapSet.member?(peers, {3, 3})
      assert MapSet.member?(peers, {5, 5})

      refute MapSet.member?(peers, {4, 4})
      refute MapSet.member?(peers, {0, 0})
      refute MapSet.member?(peers, {8, 0})
    end

    test "being a peer is mutual" do
      for row <- 0..8, col <- 0..8, peer <- Position.peers({row, col}) do
        assert Position.peers?(peer, {row, col})
      end
    end
  end

  describe "peers?/2" do
    test "same row, same column and same box are all peers" do
      assert Position.peers?({0, 0}, {0, 5})
      assert Position.peers?({0, 0}, {5, 0})
      assert Position.peers?({0, 0}, {1, 1})
    end

    test "a position is not its own peer" do
      refute Position.peers?({0, 0}, {0, 0})
    end

    test "unrelated positions are not peers" do
      refute Position.peers?({0, 0}, {4, 5})
      refute Position.peers?({8, 8}, {0, 7})
    end
  end
end
