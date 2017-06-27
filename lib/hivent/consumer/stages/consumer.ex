defmodule Hivent.Consumer.Stages.Consumer do
  @moduledoc """
  Hivent Consumer Stage. It subscribes to the Producer Stage and broadcasts
  consumed events to the internal Hivent pubsub channel
  """

  use GenStage

  alias Phoenix.PubSub

  def start_link(producer, name) do
    GenStage.start_link(__MODULE__, {producer, self()}, name: name)
  end

  def init({producer, owner}) do
    {:consumer, owner, subscribe_to: [producer]}
  end

  def handle_events(events, _from, owner) do
    for {event, queue} <- events do
      PubSub.broadcast(:hivent_pubsub, event.meta.name, {event, queue})
    end

    {:noreply, [], owner}
  end
end
