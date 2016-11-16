defmodule Hivent do
  @moduledoc """
  The main Hivent application. It starts an Agent that holds a persistent
  connection to the Redis backend.
  """
  use Application

  def start(_type, _args) do
    Agent.start_link fn -> initial_state end, name: __MODULE__
  end

  def emit(name, payload, options) do
    redis
    |> Hivent.Producer.emit(name, payload, options)
  end

  defp initial_state do
    {:ok, client} = Hivent.Redis.start_link :hivent_redis, Hivent.Config.get(:hivent, :endpoint)

    %{redis: client}
  end

  defp redis do
    Agent.get(__MODULE__, &Map.get(&1, :redis))
  end
end
