defmodule VCD.Plugs.BlockCheck do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if VCD.BlockList.blocked?(ip) do
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    else
      conn
    end
  end
end
