defmodule Hivent.Consumer.Stages.Producer do
  @moduledoc false

  import Exredis.Script
  alias Hivent.{Event, Config}
  alias Hivent.Consumer.Heartbeat

  use GenStage

  @default_interval 1_000

  defredis_script :rebalance_queues, file_path: "lib/hivent/consumer/lua/rebalance_queues.lua"

  def start_link(consumer_name, events \\ [], partition_count \\ 1, interval \\ @default_interval) do
    config = %{
      events: events,
      consumer_name: consumer_name,
      service: Config.get(:hivent, :client_id),
      partition_count: partition_count,
      interval: interval,
      demand: 0
    }

    {:ok, _} = Heartbeat.start_link(consumer_name)

    GenStage.start_link(__MODULE__, config)
  end

  def init(%{events: events, service: service, partition_count: partition_count} = state) do
    Enum.each(events, fn (event) ->
      redis |> Exredis.Api.sadd(event, service)
    end)

    redis |> Exredis.Api.set("#{service}:partition_count", partition_count)

    {:producer, state}
  end

  def handle_demand(incoming_demand, %{demand: 0} = state) do
    new_demand = state.demand + incoming_demand

    Process.send(self(), :get_events, [])

    {:noreply, [], %{state | demand: new_demand}}
  end

  def handle_demand(incoming_demand, state) do
    new_demand = state.demand + incoming_demand

    {:noreply, [], %{state | demand: new_demand}}
  end

  def handle_info(:get_events, state) do
    events = state
    |> queues
    |> Stream.flat_map(&take_items(state.demand, &1))
    |> Stream.map(&parse_item/1)
    |> Stream.reject(&is_nil/1)
    |> Enum.take(state.demand)

    num_events_received = Enum.count(events)
    new_demand = state.demand - num_events_received

    cond do
      new_demand == 0 -> :ok
      num_events_received == 0 ->
        Process.send_after(self(), :get_events, state.interval)
      true ->
        Process.send(self(), :get_events, [])
    end

    {:noreply, events, %{state | demand: new_demand}}
  end

  defp redis do
    Process.whereis(:redis)
  end

  defp queues(%{service: service, consumer_name: consumer_name, interval: interval}) do
    case rebalance_queues(redis, [], [service, consumer_name, interval]) do
      :undefined -> []
      result -> result
    end
  end

  defp take_items(amount, queue) do
    items = redis
    |> Exredis.Api.lrange(queue, -amount, -1)
    |> Enum.map(fn (item) -> {queue, item} end)

    redis |> Exredis.Api.ltrim(queue, 0, queue_length(queue) - amount)

    items
  end

  defp queue_length(queue) do
    redis |> Exredis.Api.llen(queue) |> String.to_integer()
  end

  defp parse_item({queue, item}) do
    case Poison.decode(item, as: %Event{}) do
      {:error, _} ->
        redis |> Exredis.Api.lpush("#{queue}:dead_letter", item)
        nil
      {:ok, parsed} -> {parsed, queue}
    end
  end

end
