import Config

config :vcd, debug: false

config :vcd, :shutdown,
  mode: :graceful,
  timeout_ms: 5_000
