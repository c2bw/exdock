defmodule ExdockWeb.PageController do
  use ExdockWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
