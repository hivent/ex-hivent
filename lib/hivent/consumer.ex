defmodule Hivent.Consumer do
  @moduledoc """
  The Hivent Consumer. Use module options to configure your consumer:
    - @service The name of your service, ie: "order_service"
    - @topic The topic you want to consume, ie. "some:event"
    - @partition_count The number of partitions data will be partitioned in

  Implement the Consumer behaviour by overriding `process/1`. The argument is the
  `%Hivent.Event{}` consumed. Use return values to inform Hivent if processing the
  event succeded or failed:
    - :ok
    - {:error, "Failed to process XYZ"}

  Events that have failed to be processed will be put in a dedicated dead letter
  queue.
  """

  use GenServer

  alias Hivent.{Config, Event}
  alias Hivent.Consumer

  @type event :: %Event{}

  @callback process(event) :: :ok | {:error, term}

  defmacro __using__(_options) do
    quote do
      @behaviour Consumer

      @channel_client Application.get_env(:hivent, :channel_client, Hivent.Phoenix.ChannelClient)
      @reconnect_backoff Application.get_env(:hivent, :reconnect_backoff_time, 1000)
      @max_reconnect_tries Application.get_env(:hivent, :max_reconnect_tries, 3)

      alias Hivent.Config

      require Logger

      # Client API
      def start_link(otp_opts \\ []) do
        GenServer.start_link(__MODULE__, %{
          service: @service,
          topic: @topic,
          partition_count: @partition_count,
          name: nil,
          reconnect_timer: 0
        }, otp_opts)
      end

      # Server callbacks
      def init(%{service: service, topic: topic, partition_count: partition_count} = config) do
        config = %{config | name: name()}
        name = config[:name]

        {:ok, pid} = @channel_client.start_link(name: String.to_atom("consumer_socket_#{name}"))

        GenServer.cast(self(), :connect)

        Logger.info "Initialized Hivent.Consumer #{name}"

        {:ok, %{socket: nil, channel: nil, config: config, pid: pid, reconnect_tries: 0}}
      end

      def handle_cast(:connect, state), do: try_connect(state)

      def handle_info(:connect, state), do: try_connect(state)
      def handle_info(:close, state), do: try_connect(state)
      def handle_info({"event:received", %{"event" => event, "queue" => queue}}, %{channel: channel} = state) do
        event = Poison.encode!(event) |> Poison.decode!(as: %Event{})

        case process(event) do
          {:error, _reason} ->
            Logger.info "Error processing event #{event.meta.uuid}"
            quarantine(channel, {event, queue})
          :ok ->
            Logger.info "Finished processing event #{event.meta.uuid}"
            nil
        end

        {:noreply, state}
      end
      def handle_info(_, state), do: {:noreply, state}

      def terminate(_reason, %{channel: channel}) when not is_nil(channel) do
        @channel_client.leave(channel)
      end
      def terminate(_reason, _state), do: :ok

      def process(_event), do: :ok
      defoverridable process: 1

      defp name do
        {:ok, hostname} = :inet.gethostname

        "#{hostname}:#{inspect self()}"
      end

      defp quarantine(channel, {event, queue}) do
        @channel_client.push(channel, "event:quarantine", %{event: event, queue: queue})
      end

      defp try_connect(%{config: config} = state) do
        case do_connect(state) do
          {:ok, socket} ->
            channel = @channel_client.channel(socket, "event:#{config[:topic]}", %{partition_count: config[:partition_count]})

            {:ok, _} = @channel_client.join(channel)

            {:noreply, %{state | socket: socket, channel: channel}}
          {:error, _reason} ->
            new_reconnect_timer = config[:reconnect_timer] + @reconnect_backoff

            cond do
              state[:reconnect_tries] <= @max_reconnect_tries ->
                Logger.info("Trying to reconnect to socket, #{@max_reconnect_tries - state[:reconnect_tries] + 1} tries left")
                Process.send_after(self(), :close, new_reconnect_timer)

                {:noreply, %{state |
                  channel: nil,
                  config: %{config |
                    reconnect_timer: new_reconnect_timer,
                  },
                  reconnect_tries: state[:reconnect_tries] + 1
                }}
              true ->
                {:error, "could not connect to socket"}
            end
        end
      end

      defp do_connect(%{socket: nil, config: config, pid: pid}) do
        server_config = Config.get(:hivent, :server)

        @channel_client.connect(pid,
          host: server_config[:host],
          path: "/consumer/websocket",
          port: server_config[:port],
          params: %{
            service: config[:service],
            name:    config[:name],
            api_key: server_config[:api_key]
          },
          secure: server_config[:secure]
        )
      end
      defp do_connect(%{socket: socket}) do
        case @channel_client.reconnect(socket) do
          :ok -> {:ok, socket}
          result -> result
        end
      end
    end
  end
end
