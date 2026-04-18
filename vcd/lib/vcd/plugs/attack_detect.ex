defmodule VCD.Plugs.AttackDetect do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)

    inputs = Map.values(conn.params)

    case VCD.Validator.validate(inputs) do
      {:attack, pattern} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()
        VCD.BlockList.block(ip)

        VCD.ForensicsWriter.write_and_die(%{
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
