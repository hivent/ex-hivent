defmodule Hivent.Consumer do
  @moduledoc """
  The Hivent Consumer. Use module options to configure your consumer:
    - @topic The topic you want to consume, ie. "some:event"
    - @name The name of your consumer
    - @partition_count The number of partitions data will be partitioned in
  Implement the Consumer behaviour by overriding process/1. The argument is the
  %Hivent.Event{} consumed. Use return values to inform Hivent if processing the
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

      alias Hivent.Config

      require Logger

      def start_link(otp_opts \\ []) do
        GenServer.start_link(__MODULE__, %{
          topic: @topic,
          name: @name,
          partition_count: @partition_count
        }, otp_opts)
      end

      def init(%{topic: topic, name: name, partition_count: partition_count}) do
        {:ok, pid} = @channel_client.start_link(name: String.to_atom("consumer_socket_#{name}"))

        server_config = server_config()

        {:ok, socket} = @channel_client.connect(pid,
          host: server_config[:host],
          path: server_config[:path],
          port: server_config[:port],
          params: name,
          secure: server_config[:secure]
        )
        channel = @channel_client.channel(socket, name, %{partition_count: @partition_count})

        {:ok, _} = @channel_client.join(channel)

        Logger.info "Initialized Hivent.Consumer #{name}"

        {:ok, %{socket: socket, channel: channel, topic: topic}}
      end

      def handle_info({"event:received", %{event: event, queue: queue}}, %{channel: channel} = state) do
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

      def terminate(_reason, %{channel: channel}) do
        @channel_client.leave(channel)
      end

      def process(_event), do: :ok
      defoverridable process: 1

      defp server_config, do: Config.get(:hivent, :hivent_server)

      defp quarantine(channel, {event, queue}) do
        @channel_client.push(channel, "event:quarantine", {event, queue})
      end
    end
  end
end
