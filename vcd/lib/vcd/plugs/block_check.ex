defmodule VCD.Plugs.BlockCheck do
  import Plug.Conn

  def init(opts), do: opts

  # k8s probes must always reach health endpoints regardless of blocklist
  @health_paths ["/healthz/live", "/healthz/ready"]

  def call(%{request_path: path} = conn, _opts) when path in @health_paths, do: conn

  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if VCD.BlockList.blocked?(ip) do
      # Blocked IP still attempting access — counts as repeat attack for L2 escalation
      VCD.Validator.record_repeat_attempt(ip)
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    else
      conn
    end
  end
end
