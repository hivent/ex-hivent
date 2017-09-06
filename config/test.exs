use Mix.Config

config :hivent,
  endpoint: {:system, "HIVENT_URL"},
  max_reconnect_tries: 3,
  reconnect_backoff_time: 10,
  client_id: "hivent_test"

config :hivent, :channel_client, Hivent.Support.ChannelClient

config :hivent, :server, %{
  host: "localhost",
  port: 4000,
  secure: false,
  api_key: "secret_key"
}

config :logger,
  level: :error

config :test_server, TestServerWeb.Endpoint,
  url: [host: "localhost"],
  http: [port: 9001],
  server: true,
  secret_key_base: "uMH56O33CL1bQZmaYs7PgnUtF2AFffEXm9bg05rf5vcU1F2jRELBodu+l1b1gv0M",
  render_errors: [view: TestServerWeb.ErrorView, accepts: ~w(json)],
  pubsub: [name: TestServer.PubSub,
           adapter: Phoenix.PubSub.PG2]
