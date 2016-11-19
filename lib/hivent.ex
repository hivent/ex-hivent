defmodule Hivent do
  @moduledoc """
  The main Hivent application. It starts an Agent that holds a persistent
  connection to the Redis backend.
  """
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Hivent.Redis, [:redis, Hivent.Config.get(:hivent, :endpoint)]),
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hivent)
  end

  def emit(name, payload, options) do
    redis
    |> Hivent.Producer.emit(name, payload, options)
  end

  def redis do
    Process.whereis(:redis)
  end
end
