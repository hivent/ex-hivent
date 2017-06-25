defmodule Hivent do
  @moduledoc """
  The main Hivent application. It starts an Agent that holds a persistent
  connection to the Redis backend.
  """
  use Application
  alias Hivent.{Emitter, Redis, Config, Util}

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Redis, [Hivent.Redis, Config.get(:hivent, :endpoint)]),
      supervisor(Phoenix.PubSub.PG2, [:hivent_pubsub, []]),
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Hivent)
  end

  def emit(name, payload, options) do
    redis()
    |> Emitter.emit(name, payload, options)
  end

  def quarantine(event, queue) do
    redis()
    |> Util.quarantine(event, queue)
  end

  def redis do
    Process.whereis(Hivent.Redis)
  end
end
