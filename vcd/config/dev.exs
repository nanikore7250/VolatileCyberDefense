import Config

config :vcd, debug: true

config :vcd, :shutdown,
  mode: :graceful,
  timeout_ms: 2_000
