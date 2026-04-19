defmodule Proxy.Router do
  @moduledoc """
  Simple pass-through reverse proxy.
  Forwards all incoming requests to the upstream Flask app unchanged.
  """

  use Plug.Router

  @upstream Application.compile_env(:proxy, :upstream, "http://localhost:5000")

  plug Proxy.Plugs.AttackDetect
  plug :match
  plug :dispatch

  match _ do
    forward(conn)
  end

  defp forward(conn) do
    url = @upstream <> conn.request_path <> build_query(conn)

    headers =
      conn.req_headers
      |> Enum.reject(fn {k, _} -> k in ["host", "transfer-encoding"] end)

    body = conn.assigns[:raw_body] || read_request_body(conn)

    result =
      Req.new(url: url, method: conn.method |> String.downcase() |> String.to_atom())
      |> Req.merge(headers: headers, body: body, redirect: false, retry: false, decode_body: false)
      |> Req.request()

    case result do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        conn
        |> put_resp_headers(resp_headers)
        |> send_resp(status, resp_body)

      {:error, reason} ->
        conn
        |> send_resp(502, "Bad Gateway: #{inspect(reason)}")
    end
  end

  defp build_query(conn) do
    case conn.query_string do
      "" -> ""
      qs -> "?" <> qs
    end
  end

  defp read_request_body(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} -> body
      {:more, body, _conn} -> body
      _ -> ""
    end
  end

  @skip_headers ~w[transfer-encoding content-encoding connection]

  # Req 0.5+ returns headers as %{name => [value, ...]}
  defp put_resp_headers(conn, headers) when is_map(headers) do
    Enum.reduce(headers, conn, fn {k, vs}, acc ->
      if k in @skip_headers do
        acc
      else
        Plug.Conn.put_resp_header(acc, k, List.first(vs, ""))
      end
    end)
  end

  defp put_resp_headers(conn, headers) when is_list(headers) do
    Enum.reduce(headers, conn, fn {k, v}, acc ->
      if k in @skip_headers do
        acc
      else
        Plug.Conn.put_resp_header(acc, k, v)
      end
    end)
  end
end
