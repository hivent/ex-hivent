# Hivent

## Quickstart
```elixir
defmodule TestConsumer do
  alias Experimental.GenStage
  use GenStage

  def start_link do
    {:ok, producer} = Hivent.Consumer.Stages.Producer.start_link("test", ["test:event"])
    {:ok, consumer } = GenStage.start_link(__MODULE__, [])
    GenStage.sync_subscribe(consumer, to: producer)
  end

  def init(state) do
    {:consumer, state}
  end

  def handle_events(events, _from, state) do
    for event <- events do
      IO.inspect {self(), event}
    end

    Process.sleep(250)

    # As a consumer we never emit events
    {:noreply, [], state}
  end
end
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `hivent` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:hivent, "~> 0.1.0"}]
    end
    ```

  2. Ensure `hivent` is started before your application:

    ```elixir
    def application do
      [applications: [:hivent]]
    end
    ```

