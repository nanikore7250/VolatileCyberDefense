defmodule VCD.Plugs.AttackDetect do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    case VCD.Validator.validate(Map.values(conn.params)) do
      {:attack, pattern} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        VCD.BlockList.block(ip)

        VCD.Validator.handle_detection(%{
          ip: ip,
          method: conn.method,
          path: conn.request_path,
          params: conn.params,
          pattern: inspect(pattern)
        })

      :ok ->
        conn
    end
  end
end
