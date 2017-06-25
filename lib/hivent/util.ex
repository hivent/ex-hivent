defmodule Hivent.Util do

  alias Hivent.Event

  def quarantine(redis, item, queue) when is_binary(item) do
    redis |> Exredis.Api.lpush("#{queue}:dead_letter", item)

    {:ok}
  end
  def quarantine(redis, %Event{} = item, queue) do
    quarantine(redis, Poison.encode!(item), queue)
  end

end
