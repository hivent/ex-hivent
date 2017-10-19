# Hivent

The official Elixir client for [Hivent](https://hivent.io).

* [Read the docs](https://hexdocs.pm/hivent/api-reference.html)

## Installation

  1. Add `hivent` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:hivent, "~> 3.0.0"}]
  end
  ```

  2. Ensure `hivent` is started before your application:

  ```elixir
  def application do
    [applications: [:hivent]]
  end
  ```

## Configuration

In your `<env>.exs` file:

```elixir
config :hivent,
  max_reconnect_tries: 3,
  reconnect_backoff_time: 10,
  client_id: "hivent_test",
  server: %{
    host: "<instance_id>.hivent.io",
    port: 443,
    secure: true,
    api_key: "<Secret API Key>"
  }
```

Here's what every option does:
* `max_reconnect_tries`: The maximum number of reconnections the client will attempt after losing a connection. Once all the tries are up, the server is allowed to crash.
* `reconnect_backoff_time`: The exponential amount of time to wait before reconnecting.
* `client_id`: Only useful if producing events. Every event's metadata carries a `producer` key with this config as its value.
* `server`:
  * `host`: The host for your Hivent instance
  * `port`: The port for your Hivent instance
  * `secure`: Use a secure (`wss`) or insecure (`ws`) socket connection
  * `api_key`: Your API key for the Hivent instance.

## Emitting events
```elixir
Hivent.emit("some:event", %{foo: "bar"}, %{version: 1})
```

The `Hivent.Emitter` process is automatically put into a supervision tree, so it will start automatically upon crashing.

## Consuming events
```elixir
  defmodule MyApp.Consumer do
    @topic "some:event"
    @name "test_consumer"
    @partition_count 2

    use Hivent.Consumer

    def process(%Hivent.Event{} = event) do
      if do_something(event) do
        :ok
      else
        # Puts the event in the dead letter queue
        {:error, "failed to process"}
      end
    end
  end

  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do
      import Supervisor.Spec
      children = [
        worker(MyApp.Consumer, [])
      ]

      opts = [
        strategy: :one_for_one,
        name: MyApp.Supervisor,
        max_restarts: 50
      ]
      Supervisor.start_link(children, opts)
    end
  end
```

Your consumers implementing the `Hivent.Consumer` behaviour must be supervised manually, if you wish to do so. If you fail
to supervise them, they will not be restarted automatically after crashing
