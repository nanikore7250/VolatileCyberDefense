defmodule Vcd.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      VCD.BlockList,
      {Plug.Cowboy, scheme: :http, plug: VCD.Router, options: [port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: Vcd.Supervisor]
    Logger.info("[VCD] Starting Volatile Cyber Defense on port 4000")
    Supervisor.start_link(children, opts)
  end
end
