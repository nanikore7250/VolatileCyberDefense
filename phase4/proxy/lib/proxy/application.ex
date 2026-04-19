defmodule Proxy.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:proxy, :port, 4000)

    children = [
      {Plug.Cowboy, scheme: :http, plug: Proxy.Router, options: [port: port]}
    ]

    opts = [strategy: :one_for_one, name: Proxy.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        upstream = Application.get_env(:proxy, :upstream, "http://localhost:5000")
        IO.puts("[Proxy] Listening on port #{port}, forwarding to #{upstream}")
        {:ok, pid}

      err ->
        err
    end
  end
end
