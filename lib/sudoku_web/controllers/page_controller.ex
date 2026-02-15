defmodule SudokuWeb.PageController do
  use SudokuWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
