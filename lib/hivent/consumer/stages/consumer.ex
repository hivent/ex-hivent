defmodule Hivent.Consumer.Stages.Consumer do
  use GenStage

  alias Phoenix.PubSub
  alias Hivent.Config

  def start_link(producer) do
    GenStage.start_link(__MODULE__, {producer, self()}, name: consumer_name())
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

  defp consumer_name do
    String.to_atom("#{Config.get(:hivent, :client_id)}_consumer")
  end
end
