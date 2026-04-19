defmodule Proxy.Plugs.AttackDetect do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    {raw_body, body_params} = read_and_parse_body(conn)

    # Store raw body in assigns so Router.forward can reuse it
    conn = assign(conn, :raw_body, raw_body)

    inputs =
      Map.values(conn.params) ++
        Map.values(body_params) ++
        [conn.request_path]

    case Proxy.Validator.validate(inputs) do
      {:attack, pattern} ->
        ip = conn.remote_ip |> :inet.ntoa() |> to_string()

        require Logger
        Logger.warning("[AttackDetect] Attack from #{ip} | path=#{conn.request_path} | pattern=#{pattern}")

        # Crash this request process — Flask never receives the request
        raise "attack detected: #{pattern}"

      :ok ->
        conn
    end
  end

  defp read_and_parse_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} when byte_size(body) > 0 ->
        params =
          case Jason.decode(body) do
            {:ok, map} when is_map(map) -> map
            _ -> %{"raw" => body}
          end

        {body, params}

      _ ->
        {"", %{}}
    end
  end
end
