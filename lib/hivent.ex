defmodule Hivent do
  @moduledoc """
  The main Hivent application. It starts both a Consumer and an Emitter process.
  """
  use Application
  alias Hivent.Emitter

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Emitter, [[
        host: "localhost",
        port: 4000,
        path: "/producer/websocket",
        client_id: "a_client"
      ]])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hivent)
  end

  def emit(name, payload, options) do
    Process.whereis(Hivent.Emitter)
    |> Hivent.Emitter.emit(name, payload, options)
  end
end
