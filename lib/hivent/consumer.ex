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

  alias Hivent.Config
  alias Hivent.Consumer
  alias Hivent.Consumer.Stages.Producer, as: ProducerStage
  alias Hivent.Consumer.Stages.Consumer, as: ConsumerStage
  alias Phoenix.PubSub

  @callback process(%Hivent.Event{}) :: :ok | {:error, term}

  defmacro __using__(_options) do
    quote do
      @behaviour Consumer

      def start_link(otp_opts \\ []) do
        GenServer.start_link(__MODULE__, %{
          topic: @topic,
          name: @name,
          partition_count: @partition_count
        }, otp_opts)
      end

      def init(%{topic: topic, name: name, partition_count: partition_count}) do
        {:ok, producer} = case Process.whereis(Consumer.producer_name(name)) do
          nil -> ProducerStage.start_link(name, Consumer.producer_name(name), partition_count)
          pid -> {:ok, pid}
        end

        case Process.whereis(Consumer.consumer_name(name)) do
          nil -> ConsumerStage.start_link(producer, Consumer.consumer_name(name))
          pid -> {:ok, pid}
        end

        Consumer.register(topic)

        :ok = PubSub.subscribe(:hivent_pubsub, topic)

        {:ok, %{topic: topic}}
      end

      def handle_info({event, queue}, state) do
        case process(event) do
          {:error, _reason} -> Consumer.hospitalize(event, queue)
          :ok -> nil
        end

        {:noreply, state}
      end

      def terminate(_reason, %{topic: topic}) do
        PubSub.unsubscribe(:hivent_pubsub, topic)
      end

      def process(_event), do: :ok
      defoverridable process: 1
    end
  end

  def register(topic) do
    redis() |> Exredis.Api.sadd(topic, service())
  end

  def hospitalize(event, queue) do
    Hivent.Util.quarantine(redis(), event, queue)
  end

  def producer_name(name), do: String.to_atom("#{service()}_#{name}_producer")

  def consumer_name(name), do: String.to_atom("#{service()}_#{name}_consumer")

  defp redis, do: Process.whereis(Hivent.Redis)

  defp service, do: Config.get(:hivent, :client_id)
end
