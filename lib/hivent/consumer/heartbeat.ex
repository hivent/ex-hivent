defmodule Hivent.Consumer.Heartbeat do
  @moduledoc """
  The Hivent Heartbeat process. Keeps the current instance alive on the server.
  """
  use GenServer
  import Exredis.Script
  alias Hivent.Config

  defredis_script :heartbeat, file_path: "lib/hivent/lua/heartbeat.lua"

  @default_interval 1_000

  # API
  def start_link(consumer, interval \\ @default_interval) do
    GenServer.start_link(__MODULE__, %{
      consumer: consumer,
      service: service(),
      interval: interval
    }, name: name())
  end

  def init(state) do
    # beat immediately upon starting
    schedule(0)

    {:ok, state}
  end

  # Server
  def handle_info(:beat, state) do
    redis()
    |> heartbeat([], [state[:service], state[:consumer], state[:interval]])

    schedule(state[:interval])
    {:noreply, state}
  end

  defp redis do
    Process.whereis(:redis)
  end

  defp schedule(interval) do
    Process.send_after(self(), :beat, interval)
  end

  defp service, do: Config.get(:hivent, :client_id)

  defp name, do: String.to_atom("#{service}_heartbeat")
end
