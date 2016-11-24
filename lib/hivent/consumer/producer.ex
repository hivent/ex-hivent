defmodule Hivent.Consumer.Producer do
  @moduledoc false

  import Exredis.Script
  alias Experimental.GenStage
  alias Hivent.Event

  use GenStage

  @default_interval 1_000

  defredis_script :rebalance_queues, file_path: "lib/hivent/consumer/lua/rebalance_queues.lua"

  def start_link(consumer, events \\ [], partition_count \\ 1, interval \\ @default_interval, initial \\ []) do
    config = %{
      events: events,
      consumer: consumer,
      service: Hivent.Config.get(:hivent, :client_id),
      partition_count: partition_count,
      interval: interval
    }

    GenStage.start_link(__MODULE__, {config, initial}, name: __MODULE__)
  end

  def init({%{events: events, service: service, partition_count: partition_count}, _initial} = state) do
    Enum.each(events, fn (_event) ->
      redis |> Exredis.Api.sadd("my:event", service)
    end)

    redis |> Exredis.Api.set("#{service}:partition_count", partition_count)

    {:producer, state}
  end

  def handle_demand(demand, {config, events} = state) do
    new_events = config
    |> queues
    |> Stream.flat_map(&take_items!(demand, &1))
    |> Stream.map(&parse_item!(&1))
    |> Stream.reject(&is_nil(&1))
    |> Enum.take(demand)

    {:noreply, new_events, Tuple.insert_at(state, 1, events ++ new_events)}
  end

  defp redis do
    Process.whereis(:redis)
  end

  defp queues(%{service: service, consumer: consumer, interval: interval}) do
    redis |> rebalance_queues([], [service, consumer, interval])
  end

  defp take_items!(amount, queue) do
    items = redis |> Exredis.Api.lrange(queue, -amount, -1)

    redis |> Exredis.Api.ltrim(queue, 0, queue_length(queue) - amount)

    items |> Enum.map(fn (item) -> {queue, item} end)
  end

  defp queue_length(queue) do
    redis |> Exredis.Api.llen(queue) |> String.to_integer()
  end

  defp parse_item!({queue, item}) do
    case Poison.decode(item, as: %Event{}) do
      {:error, _} ->
        redis |> Exredis.Api.lpush("#{queue}:dead_letter", item)
        nil
      {:ok, parsed} -> parsed
    end
  end

end
