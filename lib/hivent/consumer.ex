defmodule Hivent.Consumer do

  alias Experimental.GenStage
  alias Hivent.Config
  alias Hivent.Consumer.Heartbeat
  alias Hivent.Consumer.Stages.{Producer}

  @default_interval 250

  use GenStage

  def start(name, event_names, interval \\ @default_interval) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Producer, [name, event_names, Config.get(:hivent, :partition_count)]),
      worker(Heartbeat, [name]),
      worker(__MODULE__, [interval])
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def start_link(interval) do
    GenStage.start_link(__MODULE__, interval)
  end

  def init(state) do
    {:producer_consumer, state}
  end

  def handle_events(events, _from, interval) do
    Process.sleep(interval)
    {:noreply, events, interval}
  end

end
