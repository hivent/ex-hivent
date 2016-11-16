use Mix.Config

config :hivent,
  endpoint: {:system, "HIVENT_URL"},

  partition_count: 1,

  client_id: "hivent_test"