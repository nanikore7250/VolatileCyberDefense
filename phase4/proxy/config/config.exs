import Config

config :proxy,
  port: String.to_integer(System.get_env("PROXY_PORT", "4000")),
  upstream: System.get_env("UPSTREAM_URL", "http://localhost:5000")
