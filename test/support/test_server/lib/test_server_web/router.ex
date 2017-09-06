defmodule TestServerWeb.Router do
  use TestServerWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TestServerWeb do
    pipe_through :api
  end
end
